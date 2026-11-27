// lm_p41.ks -- P41, the RCS burn, and P47, the thrust monitor (release 1.4). The pilot does the burning by hand (the translation keys, the lever); the computer sets up the attitude,
// counts down to TIG and shows the velocity still to be gained (P41) or the velocity gained (P47).
//   p41_start(prev, vault, clock_zero, profile, now_ut, eng, xdelv, ref_dir, ref_up)   p41_step(prog, state, derived, ks)   p41_end(prog)
//   p47_start(prev, now_ut, ax_now)                                                    p47_step(prog, state, derived, ks)   p47_end(prog)
//
// Source: Luminary 099 P40-P47.agc (P4:), BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc (BBB:), research sections 9 and 10.
//   P41LM (P4:110-154 shared with P40, but no 1706 check, no P40AUTO and no V50 N25): R02BOTH, S40.1, S40.2,3, ZATTEROR and SETMINDB (0.3 degree deadband), R60, then BURNBABY with the P41 table
//     (lm_burnbaby.ks bb_table_p41: no ullage, no engine prompt, no zoom). V16 N85 (VG in body axes, S41.1: P4:1467-1471), steady, from the end of R60; blanked TIG - 34.9 to TIG - 29.9
//     (P41BLANK, BBB:275-277); the servicer refreshes it every 2 s from TIG - 29.9. P41SPOT slips a TIG that is too close or past with alarm 1703. At TIG (TIGTASK/TIGNOW, BBB:542-560) the
//     display flashes: V34 or PRO is TERM40 (the programme ends), ENTR shows it again. There is no cutoff and no time to go (S40.13 never runs).
//   P47 (P4:353-363, 402-410, INTI:933-936): R02BOTH, then the first display about TIMEDELT (20 s) after selection, flashing V16 N83: the delta-V gained since the start in body axes, refreshed every
//     pass (CALCN83). PRO or V34 ends it; ENTR or V32 zeroes the count and shows it again.
// Departures:
//   * The engine is never lit by these programmes. At TIG the throttle lock is dropped (ctl_release_throttle_lock) so that with RCS on a raised lever fires the RCS (research section 16);
//     the translation keys need nothing from the programme (the steering lock does not touch them). The steering lock stays until the programme ends.
//   * The velocity gained is measured as in P40 (the change in velocity less gravity, servicer_pass in lm_servicer.ks), so any translation counts, RCS or engine.
//   * The deadband is the project's coast deadband (db_step), not Luminary's 0.3 degree minimum; the lock stays on from TIG.
//   * N85 shows VG in the ship's axes (X nose, Y right, Z window side); N83 the velocity gained in the same axes. A V37 start with no burn set (P30 or
//     P32 to P35) is refused (design call 5).
//   * On an aim point (P34, P35) N85 is recomputed from the aim point each pass, as Luminary's CALCN85 does through S40.8; the attitude is not steered.
//   * No N86, N81 or N40 monitor is shown in P41 (V16 N85 only; the pilot can key the others).
//   * The steering tuning is the coast tuning of ctl_start, with a shorter stopping time on the ascent stage alone (ctl_ascent_coast_tune,
//     measured in KSP); the powered ascent tuning overshot. The real autopilot chose its configuration from APSFLAG, set by V48 (Luminary 210 EXTENDED_VERBS.agc:1351-1360),
//     P71 or P42, and AOSTASK_AND_AOSJOB.agc:120-135 used different mass coefficients for each. We have no V48.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/burn/lm_p40.ks").            // p40_attitude, p40_command, p40_r60_cycle, p40_show, p40_out, p40_facing, and what it loads

// ---- P41 ----

