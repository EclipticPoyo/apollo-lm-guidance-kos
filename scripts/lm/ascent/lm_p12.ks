// lm_p12.ks -- P12, the powered ascent (release 1.5): from the landing site to lunar orbit on the shared ignition routine.
//   p12_refusal(status_text, rls_loaded, csm, engine_found, core_stays)      why P12 cannot start, or ""
//   p12spot(tig_ut, now_ut)                                                  the TIG check (alarm 1703)
//   p12_start(prev, vault, clock_zero, profile, now_ut, craft, wm_vec)       the programme state, or LEXICON("REFUSED", reason)
//   p12_step(prog, state, derived, ks)                                       one cycle; the programme output keys the DSKY core reads
//   p12_cut_check(prog, now_ut)                                              the timed engine cut-off (also called every 0.02 s)
//   p12_end(prog)                                                            engine off and the controls back, if P12 took them
// craft is LEXICON STATUS (ship status), ENGINE (the ascent engine, or 0), CORE_STAYS, CSM (FALSE, or LEXICON NAME, R, V: from the Moon's centre,
// in the axes of now), PLAN (the saved ascent plan, or FALSE).
//
// Source: Luminary 099 P12.agc and 210 ASCENT_GUIDANCE.agc; P12TABLE in the master ignition routine (research-1.5-ascent.md sections 3 to 5b).
// The order follows P12.agc:
//   CHECK   R02, the IMU check.
//   N33     flashing V06 N33, the lift-off time. PRO: the target radius, the site's distance Y from the CSM plane at TIG, and N76 set to the nominal
//           speeds with cross-range -Y (with "Skip simulated uplink", the ascent plan's values instead).
//   N76     flashing V06 N76. PRO: the targets are read, and a guidance pass from the pad gives the yaw and pitch of N74.
//   AUTO    flashing V50 N25 00203 only when SAS is on (the attitude mode is not AUTO). PRO checks again, ENTR or V32 goes on.
//   BURN    BURNBABY: V06 N74 (with one KSP time warp to P63_WARP_LEAD_S before lift-off), blank, V99 N74 (ENTR: to the trim displays, nothing
//           staged), ignition at TIG: staging, ascent engine, V06 N63 (A11) or V06 N94 (J). Engine estimate every servicer pass; guidance from the
//           first pass that measures real thrust; vertical rise, then pitch over; windows down for 10 s, then the yaw is the pilot's (roll stick,
//           held where it is left); under 4 s to go a timed cut-off.
//   POST    flashing V16 N63 or N94.   TRIM  flashing V16 N85, velocity to be gained in body axes, for the pilot's RCS trim.
// Every flashing display: V34 ends P12, ENTR or V32 shows it again.
//
// Departures: on the surface the vehicle stores RLS from the ship's position at the start (lm_vehicle.ks); the CSM is the KSP vessel taken at the start (its plane is kept, a later target change has no effect); P12 refuses unless landed;
// guidance runs every programme cycle (Luminary: every 2 s); the delta-V is the change in velocity less gravity; the crew's ABORT STAGE and ENGINE
// ARM presses are not made; kOS steering flies the attitude; no AGS.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").                   // store_loaded, lm_store_get_tig, lm_store_get_rls, lm_store_put_asc, lm_clock_zero_save
RUNONCEPATH("0:/lm/planner/lm_plan.ks").            // plan_phase, plan_in_plane
RUNONCEPATH("0:/lm/descent/lm_control.ks").         // ctl_*, att_*, dvmon_*, win_perp, win_hold
RUNONCEPATH("0:/lm/burn/lm_servicer.ks").           // servicer_pass, servicer_live
RUNONCEPATH("0:/lm/burn/lm_burn_s.ks").             // s41_1
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").           // bb_*, resp_read
RUNONCEPATH("0:/lm/burn/lm_r60.ks").                // lm_entr_on_request
RUNONCEPATH("0:/lm/burn/lm_r02.ks").                // r02
RUNONCEPATH("0:/lm/burn/lm_p40.ks").                // p40_out, p40_show, p40_facing, P40_N25_CODE
RUNONCEPATH("0:/lm/ascent/lm_ascent_guid.ks").      // asc_*

GLOBAL P12_LOG_PATH IS "0:/lm/logs/p12.log".        // "#" lines at ignition and cut-off always; one row per cycle from ignition with LM_LOG

// p12_refusal: the first reason P12 cannot start, or "".
FUNCTION p12_refusal {
  PARAMETER status_text, rls_loaded, csm, engine_found, core_stays.
  IF status_text <> "LANDED" { RETURN "the ship is " + status_text + ", not LANDED (P12 stages the ship)". }
  IF NOT rls_loaded { RETURN "RLS (the landing site) is not loaded (P68 stores it at touchdown)". }
  IF NOT csm:ISTYPE("Lexicon") { RETURN "no CSM in orbit: P12 takes the one named in the ascent plan, else the targeted vessel". }
  IF NOT engine_found { RETURN "no ascent engine found (an engine that is never decoupled)". }
  IF NOT core_stays { RETURN "this kOS processor would be left on the descent stage". }
  RETURN "".
}

