// lm_p40.ks -- P40, the DPS burn (release 1.4): the external delta-V that P30 worked out, flown by the computer.
//   p40_start(prev, vault, clock_zero, profile, now_ut, eng, f_max_n, xdelv, wm_vec, ref_dir, ref_up)    the programme state, or LEXICON("REFUSED", reason)
//   p40_step(prog, state, derived, ks)                                                                   one cycle; the programme output keys the DSKY core reads
//   p40_end(prog)                                                                                        ullage off, engine off, the controls back
//
// Source: Luminary 099 P40-P47.agc (P4:), BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc (BBB:), R60_62.agc; the order follows research section 5.
//   P40LM (P4:110-154)       R02BOTH, S40.1, S40.2,3, PFLITEDB (1.0 degree deadband), R60, then BURNBABY. Alarm 1706 (the descent stage is gone, P4:116-119)
//                            shows flashing V05 N09: V34 ends, PRO or V32 look again (BBB:882-894).
//   P40AUTO (BBB:904-927)    flashing V50 N25 R1 00203 when the throttle switch is not AUTO or the attitude mode is not AUTO. V34 ends, PRO checks again, ENTR or V32 goes on.
//   P41SPOT (BBB:188-221)    run once after the two displays above (p41spot in lm_burn_s.ks): TIG too close or past is slipped to now + 49.9 s with alarm 1703, no answer needed.
//   BURNBABY (lm_burnbaby.ks) the clock display V06 N40, blank, ullage, the V99 N40 prompt, ignition at TIG, the throttle-up; ENTR at the prompt is GOPOST (skip the burn).
//   S40.8, NSTEER (P4:548-588, 904-961) every servicer pass (2 s): VG = VG - the delta-V measured, the time to go, steering on VG; the cutoff is a timed task set from the time to go
//                            (not a test on VG); under 4 s to go the steering stops and the timer cuts. A burn under 6 s (S40.13) is an impulse burn: timer only.
//   POSTBURN, TIGNOW, TERM40 (P4:170-212) after cutoff flashing V16 N40 (PRO goes on, V34 ends, ENTR shows it again), then flashing V16 N85 (VG in body axes, for the pilot's trim; PRO or V34 ends).
// How this departs, and where Luminary has no equivalent here:
//   * The delta-V measured in a pass comes from the change in the ship's velocity less gravity (what the accelerometers would give); passes start at the end of COAST
//     (Luminary: TIG - 29.9 s), so the ullage's delta-V is counted, and the pass length is the time that really passed, not exactly 2 s (s40_8_pass).
//   * No finite-burn correction (s40_1), no finite-thrust steering: VG's unit vector is the steering direction.
//   * Throttle: AUTO runs the table's throttle-up (full thrust ZOOMTIME after ignition unless NOTHROTL). MAN (ENG_THR_CONT) is a hardware override in the real LM: the pilot's lever
//     (ctl_man_direct: the programme's throttle lock is dropped and the lever drives the engine; only a lever below the engine's minimum is raised to it) is the throttle
//     from ignition and the computer's throttle-up is not used; MAN_THROTTLE_AFTER_S only times the "RAISE THROTTLE" cue. Free control so that no programme sits between
//     the pilot and the engine (a programme that overrides the throttle can fight the pilot, as a user's report showed).
//   * The impulse timer uses the thrust the engine really gives at its minimum throttle (THR_MIN_THRUST_FRAC, measured), not Luminary's 4671 N at the 10 percent level.
//   * A delta-V of zero is refused at the start (Luminary would run a 0.01 s burn, which the handbook warns against).
//   * After cutoff VG is only brought up to date (S40.8 with the steering off would raise alarm 1407 on a pass with no thrust).
//   * The vectors from P30 are in the raw axes of the moment P30 ran. Those axes turn with the Moon, so everything is kept in those axes ("frame 0", prog["T0"]) and turned to
//     the live axes only to command the attitude and to show N85.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").               // store_loaded, lm_store_get_tig
RUNONCEPATH("0:/lm/planner/lm_plan.ks").        // plan_spin_rotate
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/lm/burn/lm_burn_s.ks").         // s40_1, s40_2_3, s40_13, s40_8_pass, s41_1, p41spot
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").       // bb_*, resp_read
RUNONCEPATH("0:/lm/burn/lm_r60.ks").            // r60_*, lm_entr_on_request
RUNONCEPATH("0:/lm/burn/lm_r02.ks").            // r02

GLOBAL P40_N25_CODE IS 203.                     // the checklist code of the P40AUTO request, shown as 00203
GLOBAL P40_LOG_PATH IS "0:/lm/logs/p40.log".    // one line per cycle from the end of COAST on, and one "#" line per message (LM_LOG only); read back after a flight

