// lm_p70.ks -- the aborts (release 1.5): P70, abort on the descent engine, and P71, abort on the ascent engine. Both fly the ascent guidance to
// orbit through P12's powered flight, displays, cut-off and trim (lm_p12.ks).
// The rules (pure; spec section 6):
//   abt_new()                                              the abort state: ARMED, T0 (the ignition the abort clock runs from), CSM, the saved plane
//   abt_ignition(abt, ign_t, qaxis_vec, now_ut, ax_now)    armed at an ignition (LETABORT); the plane of the first one is kept, with its axes mark
//   abt_disarm(abt), abt_after_step(abt, prog_no)          disarmed, and disarmed when a programme outside the descent and the aborts is current
//   abt_key_request(abt, prog_no, landed, attached, key)   the programme a control asks for: 70, 71 or -1. key "ABORT", "STAGE0" or "SEPARATED"
//   abt_refusal(abt, prog_no, landed, attached, want_no)   why V37 may not start want_no, or ""
//   abt_keys_new, abt_keys_poll, abt_keys_take             a change of a control, latched until it is taken
// The programmes:
//   p70_start(prog_no, by_key, prev, abt, vault, profile, now_ut, craft, wm_vec)    the state, or LEXICON("REFUSED", reason)
//   p70_step(prog, state, derived, ks)                     one cycle; the programme output keys the DSKY core reads
//   p70_powered(prog, state, now_ut)                       one cycle with the engine lit (P12's state key POWERED)
//   p70_retarget(prog, st, trimming)                       J: the horizontal speed from the CSM's lead, every pass (RETARGET)
//   the END is p12_end; the timed cut-off p12_cut_check
// craft is LEXICON DPS, APS (engine, or 0), ATTACHED (the descent stage is on), CORE_STAYS, LANDED, MASS_KG, SITE_R (the landing-site radius), R, V
// (from the Moon's centre, now), AX (the axes mark of R and V), CSM (FALSE, or LEXICON NAME, R, V in the same axes), CLOCK_ZERO, MU. prev is the running programme's state.
//
// Source: Luminary 099 and 210 P70-P71.agc and ASCENT_GUIDANCE.agc (research-1.5-aborts.md sections 3 to 7). 099 for Apollo 11, 210 for J.
//
// Departures: Backspace and the 0 key stand in for the ABORT and ABORT STAGE buttons and the computer stages, with no engine arm or start presses;
// the computer takes SAS and the throttle (no V50 N25 00203); the descent thrust monitor uses the ascent threshold, so the RCS cannot hide a dry
// descent engine; P70 is refused once landed; a staging by the pilot is taken as abort stage; the CSM is the KSP vessel kept from P63, and without
// one the plane saved at P63 ignition is flown (J: the least apolune); the roll is held while the ship turns over; no 15-minute surface limit, no
// button lock-out, no abort guidance system.

RUNONCEPATH("0:/lm/ascent/lm_p12.ks").          // the shared powered flight, and through it the constants, the store, the guidance and the controls

GLOBAL ABT_LOG_PATH IS "0:/lm/logs/abort.log".  // "#" lines (start, staging, targets, cut-off) always; one row per cycle with LM_LOG

// ---- the rules ----------------------------------------------------------------------------------------------------------------

FUNCTION abt_new {
  RETURN LEXICON("ARMED", FALSE, "T0", -1, "CSM", FALSE, "QAXIS", FALSE, "PLANE_T", -1, "PLANE_AX", FALSE).
}

// abt_ignition: ign_t the UT of the engine's ignition (-1 none yet). A new one arms the aborts and restarts the abort clock; the orbit plane
// (qaxis_vec, in the axes of the mark ax_now) is saved at the first only.
FUNCTION abt_ignition {
  PARAMETER abt, ign_t, qaxis_vec, now_ut, ax_now.
  IF ign_t < 0 OR ign_t = abt["T0"] { RETURN. }
  SET abt["ARMED"] TO TRUE.
  SET abt["T0"] TO ign_t.
  IF abt["PLANE_T"] < 0 {
    SET abt["QAXIS"] TO qaxis_vec.
    SET abt["PLANE_T"] TO now_ut.
    SET abt["PLANE_AX"] TO ax_now.
  }
}

