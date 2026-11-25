// lm_control.ks -- P63 control layer: the attitude mode (AUTO / ATT HOLD), the simulated landing radar's
// lamp logic (part 1, pure), and the functions that write kOS steering, throttle and RCS (part 2, at the end).
//
// Part 1 (this part) is pure logic. The inputs are passed in, nothing reads kOS, so it is tested on the pad
// (scripts/tests/test_p63.ks).
//
//   Attitude mode (spec section 6). In Luminary the DAP reads a physical AUTO / ATT HOLD switch (channel 31 bit 13,
//   Q_R-AXIS_RCS_AUTOPILOT.agc 135-145): in AUTO the pitch and yaw axes follow the guidance command and ignore the hand
//   controller, in ATT HOLD the DAP holds attitude. Only the switch changes the mode. KSP's SAS button stands in for the
//   switch: SAS on = ATT HOLD, SAS off = AUTO. There is no stick take-over.
//
//   Radar lamps (spec section 7). Luminary's ALT and VEL lamps come from the landing radar's data-validity checks
//   (SERVICER.agc 1145-1160, 1281-1292, 1421-1448; P20-P25.agc 5115-5180):
//     - no good data (altitude out of the radar's range, speed too high for the velocity beams): lamp on;
//     - with data, each reading is tested against the computed state. Altitude: fail when
//       |radar - computed| > DELQFIX + HCALC/8. Velocity: fail when |difference| > 7.5 ft/s + |V|/8.
//     - a failing test lights the lamp only when another test failed within the previous three (two bad readings in
//       four); a passing test clears it.
//   Simplifications: the lamp is steady (Luminary flashes it through R10/R11); the altitude is the vertical height above
//   the terrain from kOS, not the slant range along the antenna beam; the range limit RADAR_ALT_MAX_M follows the Mission
//   Report's landing-radar data-good time (the software reads the radar below 50,000 ft).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").               // lm_cross, for the approach window vector (win_exnorm)

// ---- Attitude mode -------------------------------------------------------------------------------------------

// att_new: a fresh attitude-mode state. MODE is "AUTO" or "HOLD".
FUNCTION att_new {
  RETURN LEXICON("MODE", "AUTO").
}

// att_step: set the mode from the switch. sas_on is the state of the SAS button (TRUE = ATT HOLD). Changes and returns
// the same lexicon.
FUNCTION att_step {
  PARAMETER att, sas_on.
  SET att["MODE"] TO (CHOOSE "HOLD" IF sas_on ELSE "AUTO").
  RETURN att.
}

// ---- Turn, then warp (pure) ------------------------------------------------------------------------------------

// warp_new: bookkeeping for the one warp P63 makes. DONE is TRUE once the warp was started, or ruled out because the
// stop time is too close; SINCE is the time the attitude first counted as settled (-1 = not settled now).
FUNCTION warp_new {
  RETURN LEXICON("DONE", FALSE, "SINCE", -1).
}

// warp_step: called every cycle until DONE. Returns the time (UT) to warp to, or -1 for "do not warp now".
//   Not yet near the burn attitude, or still turning: -1 (and the settled timer restarts).
//   Settled for P63_SETTLE_HOLD_S: the answer is TIG - P63_WARP_LEAD_S, and DONE is set so it is returned only once.
//   If TIG - P63_WARP_LEAD_S is less than P63_WARP_MIN_S ahead (the ship is already close to ignition), DONE is set
//   and -1 returned at once: there is nothing to warp over, and no warp is started later, in the countdown.
// att_err_deg is the angle to the commanded attitude (all three axes), rate_deg_s the angular speed of the ship.
FUNCTION warp_step {
  PARAMETER wrp, now_ut, tig, att_err_deg, rate_deg_s.
  IF wrp["DONE"] { RETURN -1. }
  LOCAL stop_ut IS tig - P63_WARP_LEAD_S.
  IF stop_ut - now_ut < P63_WARP_MIN_S {
    SET wrp["DONE"] TO TRUE.
    RETURN -1.
  }
  IF att_err_deg < P63_SETTLE_ERR_DEG AND rate_deg_s < P63_SETTLE_RATE_DEG_S {
    IF wrp["SINCE"] < 0 { SET wrp["SINCE"] TO now_ut. }
    IF now_ut - wrp["SINCE"] >= P63_SETTLE_HOLD_S {
      SET wrp["DONE"] TO TRUE.
      RETURN stop_ut.
    }
  } ELSE {
    SET wrp["SINCE"] TO -1.
  }
  RETURN -1.
}

// ---- Coast deadband (pure) ------------------------------------------------------------------------------------
// The real LM's autopilot let the ship drift inside an attitude deadband and fired the jets only at its edge. kOS's own
// steering has no deadband, so P63 makes one: it drops the steering lock while the ship is close to the commanded
// attitude and still, and takes it again when the error passes P63_DB_RELOCK_DEG. Release and re-lock use different
// angles (0.5 and 1.0 degrees) so it does not flip back and forth at one value.

// db_new: LOCKED is TRUE while the steering lock is on (it starts on: the first turn needs it).
FUNCTION db_new {
  RETURN LEXICON("LOCKED", TRUE).
}

// db_step: one cycle. att_err_deg is the error to the commanded attitude, rate_deg_s the ship's turn rate, must_lock TRUE
// when the lock has to stay on whatever the error (countdown, ullage, burn). Changes LOCKED and returns the lexicon.
FUNCTION db_step {
  PARAMETER dbs, att_err_deg, rate_deg_s, must_lock.
  IF must_lock {
    SET dbs["LOCKED"] TO TRUE.
  } ELSE IF dbs["LOCKED"] {
    IF att_err_deg < P63_DB_RELEASE_DEG AND rate_deg_s < P63_DB_RATE_DEG_S { SET dbs["LOCKED"] TO FALSE. }
  } ELSE {
    IF att_err_deg > P63_DB_RELOCK_DEG { SET dbs["LOCKED"] TO TRUE. }
  }
  RETURN dbs.
}

// ---- Window roll, as in Luminary (pure) -------------------------------------------------------------------------
// Luminary's P63 never rolls the window by itself. The pre-burn turn (THE_LUNAR_LANDING.agc P63SPOT2, R60LEM with the
// thrust axis as the pointing axis) is the shortest rotation, so the LM keeps its roll. In the burn FINDCDUW uses the
// window command vector (UNIT(R)) only while XOVINHIB is set; every V37 clears it (FRESH_START_AND_RESTART.agc 656, 846),
// the landing programmes only clear it, and only the ascent guidance sets it (ASCENT_GUIDANCE.agc 428). With it clear,
// FINDCDUW takes the vehicle's own +Z axis as the window vector (AFTRFLTR, FETCHZNB): the roll is held where it is,
// and in AUTO the pilot may roll with the stick (X-axis override, P-AXIS_RCS_AUTOPILOT.agc 524-531). The roll to
// windows-up on Apollo 11 was therefore manual. So here: before ignition the window vector is carried round by the
// shortest rotation from the attitude at the start of P63 (win_min_rotation); once the ship has turned to the burn attitude (and from ignition) it is the ship's own window
// vector projected onto the plane perpendicular to the new thrust axis, turned by the stick if the pilot rolls (win_hold).
// All vectors are in raw axes; "window vector" means the direction the crew window faces.

// win_rot: vec rotated by deg degrees about the axis axis_vec (Rodrigues' formula, double precision).
FUNCTION win_rot {
  PARAMETER vec, axis_vec, deg.
  LOCAL k_vec IS axis_vec:NORMALIZED.
  RETURN vec * COS(deg) + VCRS(k_vec, vec) * SIN(deg) + k_vec * (VDOT(k_vec, vec) * (1 - COS(deg))).
}

