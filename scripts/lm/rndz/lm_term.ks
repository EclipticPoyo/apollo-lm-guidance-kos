// lm_term.ks -- the terminal phase's maths (rendezvous stage 4), pure: no ship reads, no window. lm_vehicle.ks feeds it and lm_gauge.ks draws it.
//   term_los(line, line_rate, nose_vec, face_vec)            the line-of-sight rate as the drift gauge shows it
//   term_needle(rate_mrad, full_mrad)                        a needle's place, -1 to 1
//   term_fixed(value, places)                                a number as text with that many decimals
//   term_readout(los, profile)                               the gauge's three lines: range, range rate, next gate
//   term_warp_step(warp_st, mode_text, rate, range_m)        the physics warp warning near the CSM, once for each such warp
//   term_dock_new()                                          the state of the docking message
//   term_step(dock_st, wanted, seen, nose_vec, face_vec)     whether the gauge shows, its numbers, and what to say
//
// The gauge stands for the LM's cross-pointer with the rendezvous radar selected: line-of-sight rates in two axes, full scale 20 mrad/s or
// 2 mrad/s (ALSJ Cross-Pointer page, from the LM Operations Handbook; research features/2026-11-26-rendezvous section 17). Which needle showed
// which axis, and which way it moved, was not found, so both are ours: UP is along +X (nose_vec), RIGHT is the crew's right with the window
// (+Z, face_vec) ahead, and a needle off centre means "thrust that way" to stop the drift. The docking message is our own addition (design 10).
// The range and range rate under the dial stand for the LM's tapemeter switched to RNG/RNG RT, feet and ft/s (ALSJ Tapemeters page); the gate
// line is ours (the crew had the gates on a card).

RUNONCEPATH("0:/lm/lm_constants.ks").

// term_los: line and line_rate are the CSM's position and velocity less the LM's (any one set of axes). Returns LEXICON RANGE (m), SPEED (m/s, the
// whole relative speed), RATE (m/s, the range rate, negative closing), ONAXIS (+Z within GAUGE_AXIS_DEG of the line), UP and RIGHT (mrad/s, both 0 off axis): the part of line_rate square to
// the line, over the range, along +X and along the crew's right, each of those first made square to the line.
FUNCTION term_los {
  PARAMETER line, line_rate, nose_vec, face_vec.
  LOCAL distance IS line:MAG.
  LOCAL out IS LEXICON("RANGE", distance, "SPEED", line_rate:MAG, "RATE", 0, "ONAXIS", FALSE, "UP", 0, "RIGHT", 0).
  IF distance <= 0 { RETURN out. }
  SET out["RATE"] TO VDOT(line, line_rate) / distance.
  IF VANG(face_vec, line) > GAUGE_AXIS_DEG { RETURN out. }
  SET out["ONAXIS"] TO TRUE.
  LOCAL along IS line:NORMALIZED.
  LOCAL drift IS VXCL(along, line_rate).
  // kOS axes are left-handed: VCRS of up (+X) with ahead (+Z) is the right.
  LOCAL up_axis IS VXCL(along, nose_vec):NORMALIZED.
  LOCAL right_axis IS VXCL(along, VCRS(nose_vec, face_vec)):NORMALIZED.
  SET out["UP"] TO VDOT(drift, up_axis) * 1000 / distance.
  SET out["RIGHT"] TO VDOT(drift, right_axis) * 1000 / distance.
  RETURN out.
}

// term_needle: where a needle stands for rate_mrad on a full scale of full_mrad: -1 to 1.
FUNCTION term_needle {
  PARAMETER rate_mrad, full_mrad.
  RETURN MAX(-1, MIN(1, rate_mrad / full_mrad)).
}

// term_needle_px: how many whole pixels from the dial's centre a needle stands, when full scale is travel_px pixels each way.
FUNCTION term_needle_px {
  PARAMETER rate_mrad, full_mrad, travel_px.
  RETURN ROUND(term_needle(rate_mrad, full_mrad) * travel_px).
}