FUNCTION abt_disarm {
  PARAMETER abt.
  SET abt["ARMED"] TO FALSE.
}

// abt_descent_prog: the descent programmes and P68, from which an abort may start.
FUNCTION abt_descent_prog {
  PARAMETER prog_no.
  RETURN prog_no = 63 OR prog_no = 64 OR prog_no = 65 OR prog_no = 66 OR prog_no = 68.
}

// abt_after_step: once per cycle with the programme then current (-1 none): any other than the descent and abort programmes disarms.
FUNCTION abt_after_step {
  PARAMETER abt, prog_no.
  IF abt_descent_prog(prog_no) OR prog_no = 70 OR prog_no = 71 { RETURN. }
  abt_disarm(abt).
}

// abt_key_request: key "ABORT" (Backspace), "STAGE0" (the 0 key) or "SEPARATED" (the descent stage left by itself).
FUNCTION abt_key_request {
  PARAMETER abt, prog_no, landed, attached, key_name.
  IF NOT abt["ARMED"] { RETURN -1. }
  IF NOT (abt_descent_prog(prog_no) OR prog_no = 70) { RETURN -1. }
  IF key_name <> "ABORT" { RETURN 71. }
  IF prog_no = 70 OR landed OR NOT attached { RETURN -1. }
  RETURN 70.
}

// abt_refusal: the V37 column of the rules. V37 E 71 E never stages, so it is refused while the descent stage is on.
FUNCTION abt_refusal {
  PARAMETER abt, prog_no, landed, attached, want_no.
  IF NOT abt["ARMED"] OR NOT (abt_descent_prog(prog_no) OR prog_no = 70) {
    RETURN "no abort now (aborts run from P63 ignition to the end of P68, until a cut-off)".
  }
  IF want_no = 70 {
    IF prog_no = 70 { RETURN "P70 is already flying the abort". }
    IF landed { RETURN "the ship is down: only the ascent stage can leave (the 0 key)". }
    IF NOT attached { RETURN "the descent stage is gone: P71 (the 0 key or V37 E 71 E)". }
    RETURN "".
  }
  IF attached { RETURN "the descent stage is still on: press 0 (V37 E 71 E never stages)". }
  RETURN "".
}

// abt_keys_new / abt_keys_poll: KSP toggles an action group at every press, so a press is a change from the value last seen. SEPARATED is the
// descent stage going from attached to gone. Each is latched until abt_keys_take.
FUNCTION abt_keys_new {
  PARAMETER abort_val, ag10_val, attached.
  RETURN LEXICON("LAST_ABORT", abort_val, "LAST_AG10", ag10_val, "LAST_ATTACHED", attached, "ABORT", FALSE, "STAGE0", FALSE, "SEPARATED", FALSE).
}
FUNCTION abt_keys_poll {
  PARAMETER keys, abort_val, ag10_val, attached.
  IF abort_val <> keys["LAST_ABORT"] { SET keys["ABORT"] TO TRUE. }
  IF ag10_val <> keys["LAST_AG10"] { SET keys["STAGE0"] TO TRUE. }
  IF keys["LAST_ATTACHED"] AND NOT attached { SET keys["SEPARATED"] TO TRUE. }
  SET keys["LAST_ABORT"] TO abort_val.
  SET keys["LAST_AG10"] TO ag10_val.
  SET keys["LAST_ATTACHED"] TO attached.
}
// abt_keys_take: the programme the latched controls ask for (abort stage before abort), or -1. All are cleared, used or not, so a press made
// while nothing could happen never acts later.
FUNCTION abt_keys_take {
  PARAMETER abt, keys, prog_no, landed, attached.
  LOCAL asked IS -1.
  FOR key_name IN LIST("STAGE0", "SEPARATED", "ABORT") {
    IF asked < 0 AND keys[key_name] { SET asked TO abt_key_request(abt, prog_no, landed, attached, key_name). }
    SET keys[key_name] TO FALSE.
  }
  RETURN asked.
}

