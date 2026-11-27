// probe_axes.ks -- where do the kOS raw axes stop turning with the Moon? (rendezvous research 13.1, 1.5)
//
// Run on any craft coasting in a lunar orbit with periapsis below 82 km and apoapsis above 111 km (heights where the axes
// have already been seen turning and inertial), engines off, SAS and RCS off. The descent orbit after DOI will do.
// Nothing is steered or fired; it only reads, and warps on rails for one orbit.
//   RUNPATH("0:/tests/probe_axes.ks").   Log: 0:/lm/logs/probe_axes.log
// It logs:
//   1. TURN: how fast the raw axes turn, as a share of the Moon's own spin (1 = turning with the Moon, 0 = inertial),
//      measured from SOLARPRIMEVECTOR, and the altitude of every change, going up and going down.
//   2. PLANE and ECC: how far the orbit's normal and eccentricity vector have moved from their starting directions, in
//      fixed axes built from SOLARPRIMEVECTOR. A coasting orbit keeps both, so any movement is an error in that
//      conversion. Both should stay near 0 on both sides of the change.

RUNONCEPATH("0:/shared/lm_frame.ks").

LOCAL pax_log IS "0:/lm/logs/probe_axes.log".
LOCAL pax_low_m IS 82000.                                   // the orbit must reach below this
LOCAL pax_high_m IS 111000.                                 // and above this
LOCAL pax_step_s IS 10.                                     // game seconds between samples
LOCAL pax_report_s IS 300.                                  // game seconds between routine log lines

FUNCTION pax_say {
  PARAMETER text.
  PRINT text.
  LOG text TO pax_log.
}

// pax_angle: the angle between two vectors, degrees. ARCTAN2 of the cross and dot products stays accurate for the very
// small angles measured here (the Moon turns 0.0015 degrees in 10 s).
FUNCTION pax_angle {
  PARAMETER a_vec, b_vec.
  RETURN ARCTAN2(VCRS(a_vec, b_vec):MAG, VDOT(a_vec, b_vec)).
}

// pax_look: one reading. WAIT 0 starts a fresh physics tick so that all the reads belong to the same instant.
// "PRIME" is SOLARPRIMEVECTOR flattened into the Moon's equator, in raw axes. "H" (orbit normal) and "E" (eccentricity
// vector, e = ((v^2 - mu/r) r - (r.v) v) / mu) are in the fixed axes: prime, its right angle, and the north pole.
FUNCTION pax_look {
  WAIT 0.
  LOCAL up_vec IS moon_spin():NORMALIZED.
  LOCAL prime_vec IS VXCL(up_vec, SOLARPRIMEVECTOR):NORMALIZED.
  LOCAL side_vec IS VCRS(up_vec, prime_vec):NORMALIZED.
  LOCAL pos_vec IS -SHIP:BODY:POSITION.
  LOCAL vel_vec IS SHIP:VELOCITY:ORBIT.
  LOCAL mu_val IS SHIP:BODY:MU.
  LOCAL norm_vec IS VCRS(pos_vec, vel_vec).
  LOCAL ecc_vec IS (pos_vec * (vel_vec:MAG ^ 2 - mu_val / pos_vec:MAG) - vel_vec * VDOT(pos_vec, vel_vec)) / mu_val.
  RETURN LEXICON("T", TIME:SECONDS, "ALT", SHIP:ALTITUDE, "RISING", VDOT(pos_vec, vel_vec) > 0, "PRIME", prime_vec,
      "H", V(VDOT(norm_vec, prime_vec), VDOT(norm_vec, side_vec), VDOT(norm_vec, up_vec)),
      "E", V(VDOT(ecc_vec, prime_vec), VDOT(ecc_vec, side_vec), VDOT(ecc_vec, up_vec))).
}

FUNCTION pax_km {
  PARAMETER height_m.
  RETURN ROUND(height_m / 1000, 2).
}

