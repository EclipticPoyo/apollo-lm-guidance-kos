// lm_j_p66.ks -- the J-class P66 programme (Luminary 210, Apollo 15 to 17): rate of descent with horizontal velocity nulling.
//   j_p66_start(prog)                      takes P64's programme state over (engine, attitude mode, radar and window bookkeeping carry
//                                          on without a gap) and returns it as the P66 state
//   j_p66_sample(prog)                     read the throttle lever into the ROD click detector (call every 0.02 s)
//   j_p66_step(prog, state, derived, ks)   one cycle; returns what the main loop shows (the same keys as j_p64_step, plus CONTACT)
//   j_p66_end(prog)                        gives the controls back (the same as P63's)
//
// Luminary 210 has no P65 and no P67 (spec: 2026-11-13-luminary210-logic-changes.md section 1). When the time-to-go falls below
// TENDAPPR (12 s) the guidance goes straight to P66 (STARTP66, source 157-215):
//   - the commanded descent rate VDG is set to the rate being displayed now (HDOTDISP -> VDGVERT), so the descent carries on at
//     the rate the approach guidance gave; ROD clicks then change it by J_RODSCALE each, exactly as in 099's P66;
//   - the vertical law is the 099 one (j_guid_rod_throttle: TAUROD, LAG/TAU, MINFORCE, MAXFORCE);
//   - NEW in 210: the horizontal channel (P66HZ, source 970-1089, j_guid_hz in lm_j_guidance.ks) steers the thrust direction to
//     null the velocity over the surface, with the vertical component holding the weight. In 099 P66 kept the last P65 direction.
// ROD clicks are used in any attitude mode in 210's P66 (the click count is zeroed every pass only in P63 and P64, GUILDRET,
// source 231-232), so there is no "switch SAS on first" rule as in the 099 P66.
//
// Simplifications (spec section 11, as 1.0): the throttle lever's Shift and Ctrl keys stand in for the ROD switch; ROD clicks are
// applied every cycle (Luminary applies them once a second); the engine is cut off automatically after contact (the crew did it by
// hand), so the programme ends at the cut-off and the PROCEED that ends the horizontal channel after touchdown (STOPFIRE) is not
// needed; contact comes from the ship's status (no contact probes); no landing radar reasonableness test.
// Not done (spec "Not done in 1.2"): the omission-of-P66-horizontal alarm 1466 logic (TOOFEW/CNTTHROT, no time for the horizontal
// pass), the engine-arm test, an early P66 start from a ROD click in P63 or P64.
//
// The horizontal law is evaluated every J_HZ_PERIOD_S (Luminary's 2 s servicer period) and its command held in between, because
// the law feeds back its own last command (QHZ) and so depends on the pass rate.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_p63.ks").                 // j_burn_shared_step and j_p63_end, which P66 shares

GLOBAL J_P66_LOG_PATH IS "0:/lm/logs/j_p66.log".          // one line per cycle, read back after a flight

// j_p66_start: P64 has just reported HANDOVER. prog is P64's programme lexicon and is changed and returned as P66's. The guidance
// axes P64 left (gp["CG"]) stay frozen for the vertical phase; the throttle lever is centred so both keys have room. VDG is set
// on the first step that has valid data (it is the descent rate then, source 162-163).
FUNCTION j_p66_start {
  PARAMETER prog.
  SET prog["PROG_NO"] TO 66.
  SET prog["MODE"] TO "P66".
  SET prog["VDG"] TO 0.                      // the commanded descent rate (up positive); set to HDOT on the first valid cycle
  SET prog["VDG_SET"] TO FALSE.
  SET prog["CG"] TO FALSE.
  IF prog["GP"]:HASKEY("CG") { SET prog["CG"] TO prog["GP"]["CG"]. }
  SET prog["A_HZ"] TO V(0, 0, 0).            // the last horizontal command (guidance axes), fed back by the law
  SET prog["T_HZ"] TO -1.                    // UT of the last horizontal pass (-1 = none yet)
  SET prog["ROD"] TO rod_new().
  SET prog["TRIM"] TO 0.                     // the thrust trim (j_trim_step)
  SET prog["SAMPLES"] TO 0.                  // lever samples since the last cycle (logged, to see how often the lever is read)
  SET prog["CT"] TO contact_new().
  SET prog["SHOWN"] TO FALSE.                // the V06 N60 display has been requested
  SET prog["WINDOW_MODE"] TO "KEEP".         // no window logic in the vertical phase: the ship's own roll is held
  SET prog["ROD_TOTAL"] TO 0.
  SET prog["HANDOFF_T"] TO -1.
  SET prog["LAST_ALARM"] TO 0.
  ctl_lever_centre().
  IF LM_LOG AND NOT CTL_DRY {
    IF EXISTS(J_P66_LOG_PATH) { DELETEPATH(J_P66_LOG_PATH). }
    LOG "UT,VDG,HDOT,HCALC,ABVEL,VHORIZ,VGU_Y,VGU_Z,A_HZ_Y,A_HZ_Z,THR,THRUST_FRAC,ATT_ERR_DEG,ROD_TOTAL,CONTACT,STATUS,ALT_RADAR,ALT_LAMP,VEL_LAMP,ATT_MODE,SAMPLES,TRIM" TO J_P66_LOG_PATH.
    LOG "# P66 start: mass " + ROUND(SHIP:MASS, 3) + " t, SAS " + SAS TO J_P66_LOG_PATH.
  }
  RETURN prog.
}