// ---- the flight ---------------------------------------------------------------------------------------------------------------

// p70_retarget: J only (210 ZDOTDCMP, every guidance pass and while trimming): the horizontal speed from the CSM's lead angle and the predicted
// burnout radius; with no CSM the least apolune. st is the state along the guidance axes.
FUNCTION p70_retarget {
  PARAMETER prog, st, trimming.
  IF prog["PROFILE"] <> "J" { RETURN. }
  IF trimming { SET prog["RP"] TO abt_rp(prog["G"], st, prog["G"]["TGO"], TRUE). }
  LOCAL csm IS prog["CSM_STATE"].
  LOCAL has_csm IS csm:ISTYPE("Lexicon").
  LOCAL lead IS 0.
  IF has_csm { SET lead TO abt_csm_lead(st["UR"], csm["R"], csm["V"]). }
  LOCAL aim IS abt_j_target(has_csm, lead, prog["J_SET"], prog["RP"], prog["SITE_R"], prog["MU"]).
  LOCAL tgt IS prog["TGT"].
  SET tgt["ZDOTD"] TO aim["ZDOTD"].
  lm_store_put_asc(prog["VAULT"], tgt["ZDOTD"], tgt["RDOTD"], tgt["YCO"] - prog["Y"]).          // N76 shows the target in use
}

// p70_powered: one cycle with the engine lit. As p12_powered, with the retargeting, and with the turn through the vertical (ANG1CHEK) in place of
// the pitch-over when the abort starts high. The roll is held while the ship turns over; after it the windows go towards the surface and the yaw
// is the pilot's: ASC_XOVR_S after a vertical rise, at once when there was none.
FUNCTION p70_powered {
  PARAMETER prog, state, now_ut.
  LOCAL msg IS p12_measure(prog, state, now_ut).
  IF NOT prog["GUIDING"] { RETURN msg. }
  LOCAL q_live IS servicer_live(prog, prog["QAXIS0"], state["AX"]).
  LOCAL st IS asc_state(state["R"], state["V"], q_live, state["MU"], prog["RCO"]).
  p70_retarget(prog, st, FALSE).
  LOCAL cmd IS asc_guide(prog["G"], st, prog["TGT"]).
  SET prog["VG"] TO cmd["VG"].
  SET prog["RP"] TO abt_rp(prog["G"], st, cmd["TGO"], FALSE).
  LOCAL want_dir IS cmd["DIR"].
  LOCAL want_up IS prog["CMD_UP"].
  IF prog["RISING"] {
    LOCAL downrange IS win_perp(cmd["DIR"], st["UR"]).
    IF downrange:MAG = 0 { SET downrange TO st["Z"]. }
    LOCAL face_flat IS win_perp(ctl_window_face_vec(), st["UR"]).
    LOCAL yaw_err IS 180.
    IF face_flat:MAG > 0 { SET yaw_err TO VANG(face_flat, downrange). }
    LOCAL height IS p12_height(prog, state).
    IF asc_rise_done(prog["PROFILE"], height, st["RDOT"], yaw_err) {
      SET prog["RISING"] TO FALSE.
      IF height < ASC_RISE_ALT_M {          // a real vertical rise ends the rotation too
        SET prog["ROT"] TO FALSE.
        SET prog["RISE_T"] TO now_ut.
        SET msg TO prog["TAG"] + ": PITCH OVER".
      }
    } ELSE {
      SET want_dir TO st["UR"].
      SET want_up TO downrange.
    }
  }
  IF NOT prog["RISING"] AND prog["ROT"] {
    LOCAL axis_vec IS state["XNB"].
    LOCAL turned IS abt_rotation(TRUE, cmd["DIR"], axis_vec, st["UR"]).
    SET prog["ROT"] TO turned["ROT"].
    SET want_dir TO turned["DIR"].
    IF prog["ROT"] { SET want_up TO win_min_rotation(axis_vec, ctl_window_face_vec(), want_dir). }
  }
  IF NOT prog["RISING"] AND NOT prog["ROT"] {
    LOCAL pilot_yaw IS FALSE.
    IF prog["RISE_T"] >= 0 {
      SET pilot_yaw TO now_ut - prog["RISE_T"] >= ASC_XOVR_S.
    } ELSE {
      IF ABS(ctl_pilot_roll()) > P63_ROLL_DETENT { SET prog["YAW_TAKEN"] TO TRUE. }
      SET pilot_yaw TO prog["YAW_TAKEN"].
    }
    IF pilot_yaw { SET want_up TO p12_roll(prog["ROLL"], ctl_window_face_vec(), want_dir, prog["CMD_UP"], ctl_pilot_roll(), now_ut). }
    ELSE { SET want_up TO asc_window_down(want_dir, st). }
  }
  LOCAL cut_msg IS p12_cut_set(prog, cmd["TGO"], now_ut).
  IF cut_msg <> "" { SET msg TO cut_msg. }
  p12_command(prog, want_dir, want_up).
  RETURN msg.
}