// p12spot: the TIG check when the countdown would start: a lift-off less than ASC_SPOT_MIN_S away (or past) is moved to ASC_SPOT_AHEAD_S from now,
// alarm 1703, no answer needed.
FUNCTION p12spot {
  PARAMETER tig_ut, now_ut.
  IF tig_ut - now_ut < ASC_SPOT_MIN_S { RETURN LEXICON("TIG", now_ut + ASC_SPOT_AHEAD_S, "SLIPPED", TRUE, "ALARM", 1703). }
  RETURN LEXICON("TIG", tig_ut, "SLIPPED", FALSE, "ALARM", 0).
}

// p12_start: refuses per p12_refusal; keeps the CSM plane in the axes of now ("T0"); with Skip simulated uplink in the plan, loads TIG from it.
// Nothing is taken over: the controls are taken at ignition.
FUNCTION p12_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, craft, wm_vec.
  LOCAL csm IS craft["CSM"].
  LOCAL why IS p12_refusal(craft["STATUS"], store_loaded(vault, "RLS"), csm, NOT craft["ENGINE"]:ISTYPE("Scalar"), craft["CORE_STAYS"]).
  IF why <> "" { RETURN LEXICON("REFUSED", why). }
  LOCAL plan IS craft["PLAN"].
  LOCAL skip IS FALSE.
  LOCAL plan_phase_deg IS "none".
  IF plan:ISTYPE("Lexicon") {
    IF plan:HASKEY("SKIP") { SET skip TO plan["SKIP"]. }
    IF plan:HASKEY("PHASE") { SET plan_phase_deg TO "" + ROUND(plan["PHASE"], 3) + " deg". }
  }
  LOCAL start_msg IS "".
  IF skip AND plan:ISTYPE("Lexicon") {
    IF plan:HASKEY("T_TIG") {
      LOCAL tig_s IS plan["T_TIG"] - clock_zero.
      IF tig_s >= 0 AND tig_s * 100 < LM_CLOCK_LIMIT_CS { lm_store_put_tig(vault, tig_s). SET start_msg TO "P12: LIFT-OFF TIME FILLED FROM THE ASCENT PLAN.". }
      ELSE { SET start_msg TO "P12: THE PLAN'S LIFT-OFF TIME DOES NOT FIT THE AGC CLOCK.". }
    }
  }
  IF NOT CTL_DRY {
    IF EXISTS(P12_LOG_PATH) { DELETEPATH(P12_LOG_PATH). }
    LOG "# P12 start: CSM " + csm["NAME"] + ", profile " + profile + ", clock zero UT " + ROUND(clock_zero, 2) + ", planned CSM lead " + plan_phase_deg TO P12_LOG_PATH.
    IF LM_LOG { LOG "UT,PHASE,TGO,VG,VG_BODY_X,VG_BODY_Y,VG_BODY_Z,V_INERTIAL,HDOT,HEIGHT,AT,TBUP,CTL_THR,THRUST_NOW_KN,ATT_ERR_DEG,ATT_MODE,DVMON_COUNT,ROLL_STICK,ROLL_OFF_DEG" TO P12_LOG_PATH. }
  }
  RETURN LEXICON("REFUSED", "", "PROG_NO", 12, "PHASE", "CHECK", "ENDED", FALSE,
                 "VAULT", vault, "CLOCK_ZERO", clock_zero, "PROFILE", profile, "WM", wm_vec, "T0", now_ut, "ENGINE", craft["ENGINE"],
                 "QAXIS0", asc_qaxis(csm["R"], csm["V"]), "N0", VCRS(csm["R"], csm["V"]):NORMALIZED, "CSM_NOW", FALSE,
                 "PLAN", plan, "SKIP", skip, "PLAN_LEAD", plan_phase_deg,
                 "TIG", -1, "RCO", 0, "Y", 0, "TGT", FALSE, "N74", LIST(0, 0), "G", asc_new(profile), "VG", V(0, 0, 0),
                 "ATT", att_new(), "DVMON", dvmon_new(ASC_DVMON_ACCEL_MS2), "BB", FALSE, "GUIDING", FALSE, "RISING", TRUE, "RISE_T", -1,
                 "ROLL", p12_roll_new(), "WARP", warp_new(),
                 "PASS_T0", -1, "PASS_V0", V(0, 0, 0), "PASS_R0", V(0, 0, 0), "DV", 0,
                 "ENGINE_LIT", FALSE, "IGN_T", -1, "STAGED_DONE", FALSE, "RCS_HELD", FALSE, "RCS_PARTS", LIST(), "CONTROLS", FALSE, "CUT_FIRED", FALSE,
                 "THR", 0, "CMD_DIR", V(0, 0, 0), "CMD_UP", V(0, 0, 0), "IMU_ON", TRUE, "IMU_OK", TRUE,
                 "SHOWN", FALSE, "AUTO_CHECKED", FALSE, "LAST_STATE", "", "LAST_REQ", FALSE, "DVSHOWN", FALSE, "START_MSG", start_msg).
}

// p12_run_noun: the noun shown from ignition: N63 (Luminary 099) or N94 (210).
FUNCTION p12_run_noun {
  PARAMETER prog.
  IF prog["PROFILE"] = "J" { RETURN 94. }
  RETURN 63.
}

// p12_height: height above the landing-site radius, m (the target radius is that radius plus ASC_HINJECT_M).
FUNCTION p12_height {
  PARAMETER prog, state.
  IF prog["RCO"] <= 0 { RETURN 0. }
  RETURN state["R"]:MAG - (prog["RCO"] - ASC_HINJECT_M).
}

