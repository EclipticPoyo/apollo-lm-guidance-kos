// lm_r02.ks -- R02 (the IMU status check), R03 (stub) and P51 (simplified IMU orientation) of release 1.4.
//   r02(imu_on, imu_oriented)       -> LEXICON("OK", bool, "ALARM", 0 | 210 | 220)
//   r03()                           the DAP data load, a stub
//   p51_start(prev), p51_step(prog, nav, ks), p51_end(prog)      the P51 programme
//
// R02BOTH (Luminary 099 IMU_MODE_SWITCHING_ROUTINES.agc, lines 905-918): if the REFSMMAT-known flag is set the check passes (R02ZERO, 920-923). Otherwise
// it raises alarm 00210 when the ISS is not initialised (IMODES30 bit 9 set), else alarm 00220 ("REFSMMAT not known", OCT220, 924), through VARALARM,
// which lights PROG with no display, and the programme goes to P00 (GOTOPOOH). The order follows the source: a known orientation passes whatever the
// IMU flag says (the real flag is cleared when the IMU is switched off, which does not exist here).
// Our flags: LM_VEH["IMU_ON"] is always TRUE (our IMU is always on); LM_VEH["IMU_OK"] is TRUE from the start with the IMU_ALIGN setting AUTO,
// FALSE with REQUIRED until P51 has run (design section 4). The programmes pass both to r02 and raise the alarm and end when OK is FALSE.
//
// R03 (Luminary R03 loads the DAP data): not called by P40, P41 or P47 in Luminary 099 (research section 5), and our attitude control is the kOS
// steering with no DAP data, so r03 is a documented stub that does nothing.
//
// P51 (the real programme is the IMU orientation determination: the crew sights two stars, the computer torques the IMU to the new orientation and
// shows N93): not simulated. Departure documented in the manual: P51 is one flashing display, V50 N25 with R1 00051 (the checklist-code form that
// P40AUTO uses, 00203): "please perform checklist item 51". PRO sets LM_VEH["IMU_OK"] and ends the programme (to P00); V34 ends it without setting
// the flag; V32 shows the request again (ENTR only when the request is still what is displayed, see lm_entr_on_request).

RUNONCEPATH("0:/lm/burn/lm_r60.ks").            // lm_entr_on_request

GLOBAL P51_VERB IS 50.
GLOBAL P51_NOUN IS 25.
GLOBAL P51_CODE IS 51.                          // the R1 value of the request (octal checklist code, shown as 00051)

// r02: R02BOTH. imu_on: the ISS is switched on and initialised; imu_oriented: the IMU's orientation is known (REFSMMAT). Pure.
FUNCTION r02 {
  PARAMETER imu_on, imu_oriented.
  IF imu_oriented { RETURN LEXICON("OK", TRUE, "ALARM", 0). }
  IF NOT imu_on { RETURN LEXICON("OK", FALSE, "ALARM", 210). }
  RETURN LEXICON("OK", FALSE, "ALARM", 220).
}

// r03: stub, see the header.
FUNCTION r03 {
  RETURN.
}

// p51_start: the programme state. V37 starts it with prev FALSE; nothing can refuse it.
FUNCTION p51_start {
  PARAMETER prev.
  RETURN LEXICON("PROG_NO", 51, "MODE", "P51", "REFUSED", "", "ENDED", FALSE, "SHOWN", FALSE).
}

// p51_step: the flashing V50 N25 request until the pilot answers. PRO: the IMU's orientation is taken as known (LM_VEH["IMU_OK"]) and the
// programme ends. V34 ends it with nothing set. V32 (or an ENTR answering the displayed request) shows the request again.
// Same output keys as the other steps; the nav argument is unused (P51 needs no navigation).
FUNCTION p51_step {
  PARAMETER prog, nav, ks.
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  LOCAL message IS "".
  IF pro_pressed {
    SET LM_VEH["IMU_OK"] TO TRUE.
    SET prog["ENDED"] TO TRUE.
    SET message TO "P51: IMU orientation set.".
  } ELSE IF ks["TERMINATE"] {
    SET prog["ENDED"] TO TRUE.
    SET message TO "P51: ended, the IMU orientation is not set.".
  } ELSE IF NOT prog["SHOWN"] OR ks["RECYCLE"] OR lm_entr_on_request(ks, P51_VERB, P51_NOUN) {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO P51_VERB.
    SET set_noun TO P51_NOUN.
  }
  LOCAL request IS FALSE.
  IF NOT prog["ENDED"] { SET request TO LEXICON("VERB", P51_VERB, "NOUN", P51_NOUN). }
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", request,
                 "ALARM", 0, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE, "EXTRA", LEXICON("N25", P51_CODE), "MSG", message, "ENDED", prog["ENDED"],
                 "HANDOVER", FALSE, "PROG_NO", 51, "CONTACT", FALSE, "STATUS", LIST()).
}

// p51_end: nothing was taken over, nothing to give back.
FUNCTION p51_end {
  PARAMETER prog.
}