// term_fixed: value rounded to places decimals, as text that keeps its trailing zeros.
FUNCTION term_fixed {
  PARAMETER value, places.
  LOCAL scaled IS ROUND(ABS(value) * 10 ^ places).
  LOCAL digits IS "" + scaled.
  UNTIL digits:LENGTH > places { SET digits TO "0" + digits. }
  LOCAL shown IS digits.
  IF places > 0 { SET shown TO digits:SUBSTRING(0, digits:LENGTH - places) + "." + digits:SUBSTRING(digits:LENGTH - places, places). }
  IF value < 0 AND scaled > 0 { SET shown TO "-" + shown. }
  RETURN shown.
}

// term_readout: the three lines under the dial for term_los's result: the range, the range rate, and the next braking gate (the farthest one not
// yet reached) of the profile ("A11" or "J"). Inside the last gate the docking speed stays. Every rate carries its sign, minus closing as on N54,
// the gate speeds too.
FUNCTION term_readout {
  PARAMETER los, profile.
  LOCAL range_ft IS los["RANGE"] * FT_PER_M.
  LOCAL range_text IS "".
  IF range_ft < TERM_FT_BELOW { SET range_text TO term_fixed(range_ft, 0) + " FT". }
  ELSE { SET range_text TO term_fixed(los["RANGE"] / M_PER_NM, 2) + " NM". }
  LOCAL gates IS TERM_GATES_A11.
  IF profile = "J" { SET gates TO TERM_GATES_J. }
  LOCAL gate_text IS "DOCK: " + term_fixed(-DOCK_SPEED_MS * FT_PER_M, 1) + " FT/S".
  FOR gate IN gates {
    IF range_ft > gate[0] {
      SET gate_text TO "BY " + gate[0] + " FT: -" + gate[1] + " FT/S".
      BREAK.
    }
  }
  LOCAL rate_text IS term_fixed(los["RATE"] * FT_PER_M, 1).
  IF NOT rate_text:STARTSWITH("-") { SET rate_text TO "+" + rate_text. }
  RETURN LIST("RANGE  " + range_text, "RATE  " + rate_text + " FT/S", gate_text).
}

// term_warp_step: warp_st is LEXICON("ON", FALSE) to begin with; mode_text and rate are KUNIVERSE:TIMEWARP's. Returns WARP_NEAR_TEXT once when a
// physics warp is running nearer the CSM than WARP_NEAR_M, else "". In that zone KSP keeps the CSM on rails while this ship has physics, and
// physics warp makes it jump on screen (flight, 2026-11-27). Ending the warp, or leaving the zone, arms it again.
FUNCTION term_warp_step {
  PARAMETER warp_st, mode_text, rate, range_m.
  LOCAL near IS mode_text = "PHYSICS" AND rate > 1 AND range_m < WARP_NEAR_M.
  LOCAL said IS "".
  IF near AND NOT warp_st["ON"] { SET said TO WARP_NEAR_TEXT. }
  SET warp_st["ON"] TO near.
  RETURN said.
}

// term_dock_new: nothing armed, nothing said.
FUNCTION term_dock_new {
  RETURN LEXICON("ARMED", FALSE, "TOLD", FALSE).
}

// term_step: wanted is whether the gauge belongs on screen now; seen is lm_rndz_snapshot's result. Returns LEXICON SHOW, LOS (term_los's result,
// else FALSE) and SAY (text, or ""). The docking message is said once, and only after the CSM has been further than DOCK_ARM_M, so that nothing
// is said just after an undocking. Not wanted, or no usable snapshot: hidden, silent, and dock_st left alone.
FUNCTION term_step {
  PARAMETER dock_st, wanted, seen, nose_vec, face_vec.
  LOCAL out IS LEXICON("SHOW", FALSE, "LOS", FALSE, "SAY", "").
  IF NOT wanted { RETURN out. }
  IF NOT seen["OK"] { RETURN out. }
  LOCAL los IS term_los(seen["RT"] - seen["R"], seen["VT"] - seen["V"], nose_vec, face_vec).
  IF los["RANGE"] > DOCK_ARM_M { SET dock_st["ARMED"] TO TRUE. }
  IF dock_st["ARMED"] AND NOT dock_st["TOLD"] AND los["RANGE"] <= DOCK_RANGE_M AND los["SPEED"] < DOCK_SPEED_MS {
    SET dock_st["TOLD"] TO TRUE.
    SET out["SAY"] TO DOCK_TEXT.
  }
  SET out["LOS"] TO los.
  SET out["SHOW"] TO los["RANGE"] < GAUGE_RANGE_M.
  RETURN out.
}
