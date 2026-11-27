// lm_servicer.ks -- the servicer: the delta-V measured over each pass of a powered programme, and the axes carrying it needs (release 1.5, moved
// out of P40 unchanged, then given the measured axes). In Luminary this is SERVICER.agc's 2 s Average-G cycle, which serves every powered programme
// (P12IGN hooks ATMAG onto it); it is not P40's. P40, P41, P47 and P12 call it.
//   servicer_pass(prog, state, now_ut, force)    the delta-V of the pass that has just ended, or FALSE
//   servicer_live(prog, vec0, ax_now)            a vector in the axes of prog["AX0"] carried to the axes of the mark ax_now
//   servicer_to0(prog, vec_live, ax_now)         and back
// prog must hold AX0 (the mark of frame 0), PASS_T0 (-1 before the first pass), PASS_V0, PASS_R0 and PASS_AX; state holds V, R, MU and AX.
// Departures: the velocity change less gravity stands in for the accelerometers, and the length of a pass is the time that really passed. The axes
// carrying has no Luminary counterpart: the AGC's platform does not turn, the raw axes of kOS can (lm_axes.ks measures by how much).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_axes.ks").        // axes_carry

// Frame 0 and the live axes (see the header).
FUNCTION servicer_live {
  PARAMETER prog, vec0, ax_now.
  RETURN axes_carry(vec0, prog["AX0"], ax_now).
}
FUNCTION servicer_to0 {
  PARAMETER prog, vec_live, ax_now.
  RETURN axes_carry(vec_live, ax_now, prog["AX0"]).
}

// servicer_pass: the servicer pass. Once BURN_PASS_S has gone since the last one, returns LEXICON("DELVREF", the delta-V gained in the pass (frame 0), "SPAN", seconds) and starts the next
// pass; otherwise FALSE. The first call only starts the first pass. The measured delta-V is the change in velocity less gravity at the middle of the pass (what the accelerometers read).
// force closes the pass now however short (the cycle ignition happens: the delta-V from the last pass boundary to ignition, the ullage's, is counted and the first pass with thrust starts at ignition).
FUNCTION servicer_pass {
  PARAMETER prog, state, now_ut, force.
  IF prog["PASS_T0"] < 0 {
    SET prog["PASS_T0"] TO now_ut.
    SET prog["PASS_V0"] TO state["V"].
    SET prog["PASS_R0"] TO state["R"].
    SET prog["PASS_AX"] TO state["AX"].
    RETURN FALSE.
  }
  LOCAL span_s IS now_ut - prog["PASS_T0"].
  IF span_s <= 0 OR (span_s < BURN_PASS_S AND NOT force) { RETURN FALSE. }
  // The velocity and position at the start of the pass are in the axes of that moment: carry them to the axes of now before differencing, or a turn of the raw axes shows
  // up as a velocity change (with the Moon's spin: omega x V x span, about 0.01 m/s per 2 s pass in a 60 nmi orbit, along the radius: it made N85 drift steadily).
  LOCAL v_start IS axes_carry(prog["PASS_V0"], prog["PASS_AX"], state["AX"]).
  LOCAL r_start IS axes_carry(prog["PASS_R0"], prog["PASS_AX"], state["AX"]).
  LOCAL r_mid IS (r_start + state["R"]) / 2.
  LOCAL grav_vec IS r_mid * (-state["MU"] / (r_mid:MAG ^ 3)).
  LOCAL delv_live IS (state["V"] - v_start) - grav_vec * span_s.
  SET prog["PASS_T0"] TO now_ut.
  SET prog["PASS_V0"] TO state["V"].
  SET prog["PASS_R0"] TO state["R"].
  SET prog["PASS_AX"] TO state["AX"].
  RETURN LEXICON("DELVREF", servicer_to0(prog, delv_live, state["AX"]), "SPAN", span_s).
}