// p12_mark: one line in the log at ignition and at cut-off, with the CSM's angle ahead of the LM (to compare with the plan's).
FUNCTION p12_mark {
  PARAMETER prog, state, label.
  IF CTL_DRY { RETURN. }
  LOCAL ur_vec IS state["R"]:NORMALIZED.
  LOCAL rdot IS VDOT(state["V"], ur_vec).
  LOCAL horiz IS (state["V"] - ur_vec * rdot):MAG.
  LOCAL lead IS "not known".
  IF prog["CSM_NOW"]:ISTYPE("Vector") {
    LOCAL n_live IS servicer_live(prog, prog["N0"], state["T"]).
    SET lead TO "" + ROUND(plan_phase(prog["CSM_NOW"], n_live, plan_in_plane(ur_vec, n_live)), 3) + " deg".
  }
  LOG "# P12 " + label + ": UT " + ROUND(state["T"], 2) + ", TIG " + ROUND(prog["TIG"], 2) + ", since ignition " + ROUND(state["T"] - prog["IGN_T"], 2)
      + " s, TGO " + ROUND(prog["G"]["TGO"], 2) + " s, inertial " + ROUND(state["V"]:MAG, 2) + " m/s, radial " + ROUND(rdot, 2) + " m/s, horizontal "
      + ROUND(horiz, 2) + " m/s, height " + ROUND(p12_height(prog, state)) + " m, mass " + ROUND(state["MASS"] * 1000) + " kg, CSM ahead " + lead
      + " (planned at insertion " + prog["PLAN_LEAD"] + ")" TO P12_LOG_PATH.
}

// p12_log: the flight record (the terminal cannot be copied from). Nothing on the pad or with LM_LOG off.
FUNCTION p12_log {
  PARAMETER prog, state, now_ut, msg, vg_body.
  IF CTL_DRY OR NOT LM_LOG { RETURN. }
  IF msg <> "" { LOG "# " + ROUND(now_ut, 2) + " " + msg TO P12_LOG_PATH. }
  IF prog["IGN_T"] < 0 { RETURN. }
  LOG "" + ROUND(now_ut, 2) + "," + prog["PHASE"] + "," + ROUND(prog["G"]["TGO"], 2) + "," + ROUND(prog["VG"]:MAG, 2) + "," + ROUND(vg_body[0], 2) + ","
      + ROUND(vg_body[1], 2) + "," + ROUND(vg_body[2], 2) + "," + ROUND(state["V"]:MAG, 2) + "," + ROUND(VDOT(state["V"], state["R"]:NORMALIZED), 2) + ","
      + ROUND(p12_height(prog, state)) + "," + ROUND(prog["G"]["AT"], 4) + "," + ROUND(prog["G"]["TBUP"], 1) + "," + ROUND(CTL_THR, 3) + ","
      + ROUND(state["THRUST_NOW"], 2) + "," + ROUND(ctl_att_error_deg(), 2) + "," + prog["ATT"]["MODE"] + "," + prog["DVMON"]["COUNT"] + ","
      + ROUND(ctl_pilot_roll(), 2) + "," + ROUND(p12_roll_off(prog), 2) TO P12_LOG_PATH.
}

// p12_roll_off: for the log, the angle about the thrust axis between the ship's window face and the commanded one, degrees.
FUNCTION p12_roll_off {
  PARAMETER prog.
  LOCAL face_flat IS win_perp(ctl_window_face_vec(), CTL_DIR).
  LOCAL want_flat IS win_perp(prog["CMD_UP"], CTL_DIR).
  IF face_flat:MAG = 0 OR want_flat:MAG = 0 { RETURN 0. }
  RETURN VANG(face_flat, want_flat).
}

// p12_attitude: the SAS button as the attitude mode. Before ignition P12 holds no controls, so only the mode (and the ATT HOLD lamp) follows it.
// From ignition SAS on gives the attitude to the pilot, SAS off takes it back. Returns a message.
FUNCTION p12_attitude {
  PARAMETER prog.
  LOCAL mode_before IS prog["ATT"]["MODE"].
  att_step(prog["ATT"], ctl_sas_read(mode_before = "HOLD")).
  IF prog["ATT"]["MODE"] = mode_before OR NOT prog["CONTROLS"] { RETURN "". }
  IF prog["ATT"]["MODE"] = "HOLD" { ctl_hold(). RETURN "P12: ATTITUDE HOLD (SAS on). SWITCH SAS OFF FOR AUTO.". }
  ctl_auto().
  RETURN "P12: AUTO ATTITUDE RESUMED".
}

// p12_ask: a flashing display with its three answers. V34 ends P12; ENTR (also on verb 16 of the noun, which a keyed load leaves up) or V32 shows
// it again. Returns TRUE for PRO; the request stays in out until the caller moves on.
FUNCTION p12_ask {
  PARAMETER prog, ks, out, verb_no, noun_no.
  LOCAL ans IS resp_read(ks).
  IF ans["TERM"] { SET prog["ENDED"] TO TRUE. RETURN FALSE. }
  IF ans["V32"] OR lm_entr_on_request(ks, verb_no, noun_no) OR lm_entr_on_request(ks, 16, noun_no) { SET prog["SHOWN"] TO FALSE. }
  IF NOT prog["SHOWN"] AND NOT ans["PRO"] {
    p40_show(out, verb_no, noun_no).
    SET prog["SHOWN"] TO TRUE.
  }
  SET out["REQUEST"] TO LEXICON("VERB", verb_no, "NOUN", noun_no).
  RETURN ans["PRO"].
}

