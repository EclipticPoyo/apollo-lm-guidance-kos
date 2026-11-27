// probe_rendezvous.ks -- what can kOS tell us about the CSM, and how well? (rendezvous research, 1.5)
//
// Historical research probe: it keeps its own axes and Kepler maths, written before lm_axes.ks and lm_conics.ks, so a rerun
// does not test the code P32 and P33 fly (the pad tests test_axes and test_conics do).
//
// Run on the LM in lunar orbit, engines off, SAS and RCS off, no manoeuvre nodes, with the CSM (another vessel in lunar
// orbit) selected as the target. Nothing is steered or fired; it only reads, and warps.
//   RUNPATH("0:/tests/probe_rendezvous.ks").   Log: 0:/lm/logs/probe_rendezvous_far.log or ..._near.log
// The range at the start picks the run:
//   FAR (over 10 km, about 2 h of game time, warped): state noise, and how well the future is predicted, by kOS
//       (POSITIONAT, VELOCITYAT) and by a conic propagator of our own (Kepler, universal variable), against what happens.
//   NEAR (10 km or less, instant): load distances, state noise, docking ports and RCS thrusters of both craft.
//
// All positions are compared in "fixed axes": built each time from SOLARPRIMEVECTOR (kOS docs, bindings) and the Moon's
// north pole, because the raw axes may turn with the Moon in low orbit.

RUNONCEPATH("0:/shared/lm_frame.ks").

LOCAL prv_near_m IS 10000.                                  // range that separates the two runs
LOCAL prv_horizons IS LIST(600, 1800, 3600, 7200).          // seconds ahead that are predicted
LOCAL prv_log IS "0:/lm/logs/probe_rendezvous_far.log".

FUNCTION prv_say {
  PARAMETER text.
  PRINT text.
  LOG text TO prv_log.
}

// prv_axes: three unit vectors, in the raw axes of this moment, that point the same way in space at any time.
FUNCTION prv_axes {
  LOCAL ax_up IS moon_spin():NORMALIZED.
  LOCAL ax_one IS VXCL(ax_up, SOLARPRIMEVECTOR):NORMALIZED.
  RETURN LIST(ax_one, VCRS(ax_up, ax_one):NORMALIZED, ax_up).
}
FUNCTION prv_fix {
  PARAMETER raw_vec, axes.
  RETURN V(VDOT(raw_vec, axes[0]), VDOT(raw_vec, axes[1]), VDOT(raw_vec, axes[2])).
}

// prv_state: both craft now, in fixed axes, positions from the Moon's centre. WAIT 0 starts a fresh physics tick so that
// all the reads belong to the same instant.
FUNCTION prv_state {
  PARAMETER csm_ves.
  WAIT 0.
  LOCAL axes IS prv_axes().
  RETURN LEXICON("T", TIME:SECONDS, "AXES", axes,
      "RS", prv_fix(-SHIP:BODY:POSITION, axes), "VS", prv_fix(SHIP:VELOCITY:ORBIT, axes),
      "RT", prv_fix(csm_ves:POSITION - SHIP:BODY:POSITION, axes), "VT", prv_fix(csm_ves:VELOCITY:ORBIT, axes)).
}

