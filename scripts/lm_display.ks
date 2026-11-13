// lm_display.ks -- DSKY-style display and key entry (plan Task 5).
//
// Register contents follow the noun table in PINBALL_NOUN_TABLES.agc (spec section 7).
// Everything inside the scripts is SI; Apollo units appear only here.
// Only display_init, display_update and keys_poll touch the terminal; the rest is pure text/logic,
// so it can be tested on the pad.

RUNONCEPATH("0:/lm/lm_constants.ks").

// ---- Number formatting -----------------------------------------------------

// zero_pad: text of a whole number n, padded on the left with zeros to width digits.
FUNCTION zero_pad {
  PARAMETER n, width.
  LOCAL text IS "" + n.
  UNTIL text:LENGTH >= width { SET text TO "0" + text. }
  RETURN text.
}

// fmt_reg: a signed register like the DSKY's: sign plus five digits ("+12345", "-00012").
// With decimals > 0 there are four digits and a decimal point ("+123.4"), so the width stays six
// characters. Values too big to show are clamped to the largest digits, keeping the sign.
FUNCTION fmt_reg {
  PARAMETER value, decimals.
  LOCAL ndigits IS 5 - MIN(decimals, 1).
  LOCAL biggest IS 10 ^ ndigits - 1.
  LOCAL n IS MIN(ROUND(ABS(value) * 10 ^ decimals), biggest).
  LOCAL sign IS "+".
  IF value < 0 AND n > 0 { SET sign TO "-". }      // no "-00000"
  LOCAL digits IS zero_pad(n, ndigits).
  IF decimals > 0 {
    SET digits TO digits:SUBSTRING(0, ndigits - decimals) + "." + digits:SUBSTRING(ndigits - decimals, decimals).
  }
  RETURN sign + digits.
}

// fmt_minsec: a time in seconds as a DSKY MIN/SEC register: sign, minutes, a blank, seconds ("+02 05", "-00 35"). The
// real register has no colon; the blank stands where the colon would be. Clamped to 99 min 59 s either way; no "-00 00".
FUNCTION fmt_minsec {
  PARAMETER seconds.
  LOCAL total IS MIN(ROUND(ABS(seconds)), 99 * 60 + 59).
  LOCAL sign IS "+".
  IF seconds < 0 AND total > 0 { SET sign TO "-". }
  LOCAL mins IS FLOOR(total / 60).
  RETURN sign + zero_pad(mins, 2) + " " + zero_pad(total - mins * 60, 2).
}

// ---- Nouns -----------------------------------------------------------------
GLOBAL NA IS "-----".                      // register that needs guidance (milestone 2)
GLOBAL KNOWN_NOUNS IS LIST(60, 61, 62, 63, 64, 68).
GLOBAL KNOWN_VERBS IS LIST(6, 16, 34, 37). // 06 display, 16 monitor (both just show the noun here), 34 terminate (lm_main.ks exits), 37 change programme
GLOBAL KNOWN_PROGS IS LIST(0, 63).         // programmes V37 can select: P00 (none) and P63 (milestone 3). P64 is reached only by the handover from P63, P65 by the handover from P64 and P66 from P65 (V37 ENTR 64, 65 or 66 lights OPR ERR)

