// lm_p65.ks -- the P65 and P66 programmes (milestone 5): final descent and the pilot's rate-of-descent control.
//   p65_start(prog)                      takes P64's programme state over (engine, attitude mode, deadband, radar and window
//                                        bookkeeping carry on without a gap) and returns it as the P65 state
//   p65_sample(prog)                     read the throttle lever into the ROD click detector (call every 0.02 s)
//   p65_step(prog, state, derived, ks)   one cycle; returns what the main loop shows (the same keys as p64_step, plus CONTACT)
//   p65_end(prog)                        gives the controls back (the same as P63's)
//
// P65 (automatic landing) and P66 (rate of descent) are one guidance phase in Luminary (WCHPHASE 2, VERTGUID, source 897-899) and
// the pilot switches between them in flight, so they live in one file, P66 being a mode of the programme state ("MODE").
//   P65: the thrust direction and throttle come from the velocity-nulling law (guid_pass_vert): ACG = (V2FG - VGU)/TAUVERT.
//   P66: starts at a ROD click made with SAS on (ATT HOLD): in Luminary (GUILDEN, source 134-216) a click in AUTO is thrown away
//        (the count is zeroed every AUTO pass, 224-225) and ATT HOLD alone does nothing. The throttle holds the
//        commanded descent rate VDG, which each ROD click changes by RODSCALE (guid_rod_throttle). The thrust direction is not
//        updated any more (source 919-920: P66VERT never reaches AFCCALC1 or STEER?): the ship keeps the last P65 direction in
//        AUTO, and with SAS on the pilot flies it.
//   There is no window logic in this phase (source 72-81): the ship's own roll is held (win_hold), with the roll stick in AUTO.
//   Contact: the CONTACT lamp lights at touchdown (contact_test) and the engine is cut off P66_CUTOFF_DELAY_S later unless the
//   pilot stopped it first; the programme then shows P68 (landing confirmation) and ends.
//
// Simplifications (spec section 11): the throttle lever's Shift and Ctrl keys stand in for the ROD switch; ROD clicks are applied
// every cycle (Luminary applies them once a second); the engine is cut off automatically after contact (the crew did it by hand);
// contact comes from the ship's status (no contact probes); no P67, no landing radar reasonableness test.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_guidance.ks").
RUNONCEPATH("0:/lm/lm_control.ks").
RUNONCEPATH("0:/lm/lm_p63.ks").                 // burn_shared_step and p63_end, which P65 shares

GLOBAL P65_LOG_PATH IS "0:/lm/p65.log".          // one line per cycle, read back after a flight

// p65_start: P64 has just reported HANDOVER. prog is P64's programme lexicon and is changed and returned as P65's. The guidance
// axes P64 left (gp["CG"]) stay frozen for the vertical phase; the throttle lever is centred so both keys have room.
FUNCTION p65_start {
  PARAMETER prog.
  SET prog["PROG_NO"] TO 65.
  SET prog["MODE"] TO "P65".
  SET prog["VDG"] TO 0.                      // the commanded descent rate in P66 (up positive); set to HDOT when P66 starts
  SET prog["CG"] TO FALSE.
  IF prog["GP"]:HASKEY("CG") { SET prog["CG"] TO prog["GP"]["CG"]. }
  SET prog["ROD"] TO rod_new().
  SET prog["TRIM"] TO 0.                     // the thrust trim (trim_step)
  SET prog["SAMPLES"] TO 0.                  // lever samples since the last cycle (logged, to see how often the lever is read)
  SET prog["CT"] TO contact_new().
  SET prog["SHOWN"] TO "".                   // which mode the V06 N60 display was last requested for
  SET prog["WINDOW_MODE"] TO "KEEP".         // no window logic in the vertical phase: the ship's own roll is held
  SET prog["ROD_TOTAL"] TO 0.
  SET prog["HANDOFF_T"] TO -1.
  SET prog["LAST_ALARM"] TO 0.
  ctl_lever_centre().
  IF LM_LOG AND NOT CTL_DRY {
    IF EXISTS(P65_LOG_PATH) { DELETEPATH(P65_LOG_PATH). }
    LOG "UT,MODE,VDG,HDOT,HCALC,ABVEL,VHORIZ,THR,THRUST_FRAC,ATT_ERR_DEG,ROD_TOTAL,CONTACT,STATUS,ALT_RADAR,ALT_LAMP,VEL_LAMP,ATT_MODE,SAMPLES,TRIM" TO P65_LOG_PATH.
    LOG "# P65 start: mass " + ROUND(SHIP:MASS, 3) + " t, SAS " + SAS TO P65_LOG_PATH.
  }
  RETURN prog.
}

// p65_sample: read the throttle lever into the ROD click detector and re-centre it when the detector asks. The main loop calls it
// every 0.02 s so a key tap shorter than one 0.25 s cycle still counts.
FUNCTION p65_sample {
  PARAMETER prog.
  SET prog["SAMPLES"] TO prog["SAMPLES"] + 1.
  rod_sample(prog["ROD"], ctl_pilot_throttle(), TIME:SECONDS).
  IF prog["ROD"]["RECENTRE"] {
    SET prog["ROD"]["RECENTRE"] TO FALSE.
    ctl_lever_centre().
  }
}