// j_p66_sample: read the throttle lever into the ROD click detector and re-centre it when the detector asks. The main loop calls it
// every 0.02 s so a key tap shorter than one 0.25 s cycle still counts.
FUNCTION j_p66_sample {
  PARAMETER prog.
  SET prog["SAMPLES"] TO prog["SAMPLES"] + 1.
  rod_sample(prog["ROD"], ctl_pilot_throttle(), TIME:SECONDS).
  IF prog["ROD"]["RECENTRE"] {
    SET prog["ROD"]["RECENTRE"] TO FALSE.
    ctl_lever_centre().
  }
}

// j_p66_trimmed: the throttle to command: the one guidance gave, or, when a low thrust is wanted (under THR_TRIM_BAND) and the engine
// is giving thrust, the one for the wanted thrust plus the trim, which follows the error between wanted and measured thrust (j_trim_step).
FUNCTION j_p66_trimmed {
  PARAMETER prog, thr_given, wanted, state, dt.
  IF wanted < 0 OR wanted >= THR_TRIM_BAND OR state["THRUST"] <= 0 { RETURN thr_given. }
  SET prog["TRIM"] TO j_trim_step(prog["TRIM"], wanted, state["THRUST_NOW"] / state["THRUST"], dt).
  RETURN j_thr_command(wanted + prog["TRIM"]).
}

// j_p66_hz_due: is it time for the next horizontal pass? (the first one at once; then every J_HZ_PERIOD_S)
FUNCTION j_p66_hz_due {
  PARAMETER t_last, now_ut.
  RETURN t_last < 0 OR now_ut - t_last >= J_HZ_PERIOD_S.
}

// j_p66_step: one cycle, the same arguments as j_p64_step. Returns the same keys (SET_VERB, SET_NOUN, KEY_REL, BLANK, FLASH, ALARM,
// ALT_LAMP, VEL_LAMP, EXTRA, MSG, ENDED, HANDOVER (always FALSE), PROG_NO: 66, or 68 on the cycle the engine is cut off) and
// CONTACT (the lamp).
FUNCTION j_p66_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL dt IS MAX(0, now_ut - prog["T_LAST"]).
  SET prog["T_LAST"] TO now_ut.
  SET ks["PRO"] TO FALSE.
  LOCAL msg IS "".
  LOCAL terminating IS ks["VERB"] = 34.

  // ---- the commanded descent rate: the rate now at the start, then the pilot's ROD clicks (in any attitude mode) ----
  IF NOT prog["VDG_SET"] AND derived["VALID"] {
    SET prog["VDG"] TO derived["HDOT"].
    SET prog["VDG_SET"] TO TRUE.
    SET msg TO "P66: RATE OF DESCENT. SHIFT RAISES THE COMMANDED RATE, CTRL LOWERS IT. HORIZONTAL SPEED IS NULLED AUTOMATICALLY.".
  }
  LOCAL clicks IS rod_take(prog["ROD"]).
  IF clicks <> 0 AND prog["VDG_SET"] {
    SET prog["VDG"] TO prog["VDG"] + clicks * J_RODSCALE.
    SET prog["ROD_TOTAL"] TO prog["ROD_TOTAL"] + clicks.
  }

  // ---- guidance: the vertical channel throttles, the horizontal channel steers ----
  LOCAL dir_cmd IS prog["BURN_DIR"].
  LOCAL vgu_vec IS V(0, 0, 0).
  IF derived["VALID"] AND prog["VDG_SET"] {
    IF NOT prog["CG"]:ISTYPE("List") { SET prog["CG"] TO guidance_cg(prog["LAND"], state["R"], V(0, 0, 0), 0). }
    LOCAL g_mag IS j_guid_gravity(state["R"], state["MU"]):MAG.
    SET vgu_vec TO vgu(prog["CG"], state["V"], state["R"], prog["WM"]).
    IF j_p66_hz_due(prog["T_HZ"], now_ut) {
      SET prog["A_HZ"] TO j_guid_hz(vgu_vec, prog["A_HZ"], g_mag).
      SET prog["T_HZ"] TO now_ut.
    }
    SET dir_cmd TO cg_unapply(prog["CG"], prog["A_HZ"]):NORMALIZED.
    SET prog["BURN_DIR"] TO dir_cmd.
    LOCAL tilt_cos IS VDOT(state["XNB"], state["R"]:NORMALIZED).
    LOCAL a_present IS 0.
    IF state["MASS"] > 0 { SET a_present TO state["THRUST_NOW"] / state["MASS"]. }       // kN over tonnes is m/s^2
    LOCAL rod_out IS j_guid_rod_throttle(prog["VDG"], derived["HDOT"], tilt_cos, state["MASS"] * 1000, state["THRUST"] * 1000, prog["THR"], a_present, g_mag).
    SET prog["THR"] TO j_p66_trimmed(prog, rod_out["THR"], rod_out["WANTED"], state, dt).
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
  LOCAL shared_msg IS j_burn_shared_step(prog, state, derived, dt, TRUE, "P" + prog["PROG_NO"]).
  IF shared_msg <> "" { SET msg TO (msg + " " + shared_msg):TRIM. }

  // ---- the display: V06 N60 on entering P66 ----
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT prog["SHOWN"] AND NOT terminating AND NOT ct_out["DONE"] {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO 6.
    SET set_noun TO 60.
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }
  LOCAL extra IS LEXICON("TTOGO", 0, "DVTOTAL", prog["DV"], "OUTOFPLN", prog["OUTOFPLN"], "TTFDISP", 0).

  j_p66_log(prog, state, derived, vgu_vec, ct_out["LAMP"]).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE,
                 "FLASH", FALSE, "ALARM", 0, "ALT_LAMP", prog["RAD"]["ALT_LAMP"], "VEL_LAMP", prog["RAD"]["VEL_LAMP"],
                 "EXTRA", extra, "MSG", msg, "ENDED", prog["ENDED"], "HANDOVER", FALSE, "PROG_NO", prog_no, "CONTACT", ct_out["LAMP"],
                 "STATUS", j_p66_status(prog, derived, vgu_vec)).
}

