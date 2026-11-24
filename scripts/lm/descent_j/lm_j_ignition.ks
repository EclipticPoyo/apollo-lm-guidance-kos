// lm_j_ignition.ks -- P63 ignition: the ignition algorithm IGNALG (plan Task 6) and the BURNBABY countdown
// sequence (plan Task 7).
//
// Ported from Luminary 099:
//   IGNALG / DDUMCALC / DDUMGOOD  (THE_LUNAR_LANDING.agc 77-200)  -> j_ign_ddum, j_ign_trim_dv, j_ign_out_of_plane, j_ign_solve
//   EXGSUB (LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 720-729)         -> j_ign_trim_dv
//   BURNBABY (BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc)        -> seq_* (Task 7)
// Everything here is pure maths: the orbit prediction is passed in as a function, so it is tested on the pad.
//
// What IGNALG does. The braking guidance only works if the burn starts at the right moment on the descent orbit.
// IGNALG finds that moment, TIG (time of ignition). It takes a guess, asks "where will the ship be then if it coasts?",
// runs the guidance on that state and measures how far the state is from the pad-loaded ignition conditions
// (J_RIGNX, J_RIGNZ, J_VIGN) with the gain constants J_KIGNX, J_KIGNY, J_KIGNV. That distance, divided by the speed along the
// track, is a time correction DDUM. It moves the guess by DDUM and repeats until |DDUM| is under 0.08 s.
//
// Why TIG is about 26 s before the planner's PDI time. The state IGNALG tests is where the ship WOULD be at the moment the
// throttle goes up (J_ZOOMTIME, 26 s after ignition), with the speed the zoom would have added (a trim, below). So
// the converged time is the zoom time, and TIG = that time - J_ZOOMTIME (DDUMGOOD, lines 187-192). The planner
// (milestone 2) places the pad-load conditions at its PDI time, so TIG comes out about 26 s before it.
//
// Simplifications: the orbit is predicted by kOS (POSITIONAT, VELOCITYAT) instead of Luminary's own integrator; at most
// 10 passes (Luminary allows 40 and raises alarm 1412 on running out).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_guidance.ks").

// First guess of the time-to-go for the three guidance passes at each IGNALG iteration. The cubic settles from any
// reasonable start; the Apollo 11 value at ignition is about 553 s.
GLOBAL J_IGN_TGO_SEED IS 550.
GLOBAL J_IGN_MAX_PASSES IS 10.          // most IGNALG iterations before giving up
GLOBAL J_IGN_MAX_MOVE_S IS 600.         // most the answer may be from the guess before it is rejected, s

// j_ign_ddum: the time correction DDUM, seconds. rgu_vec and vgu_vec are the position and velocity relative to the landing
// site in guidance axes (up, crossrange, downrange). The scale factors of the AGC cancel in SI, giving
//   DDUM = [(J_RIGNZ - RGz) + J_KIGNY RGy^2 + J_KIGNX (RGx - J_RIGNX) + J_KIGNV (|VG| - J_VIGN)] / (VGz - J_KIGNX VGx).
// Zero at the pad-load conditions. Positive means "the ship is short of the nominal point: wait longer".
FUNCTION j_ign_ddum {
  PARAMETER rgu_vec, vgu_vec.
  LOCAL numer IS (J_RIGNZ - rgu_vec:Z) + J_KIGNY * rgu_vec:Y ^ 2 + J_KIGNX * (rgu_vec:X - J_RIGNX) + J_KIGNV * (vgu_vec:MAG - J_VIGN).
  RETURN numer / (vgu_vec:Z - J_KIGNX * vgu_vec:X).
}

// j_ign_trim_dv: the velocity the zoom adds, as a raw-axes vector: J_ZOOMTIME x TRIMACCL along the thrust direction.
// afc_guid_vec is the thrust acceleration in guidance axes, cg the guidance matrix (rows = guidance axes in raw axes).
// A vector in guidance axes goes back to raw axes by adding up its components times the rows. No thrust, no correction.
FUNCTION j_ign_trim_dv {
  PARAMETER afc_guid_vec, cg.
  IF afc_guid_vec:MAG = 0 { RETURN V(0, 0, 0). }
  LOCAL dir_vec IS afc_guid_vec:NORMALIZED.
  RETURN cg_unapply(cg, dir_vec) * (J_ZOOMTIME * TRIMACCL).
}

// j_ign_out_of_plane: how far the landing site is out of the orbit plane at ignition, metres, signed (UNIT(V x R) . LAND,
// lines 192-197; + when the site is to the right/north of the track, - to the left/south, Luminary's convention).
// A zero V x R (no sideways velocity) gives 0.
FUNCTION j_ign_out_of_plane {
  PARAMETER r_vec, v_vec, land_vec.
  LOCAL normal_vec IS lm_cross(v_vec, r_vec).
  IF normal_vec:MAG = 0 { RETURN 0. }
  RETURN VDOT(normal_vec:NORMALIZED, land_vec).
}

// j_ign_fail: the result of j_ign_solve when it cannot give an ignition time.
FUNCTION j_ign_fail {
  PARAMETER why, iter_no.
  RETURN LEXICON("OK", FALSE, "WHY", why, "ITER", iter_no).
}

