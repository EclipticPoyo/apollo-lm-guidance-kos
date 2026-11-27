// lm_r60.ks -- R60, the attitude manoeuvre routine of the burn programmes (release 1.4); P20, P25 and V89 use it too (release 1.5).
//   r60_new(burn_dir, burn_up)                          a fresh R60 state for a burn attitude
//   r60_step(r60, ks, att_err_deg, rate_deg_s)          one cycle; returns what to display and command
//   r60_cdu_angles(ref_dir, ref_up, cmd_dir, cmd_up)    the N18 angles (roll, pitch, yaw) of an attitude against the reference
//   lm_entr_on_request(ks, verb_no, noun_no)            did the pilot answer the flashing request verb_no noun_no with ENTR
//
// Source: Luminary 099 R60_62.agc, R60LEM (line 107):
//   TOBALL, TOBALLA (R60:120-127)  show the flashing "please perform auto manoeuvre" display with the final angles, N18 (GOPERF2R, which has
//                                  four returns: terminate = R61TEST (R60:125, 202-212: GOTOPOOH when a programme is running), proceed (PRO) =
//                                  REDOMANC (R60:126), enter (ENTR) = ENDMANU1, finished with R60 (R60:127, 157-160))
//   REDOMANC, TOBALLC (R60:132-146) the manoeuvre request: checks the G+N and AUTO switches (G+N,AUTO, R60:226-237), not set goes back to the request
//   AUTOMANV (R60:148-150)         a static, non-flashing V06 N18 during the manoeuvre (GODSPR)
//   STARTMNV (R60:153-154)         GOMANUR = KALCMANU turns the vehicle
//   ENDMANUV (R60:156)             back to TOBALLA: the flashing request again; ENTR then exits (R60:127)
// The flashing request is V50 N18 (research note, section 5 item 3; the source passes V06N18 to GOPERF2R, which makes it a "please perform" request).
//
// What this port does and does not do (documented departures):
//   * The manoeuvre is flown by the kOS steering: while TURNING the caller applies CMD_DIR and CMD_UP with ctl_set_command each cycle, which slews at
//     P63_TURN_RATE_DEG_S (one rotation about a single axis, as KALCMANU does). R60 itself reads nothing from the ship: the caller passes the attitude error
//     (ctl_att_error_deg) and the turn rate (ctl_rate_deg_s). The end of the turn is both inside P63_SETTLE_ERR_DEG and P63_SETTLE_RATE_DEG_S (no hold time).
//   * The G+N and AUTO switch test is not made (our SAS button is the attitude mode, and the turn needs steering that the programme owns).
//   * Luminary 210 shows no static V06N18 during the manoeuvre (what it shows is not determined, research section 19): both profiles use the 099 display.
//   * ENTR is the pilot's answer only while the flashing display is still the one shown (ks VERB and NOUN are the request's): the core sets ks["ENTER"] on every
//     ENTR, also the one that ends a verb the pilot keyed over the request, which must not finish R60.
//   * A PRO in the second request starts the manoeuvre again (REDOMANC, as in the first); the source loops back to the request after each turn (ENDMANUV, R60:156).
//   * N18 shows the Euler angles of the burn attitude against the reference attitude (r60_cdu_angles): our vehicle has no gimbal angles.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_axes.ks").        // axes_carry

GLOBAL R60_VERB_ASK IS 50.          // flashing V50: "please perform" (a request verb; see the header)
GLOBAL R60_NOUN_ANGLES IS 18.       // N18: roll, pitch, yaw

// lm_entr_on_request: ENTR as the answer to the flashing request verb_no noun_no. ks["ENTER"] is set on every ENTR; it only answers the request when
// the display (ks VERB and NOUN) is still the request, not a verb and noun the pilot has keyed in its place. Pure.
FUNCTION lm_entr_on_request {
  PARAMETER ks, verb_no, noun_no.
  IF NOT ks["ENTER"] { RETURN FALSE. }
  RETURN ks["VERB"] = verb_no AND ks["NOUN"] = noun_no.
}

// r60_cdu_angles: the roll, pitch and yaw (degrees, 0 to 360) of the attitude (cmd_dir = thrust axis, cmd_up = roll reference) against the reference
// attitude (ref_dir, ref_up). The reference axes are e1 = ref_dir, e2 = ref_up made square to it, e3 = e1 x e2. The thrust axis f gets
// yaw about e2 and pitch towards e2: f = (cos p cos y, sin p, cos p sin y) in (e1, e2, e3); roll is the signed angle about f from the top direction of that
// yaw and pitch alone (t0 = (-sin p cos y, cos p, -sin p sin y)) to cmd_up made square to f. The attitude equal to the reference is 0, 0, 0. Pure.
// Assumed convention (documented departure): the real N18 is three gimbal angles against REFSMMAT.
FUNCTION r60_cdu_angles {
  PARAMETER ref_dir, ref_up, cmd_dir, cmd_up.
  LOCAL e1 IS ref_dir:NORMALIZED.
  LOCAL e2 IS VECTOREXCLUDE(e1, ref_up):NORMALIZED.
  LOCAL e3 IS VCRS(e1, e2).
  LOCAL f_vec IS cmd_dir:NORMALIZED.
  LOCAL f1 IS VDOT(f_vec, e1).
  LOCAL f2 IS VDOT(f_vec, e2).
  LOCAL f3 IS VDOT(f_vec, e3).
  LOCAL yaw_deg IS ARCTAN2(f3, f1).
  LOCAL pitch_deg IS ARCSIN(MAX(-1, MIN(1, f2))).
  LOCAL t_zero IS (-SIN(pitch_deg) * COS(yaw_deg)) * e1 + COS(pitch_deg) * e2 + (-SIN(pitch_deg) * SIN(yaw_deg)) * e3.
  LOCAL t_vec IS VECTOREXCLUDE(f_vec, cmd_up):NORMALIZED.
  LOCAL roll_deg IS ARCTAN2(VDOT(f_vec, VCRS(t_zero, t_vec)), VDOT(t_zero, t_vec)).
  RETURN LIST(r60_wrap_deg(roll_deg), r60_wrap_deg(pitch_deg), r60_wrap_deg(yaw_deg)).
}