// noun_registers: the three register texts for a noun, from the derived lexicon (nav_derived).
// An empty list means "no such noun" and the caller lights OPR ERR.
//   N60 VHORIZ ft/s, HDOT ft/s, HCALC ft
//   N61 TTFDISP (time to go in braking, +mm ss), TTOGO (time to ignition, +mm ss counting down), OUTOFPLN (nautical miles)
//   N62 ABVEL ft/s, TTOGO (as N61), DVTOTAL ft/s (delta-v gained since ignition)
//   TTOGO departs from Luminary's sign on purpose (user's choice): Luminary has TTOGO = TIME2 - TIG, negative until
//   ignition; here it is TIG - now, shown + before ignition and counting down through zero (then -mm ss after TIG).
//   N63 ABVEL ft/s, HDOT ft/s, HCALC ft   (HCALC1 in Luminary is HCALC plus a pad term; plain HCALC here)
//   N64 look angle deg (FUNNYDSP, its time-to-redesignation half needs guidance), HDOT, HCALC
//   N68 RANGEDSP nautical miles, guidance, DELTAH ft
// The P63 quantities (TTFDISP, TTOGO, OUTOFPLN, DVTOTAL) are extra keys the P63 programme adds to the derived lexicon
// (lm_p63.ks); without them those registers show NA, as before P63 existed. TTFDISP, TTOGO and DVTOTAL follow
// PINBALL_NOUN_TABLES.agc lines 717-722 (nouns 61 and 62).
FUNCTION noun_registers {
  PARAMETER noun_no, derived.
  IF NOT KNOWN_NOUNS:CONTAINS(noun_no) { RETURN LIST(). }
  IF NOT derived["VALID"] { RETURN LIST(NA, NA, NA). }
  LOCAL vhoriz IS fmt_reg(ms_to_fps(derived["VHORIZ"]), 0).
  LOCAL abvel IS fmt_reg(ms_to_fps(derived["ABVEL"]), 0).
  LOCAL hdot IS fmt_reg(ms_to_fps(derived["HDOT"]), 0).
  LOCAL hcalc IS fmt_reg(m_to_ft(derived["HCALC"]), 0).
  LOCAL ttfdisp IS NA.
  LOCAL ttogo IS NA.
  LOCAL outofpln IS NA.
  LOCAL dvtotal IS NA.
  IF derived:HASKEY("TTFDISP") { SET ttfdisp TO fmt_minsec(derived["TTFDISP"]). }
  IF derived:HASKEY("TTOGO") { SET ttogo TO fmt_minsec(derived["TTOGO"]). }
  IF derived:HASKEY("OUTOFPLN") { SET outofpln TO fmt_reg(m_to_nm(derived["OUTOFPLN"]), 1). }
  IF derived:HASKEY("DVTOTAL") { SET dvtotal TO fmt_reg(ms_to_fps(derived["DVTOTAL"]), 0). }
  IF noun_no = 60 { RETURN LIST(vhoriz, hdot, hcalc). }
  IF noun_no = 61 { RETURN LIST(ttfdisp, ttogo, outofpln). }
  IF noun_no = 62 { RETURN LIST(abvel, ttogo, dvtotal). }
  IF noun_no = 63 { RETURN LIST(abvel, hdot, hcalc). }
  IF noun_no = 64 { RETURN LIST(fmt_reg(derived["LOOKANGL"], 1), hdot, hcalc). }
  // noun 68
  RETURN LIST(fmt_reg(m_to_nm(derived["RANGEDSP"]), 1), NA, fmt_reg(m_to_ft(derived["DELTAH"]), 0)).
}

// ---- Key entry -------------------------------------------------------------
// Keyboard: V, N, two digits, E = ENTR, P = PRO, C = CLR, R = RSET (Enter/Return also work as ENTR).
// The key state is a lexicon: VERB, NOUN (committed numbers), MODE ("" / "V" / "N": which buffer is
// being typed), VBUF, NBUF (digits typed so far), OPRERR, PRO (PRO pressed, caller clears it).

// Programme selection (V37 ENTR, then the two-digit programme number and ENTR, as on the DSKY): AWAIT_PROG is TRUE
// between V37 ENTR and the programme number's ENTR, PBUF the digits typed so far, VERB_BEFORE the verb to go back to,
// PROG_REQ the programme asked for (-1 none; the main loop reads it and sets it back to -1).
FUNCTION keys_new {
  RETURN LEXICON("VERB", 16, "NOUN", 60, "MODE", "", "VBUF", "", "NBUF", "", "OPRERR", FALSE, "PRO", FALSE,
                 "AWAIT_PROG", FALSE, "PBUF", "", "PROG_REQ", -1, "VERB_BEFORE", 16).
}

// key_prog_cancel: stop waiting for a programme number and put the verb back.
FUNCTION key_prog_cancel {
  PARAMETER ks.
  IF ks["AWAIT_PROG"] {
    SET ks["AWAIT_PROG"] TO FALSE.
    SET ks["PBUF"] TO "".
    SET ks["VERB"] TO ks["VERB_BEFORE"].
  }
}

// key_enter_prog: ENTR while waiting for a programme number. Two digits naming a programme in KNOWN_PROGS make the
// request; anything else is OPR ERR. Either way the wait ends.
FUNCTION key_enter_prog {
  PARAMETER ks.
  LOCAL number IS -1.
  IF ks["PBUF"]:LENGTH = 2 { SET number TO ks["PBUF"]:TONUMBER(-1). }
  IF KNOWN_PROGS:CONTAINS(number) { SET ks["PROG_REQ"] TO number. } ELSE { SET ks["OPRERR"] TO TRUE. }
  key_prog_cancel(ks).
}