// p40_log: the flight record (the terminal cannot be copied from). Nothing on the pad or with LM_LOG off.
FUNCTION p40_log {
  PARAMETER prog, state, now_ut, msg.
  IF CTL_DRY OR NOT LM_LOG { RETURN. }
  IF msg <> "" { LOG "# " + ROUND(now_ut, 2) + " " + msg TO P40_LOG_PATH. }
  IF prog["PASS_T0"] < 0 { RETURN. }
  LOCAL vg_vec IS prog["VG"].
  LOG "" + ROUND(now_ut, 2) + "," + prog["PHASE"] + "," + ROUND(p40_remain(prog, now_ut), 1) + "," + ROUND(vg_vec:MAG, 2) + "," + ROUND(vg_vec:X, 2) + "," + ROUND(vg_vec:Y, 2) + ","
      + ROUND(vg_vec:Z, 2) + "," + ROUND(prog["DV"], 2) + "," + ROUND(prog["THR"], 3) + "," + ROUND(CTL_THR, 3) + "," + ROUND(state["THRUST_NOW"], 2) + ","
      + ROUND(ctl_att_error_deg(), 2) + "," + prog["ATT"]["MODE"] + "," + prog["STEER"] + "," + prog["DVMON"]["COUNT"] TO P40_LOG_PATH.
}

// p40_facing: the ship's facing, for the body-axes nouns (S41.1). On the pad (CTL_DRY) P40_DRY_FACING, which tests set.
GLOBAL P40_DRY_FACING IS LOOKDIRUP(V(1, 0, 0), V(0, 1, 0)).
FUNCTION p40_facing {
  IF CTL_DRY { RETURN P40_DRY_FACING. }
  RETURN SHIP:FACING.
}

// p40_out: the output keys every programme step returns, all at their quiet values.
FUNCTION p40_out {
  RETURN LEXICON("SET_VERB", -1, "SET_NOUN", -1, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", FALSE, "ALARM", 0, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE,
                 "EXTRA", LEXICON(), "MSG", "", "ENDED", FALSE, "HANDOVER", FALSE, "PROG_NO", 40, "CONTACT", FALSE, "STATUS", LIST()).
}

// p40_show: ask the core to show a verb and noun now.
FUNCTION p40_show {
  PARAMETER out, verb_no, noun_no.
  SET out["SET_VERB"] TO verb_no.
  SET out["SET_NOUN"] TO noun_no.
}

// Frame 0 and the live axes (see the header): a vector in the axes of prog["T0"] turned to the axes of now_ut, and back.
FUNCTION p40_live {
  PARAMETER prog, vec0, now_ut.
  RETURN plan_spin_rotate(vec0, prog["WM"], -(now_ut - prog["T0"])).
}
FUNCTION p40_to0 {
  PARAMETER prog, vec_live, now_ut.
  RETURN plan_spin_rotate(vec_live, prog["WM"], now_ut - prog["T0"]).
}

// p40_stage_ok: the descent stage is still there: an engine of at least STAGED_THRUST_N in a vacuum and no staging flag. f_max_n is that engine's thrust, N.
FUNCTION p40_stage_ok {
  PARAMETER f_max_n, staged_flag.
  RETURN NOT staged_flag AND f_max_n >= STAGED_THRUST_N.
}

// TODO (1.7 rendezvous): Luminary does not refuse when P30 has not run; with XDELVFLG clear P40 steers on the Lambert (aim-point) VG that P32 to P35 left.
// We refuse because there is no Lambert solution yet. Add it, then drop the XDELV refusal below (and the same one in lm_p41.ks).
// p40_start: refuses (LEXICON with "REFUSED") when P30 has not run, TIG is not loaded or the delta-V is zero; otherwise takes the controls (ctl_start) and returns the
// programme state. xdelv is LM_VEH["XDELV"] (FALSE until P30 has run); wm_vec the Moon's spin; ref_dir and ref_up the IMU reference attitude (N18's zero). f_max_n is the
// engine's vacuum thrust (N), eng the engine part (0 on the pad). prev is FALSE (a V37 start).
FUNCTION p40_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, eng, f_max_n, xdelv, wm_vec, ref_dir, ref_up.
  IF NOT xdelv:ISTYPE("Lexicon") { RETURN LEXICON("REFUSED", "P30 has not been run: run P30 first (V37 E 30 E)"). }
  IF NOT store_loaded(vault, "TIG") { RETURN LEXICON("REFUSED", "TIG is not loaded (V25 N33 E, or the PAD); run P30 first"). }
  IF xdelv["DELVSAB"] <= 0 { RETURN LEXICON("REFUSED", "the delta-V is zero: there is nothing to burn"). }
  LOCAL t0 IS now_ut.
  IF xdelv:HASKEY("T0") { SET t0 TO xdelv["T0"]. }
  IF LM_LOG AND NOT CTL_DRY {
    IF EXISTS(P40_LOG_PATH) { DELETEPATH(P40_LOG_PATH). }
    LOG "UT,PHASE,REMAIN_S,VG,VG_X,VG_Y,VG_Z,DV_GAINED,THR_CMD,CTL_THR,THRUST_NOW_KN,ATT_ERR_DEG,ATT_MODE,STEER,DVMON_COUNT" TO P40_LOG_PATH.
    LOG "# P40 start: TIG UT " + ROUND(clock_zero + lm_store_get_tig(vault), 2) + ", delta-V " + ROUND(xdelv["DELVSAB"], 3) + " m/s, thrust " + ROUND(f_max_n / 1000, 2) + " kN, ENG_THR_CONT " + ENG_THR_CONT TO P40_LOG_PATH.
  }
  ctl_start().
  RETURN LEXICON("REFUSED", "", "PROG_NO", 40, "PHASE", "CHECK", "ENDED", FALSE,
                 "VAULT", vault, "CLOCK_ZERO", clock_zero, "PROFILE", profile, "ENGINE", eng, "F_MAX_N", f_max_n, "WM", wm_vec, "T0", t0,
                 "XD", xdelv, "TIG", clock_zero + lm_store_get_tig(vault), "MAN", ENG_THR_CONT = "MAN",
                 "REF_DIR", ref_dir, "REF_UP", ref_up, "IMU_ON", TRUE, "IMU_OK", TRUE, "STAGED", FALSE,
                 "ATT", att_new(), "DB", db_new(), "WARP", warp_new(), "DVMON", dvmon_new(), "R60", FALSE, "BB", FALSE,
                 "VG", V(0, 0, 0), "UT", V(0, 0, 0), "AXES", FALSE, "N18", LIST(0, 0, 0), "BURN_S", 0, "NOTHROTL", FALSE, "IMPULSE", FALSE,
                 "TGO", 0, "TGO_AT", now_ut, "STEER", TRUE, "CUT_FROZEN", FALSE,
                 "PASS_T0", -1, "PASS_V0", V(0, 0, 0), "PASS_R0", V(0, 0, 0), "DV", 0, "VGMAG0", 0,
                 "ENGINE_LIT", FALSE, "IGN_T", -1, "ULLAGE_ON", FALSE, "THR", 0, "MAN_MSG", FALSE, "CMD_BURN", FALSE, "CMD_DIR", V(0, 0, 0), "CMD_UP", V(0, 0, 0),
                 "SHOWN", FALSE, "AUTO_CHECKED", FALSE, "LAST_STATE", "", "LAST_REQ", FALSE, "DVSHOWN", FALSE, "T_LAST", now_ut, "R1_FINAL", 0).
}