// win_exnorm: the direction the crew window should face in the approach (P64), Luminary's EXNORM
// (LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 748-815). land_vec and r_vec as in lm_frame.ks, xnb_vec the ship's +X axis (up
// through the top hatch = the kOS fore vector), cg the guidance axes (rows: up, crossrange, horizontal toward the site).
//   u    = unit(LAND - R), the line of sight to the site
//   PROJ = (u x XNB) . crossrange axis: the sine of the angle between the line of sight and the ship's X axis, as seen along
//          the crossrange direction
//   window = a * (horizontal axis toward the site) + b * u, with a = max(0, PROJMAX - PROJ) and b = max(0, PROJ - PROJMIN)
//          (PROJMAX = sin 25 deg, PROJMIN = sin 15 deg), then made unit length.
// So with the site nearly straight below the ship's axis (PROJ small) the window faces the horizon toward the site, with a
// shallow view of the site (PROJ large) it faces the site itself, and in between the two are blended. A zero vector is
// returned if the ship is exactly at the site or the two terms cancel.
FUNCTION win_exnorm {
  PARAMETER land_vec, r_vec, xnb_vec, cg.
  LOCAL los_vec IS land_vec - r_vec.
  IF los_vec:MAG = 0 { RETURN V(0, 0, 0). }
  LOCAL u_vec IS los_vec:NORMALIZED.
  LOCAL proj IS VDOT(lm_cross(u_vec, xnb_vec), cg[1]).
  LOCAL a_coef IS MAX(0, P64_PROJMAX - proj).
  LOCAL b_coef IS MAX(0, proj - P64_PROJMIN).
  LOCAL w_vec IS cg[2] * a_coef + u_vec * b_coef.
  IF w_vec:MAG < 1e-6 { RETURN V(0, 0, 0). }
  RETURN w_vec:NORMALIZED.
}

// win_perp: vec with its part along dir_vec removed, made unit length. A zero vector when nothing is left (vec parallel to dir_vec).
FUNCTION win_perp {
  PARAMETER vec, dir_vec.
  LOCAL d_unit IS dir_vec:NORMALIZED.
  LOCAL rest IS vec - d_unit * VDOT(vec, d_unit).
  IF rest:MAG < 1e-6 { RETURN V(0, 0, 0). }
  RETURN rest:NORMALIZED.
}

// win_min_rotation: where the window vector win0 goes when the thrust axis is turned from fore0 to dir_new by the shortest
// rotation (about fore0 x dir_new). Which way is "positive" for the rotation depends on kOS's left-handed axes, so both
// signs are tried and the one that really takes fore0 to dir_new is used. Exactly opposite (the cross product is zero): the
// turn is made about win0 itself, which leaves it unchanged.
FUNCTION win_min_rotation {
  PARAMETER fore0, win0, dir_new.
  LOCAL f_unit IS fore0:NORMALIZED.
  LOCAL d_unit IS dir_new:NORMALIZED.
  LOCAL turn_deg IS VANG(f_unit, d_unit).
  LOCAL axis_vec IS VCRS(f_unit, d_unit).
  IF axis_vec:MAG < 1e-9 { RETURN win0:NORMALIZED. }     // no turn, or exactly opposite (turned about win0 itself)
  LOCAL sign IS 1.
  IF VANG(win_rot(f_unit, axis_vec, turn_deg), d_unit) > VANG(win_rot(f_unit, axis_vec, -turn_deg), d_unit) { SET sign TO -1. }
  RETURN win_rot(win0, axis_vec, sign * turn_deg):NORMALIZED.
}

// win_hold: the window vector to command once the ship has turned to the burn attitude: the ship's own window vector
// face_vec (the roll is held where it is) projected onto the plane perpendicular to the thrust axis dir_vec, then turned
// about dir_vec to lead the ship by stick * P63_ROLL_STICK_LEAD_DEG degrees when the roll stick (-1 to 1) is out of its
// detent (|stick| above P63_ROLL_DETENT): the X-axis override. The command stays a fixed angle ahead of the ship while the
// stick is held, so the ship keeps rolling toward it at the rate kOS steering gives for that error (a command only a
// small step ahead each cycle gave a very slow roll in flight). If the window vector is parallel to the thrust axis,
// the old command w_old is kept.
FUNCTION win_hold {
  PARAMETER face_vec, dir_vec, w_old, stick.
  LOCAL base_vec IS win_perp(face_vec, dir_vec).
  IF base_vec:MAG = 0 { RETURN w_old. }
  IF ABS(stick) <= P63_ROLL_DETENT { RETURN base_vec. }
  RETURN win_rot(base_vec, dir_vec, P63_ROLL_STICK_SIGN * stick * P63_ROLL_STICK_LEAD_DEG):NORMALIZED.
}

// ---- Simulated landing radar lamps -----------------------------------------------------------------------------

// radar_new: ALT_LAMP and VEL_LAMP are the lamp states. The rest is bookkeeping: *_N counts the tests so far, *_R is the
// number of the last failing test (0 = none), *_TEST is the lamp as the tests alone say it, before the no-data rule.
FUNCTION radar_new {
  RETURN LEXICON("ALT_LAMP", FALSE, "VEL_LAMP", FALSE,
                 "ALT_N", 0, "ALT_R", 0, "ALT_TEST", FALSE,
                 "VEL_N", 0, "VEL_R", 0, "VEL_TEST", FALSE).
}

// radar_test: one reasonableness test on one channel. failed says whether this reading was bad. Updates the channel's
// counters and returns whether the test alone lights the lamp. chan is "ALT" or "VEL".
FUNCTION radar_test {
  PARAMETER rad, chan, failed.
  SET rad[chan + "_N"] TO rad[chan + "_N"] + 1.
  LOCAL lit IS FALSE.
  IF failed {
    // Lit only when another test failed within the previous three: fewer than four tests since that one.
    SET lit TO rad[chan + "_R"] <> 0 AND rad[chan + "_N"] - rad[chan + "_R"] < 4.
    SET rad[chan + "_R"] TO rad[chan + "_N"].
  }
  SET rad[chan + "_TEST"] TO lit.
  RETURN lit.
}

// radar_step: one radar cycle. h_calc is the computed height above the landing site (HCALC, m), h_radar the radar's
// height above the terrain (m), speed_surf the speed over the surface (m/s) and v_err the difference between the
// velocity the radar measures and the computed one (m/s; the caller passes 0 when there is no independent
// measurement). test_alt: run the altitude test (TRUE, the default, from the high gate on). Updates the lexicon's ALT_LAMP and VEL_LAMP and returns it. Negative h_calc counts as zero.
FUNCTION radar_step {
  PARAMETER rad, h_calc, h_radar, speed_surf, v_err, test_alt IS TRUE.
  LOCAL no_alt_data IS h_radar > RADAR_ALT_MAX_M.
  // test_alt is FALSE before the high gate (P63): the altitude reasonableness test is not run, and so cannot count (Luminary tests it only from the
  // approach phase on, audit K1); the no-data rule above still applies.
  IF NOT no_alt_data AND test_alt {
    radar_test(rad, "ALT", ABS(h_radar - h_calc) > DELQFIX + MAX(h_calc, 0) / 8).
  }
  SET rad["ALT_LAMP"] TO no_alt_data OR rad["ALT_TEST"].
  LOCAL no_vel_data IS speed_surf >= RADAR_V_MAX.
  IF NOT no_vel_data {
    radar_test(rad, "VEL", ABS(v_err) > RADAR_DV_FIXED + ABS(speed_surf) * RADAR_DV_FRAC).
  }
  SET rad["VEL_LAMP"] TO no_vel_data OR rad["VEL_TEST"].
  RETURN rad.
}