// p41_start: refuses like P40 (p40_burn_refusal); otherwise takes the controls (ctl_start,
// then ctl_ascent_coast_tune when the descent stage is gone) and returns the programme state.
FUNCTION p41_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, eng, xdelv, ref_dir, ref_up.
  LOCAL why IS p40_burn_refusal(vault, clock_zero, now_ut, xdelv).
  IF why <> "" { RETURN LEXICON("REFUSED", why). }
  ctl_start().
  LOCAL dbs IS db_new().
  LOCAL wrp IS warp_new().
  IF NOT ctl_descent_attached() {
    ctl_ascent_coast_tune().                  // brakes the turn earlier on the light stage
    ctl_ascent_hold(dbs, wrp).
  }
  RETURN LEXICON("REFUSED", "", "PROG_NO", 41, "PHASE", "CHECK", "ENDED", FALSE, "APS", FALSE,
                 "VAULT", vault, "CLOCK_ZERO", clock_zero, "PROFILE", profile, "ENGINE", eng, "AX0", xdelv["AX0"],
                 "XD", xdelv, "TIG", clock_zero + lm_store_get_tig(vault),
                 "REF_DIR", ref_dir, "REF_UP", ref_up, "IMU_ON", TRUE, "IMU_OK", TRUE,
                 "ATT", att_new(), "DB", dbs, "WARP", wrp, "R60", FALSE, "BB", FALSE,
                 "VG", V(0, 0, 0), "UT", V(0, 0, 0), "AXES", FALSE, "N18", LIST(0, 0, 0),
                 "PASS_T0", -1, "PASS_V0", V(0, 0, 0), "PASS_R0", V(0, 0, 0), "PASS_AX", FALSE, "DV", 0,
                 "IGN_T", -1, "STEER", FALSE, "THR", 0, "CMD_BURN", FALSE, "CMD_DIR", V(0, 0, 0), "CMD_UP", V(0, 0, 0),
                 "SHOWN", FALSE, "LAST_STATE", "", "T_LAST", now_ut, "AIM_LOST", FALSE, "NOTE", "").
}

// p41_check: R02, S40.1 (or S40.1B on an aim point) and S40.2,3 (frame 0), R60's state. Sets prog["PHASE"] to R60 or ends with an alarm (IMU, or no
// solution to the aim point). Returns a message.
FUNCTION p41_check {
  PARAMETER prog, state, now_ut, out.
  LOCAL imu IS r02(prog["IMU_ON"], prog["IMU_OK"]).
  IF NOT imu["OK"] {
    SET out["ALARM"] TO imu["ALARM"].
    SET prog["ENDED"] TO TRUE.
    RETURN "P41: alarm " + imu["ALARM"] + (CHOOSE " (the IMU is not on)." IF imu["ALARM"] = 210 ELSE " (the IMU orientation is not known: run P51, or set IMU_ALIGN to AUTO).").
  }
  LOCAL vg_msg IS p40_check_vg(prog, state, now_ut, out).
  IF prog["ENDED"] { RETURN vg_msg. }
  LOCAL axes IS prog["AXES"].
  SET prog["R60"] TO r60_new(axes["X"], axes["Z"]).
  IF axes["X"]:MAG > 0 { SET prog["N18"] TO r60_cdu_angles(prog["REF_DIR"], prog["REF_UP"], axes["X"], axes["Z"]). }
  SET prog["PHASE"] TO "R60".
  RETURN "".
}

// p41_vg_body: VG in the ship's axes now (S41.1): LIST of three, m/s.
FUNCTION p41_vg_body {
  PARAMETER prog, ax_now.
  LOCAL body_vec IS s41_1(servicer_live(prog, prog["VG"], ax_now), p40_facing()).
  RETURN LIST(body_vec:X, body_vec:Y, body_vec:Z).
}

// p41_servicer: the servicer passes from the end of COAST on: VG brought up to date (by the delta-V the pilot has made, any thrust, or from the aim point
// as Luminary's CALCN85 does), the delta-V gained counted.
FUNCTION p41_servicer {
  PARAMETER prog, state, now_ut.
  LOCAL pass_data IS servicer_pass(prog, state, now_ut, FALSE).
  IF pass_data:ISTYPE("Lexicon") {
    SET prog["VG"] TO p40_vg_pass(prog, state, now_ut, pass_data["DELVREF"]).
    SET prog["DV"] TO prog["DV"] + pass_data["DELVREF"]:MAG.
  }
}

// p41_status: the terminal readout (two lines) from the burn phase on: the time to TIG counting down as m:ss (the display shows N85, not a clock, and it goes blank 35 s before TIG),
// then, once TIG has passed, a reminder of what to do. Nothing before the burn phase (R60 has its own displays).
FUNCTION p41_status {
  PARAMETER prog, now_ut.
  IF prog["PHASE"] = "BURN" {
    LOCAL secs IS MAX(0, CEILING(prog["TIG"] - now_ut)).
    LOCAL mins IS FLOOR(secs / 60).
    LOCAL rest IS secs - mins * 60.
    RETURN LIST("P41 RCS BURN: TIG IN " + mins + ":" + (CHOOSE "0" IF rest < 10 ELSE "") + rest, "V16 N85 SHOWS VG; IT FLASHES AT TIG").
  }
  IF prog["PHASE"] = "TIGNOW" {
    RETURN LIST("P41 RCS BURN: TIG PASSED", "TRANSLATION KEYS TO ZERO N85, PRO OR V34 ENDS").
  }
  RETURN LIST().
}