// r60_ref_in: the reference attitude (LEXICON "DIR", "UP", and "AX", the axes mark it was taken in) in the axes of the mark ax_to. The raw axes can turn
// (lm_axes.ks), so r60_cdu_angles must be given the reference and the commanded attitude in the same axes. Pure.
FUNCTION r60_ref_in {
  PARAMETER ref_att, ax_to.
  RETURN LEXICON("DIR", axes_carry(ref_att["DIR"], ref_att["AX"], ax_to), "UP", axes_carry(ref_att["UP"], ref_att["AX"], ax_to), "AX", ax_to).
}

// r60_wrap_deg: an angle in 0 to 360 degrees; one that rounds to 360.00 on the display (a hair under a full turn) is shown as 0. Pure.
FUNCTION r60_wrap_deg {
  PARAMETER angle_deg.
  LOCAL wrapped IS MOD(angle_deg + 360, 360).
  IF wrapped >= 359.995 { RETURN 0. }
  RETURN wrapped.
}

// r60_new: the R60 state for a burn attitude (burn_dir: the thrust axis, burn_up: the roll reference, both in raw axes). It starts at the request.
FUNCTION r60_new {
  PARAMETER burn_dir, burn_up.
  RETURN LEXICON("STATE", "ASK", "BURN_DIR", burn_dir, "BURN_UP", burn_up, "SHOWN", FALSE).
}

// r60_step: one cycle. State ASK is the first flashing V50 N18 (PRO starts the manoeuvre, ENTR finishes R60 at the present attitude, V34 terminates);
// TURNING is the static V06 N18 while the ship turns (every answer is ignored, PRO included: the key is consumed); ASK2 is the flashing request after the
// turn (PRO turns again, ENTR finishes, V34 terminates). DONE and TERM are final. att_err_deg is how far the ship is from the commanded attitude and
// rate_deg_s how fast it turns (the caller reads them; they are only looked at while TURNING).
// Returns LEXICON("STATE", text, "VERB", n, "NOUN", n, "FLASH", bool, "CHANGED", bool, "CMD_DIR", vec, "CMD_UP", vec):
//   VERB, NOUN: what to show (50, 18 flashing as a request, or 6, 18 static; -1 when R60 shows nothing: DONE and TERM);
//   CHANGED: the caller sets the display (SET_VERB and SET_NOUN) this cycle: R60 has just changed it, or V32 asked for it again;
//   CMD_DIR, CMD_UP: the attitude to command while TURNING (apply with ctl_set_command, thrust 0); zero vectors in every other state.
FUNCTION r60_step {
  PARAMETER r60, ks, att_err_deg, rate_deg_s.
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  LOCAL state_now IS r60["STATE"].
  LOCAL changed IS FALSE.
  IF state_now = "ASK" OR state_now = "ASK2" {
    IF ks["TERMINATE"] { SET state_now TO "TERM". }
    ELSE IF lm_entr_on_request(ks, R60_VERB_ASK, R60_NOUN_ANGLES) { SET state_now TO "DONE". }
    ELSE IF pro_pressed { SET state_now TO "TURNING". SET changed TO TRUE. }
    ELSE IF ks["RECYCLE"] OR NOT r60["SHOWN"] { SET changed TO TRUE. }
  } ELSE IF state_now = "TURNING" {
    IF att_err_deg <= P63_SETTLE_ERR_DEG AND rate_deg_s <= P63_SETTLE_RATE_DEG_S {
      SET state_now TO "ASK2".
      SET changed TO TRUE.
    }
  }
  SET r60["STATE"] TO state_now.
  IF changed { SET r60["SHOWN"] TO TRUE. }
  LOCAL out_verb IS -1.
  LOCAL out_noun IS -1.
  LOCAL out_flash IS FALSE.
  LOCAL cmd_dir IS V(0, 0, 0).
  LOCAL cmd_up IS V(0, 0, 0).
  IF state_now = "ASK" OR state_now = "ASK2" {
    SET out_verb TO R60_VERB_ASK.
    SET out_noun TO R60_NOUN_ANGLES.
    SET out_flash TO TRUE.
  } ELSE IF state_now = "TURNING" {
    SET out_verb TO 6.
    SET out_noun TO R60_NOUN_ANGLES.
    SET cmd_dir TO r60["BURN_DIR"].
    SET cmd_up TO r60["BURN_UP"].
  }
  RETURN LEXICON("STATE", state_now, "VERB", out_verb, "NOUN", out_noun, "FLASH", out_flash, "CHANGED", changed, "CMD_DIR", cmd_dir, "CMD_UP", cmd_up).
}