// ---- ROD clicks from the throttle lever (milestone 5, P66; pure) -----------------------------------------------------
// The real LM's rate-of-descent switch was clicked up or down; each click changed the commanded descent rate (source
// DESCBITS 1223-1228: a trap counts one click per switch movement and is reset when the switch is released). Here the keyboard's
// throttle keys stand in for it: Shift raises KSP's throttle lever and Ctrl lowers it, at 0.5 per second, and the lever keeps
// following the keys while a programme holds the throttle (probe_rod.ks, spec section 13). The lever is kept near 0.5 so both
// keys have room.
//   A click is the lever moving ROD_LEVER_STEP or more away from the reference REF (0.5): up is +1, down is -1 (times
//   P66_ROD_SIGN). One key press is one click: after a click the lever is written back to 0.5 on every sample (the caller does it
//   when RECENTRE is TRUE and clears the flag), so a held key keeps moving it a little each sample and it never reaches an end stop,
//   and no other click counts until the lever has stayed at 0.5 for ROD_LEVER_REARM_S (the key was released). A lever change bigger
//   than ROD_LEVER_JUMP in one sample is not a click (the X and Z keys cut and fully open the throttle).
// rod_new: REF the lever value a click is measured from, LAST the lever at the last sample, HELD 0 (armed) or the direction
// of the click being held, QUIET_SINCE the time the lever last became still (-1 = not still), CLICKS the waiting clicks.
// ---- the thrust monitor (Luminary DVMON and COMFAIL, V97) -----------------------------------------------------------------------------------
// Every DVMON_PERIOD_S the acceleration gained since the last check is compared with the monitor's threshold MIN (DVMON_ACCEL_MS2 for the descent
// engine; the ascent passes its own, Luminary loading DVTHRUSH per programme). Enough resets the count to 1; too little
// counts it down, and a low check with the count already zero is the failure: 5 low checks before any thrust has been seen (count starts at 4), 2 after.
// dvmon_step(mon, dv_total, now) takes the delta-v gained since ignition (m/s) and the UT; mon["FAILED"] says the V97 display is due.
FUNCTION dvmon_new {
  PARAMETER min_accel IS DVMON_ACCEL_MS2.
  RETURN LEXICON("COUNT", 4, "FAILED", FALSE, "T0", -1, "DV0", 0, "MIN", min_accel).
}
FUNCTION dvmon_step {
  PARAMETER mon, dv_total, now.
  IF mon["FAILED"] { RETURN. }
  IF mon["T0"] < 0 {
    SET mon["T0"] TO now.
    SET mon["DV0"] TO dv_total.
    RETURN.
  }
  IF now - mon["T0"] < DVMON_PERIOD_S { RETURN. }
  LOCAL accel IS (dv_total - mon["DV0"]) / (now - mon["T0"]).
  SET mon["T0"] TO now.
  SET mon["DV0"] TO dv_total.
  IF accel >= mon["MIN"] { SET mon["COUNT"] TO 1. }
  ELSE IF mon["COUNT"] <= 0 { SET mon["FAILED"] TO TRUE. }
  ELSE { SET mon["COUNT"] TO mon["COUNT"] - 1. }
}
// dvmon_reset: PRO at the V97 display (Luminary COMFAIL3) puts the monitor back to its start.
FUNCTION dvmon_reset {
  PARAMETER mon.
  SET mon["COUNT"] TO 4.
  SET mon["FAILED"] TO FALSE.
  SET mon["T0"] TO -1.
}

// A programme's ROD detector (rod_new) holds two independent detectors, so that one input never disturbs the other: the top level reads
// the H and N keys (the lever-style level of rod_key_level), and rod["LV"] reads the throttle lever (Shift and Ctrl, the 1.3.1 input). Which
// are fed is the ROD_KEYS setting (rod_feed). rod_take and rod_discard cover both.
FUNCTION rod_base {
  RETURN LEXICON("REF", 0.5, "LAST", 0.5, "HELD", 0, "QUIET_SINCE", -1, "CLICKS", 0, "RECENTRE", FALSE).
}
FUNCTION rod_new {
  LOCAL rod IS rod_base().
  SET rod["LV"] TO rod_base().
  RETURN rod.
}

// rod_sample: feed the lever value (0 to 1) of one moment; call it every 0.02 s. Returns the click this sample made: -1, 0 or 1,
// already multiplied by P66_ROD_SIGN, and adds it to CLICKS.
FUNCTION rod_sample {
  PARAMETER rod, lever, now_ut.
  LOCAL click IS 0.
  IF ABS(lever - rod["LAST"]) > ROD_LEVER_JUMP {
    // The X or Z key (or the lever starting at 0 before our first write lands): not a click; re-centre.
    SET rod["LAST"] TO lever.
    SET rod["HELD"] TO 0.
    SET rod["QUIET_SINCE"] TO -1.
    SET rod["RECENTRE"] TO TRUE.
    RETURN 0.
  }
  IF rod["HELD"] = 0 {
    IF lever - rod["REF"] >= ROD_LEVER_STEP { SET click TO 1. }
    ELSE IF rod["REF"] - lever >= ROD_LEVER_STEP { SET click TO -1. }
    IF click <> 0 {
      SET rod["HELD"] TO click.
      SET rod["QUIET_SINCE"] TO -1.
      SET click TO click * P66_ROD_SIGN.
      SET rod["CLICKS"] TO rod["CLICKS"] + click.
    }
  } ELSE {
    IF ABS(lever - rod["REF"]) < ROD_LEVER_STEP / 2 {
      IF rod["QUIET_SINCE"] < 0 { SET rod["QUIET_SINCE"] TO now_ut. }
      IF now_ut - rod["QUIET_SINCE"] >= ROD_LEVER_REARM_S {
        SET rod["HELD"] TO 0.
        SET rod["QUIET_SINCE"] TO -1.
      }
    } ELSE {
      SET rod["QUIET_SINCE"] TO -1.
    }
  }
  IF rod["HELD"] <> 0 { SET rod["RECENTRE"] TO TRUE. }      // the caller writes the lever back to REF (0.5) while a click is held
  SET rod["LAST"] TO lever.
  RETURN click.
}

// ctl_rod_feed: read the ROD inputs into the click detectors (call every 0.02 s; P63 and P64 use it so a click can start P66 early, P65 and
// J P66 call it from their own sample hook, which also counts the samples). ROD_KEYS says which inputs count: "BOTH" (default), "HN" (the H
// and N keys only; the lever is neither read nor written) or "SHIFTCTRL" (the throttle lever only). The lever detector re-centres the lever
// when it asks; the H/N detector writes nothing.
FUNCTION ctl_rod_feed {
  PARAMETER rod.
  LOCAL now_ut IS TIME:SECONDS.
  IF ROD_KEYS <> "SHIFTCTRL" { rod_sample(rod, ctl_pilot_keys(), now_ut). }
  IF ROD_KEYS <> "HN" AND rod:HASKEY("LV") {
    rod_sample(rod["LV"], ctl_pilot_throttle(), now_ut).
    IF rod["LV"]["RECENTRE"] {
      SET rod["LV"]["RECENTRE"] TO FALSE.
      ctl_lever_centre().
    }
  }
}

