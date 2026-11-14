// lm_p64.ks -- the P64 approach programme (milestone 4): the pilot's redesignation clicks and the landing-point maths
// (pure: nothing reads kOS, so they are tested on the pad by scripts/tests/test_p64.ks), then the programme itself:
//   p64_start(prog, site_lat, site_lng, site_alt)  takes P63's programme state over (the engine, attitude mode, radar and window
//                                                  bookkeeping carry on without a gap) and returns it as the P64 state
//   p64_sample(prog)                               read the pitch and yaw keys into the click detector (call every 0.02 s)
//   p64_step(prog, state, derived, ks)             one cycle; returns what the main loop shows (the same keys as p63_step); at the
//                                                  end of the approach it asks for the handover to P65 (lm_p65.ks)
//   p64_end(prog)                                  gives the controls back (the same as P63's)
//
// P64 is the second phase of the lunar landing: the same quadratic guidance as the braking phase (P63) with the approach
// targets, the crew window turned toward the landing site, and the chance to move the aim point ("redesignate") with
// hand-controller clicks. Luminary source: LUNAR_LANDING_GUIDANCE_EQUATIONS.agc (REDESIG 335-415, STARTP64 260-270,
// P64DISPS 856-890, the redesignator trap 1120-1212).
//
// Redesignation in the real LM (source 1120-1205): the rotational hand controller's pitch and yaw deflections set bits in
// channel 31; a monitor counts one click for each deflection (it waits for the stick to come back before it counts the
// next), only in AUTO and only while P64 runs. Each pitch click moves the aim point 1/2 degree (ELEACH), each yaw click
// 2 degrees (AZEACH). Here the keyboard's pitch and yaw give -1, 0 or 1; see clk_* below.
//
// Simplifications (spec section 10): the keyboard stands in for the hand controller's discrete bits; the look angle on the
// DSKY stands in for the scribed window; the time-to-redesignation display (TREDES) is not shown and the display does not
// flash again after each redesignation.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent/lm_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/lm/descent/lm_p63.ks").                 // burn_shared_step and p63_end, which P64 shares

GLOBAL P64_LOG_PATH IS "0:/lm/logs/p64.log".          // one line per cycle, read back after a flight

// ---- The click detector --------------------------------------------------------------------------------------

// clk_new: EL_HELD and AZ_HELD are -1, 0 or 1: which way the pitch / yaw key is held down now (0 = released). EL and AZ are
// the clicks waiting to be used, signed and already multiplied by P64_PITCH_SIGN / P64_YAW_SIGN. COUNT is the number of
// clicks counted so far (for tests and the log).
FUNCTION clk_new {
  RETURN LEXICON("EL_HELD", 0, "AZ_HELD", 0, "EL", 0, "AZ", 0, "COUNT", 0).
}

// clk_axis: one axis of the detector. held is the direction held at the last sample (-1, 0 or 1), x the stick value now.
// A value at or beyond P64_CLICK_THRESH (either sign) in a direction that is not the held one is a click. The key counts as
// released only when |x| is back inside P64_CLICK_REARM (between the two the previous state stays, so a stick resting
// between them does not chatter). A direct reversal (held +1, now at or below -THRESH) is a new click.
// Returns LIST(held now, click): click is -1, 0 or 1, the direction of the new click.
FUNCTION clk_axis {
  PARAMETER held, x.
  LOCAL click IS 0.
  LOCAL dir_now IS 0.
  IF x >= P64_CLICK_THRESH { SET dir_now TO 1. }
  ELSE IF x <= -P64_CLICK_THRESH { SET dir_now TO -1. }
  IF dir_now <> 0 AND dir_now <> held {
    SET click TO dir_now.
    SET held TO dir_now.
  } ELSE IF held <> 0 AND ABS(x) < P64_CLICK_REARM {
    SET held TO 0.
  }
  RETURN LIST(held, click).
}

// clk_sample: feed the stick values (-1 to 1) of one moment. Call it often (every 0.02 s while P64 runs) so a short key tap
// is not missed between two guidance cycles.
FUNCTION clk_sample {
  PARAMETER clk, pitch, yaw.
  LOCAL el_out IS clk_axis(clk["EL_HELD"], pitch).
  LOCAL az_out IS clk_axis(clk["AZ_HELD"], yaw).
  SET clk["EL_HELD"] TO el_out[0].
  SET clk["AZ_HELD"] TO az_out[0].
  IF el_out[1] <> 0 {
    SET clk["EL"] TO clk["EL"] + el_out[1] * P64_PITCH_SIGN.
    SET clk["COUNT"] TO clk["COUNT"] + 1.
  }
  IF az_out[1] <> 0 {
    SET clk["AZ"] TO clk["AZ"] + az_out[1] * P64_YAW_SIGN.
    SET clk["COUNT"] TO clk["COUNT"] + 1.
  }
}