// p40_check: the start of P40LM in one cycle: the stage check (alarm 1706), R02, then S40.1 and S40.2,3 (frame 0, the vectors P30 stored), the burn-time estimate (S40.13) and R60's state.
// Sets prog["PHASE"] to R60 (or STAGED, or ended with an alarm), and returns a message.
FUNCTION p40_check {
  PARAMETER prog, state, now_ut, out.
  IF NOT p40_stage_ok(prog["F_MAX_N"], prog["STAGED"]) {
    SET prog["PHASE"] TO "STAGED".
    SET prog["SHOWN"] TO FALSE.
    RETURN "".
  }
  LOCAL imu IS r02(prog["IMU_ON"], prog["IMU_OK"]).
  IF NOT imu["OK"] {
    SET out["ALARM"] TO imu["ALARM"].
    SET prog["ENDED"] TO TRUE.
    RETURN "P40: alarm " + imu["ALARM"] + (CHOOSE " (the IMU is not on)." IF imu["ALARM"] = 210 ELSE " (the IMU orientation is not known: run P51, or set IMU_ALIGN to AUTO).").
  }
  LOCAL xd IS prog["XD"].
  LOCAL s1 IS s40_1(xd["DELVSIN"]).
  LOCAL axes IS s40_2_3(s1["UT"], xd["RTIG"], xd["VTIG"]).
  SET prog["VG"] TO s1["VG"].
  SET prog["UT"] TO s1["UT"].
  SET prog["VGMAG0"] TO s1["VGMAG"].
  SET prog["AXES"] TO axes.
  LOCAL s13 IS s40_13(state["MASS"] * 1000, s1["VGMAG"], prog["PROFILE"]).
  SET prog["BURN_S"] TO s13["BURN_S"].
  SET prog["NOTHROTL"] TO s13["NOTHROTL"].
  SET prog["IMPULSE"] TO s13["IMPULSE"].
  SET prog["TGO"] TO s13["BURN_S"].
  SET prog["TGO_AT"] TO now_ut.
  SET prog["R60"] TO r60_new(axes["X"], axes["Z"]).
  IF axes["X"]:MAG > 0 { SET prog["N18"] TO r60_cdu_angles(prog["REF_DIR"], prog["REF_UP"], axes["X"], axes["Z"]). }
  SET prog["PHASE"] TO "R60".
  RETURN "".
}

// p40_attitude: the SAS button as the attitude mode and the coast deadband, as P63 does (burn_shared_step): ATT HOLD (SAS on) gives the attitude to the pilot, AUTO takes it back;
// in AUTO the steering lock is dropped inside the deadband and taken again outside it, except when must_lock (the turn, the countdown and the burn). Returns a message.
FUNCTION p40_attitude {
  PARAMETER prog, must_lock.
  LOCAL msg IS "".
  LOCAL mode_before IS prog["ATT"]["MODE"].
  att_step(prog["ATT"], ctl_sas_read(mode_before = "HOLD")).
  IF prog["ATT"]["MODE"] <> mode_before {
    IF prog["ATT"]["MODE"] = "HOLD" { ctl_hold(). SET msg TO "P40: ATTITUDE HOLD (SAS on). SWITCH SAS OFF FOR AUTO.". }
    ELSE { ctl_auto(). SET prog["DB"]["LOCKED"] TO TRUE. SET msg TO "P40: AUTO ATTITUDE RESUMED". }
  }
  IF prog["ATT"]["MODE"] = "AUTO" {
    LOCAL locked_before IS prog["DB"]["LOCKED"].
    db_step(prog["DB"], ctl_att_error_deg(), ctl_rate_deg_s(), must_lock).
    IF prog["DB"]["LOCKED"] <> locked_before {
      IF prog["DB"]["LOCKED"] { ctl_steer_lock(). } ELSE { ctl_steer_release(). }
    }
  }
  RETURN msg.
}