// key_enter: ENTR. Both typed numbers are checked first, and nothing changes if either is bad.
FUNCTION key_enter {
  PARAMETER ks.
  IF ks["AWAIT_PROG"] { key_enter_prog(ks). RETURN. }
  LOCAL verb_new IS ks["VERB"].
  LOCAL noun_new IS ks["NOUN"].
  LOCAL bad IS FALSE.
  IF ks["VBUF"]:LENGTH > 0 {
    IF ks["VBUF"]:LENGTH = 2 AND KNOWN_VERBS:CONTAINS(ks["VBUF"]:TONUMBER(-1)) { SET verb_new TO ks["VBUF"]:TONUMBER(-1). }
    ELSE { SET bad TO TRUE. }
  }
  IF ks["NBUF"]:LENGTH > 0 {
    IF ks["NBUF"]:LENGTH = 2 AND KNOWN_NOUNS:CONTAINS(ks["NBUF"]:TONUMBER(-1)) { SET noun_new TO ks["NBUF"]:TONUMBER(-1). }
    ELSE { SET bad TO TRUE. }
  }
  IF bad { SET ks["OPRERR"] TO TRUE. }
  ELSE {
    // V37 ENTR: the DSKY now waits for the programme number. VERB shows 37 meanwhile.
    IF verb_new = 37 AND ks["VERB"] <> 37 {
      SET ks["VERB_BEFORE"] TO ks["VERB"].
      SET ks["AWAIT_PROG"] TO TRUE.
      SET ks["PBUF"] TO "".
    }
    SET ks["VERB"] TO verb_new.
    SET ks["NOUN"] TO noun_new.
  }
  SET ks["VBUF"] TO "".
  SET ks["NBUF"] TO "".
  SET ks["MODE"] TO "".
}

// key_press: handle one typed character (one-character string).
FUNCTION key_press {
  PARAMETER ks, ch.
  LOCAL key IS ch:TOUPPER.
  // Waiting for a programme number (after V37 ENTR): digits go to PBUF, CLR empties it; V or N cancels the wait.
  IF ks["AWAIT_PROG"] AND "0123456789":CONTAINS(key) AND key:LENGTH = 1 {
    IF ks["PBUF"]:LENGTH < 2 { SET ks["PBUF"] TO ks["PBUF"] + key. } ELSE { SET ks["OPRERR"] TO TRUE. }
    RETURN.
  }
  IF ks["AWAIT_PROG"] AND key = "C" { SET ks["PBUF"] TO "". RETURN. }
  IF key = "V" OR key = "N" { key_prog_cancel(ks). }
  IF key = "V" { SET ks["MODE"] TO "V". SET ks["VBUF"] TO "". }
  ELSE IF key = "N" { SET ks["MODE"] TO "N". SET ks["NBUF"] TO "". }
  ELSE IF key = "E" OR ch = CHAR(13) OR ch = CHAR(10) { key_enter(ks). }
  ELSE IF key = "P" { SET ks["PRO"] TO TRUE. }
  ELSE IF key = "C" {                                  // CLR: drop what is being typed
    IF ks["MODE"] = "V" { SET ks["VBUF"] TO "". }
    IF ks["MODE"] = "N" { SET ks["NBUF"] TO "". }
  }
  ELSE IF key = "R" { SET ks["OPRERR"] TO FALSE. }     // RSET
  ELSE IF "0123456789":CONTAINS(key) AND key:LENGTH = 1 {
    IF ks["MODE"] = "V" AND ks["VBUF"]:LENGTH < 2 { SET ks["VBUF"] TO ks["VBUF"] + key. }
    ELSE IF ks["MODE"] = "N" AND ks["NBUF"]:LENGTH < 2 { SET ks["NBUF"] TO ks["NBUF"] + key. }
    ELSE { SET ks["OPRERR"] TO TRUE. }                // a digit with no V or N pressed first
  }
  // Any other key is ignored.
}

// keys_poll: read every key waiting in the terminal, without blocking. Returns the same lexicon.
FUNCTION keys_poll {
  PARAMETER ks.
  UNTIL NOT TERMINAL:INPUT:HASCHAR { key_press(ks, TERMINAL:INPUT:GETCHAR()). }
  RETURN ks.
}

// ---- Screen: plain-text terminal display (fallback) --------------------------------------------
// The main display is the GUI window (lm_gui.ks). This is a plain text readout of the same values for
// when the GUI is not wanted: it does not try to look like the DSKY panel. ASCII only.

// repeat_text: ch repeated count times.
FUNCTION repeat_text {
  PARAMETER ch, count.
  LOCAL out IS "".
  UNTIL out:LENGTH >= count { SET out TO out + ch. }
  RETURN out.
}

// pad_right: text padded with spaces to width characters, or cut to width.
FUNCTION pad_right {
  PARAMETER text, width.
  RETURN (text + repeat_text(" ", width)):SUBSTRING(0, width).
}

// entry_text: what the pilot has typed so far, like the DSKY entry: "V16 N60", "V1", "N", or "".
// A buffer shows once its key was pressed (MODE) or it holds digits.
FUNCTION entry_text {
  PARAMETER ks.
  LOCAL out IS "".
  // After V37 ENTR the DSKY is waiting for the programme number: "V37 P63" (P = the programme number being keyed).
  IF ks["AWAIT_PROG"] { RETURN "V37 P" + ks["PBUF"]. }
  IF ks["MODE"] = "V" OR ks["VBUF"]:LENGTH > 0 { SET out TO "V" + ks["VBUF"]. }
  IF ks["MODE"] = "N" OR ks["NBUF"]:LENGTH > 0 {
    IF out <> "" { SET out TO out + " ". }
    SET out TO out + "N" + ks["NBUF"].
  }
  RETURN out.
}