// p65_trimmed: the throttle to command: the one guidance gave, or, when a low thrust is wanted (under THR_TRIM_BAND) and the engine
// is giving thrust, the one for the wanted thrust plus the trim, which follows the error between wanted and measured thrust (trim_step).
FUNCTION p65_trimmed {
  PARAMETER prog, thr_given, wanted, state, dt.
  IF wanted < 0 OR wanted >= THR_TRIM_BAND OR state["THRUST"] <= 0 { RETURN thr_given. }
  SET prog["TRIM"] TO trim_step(prog["TRIM"], wanted, state["THRUST_NOW"] / state["THRUST"], dt).
  RETURN thr_command(wanted + prog["TRIM"]).
}

// p65_step: one cycle, the same arguments as p64_step. Returns the same keys (SET_VERB, SET_NOUN, KEY_REL, BLANK, FLASH, ALARM,
// ALT_LAMP, VEL_LAMP, EXTRA, MSG, ENDED, HANDOVER (always FALSE), PROG_NO: 65, 66, or 68 on the cycle the engine is cut off) and
// CONTACT (the lamp).
FUNCTION p65_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL dt IS MAX(0, now_ut - prog["T_LAST"]).
  SET prog["T_LAST"] TO now_ut.
  SET ks["PRO"] TO FALSE.
  LOCAL msg IS "".
  LOCAL terminating IS ks["VERB"] = 34.

  // ---- mode: the first ROD click made with SAS on starts P66 ----
  LOCAL clicks IS rod_take(prog["ROD"]).
  LOCAL sas_now IS ctl_sas_read(prog["ATT"]["MODE"] = "HOLD").
  // ROD clicks are used only in ATT HOLD (SAS on): in AUTO the click count is zeroed every pass (source 224-225).
  IF clicks <> 0 AND NOT sas_now {
    SET clicks TO 0.
    SET msg TO "ROD CLICK IGNORED IN AUTO: SWITCH SAS ON (ATT HOLD) FIRST, AS IN THE LM.".
  }
  IF prog["MODE"] = "P65" AND clicks <> 0 AND derived["VALID"] {
    SET prog["MODE"] TO "P66".
    SET prog["PROG_NO"] TO 66.
    SET prog["VDG"] TO derived["HDOT"].
    SET msg TO "P66: RATE OF DESCENT. SHIFT RAISES THE COMMANDED RATE, CTRL LOWERS IT.".
  }
  IF prog["MODE"] = "P66" AND clicks <> 0 {
    SET prog["VDG"] TO prog["VDG"] + clicks * RODSCALE.
    SET prog["ROD_TOTAL"] TO prog["ROD_TOTAL"] + clicks.
    SET msg TO msg + " P66: COMMANDED DESCENT RATE " + ROUND(ms_to_fps(prog["VDG"]), 1) + " FT/S (" + ROUND(prog["VDG"], 2) + " M/S, UP POSITIVE).".
  }

  // ---- guidance: P65 steers and throttles, P66 only throttles ----
  LOCAL dir_cmd IS prog["BURN_DIR"].
  IF derived["VALID"] {
    IF NOT prog["CG"]:ISTYPE("List") { SET prog["CG"] TO guidance_cg(prog["LAND"], state["R"], V(0, 0, 0), 0). }
    IF prog["MODE"] = "P65" {
      LOCAL gp IS guid_pass_vert(state, prog["LAND"], prog["WM"], prog["THR"], prog["CG"]).
      IF gp["VALID"] {
        SET prog["GP"] TO gp.
        SET dir_cmd TO cg_unapply(prog["CG"], gp["AFC"]).
        SET prog["THR"] TO p65_trimmed(prog, gp["THR"], gp["WANTED"], state, dt).
        SET prog["BURN_DIR"] TO dir_cmd.
      }
    } ELSE {
      LOCAL tilt_cos IS VDOT(state["XNB"], state["R"]:NORMALIZED).
      LOCAL g_mag IS guid_gravity(state["R"], state["MU"]):MAG.
      LOCAL a_present IS 0.
      IF state["MASS"] > 0 { SET a_present TO state["THRUST_NOW"] / state["MASS"]. }       // kN over tonnes is m/s^2
      LOCAL rod_out IS guid_rod_throttle(prog["VDG"], derived["HDOT"], tilt_cos, state["MASS"] * 1000, state["THRUST"] * 1000, prog["THR"], a_present, g_mag).
      SET prog["THR"] TO p65_trimmed(prog, rod_out["THR"], rod_out["WANTED"], state, dt).
    }
  }

  // ---- window (the ship's own roll, with the roll stick in AUTO) and the commands ----
  LOCAL stick IS ctl_pilot_roll().
  IF prog["ATT"]["MODE"] <> "AUTO" { SET stick TO 0. }
  SET prog["WCMD"] TO win_hold(ctl_window_face_vec(), dir_cmd, prog["WCMD"], stick).
  ctl_set_command(dir_cmd, prog["WCMD"], prog["THR"]).

  // ---- contact: lamp, then the engine cut-off (unless the pilot stopped the engine first) ----
  LOCAL contact_now IS FALSE.
  IF derived["VALID"] { SET contact_now TO contact_test(ctl_status(), derived["HCALC"], derived["HDOT"]). }
  LOCAL pilot_stopped IS prog["ENGINE_LIT"] AND state["THRUST_NOW"] < 0.001.
  LOCAL ct_out IS contact_step(prog["CT"], contact_now, now_ut, pilot_stopped).
  LOCAL prog_no IS prog["PROG_NO"].
  IF prog["CT"]["T_CONTACT"] >= 0 AND prog["CT"]["T_CONTACT"] = now_ut { SET msg TO "CONTACT: THE LANDER HAS TOUCHED DOWN. THE ENGINE CUTS OFF IN " + P66_CUTOFF_DELAY_S + " S UNLESS YOU STOP IT.". }
  IF ct_out["DONE"] {
    IF ct_out["CUT_NOW"] { ctl_engine_off(prog["ENGINE"]). }       // not when the pilot has already stopped it
    SET CTL_THR TO 0.
    SET prog["ENGINE_LIT"] TO FALSE.
    SET prog["THR"] TO 0.
    SET prog_no TO 68.
    SET prog["ENDED"] TO TRUE.
    SET msg TO "P68: LANDING CONFIRMED." + (CHOOSE " ENGINE CUT OFF." IF ct_out["CUT_NOW"] ELSE " ENGINE ALREADY STOPPED.").
  }

  // ---- attitude mode, deadband, radar lamps, delta-v (shared with P63 and P64; the engine is burning, so the lock stays on) ----
  LOCAL shared_msg IS burn_shared_step(prog, state, derived, dt, TRUE, "P" + prog["PROG_NO"]).
  IF shared_msg <> "" { SET msg TO (msg + " " + shared_msg):TRIM. }

  // ---- the display: V06 N60 on entering P65 and again on entering P66 ----
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF prog["SHOWN"] <> prog["MODE"] AND NOT terminating AND NOT ct_out["DONE"] {
    SET prog["SHOWN"] TO prog["MODE"].
    SET set_verb TO 6.
    SET set_noun TO 60.
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }
  LOCAL extra IS LEXICON("TTOGO", 0, "DVTOTAL", prog["DV"], "OUTOFPLN", prog["OUTOFPLN"], "TTFDISP", 0).

  p65_log(prog, state, derived, ct_out["LAMP"]).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE,
                 "FLASH", FALSE, "ALARM", 0, "ALT_LAMP", prog["RAD"]["ALT_LAMP"], "VEL_LAMP", prog["RAD"]["VEL_LAMP"],
                 "EXTRA", extra, "MSG", msg, "ENDED", prog["ENDED"], "HANDOVER", FALSE, "PROG_NO", prog_no, "CONTACT", ct_out["LAMP"]).
}