// rod_take: the waiting clicks from both detectors (signed sum), and the waiting count back to zero.
FUNCTION rod_take {
  PARAMETER rod.
  LOCAL n IS rod["CLICKS"].
  SET rod["CLICKS"] TO 0.
  IF rod:HASKEY("LV") {
    SET n TO n + rod["LV"]["CLICKS"].
    SET rod["LV"]["CLICKS"] TO 0.
  }
  RETURN n.
}

// rod_discard: forget the waiting clicks.
FUNCTION rod_discard {
  PARAMETER rod.
  SET rod["CLICKS"] TO 0.
  IF rod:HASKEY("LV") { SET rod["LV"]["CLICKS"] TO 0. }
}

// rod_log: one line to ROD_LOG_PATH for every ROD click a programme took (used or thrown away, and why), so a report such as "SAS was on
// and the clicks did nothing" can be read back from the log. Always on (not tied to LM_LOG: it is one short line per click, and it is the log
// that answers an input report), but only with a ship (not on the pad: CTL_DRY).
GLOBAL ROD_LOG_PATH IS "0:/lm/logs/rod.log".
FUNCTION rod_log {
  PARAMETER text.
  IF NOT CTL_DRY { LOG ROUND(TIME:SECONDS, 2) + " " + text TO ROD_LOG_PATH. }
}

// ---- Contact and engine cut-off (milestone 5; pure) ----------------------------------------------------------------------
// The real LM had contact probes under the footpads: the Contact Light came on and the crew stopped the engine; P68 then
// confirmed the landing. KSP has no probes, so contact is the ship's status (kOS Vessel:STATUS reads "LANDED" or "SPLASHED" once
// a leg touches); with P66_CONTACT_FALLBACK set (off by default: it measures the centre of mass above the site radius, not the
// terrain) also being almost at the surface and almost still. After the lamp lights the programme ends P66_CUTOFF_DELAY_S later
// (P68), cutting the engine off then unless the pilot has already stopped it (a departure from Apollo, spec section 6).

// contact_test: status_text is SHIP:STATUS, h_calc the height above the site (m), hdot the vertical speed (m/s).
FUNCTION contact_test {
  PARAMETER status_text, h_calc, hdot.
  IF status_text = "LANDED" OR status_text = "SPLASHED" { RETURN TRUE. }
  IF NOT P66_CONTACT_FALLBACK { RETURN FALSE. }
  RETURN h_calc < P66_CONTACT_ALT_M AND ABS(hdot) < P66_CONTACT_RATE.
}

// contact_new: T_CONTACT the time of first contact (-1 = none yet), DONE TRUE once the end of the landing has been given,
// STOPPED TRUE once the pilot has stopped the engine.
FUNCTION contact_new {
  RETURN LEXICON("T_CONTACT", -1, "DONE", FALSE, "STOPPED", FALSE).
}

// contact_step: call every cycle. contact_now is the contact test's answer, pilot_stopped is TRUE when the pilot has stopped the
// engine (it was lit and is not now). Returns LEXICON("LAMP", the CONTACT lamp (lit from the first contact on),
// "DONE", TRUE once, at P66_CUTOFF_DELAY_S after the first contact (the landing is over: P68),
// "CUT_NOW", TRUE with DONE unless the pilot had stopped the engine already (then there is nothing to cut off)).
FUNCTION contact_step {
  PARAMETER ct, contact_now, now_ut, pilot_stopped.
  IF contact_now AND ct["T_CONTACT"] < 0 { SET ct["T_CONTACT"] TO now_ut. }
  IF pilot_stopped { SET ct["STOPPED"] TO TRUE. }
  LOCAL done IS FALSE.
  LOCAL cut_now IS FALSE.
  IF ct["T_CONTACT"] >= 0 AND NOT ct["DONE"] {
    IF now_ut - ct["T_CONTACT"] >= P66_CUTOFF_DELAY_S {
      SET ct["DONE"] TO TRUE.
      SET done TO TRUE.
      SET cut_now TO NOT ct["STOPPED"].
    }
  }
  RETURN LEXICON("LAMP", ct["T_CONTACT"] >= 0, "DONE", done, "CUT_NOW", cut_now).
}

// ======================================================================================================================
// Part 2: the kOS-facing functions (plan Task 8). These are the ONLY functions that write the ship's controls.
// They cannot be tested on the pad; they are exercised in the flight tests. Names checked in the kOS docs (see
// scripts/tests/probe_control.ks): LOCK STEERING / LOCK THROTTLE (commands/flight/cooked.rst), SHIP:CONTROL:FORE and
// NEUTRALIZE (raw.rst), SHIP:CONTROL:PILOTPITCH/YAW/ROLL and PILOTMAINTHROTTLE (pilot.rst), SAS, RCS, SASMODE (systems.rst).
//
// How the steering works, in plain words. kOS has "cooked" steering: LOCK STEERING TO <direction> makes kOS turn the
// ship to that direction and hold it. The direction is an expression that kOS re-reads many times a second, so we keep
// the wanted direction in global variables (CTL_DIR, CTL_UP, CTL_ROLL) and the lock reads them. Guidance updates the
// variables each cycle and the ship follows. A LOCK always has global scope (docs, language/variables), so it is safe to
// create it inside a function.
// The lander steers with its RCS thrusters, so RCS is switched ON for the programme.
//
// SAS (KSP's own autopilot) must NOT be on together with LOCK STEERING (docs warning). The override therefore UNLOCKS
// steering first, then turns SAS on in "stability assist" mode, which holds whatever attitude the pilot leaves the ship in.

GLOBAL CTL_DIR IS V(0, 0, 1).      // the direction the ship's nose (thrust axis) should point, raw axes
GLOBAL CTL_UP IS V(0, 1, 0).       // a direction the "up" side of the ship should lean toward (sets the roll)
GLOBAL CTL_GOAL_DIR IS V(0, 0, 1).  // what guidance wants (CTL_DIR and CTL_UP follow it no faster than P63_TURN_RATE_DEG_S, see ctl_set_command)
GLOBAL CTL_GOAL_UP IS V(0, 1, 0).
GLOBAL CTL_SLEW_T IS 0.            // UT of the last slew step
GLOBAL CTL_ROLL IS 0.              // extra roll about the thrust axis, degrees, so the crew window faces CTL_UP
GLOBAL CTL_THR IS 0.               // throttle setting, 0 to 1
GLOBAL CTL_THR_LOCKED IS FALSE.    // the programme holds the throttle (LOCK THROTTLE TO CTL_THR); FALSE once ctl_man_direct has given the engine to the lever
// CTL_DRY: when TRUE every function below that would write the ship's controls does nothing, so the programme's step
// (lm_p63.ks) can be run on the pad in the pad tests. Always FALSE in flight.
GLOBAL CTL_DRY IS FALSE.
GLOBAL CTL_DRY_STATUS IS "FLYING".   // what ctl_status returns on the pad (tests set it to "LANDED")
GLOBAL CTL_DRY_LEVER IS 0.5.         // what ctl_pilot_throttle returns on the pad (tests set it to move the lever)
GLOBAL CTL_DRY_STAGES IS 0.          // how often ctl_stage_ascent was called on the pad (tests read it)
GLOBAL CTL_DRY_FORE IS TRUE.         // on the pad: FALSE between ctl_rcs_fore_off and ctl_rcs_fore_restore (tests read it)

