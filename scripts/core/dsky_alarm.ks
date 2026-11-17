// dsky_alarm.ks -- the alarm facility of the DSKY core (Luminary ALARM_AND_ABORT.agc, ALARM and MULTFAIL). Vehicle-independent.
//
// An alarm is a code (an integer whose decimal digits are the digits shown: 1202 is alarm 01202; real alarm codes are octal and
// the DSKY shows them as digits, so the digits are all we keep). The facility keeps the first three in FAILREG order: the
// first alarm in slot 1, the second in slot 2, the third in slot 3. A later alarm replaces slot 3 with bit 15 added (here
// 40000 + code, the "more than three" mark). Every alarm lights the PROG lamp and it stays lit until RSET, which also clears the
// three slots. N09 shows the three slots (the vehicle's noun table).

GLOBAL ALARM_BIT15 IS 40000.

// alarm_new: no alarms, lamp dark.
FUNCTION alarm_new {
  RETURN LEXICON("CODES", LIST(0, 0, 0), "LAMP", FALSE).
}

// alarm_raise: record code (a positive integer) and light the lamp.
FUNCTION alarm_raise {
  PARAMETER alarm_state, code.
  LOCAL placed IS FALSE.
  FROM { LOCAL i IS 0. } UNTIL i >= 3 OR placed STEP { SET i TO i + 1. } DO {
    IF alarm_state["CODES"][i] = 0 {
      SET alarm_state["CODES"][i] TO code.
      SET placed TO TRUE.
    }
  }
  IF NOT placed {
    IF code < ALARM_BIT15 { SET alarm_state["CODES"][2] TO code + ALARM_BIT15. } ELSE { SET alarm_state["CODES"][2] TO code. }
  }
  SET alarm_state["LAMP"] TO TRUE.
}

// alarm_reset: RSET: the three slots empty, the lamp out.
FUNCTION alarm_reset {
  PARAMETER alarm_state.
  SET alarm_state["CODES"] TO LIST(0, 0, 0).
  SET alarm_state["LAMP"] TO FALSE.
}

// alarm_text: the code as five digits, zero padded (a code of 40000 or more shows as it is).
FUNCTION alarm_text {
  PARAMETER code.
  LOCAL text IS "" + ROUND(code).
  UNTIL text:LENGTH >= 5 { SET text TO "0" + text. }
  RETURN text.
}