// prv_kepler: where a conic orbit is dt seconds later (universal variable, ellipses only). kOS trig takes degrees, so
// the square root of z (radians) is converted. chi is the "universal anomaly" solved for by Newton's method.
FUNCTION prv_kepler {
  PARAMETER pos0, vel0, dt, mu_val.
  LOCAL r0_mag IS pos0:MAG.
  LOCAL rv_term IS VDOT(pos0, vel0) / SQRT(mu_val).
  LOCAL inv_sma IS 2 / r0_mag - vel0:SQRMAGNITUDE / mu_val.      // 1 / semi-major axis
  LOCAL chi IS SQRT(mu_val) * inv_sma * dt.
  LOCAL c_val IS 0.5.
  LOCAL s_val IS 1 / 6.
  LOCAL z_val IS 0.
  LOCAL passes IS 0.
  LOCAL newton_step IS 1.
  UNTIL ABS(newton_step) < 0.000001 OR passes >= 30 {
    SET z_val TO inv_sma * chi * chi.
    IF z_val > 0.000001 {
      LOCAL root IS SQRT(z_val).
      SET c_val TO (1 - COS(root * CONSTANT:RADTODEG)) / z_val.
      SET s_val TO (root - SIN(root * CONSTANT:RADTODEG)) / (root * z_val).
    } ELSE {
      SET c_val TO 0.5 - z_val / 24.
      SET s_val TO 1 / 6 - z_val / 120.
    }
    LOCAL f_val IS rv_term * chi * chi * c_val + (1 - inv_sma * r0_mag) * chi ^ 3 * s_val + r0_mag * chi - SQRT(mu_val) * dt.
    LOCAL f_slope IS rv_term * chi * (1 - z_val * s_val) + (1 - inv_sma * r0_mag) * chi * chi * c_val + r0_mag.
    SET newton_step TO f_val / f_slope.
    SET chi TO chi - newton_step.
    SET passes TO passes + 1.
  }
  SET z_val TO inv_sma * chi * chi.
  IF z_val > 0.000001 {
    LOCAL root IS SQRT(z_val).
    SET c_val TO (1 - COS(root * CONSTANT:RADTODEG)) / z_val.
    SET s_val TO (root - SIN(root * CONSTANT:RADTODEG)) / (root * z_val).
  }
  LOCAL f_coef IS 1 - chi * chi / r0_mag * c_val.
  LOCAL g_coef IS dt - chi ^ 3 * s_val / SQRT(mu_val).
  LOCAL pos1 IS pos0 * f_coef + vel0 * g_coef.
  LOCAL f_dot IS SQRT(mu_val) / (pos1:MAG * r0_mag) * chi * (z_val * s_val - 1).
  LOCAL g_dot IS 1 - chi * chi / pos1:MAG * c_val.
  RETURN LEXICON("R", pos1, "V", pos0 * f_dot + vel0 * g_dot, "PASSES", passes).
}

FUNCTION prv_load_text {
  PARAMETER csm_ves.
  RETURN "CSM loaded=" + csm_ves:LOADED + " unpacked=" + csm_ves:UNPACKED.
}

// prv_noise: 100 physics ticks. Range rate from the two velocities against the change of the range itself.
FUNCTION prv_noise {
  PARAMETER csm_ves.
  LOCAL last_t IS 0.
  LOCAL last_range IS 0.
  LOCAL last_rate IS 0.
  LOCAL sum_diff IS 0.
  LOCAL max_diff IS 0.
  LOCAL max_jump IS 0.
  LOCAL count IS 0.
  UNTIL count > 100 {
    WAIT 0.
    LOCAL now_t IS TIME:SECONDS.
    LOCAL los IS csm_ves:POSITION.                           // the ship's centre of mass is the origin of raw axes
    LOCAL now_range IS los:MAG.
    LOCAL now_rate IS VDOT(csm_ves:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT, los:NORMALIZED).
    IF count > 0 AND now_t > last_t {
      LOCAL diff IS (now_range - last_range) / (now_t - last_t) - (now_rate + last_rate) / 2.
      SET sum_diff TO sum_diff + diff.
      SET max_diff TO MAX(max_diff, ABS(diff)).
      SET max_jump TO MAX(max_jump, ABS(now_rate - last_rate)).
    }
    SET last_t TO now_t.
    SET last_range TO now_range.
    SET last_rate TO now_rate.
    SET count TO count + 1.
  }
  prv_say("noise over 100 ticks: range " + ROUND(last_range, 2) + " m, range rate " + ROUND(last_rate, 4) + " m/s; "
      + "(range change rate - velocity rate) mean " + ROUND(sum_diff / 100, 4) + ", largest " + ROUND(max_diff, 4)
      + " m/s; largest tick-to-tick change of the rate " + ROUND(max_jump, 4) + " m/s.").
}

// prv_ship_axes: a raw vector as starboard / top / nose parts of the ship.
FUNCTION prv_ship_axes {
  PARAMETER raw_vec, face.
  RETURN "star " + ROUND(VDOT(raw_vec, face:STARVECTOR), 3) + " top " + ROUND(VDOT(raw_vec, face:TOPVECTOR), 3)
      + " nose " + ROUND(VDOT(raw_vec, face:FOREVECTOR), 3).
}