// clk_take: the waiting clicks, as LEXICON("EL", n, "AZ", n), and the waiting counts back to zero (the held state stays).
FUNCTION clk_take {
  PARAMETER clk.
  LOCAL out IS LEXICON("EL", clk["EL"], "AZ", clk["AZ"]).
  SET clk["EL"] TO 0.
  SET clk["AZ"] TO 0.
  RETURN out.
}

// clk_discard: forget the waiting clicks (used when redesignation is not allowed: before PRO, in ATT HOLD, or too late).
FUNCTION clk_discard {
  PARAMETER clk.
  SET clk["EL"] TO 0.
  SET clk["AZ"] TO 0.
}

// ---- Redesignation ---------------------------------------------------------------------------------------------

// p64_redes_open: redesignation is possible while the time-to-go is more than TCGFAPPR + P64_REDES_CLOSE_S (Luminary's TREDES
// reaches zero two guidance passes before the guidance axes freeze at TCGFAPPR; TDISPSET, source 1381-1410).
FUNCTION p64_redes_open {
  PARAMETER tgo.
  RETURN tgo > TCGFAPPR + P64_REDES_CLOSE_S.
}

// redes_los: the landing site vector after clicks, REDESIG (source 338-415), in real size (the source keeps its vectors at
// half size and its scale factors cancel). land_vec and r_vec as in lm_frame.ks (from the body's centre), ynb_vec the LM
// +Y axis (crossrange), el_rad and az_rad the sums of the clicks times ELEACH / AZEACH (radians).
//   u = unit(LAND - R)                     the line of sight to the site
//   w = u + el (u x YNB) - az YNB          the click moves it: el in the vertical plane, az sideways ((u x YNB) is the
//                                          right-handed product of the AGC, lm_cross)
//   w_up = min(w_up, DEPRCRIT)             the line of sight may not rise above 1.1 degrees below the horizontal (REDES1)
//   s = (LAND - R)_up / w_up               the new aim point is on w at the same height below the ship as before
//   LAND' = |LAND| unit(R + s w)           and put back on the sphere of the site's radius
// "up" is unit(LAND). Returns land_vec unchanged for no clicks, a ship at the site or at or below the site's height.
FUNCTION redes_los {
  PARAMETER land_vec, r_vec, ynb_vec, el_rad, az_rad.
  IF el_rad = 0 AND az_rad = 0 { RETURN land_vec. }
  LOCAL los_vec IS land_vec - r_vec.
  IF land_vec:MAG = 0 OR los_vec:MAG = 0 { RETURN land_vec. }
  LOCAL up_vec IS land_vec:NORMALIZED.
  LOCAL drop IS VDOT(los_vec, up_vec).               // how far the site is above the ship (negative = below it)
  IF drop >= 0 { RETURN land_vec. }
  LOCAL u_vec IS los_vec:NORMALIZED.
  LOCAL w_vec IS u_vec + lm_cross(u_vec, ynb_vec) * el_rad - ynb_vec * az_rad.
  LOCAL w_up IS VDOT(w_vec, up_vec).
  IF w_up >= P64_DEPRCRIT { SET w_vec TO w_vec - up_vec * (w_up - P64_DEPRCRIT). SET w_up TO P64_DEPRCRIT. }
  RETURN (r_vec + w_vec * (drop / w_up)):NORMALIZED * land_vec:MAG.
}

// ---- The programme -------------------------------------------------------------------------------------------

