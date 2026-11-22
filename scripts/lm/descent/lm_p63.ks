// lm_p63.ks -- the P63 programme (milestone 3): start, one step per main-loop cycle, end.
//
// P63 is the lunar landing braking phase. It joins the pieces built in the earlier files:
//   lm_ignition.ks  finds the ignition time (IGNALG) and runs the BURNBABY countdown (seq_*)
//   lm_guidance.ks  the braking guidance, once the engine has zoomed to full throttle
//   lm_control.ks   turns the commands into steering, throttle, ullage; the override; the simulated radar lamps
// Luminary source: THE_LUNAR_LANDING.agc (P63LM) and BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc.
//
//   p63_start(plan, site_lat, site_lng, land_vec, wm_vec)  returns the programme state (a LEXICON), or a lexicon with a
//                                                          "REFUSED" key holding the reason
//   p63_step(prog, state, derived, ks)                     one cycle; returns what the main loop shows
//   p63_end(prog)                                          gives the controls back
//
// What the pilot sees (spec sections 4 and 8): the programme sets the verb and noun at each change of state (V06 N62
// countdown, V99 N62 flashing "please enable engine", V06 N63 once the engine is lit); the pilot can then change the
// noun freely. PRO enables the engine; the SAS button shows the attitude mode (lit = ATT HOLD); only a strong stick input enters ATT HOLD, SAS off returns to AUTO.
//
// When the time-to-go falls below TENDBRAK the step returns HANDOVER = TRUE (once) and the main loop starts P64 (lm_p64.ks),
// which takes this programme's state over: the engine, attitude mode, radar and window bookkeeping carry on without a gap.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/planner/lm_plan.ks").
RUNONCEPATH("0:/lm/descent/lm_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_ignition.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").

GLOBAL P63_MIN_LEAD_S IS 40.               // chosen: P63 refuses to start when the ignition is closer than this, s. The countdown
                                           // starts at TIG-35, and the ship needs time to turn and the propellant to settle
GLOBAL P63_LOG_PATH IS "0:/lm/logs/p63.log".    // one line per cycle, read back after a flight

// p63_predict: the ship's coasting state at UT t_ut, in the live raw axes (which turn with the Moon). The orbit
// prediction (POSITIONAT, VELOCITYAT) is in fixed (inertial) axes, so the result is turned back by the Moon's spin
// since t0 (the time the prediction was made), the opposite sense to the planner's plan_site_at. POSITIONAT is measured
// from the ship's position NOW, so the body's position is subtracted in the same call. Both include maneuver nodes
// still ahead. The past cannot be predicted: times before t0 are treated as t0.
FUNCTION p63_predict {
  PARAMETER t0, wm_vec, t_ut.
  LOCAL t_use IS MAX(t_ut, t0).
  LOCAL r_in IS POSITIONAT(SHIP, t_use) - SHIP:BODY:POSITION.
  LOCAL v_in IS VELOCITYAT(SHIP, t_use):ORBIT.
  RETURN LEXICON("R", plan_spin_rotate(r_in, wm_vec, -(t_use - t0)), "V", plan_spin_rotate(v_in, wm_vec, -(t_use - t0))).
}

// p63_pick_window: "UP" or "KEEP" (see P63_WINDOW_MODE in lm_constants.ks): the plan's choice, or the default when the
// plan has none or an unknown one.
FUNCTION p63_pick_window {
  PARAMETER plan.
  IF plan:ISTYPE("Lexicon") {
    IF plan:HASKEY("WINDOW_MODE") {
      IF plan["WINDOW_MODE"] = "UP" OR plan["WINDOW_MODE"] = "KEEP" { RETURN plan["WINDOW_MODE"]. }
    }
  }
  RETURN P63_WINDOW_MODE.
}

FUNCTION p63_refuse {
  PARAMETER why.
  RETURN LEXICON("REFUSED", why).
}