// p12_next: on to the next phase, whose display is shown on its first cycle.
FUNCTION p12_next {
  PARAMETER prog, out, phase_name.
  SET prog["PHASE"] TO phase_name.
  SET prog["SHOWN"] TO FALSE.
  SET out["REQUEST"] TO FALSE.
}

// p12_accept_tig: PRO at N33 (P12.agc, GUIDINIT and P12INIT): the target radius, Y at TIG from the landed position, and the N76 values.
FUNCTION p12_accept_tig {
  PARAMETER prog, state.
  LOCAL vault IS prog["VAULT"].
  SET prog["TIG"] TO prog["CLOCK_ZERO"] + lm_store_get_tig(vault).
  SET prog["RCO"] TO lm_store_get_rls(vault):MAG + ASC_HINJECT_M.
  LOCAL q_tig IS servicer_live(prog, prog["QAXIS0"], prog["TIG"]).
  SET prog["Y"] TO prog["RCO"] * VDOT(state["R"]:NORMALIZED, q_tig).
  lm_store_put_asc(vault, ASC_ZDOTD_NOM, ASC_RDOTD_NOM, -prog["Y"]).
  LOCAL plan IS prog["PLAN"].
  IF prog["SKIP"] AND plan:ISTYPE("Lexicon") {
    IF plan:HASKEY("ZDOTD") AND plan:HASKEY("RDOTD") AND plan:HASKEY("XRANGE") { lm_store_put_asc(vault, plan["ZDOTD"], plan["RDOTD"], plan["XRANGE"]). }
  }
  IF ABS(prog["Y"]) <= ASC_XRANGE_PAD_M { RETURN "". }
  RETURN "P12: CROSS-RANGE " + ROUND(ABS(prog["Y"]) / M_PER_NM, 1) + " NM IS OVER " + ROUND(ASC_XRANGE_PAD_M / M_PER_NM)
         + " NM. THE ASCENT PAD LOADS " + ROUND(ASC_XRANGE_PAD_M / M_PER_NM) + " AT N76 R3, SAME SIGN (V23 N76 E).".
}

// p12_accept_targets: PRO at N76: the targets from the store, and the pre-ignition guidance pass for N74 (P12RET: at the pad, with the radial speed
// assumed at pitch-over).
FUNCTION p12_accept_targets {
  PARAMETER prog, state.
  LOCAL asc IS lm_store_get_asc(prog["VAULT"]).
  SET prog["TGT"] TO asc_target(prog["RCO"], asc["XRANGE"] + prog["Y"], asc["RDOTD"], asc["ZDOTD"]).
  LOCAL q_tig IS servicer_live(prog, prog["QAXIS0"], prog["TIG"]).
  LOCAL first_st IS asc_state(state["R"], state["V"] + state["R"]:NORMALIZED * ASC_TIPOVER_RDOT, q_tig, state["MU"], prog["RCO"]).
  SET prog["N74"] TO asc_yaw_pitch(asc_guide(asc_new(prog["PROFILE"]), first_st, prog["TGT"]), first_st).
}

// p12_engine_off: the engine shut down (it may be lit again after V97).
FUNCTION p12_engine_off {
  PARAMETER prog.
  IF CTL_DRY OR prog["ENGINE"]:ISTYPE("Engine") { ctl_engine_off(prog["ENGINE"]). }
  SET prog["ENGINE_LIT"] TO FALSE.
  SET prog["THR"] TO 0.
}

// p12_rcs_back: the pilot's fore-by-throttle setting back, once (after the throttle is zeroed).
FUNCTION p12_rcs_back {
  PARAMETER prog.
  IF NOT prog["RCS_HELD"] { RETURN. }
  ctl_rcs_fore_restore(prog["RCS_PARTS"]).
  SET prog["RCS_HELD"] TO FALSE.
}