// p70_engage_dps: a V97 relight in P70 takes the controls again with the descent's steering (P12's state key ENGAGE).
FUNCTION p70_engage_dps {
  PARAMETER sas_on.
  ctl_abort_take(FALSE).
  IF sas_on { ctl_hold(). }
}

// ---- the start ----------------------------------------------------------------------------------------------------------------

// p70_refusal: why the abort programme prog_no cannot start, or "". by_key: asked for by a control, not keyed with V37.
FUNCTION p70_refusal {
  PARAMETER prog_no, by_key, cur_no, abt, craft.
  IF by_key {
    LOCAL allowed IS FALSE.
    FOR key_name IN LIST("ABORT", "STAGE0", "SEPARATED") {
      IF abt_key_request(abt, cur_no, craft["LANDED"], craft["ATTACHED"], key_name) = prog_no { SET allowed TO TRUE. }
    }
    IF NOT allowed { RETURN "that control does nothing now". }
  } ELSE {
    LOCAL why IS abt_refusal(abt, cur_no, craft["LANDED"], craft["ATTACHED"], prog_no).
    IF why <> "" { RETURN why. }
  }
  IF prog_no = 70 {
    IF craft["DPS"]:ISTYPE("Scalar") { RETURN "no descent engine found". }
    RETURN "".
  }
  IF craft["APS"]:ISTYPE("Scalar") { RETURN "no ascent engine found (an engine that is never decoupled)". }
  IF craft["ATTACHED"] AND NOT craft["CORE_STAYS"] { RETURN "this kOS processor would be left on the descent stage". }
  RETURN "".
}

// p70_targets: the targets chosen at the first abort programme (COMMINIT and the abort's own): 60 000 ft over the site; the CSM's plane, or the
// one saved at P63 ignition; the cross-range no more than YLIM towards it; the radial speed; the horizontal speed from the time since ignition
// (099) or the CSM's lead (210). Into the state and N76.
FUNCTION p70_targets {
  PARAMETER prog, abt, craft, now_ut.
  LOCAL rco IS prog["SITE_R"] + ASC_HINJECT_M.
  LOCAL csm IS craft["CSM"].
  LOCAL has_csm IS csm:ISTYPE("Lexicon").
  LOCAL qaxis IS V(0, 0, 0).
  IF has_csm { SET qaxis TO asc_qaxis(csm["R"], csm["V"]). SET prog["N0"] TO VCRS(csm["R"], csm["V"]):NORMALIZED. }
  ELSE { SET qaxis TO axes_carry(abt["QAXIS"], abt["PLANE_AX"], craft["AX"]). SET prog["N0"] TO qaxis. }
  SET prog["QAXIS0"] TO qaxis.
  SET prog["AX0"] TO craft["AX"].
  SET prog["RCO"] TO rco.
  SET prog["RP"] TO rco.
  LOCAL st IS asc_state(craft["R"], craft["V"], qaxis, craft["MU"], rco).
  SET prog["Y"] TO st["Y"].
  LOCAL lead IS 0.
  IF has_csm {
    SET lead TO abt_csm_lead(st["UR"], csm["R"], csm["V"]).
    SET prog["J_SET"] TO abt_j_set(lead).
  }
  LOCAL zdotd IS 0.
  IF prog["PROFILE"] = "J" { SET zdotd TO abt_j_target(has_csm, lead, prog["J_SET"], rco, prog["SITE_R"], craft["MU"])["ZDOTD"]. }
  ELSE { SET zdotd TO abt_a11_zdotd((CHOOSE "DPS" IF prog["PROG_NO"] = 70 ELSE "APS"), now_ut - abt["T0"]). }
  SET prog["TGT"] TO asc_target(rco, abt_cross_range(st["Y"]), ABT_RDOTD, zdotd).
  lm_store_put_asc(prog["VAULT"], zdotd, ABT_RDOTD, prog["TGT"]["YCO"] - st["Y"]).
}

