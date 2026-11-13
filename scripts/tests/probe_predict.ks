// probe_predict.ks -- flight probe for the deorbit planner (milestone 2, plan Task 2).
//
// Settles four conventions that cannot be found on the pad:
//   1. NODE_NORMAL_SIGN / NODE_RADIAL_SIGN: which way kOS counts the node's normal and radial components,
//      and whether BURNVECTOR is in the same frame as POSITIONAT / VELOCITYAT.
//   2. POSITIONAT_INCLUDES_NODES: does the prediction include planned maneuver nodes?
//   3. PREDICT_AXES_INERTIAL: are POSITIONAT results in axes that stay fixed while the Moon turns?
//   4. CAN_MAKE_NODES: what Career():CANMAKENODES says.
// Run in lunar orbit with engines off and NO maneuver nodes. It waits 900 s of game time (warp is used).
//   RUNPATH("0:/lm/tests/probe_predict.ks").
// Everything is logged to 0:/lm/probe_predict.log. The probe adds three test nodes one at a time and
// removes each straight away; it never touches nodes it did not make (it stops if any exist).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_plan.ks").

LOCAL log_path IS "0:/lm/probe_predict.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }
FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

IF SHIP:BODY:NAME <> BODY_NAME {
  say("probe_predict: run this in the " + BODY_NAME + "'s sphere of influence.").
} ELSE IF ALLNODES:LENGTH > 0 {
  say("probe_predict: the ship already has maneuver nodes. Remove them first; the probe will not touch them.").
} ELSE {
  say("probe_predict " + ROUND(TIME:SECONDS) + " UT, ship " + SHIP:NAME).

  // ---- 1 + 2: node axes and the effect of a node on the prediction -------------------------------
  LOCAL t_n IS TIME:SECONDS + 600.
  LOCAL r_vec IS POSITIONAT(SHIP, t_n) - SHIP:BODY:POSITION.
  LOCAL v_vec IS VELOCITYAT(SHIP, t_n):ORBIT.
  LOCAL pro_vec IS v_vec:NORMALIZED.
  LOCAL nrm_vec IS VCRS(r_vec, v_vec):NORMALIZED.
  LOCAL rad_vec IS VCRS(pro_vec, nrm_vec):NORMALIZED.
  say("node time t_n=" + ROUND(t_n) + " |r|=" + ROUND(r_vec:MAG) + " |v|=" + ROUND(v_vec:MAG, 2)).

  // (radial, normal, prograde) = 5 m/s along one component at a time.
  LOCAL tests IS LIST(LIST("radial", 5, 0, 0), LIST("normal", 0, 5, 0), LIST("prograde", 0, 0, 5)).
  LOCAL normal_sign IS 0.
  LOCAL radial_sign IS 0.
  LOCAL burn_err IS 0.
  FOR tst IN tests {
    LOCAL test_node IS NODE(t_n, tst[1], tst[2], tst[3]).
    ADD test_node.
    LOCAL bv IS test_node:BURNVECTOR.
    LOCAL d_rad IS VDOT(bv, rad_vec) / 5.
    LOCAL d_nrm IS VDOT(bv, nrm_vec) / 5.
    LOCAL d_pro IS VDOT(bv, pro_vec) / 5.
    say(tst[0] + " test: BURNVECTOR=" + bv + " |bv|=" + ROUND(bv:MAG, 4) + " dots with radial/normal/prograde axes (x1/5): "
        + ROUND(d_rad, 4) + " / " + ROUND(d_nrm, 4) + " / " + ROUND(d_pro, 4)).
    IF tst[0] = "radial" {
      SET radial_sign TO CHOOSE 1 IF d_rad >= 0 ELSE -1.
      SET burn_err TO MAX(burn_err, (bv - rad_vec * 5 * radial_sign):MAG).
    } ELSE IF tst[0] = "normal" {
      SET normal_sign TO CHOOSE 1 IF d_nrm >= 0 ELSE -1.
      SET burn_err TO MAX(burn_err, (bv - nrm_vec * 5 * normal_sign):MAG).
    } ELSE {
      SET burn_err TO MAX(burn_err, (bv - pro_vec * 5):MAG).
    }
    IF tst[0] = "prograde" {
      // Does a planned node change the prediction? Compare the speed just after and just before it.
      LOCAL jump IS VELOCITYAT(SHIP, t_n + 1):ORBIT:MAG - VELOCITYAT(SHIP, t_n - 1):ORBIT:MAG.
      say("prediction speed jump across the 5 m/s node: " + ROUND(jump, 3) + " m/s (about 5 if included, about 0 if not)").
      say("POSITIONAT_INCLUDES_NODES = " + (CHOOSE "TRUE" IF jump > 2.5 ELSE "FALSE")).
    }
    REMOVE test_node.
  }
  say("NODE_NORMAL_SIGN = " + normal_sign).
  say("NODE_RADIAL_SIGN = " + radial_sign).
  say("largest |BURNVECTOR - expected| across the three tests = " + ROUND(burn_err, 5) + " m/s (below 0.01: BURNVECTOR is in the POSITIONAT frame)").

  // ---- 4: career limits ------------------------------------------------------------------------
  say("CAN_MAKE_NODES = " + CAREER():CANMAKENODES).

  // ---- 3: prediction frame vs the Moon's spin -----------------------------------------------------
  // Predict the position 900 s ahead, wait, measure it. The prediction is in the axes of NOW; the later
  // measurement is in the axes of THEN. Rotating the prediction by the Moon's spin over 900 s (forward,
  // none or backward) and seeing which gives the smallest miss shows how the two sets of axes relate.
  LOCAL wait_s IS 900.
  LOCAL wm_vec IS moon_spin().
  LOCAL t0 IS TIME:SECONDS.
  LOCAL pred_vec IS POSITIONAT(SHIP, t0 + wait_s) - SHIP:BODY:POSITION.
  LOCAL fix_vec0 IS land_vector(0, 0, 0).         // a Moon-fixed point (lat 0, lng 0) in the raw axes now
  say("waiting " + wait_s + " s (warping) ...").
  WARPTO(t0 + wait_s).
  WAIT UNTIL TIME:SECONDS >= t0 + wait_s.
  LOCAL act_vec IS -SHIP:BODY:POSITION.
  // Two separate questions, because the raw axes may or may not turn with the Moon at this altitude:
  //  (a) do the raw axes turn with the Moon? A point fixed to the Moon (lat 0, lng 0) keeps the same
  //      vector in the raw axes if they do (drift about 0), and drifts by the spin angle if they do not.
  //  (b) is the prediction made in axes frozen at the time of the call? Then the later measurement,
  //      mapped back into the axes of t0, must equal the prediction.
  // The planner needs TRUE whenever the prediction is frozen at call time (the site then moves by the
  // spin in the prediction's axes), whichever regime the raw axes are in. FALSE only if the prediction
  // itself turns with the Moon's axes.
  LOCAL spin_deg IS wm_vec:MAG * wait_s * 180 / CONSTANT:PI.
  LOCAL drift_deg IS VANG(fix_vec0, land_vector(0, 0, 0)).
  LOCAL axes_rotate IS drift_deg < spin_deg / 2.
  // Measured vector expressed in the axes of t0: if the axes turn with the Moon, they have turned by the
  // spin since t0, so the vector is turned the same way back into the t0 axes.
  LOCAL act_in_t0 IS act_vec.
  IF axes_rotate { SET act_in_t0 TO plan_spin_rotate(act_vec, wm_vec, wait_s). }
  LOCAL res_frozen IS (pred_vec - act_in_t0):MAG.        // prediction frozen at call time
  LOCAL res_live IS (pred_vec - act_vec):MAG.            // prediction in the axes of the later time
  say("altitude " + ROUND(SHIP:ALTITUDE) + " m. Moon rotation period " + ROUND(SHIP:BODY:ROTATIONPERIOD) + " s; spin over " + wait_s
      + " s = " + ROUND(spin_deg, 4) + " deg = " + ROUND(wm_vec:MAG * wait_s * pred_vec:MAG) + " m at this radius.").
  say("a) a Moon-fixed point drifted " + ROUND(drift_deg, 4) + " deg in the raw axes: raw axes " + (CHOOSE "TURN WITH the Moon" IF axes_rotate ELSE "are INERTIAL")).
  say("b) prediction miss (m): treated as frozen at call time " + ROUND(res_frozen, 1) + ", treated as live " + ROUND(res_live, 1)).
  IF res_frozen < res_live {
    say("PREDICT_AXES_INERTIAL = TRUE").
  } ELSE IF axes_rotate AND res_live < res_frozen {
    say("PREDICT_AXES_INERTIAL = FALSE").
  } ELSE {
    say("PREDICT_AXES_INERTIAL = UNEXPECTED (inertial raw axes yet the live reading fits better: stop and investigate)").
  }
  say("probe_predict done. Results are in " + log_path).
}