// p64_start: P63 has just reported HANDOVER. prog is P63's programme lexicon and is changed and returned as P64's: the
// time-to-go gets Luminary's DELTTFAP step (STARTP64: TTF is negative there, so adding DELTTFAP = -110 s lengthens the plain
// positive time-to-go by 110 s, because the approach targets lie past the braking target in time), the click detector and
// the redesignation permit are new, and the site is kept as latitude, longitude and height so a redesignated site can follow
// the turning Moon (lm_vehicle.ks builds the site vector from them each cycle). The old P63 log is left as it is; P64 writes its own.
FUNCTION p64_start {
  PARAMETER prog, site_lat, site_lng, site_alt.
  SET prog["PROG_NO"] TO 64.
  SET prog["TGO"] TO prog["TGO"] - DELTTFAP.
  SET prog["CLK"] TO clk_new().
  SET prog["PERMIT"] TO FALSE.               // set by PRO: Luminary's REDFLAG
  SET prog["SHOWN"] TO FALSE.                // the V06 N64 display has been requested
  SET prog["HANDOFF_T"] TO -1.
  SET prog["SITE_LAT"] TO site_lat.
  SET prog["SITE_LNG"] TO site_lng.
  SET prog["SITE_ALT"] TO site_alt.
  SET prog["EL_TOTAL"] TO 0.                 // clicks applied so far, for the log
  SET prog["AZ_TOTAL"] TO 0.
  SET prog["REDES_ENDED"] TO FALSE.          // the "redesignation closed" message has been given
  IF LM_LOG AND NOT CTL_DRY {
    IF EXISTS(P64_LOG_PATH) { DELETEPATH(P64_LOG_PATH). }
    LOG "UT,TGO,ALARM,THR,MODE,HCALC,HDOT,ABVEL,LOOKANGL,RGU_X,RGU_Y,RGU_Z,VGU_X,VGU_Y,VGU_Z,ATT_ERR_DEG,PERMIT,REDES_OPEN,EL_CLICKS,AZ_CLICKS,SITE_LAT,SITE_LNG,ALT_LAMP,VEL_LAMP,THRUST_FRAC" TO P64_LOG_PATH.
    LOG "# P64 start: time to go " + ROUND(prog["TGO"], 1) + " s (DELTTFAP " + DELTTFAP + " s applied)" TO P64_LOG_PATH.
  }
  RETURN prog.
}

// p64_sample: read the pitch and yaw keys into the click detector. The main loop calls it every 0.02 s so a key tap shorter
// than one 0.25 s cycle still counts (spec section 5).
FUNCTION p64_sample {
  PARAMETER prog.
  clk_sample(prog["CLK"], ctl_pilot_pitch(), ctl_pilot_yaw()).
}

// p64_apply_clicks: use the clicks that have built up since the last cycle. They are used only when the pilot has pressed PRO,
// the redesignation window is still open and the attitude mode is AUTO (in ATT HOLD Luminary ignores them); otherwise they are
// thrown away, not kept for later. Returns TRUE when the aim point moved (no terminal message). The new site is also stored as latitude and
// longitude (kOS Body:GEOPOSITIONOF takes a position measured from the ship, so the body's position is added back).
// YNB, the LM +Y axis, is the cross product of the window face (LM +Z) and the ship's up axis (LM +X), right-handed.
FUNCTION p64_apply_clicks {
  PARAMETER prog, state.
  LOCAL clicks IS clk_take(prog["CLK"]).
  IF clicks["EL"] = 0 AND clicks["AZ"] = 0 { RETURN FALSE. }
  IF NOT (prog["PERMIT"] AND p64_redes_open(prog["TGO"]) AND prog["ATT"]["MODE"] = "AUTO") { RETURN FALSE. }
  LOCAL ynb_vec IS lm_cross(ctl_window_face_vec(), state["XNB"]).
  LOCAL new_land IS redes_los(prog["LAND"], state["R"], ynb_vec, clicks["EL"] * P64_ELEACH_RAD, clicks["AZ"] * P64_AZEACH_RAD).
  IF (new_land - prog["LAND"]):MAG = 0 { RETURN FALSE. }
  SET prog["LAND"] TO new_land.
  SET prog["EL_TOTAL"] TO prog["EL_TOTAL"] + clicks["EL"].
  SET prog["AZ_TOTAL"] TO prog["AZ_TOTAL"] + clicks["AZ"].
  IF NOT CTL_DRY {
    LOCAL geo IS SHIP:BODY:GEOPOSITIONOF(new_land + SHIP:BODY:POSITION).
    SET prog["SITE_LAT"] TO geo:LAT.
    SET prog["SITE_LNG"] TO geo:LNG.
    SET prog["SITE_ALT"] TO new_land:MAG - SHIP:BODY:RADIUS.
  }
  RETURN TRUE.
}