// j_ign_solve: find TIG. predict is a function taking a UT and returning LEXICON("R", position, "V", velocity), both
// from the body's centre in kOS raw axes, for the ship coasting to that time (the caller builds it from POSITIONAT and
// VELOCITYAT; pass it as name@). mass_kg and f_max_n are the lander's mass and full thrust (N), used for the thrust
// direction in the trim; mu the body's gravitational parameter; t_guess the first guess of the converged time (the
// planner's PDI time).
// Returns LEXICON("OK", ..., "TIG", UT, "T_CONV", UT, "ITER", passes, "OUTOFPLN", metres, "WHY", text).
// It fails (OK FALSE, WHY says why) when the state is not on a bound orbit, the time-to-go solver cannot settle, the
// answer moves more than J_IGN_MAX_MOVE_S from the guess, or J_IGN_MAX_PASSES passes do not converge.
FUNCTION j_ign_solve {
  PARAMETER predict, land_vec, wm_vec, mass_kg, f_max_n, mu, t_guess.
  LOCAL t_now IS t_guess.
  LOCAL iter_no IS 0.
  UNTIL iter_no >= J_IGN_MAX_PASSES {
    SET iter_no TO iter_no + 1.
    LOCAL pred_state IS predict:CALL(t_now).
    LOCAL r_vec IS pred_state["R"].
    LOCAL v_vec IS pred_state["V"].
    // Specific energy: negative on a bound orbit.
    IF 0.5 * v_vec:MAG ^ 2 - mu / r_vec:MAG >= 0 { RETURN j_ign_fail("the predicted state is not on a bound orbit", iter_no). }
    LOCAL state IS LEXICON("BODY_OK", TRUE, "R", r_vec, "V", v_vec, "MASS", mass_kg / 1000, "THRUST", f_max_n / 1000, "MU", mu).
    // Three guidance passes (?GUIDSUB): they settle the time-to-go and give the thrust direction for the trim.
    LOCAL tgo IS J_IGN_TGO_SEED.
    LOCAL gp IS LEXICON().
    FROM { LOCAL k IS 0. } UNTIL k >= 3 STEP { SET k TO k + 1. } DO {
      SET gp TO j_guid_pass(state, land_vec, wm_vec, tgo, 1, j_guid_targets_brake(), FALSE).
      IF NOT gp["OK"] { RETURN j_ign_fail("the time-to-go solver did not settle", iter_no). }
      SET tgo TO gp["TGO"].
    }
    LOCAL angterm_vec IS v_vec - lm_cross(wm_vec, r_vec).
    LOCAL cg IS guidance_cg(land_vec, r_vec, angterm_vec, -tgo / CG_LEAD_DIV * J_GAINBRAK).
    LOCAL trim_vec IS j_ign_trim_dv(gp["AFC"], cg).
    LOCAL rgu_vec IS rgu(cg, r_vec, land_vec).
    LOCAL vgu_vec IS vgu(cg, v_vec + trim_vec, r_vec, wm_vec).
    LOCAL ddum IS j_ign_ddum(rgu_vec, vgu_vec).
    IF ABS(ddum) < DDUMCRIT {
      // THRUST_DIR: the direction the nose must point for the burn (unit vector, raw axes), zero if there is no thrust.
      LOCAL thrust_dir IS V(0, 0, 0).
      IF trim_vec:MAG > 0 { SET thrust_dir TO trim_vec:NORMALIZED. }
      RETURN LEXICON("OK", TRUE, "WHY", "", "ITER", iter_no, "T_CONV", t_now, "TIG", t_now - J_ZOOMTIME,
                     "OUTOFPLN", j_ign_out_of_plane(r_vec, v_vec, land_vec), "THRUST_DIR", thrust_dir).
    }
    SET t_now TO t_now + ddum.
    IF ABS(t_now - t_guess) > J_IGN_MAX_MOVE_S { RETURN j_ign_fail("the ignition time is more than " + J_IGN_MAX_MOVE_S + " s from the planned time", iter_no). }
  }
  RETURN j_ign_fail("no convergence in " + J_IGN_MAX_PASSES + " passes", iter_no).
}

// ======================================================================================================================
// The BURNBABY sequence now lives in lm/burn/lm_burnbaby.ks (release 1.4, plan Task 12)
// ======================================================================================================================
// The J (Luminary 210) sequence differed from the Apollo 11 one in one thing only: it read J_ZOOMTIME where the other reads
// ZOOMTIME (both 26 s, the P63TABLE of 210 has the same values as 099). j_seq_new builds the P63 table for the J profile and
// gives it J_ZOOMTIME, so the J constant is still the one that counts. P63 (J) calls these two; the old code is the
// reference in tests/test_burnbaby.ks.
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").

FUNCTION j_seq_new {
  PARAMETER tig.
  LOCAL tbl IS bb_table_p63("J").
  SET tbl["ZOOMTIME"] TO J_ZOOMTIME.
  RETURN bb_new(tbl, tig).
}

FUNCTION j_seq_step {
  PARAMETER seq, now, pro_pressed, terminate.
  RETURN bb_step(seq, now, pro_pressed, terminate, FALSE).
}