// p70_mark_targets: the targets in the log.
FUNCTION p70_mark_targets {
  PARAMETER prog, label.
  IF CTL_DRY { RETURN. }
  LOG "# " + prog["TAG"] + " targets " + label + ": horizontal " + ROUND(prog["TGT"]["ZDOTD"], 2) + " m/s, radial " + ROUND(prog["TGT"]["RDOTD"], 2)
      + " m/s, radius " + ROUND(prog["TGT"]["RCO"]) + " m, Y " + ROUND(prog["Y"]) + " m, YCO " + ROUND(prog["TGT"]["YCO"]) + " m, burnout radius predicted "
      + ROUND(prog["RP"]) + " m, J set " + prog["J_SET"] + ", CSM " + (CHOOSE prog["CSM_STATE"]["NAME"] IF prog["CSM_STATE"]:ISTYPE("Lexicon") ELSE "none") TO prog["LOG"].
}

// p70_start: refusals first, which touch nothing. Then the clock zero is saved (a separation can restart KSP's mission clock), the controls are
// taken at full throttle, and the engine is made ready: P70 the descent engine, nothing staged; P71 the staging, or only the ascent engine when
// the descent stage has gone. The state starts lit, in P12's BURN phase. P71 after P70 keeps P70's targets, rise state and steering terms.
FUNCTION p70_start {
  PARAMETER prog_no, by_key, prev, abt, vault, profile, now_ut, craft, wm_vec.
  LOCAL cur_no IS -1.
  IF prev:ISTYPE("Lexicon") { IF prev:HASKEY("PROG_NO") { SET cur_no TO prev["PROG_NO"]. } }
  LOCAL why IS p70_refusal(prog_no, by_key, cur_no, abt, craft).
  IF why <> "" { RETURN LEXICON("REFUSED", why). }
  LOCAL tag IS "P" + prog_no.
  LOCAL after_p70 IS FALSE.
  IF prog_no = 71 AND cur_no = 70 { SET after_p70 TO prev:HASKEY("ABORT"). }

  IF NOT CTL_DRY {
    lm_clock_zero_save(craft["CLOCK_ZERO"]).
    IF NOT after_p70 {
      IF EXISTS(ABT_LOG_PATH) { DELETEPATH(ABT_LOG_PATH). }
      IF LM_LOG { LOG "UT,PHASE,TGO,VG,VG_BODY_X,VG_BODY_Y,VG_BODY_Z,V_INERTIAL,HDOT,HEIGHT,AT,TBUP,CTL_THR,THRUST_NOW_KN,ATT_ERR_DEG,ATT_MODE,DVMON_COUNT,ROLL_STICK,ROLL_OFF_DEG" TO ABT_LOG_PATH. }
    }
    LOG "# " + tag + " start: UT " + ROUND(now_ut, 2) + ", from P" + cur_no + (CHOOSE " by a control" IF by_key ELSE " by V37") + ", since ignition "
        + ROUND(now_ut - abt["T0"], 2) + " s, mass " + ROUND(craft["MASS_KG"]) + " kg, descent stage " + (CHOOSE "on" IF craft["ATTACHED"] ELSE "gone")
        + ", profile " + profile TO ABT_LOG_PATH.
  }
  ctl_abort_take(prog_no = 71).          // the throttle command is 1 before anything is lit or staged

  LOCAL engine IS craft["APS"].
  LOCAL start_msg IS "".
  LOCAL start_warn IS "".
  IF prog_no = 70 {
    SET engine TO craft["DPS"].
    ctl_engine_on(engine).
    SET start_msg TO "P70: ABORT ON THE DESCENT ENGINE. FULL THROTTLE, SAS OFF. 0 STAGES.".
  } ELSE IF craft["ATTACHED"] {
    LOCAL stage_why IS ctl_stage_ascent(engine).
    SET start_msg TO "P71: ABORT STAGE. THE ASCENT ENGINE HAS IT.".
    IF stage_why <> "" { SET start_msg TO "". SET start_warn TO "P71: STAGING FAILED: " + stage_why + ". PRESS SPACE.". }
    IF NOT CTL_DRY {
      LOG "# P71 staging: " + (CHOOSE "done" IF stage_why = "" ELSE "failed: " + stage_why) TO ABT_LOG_PATH.
      LOCAL found IS ctl_find_ascent_engine().       // looked up again: the ship has just changed
      IF found:ISTYPE("Engine") { SET engine TO found. }
    }
  } ELSE {
    ctl_engine_on(engine).
    SET start_msg TO "P71: ABORT ON THE ASCENT ENGINE (THE DESCENT STAGE HAD GONE).".
  }
  // The throttle stops firing the RCS; after P70 the parts it held that are still here are kept for the restore.
  LOCAL rcs_parts IS LIST().
  IF after_p70 { SET rcs_parts TO ctl_rcs_still_here(prev["RCS_PARTS"]). }
  FOR one_part IN ctl_rcs_fore_off() { rcs_parts:ADD(one_part). }
  IF prog_no = 71 { abt_disarm(abt). }          // nothing follows P71

  LOCAL g IS FALSE.
  IF after_p70 {
    SET g TO asc_new(profile).
    FOR term_name IN LIST("A", "B", "C", "D", "FLPC") { SET g[term_name] TO prev["G"][term_name]. }
    SET g["TGO"] TO 2 * prev["G"]["TGO"].
  } ELSE {
    IF prog_no = 70 { SET g TO asc_new(profile, abt_engine_dps(profile, craft["MASS_KG"])). }
    ELSE { SET g TO asc_new(profile). }
    SET g["TGO"] TO now_ut - abt["T0"].
  }
  LOCAL bb IS bb_new(bb_table_abort(profile), now_ut).          // used by a V97 relight; here the engine counts as lit already
  SET bb["ARMED"] TO TRUE.
  SET bb["IGN_T"] TO now_ut.
  LOCAL run_noun IS 63.
  IF profile = "J" { SET run_noun TO 94. }
  LOCAL engage IS FALSE.
  IF prog_no = 70 { SET engage TO p70_engage_dps@. }
  LOCAL csm IS craft["CSM"].
  LOCAL csm_now IS FALSE.
  IF csm:ISTYPE("Lexicon") { SET csm_now TO csm["R"]. }

  LOCAL prog IS LEXICON("REFUSED", "", "PROG_NO", prog_no, "PHASE", "BURN", "ENDED", FALSE,
      "VAULT", vault, "CLOCK_ZERO", craft["CLOCK_ZERO"], "PROFILE", profile, "WM", wm_vec, "AX0", craft["AX"], "ENGINE", engine,
      "QAXIS0", V(0, 0, 0), "N0", V(0, 0, 0), "CSM_NOW", csm_now, "PLAN", FALSE, "SKIP", FALSE, "PLAN_LEAD", "none",
      "TIG", now_ut, "RCO", 0, "Y", 0, "TGT", FALSE, "N74", LIST(0, 0), "G", g, "VG", V(0, 0, 0),
      "ATT", att_new(), "DVMON", dvmon_new(ASC_DVMON_ACCEL_MS2), "BB", bb, "GUIDING", FALSE, "RISING", TRUE, "RISE_T", -1,
      "ROLL", p12_roll_new(), "WARP", warp_new(),
      "PASS_T0", -1, "PASS_V0", V(0, 0, 0), "PASS_R0", V(0, 0, 0), "PASS_AX", FALSE, "DV", 0,
      "ENGINE_LIT", TRUE, "IGN_T", now_ut, "STAGED_DONE", TRUE, "RCS_HELD", TRUE, "RCS_PARTS", rcs_parts, "CONTROLS", TRUE, "CUT_FIRED", FALSE,
      "THR", 1, "CMD_DIR", p40_facing():FOREVECTOR, "CMD_UP", ctl_window_face_vec(), "IMU_ON", TRUE, "IMU_OK", TRUE,
      "SHOWN", FALSE, "AUTO_CHECKED", TRUE, "LAST_STATE", "BURN", "LAST_REQ", FALSE, "DVSHOWN", FALSE, "START_MSG", start_msg, "START_WARN", start_warn,
      "TAG", tag, "LOG", ABT_LOG_PATH, "IDLE_NOUN", run_noun, "PROMPT_NOUN", 63, "POWERED", p70_powered@, "RETARGET", p70_retarget@, "ENGAGE", engage,
      "ABORT", TRUE, "ABT", abt, "HAS_CSM", csm:ISTYPE("Lexicon"), "CSM_STATE", csm, "J_SET", 1, "RP", 0, "SITE_R", craft["SITE_R"], "MU", craft["MU"],
      "ROT", TRUE, "YAW_TAKEN", FALSE, "VEHICLE_STAGED", prog_no = 71).
  IF after_p70 {
    // No retargeting: P70's plane, targets, rise and rotation state.
    FOR kept_key IN LIST("AX0", "QAXIS0", "N0", "RCO", "Y", "RP", "J_SET", "SITE_R", "HAS_CSM", "RISING", "ROT", "RISE_T", "YAW_TAKEN", "ROLL") {
      SET prog[kept_key] TO prev[kept_key].
    }
    SET prog["TGT"] TO prev["TGT"]:COPY.
  } ELSE {
    p70_targets(prog, abt, craft, now_ut).
  }
  p70_mark_targets(prog, (CHOOSE "kept from P70" IF after_p70 ELSE "at the start")).
  RETURN prog.
}