FUNCTION pax_run {
  LOCAL base IS pax_look().
  LOCAL spin_deg_s IS 360 / SHIP:BODY:ROTATIONPERIOD.
  LOCAL end_t IS base["T"] + SHIP:ORBIT:PERIOD + 120.
  LOCAL next_report IS base["T"].
  LOCAL state_now IS "".                                    // "TURNING" or "INERTIAL" once the first sample is in
  LOCAL odd_count IS 0.                                     // samples in a row that disagree with state_now
  LOCAL switch_text IS "".
  LOCAL switches IS LIST().
  // For each state: lowest and highest share seen, lowest and highest altitude seen.
  LOCAL seen IS LEXICON("TURNING", LIST(), "INERTIAL", LIST()).
  LOCAL plane_max IS 0.
  LOCAL ecc_max IS 0.
  LOCAL prev IS base.
  LOCAL prev_alt IS base["ALT"].

  pax_say("period " + ROUND(SHIP:ORBIT:PERIOD) + " s, " + pax_km(SHIP:ORBIT:PERIAPSIS) + " x " + pax_km(SHIP:ORBIT:APOAPSIS)
      + " km, inclination " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " deg, e " + ROUND(SHIP:ORBIT:ECCENTRICITY, 5)
      + ", starting at " + pax_km(base["ALT"]) + " km").
  SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

  UNTIL prev["T"] >= end_t {
    // KSP limits rails warp near the Moon, so ask for less when low. WARP is the step number (0 = 1x), not the rate:
    // the steps differ between installs (here 1x, 10x, 100x), and asking for a RATE picks the nearest, so 5 gave 1x.
    LOCAL warp_want IS 0.
    IF SHIP:ALTITUDE > 7000 { SET warp_want TO 1. }
    IF SHIP:ALTITUDE > 35000 { SET warp_want TO 2. }
    // Asked again at every sample where the step differs: KSP can refuse or drop a warp.
    IF KUNIVERSE:TIMEWARP:WARP <> warp_want { SET KUNIVERSE:TIMEWARP:WARP TO warp_want. }
    WAIT pax_step_s.
    LOCAL now_look IS pax_look().
    LOCAL span IS now_look["T"] - prev["T"].
    LOCAL share IS pax_angle(prev["PRIME"], now_look["PRIME"]) / (spin_deg_s * span).
    LOCAL plane_deg IS pax_angle(base["H"], now_look["H"]).
    LOCAL ecc_deg IS pax_angle(base["E"], now_look["E"]).
    SET plane_max TO MAX(plane_max, plane_deg).
    SET ecc_max TO MAX(ecc_max, ecc_deg).
    LOCAL looks_like IS "INERTIAL".
    IF share > 0.5 { SET looks_like TO "TURNING". }
    LOCAL numbers IS "alt " + pax_km(now_look["ALT"]) + " km, TURN " + ROUND(share, 3) + ", PLANE " + ROUND(plane_deg, 4)
        + " deg, ECC " + ROUND(ecc_deg, 4) + " deg, warp " + ROUND(KUNIVERSE:TIMEWARP:RATE) + "x".

    IF state_now = "" {
      SET state_now TO looks_like.
      pax_say("first sample: " + state_now + ", " + numbers).
    }
    IF looks_like <> state_now {
      // Two samples in a row are needed, so that one odd reading is not counted as a change.
      SET odd_count TO odd_count + 1.
      IF odd_count = 1 {
        LOCAL way IS "going down".
        IF now_look["RISING"] { SET way TO "going up". }
        SET switch_text TO "CHANGE to " + looks_like + " " + way + ", between " + pax_km(prev_alt) + " and "
            + pax_km(now_look["ALT"]) + " km".
        pax_say("odd sample: " + numbers).
      } ELSE {
        SET state_now TO looks_like.
        SET odd_count TO 0.
        switches:ADD(switch_text).
        pax_say(switch_text + " (" + numbers + ")").
      }
    } ELSE {
      SET odd_count TO 0.
      LOCAL stats IS seen[state_now].
      IF stats:LENGTH = 0 {
        stats:ADD(share). stats:ADD(share). stats:ADD(now_look["ALT"]). stats:ADD(now_look["ALT"]).
      } ELSE {
        SET stats[0] TO MIN(stats[0], share).
        SET stats[1] TO MAX(stats[1], share).
        SET stats[2] TO MIN(stats[2], now_look["ALT"]).
        SET stats[3] TO MAX(stats[3], now_look["ALT"]).
      }
    }
    IF now_look["T"] >= next_report {
      pax_say("+" + ROUND(now_look["T"] - base["T"]) + " s " + state_now + ", " + numbers).
      SET next_report TO now_look["T"] + pax_report_s.
    }
    SET prev_alt TO prev["ALT"].
    SET prev TO now_look.
  }
  KUNIVERSE:TIMEWARP:CANCELWARP().

  pax_say("-- summary").
  FOR name IN LIST("TURNING", "INERTIAL") {
    LOCAL stats IS seen[name].
    IF stats:LENGTH = 0 {
      pax_say(name + ": never seen").
    } ELSE {
      pax_say(name + ": " + pax_km(stats[2]) + " to " + pax_km(stats[3]) + " km, TURN " + ROUND(stats[0], 3) + " to "
          + ROUND(stats[1], 3)).
    }
  }
  pax_say("changes: " + switches:LENGTH).
  FOR line IN switches { pax_say("  " + line). }
  pax_say("largest PLANE " + ROUND(plane_max, 4) + " deg, largest ECC " + ROUND(ecc_max, 4) + " deg").
  pax_say("== done").
}

IF EXISTS(pax_log) { DELETEPATH(pax_log). }
pax_say("== probe_axes " + TIME:CALENDAR + " " + TIME:CLOCK + ", " + SHIP:NAME + " at " + SHIP:BODY:NAME).
IF SHIP:ORBIT:PERIAPSIS > 0 AND SHIP:ORBIT:PERIAPSIS < pax_low_m AND SHIP:ORBIT:APOAPSIS > pax_high_m {
  pax_run().
} ELSE {
  pax_say("not run: the orbit is " + pax_km(SHIP:ORBIT:PERIAPSIS) + " x " + pax_km(SHIP:ORBIT:APOAPSIS)
      + " km; it needs a periapsis below " + pax_km(pax_low_m) + " km and an apoapsis above " + pax_km(pax_high_m) + " km.").
}