// flags_from_keys: the lexicon gui_update and display_lines take, built from the key state ks. prog_lamp is
// the PROG lamp (TRUE lights it). "ENTRY" is the typed text for the terminal display; "MODE", "VBUF" and
// "NBUF" let the GUI show what is being keyed in the VERB and NOUN cells. "PROGKEY" is TRUE between V37 ENTR and the
// programme number's ENTR, when "PBUF" (the digits typed so far) is shown in the NOUN cells, as Luminary's MMCHANG does
// ("MMCHANG USES NOUN DISPLAY UNTIL ENTER", PINBALL_GAME_BUTTONS_AND_LIGHTS.agc).
FUNCTION flags_from_keys {
  PARAMETER ks, prog_lamp.
  RETURN LEXICON("PROG", prog_lamp, "OPRERR", ks["OPRERR"], "ENTRY", entry_text(ks),
                 "MODE", ks["MODE"], "VBUF", ks["VBUF"], "NBUF", ks["NBUF"],
                 "PROGKEY", ks["AWAIT_PROG"], "PBUF", ks["PBUF"]).
}

// display_lines: the screen as a LIST of text lines (pure text, so it can be tested without a terminal).
// prog: text like "63"; verb, noun: numbers; flags: lexicon with "PROG" and "OPRERR" booleans (the two
// alarm lights) and "ENTRY" (typed text). Instruments: forward = toward the site (VGU Z), lateral =
// sideways (VGU Y).
FUNCTION display_lines {
  PARAMETER derived, prog, verb, noun, flags.
  LOCAL regs IS noun_registers(noun, derived).
  IF regs:LENGTH = 0 { SET regs TO LIST(NA, NA, NA). }
  LOCAL alarms IS "".
  IF flags["PROG"] { SET alarms TO alarms + " [PROG]". }
  IF flags["OPRERR"] { SET alarms TO alarms + " [OPR ERR]". }
  LOCAL alt_text IS NA.
  LOCAL rate_text IS NA.
  LOCAL fwd_text IS NA.
  LOCAL lat_text IS NA.
  IF derived["VALID"] {
    SET alt_text TO fmt_reg(m_to_ft(derived["HCALC"]), 0).
    SET rate_text TO fmt_reg(ms_to_fps(derived["HDOT"]), 0).
    SET fwd_text TO fmt_reg(ms_to_fps(derived["VGU"]:Z), 0).
    SET lat_text TO fmt_reg(ms_to_fps(derived["VGU"]:Y), 0).
  }
  RETURN LIST(
    "APOLLO LM GUIDANCE",
    "",
    "PROG " + prog + "    VERB " + zero_pad(verb, 2) + "    NOUN " + zero_pad(noun, 2),
    "ALARMS:" + alarms,
    "",
    "R1  " + regs[0],
    "R2  " + regs[1],
    "R3  " + regs[2],
    "",
    "ENTRY: " + flags["ENTRY"],
    "",
    "ALT      " + alt_text + " ft",
    "ALT RATE " + rate_text + " ft/s",
    "FWD VEL  " + fwd_text + " ft/s",
    "LAT VEL  " + lat_text + " ft/s",
    "",
    "Keys: V N 0-9  E=ENTR P=PRO C=CLR R=RSET").
}

// draw_text: print text at (x, y) only if it differs from what is already drawn there, so a 10 Hz
// update prints almost nothing. DRAWN remembers the last text at each key; display_init clears it.
GLOBAL DRAWN IS LEXICON().
FUNCTION draw_text {
  PARAMETER key, x, y, text.
  IF NOT DRAWN:HASKEY(key) OR DRAWN[key] <> text {
    PRINT text AT (x, y).
    SET DRAWN[key] TO text.
  }
}

// display_init: clear the screen and forget what was drawn.
FUNCTION display_init {
  CLEARSCREEN.
  SET DRAWN TO LEXICON().
}

// display_update: print the lines from display_lines, redrawing only the lines that changed.
FUNCTION display_update {
  PARAMETER derived, prog, verb, noun, flags.
  LOCAL lines IS display_lines(derived, prog, verb, noun, flags).
  FROM { LOCAL i IS 0. } UNTIL i >= lines:LENGTH STEP { SET i TO i + 1. } DO {
    draw_text("row" + i, 0, i, pad_right(lines[i], 48)).
  }
}