// ---- the cycle ----------------------------------------------------------------------------------------------------------------

// p70_step: one cycle from the BURN phase on, as p12_step. A cut-off, or ENTR at a relight prompt, ends the abort window.
FUNCTION p70_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL out IS p40_out().
  SET out["PROG_NO"] TO prog["PROG_NO"].
  LOCAL msg IS "".
  LOCAL att_msg IS p12_attitude(prog).
  p12_cut_check(prog, now_ut).
  IF prog["PHASE"] = "BURN" AND prog["CUT_FIRED"] {
    p12_next(prog, out, "POST").                       // this cycle's keys are not read by the next phase
    abt_disarm(prog["ABT"]).
    SET msg TO prog["TAG"] + ": ENGINE CUT-OFF".
    p12_mark(prog, state, "cut-off").
    p70_mark_targets(prog, "at cut-off").
  } ELSE IF prog["PHASE"] = "BURN" {
    SET msg TO p12_burn(prog, state, ks, now_ut, out).
    IF prog["PHASE"] = "POST" { abt_disarm(prog["ABT"]). }
  } ELSE {
    p12_post_step(prog, ks, out).
  }
  p12_trim_update(prog, state, now_ut).
  IF prog["START_MSG"] <> "" {
    SET msg TO prog["START_MSG"] + (CHOOSE "" IF msg = "" ELSE " " + msg).
    SET prog["START_MSG"] TO "".
  }
  p40_warn(out, prog["START_WARN"]).
  SET prog["START_WARN"] TO "".
  IF att_msg <> "" { SET msg TO att_msg. }
  RETURN p12_close_step(prog, state, out, msg).
}