// ctl_roll_for_window: the extra roll (degrees about the thrust axis) that puts the crew window face (WINDOW_AXIS in
// lm_constants.ks) toward the roll reference instead of the ship's "top". "TOP" needs none, "BOTTOM" a half turn.
// "STAR" and "PORT" are a quarter turn each way; which sign is which depends on kOS's left-handed rotations and is
// UNVERIFIED: if the window comes out facing the wrong way, swap them (flight test 1).
FUNCTION ctl_roll_for_window {
  IF WINDOW_AXIS = "BOTTOM" { RETURN 180. }
  IF WINDOW_AXIS = "STAR" { RETURN -90. }
  IF WINDOW_AXIS = "PORT" { RETURN 90. }
  RETURN 0.
}

// ctl_window_face_vec: the direction the crew window faces now (raw axes), from the ship's axes and WINDOW_AXIS. On the pad
// (CTL_DRY) there is no ship: a fixed vector.
FUNCTION ctl_window_face_vec {
  IF CTL_DRY { RETURN V(0, 1, 0). }
  LOCAL facing_dir IS SHIP:FACING.
  IF WINDOW_AXIS = "BOTTOM" { RETURN -facing_dir:TOPVECTOR. }
  IF WINDOW_AXIS = "STAR" { RETURN facing_dir:STARVECTOR. }
  IF WINDOW_AXIS = "PORT" { RETURN -facing_dir:STARVECTOR. }
  RETURN facing_dir:TOPVECTOR.
}

// ctl_pilot_roll: the roll stick, -1 to 1 (SHIP:CONTROL:PILOTROLL, what the player is doing; probe_control.ks read 0 still, 1 moved).
// Zero on the pad (CTL_DRY).
FUNCTION ctl_pilot_roll {
  IF CTL_DRY { RETURN 0. }
  RETURN SHIP:CONTROL:PILOTROLL.
}

// ctl_pilot_pitch, ctl_pilot_yaw: the pitch and yaw sticks, -1 to 1 (SHIP:CONTROL:PILOTPITCH / PILOTYAW: what the player is
// doing; names confirmed by probe_control.ks). On the keyboard they are -1, 0 or 1. Zero on the pad (CTL_DRY).
FUNCTION ctl_pilot_pitch {
  IF CTL_DRY { RETURN 0. }
  RETURN SHIP:CONTROL:PILOTPITCH.
}

FUNCTION ctl_pilot_yaw {
  IF CTL_DRY { RETURN 0. }
  RETURN SHIP:CONTROL:PILOTYAW.
}

// rod_key_level: the ROD input as a lever-style level for rod_sample (pure). fore_in is the pilot's fore/aft translation input,
// -1, 0 or 1 (SHIP:CONTROL:PILOTFORE: H is +1, N is -1 with KSP's default keys; probe_translation.ks: exact steps, same with RCS on
// or off). H gives 0.6, N gives 0.4, anything else 0.5, so a press is a step of 0.1 from the reference: a click for rod_sample and
// well under its ROD_LEVER_JUMP.
FUNCTION rod_key_level {
  PARAMETER fore_in.
  IF fore_in >= 0.5 { RETURN 0.6. }
  IF fore_in <= -0.5 { RETURN 0.4. }
  RETURN 0.5.
}

// ctl_pilot_keys: the H and N ROD input level, 0.4 / 0.5 / 0.6 (see rod_key_level). Added in 1.3.2 because a pilot whose throttle keys did
// nothing could not click (reported on 1.3.1), and the lever has to be written back to centre, which a controller axis can fight. The
// translation keys are read-only. 0.5 (no key) on the pad (CTL_DRY).
FUNCTION ctl_pilot_keys {
  IF CTL_DRY { RETURN 0.5. }
  RETURN rod_key_level(SHIP:CONTROL:PILOTFORE).
}

// ctl_pilot_throttle: the throttle lever, 0 to 1 (SHIP:CONTROL:PILOTMAINTHROTTLE: Shift raises it, Ctrl lowers it, 0.5 per second,
// even while the programme's LOCK THROTTLE is active: probe_rod.ks). 0.5 (centred) on the pad (CTL_DRY).
FUNCTION ctl_pilot_throttle {
  IF CTL_DRY { RETURN CTL_DRY_LEVER. }
  RETURN SHIP:CONTROL:PILOTMAINTHROTTLE.
}

// ctl_lever_centre: put the throttle lever back to 0.5 so both keys have room (writing it sticks: probe_rod.ks). Nothing on the pad, and
// nothing when ROD_KEYS is "HN" (the lever is then left alone).
FUNCTION ctl_lever_centre {
  IF CTL_DRY OR ROD_KEYS = "HN" { RETURN. }
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
}

// ctl_status: the ship's status text (SHIP:STATUS: "LANDED", "SPLASHED", "FLYING", "SUB_ORBITAL", ...). CTL_DRY_STATUS on the pad (CTL_DRY).
FUNCTION ctl_status {
  IF CTL_DRY { RETURN CTL_DRY_STATUS. }
  RETURN SHIP:STATUS.
}

// ctl_engine_off: shut the engine down (Engine:SHUTDOWN) and the throttle command to zero. Nothing on the pad.
FUNCTION ctl_engine_off {
  PARAMETER eng.
  SET CTL_THR TO 0.
  IF CTL_DRY { RETURN. }
  eng:SHUTDOWN().
}

// ctl_steer_lock: (re)create the steering lock. A function so ctl_start and ctl_auto share it.
FUNCTION ctl_steer_lock {
  IF CTL_DRY { RETURN. }
  LOCK STEERING TO ANGLEAXIS(CTL_ROLL, CTL_DIR) * LOOKDIRUP(CTL_DIR, CTL_UP).
}

// ctl_steer_release: drop the steering lock so the jets go quiet and the ship drifts (the coast deadband, db_step), and
// hand the raw controls back so no jet command is left over. ctl_steer_lock takes it again.
FUNCTION ctl_steer_release {
  IF CTL_DRY { RETURN. }
  UNLOCK STEERING.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
}

// ctl_start: take control for the programme. RCS on (the lander steers with it), SAS off, steering held where the ship
// points now, throttle locked at zero. The kOS steering is first made slower to react (probe_steer.ks): the stopping
// time times P63_STEER_STOP_MULT, the settling times times P63_STEER_TS_MULT and the torque dead zone times P63_STEER_EPS_MULT. The dead-zone maximum is set before
// the minimum because kOS raises the maximum if the minimum is set above it (docs, steeringmanager).
// ctl_release puts them back (STEERINGMANAGER:RESETTODEFAULT, as the probe did between configurations).
FUNCTION ctl_start {
  IF CTL_DRY { RETURN. }
  STEERINGMANAGER:RESETTODEFAULT().
  SET STEERINGMANAGER:MAXSTOPPINGTIME TO STEERINGMANAGER:MAXSTOPPINGTIME * P63_STEER_STOP_MULT.
  SET STEERINGMANAGER:PITCHTS TO STEERINGMANAGER:PITCHTS * P63_STEER_TS_MULT.
  SET STEERINGMANAGER:YAWTS TO STEERINGMANAGER:YAWTS * P63_STEER_TS_MULT.
  SET STEERINGMANAGER:ROLLTS TO STEERINGMANAGER:ROLLTS * P63_STEER_TS_MULT.
  SET STEERINGMANAGER:TORQUEEPSILONMAX TO STEERINGMANAGER:TORQUEEPSILONMAX * P63_STEER_EPS_MULT.
  SET STEERINGMANAGER:TORQUEEPSILONMIN TO STEERINGMANAGER:TORQUEEPSILONMIN * P63_STEER_EPS_MULT.
  RCS ON.
  SAS OFF.
  SET CTL_DIR TO SHIP:FACING:FOREVECTOR.
  // The roll reference is the window face, not the top: the steering lock adds CTL_ROLL (180 for a bottom window) to it, so the two cancel and the
  // ship holds the attitude it has. With the top vector here, a BOTTOM window made the ship roll 180 degrees before PRO (1.3.1 holds until PRO).
  SET CTL_UP TO ctl_window_face_vec().
  SET CTL_ROLL TO ctl_roll_for_window().
  SET CTL_GOAL_DIR TO CTL_DIR.
  SET CTL_GOAL_UP TO CTL_UP.
  SET CTL_SLEW_T TO TIME:SECONDS.
  SET CTL_THR TO 0.
  ctl_steer_lock().
  LOCK THROTTLE TO CTL_THR.
  SET CTL_THR_LOCKED TO TRUE.
}