// p63_start: check the conditions, find the ignition time and take control. plan is the saved planner result (or FALSE),
// site_lat and site_lng the landing site in use, land_vec and wm_vec as in lm_frame.ks. Refuses (returns a lexicon with
// "REFUSED") when there is no usable plan, the plan is for another site, the planned PDI has passed, the orbit is not
// bound, there is no engine, IGNALG cannot find an ignition time, or the ignition is less than P63_MIN_LEAD_S away.
FUNCTION p63_start {
  PARAMETER plan, site_lat, site_lng, land_vec, wm_vec.
  LOCAL now_ut IS TIME:SECONDS.
  IF NOT plan:ISTYPE("Lexicon") { RETURN p63_refuse("no saved deorbit plan: run the planner first"). }
  IF NOT (plan:HASKEY("T_PDI") AND plan:HASKEY("SITE_LAT") AND plan:HASKEY("SITE_LNG")) { RETURN p63_refuse("the saved plan is incomplete"). }
  LOCAL lng_diff IS MOD(ABS(plan["SITE_LNG"] - site_lng), 360).
  IF lng_diff > 180 { SET lng_diff TO 360 - lng_diff. }
  IF ABS(plan["SITE_LAT"] - site_lat) > 0.01 OR lng_diff > 0.01 { RETURN p63_refuse("the saved plan is for another landing site"). }
  IF SHIP:BODY:NAME <> BODY_NAME { RETURN p63_refuse("not over the " + BODY_NAME). }
  IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN p63_refuse("the orbit is not bound"). }
  IF plan["T_PDI"] < now_ut { RETURN p63_refuse("the planned PDI time has passed"). }
  LOCAL eng IS ctl_find_engine().
  IF NOT eng:ISTYPE("Engine") { RETURN p63_refuse("no engine found"). }
  LOCAL f_max_n IS eng:POSSIBLETHRUSTAT(0) * 1000.
  LOCAL mass_kg IS SHIP:MASS * 1000.
  // @ makes a delegate of the function; :BIND fixes its first two arguments (t0 and the spin), so IGNALG can call it
  // with just a time (kOS docs, language/delegates).
  LOCAL ign IS ign_solve(p63_predict@:BIND(now_ut, wm_vec), land_vec, wm_vec, mass_kg, f_max_n, SHIP:BODY:MU, plan["T_PDI"]).
  IF NOT ign["OK"] { RETURN p63_refuse("ignition time: " + ign["WHY"]). }
  IF ign["TIG"] < now_ut + P63_MIN_LEAD_S { RETURN p63_refuse("the ignition time is less than " + P63_MIN_LEAD_S + " s away"). }
  LOCAL win0_vec IS ctl_window_face_vec().
  ctl_start().
  IF EXISTS(ROD_LOG_PATH) { DELETEPATH(ROD_LOG_PATH). }     // rod.log is always written (one line per ROD click), whatever LM_LOG says
  IF LM_LOG {
  IF EXISTS(P63_LOG_PATH) { DELETEPATH(P63_LOG_PATH). }
  LOG "UT,STATE,TTOGO,TGO,ALARM,THR,MODE,ALT_RADAR,HCALC,ABVEL,HDOT,RGU_X,RGU_Y,RGU_Z,VGU_X,VGU_Y,VGU_Z,ATT_ERR_DEG,ALT_LAMP,VEL_LAMP,DV_GAINED,THRUST_FRAC,STEER_LOCKED" TO P63_LOG_PATH.
  LOG "# P63 start: TIG " + ROUND(ign["TIG"], 1) + " (in " + ROUND(ign["TIG"] - now_ut, 1) + " s), IGNALG passes " + ign["ITER"]
      + ", out of plane " + ROUND(ign["OUTOFPLN"]) + " m, full thrust " + ROUND(f_max_n / 1000, 2) + " kN, mass " + ROUND(SHIP:MASS, 3) + " t" TO P63_LOG_PATH.
  }
  RETURN LEXICON("REFUSED", "", "PROG_NO", 63, "SEQ", seq_new(ign["TIG"]), "WINDOW_MODE", p63_pick_window(plan), "TURNED", FALSE, "FORE0", SHIP:FACING:FOREVECTOR, "WIN0", win0_vec, "WCMD", win0_vec, "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "ROD", rod_new(), "ROD_START", FALSE, "HIGHGATE", FALSE, "GO", FALSE, "DVMON", dvmon_new(), "DVSHOWN", FALSE, "LAST_REQ", FALSE, "N61_SHOWN", FALSE, "WARP", warp_new(), "ENGINE", eng,
                 "LAND", land_vec, "WM", wm_vec, "TIG", ign["TIG"], "BURN_DIR", ign["THRUST_DIR"], "OUTOFPLN", ign["OUTOFPLN"],
                 "TGO", IGN_TGO_SEED, "THR", 0, "GP", LEXICON(), "ZOOMED", FALSE, "ENGINE_LIT", FALSE, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", now_ut, "HANDOFF_T", -1, "LAST_STATE", "", "LAST_ALARM", 0, "ENDED", FALSE).
}