// p64_step: one cycle, the same arguments and returned keys as p63_step (SET_VERB, SET_NOUN, KEY_REL, BLANK, FLASH, ALARM,
// ALT_LAMP, VEL_LAMP, EXTRA, MSG, ENDED, HANDOVER (TRUE once, at the handoff: the main loop then starts P65), PROG_NO (64)).
//   - the time-to-go is moved on by the time since the last cycle, then the guidance pass runs with the approach targets;
//   - PRO permits redesignation; clicks then move the landing site (p64_apply_clicks);
//   - the attitude command is the guidance thrust direction; the window is held toward the site (UP, EXNORM) or the ship's
//     own roll is kept with the stick roll (KEEP, as in P63);
//   - the display shows V06 N64, flashing with KEY REL lit until PRO;
//   - below TENDAPPR the step returns HANDOVER once and the main loop starts P65 (lm_p65.ks), which takes this state over.
FUNCTION p64_step {
  PARAMETER prog, state, derived, ks.
  LOCAL now_ut IS state["T"].
  LOCAL dt IS MAX(0, now_ut - prog["T_LAST"]).
  SET prog["T_LAST"] TO now_ut.
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  LOCAL msg IS "".
  LOCAL terminating IS ks["VERB"] = 34.

  SET prog["TGO"] TO MAX(1, prog["TGO"] - dt).
  IF pro_pressed AND NOT prog["PERMIT"] {
    SET prog["PERMIT"] TO TRUE.
    SET msg TO "P64: REDESIGNATION PERMITTED. PITCH KEYS MOVE THE AIM POINT 0.5 DEG, YAW KEYS 2 DEG (AUTO ONLY).".
  }
  p64_apply_clicks(prog, state).               // no terminal message per click: the look angle (R1) and the site vector show it
  // Once, when the redesignation window closes (about 34 s to go), say that the aim point is now fixed.
  IF NOT prog["REDES_ENDED"] AND NOT p64_redes_open(prog["TGO"]) {
    SET prog["REDES_ENDED"] TO TRUE.
    SET msg TO (msg + " P64: REDESIGNATION CLOSED. THE AIM POINT IS NOW FIXED."):TRIM.
  }

  // ---- guidance with the approach targets ----
  LOCAL gp IS prog["GP"].
  IF derived["VALID"] {
    LOCAL cg_last IS FALSE.
    IF gp:HASKEY("CG") { SET cg_last TO gp["CG"]. }
    SET gp TO guid_pass(state, prog["LAND"], prog["WM"], prog["TGO"], prog["THR"], guid_targets_approach(), cg_last).
    IF gp["VALID"] { SET prog["TGO"] TO gp["TGO"]. SET prog["GP"] TO gp. }
  }

  // ---- the commanded attitude, window and throttle ----
  LOCAL dir_cmd IS prog["BURN_DIR"].
  IF gp:HASKEY("AFC") {
    SET dir_cmd TO cg_unapply(gp["CG"], gp["AFC"]).
    SET prog["THR"] TO gp["THR"].
    SET prog["BURN_DIR"] TO dir_cmd.
  }
  IF prog["WINDOW_MODE"] = "UP" {
    IF gp:HASKEY("CG") {
      LOCAL win_vec IS win_perp(win_exnorm(prog["LAND"], state["R"], state["XNB"], gp["CG"]), dir_cmd).
      IF win_vec:MAG > 0 { SET prog["WCMD"] TO win_vec. }
    }
  } ELSE {
    LOCAL stick IS ctl_pilot_roll().
    IF prog["ATT"]["MODE"] <> "AUTO" { SET stick TO 0. }
    SET prog["WCMD"] TO win_hold(ctl_window_face_vec(), dir_cmd, prog["WCMD"], stick).
  }
  ctl_set_command(dir_cmd, prog["WCMD"], prog["THR"]).

  // ---- handoff to P65: the main loop starts P65 on the "HANDOVER" flag below (it takes this programme's state over) ----
  LOCAL handover IS FALSE.
  IF gp:HASKEY("HANDOFF") AND gp["HANDOFF"] AND prog["HANDOFF_T"] < 0 {
    SET prog["HANDOFF_T"] TO now_ut.
    SET handover TO TRUE.
    SET msg TO "P64 COMPLETE (time to go below " + TENDAPPR + " s). P65 STARTS.".
  }

  // ---- attitude mode, deadband, radar lamps, delta-v (shared with P63; the engine is burning, so the lock stays on) ----
  LOCAL shared_msg IS burn_shared_step(prog, state, derived, dt, TRUE, "P64").
  IF shared_msg <> "" { SET msg TO shared_msg. }

  // ---- the display: V06 N64, flashing with KEY REL until PRO ----
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT prog["SHOWN"] AND NOT terminating {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO 6.
    SET set_noun TO 64.
  }
  LOCAL flashing IS NOT prog["PERMIT"].
  LOCAL alarm_no IS 0.
  IF gp:HASKEY("ALARM") { SET alarm_no TO gp["ALARM"]. }
  IF alarm_no <> prog["LAST_ALARM"] {
    IF alarm_no > 0 { SET msg TO "P64 ALARM " + alarm_no + ": TIME-TO-GO NOT CONVERGED. THE GUIDANCE KEEPS THE LAST TIME-TO-GO.". }
    SET prog["LAST_ALARM"] TO alarm_no.
  }
  IF terminating { SET prog["ENDED"] TO TRUE. }
  LOCAL extra IS LEXICON("TTOGO", prog["TIG"] - now_ut, "DVTOTAL", prog["DV"], "OUTOFPLN", prog["OUTOFPLN"], "TTFDISP", prog["TGO"], "TREDES", MAX(0, prog["TGO"] - TCGFAPPR - P64_REDES_CLOSE_S)).

  p64_log(prog, gp, state, derived).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", flashing, "BLANK", FALSE,
                 "FLASH", flashing, "ALARM", alarm_no, "ALT_LAMP", prog["RAD"]["ALT_LAMP"], "VEL_LAMP", prog["RAD"]["VEL_LAMP"],
                 "EXTRA", extra, "MSG", msg, "ENDED", prog["ENDED"], "HANDOVER", handover, "PROG_NO", 64).
}