// p40_pass: the servicer pass. Once BURN_PASS_S has gone since the last one, returns LEXICON("DELVREF", the delta-V gained in the pass (frame 0), "SPAN", seconds) and starts the next
// pass; otherwise FALSE. The first call only starts the first pass. The measured delta-V is the change in velocity less gravity at the middle of the pass (what the accelerometers read).
// force closes the pass now however short (the cycle ignition happens: the delta-V from the last pass boundary to ignition, the ullage's, is counted and the first pass with thrust starts at ignition).
FUNCTION p40_pass {
  PARAMETER prog, state, now_ut, force.
  IF prog["PASS_T0"] < 0 {
    SET prog["PASS_T0"] TO now_ut.
    SET prog["PASS_V0"] TO state["V"].
    SET prog["PASS_R0"] TO state["R"].
    RETURN FALSE.
  }
  LOCAL span_s IS now_ut - prog["PASS_T0"].
  IF span_s <= 0 OR (span_s < BURN_PASS_S AND NOT force) { RETURN FALSE. }
  // The raw axes turn with the Moon, so the velocity and position at the start of the pass are in the axes of that moment: turn them to the axes of now before differencing, or
  // the Moon's spin shows up as a velocity change (omega x V x span, about 0.01 m/s per 2 s pass in a 60 nmi orbit, along the radius: it made N85 drift steadily).
  LOCAL v_start IS plan_spin_rotate(prog["PASS_V0"], prog["WM"], -(now_ut - prog["PASS_T0"])).
  LOCAL r_start IS plan_spin_rotate(prog["PASS_R0"], prog["WM"], -(now_ut - prog["PASS_T0"])).
  LOCAL r_mid IS (r_start + state["R"]) / 2.
  LOCAL grav_vec IS r_mid * (-state["MU"] / (r_mid:MAG ^ 3)).
  LOCAL delv_live IS (state["V"] - v_start) - grav_vec * span_s.
  SET prog["PASS_T0"] TO now_ut.
  SET prog["PASS_V0"] TO state["V"].
  SET prog["PASS_R0"] TO state["R"].
  RETURN LEXICON("DELVREF", p40_to0(prog, delv_live, now_ut), "SPAN", span_s).
}

// p40_command: the attitude the steering follows (frame 0 turned to the live axes). Before ignition the burn attitude (once R60 has turned there, or the engine is lit); from ignition the
// direction of VG while the steering is on (S40.8), then held. Nothing is commanded until CMD_BURN (the ship holds the attitude P40 started in).
FUNCTION p40_command {
  PARAMETER prog, now_ut.
  IF NOT prog["CMD_BURN"] { RETURN. }
  IF prog["IGN_T"] < 0 {
    SET prog["CMD_DIR"] TO p40_live(prog, prog["AXES"]["X"], now_ut).
    SET prog["CMD_UP"] TO p40_live(prog, prog["AXES"]["Z"], now_ut).
  } ELSE IF prog["STEER"] AND prog["VG"]:MAG > 0 {
    SET prog["CMD_DIR"] TO p40_live(prog, prog["VG"], now_ut):NORMALIZED.
  }
  ctl_set_command(prog["CMD_DIR"], prog["CMD_UP"], prog["THR"]).
}

// p40_r60_cycle: one cycle of the R60 phase, shared with P41 (lm_p41.ks): the R60 display and keys, the attitude mode and the command. Returns LIST(done, message): done is TRUE
// the cycle R60 finishes (ENTR); a V34 sets prog["ENDED"]. The caller moves on to its next phase.
FUNCTION p40_r60_cycle {
  PARAMETER prog, ks, now_ut, out.
  LOCAL r60_out IS r60_step(prog["R60"], ks, ctl_att_error_deg(), ctl_rate_deg_s()).
  LOCAL done IS FALSE.
  IF r60_out["STATE"] = "TERM" { SET prog["ENDED"] TO TRUE. }
  ELSE IF r60_out["STATE"] = "DONE" { SET done TO TRUE. }
  ELSE {
    IF r60_out["CHANGED"] { p40_show(out, r60_out["VERB"], r60_out["NOUN"]). }
    IF r60_out["FLASH"] { SET out["REQUEST"] TO LEXICON("VERB", R60_VERB_ASK, "NOUN", R60_NOUN_ANGLES). }
    IF r60_out["STATE"] = "TURNING" OR r60_out["STATE"] = "ASK2" { SET prog["CMD_BURN"] TO TRUE. }
  }
  LOCAL turn_msg IS p40_attitude(prog, r60_out["STATE"] = "TURNING").
  IF NOT prog["ENDED"] { p40_command(prog, now_ut). }
  RETURN LIST(done, turn_msg).
}

// p40_remain: the seconds to the next event the clock counts to: TIG before ignition, the cutoff once the time to go is known, the burn estimate until then, zero after the cutoff.
FUNCTION p40_remain {
  PARAMETER prog, now_ut.
  IF prog["PHASE"] = "POST" OR prog["PHASE"] = "TRIM" { RETURN prog["R1_FINAL"]. }
  IF prog["IGN_T"] < 0 { RETURN prog["TIG"] - now_ut. }
  IF prog["BB"]["CUT_UT"] >= 0 { RETURN MAX(0, prog["BB"]["CUT_UT"] - now_ut). }
  RETURN MAX(0, prog["TGO"] - (now_ut - prog["TGO_AT"])).
}