// p63_step: one cycle. state is nav_state(), derived is nav_derived(...), ks the key state (reads and clears PRO).
// Returns a LEXICON for the main loop: SET_VERB and SET_NOUN (a number to show now, -1 for no change), KEY_REL,
// BLANK, FLASH, ALARM (0 or the alarm code, shown as the PROG lamp), ALT_LAMP, VEL_LAMP, EXTRA (values for the P63 nouns), MSG (text to print, "" for none), ENDED,
// HANDOVER (TRUE once, when braking is over: start P64) and PROG_NO (63).
FUNCTION p63_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL dt IS MAX(0, now_ut - prog["T_LAST"]).
  SET prog["T_LAST"] TO now_ut.
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  LOCAL msg IS "".
  // V34 ENTR ends the programme in every state, including the enable prompt (where the verb would otherwise be forced
  // back to 99 each cycle): the sequence is told to terminate, which switches the ullage off.
  // Luminary VBTERM only answers a flashing request: P63's only one is the V99 enable prompt (BURN_BABY_BURN: TERMINATE goes to
  // GOTOPOOH, which turns the ullage off). Outside the prompt V34 does nothing. LAST_STATE is the state of the previous cycle.
  // V34 (ks["TERMINATE"], set by the core only while a request is pending) ends the programme: it answers the flashing V06 N61 at the start and the V99
  // enable prompt (LAST_REQ: a request was up last cycle). With no request pending it does nothing.
  LOCAL terminating IS ks["TERMINATE"] AND prog["LAST_REQ"].        // the N61 request, the V99 prompt or the V97 display
  // The first display is V06 N61 flashing (Luminary: ASTNCLOK, "to reset his event timer to agree with TIG"). PRO answers it (GO): the programme then
  // turns and warps. Until then it holds the attitude it started in and does not warp (the sequence and TIG are fixed and run on). Unanswered, it
  // moves on by itself at TIG-35, where the real clock task blanks the display (the sequence leaves COAST).
  IF pro_pressed AND NOT prog["GO"] { SET prog["GO"] TO TRUE. }

  // ---- V97 (engine failure, Luminary COMFAIL): ENTR at the display lights the engine again from TIG-5; PRO takes the failure back and monitors again ----
  LOCAL dv_failed IS prog:HASKEY("DVMON") AND prog["ENGINE_LIT"] AND prog["DVMON"]["FAILED"].
  IF dv_failed AND pro_pressed { dvmon_reset(prog["DVMON"]). SET prog["DVSHOWN"] TO FALSE. SET dv_failed TO FALSE. SET msg TO "P63: THRUST MONITOR RESET.". }
  ELSE IF dv_failed AND ks["ENTER"] {
    ctl_engine_off(prog["ENGINE"]).
    SET prog["ENGINE_LIT"] TO FALSE.
    SET prog["ZOOMED"] TO FALSE.
    SET prog["THR"] TO 0.
    SET prog["GP"] TO LEXICON().
    SET prog["TGO"] TO IGN_TGO_SEED.
    SET prog["TIG"] TO now_ut + DVMON_RETRY_S.
    SET prog["SEQ"] TO seq_new(prog["TIG"]).
    dvmon_reset(prog["DVMON"]).
    SET prog["DVSHOWN"] TO FALSE.
    SET dv_failed TO FALSE.
    SET msg TO "P63: NEW IGNITION IN " + DVMON_RETRY_S + " S.".
  }

  // ---- the sequence: countdown, ullage, enable prompt, ignition, zoom ----
  LOCAL sq IS seq_step(prog["SEQ"], now_ut, pro_pressed, terminating).
  IF sq["STATE"] <> "COAST" { SET prog["GO"] TO TRUE. }
  IF sq["ULLAGE"] <> prog["ULLAGE_ON"] {
    ctl_ullage(sq["ULLAGE"]).
    SET prog["ULLAGE_ON"] TO sq["ULLAGE"].
  }
  IF sq["ENGINE_ON"] AND NOT prog["ENGINE_LIT"] {
    ctl_engine_on(prog["ENGINE"]).
    SET prog["ENGINE_LIT"] TO TRUE.
    SET prog["THR"] TO THR_MIN_FRAC.          // Apollo lights the engine at minimum throttle and zooms to full 26 s later
    SET msg TO "P63: ENGINE ON".
  }
  IF sq["ZOOM"] {
    SET prog["ZOOMED"] TO TRUE.
    SET prog["THR"] TO 1.
    SET msg TO "P63: THROTTLE UP, BRAKING GUIDANCE ENGAGED".
  }

  // ---- guidance (from ignition on, so the time-to-go display is live; it steers only after the zoom) ----
  LOCAL gp IS prog["GP"].
  IF prog["ENGINE_LIT"] AND derived["VALID"] {
    SET prog["TGO"] TO MAX(1, prog["TGO"] - dt).     // the old time-to-go, moved on by the time since
    LOCAL cg_last IS FALSE.
    IF gp:HASKEY("CG") { SET cg_last TO gp["CG"]. }
    SET gp TO guid_pass(state, prog["LAND"], prog["WM"], prog["TGO"], prog["THR"], guid_targets_brake(), cg_last).
    IF gp["VALID"] { SET prog["TGO"] TO gp["TGO"]. SET prog["GP"] TO gp. }
  }

  // ---- the commanded attitude and throttle ----
  LOCAL dir_cmd IS prog["BURN_DIR"].
  IF prog["ZOOMED"] AND gp:HASKEY("AFC") {
    SET dir_cmd TO cg_unapply(gp["CG"], gp["AFC"]).
    SET prog["THR"] TO gp["THR"].
  }
  // The crew window (P63_WINDOW_MODE, lm_constants.ks). UP: held toward straight up from the Moon throughout (the later
  // missions, per the user). KEEP, as Luminary 099 (lm_control.ks): the shortest turn from the attitude P63 started in (the
  // ship keeps its roll) until it has turned to the burn attitude; after that (and in the burn) the ship's own roll is held,
  // and in AUTO the roll stick may turn it (X-axis override). TURNED latches once the attitude has been reached.
  IF prog["WINDOW_MODE"] = "UP" {
    LOCAL up_proj IS win_perp(state["R"], dir_cmd).
    IF up_proj:MAG > 0 { SET prog["WCMD"] TO up_proj. }
  } ELSE {
    IF NOT prog["TURNED"] AND ctl_att_error_deg() < P63_SETTLE_ERR_DEG { SET prog["TURNED"] TO TRUE. }
    IF prog["TURNED"] OR prog["ENGINE_LIT"] {
      LOCAL stick IS ctl_pilot_roll().
      IF prog["ATT"]["MODE"] <> "AUTO" { SET stick TO 0. }
      SET prog["WCMD"] TO win_hold(ctl_window_face_vec(), dir_cmd, prog["WCMD"], stick).
    } ELSE {
      SET prog["WCMD"] TO win_min_rotation(prog["FORE0"], prog["WIN0"], dir_cmd).
    }
  }
  IF prog["GO"] { ctl_set_command(dir_cmd, prog["WCMD"], prog["THR"]). }

  // ---- turn, then warp: once the ship holds the burn attitude, warp to P63_WARP_LEAD_S before ignition (once only) ----
  // After the command above, so the attitude error is measured against this cycle's command, not the previous one.
  LOCAL warp_ut IS 0.
  IF prog["GO"] { SET warp_ut TO warp_step(prog["WARP"], now_ut, prog["TIG"], ctl_att_error_deg(), ctl_rate_deg_s()). }
  IF warp_ut > 0 {
    ctl_warp_to(warp_ut).
    SET msg TO "P63: ATTITUDE REACHED. WARPING TO " + P63_WARP_LEAD_S + " S BEFORE IGNITION (CANCEL WITH KSP'S WARP CANCEL KEY).".
  }

  // ---- handoff to P64: the main loop starts P64 on the "HANDOVER" flag below (it takes this programme's state over) ----
  LOCAL handover IS FALSE.
  // A ROD click with SAS on, once the engine is lit and zoomed, asks for P66 at once: P63 hands over to P64, which hands over to P65, which starts in P66.
  LOCAL rod_msg IS "".
  IF burn_rod_start(prog, prog["ENGINE_LIT"] AND prog["ZOOMED"]) { SET rod_msg TO "P63: ROD CLICK WITH SAS ON. P66 RATE OF DESCENT IS ASKED FOR.". }
  IF prog:HASKEY("ROD_DROP") AND prog["ROD_DROP"] <> "" AND msg = "" { SET msg TO prog["ROD_DROP"]. }
  IF prog["ZOOMED"] AND ((gp:HASKEY("HANDOFF") AND gp["HANDOFF"]) OR prog["ROD_START"]) AND prog["HANDOFF_T"] < 0 {
    SET prog["HANDOFF_T"] TO now_ut.
    SET handover TO TRUE.
    SET msg TO "P63 COMPLETE (time to go below " + TENDBRAK + " s). P64 STARTS.".
    IF rod_msg <> "" { SET msg TO rod_msg. }
  }

  // ---- attitude mode, coast deadband, radar lamps, delta-v (shared with P64) ----
  LOCAL shared_msg IS burn_shared_step(prog, state, derived, dt, sq["STATE"] <> "COAST", "P63").
  IF shared_msg <> "" { SET msg TO shared_msg. }

  // ---- what the display should show ----
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  LOCAL request IS FALSE.
  IF NOT prog["GO"] {
    IF NOT prog["N61_SHOWN"] OR ks["RECYCLE"] { SET set_verb TO 6. SET set_noun TO 61. SET prog["N61_SHOWN"] TO TRUE. }     // V32 shows it again
    SET request TO LEXICON("VERB", 6, "NOUN", 61).
  } ELSE IF NOT terminating AND sq["VN"] <> "" AND (sq["STATE"] <> prog["LAST_STATE"] OR sq["STATE"] = "PROMPT") {
    SET set_verb TO sq["VN"]:SUBSTRING(1, 2):TONUMBER(0).
    SET set_noun TO sq["VN"]:SUBSTRING(4, 2):TONUMBER(0).
  }
  IF sq["STATE"] <> prog["LAST_STATE"] AND sq["STATE"] = "PROMPT" { SET msg TO "P63: PLEASE ENABLE ENGINE: PRESS PRO". }
  SET prog["LAST_STATE"] TO sq["STATE"].
  // Alarm 1406: the time-to-go solver did not settle. The code is returned every cycle (the main loop lights PROG); the
  // message is printed once, when the alarm first appears or changes.
  LOCAL alarm_no IS 0.
  IF gp:HASKEY("ALARM") { SET alarm_no TO gp["ALARM"]. }
  IF alarm_no <> prog["LAST_ALARM"] {
    IF alarm_no > 0 { SET msg TO "P63 ALARM " + alarm_no + ": TIME-TO-GO NOT CONVERGED. THE GUIDANCE KEEPS THE LAST TIME-TO-GO." . }
    SET prog["LAST_ALARM"] TO alarm_no.
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }
  IF sq["PROMPT"] { SET request TO LEXICON("VERB", 99, "NOUN", 62). }          // the V99 N62 enable prompt flashes until PRO
  IF terminating { SET request TO FALSE. }
  // The thrust monitor runs once the engine is lit (after this cycle's delta-v); a failure makes V97 N62 flash until PRO, ENTR or V34 answers it.
  IF prog:HASKEY("DVMON") AND prog["ENGINE_LIT"] AND NOT terminating {
    dvmon_step(prog["DVMON"], prog["DV"], now_ut).
    IF prog["DVMON"]["FAILED"] {
      IF NOT request:ISTYPE("Lexicon") { SET request TO LEXICON("VERB", 97, "NOUN", 62). }
      IF NOT prog["DVSHOWN"] { SET prog["DVSHOWN"] TO TRUE. SET msg TO "P63: ENGINE FAILURE (V97): NO THRUST. PRO RESETS, ENTR TRIES AGAIN, V34 ENDS.". SET set_verb TO 97. SET set_noun TO 62. }
      ELSE IF set_verb >= 0 { SET set_verb TO 97. SET set_noun TO 62. }          // a state change must not take the display off V97
    }
  }
  SET prog["LAST_REQ"] TO request:ISTYPE("Lexicon").
  LOCAL extra IS LEXICON("TTOGO", sq["TTOGO"], "DVTOTAL", prog["DV"], "OUTOFPLN", prog["OUTOFPLN"]).
  IF prog["ENGINE_LIT"] { SET extra["TTFDISP"] TO prog["TGO"]. }

  p63_log(prog, sq, gp, state, derived).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", sq["BLANK"],
                 "REQUEST", request, "FLASH", FALSE, "ALARM", alarm_no, "ALT_LAMP", prog["RAD"]["ALT_LAMP"], "VEL_LAMP", prog["RAD"]["VEL_LAMP"],
                 "EXTRA", extra, "MSG", msg, "ENDED", prog["ENDED"], "HANDOVER", handover, "PROG_NO", 63).
}