// prv_craft: docking ports and RCS of one craft, in that craft's own axes.
FUNCTION prv_craft {
  PARAMETER craft, label.
  LOCAL face IS craft:FACING.
  prv_say(label + " " + craft:NAME + ": mass " + ROUND(craft:MASS, 3) + " t, docking ports " + craft:DOCKINGPORTS:LENGTH).
  FOR port IN craft:DOCKINGPORTS {
    prv_say("  port '" + port:TITLE + "' type " + port:NODETYPE + " state " + port:STATE).
    prv_say("    node from centre of mass, m: " + prv_ship_axes(port:NODEPOSITION - craft:POSITION, face)).
    prv_say("    faces: " + prv_ship_axes(port:PORTFACING:FOREVECTOR, face)).
  }
  // Thrusters of the ship only: reading the CSM's RCS list as a target stopped kOS 1.6.0.1 with "impossible
  // FromPrimitiveWithAssert(<null>)" (KSP session 1).
  IF label <> "LM" { RETURN. }
  prv_say("  RCS entries " + craft:RCS:LENGTH).
  FOR thr IN craft:RCS {
    prv_say("  rcs '" + thr:TITLE + "' enabled " + thr:ENABLED + " fore/star/top " + thr:FOREENABLED + "/" + thr:STARBOARDENABLED
        + "/" + thr:TOPENABLED + " availablethrust " + ROUND(thr:AVAILABLETHRUST, 4) + " kN isp " + ROUND(thr:ISP, 1)
        + " nozzles " + thr:THRUSTVECTORS:LENGTH).
    FOR nozzle IN thr:THRUSTVECTORS { prv_say("    nozzle " + prv_ship_axes(nozzle, face)). }
  }
}

FUNCTION prv_near_run {
  PARAMETER csm_ves.
  LOCAL dist IS csm_ves:LOADDISTANCE:ORBIT.
  prv_say("CSM load distances in orbit, m: load " + dist:LOAD + " unload " + dist:UNLOAD + " pack " + dist:PACK + " unpack " + dist:UNPACK).
  LOCAL own IS SHIP:LOADDISTANCE:ORBIT.
  prv_say("LM  load distances in orbit, m: load " + own:LOAD + " unload " + own:UNLOAD + " pack " + own:PACK + " unpack " + own:UNPACK).
  prv_noise(csm_ves).
  prv_craft(SHIP, "LM").
  IF csm_ves:UNPACKED { prv_craft(csm_ves, "CSM"). }
  ELSE { prv_say("CSM is not unpacked (too far): its ports were not read. Move closer than the unpack distance and run again."). }
}

FUNCTION prv_far_run {
  PARAMETER csm_ves.
  LOCAL mu_val IS SHIP:BODY:MU.
  prv_noise(csm_ves).
  // 1: time the conic propagator.
  LOCAL base IS prv_state(csm_ves).
  LOCAL clock_start IS TIME:SECONDS.
  LOCAL count IS 0.
  LOCAL passes IS 0.
  UNTIL count >= 100 {
    SET passes TO passes + prv_kepler(base["RT"], base["VT"], 600 + count * 60, mu_val)["PASSES"].
    SET count TO count + 1.
  }
  prv_say("own propagator: 100 solutions in " + ROUND(TIME:SECONDS - clock_start, 2) + " s at IPU " + CONFIG:IPU + ", mean "
      + ROUND(passes / 100, 1) + " passes each.").

  // 2: predict from one instant, then go and look.
  SET base TO prv_state(csm_ves).
  LOCAL preds IS LIST().
  FOR ahead IN prv_horizons {
    LOCAL at_t IS base["T"] + ahead.
    WAIT 0.                                                  // one tick for the four predictions and their axes
    LOCAL axes IS prv_axes().
    preds:ADD(LEXICON("T", at_t,
        "RS", prv_fix(POSITIONAT(SHIP, at_t) - SHIP:BODY:POSITION, axes), "VS", prv_fix(VELOCITYAT(SHIP, at_t):ORBIT, axes),
        "RT", prv_fix(POSITIONAT(csm_ves, at_t) - SHIP:BODY:POSITION, axes), "VT", prv_fix(VELOCITYAT(csm_ves, at_t):ORBIT, axes))).
  }
  prv_say("predictions made within " + ROUND(TIME:SECONDS - base["T"], 3) + " s of the starting state.").
  LOCAL spv_start IS SOLARPRIMEVECTOR.

  LOCAL index IS 0.
  UNTIL index >= preds:LENGTH {
    LOCAL pred IS preds[index].
    prv_say("-- waiting for +" + prv_horizons[index] + " s (warping)").
    WARPTO(pred["T"] - 20).
    WAIT UNTIL TIME:SECONDS >= pred["T"] - 20.
    WAIT UNTIL KUNIVERSE:TIMEWARP:RATE = 1 AND KUNIVERSE:TIMEWARP:ISSETTLED.
    WAIT UNTIL TIME:SECONDS >= pred["T"].
    LOCAL now_state IS prv_state(csm_ves).
    LOCAL late IS now_state["T"] - pred["T"].
    // The look is a tick or so late: step the measured position back along the measured velocity, and the velocity back
    // along gravity.
    LOCAL real_rs IS now_state["RS"] - now_state["VS"] * late.
    LOCAL real_rt IS now_state["RT"] - now_state["VT"] * late.
    LOCAL real_vs IS now_state["VS"] + now_state["RS"] * (mu_val * late / now_state["RS"]:MAG ^ 3).
    LOCAL real_vt IS now_state["VT"] + now_state["RT"] * (mu_val * late / now_state["RT"]:MAG ^ 3).
    LOCAL span IS now_state["T"] - base["T"].
    LOCAL own_s IS prv_kepler(base["RS"], base["VS"], span, mu_val).
    LOCAL own_t IS prv_kepler(base["RT"], base["VT"], span, mu_val).
    prv_say("+" + ROUND(span, 2) + " s, " + prv_load_text(csm_ves) + ", range " + ROUND((real_rt - real_rs):MAG) + " m, raw axes turned "
        + ROUND(VANG(spv_start, SOLARPRIMEVECTOR), 4) + " deg").
    prv_say("  POSITIONAT miss: LM " + ROUND((pred["RS"] - real_rs):MAG, 1) + " m, CSM " + ROUND((pred["RT"] - real_rt):MAG, 1)
        + " m, relative " + ROUND(((pred["RT"] - pred["RS"]) - (real_rt - real_rs)):MAG, 1) + " m").
    prv_say("  VELOCITYAT miss: LM " + ROUND((pred["VS"] - real_vs):MAG, 3) + " m/s, CSM " + ROUND((pred["VT"] - real_vt):MAG, 3)
        + " m/s (looked " + ROUND(late, 3) + " s late)").
    prv_say("  own propagator miss: LM " + ROUND((own_s["R"] - now_state["RS"]):MAG, 1) + " m " + ROUND((own_s["V"] - now_state["VS"]):MAG, 3)
        + " m/s, CSM " + ROUND((own_t["R"] - now_state["RT"]):MAG, 1) + " m " + ROUND((own_t["V"] - now_state["VT"]):MAG, 3)
        + " m/s, relative " + ROUND(((own_t["R"] - own_s["R"]) - (now_state["RT"] - now_state["RS"])):MAG, 1) + " m").
    SET index TO index + 1.
  }
}