// p40_burn: the BURN phase: the BURNBABY sequence (countdown, ullage, prompt, ignition, throttle, passes, cutoff). Returns a message; sets out["ALARM"] and the display.
FUNCTION p40_burn {
  PARAMETER prog, state, ks, now_ut, dt_cycle, out.
  LOCAL msg IS "".
  LOCAL eng IS prog["ENGINE"].
  LOCAL bb IS prog["BB"].
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  // V34 ends the programme only while a request is up (the V99 prompt or the V97 display; the core sets TERMINATE only then, LAST_REQ is the second guard as in P63).
  LOCAL terminating IS ks["TERMINATE"] AND prog["LAST_REQ"].
  LOCAL entr_pressed IS ks["RECYCLE"] OR lm_entr_on_request(ks, 99, 40).

  // ---- V97 (Luminary COMFAIL): PRO takes the failure back, ENTR lights the engine again from TIG - 5 s ----
  LOCAL dv_failed IS prog["ENGINE_LIT"] AND prog["DVMON"]["FAILED"].
  IF dv_failed AND pro_pressed {
    dvmon_reset(prog["DVMON"]).
    SET prog["DVSHOWN"] TO FALSE.
    SET dv_failed TO FALSE.
    SET pro_pressed TO FALSE.
    SET msg TO "P40: THRUST MONITOR RESET.".
  } ELSE IF dv_failed AND (ks["RECYCLE"] OR lm_entr_on_request(ks, 97, 40)) {
    ctl_engine_off(eng).
    SET prog["ENGINE_LIT"] TO FALSE.
    SET prog["IGN_T"] TO -1.
    SET prog["THR"] TO 0.
    SET prog["PASS_T0"] TO -1.
    SET prog["STEER"] TO TRUE.
    SET prog["CUT_FROZEN"] TO FALSE.
    SET prog["TGO"] TO prog["BURN_S"].
    SET prog["TGO_AT"] TO now_ut.
    bb_retime(bb, now_ut + DVMON_RETRY_S).
    SET prog["TIG"] TO now_ut + DVMON_RETRY_S.
    dvmon_reset(prog["DVMON"]).
    SET prog["DVSHOWN"] TO FALSE.
    SET dv_failed TO FALSE.
    SET entr_pressed TO FALSE.
    SET msg TO "P40: NEW IGNITION IN " + DVMON_RETRY_S + " S.".
  }
  IF dv_failed { SET entr_pressed TO FALSE. }

  // ---- the sequence ----
  LOCAL sq IS bb_step(bb, now_ut, pro_pressed, terminating, entr_pressed).
  IF sq["ULLAGE"] <> prog["ULLAGE_ON"] {
    ctl_ullage(sq["ULLAGE"]).
    SET prog["ULLAGE_ON"] TO sq["ULLAGE"].
  }
  // S40.13 runs again at TIG - 5 s, when the prompt comes up (BBB:370-378): the mass is the latest one.
  IF sq["STATE"] = "PROMPT" AND prog["LAST_STATE"] <> "PROMPT" {
    LOCAL s13 IS s40_13(state["MASS"] * 1000, prog["VG"]:MAG, prog["PROFILE"]).
    SET prog["BURN_S"] TO s13["BURN_S"].
    SET prog["NOTHROTL"] TO s13["NOTHROTL"].
    SET prog["IMPULSE"] TO s13["IMPULSE"].
    bb_set_nothrotl(bb, s13["NOTHROTL"]).
    SET msg TO "P40: PLEASE ENABLE ENGINE: PRESS PRO".
  }
  // The servicer: passes from the end of COAST on (ullage delta-V counts), VG brought up to date, DV (N40 R3) and, from ignition, the steering and the timed cutoff.
  IF sq["STATE"] <> "COAST" AND NOT bb["CUT_DONE"] {
    LOCAL pass_data IS p40_pass(prog, state, now_ut, FALSE).
    IF pass_data:ISTYPE("Lexicon") {
      SET prog["DV"] TO prog["DV"] + pass_data["DELVREF"]:MAG.
      IF NOT prog["ENGINE_LIT"] {
        SET prog["VG"] TO prog["VG"] - pass_data["DELVREF"].
      } ELSE IF NOT prog["IMPULSE"] {
        LOCAL r8 IS s40_8_pass(prog["VG"], pass_data["DELVREF"], pass_data["SPAN"], TDECAY_S, DPSVEX).
        SET prog["VG"] TO r8["VG"].
        IF r8["ALARM"] > 0 { SET out["ALARM"] TO r8["ALARM"]. SET msg TO "P40 ALARM " + r8["ALARM"] + ": VG AND THE MEASURED DELTA-V DISAGREE. NO NEW TIME TO GO.". }
        ELSE {
          SET prog["TGO"] TO r8["TGO"].
          SET prog["TGO_AT"] TO now_ut.
          IF NOT prog["CUT_FROZEN"] { bb_cutoff_set(bb, now_ut + r8["TGO"]). }
          IF NOT r8["STEER"] { SET prog["CUT_FROZEN"] TO TRUE. SET prog["STEER"] TO FALSE. }
        }
        dvmon_step(prog["DVMON"], prog["DV"], now_ut).
      }
    }
  }
  // ---- ignition ----
  IF sq["ENGINE_ON"] AND NOT prog["ENGINE_LIT"] {
    LOCAL ign_pass IS p40_pass(prog, state, now_ut, TRUE).          // the ullage's delta-V up to ignition
    IF ign_pass:ISTYPE("Lexicon") {
      SET prog["VG"] TO prog["VG"] - ign_pass["DELVREF"].
      SET prog["DV"] TO prog["DV"] + ign_pass["DELVREF"]:MAG.
    }
    ctl_arm(eng).
    SET prog["ENGINE_LIT"] TO TRUE.
    SET prog["IGN_T"] TO now_ut.
    SET prog["THR"] TO THR_MIN_FRAC.
    SET prog["CMD_BURN"] TO TRUE.
    IF prog["VG"]:MAG > 0 {
      // The engine steers to the burn attitude from ignition even when R60 was skipped (FINDCDUW): VG's direction, the roll reference from S40.2,3.
      SET prog["CMD_DIR"] TO p40_live(prog, prog["VG"], now_ut):NORMALIZED.
      SET prog["CMD_UP"] TO p40_live(prog, prog["AXES"]["Z"], now_ut).
    }
    SET prog["TGO"] TO prog["BURN_S"].
    SET prog["TGO_AT"] TO now_ut.
    SET msg TO "P40: ENGINE ON".
    IF prog["IMPULSE"] {
      // IMPLBURN (P4:421-439): ignite, send the engine off at the time to go, no steering, no thrust monitor (departure: the time uses the thrust the engine really gives).
      LOCAL thrust_n IS THR_MIN_THRUST_FRAC * prog["F_MAX_N"].
      LOCAL imp_s IS 0.
      IF thrust_n > 0 { SET imp_s TO state["MASS"] * 1000 * prog["VG"]:MAG / thrust_n. }
      bb_cutoff_set(bb, now_ut + MAX(0.1, imp_s + TDECAY_S)).
      SET prog["STEER"] TO FALSE.
      SET prog["CUT_FROZEN"] TO TRUE.
    }
  }
  IF sq["ZOOM"] AND NOT prog["MAN"] {
    SET prog["THR"] TO 1.
    SET msg TO "P40: THROTTLE UP".
  }
  // MAN throttle: KSP's lever drives the engine directly from ignition (ctl_man_direct drops the programme's lock); the programme only raises a lever that is below
  // the engine's minimum. The +15 s "RAISE THROTTLE" message is the handbook's cue (the DOI's 40 percent), not a gate.
  IF prog["ENGINE_LIT"] AND prog["MAN"] {
    SET prog["THR"] TO ctl_man_direct().
    IF NOT prog["MAN_MSG"] AND now_ut >= prog["IGN_T"] + MAN_THROTTLE_AFTER_S { SET prog["MAN_MSG"] TO TRUE. SET msg TO "P40: RAISE THROTTLE". }
  }
  // ---- cutoff ----
  IF sq["ENGINE_OFF"] {
    ctl_disarm(eng).
    SET prog["ENGINE_LIT"] TO FALSE.
    SET prog["THR"] TO 0.
    SET prog["R1_FINAL"] TO 0.
    SET prog["PHASE"] TO "POST".
    SET prog["SHOWN"] TO FALSE.
    SET msg TO "P40: CUTOFF".
  }
  IF sq["GOPOST"] {
    SET prog["R1_FINAL"] TO MAX(0, prog["TIG"] - now_ut).
    SET prog["PHASE"] TO "POST".
    SET prog["SHOWN"] TO FALSE.
    SET msg TO "P40: BURN SKIPPED (ENTR AT THE PROMPT)".
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }

  // ---- the attitude: coast deadband and the SAS button, and the command ----
  LOCAL att_msg IS p40_attitude(prog, sq["STATE"] <> "COAST" OR prog["ENGINE_LIT"]).
  IF att_msg <> "" { SET msg TO att_msg. }
  p40_command(prog, now_ut).
  // ---- turn, then warp: once the ship holds the burn attitude, warp to P63_WARP_LEAD_S before ignition (once only) ----
  IF sq["STATE"] = "COAST" {
    LOCAL warp_ut IS warp_step(prog["WARP"], now_ut, prog["TIG"], ctl_att_error_deg(), ctl_rate_deg_s()).
    IF warp_ut > 0 {
      ctl_warp_to(warp_ut).
      SET msg TO "P40: ATTITUDE REACHED. WARPING TO " + P63_WARP_LEAD_S + " S BEFORE IGNITION (CANCEL WITH KSP'S WARP CANCEL KEY).".
    }
  }

  // ---- the display ----
  IF NOT prog["ENDED"] AND prog["PHASE"] = "BURN" {
    IF NOT prog["SHOWN"] { p40_show(out, 6, 40). SET prog["SHOWN"] TO TRUE. }       // the N40 clock starts as the burn phase does (BBB:159)
    ELSE IF sq["VN"] <> "" AND (sq["STATE"] <> prog["LAST_STATE"] OR sq["STATE"] = "PROMPT") AND NOT dv_failed {
      p40_show(out, sq["VN"]:SUBSTRING(1, 2):TONUMBER(0), sq["VN"]:SUBSTRING(4, 2):TONUMBER(0)).
    }
    IF sq["PROMPT"] { SET out["REQUEST"] TO LEXICON("VERB", 99, "NOUN", 40). }
    IF prog["ENGINE_LIT"] AND prog["DVMON"]["FAILED"] {
      SET out["REQUEST"] TO LEXICON("VERB", 97, "NOUN", 40).
      IF NOT prog["DVSHOWN"] {
        SET prog["DVSHOWN"] TO TRUE.
        p40_show(out, 97, 40).
        SET msg TO "P40: ENGINE FAILURE (V97): NO THRUST. PRO RESETS, ENTR TRIES AGAIN, V34 ENDS.".
      }
    }
    SET out["BLANK"] TO sq["BLANK"].
  }
  IF terminating { SET out["REQUEST"] TO FALSE. }
  SET prog["LAST_STATE"] TO sq["STATE"].
  RETURN msg.
}