// j_p66_ms_text: a speed in m/s as text with two decimals ("0.91", "-0.30"), so the readout keeps the same width.
FUNCTION j_p66_ms_text {
  PARAMETER ms_value.
  LOCAL hundredths IS ROUND(ABS(ms_value) * 100).
  LOCAL whole IS FLOOR(hundredths / 100).
  LOCAL sign IS "".
  IF ms_value < 0 AND hundredths > 0 { SET sign TO "-". }
  RETURN sign + whole + "." + zero_pad(hundredths - whole * 100, 2).
}

// j_p66_status: the three terminal readout lines (the DSKY core draws them in place, not as scrolling messages). Descent rate is
// positive going down, in m/s: the DSKY's R2 shows ft/s with up positive. The second line is the rate the pilot has commanded, the
// third the horizontal speed over the surface that the horizontal channel is nulling.
FUNCTION j_p66_status {
  PARAMETER prog, derived, vgu_vec.
  LOCAL rate_text IS "-----".
  IF derived["VALID"] { SET rate_text TO j_p66_ms_text(-derived["HDOT"]). }
  LOCAL hz_text IS "-----".
  IF derived["VALID"] { SET hz_text TO j_p66_ms_text(SQRT(vgu_vec:Y ^ 2 + vgu_vec:Z ^ 2)). }
  RETURN LIST("DESCENT RATE  " + rate_text + " m/s",
              "P66 COMMANDED " + j_p66_ms_text(-prog["VDG"]) + " m/s  (SHIFT/CTRL)",
              "HORIZONTAL    " + hz_text + " m/s  AUTO NULL").
}

// j_p66_log: one line per cycle to J_P66_LOG_PATH.
FUNCTION j_p66_log {
  PARAMETER prog, state, derived, vgu_vec, contact_lamp.
  IF CTL_DRY { RETURN. }
  LOCAL abvel IS 0.
  LOCAL hdot IS 0.
  LOCAL hcalc IS 0.
  LOCAL vhoriz IS 0.
  IF derived["VALID"] { SET abvel TO derived["ABVEL"]. SET hdot TO derived["HDOT"]. SET hcalc TO derived["HCALC"]. SET vhoriz TO derived["VHORIZ"]. }
  LOCAL thrust_frac IS 0.
  IF state["THRUST"] > 0 { SET thrust_frac TO state["THRUST_NOW"] / state["THRUST"]. }
  IF LM_LOG { LOG "" + ROUND(state["T"], 2) + "," + ROUND(prog["VDG"], 2) + "," + ROUND(hdot, 2) + "," + ROUND(hcalc, 1) + ","
      + ROUND(abvel, 2) + "," + ROUND(vhoriz, 2) + "," + ROUND(vgu_vec:Y, 2) + "," + ROUND(vgu_vec:Z, 2) + ","
      + ROUND(prog["A_HZ"]:Y, 3) + "," + ROUND(prog["A_HZ"]:Z, 3) + "," + ROUND(CTL_THR, 3) + "," + ROUND(thrust_frac, 3) + ","
      + ROUND(ctl_att_error_deg(), 2) + "," + prog["ROD_TOTAL"] + "," + contact_lamp + "," + ctl_status() + ","
      + ROUND(state["ALT_RADAR"], 1) + "," + prog["RAD"]["ALT_LAMP"] + "," + prog["RAD"]["VEL_LAMP"] + "," + prog["ATT"]["MODE"] + "," + prog["SAMPLES"] + "," + ROUND(prog["TRIM"], 4) TO J_P66_LOG_PATH. }
  SET prog["SAMPLES"] TO 0.
}

// j_p66_end: give everything back to the pilot (the same as P63's end).
FUNCTION j_p66_end {
  PARAMETER prog.
  j_p63_end(prog).
}