// ctl_set_command: the new command from guidance. dir_vec is the direction the thrust axis must point (a zero vector is
// ignored and the last good direction kept), up_vec the roll reference, thr_frac the throttle 0 to 1 (clamped).
FUNCTION ctl_set_command {
  PARAMETER dir_vec, up_vec, thr_frac.
  IF dir_vec:MAG > 0 { SET CTL_GOAL_DIR TO dir_vec:NORMALIZED. }
  IF up_vec:MAG > 0 { SET CTL_GOAL_UP TO up_vec:NORMALIZED. }
  SET CTL_THR TO MAX(0, MIN(1, thr_frac)).
  // The command the steering lock follows is moved toward the goal at no more than P63_TURN_RATE_DEG_S. Handed the whole 180 degree jump, kOS fired a big burst,
  // chattered all the way round and settled; a goal that moves smoothly gives a smooth turn. No limit on the pad (CTL_DRY) or when the rate is 0.
  LOCAL now_t IS TIME:SECONDS.
  LOCAL step_deg IS P63_TURN_RATE_DEG_S * MIN(1, MAX(0, now_t - CTL_SLEW_T)).
  SET CTL_SLEW_T TO now_t.
  IF CTL_DRY OR P63_TURN_RATE_DEG_S <= 0 {
    SET CTL_DIR TO CTL_GOAL_DIR.
    SET CTL_UP TO CTL_GOAL_UP.
  } ELSE {
    LOCAL stepped IS ctl_slew_att(CTL_DIR, CTL_UP, CTL_GOAL_DIR, CTL_GOAL_UP, step_deg).
    SET CTL_DIR TO stepped[0].
    SET CTL_UP TO stepped[1].
  }
}

// ctl_slew_att: the attitude (nose cur_dir, roll reference cur_up) turned toward the goal attitude by at most max_deg degrees, as ONE rotation about a single fixed
// axis (what Luminary's KALCMANU does), so the body rates stay constant along the turn. Slewing the nose and the roll reference separately made the roll rate
// change all the way round and the roll chattered. Returns LIST(new_dir, new_up). Pure (the goal is returned when it is within the step).
// The rotation between the two attitudes is found from their axis triads (nose, up, nose x up): the sum of cur x goal over the three is 2 sin(angle) times
// the axis, and the sum of cur . goal is 1 + 2 cos(angle). kOS's rotation sign is not relied on: the sign that ends closer to the goal is used.
FUNCTION ctl_slew_att {
  PARAMETER cur_dir, cur_up, goal_dir, goal_up, max_deg.
  LOCAL a1 IS cur_dir:NORMALIZED.
  LOCAL b1 IS goal_dir:NORMALIZED.
  IF VECTOREXCLUDE(cur_up, a1):MAG < 1e-6 OR VECTOREXCLUDE(goal_up, b1):MAG < 1e-6 { RETURN LIST(goal_dir, goal_up). }
  LOCAL a2 IS VECTOREXCLUDE(cur_up, a1):NORMALIZED.
  LOCAL b2 IS VECTOREXCLUDE(goal_up, b1):NORMALIZED.
  LOCAL a3 IS VCRS(a1, a2).
  LOCAL b3 IS VCRS(b1, b2).
  LOCAL sum_cross IS VCRS(a1, b1) + VCRS(a2, b2) + VCRS(a3, b3).
  LOCAL sum_dot IS VDOT(a1, b1) + VDOT(a2, b2) + VDOT(a3, b3).
  LOCAL gap_deg IS ARCTAN2(sum_cross:MAG / 2, (sum_dot - 1) / 2).
  IF gap_deg <= max_deg { RETURN LIST(goal_dir, goal_up). }
  LOCAL axis_vec IS sum_cross.
  IF axis_vec:MAG < 1e-3 {            // about 180 degrees: the axis is the way between each pair (any pair that is not exactly opposite)
    SET axis_vec TO a1 + b1.
    IF axis_vec:MAG < 1e-3 { SET axis_vec TO a2 + b2. }
    IF axis_vec:MAG < 1e-3 { SET axis_vec TO a3 + b3. }
  }
  SET axis_vec TO axis_vec:NORMALIZED.
  LOCAL dir_a IS ANGLEAXIS(max_deg, axis_vec) * a1.
  LOCAL up_a IS ANGLEAXIS(max_deg, axis_vec) * a2.
  LOCAL dir_b IS ANGLEAXIS(-max_deg, axis_vec) * a1.
  LOCAL up_b IS ANGLEAXIS(-max_deg, axis_vec) * a2.
  IF VANG(dir_a, b1) + VANG(up_a, b2) <= VANG(dir_b, b1) + VANG(up_b, b2) { RETURN LIST(dir_a, up_a). }
  RETURN LIST(dir_b, up_b).
}

// ctl_ullage: RCS ullage on or off. Ullage pushes the whole ship forward along its thrust axis (SHIP:CONTROL:FORE) so the
// propellant settles at the tank outlets before the engine lights. Off returns the raw controls to the player.
FUNCTION ctl_ullage {
  PARAMETER on_flag.
  IF CTL_DRY { RETURN. }
  IF on_flag {
    RCS ON.
    SET SHIP:CONTROL:FORE TO 1.
  } ELSE {
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  }
}

// ctl_hold: hand the attitude to the pilot (the SAS switch turned on). Unlock steering FIRST (docs: SAS and LOCK STEERING must not both
// be on), then SAS on in stability assist, which holds the attitude when the pilot lets go. Throttle stays locked.
FUNCTION ctl_hold {
  IF CTL_DRY { RETURN. }
  UNLOCK STEERING.
  SAS ON.
  SET SASMODE TO "STABILITYASSIST".
}

// ctl_sas_read: is KSP's SAS switched on? The SAS button is the pilot's AUTO / ATT HOLD switch: lit = ATT HOLD. on the pad
// (CTL_DRY) there is no ship to read, so it returns assumed_on, the state the caller expects, i.e. "no change".
FUNCTION ctl_sas_read {
  PARAMETER assumed_on.
  IF CTL_DRY { RETURN assumed_on. }
  RETURN SAS.
}

// ctl_auto: take the attitude back (the SAS switch turned off). SAS off, then the steering lock again on the live command.
FUNCTION ctl_auto {
  IF CTL_DRY { RETURN. }
  SAS OFF.
  ctl_steer_lock().
}