// p12_ignite: TIG, enabled: the clock zero is saved (a separation can restart KSP's mission clock), the controls are taken with the throttle full,
// the stages separate (once only) and the ascent engine is lit. The present attitude is commanded until guidance starts.
FUNCTION p12_ignite {
  PARAMETER prog, state, now_ut.
  LOCAL msg IS "P12: IGNITION".
  IF NOT CTL_DRY { lm_clock_zero_save(prog["CLOCK_ZERO"]). }
  LOCAL sas_on IS ctl_sas_read(prog["ATT"]["MODE"] = "HOLD").
  att_step(prog["ATT"], sas_on).
  LOCAL nose_now IS p40_facing():FOREVECTOR.
  LOCAL window_now IS ctl_window_face_vec().
  ctl_ascent_start(sas_on).                          // before staging: the throttle command must be 1 when the engine is lit
  SET prog["CONTROLS"] TO TRUE.
  IF NOT prog["STAGED_DONE"] {
    LOCAL why IS ctl_stage_ascent(prog["ENGINE"]).
    SET prog["STAGED_DONE"] TO TRUE.                 // never staged twice, whatever happened
    IF why <> "" { SET msg TO "P12: STAGING FAILED: " + why + ". CHECK THE SHIP.". }
    IF NOT CTL_DRY {
      LOCAL found IS ctl_find_ascent_engine().       // looked up again: the ship has just changed
      IF found:ISTYPE("Engine") { SET prog["ENGINE"] TO found. }
    }
  }
  IF NOT prog["RCS_HELD"] {                          // once, after staging (the parts that stay); a V97 relight keeps the first list
    SET prog["RCS_PARTS"] TO ctl_rcs_fore_off().
    SET prog["RCS_HELD"] TO TRUE.
    IF NOT CTL_DRY { LOG "# P12 RCS: the throttle was set to fire " + prog["RCS_PARTS"]:LENGTH + " thruster part(s); off until the cut-off" TO P12_LOG_PATH. }
  }
  IF CTL_DRY OR prog["ENGINE"]:ISTYPE("Engine") { ctl_engine_on(prog["ENGINE"]). }
  SET prog["ENGINE_LIT"] TO TRUE.
  SET prog["IGN_T"] TO now_ut.
  SET prog["THR"] TO 1.
  SET prog["PASS_T0"] TO -1.
  dvmon_reset(prog["DVMON"]).
  SET prog["DVSHOWN"] TO FALSE.
  SET prog["CMD_DIR"] TO nose_now.
  SET prog["CMD_UP"] TO window_now.
  p12_mark(prog, state, "ignition").
  RETURN msg.
}

// p12_roll_new: the state of the pilot's yaw. FREE TRUE from a stick movement (or ATT HOLD) until a roll attitude has been taken again; FACE and
// SEEN the window face and the time of the last call, for the roll rate.
FUNCTION p12_roll_new {
  RETURN LEXICON("FREE", FALSE, "FACE", V(0, 0, 0), "SEEN", -1).
}

// p12_roll: the window command once the yaw is the pilot's (the roll about the thrust axis, the LM's X axis). With the stick out the command leads
// the ship; released, a fixed attitude is taken at once, ASC_ROLL_LEAD_S of the present turn ahead (about where the ship can stop), and held: only
// a fixed target gives kOS's steering something to brake against. Luminary's P-axis autopilot damps the rate and then holds the angle reached.
// Held, the attitude turns with the thrust axis. face_vec is the ship's window face, up_old the last command.
FUNCTION p12_roll {
  PARAMETER roll, face_vec, dir_vec, up_old, stick, now_ut.
  LOCAL face_now IS win_perp(face_vec, dir_vec).
  LOCAL face_last IS win_perp(roll["FACE"], dir_vec).
  LOCAL since_s IS now_ut - roll["SEEN"].
  LOCAL has_last IS roll["SEEN"] >= 0 AND since_s > 0.
  SET roll["FACE"] TO face_vec.
  SET roll["SEEN"] TO now_ut.
  IF ABS(stick) > P63_ROLL_DETENT {
    SET roll["FREE"] TO TRUE.
    RETURN win_hold(face_vec, dir_vec, up_old, stick).
  }
  IF roll["FREE"] {
    IF face_now:MAG = 0 { RETURN up_old. }
    SET roll["FREE"] TO FALSE.
    IF NOT has_last OR face_last:MAG = 0 { RETURN face_now. }
    RETURN (face_now + (face_now - face_last) * (ASC_ROLL_LEAD_S / since_s)):NORMALIZED.
  }
  LOCAL held IS win_perp(up_old, dir_vec).
  IF held:MAG = 0 { RETURN up_old. }
  RETURN held.
}