// ---- main ------------------------------------------------------------------------------------------------------------
LOCAL prv_csm IS FALSE.
IF HASTARGET { IF TARGET:ISTYPE("Vessel") { SET prv_csm TO TARGET. } }

IF NOT prv_csm:ISTYPE("Vessel") {
  PRINT "probe_rendezvous: select the CSM (a vessel, not a docking port) as the target, then run again.".
} ELSE IF prv_csm:BODY:NAME <> SHIP:BODY:NAME OR prv_csm:STATUS <> "ORBITING" OR SHIP:STATUS <> "ORBITING" {
  PRINT "probe_rendezvous: both craft must be in orbit of the same body.".
} ELSE IF ALLNODES:LENGTH > 0 {
  PRINT "probe_rendezvous: remove the manoeuvre nodes first.".
} ELSE {
  LOCAL prv_near IS prv_csm:POSITION:MAG <= prv_near_m.
  IF prv_near { SET prv_log TO "0:/lm/logs/probe_rendezvous_near.log". }
  IF EXISTS(prv_log) { DELETEPATH(prv_log). }
  LOCAL prv_old_ipu IS CONFIG:IPU.
  SET CONFIG:IPU TO 2000.
  prv_say("== probe_rendezvous  LM=" + SHIP:NAME + "  CSM=" + prv_csm:NAME + "  body=" + SHIP:BODY:NAME + "  MU=" + SHIP:BODY:MU).
  prv_say("LM " + ROUND(SHIP:ORBIT:PERIAPSIS) + " x " + ROUND(SHIP:ORBIT:APOAPSIS) + " m, CSM " + ROUND(prv_csm:ORBIT:PERIAPSIS) + " x "
      + ROUND(prv_csm:ORBIT:APOAPSIS) + " m, range " + ROUND(prv_csm:POSITION:MAG) + " m, " + prv_load_text(prv_csm)).
  IF prv_near { prv_near_run(prv_csm). } ELSE { prv_far_run(prv_csm). }
  prv_say("== done").
  SET CONFIG:IPU TO prv_old_ipu.
}