// p64_log: one line per cycle to P64_LOG_PATH.
FUNCTION p64_log {
  PARAMETER prog, gp, state, derived.
  IF CTL_DRY { RETURN. }
  LOCAL alarm_no IS 0.
  LOCAL rgu_vec IS V(0, 0, 0).
  LOCAL vgu_vec IS V(0, 0, 0).
  IF gp:HASKEY("ALARM") { SET alarm_no TO gp["ALARM"]. SET rgu_vec TO gp["RGU"]. SET vgu_vec TO gp["VGU"]. }
  LOCAL abvel IS 0.
  LOCAL hdot IS 0.
  LOCAL hcalc IS 0.
  LOCAL look IS 0.
  IF derived["VALID"] { SET abvel TO derived["ABVEL"]. SET hdot TO derived["HDOT"]. SET hcalc TO derived["HCALC"]. SET look TO derived["LOOKANGL"]. }
  LOCAL thrust_frac IS 0.
  IF state["THRUST"] > 0 { SET thrust_frac TO state["THRUST_NOW"] / state["THRUST"]. }
  IF LM_LOG { LOG "" + ROUND(state["T"], 2) + "," + ROUND(prog["TGO"], 1) + "," + alarm_no + "," + ROUND(CTL_THR, 3) + "," + prog["ATT"]["MODE"] + ","
      + ROUND(hcalc) + "," + ROUND(hdot, 1) + "," + ROUND(abvel, 1) + "," + ROUND(look, 2) + ","
      + ROUND(rgu_vec:X) + "," + ROUND(rgu_vec:Y) + "," + ROUND(rgu_vec:Z) + ","
      + ROUND(vgu_vec:X, 1) + "," + ROUND(vgu_vec:Y, 1) + "," + ROUND(vgu_vec:Z, 1) + ","
      + ROUND(ctl_att_error_deg(), 2) + "," + prog["PERMIT"] + "," + p64_redes_open(prog["TGO"]) + ","
      + prog["EL_TOTAL"] + "," + prog["AZ_TOTAL"] + "," + ROUND(prog["SITE_LAT"], 4) + "," + ROUND(prog["SITE_LNG"], 4) + ","
      + prog["RAD"]["ALT_LAMP"] + "," + prog["RAD"]["VEL_LAMP"] + "," + ROUND(thrust_frac, 3) TO P64_LOG_PATH. }
}

// p64_end: give everything back to the pilot (the same as P63's end: ullage off, steering and throttle released, the ship
// handed over in SAS stability assist while the engine burns).
FUNCTION p64_end {
  PARAMETER prog.
  p63_end(prog).
}