// ctl_release: give everything back to the pilot (V34, programme end). The pilot's own throttle lever is first set to the
// throttle the programme last commanded, so unlocking does not snap the engine to wherever the lever was left.
// hold_attitude: TRUE when the engine is burning. The ship is then handed over in SAS stability assist, which holds the
// attitude it has, so releasing the steering lock does not leave a burning lander free to tumble. Before ignition it
// is released with SAS off.
FUNCTION ctl_release {
  PARAMETER hold_attitude.
  IF CTL_DRY { RETURN. }
  IF CTL_THR_LOCKED { SET SHIP:CONTROL:PILOTMAINTHROTTLE TO CTL_THR. }      // when the lever already drives the engine (ctl_man_direct) it is left as the pilot has it
  UNLOCK STEERING.
  STEERINGMANAGER:RESETTODEFAULT().
  UNLOCK THROTTLE.
  SET CTL_THR_LOCKED TO FALSE.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  IF hold_attitude { SAS ON. } ELSE { SAS OFF. }
}

// ctl_find_engine: the descent engine, taken as the engine with the most vacuum thrust (the descent engine, 46.7 kN,
// against the ascent engine, 15.6 kN, on the Realism Overhaul LM). Returns the engine part, or 0 (a number) when the
// ship has no engines. POSSIBLETHRUSTAT(0) is the thrust in a vacuum at full throttle even when the engine is off
// (kOS docs, structures/vessels/engine).
FUNCTION ctl_find_engine {
  LIST ENGINES IN engines_list.
  LOCAL best IS 0.
  LOCAL best_thrust IS 0.
  FOR eng IN engines_list {
    LOCAL possible IS eng:POSSIBLETHRUSTAT(0).
    IF possible > best_thrust {
      SET best TO eng.
      SET best_thrust TO possible.
    }
  }
  RETURN best.
}

// ctl_find_ascent_engine (release 1.5): the ascent engine: of the engines that are never decoupled (Part:DECOUPLEDIN below 0), the one with the most
// vacuum thrust; 0 when there is none. ctl_find_engine (most thrust) finds the descent engine and must not be used for the ascent.
FUNCTION ctl_find_ascent_engine {
  LOCAL eng_list IS LIST().
  LIST ENGINES IN eng_list.
  LOCAL best IS 0.
  LOCAL best_thrust IS 0.
  FOR eng IN eng_list {
    IF eng:DECOUPLEDIN < 0 {
      LOCAL thrust_kn IS eng:POSSIBLETHRUSTAT(0).
      IF thrust_kn > best_thrust {
        SET best TO eng.
        SET best_thrust TO thrust_kn.
      }
    }
  }
  RETURN best.
}

// ---- Ascent control layer (release 1.5): staging and ascent steering ----------------------------------------------------------
// Probed in KSP (J craft, from the surface; research-1.5-ascent.md section 10a): shutting the descent engine down, the decoupler's
// event and the ascent engine's ACTIVATE in one tick separate the stages, and kOS steering on RCS alone holds the ascent stage.

// ctl_core_stays: this kOS processor is never decoupled, so it goes up with the ascent stage.
FUNCTION ctl_core_stays {
  RETURN CORE:PART:DECOUPLEDIN < 0.
}

// ctl_find_decoupler: the LM decoupler's separate event as LEXICON MODULE, EVENT, or FALSE: a part whose name contains "LEMDecoupler"
// (ROC-LEMDecouplerBDB on both craft), a module containing "Decouple" (ModuleDecouple), an event containing "decouple" and not "staging".
FUNCTION ctl_find_decoupler {
  FOR prt IN SHIP:PARTS {
    IF prt:NAME:CONTAINS("LEMDecoupler") {
      FOR module_name IN prt:MODULES {
        IF module_name:CONTAINS("Decouple") {
          LOCAL mdl IS prt:GETMODULE(module_name).
          FOR event_name IN mdl:ALLEVENTNAMES {
            IF event_name:CONTAINS("decouple") AND NOT event_name:CONTAINS("staging") {
              RETURN LEXICON("MODULE", mdl, "EVENT", event_name).
            }
          }
        }
      }
    }
  }
  RETURN FALSE.
}

// ctl_stage_ascent: at ignition: shut down the engines that will be left behind, activate the ascent engine, and a fraction of a second later fire
// the decoupler's event. Returns "", or why it failed (for the first two reasons nothing has been touched). With no event the stage list is pressed
// instead until the ascent engine is lit, at most ASC_STAGE_PRESSES times (the H craft needs two: decoupler, then engine); that takes a few
// ticks. The throttle is the caller's (ctl_ascent_start). On the pad (CTL_DRY) it is only counted.
// Departure from Apollo: the crew's ABORT STAGE and ENGINE ARM ASCENT presses are not made.
FUNCTION ctl_stage_ascent {
  PARAMETER asc_eng.
  IF CTL_DRY {
    SET CTL_DRY_STAGES TO CTL_DRY_STAGES + 1.
    RETURN "".
  }
  IF NOT asc_eng:ISTYPE("Engine") { RETURN "no ascent engine found". }
  IF NOT ctl_core_stays() { RETURN "this kOS processor would be left on the descent stage". }
  LOCAL decoupler IS ctl_find_decoupler().
  LOCAL eng_list IS LIST().
  LIST ENGINES IN eng_list.
  FOR eng IN eng_list { IF eng:DECOUPLEDIN >= 0 { eng:SHUTDOWN(). } }
  IF decoupler:ISTYPE("Lexicon") {
    // Lit first, still attached, and separated once the thrust has built up, so the ascent stage does not drop back while the engine spools up.
    // With no thrust after ASC_LIGHT_MAX_S the stages separate anyway (V97 then shows).
    asc_eng:ACTIVATE().
    LOCAL give_up IS TIME:SECONDS + ASC_LIGHT_MAX_S.
    WAIT UNTIL asc_eng:THRUST >= ASC_LIGHT_FRAC * asc_eng:POSSIBLETHRUSTAT(0) OR TIME:SECONDS >= give_up.
    decoupler["MODULE"]:DOEVENT(decoupler["EVENT"]).
    RETURN "".
  }
  LOCAL lit_eng IS asc_eng.
  LOCAL presses IS 0.
  UNTIL lit_eng:IGNITION OR presses >= ASC_STAGE_PRESSES {
    WAIT UNTIL STAGE:READY.
    STAGE.
    SET presses TO presses + 1.
    LOCAL found IS ctl_find_ascent_engine().            // looked up again: the ship has just changed
    IF found:ISTYPE("Engine") { SET lit_eng TO found. }
  }
  IF NOT lit_eng:IGNITION { RETURN "the ascent engine is not lit after staging". }
  RETURN "".
}

// ctl_ascent_start: take control for the ascent: ctl_start, then the ascent stage's steering tuning in place of the descent's, and the
// throttle command at 1 (the ascent engine is not throttled). sas_was_on: SAS (ATT HOLD) was on before the call (ctl_start turns it off),
// so the attitude is handed back at once. Nothing on the pad (CTL_DRY).
FUNCTION ctl_ascent_start {
  PARAMETER sas_was_on.
  IF CTL_DRY { RETURN. }
  ctl_start().
  STEERINGMANAGER:RESETTODEFAULT().
  SET STEERINGMANAGER:MAXSTOPPINGTIME TO STEERINGMANAGER:MAXSTOPPINGTIME * ASC_STEER_STOP_MULT.
  SET STEERINGMANAGER:PITCHTS TO STEERINGMANAGER:PITCHTS * ASC_STEER_TS_MULT.
  SET STEERINGMANAGER:YAWTS TO STEERINGMANAGER:YAWTS * ASC_STEER_TS_MULT.
  SET STEERINGMANAGER:ROLLTS TO STEERINGMANAGER:ROLLTS * ASC_STEER_TS_MULT.
  SET STEERINGMANAGER:TORQUEEPSILONMAX TO STEERINGMANAGER:TORQUEEPSILONMAX * ASC_STEER_EPS_MULT.
  SET STEERINGMANAGER:TORQUEEPSILONMIN TO STEERINGMANAGER:TORQUEEPSILONMIN * ASC_STEER_EPS_MULT.
  SET CTL_THR TO 1.
  IF sas_was_on { ctl_hold(). }
}