// burn_rod_start: the ROD clicks waiting from the H and N keys (prog["ROD"], P63 and P64 only) start P66 early: a click made with SAS on (ATT HOLD),
// and with the engine lit and zoomed when engine_ok says so, sets prog["ROD_START"] (P65 then starts in P66). Any other click is thrown away (in AUTO the
// click count is zeroed every pass, as in P66) and prog["ROD_DROP"] says why, for the caller's message. Returns TRUE the cycle the flag is set. A programme with no ROD (the J set) is ignored.
FUNCTION burn_rod_start {
  PARAMETER prog, engine_ok.
  IF NOT prog:HASKEY("ROD") { RETURN FALSE. }
  // ROD_DROP says why a click was thrown away this cycle ("" when none was, or it was used); the caller shows it. Every click taken is logged (rod_log).
  SET prog["ROD_DROP"] TO "".
  LOCAL clicks IS rod_take(prog["ROD"]).
  IF clicks = 0 OR prog["ROD_START"] { RETURN FALSE. }
  LOCAL sas_now IS ctl_sas_read(prog["ATT"]["MODE"] = "HOLD").
  IF NOT engine_ok { SET prog["ROD_DROP"] TO "ROD CLICK IGNORED: ENGINE NOT LIT AND ZOOMED YET.". }
  ELSE IF NOT sas_now { SET prog["ROD_DROP"] TO "ROD CLICK IGNORED: SAS IS OFF (AUTO). TURN SAS ON FIRST.". }
  rod_log("burn clicks " + clicks + " sas " + sas_now + " engine_ok " + engine_ok + " -> " + (CHOOSE "USED" IF prog["ROD_DROP"] = "" ELSE prog["ROD_DROP"])).
  IF prog["ROD_DROP"] <> "" { RETURN FALSE. }
  SET prog["ROD_START"] TO TRUE.
  RETURN TRUE.
}