// p12_powered: one cycle with the engine lit: the servicer pass into the engine estimate and the thrust monitor, then guidance (from the first pass
// that measured real thrust), the attitude it wants and the timed cut-off. Returns a message.
FUNCTION p12_powered {
  PARAMETER prog, state, now_ut.
  LOCAL msg IS "".
  LOCAL bb IS prog["BB"].
  LOCAL pass_data IS servicer_pass(prog, state, now_ut, FALSE).
  IF pass_data:ISTYPE("Lexicon") {
    LOCAL dv_ms IS pass_data["DELVREF"]:MAG.
    SET prog["DV"] TO prog["DV"] + dv_ms.
    IF asc_engine(prog["G"], dv_ms, pass_data["SPAN"]) {
      IF NOT prog["GUIDING"] { SET prog["GUIDING"] TO TRUE. SET msg TO "P12: GUIDANCE ON". }
    }
    IF bb["CUT_UT"] < 0 { dvmon_step(prog["DVMON"], prog["DV"], now_ut). }          // the monitor stops once the cut-off is set
  }
  IF NOT prog["GUIDING"] { RETURN msg. }
  LOCAL q_live IS servicer_live(prog, prog["QAXIS0"], now_ut).
  LOCAL st IS asc_state(state["R"], state["V"], q_live, state["MU"], prog["RCO"]).
  LOCAL cmd IS asc_guide(prog["G"], st, prog["TGT"]).
  SET prog["VG"] TO cmd["VG"].
  LOCAL want_dir IS cmd["DIR"].
  LOCAL want_up IS prog["CMD_UP"].
  IF prog["RISING"] {
    // Vertical rise: thrust straight up, the windows turned to the way the ascent will go.
    LOCAL downrange IS win_perp(cmd["DIR"], st["UR"]).
    IF downrange:MAG = 0 { SET downrange TO st["Z"]. }
    LOCAL face_flat IS win_perp(ctl_window_face_vec(), st["UR"]).
    LOCAL yaw_err IS 180.
    IF face_flat:MAG > 0 { SET yaw_err TO VANG(face_flat, downrange). }
    IF asc_rise_done(prog["PROFILE"], p12_height(prog, state), st["RDOT"], yaw_err) {
      SET prog["RISING"] TO FALSE.
      SET prog["RISE_T"] TO now_ut.
      SET msg TO "P12: PITCH OVER".
    } ELSE {
      SET want_dir TO st["UR"].
      SET want_up TO downrange.
    }
  }
  IF NOT prog["RISING"] {
    // Windows toward the surface for ASC_XOVR_S, then the roll about the thrust axis (the LM's yaw) is the pilot's.
    IF now_ut - prog["RISE_T"] < ASC_XOVR_S { SET want_up TO asc_window_down(want_dir, st). }
    ELSE { SET want_up TO p12_roll(prog["ROLL"], ctl_window_face_vec(), want_dir, prog["CMD_UP"], ctl_pilot_roll(), now_ut). }
  }
  IF prog["ATT"]["MODE"] = "HOLD" {          // the pilot is flying: back in AUTO the roll left is taken, not the old one
    SET prog["ROLL"]["FREE"] TO TRUE.
  }
  IF bb["CUT_UT"] < 0 AND cmd["TGO"] < ASC_T_CUT {
    bb_cutoff_set(bb, now_ut + MAX(0, cmd["TGO"])).
    SET msg TO "P12: CUT-OFF IN " + ROUND(MAX(0, cmd["TGO"]), 1) + " S".
  }
  IF prog["ATT"]["MODE"] = "AUTO" {          // ATT HOLD: guidance and the cut-off go on, no attitude commands
    SET prog["CMD_DIR"] TO want_dir.
    SET prog["CMD_UP"] TO want_up.
  }
  RETURN msg.
}

// p12_cut_check: the timed engine cut-off (ENGOFTSK). Once, at or after the cut time: engine off, and the throttle lever drives the RCS again.
FUNCTION p12_cut_check {
  PARAMETER prog, now_ut.
  IF NOT prog["ENGINE_LIT"] { RETURN. }
  LOCAL bb IS prog["BB"].
  IF bb["CUT_UT"] < 0 OR now_ut < bb["CUT_UT"] { RETURN. }
  SET bb["CUT_DONE"] TO TRUE.
  IF CTL_DRY OR prog["ENGINE"]:ISTYPE("Engine") { ctl_disarm(prog["ENGINE"]). }
  SET prog["ENGINE_LIT"] TO FALSE.
  SET prog["THR"] TO 0.
  p12_rcs_back(prog).
  SET prog["CUT_FIRED"] TO TRUE.
}