// p41_step: one cycle. Phases: CHECK, R60 (as P40), BURN (the countdown: steady V16 N85, blank, passes, the warp), TIGNOW (flashing V16 N85).
// Output keys as p63_step; EXTRA carries P40_VGB (VG in body axes, m/s, for N85), N18, VGDISP and DVTOTAL.
FUNCTION p41_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  SET prog["T_LAST"] TO now_ut.
  LOCAL out IS p40_out().
  SET out["PROG_NO"] TO 41.
  LOCAL msg IS "".
  LOCAL phase_name IS prog["PHASE"].
  IF phase_name = "CHECK" {
    p40_warn(out, p41_check(prog, state, now_ut, out)).          // all it says is why it ends
  } ELSE IF phase_name = "R60" {
    LOCAL r60_cycle IS p40_r60_cycle(prog, ks, state["AX"], out).
    SET msg TO r60_cycle[1].
    IF r60_cycle[0] {
      // P41SPOT, once, then the sequence for the P41 table: no ullage, no prompt.
      LOCAL spot IS p41spot(prog["TIG"], now_ut).
      IF spot["SLIPPED"] {
        SET prog["TIG"] TO spot["TIG"].
        SET out["ALARM"] TO spot["ALARM"].
        p40_warn(out, "P41 ALARM " + spot["ALARM"] + ": TIG TOO CLOSE OR PAST, SLIPPED TO " + ROUND(spot["TIG"] - now_ut, 1) + " S FROM NOW.").
      }
      SET prog["BB"] TO bb_new(bb_table_p41(prog["PROFILE"]), prog["TIG"]).
      SET prog["PHASE"] TO "BURN".
      SET prog["SHOWN"] TO FALSE.
    }
  } ELSE IF phase_name = "BURN" {
    SET ks["PRO"] TO FALSE.                      // PRO means nothing before TIG (no display is waiting for it)
    LOCAL sq IS bb_step(prog["BB"], now_ut, FALSE, FALSE, FALSE).
    IF sq["STATE"] <> "COAST" { p41_servicer(prog, state, now_ut). }
    IF sq["TIG_REACHED"] {
      ctl_release_throttle_lock().
      SET prog["PHASE"] TO "TIGNOW".
      SET prog["SHOWN"] TO FALSE.
      p40_warn(out, "P41: TIG. BURN BY HAND (TRANSLATION KEYS). PRO OR V34 ENDS.").
    }
    LOCAL att_msg IS p40_attitude(prog, sq["STATE"] <> "COAST").
    IF att_msg <> "" { SET msg TO att_msg. }
    p40_command(prog, state["AX"]).
    IF sq["STATE"] = "COAST" {
      LOCAL warp_ut IS warp_step(prog["WARP"], now_ut, prog["TIG"], ctl_att_error_deg(), ctl_rate_deg_s()).
      IF warp_ut > 0 {
        ctl_warp_to(warp_ut).
        SET msg TO "P41: ATTITUDE REACHED. WARPING TO " + P63_WARP_LEAD_S + " S BEFORE IGNITION (CANCEL WITH KSP'S WARP CANCEL KEY).".
      }
    }
    IF prog["PHASE"] = "BURN" {
      IF NOT prog["SHOWN"] { p40_show(out, 16, 85). SET prog["SHOWN"] TO TRUE. }          // steady V16 N85 as the burn phase starts
      SET out["BLANK"] TO sq["BLANK"].
    }
  } ELSE {
    // TIGNOW: flashing V16 N85. V34 or PRO ends (TERM40); ENTR or V32 shows it again. The passes go on: the pilot is burning.
    LOCAL ans IS resp_read(ks).
    p41_servicer(prog, state, now_ut).
    IF ans["TERM"] OR ans["PRO"] { SET prog["ENDED"] TO TRUE. }
    ELSE IF ans["V32"] OR lm_entr_on_request(ks, 16, 85) { SET prog["SHOWN"] TO FALSE. }
    IF NOT prog["ENDED"] {
      IF NOT prog["SHOWN"] { p40_show(out, 16, 85). SET prog["SHOWN"] TO TRUE. }
      SET out["REQUEST"] TO LEXICON("VERB", 16, "NOUN", 85).
    }
    LOCAL hold_msg IS p40_attitude(prog, TRUE).
    IF hold_msg <> "" { SET msg TO hold_msg. }
    p40_command(prog, state["AX"]).
  }
  SET out["EXTRA"] TO LEXICON("P40_VGB", p41_vg_body(prog, state["AX"]), "N18", prog["N18"], "N25", P40_N25_CODE, "VGDISP", prog["VG"]:MAG, "DVTOTAL", prog["DV"], "TTOGO", MAX(0, prog["TIG"] - now_ut)).
  SET out["STATUS"] TO p41_status(prog, now_ut).
  IF prog["NOTE"] <> "" { p40_warn(out, prog["NOTE"]). SET prog["NOTE"] TO "". }
  SET out["MSG"] TO msg.
  SET out["ENDED"] TO prog["ENDED"].
  RETURN out.
}