// ctl_rcs_fore_off: stop the main throttle firing the RCS forward (RCS:FOREBYTHROTTLE, kOS docs) on every thruster part that has it on, and return
// those parts for ctl_rcs_fore_restore. Seen in flight: with the ascent engine out and the throttle full, the RCS pushed forward on ascent
// propellant. The probe of 1.4 (research 16) did not prove this setting is the only cause. On the pad only CTL_DRY_FORE changes.
FUNCTION ctl_rcs_fore_off {
  LOCAL changed IS LIST().
  IF CTL_DRY { SET CTL_DRY_FORE TO FALSE. RETURN changed. }
  LOCAL rcs_list IS LIST().
  LIST RCS IN rcs_list.
  FOR thruster IN rcs_list {
    IF thruster:FOREBYTHROTTLE {
      SET thruster:FOREBYTHROTTLE TO FALSE.
      changed:ADD(thruster).
    }
  }
  RETURN changed.
}

// ctl_rcs_fore_restore: put the setting back on the parts ctl_rcs_fore_off changed.
FUNCTION ctl_rcs_fore_restore {
  PARAMETER changed.
  IF CTL_DRY { SET CTL_DRY_FORE TO TRUE. RETURN. }
  FOR thruster IN changed { SET thruster:FOREBYTHROTTLE TO TRUE. }
}

// ctl_engine_on: switch the engine on (Engine:ACTIVATE). It then burns at whatever the throttle lock says; the ignition
// itself needs the propellant settled (ullage) and an ignition left, which Realism Overhaul enforces.
FUNCTION ctl_engine_on {
  PARAMETER eng.
  IF CTL_DRY { RETURN. }
  eng:ACTIVATE().
}

// ---- Burn control layer (release 1.4, P40 / P41): ENG ARM, ENG ARM OFF, the MAN throttle ----------------------------------------------
// ctl_arm: ENG ARM. Engine on and the throttle command at the engine's minimum (Apollo: the burn starts at minimum throttle).
FUNCTION ctl_arm {
  PARAMETER eng.
  SET CTL_THR TO THR_MIN_FRAC.
  ctl_engine_on(eng).
}

// ctl_release_throttle_lock: drop the programme's throttle lock and neutralise the translation inputs, so a raised lever is the pilot's
// again. With RCS on and the engine shut down, KSP's Fore By Throttle makes the lever fire the RCS (research section 16: probe_throttle
// batch 1, phase 2 clear, a LOCK THROTTLE TO 0 suppressed it; whether it still fires after an engine run is the user's recollection,
// "I think", not a clear number). Nothing on the pad (CTL_DRY).
FUNCTION ctl_release_throttle_lock {
  IF CTL_DRY { RETURN. }
  UNLOCK THROTTLE.
  SET CTL_THR_LOCKED TO FALSE.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
}

// ctl_disarm: ENG ARM OFF at cutoff. Engine shut down and the command to zero (ctl_engine_off), then the throttle lock is dropped so the
// lever drives the RCS (see ctl_release_throttle_lock for what the probe showed). The lever itself is zeroed too: on MAN the pilot has raised it
// for the burn (about 40 percent for the DOI) and it would stay there, so with RCS on the shut-down ship would be pushed forward at once.
FUNCTION ctl_disarm {
  PARAMETER eng.
  ctl_engine_off(eng).
  ctl_release_throttle_lock().
  IF NOT CTL_DRY { SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0. }
}

// ctl_man_throttle: the MAN throttle. The lever (0 to 1) floored at the engine's minimum so a lever at zero cannot flame the engine
// out mid-burn (the real computer reads the throttle switch only for the V50 N25 prompt; MAN is a hardware override).
FUNCTION ctl_man_throttle {
  RETURN MAX(THR_MIN_FRAC, MIN(1, ctl_pilot_throttle())).
}

// ctl_man_direct: the MAN throttle, called every cycle while the engine burns on MAN. The engine is given to KSP's own lever: the programme's throttle lock is
// dropped the first time (the lever is first raised to the minimum if it was below, so the drop cannot shut the engine down) and after that the only thing done
// is the protection: a lever below the engine's minimum is raised to it, on the lever itself. Above the minimum the lever is left alone, so it is the pilot's
// throttle with no programme in between. Returns the throttle the engine now has (the lever floored at the minimum, at most 1), for the display and the log.
// On the pad (CTL_DRY) there is no lever to move: the same value as ctl_man_throttle.
FUNCTION ctl_man_direct {
  IF CTL_DRY { RETURN ctl_man_throttle(). }
  LOCAL lever IS ctl_pilot_throttle().
  IF lever < THR_MIN_FRAC {
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO THR_MIN_FRAC.
    SET lever TO THR_MIN_FRAC.
  }
  IF CTL_THR_LOCKED {
    UNLOCK THROTTLE.
    SET CTL_THR_LOCKED TO FALSE.
  }
  RETURN MIN(1, lever).
}

// ctl_thrust_pct: thrust now as a percent of full thrust, 0 to 100; 0 when there is no full thrust (the "raise throttle" readout).
FUNCTION ctl_thrust_pct {
  PARAMETER thrust_now, thrust_full.
  IF thrust_full <= 0 { RETURN 0. }
  RETURN MAX(0, MIN(100, 100 * thrust_now / thrust_full)).
}

// ctl_burn_end: the programme END for a burn: ullage off, ENG ARM OFF, then the controls back (ctl_release; hold_attitude as there).
FUNCTION ctl_burn_end {
  PARAMETER eng, hold_attitude.
  ctl_ullage(FALSE).
  ctl_disarm(eng).
  ctl_release(hold_attitude).
}

// ctl_att_error_deg: how far the ship is from the attitude the steering lock is told to hold, in degrees: the larger of
// the angle between the thrust axes (fore vectors) and between the window-side axes (top vectors), so a wrong roll
// counts too. On the pad (CTL_DRY) there is no ship: 999, which never counts as settled.
FUNCTION ctl_att_error_deg {
  IF CTL_DRY { RETURN 999. }
  LOCAL cmd_dir IS ANGLEAXIS(CTL_ROLL, CTL_GOAL_DIR) * LOOKDIRUP(CTL_GOAL_DIR, CTL_GOAL_UP).          // against the goal, so the attitude is "reached" only when the whole turn is done
  RETURN MAX(VANG(SHIP:FACING:FOREVECTOR, cmd_dir:FOREVECTOR), VANG(SHIP:FACING:TOPVECTOR, cmd_dir:TOPVECTOR)).
}

// ctl_rate_deg_s: how fast the ship is turning, degrees per second (SHIP:ANGULARVEL is in radians per second).
FUNCTION ctl_rate_deg_s {
  IF CTL_DRY { RETURN 999. }
  RETURN SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI.
}

// ctl_warp_to: start an automated warp to a universal time (kOS TimeWarp:WARPTO; it returns at once and the main loop
// keeps running). ctl_warp_stop: cancel any warp (the pilot can also cancel it with KSP's own key).
FUNCTION ctl_warp_to {
  PARAMETER target_ut.
  IF CTL_DRY { RETURN. }
  KUNIVERSE:TIMEWARP:WARPTO(target_ut).
}
FUNCTION ctl_warp_stop {
  IF CTL_DRY { RETURN. }
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
}