// p12_burn: the BURN phase: the BURNBABY sequence (countdown, prompt, ignition), V97, the powered flight and the displays. Returns a message.
FUNCTION p12_burn {
  PARAMETER prog, state, ks, now_ut, out.
  LOCAL msg IS "".
  LOCAL bb IS prog["BB"].
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  // V34 ends P12 only while a request is up (the V99 prompt or V97), as in P40.
  LOCAL terminating IS ks["TERMINATE"] AND prog["LAST_REQ"].
  LOCAL entr_pressed IS ks["RECYCLE"] OR lm_entr_on_request(ks, 99, 74).

  // ---- V97 (COMFAIL): PRO takes the failure back, ENTR lights the engine again from TIG - 5 s; the stages are not separated again ----
  LOCAL dv_failed IS prog["ENGINE_LIT"] AND prog["DVMON"]["FAILED"].
  IF dv_failed AND pro_pressed {
    dvmon_reset(prog["DVMON"]).
    SET prog["DVSHOWN"] TO FALSE.
    SET dv_failed TO FALSE.
    SET pro_pressed TO FALSE.
    SET msg TO "P12: THRUST MONITOR RESET.".
  } ELSE IF dv_failed AND (ks["RECYCLE"] OR lm_entr_on_request(ks, 97, 74)) {
    p12_engine_off(prog).
    SET prog["IGN_T"] TO -1.
    SET prog["PASS_T0"] TO -1.
    bb_retime(bb, now_ut + DVMON_RETRY_S).
    SET prog["TIG"] TO now_ut + DVMON_RETRY_S.
    dvmon_reset(prog["DVMON"]).
    SET prog["DVSHOWN"] TO FALSE.
    SET dv_failed TO FALSE.
    SET entr_pressed TO FALSE.
    SET msg TO "P12: NEW IGNITION IN " + DVMON_RETRY_S + " S. SETTLE THE PROPELLANT (H) IF IN FLIGHT, THEN PRO.".
  }
  IF dv_failed { SET entr_pressed TO FALSE. }

  // ---- the sequence ----
  LOCAL sq IS bb_step(bb, now_ut, pro_pressed, terminating, entr_pressed).
  LOCAL lit_now IS FALSE.
  IF sq["ENGINE_ON"] AND NOT prog["ENGINE_LIT"] {
    SET msg TO p12_ignite(prog, state, now_ut).
    SET lit_now TO TRUE.
  }
  IF prog["ENGINE_LIT"] {
    LOCAL flight_msg IS p12_powered(prog, state, now_ut).
    IF flight_msg <> "" { SET msg TO flight_msg. }
  }
  // The warp to the countdown, once, a few seconds after V06 N74 appears (not Apollo: KSP's time warp, as P63 and P40; its cancel key stops it).
  IF sq["STATE"] = "COAST" {
    LOCAL warp_ut IS warp_step(prog["WARP"], now_ut, prog["TIG"], 0, 0).          // landed: there is no turn to wait for
    IF warp_ut > 0 {
      ctl_warp_to(warp_ut).
      SET msg TO "P12: WARPING TO " + P63_WARP_LEAD_S + " S BEFORE LIFT-OFF (CANCEL WITH KSP'S WARP CANCEL KEY).".
    }
  }
  IF sq["GOPOST"] {
    p12_next(prog, out, "POST").
    SET msg TO "P12: NO ASCENT (ENTR AT THE PROMPT). NOTHING WAS STAGED.".
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }

  // ---- the display ----
  IF NOT prog["ENDED"] AND prog["PHASE"] = "BURN" {
    IF lit_now {
      p40_show(out, 6, p12_run_noun(prog)).
      SET prog["SHOWN"] TO TRUE.
    } ELSE IF NOT prog["SHOWN"] {
      p40_show(out, 6, 74).
      SET prog["SHOWN"] TO TRUE.
    } ELSE IF sq["VN"] <> "" AND (sq["STATE"] <> prog["LAST_STATE"] OR sq["STATE"] = "PROMPT") AND NOT dv_failed {
      p40_show(out, sq["VN"]:SUBSTRING(1, 2):TONUMBER(0), sq["VN"]:SUBSTRING(4, 2):TONUMBER(0)).
    }
    IF sq["PROMPT"] { SET out["REQUEST"] TO LEXICON("VERB", 99, "NOUN", 74). }
    IF prog["ENGINE_LIT"] AND prog["DVMON"]["FAILED"] {
      SET out["REQUEST"] TO LEXICON("VERB", 97, "NOUN", 74).
      IF NOT prog["DVSHOWN"] {
        SET prog["DVSHOWN"] TO TRUE.
        p40_show(out, 97, 74).
        SET msg TO "P12: ENGINE FAILURE (V97): NO THRUST. PRO RESETS, ENTR TRIES AGAIN, V34 ENDS.".
      }
    }
    SET out["BLANK"] TO sq["BLANK"].
  }
  IF terminating { SET out["REQUEST"] TO FALSE. }
  SET prog["LAST_STATE"] TO sq["STATE"].
  RETURN msg.
}