// p41_end: the engine was never lit. Ullage off (none was on), the controls back (ctl_release with SAS off: the ship is not burning).
FUNCTION p41_end {
  PARAMETER prog.
  ctl_warp_stop().
  ctl_ullage(FALSE).
  ctl_release(FALSE).
}

// ---- P47 ----

// p47_start: nothing can refuse it. The count is kept in the raw axes of the mark ax_now (frame 0, as P40) and starts at zero. No controls are taken.
FUNCTION p47_start {
  PARAMETER prev, now_ut, ax_now.
  RETURN LEXICON("REFUSED", "", "PROG_NO", 47, "PHASE", "WAIT", "ENDED", FALSE, "CHECKED", FALSE, "AX0", ax_now, "START", now_ut,
                 "IMU_ON", TRUE, "IMU_OK", TRUE, "PASS_T0", -1, "PASS_V0", V(0, 0, 0), "PASS_R0", V(0, 0, 0), "PASS_AX", FALSE, "DVCUM", V(0, 0, 0), "SHOWN", FALSE).
}

// p47_step: R02 once, the passes, the first display TIMEDELT (TIG_SLIP_MIN_S, 20 s) after the start, then flashing V16 N83 with its three returns.
FUNCTION p47_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL out IS p40_out().
  SET out["PROG_NO"] TO 47.
  LOCAL msg IS "".
  IF NOT prog["CHECKED"] {
    SET prog["CHECKED"] TO TRUE.
    LOCAL imu IS r02(prog["IMU_ON"], prog["IMU_OK"]).
    IF NOT imu["OK"] {
      SET out["ALARM"] TO imu["ALARM"].
      SET prog["ENDED"] TO TRUE.
      p40_warn(out, "P47: alarm " + imu["ALARM"] + (CHOOSE " (the IMU is not on)." IF imu["ALARM"] = 210 ELSE " (the IMU orientation is not known: run P51, or set IMU_ALIGN to AUTO).")).
    }
  }
  IF NOT prog["ENDED"] {
    LOCAL pass_data IS servicer_pass(prog, state, now_ut, FALSE).
    IF pass_data:ISTYPE("Lexicon") { SET prog["DVCUM"] TO prog["DVCUM"] + pass_data["DELVREF"]. }
    IF prog["PHASE"] = "WAIT" AND now_ut >= prog["START"] + TIG_SLIP_MIN_S {
      SET prog["PHASE"] TO "SHOW".
      SET prog["SHOWN"] TO FALSE.
    }
    IF prog["PHASE"] = "SHOW" {
      LOCAL ans IS resp_read(ks).
      IF ans["TERM"] OR ans["PRO"] { SET prog["ENDED"] TO TRUE. }
      ELSE IF ans["V32"] OR lm_entr_on_request(ks, 16, 83) {
        SET prog["DVCUM"] TO V(0, 0, 0).
        SET prog["SHOWN"] TO FALSE.
      }
      IF NOT prog["ENDED"] {
        IF NOT prog["SHOWN"] { p40_show(out, 16, 83). SET prog["SHOWN"] TO TRUE. }
        SET out["REQUEST"] TO LEXICON("VERB", 16, "NOUN", 83).
      }
    }
  }
  LOCAL body_vec IS s41_1(servicer_live(prog, prog["DVCUM"], state["AX"]), p40_facing()).
  SET out["EXTRA"] TO LEXICON("P47_DVB", LIST(body_vec:X, body_vec:Y, body_vec:Z)).
  SET out["MSG"] TO msg.
  SET out["ENDED"] TO prog["ENDED"].
  RETURN out.
}

// p47_end: nothing was taken, nothing to give back.
FUNCTION p47_end {
  PARAMETER prog.
}