// p40_after: the POST and TRIM phases. The passes go on (VG brought up to date, the delta-V gained counted); PRO, V34 and ENTR as in POSTBURN and TIGNOW.
FUNCTION p40_after {
  PARAMETER prog, state, ks, now_ut, out.
  LOCAL ans IS resp_read(ks).
  LOCAL verb_no IS 16.
  LOCAL noun_no IS 40.
  IF prog["PHASE"] = "TRIM" { SET noun_no TO 85. }
  IF prog["IGN_T"] >= 0 {
    LOCAL pass_data IS p40_pass(prog, state, now_ut, FALSE).
    IF pass_data:ISTYPE("Lexicon") {
      SET prog["VG"] TO prog["VG"] - pass_data["DELVREF"].
      SET prog["DV"] TO prog["DV"] + pass_data["DELVREF"]:MAG.
    }
  }
  IF ans["TERM"] {
    SET prog["ENDED"] TO TRUE.
  } ELSE IF ans["PRO"] {
    IF prog["PHASE"] = "POST" { SET prog["PHASE"] TO "TRIM". SET noun_no TO 85. SET prog["SHOWN"] TO FALSE. }
    ELSE { SET prog["ENDED"] TO TRUE. }
  } ELSE IF ans["V32"] OR lm_entr_on_request(ks, verb_no, noun_no) {
    SET prog["SHOWN"] TO FALSE.
  }
  IF NOT prog["ENDED"] {
    IF NOT prog["SHOWN"] { p40_show(out, verb_no, noun_no). SET prog["SHOWN"] TO TRUE. }
    SET out["REQUEST"] TO LEXICON("VERB", verb_no, "NOUN", noun_no).
  }
}