// p12_step: one cycle. Output keys as p40_step; EXTRA carries TTOGO (seconds to TIG, negative after), P12_YAW and P12_PITCH (N74), P40_VGB (VG in
// body axes, N85 and N94), ABVEL (the inertial speed, N63) and N25.
FUNCTION p12_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL out IS p40_out().
  SET out["PROG_NO"] TO 12.
  LOCAL msg IS "".
  LOCAL att_msg IS p12_attitude(prog).
  p12_cut_check(prog, now_ut).
  LOCAL phase_name IS prog["PHASE"].
  IF phase_name = "BURN" AND prog["CUT_FIRED"] {
    p12_next(prog, out, "POST").                       // this cycle's keys are not read by the next phase
    SET msg TO "P12: ENGINE CUT-OFF".
    p12_mark(prog, state, "cut-off").
  } ELSE IF phase_name = "CHECK" {
    LOCAL imu IS r02(prog["IMU_ON"], prog["IMU_OK"]).
    IF imu["OK"] {
      p12_next(prog, out, "N33").
      SET msg TO prog["START_MSG"].
    } ELSE {
      SET out["ALARM"] TO imu["ALARM"].
      SET prog["ENDED"] TO TRUE.
      SET msg TO "P12: alarm " + imu["ALARM"] + (CHOOSE " (the IMU is not on)." IF imu["ALARM"] = 210 ELSE " (the IMU orientation is not known: run P51, or set IMU_ALIGN to AUTO).").
    }
  } ELSE IF phase_name = "N33" {
    IF p12_ask(prog, ks, out, 6, 33) {
      IF store_loaded(prog["VAULT"], "TIG") {
        SET msg TO p12_accept_tig(prog, state).
        p12_next(prog, out, "N76").
      } ELSE {
        SET ks["OPRERR"] TO TRUE.
        SET msg TO "P12: THE LIFT-OFF TIME IS NOT LOADED (V25 N33 E, FROM THE ASCENT PAD).".
      }
    }
  } ELSE IF phase_name = "N76" {
    IF p12_ask(prog, ks, out, 6, 76) {
      p12_accept_targets(prog, state).
      p12_next(prog, out, "AUTO").
    }
  } ELSE IF phase_name = "AUTO" {
    // The request is only put up when SAS is on. PRO checks again, ENTR or V32 goes on, V34 ends.
    LOCAL sas_on IS prog["ATT"]["MODE"] = "HOLD".
    LOCAL go_on IS FALSE.
    LOCAL ans IS resp_read(ks).
    IF NOT prog["AUTO_CHECKED"] {
      SET prog["AUTO_CHECKED"] TO TRUE.
      IF NOT sas_on { SET go_on TO TRUE. }
    }
    IF ans["TERM"] { SET prog["ENDED"] TO TRUE. }
    ELSE IF ans["PRO"] { IF sas_on { SET prog["SHOWN"] TO FALSE. } ELSE { SET go_on TO TRUE. } }
    ELSE IF ans["V32"] OR lm_entr_on_request(ks, 50, 25) { SET go_on TO TRUE. }
    IF go_on AND NOT prog["ENDED"] {
      LOCAL spot IS p12spot(prog["TIG"], now_ut).
      IF spot["SLIPPED"] {
        SET prog["TIG"] TO spot["TIG"].
        SET out["ALARM"] TO spot["ALARM"].
        SET msg TO "P12 ALARM 1703: TIG TOO CLOSE OR PAST, NOW " + ASC_SPOT_AHEAD_S + " S AHEAD. THE RENDEZVOUS TIMING IS LOST (V34 ENDS).".
      }
      SET prog["BB"] TO bb_new(bb_table_p12(prog["PROFILE"]), prog["TIG"]).
      p12_next(prog, out, "BURN").
    } ELSE IF NOT prog["ENDED"] {
      IF NOT prog["SHOWN"] { SET prog["SHOWN"] TO TRUE. p40_show(out, 50, 25). }
      SET out["REQUEST"] TO LEXICON("VERB", 50, "NOUN", 25).
    }
  } ELSE IF phase_name = "BURN" {
    SET msg TO p12_burn(prog, state, ks, now_ut, out).
  } ELSE {
    LOCAL noun_no IS p12_run_noun(prog).
    IF phase_name = "TRIM" { SET noun_no TO 85. }
    IF p12_ask(prog, ks, out, 16, noun_no) {
      IF phase_name = "POST" { p12_next(prog, out, "TRIM"). } ELSE { SET prog["ENDED"] TO TRUE. }
    }
  }
  // After the cut-off (or ENTR at the prompt): the velocity still to be gained, kept up to date for the trim. No guidance steering.
  IF (prog["PHASE"] = "POST" OR prog["PHASE"] = "TRIM") AND prog["TGT"]:ISTYPE("Lexicon") {
    LOCAL q_live IS servicer_live(prog, prog["QAXIS0"], now_ut).
    LOCAL st IS asc_state(state["R"], state["V"], q_live, state["MU"], prog["RCO"]).
    SET prog["VG"] TO asc_trim(prog["G"], st, prog["TGT"]).
  }
  IF att_msg <> "" { SET msg TO att_msg. }
  IF prog["CONTROLS"] AND NOT prog["ENDED"] AND prog["ATT"]["MODE"] = "AUTO" { ctl_set_command(prog["CMD_DIR"], prog["CMD_UP"], prog["THR"]). }
  // ---- the values the nouns show ----
  LOCAL vg_body IS LIST(0, 0, 0).
  IF prog["GUIDING"] OR prog["PHASE"] = "POST" OR prog["PHASE"] = "TRIM" {
    LOCAL body_vec IS s41_1(prog["VG"], p40_facing()).
    SET vg_body TO LIST(body_vec:X, body_vec:Y, body_vec:Z).
  }
  LOCAL ttogo IS 0.
  IF prog["TIG"] >= 0 { SET ttogo TO prog["TIG"] - now_ut. }
  SET out["EXTRA"] TO LEXICON("TTOGO", ttogo, "P12_YAW", prog["N74"][0], "P12_PITCH", prog["N74"][1], "P40_VGB", vg_body,
                              "ABVEL", state["V"]:MAG, "N25", P40_N25_CODE).
  IF prog["CONTROLS"] OR prog["PHASE"] = "POST" OR prog["PHASE"] = "TRIM" {          // stays up through a V97 relight
    SET out["STATUS"] TO LIST("P12 " + prog["PHASE"] + (CHOOSE ", ATT HOLD" IF prog["ATT"]["MODE"] = "HOLD" ELSE ""),
                              "TGO " + ROUND(prog["G"]["TGO"], 1) + " S   VG " + ROUND(prog["VG"]:MAG, 1) + " M/S",
                              "HEIGHT " + ROUND(p12_height(prog, state)) + " M").
  }
  SET out["MSG"] TO msg.
  SET out["ENDED"] TO prog["ENDED"].
  SET prog["LAST_REQ"] TO out["REQUEST"]:ISTYPE("Lexicon").
  p12_log(prog, state, now_ut, msg, vg_body).
  RETURN out.
}

// p12_end: if P12 took the controls: engine off, the lever back to the RCS, SAS on to hold the attitude. Before ignition nothing was taken.
// This is also what V37 does during the ascent: it shuts the engine off, as in Luminary.
FUNCTION p12_end {
  PARAMETER prog.
  ctl_warp_stop().                          // also before ignition, when nothing else was taken
  IF NOT prog["CONTROLS"] { RETURN. }
  IF CTL_DRY OR prog["ENGINE"]:ISTYPE("Engine") { ctl_burn_end(prog["ENGINE"], TRUE). }
  ELSE { ctl_ullage(FALSE). ctl_release(TRUE). }
  p12_rcs_back(prog).
  SET prog["ENGINE_LIT"] TO FALSE.
  SET prog["CONTROLS"] TO FALSE.
}