// burn_steer_off: PRO or ENTER in P65 and P66 dropped the steering target (prog["STEER_OFF"]); the other programmes never set it.
FUNCTION burn_steer_off {
  PARAMETER prog.
  IF prog:HASKEY("STEER_OFF") { RETURN prog["STEER_OFF"]. }
  RETURN FALSE.
}

// burn_shared_step: the per-cycle work P63 and P64 both do, in the order P63 did it (it moved here from p63_step unchanged;
// P64 calls it too). Returns a message to print, "" for none. tag is "P63" or "P64" for the messages. dt is the time since
// the last cycle, s. keep_lock is TRUE when the steering lock must stay on (the countdown and the burn: only P63's COAST
// state may let the ship drift inside the deadband; in P64 the engine is always burning).
//   1. Attitude mode. The SAS button is the AUTO / ATT HOLD switch (lit = ATT HOLD), as in Luminary where only the switch
//      selects the mode. Going to HOLD gives the pilot stability assist; coming back to AUTO takes the steering lock again
//      and restarts the window's turn bookkeeping.
//   2. Coast deadband (AUTO only): the steering lock is dropped while the attitude is within the deadband and taken again
//      when it passes the re-lock angle.
//   3. Simulated landing radar (ALT and VEL lamps).
//   4. Delta-v gained since ignition (N62 R3): thrust acceleration summed over time.
FUNCTION burn_shared_step {
  PARAMETER prog, state, derived, dt, keep_lock, tag.
  LOCAL msg IS "".
  LOCAL mode_before IS prog["ATT"]["MODE"].
  att_step(prog["ATT"], ctl_sas_read(mode_before = "HOLD")).
  IF prog["ATT"]["MODE"] <> mode_before {
    IF prog:HASKEY("STEER_OFF") { SET prog["STEER_OFF"] TO FALSE. }          // any attitude-mode change gives the steering target back
    IF prog["ATT"]["MODE"] = "HOLD" { ctl_hold(). SET msg TO tag + ": ATTITUDE HOLD (SAS on). SWITCH SAS OFF FOR AUTO.". }
    ELSE { ctl_auto(). SET prog["DB"]["LOCKED"] TO TRUE. SET prog["FORE0"] TO SHIP:FACING:FOREVECTOR. SET prog["WIN0"] TO ctl_window_face_vec(). SET prog["TURNED"] TO FALSE. SET msg TO tag + ": AUTO ATTITUDE RESUMED". }   // ctl_auto takes the steering lock
  }
  IF prog["ATT"]["MODE"] = "AUTO" AND NOT burn_steer_off(prog) {
    LOCAL locked_before IS prog["DB"]["LOCKED"].
    db_step(prog["DB"], ctl_att_error_deg(), ctl_rate_deg_s(), keep_lock).
    IF prog["DB"]["LOCKED"] <> locked_before {
      IF prog["DB"]["LOCKED"] { ctl_steer_lock(). } ELSE { ctl_steer_release(). }
    }
  }
  IF derived["VALID"] { radar_step(prog["RAD"], derived["HCALC"], state["ALT_RADAR"], derived["ABVEL"], 0, prog["HIGHGATE"]). }
  IF prog["ENGINE_LIT"] AND state["MASS"] > 0 { SET prog["DV"] TO prog["DV"] + state["THRUST_NOW"] / state["MASS"] * dt. }
  RETURN msg.
}