// p65_log: one line per cycle to P65_LOG_PATH.
FUNCTION p65_log {
  PARAMETER prog, state, derived, contact_lamp.
  IF CTL_DRY { RETURN. }
  LOCAL abvel IS 0.
  LOCAL hdot IS 0.
  LOCAL hcalc IS 0.
  LOCAL vhoriz IS 0.
  IF derived["VALID"] { SET abvel TO derived["ABVEL"]. SET hdot TO derived["HDOT"]. SET hcalc TO derived["HCALC"]. SET vhoriz TO derived["VHORIZ"]. }
  LOCAL thrust_frac IS 0.
  IF state["THRUST"] > 0 { SET thrust_frac TO state["THRUST_NOW"] / state["THRUST"]. }
  IF LM_LOG { LOG "" + ROUND(state["T"], 2) + "," + prog["MODE"] + "," + ROUND(prog["VDG"], 2) + "," + ROUND(hdot, 2) + "," + ROUND(hcalc, 1) + ","
      + ROUND(abvel, 2) + "," + ROUND(vhoriz, 2) + "," + ROUND(CTL_THR, 3) + "," + ROUND(thrust_frac, 3) + ","
      + ROUND(ctl_att_error_deg(), 2) + "," + prog["ROD_TOTAL"] + "," + contact_lamp + "," + ctl_status() + ","
      + ROUND(state["ALT_RADAR"], 1) + "," + prog["RAD"]["ALT_LAMP"] + "," + prog["RAD"]["VEL_LAMP"] + "," + prog["ATT"]["MODE"] + "," + prog["SAMPLES"] + "," + ROUND(prog["TRIM"], 4) TO P65_LOG_PATH. }
  SET prog["SAMPLES"] TO 0.
}

// p65_end: give everything back to the pilot (the same as P63's end).
FUNCTION p65_end {
  PARAMETER prog.
  p63_end(prog).
}
