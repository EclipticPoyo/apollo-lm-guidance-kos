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
//   the terrain from kOS, not the slant range along the antenna beam; the range limit RADAR_ALT_MAX_M is a chosen
//   value (the radar's hardware range is not in the sources).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").               // lm_cross, for the approach window vector (win_exnorm)

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
// measurement). Updates the lexicon's ALT_LAMP and VEL_LAMP and returns it. Negative h_calc counts as zero.
FUNCTION radar_step {
  PARAMETER rad, h_calc, h_radar, speed_surf, v_err.
  LOCAL no_alt_data IS h_radar > RADAR_ALT_MAX_M.
  IF NOT no_alt_data {
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
FUNCTION rod_new {
  RETURN LEXICON("REF", 0.5, "LAST", 0.5, "HELD", 0, "QUIET_SINCE", -1, "CLICKS", 0, "RECENTRE", FALSE).
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

// rod_take: the waiting clicks (signed sum), and the waiting count back to zero.
FUNCTION rod_take {
  PARAMETER rod.
  LOCAL n IS rod["CLICKS"].
  SET rod["CLICKS"] TO 0.
  RETURN n.
}

// rod_discard: forget the waiting clicks.
FUNCTION rod_discard {
  PARAMETER rod.
  SET rod["CLICKS"] TO 0.
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
GLOBAL CTL_ROLL IS 0.              // extra roll about the thrust axis, degrees, so the crew window faces CTL_UP
GLOBAL CTL_THR IS 0.               // throttle setting, 0 to 1
// CTL_DRY: when TRUE every function below that would write the ship's controls does nothing, so the programme's step
// (lm_p63.ks) can be run on the pad in the pad tests. Always FALSE in flight.
GLOBAL CTL_DRY IS FALSE.
GLOBAL CTL_DRY_STATUS IS "FLYING".   // what ctl_status returns on the pad (tests set it to "LANDED")

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

// ctl_pilot_throttle: the throttle lever, 0 to 1 (SHIP:CONTROL:PILOTMAINTHROTTLE: Shift raises it, Ctrl lowers it, 0.5 per second,
// even while the programme's LOCK THROTTLE is active: probe_rod.ks). 0.5 (centred) on the pad (CTL_DRY).
FUNCTION ctl_pilot_throttle {
  IF CTL_DRY { RETURN 0.5. }
  RETURN SHIP:CONTROL:PILOTMAINTHROTTLE.
}

// ctl_status: the ship's status text (SHIP:STATUS: "LANDED", "SPLASHED", "FLYING", "SUB_ORBITAL", ...). CTL_DRY_STATUS on the pad (CTL_DRY).
FUNCTION ctl_status {
  IF CTL_DRY { RETURN CTL_DRY_STATUS. }
  RETURN SHIP:STATUS.
}

// ctl_lever_centre: put the throttle lever back to 0.5 so both keys have room (writing it sticks: probe_rod.ks). Nothing on the pad.
FUNCTION ctl_lever_centre {
  IF CTL_DRY { RETURN. }
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
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
  SET CTL_UP TO SHIP:FACING:TOPVECTOR.
  SET CTL_ROLL TO ctl_roll_for_window().
  SET CTL_THR TO 0.
  ctl_steer_lock().
  LOCK THROTTLE TO CTL_THR.
}

// ctl_set_command: the new command from guidance. dir_vec is the direction the thrust axis must point (a zero vector is
// ignored and the last good direction kept), up_vec the roll reference, thr_frac the throttle 0 to 1 (clamped).
FUNCTION ctl_set_command {
  PARAMETER dir_vec, up_vec, thr_frac.
  IF dir_vec:MAG > 0 { SET CTL_DIR TO dir_vec:NORMALIZED. }
  IF up_vec:MAG > 0 { SET CTL_UP TO up_vec:NORMALIZED. }
  SET CTL_THR TO MAX(0, MIN(1, thr_frac)).
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
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO CTL_THR.
  UNLOCK STEERING.
  STEERINGMANAGER:RESETTODEFAULT().
  UNLOCK THROTTLE.
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

// ctl_engine_on: switch the engine on (Engine:ACTIVATE). It then burns at whatever the throttle lock says; the ignition
// itself needs the propellant settled (ullage) and an ignition left, which Realism Overhaul enforces.
FUNCTION ctl_engine_on {
  PARAMETER eng.
  IF CTL_DRY { RETURN. }
  eng:ACTIVATE().
}

// ctl_att_error_deg: how far the ship is from the attitude the steering lock is told to hold, in degrees: the larger of
// the angle between the thrust axes (fore vectors) and between the window-side axes (top vectors), so a wrong roll
// counts too. On the pad (CTL_DRY) there is no ship: 999, which never counts as settled.
FUNCTION ctl_att_error_deg {
  IF CTL_DRY { RETURN 999. }
  LOCAL cmd_dir IS ANGLEAXIS(CTL_ROLL, CTL_DIR) * LOOKDIRUP(CTL_DIR, CTL_UP).
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