// p63_log: one line per cycle to P63_LOG_PATH (the terminal cannot be copied from, so the flight is read back from here).
FUNCTION p63_log {
  PARAMETER prog, sq, gp, state, derived.
  IF CTL_DRY { RETURN. }
  LOCAL alarm_no IS 0.
  LOCAL rgu_vec IS V(0, 0, 0).
  LOCAL vgu_vec IS V(0, 0, 0).
  IF gp:HASKEY("ALARM") { SET alarm_no TO gp["ALARM"]. SET rgu_vec TO gp["RGU"]. SET vgu_vec TO gp["VGU"]. }
  LOCAL abvel IS 0.
  LOCAL hdot IS 0.
  LOCAL hcalc IS 0.
  IF derived["VALID"] { SET abvel TO derived["ABVEL"]. SET hdot TO derived["HDOT"]. SET hcalc TO derived["HCALC"]. }
  LOCAL att_err IS VANG(SHIP:FACING:FOREVECTOR, CTL_GOAL_DIR).
  // The thrust the engine is really giving as a fraction of its full thrust, to compare with the throttle setting THR:
  // on a RealFuels engine the setting may not equal the thrust fraction (flight test 1 checks this).
  LOCAL thrust_frac IS 0.
  IF state["THRUST"] > 0 { SET thrust_frac TO state["THRUST_NOW"] / state["THRUST"]. }
  IF LM_LOG { LOG "" + ROUND(state["T"], 2) + "," + sq["STATE"] + "," + ROUND(sq["TTOGO"], 1) + "," + ROUND(prog["TGO"], 1) + "," + alarm_no + ","
      + ROUND(CTL_THR, 3) + "," + prog["ATT"]["MODE"] + "," + ROUND(state["ALT_RADAR"]) + "," + ROUND(hcalc) + "," + ROUND(abvel, 1) + ","
      + ROUND(hdot, 1) + "," + ROUND(rgu_vec:X) + "," + ROUND(rgu_vec:Y) + "," + ROUND(rgu_vec:Z) + ","
      + ROUND(vgu_vec:X, 1) + "," + ROUND(vgu_vec:Y, 1) + "," + ROUND(vgu_vec:Z, 1) + "," + ROUND(att_err, 2) + ","
      + prog["RAD"]["ALT_LAMP"] + "," + prog["RAD"]["VEL_LAMP"] + "," + ROUND(prog["DV"], 1) + ","
      + ROUND(thrust_frac, 3) + "," + prog["DB"]["LOCKED"] TO P63_LOG_PATH. }
}

// p63_end: give everything back to the pilot: ullage off, steering and throttle released (the throttle lever is set to the
// last commanded throttle first, so the engine does not snap off; see ctl_release). If the engine is burning the ship is
// handed over in SAS stability assist, so it holds its attitude and does not tumble.
FUNCTION p63_end {
  PARAMETER prog.
  ctl_warp_stop().                          // an unfinished P63 warp must not run on after the programme
  ctl_ullage(FALSE).
  ctl_release(prog["ENGINE_LIT"]).
}