// p40_status: the terminal readout (up to three lines) during the burn: the throttle and the thrust the engine is giving.
FUNCTION p40_status {
  PARAMETER prog, state.
  IF NOT prog["ENGINE_LIT"] { RETURN LIST(). }
  LOCAL pct IS ROUND(ctl_thrust_pct(state["THRUST_NOW"], state["THRUST"])).
  LOCAL lines IS LIST("P40 BURN, THROTTLE " + (CHOOSE "MAN" IF prog["MAN"] ELSE "AUTO")).
  IF prog["MAN"] AND prog["MAN_MSG"] { lines:ADD("RAISE THROTTLE: LEVER (SHIFT / CTRL), THRUST " + pct + " PERCENT"). }
  ELSE IF prog["MAN"] { lines:ADD("THROTTLE: LEVER (SHIFT / CTRL), THRUST " + pct + " PERCENT"). }
  ELSE { lines:ADD("THRUST " + pct + " PERCENT"). }
  RETURN lines.
}

// p40_step: one cycle. The phases are CHECK (stage, IMU, S40.1 to S40.13), STAGED (alarm 1706), R60 (the attitude manoeuvre), AUTO (the P40AUTO request), BURN (BURNBABY),
// POST (flashing V16 N40) and TRIM (flashing V16 N85); each handles its own keys, and a key that moves the programme on is not seen by the next phase in the same cycle.
// Output keys as p63_step; EXTRA carries TTOGO (seconds to the next event, positive), VGDISP, DVTOTAL (m/s), N18 (three angles), N25 (the checklist code) and P40_VGB (VG in body axes, m/s).
FUNCTION p40_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL dt_cycle IS MAX(0, now_ut - prog["T_LAST"]).
  SET prog["T_LAST"] TO now_ut.
  LOCAL out IS p40_out().
  LOCAL msg IS "".
  LOCAL phase_name IS prog["PHASE"].
  IF phase_name = "CHECK" {
    SET msg TO p40_check(prog, state, now_ut, out).
  } ELSE IF phase_name = "STAGED" {
    LOCAL ans IS resp_read(ks).
    IF ans["TERM"] { SET prog["ENDED"] TO TRUE. }
    ELSE IF ans["PRO"] OR ans["V32"] {
      IF p40_stage_ok(prog["F_MAX_N"], prog["STAGED"]) { SET prog["PHASE"] TO "CHECK". SET prog["SHOWN"] TO FALSE. }
      ELSE { SET prog["SHOWN"] TO FALSE. }
    }
    IF NOT prog["ENDED"] AND prog["PHASE"] = "STAGED" {
      IF NOT prog["SHOWN"] {
        SET prog["SHOWN"] TO TRUE.
        SET out["ALARM"] TO 1706.
        p40_show(out, 5, 9).
        SET msg TO "P40 ALARM 1706: THE DESCENT STAGE IS GONE. V34 ENDS; PRO LOOKS AGAIN.".
      }
      SET out["REQUEST"] TO LEXICON("VERB", 5, "NOUN", 9).
    }
  } ELSE IF phase_name = "R60" {
    LOCAL r60_cycle IS p40_r60_cycle(prog, ks, now_ut, out).
    SET msg TO r60_cycle[1].
    IF r60_cycle[0] { SET prog["PHASE"] TO "AUTO". SET prog["SHOWN"] TO FALSE. }
  } ELSE IF phase_name = "AUTO" {
    // P40AUTO (BBB:904-927): the request is only put up when the throttle switch or the attitude mode is not AUTO. PRO checks again, ENTR or V32 goes on, V34 ends.
    LOCAL not_auto IS prog["MAN"] OR prog["ATT"]["MODE"] <> "AUTO".
    LOCAL go_on IS FALSE.
    LOCAL ans IS resp_read(ks).
    IF NOT prog["AUTO_CHECKED"] {
      SET prog["AUTO_CHECKED"] TO TRUE.
      IF NOT not_auto { SET go_on TO TRUE. }
    }
    IF ans["TERM"] { SET prog["ENDED"] TO TRUE. }
    ELSE IF ans["PRO"] { IF not_auto { SET prog["SHOWN"] TO FALSE. } ELSE { SET go_on TO TRUE. } }
    ELSE IF ans["V32"] OR lm_entr_on_request(ks, 50, 25) { SET go_on TO TRUE. }
    IF go_on AND NOT prog["ENDED"] {
      // P41SPOT: the TIG check, once. A TIG too close or already past is slipped with alarm 1703, no answer needed.
      LOCAL spot IS p41spot(prog["TIG"], now_ut).
      IF spot["SLIPPED"] {
        SET prog["TIG"] TO spot["TIG"].
        SET out["ALARM"] TO spot["ALARM"].
        SET msg TO "P40 ALARM " + spot["ALARM"] + ": TIG TOO CLOSE OR PAST, SLIPPED TO " + ROUND(spot["TIG"] - now_ut, 1) + " S FROM NOW.".
      }
      SET prog["BB"] TO bb_new(bb_table_p40(prog["PROFILE"]), prog["TIG"]).
      bb_set_nothrotl(prog["BB"], prog["NOTHROTL"]).
      SET prog["PHASE"] TO "BURN".
      SET prog["SHOWN"] TO FALSE.
    } ELSE IF NOT prog["ENDED"] {
      IF NOT prog["SHOWN"] { SET prog["SHOWN"] TO TRUE. p40_show(out, 50, 25). }
      SET out["REQUEST"] TO LEXICON("VERB", 50, "NOUN", 25).
    }
    LOCAL auto_msg IS p40_attitude(prog, FALSE).
    IF auto_msg <> "" { SET msg TO auto_msg. }
    IF NOT prog["ENDED"] { p40_command(prog, now_ut). }
  } ELSE IF phase_name = "BURN" {
    SET msg TO p40_burn(prog, state, ks, now_ut, dt_cycle, out).
  } ELSE {
    p40_after(prog, state, ks, now_ut, out).
    LOCAL post_msg IS p40_attitude(prog, FALSE).
    IF post_msg <> "" { SET msg TO post_msg. }
  }
  // ---- the values the nouns show ----
  LOCAL vg_body IS LIST(0, 0, 0).
  IF prog["PHASE"] = "TRIM" {
    LOCAL vg_live IS p40_live(prog, prog["VG"], now_ut).
    LOCAL body_vec IS s41_1(vg_live, p40_facing()).
    SET vg_body TO LIST(body_vec:X, body_vec:Y, body_vec:Z).
  }
  SET out["EXTRA"] TO LEXICON("TTOGO", p40_remain(prog, now_ut), "VGDISP", prog["VG"]:MAG, "DVTOTAL", prog["DV"], "N18", prog["N18"], "N25", P40_N25_CODE, "P40_VGB", vg_body).
  IF prog["PHASE"] = "BURN" OR prog["PHASE"] = "POST" OR prog["PHASE"] = "TRIM" { SET out["STATUS"] TO p40_status(prog, state). }
  SET out["MSG"] TO msg.
  SET out["ENDED"] TO prog["ENDED"].
  SET prog["LAST_REQ"] TO out["REQUEST"]:ISTYPE("Lexicon").
  p40_log(prog, state, now_ut, msg).
  RETURN out.
}

// p40_end: ullage off, engine off (the lever then drives the RCS: ctl_disarm), the controls back. The ship is handed over in SAS stability assist when the engine has burned.
FUNCTION p40_end {
  PARAMETER prog.
  ctl_warp_stop().
  IF prog["ENGINE"]:ISTYPE("Engine") OR CTL_DRY {
    ctl_burn_end(prog["ENGINE"], prog["IGN_T"] >= 0).
  } ELSE {
    ctl_ullage(FALSE).          // no engine on the ship (alarm 1706 with the stage gone): there is nothing to shut down
    ctl_release(FALSE).
  }
}
