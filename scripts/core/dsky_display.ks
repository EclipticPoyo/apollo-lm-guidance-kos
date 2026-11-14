// dsky_display.ks -- the DSKY core's number formatting and plain-text terminal display. Vehicle-independent.
//
// The three register texts of the noun on show come in through flags["REGS"] (a LIST of three texts, built by the
// vehicle's noun table); without it every register shows NA. Everything inside the scripts is SI; Apollo units appear
// only in the vehicle's noun table and in the instrument lines of display_lines (m_to_ft, ms_to_fps, m_to_nm: the unit
// helpers in the constants file, which the entry script or the test loads first).
// Only display_init and display_update touch the terminal; the rest is pure text/logic, so it can be tested on the pad.

// ---- Number formatting -----------------------------------------------------

// zero_pad: text of a whole number n, padded on the left with zeros to width digits.
FUNCTION zero_pad {
  PARAMETER n, width.
  LOCAL text IS "" + n.
  UNTIL text:LENGTH >= width { SET text TO "0" + text. }
  RETURN text.
}

// fmt_reg: a signed register like the DSKY's: sign plus five digits ("+12345", "-00012"). The real DSKY has no decimal
// point: a noun with a fractional scale (Luminary's POS7 "XXXX.X NAUT MI") shows the value in units of its last digit,
// so with decimals = 1 the value is multiplied by 10 and shown as five plain digits ("+01235" for 123.5). Values too
// big to show are clamped to the largest digits, keeping the sign.
FUNCTION fmt_reg {
  PARAMETER value, decimals.
  LOCAL ndigits IS 5.
  LOCAL biggest IS 10 ^ ndigits - 1.
  LOCAL n IS MIN(ROUND(ABS(value) * 10 ^ decimals), biggest).
  LOCAL sign IS "+".
  IF value < 0 AND n > 0 { SET sign TO "-". }      // no "-00000"
  RETURN sign + zero_pad(n, ndigits).
}

// vn_digits: a verb or noun number as the two digits of its cells; a negative number (nothing displayed) is two blanks.
FUNCTION vn_digits {
  PARAMETER number.
  IF number < 0 { RETURN "  ". }
  RETURN zero_pad(number, 2).
}

// fmt_2int: two integers in one register like Luminary's 2INTOUT (PINBALL_GAME_BUTTONS_AND_LIGHTS.agc, "TWO CONTIGUOUS SP POSITIVE
// INTEGERS ... IN RXD1-RXD2 AND RXD4-RXD5 (RXD3 IS BLANKED)"): a plus sign, the first integer in two digits, a blank, the
// second in two digits ("+12 45"). Each is clamped to 0 to 99.
FUNCTION fmt_2int {
  PARAMETER first, second.
  RETURN "+" + zero_pad(MIN(99, MAX(0, ROUND(first))), 2) + " " + zero_pad(MIN(99, MAX(0, ROUND(second))), 2).
}

// fmt_minsec: a time in seconds as a DSKY MIN/SEC register: sign, minutes, a blank, seconds ("+02 05", "-00 35"). The
// real register has no colon; the blank stands where the colon would be (Luminary M/SOUT, PINBALL_GAME_BUTTONS_AND_LIGHTS.agc
// 1594-1640: seconds in digits 4-5, digit 3 blanked, minutes in digits 1-2). Clamped to 59 min 59 s either way, as M/SLIMIT
// does ("FORCE MPAC, MPAC+1 TO +/- 59M59.5S"); no "-00 00".
FUNCTION fmt_minsec {
  PARAMETER seconds.
  LOCAL total IS MIN(ROUND(ABS(seconds)), 59 * 60 + 59).
  LOCAL sign IS "+".
  IF seconds < 0 AND total > 0 { SET sign TO "-". }
  LOCAL mins IS FLOOR(total / 60).
  RETURN sign + zero_pad(mins, 2) + " " + zero_pad(total - mins * 60, 2).
}

// ---- Nouns -----------------------------------------------------------------
GLOBAL NA IS "".                           // register with no data: blank (digit cells and sign off). The real DSKY has no dash glyph; its digit relays take only 0 to 9 or blank (PINBALL_GAME_BUTTONS_AND_LIGHTS.agc, relay codes)

// ---- Screen: plain-text terminal display (fallback) --------------------------------------------
// The main display is the GUI window (the vehicle's window file). This is a plain text readout of the same values for
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

// display_lines: the screen as a LIST of text lines (pure text, so it can be tested without a terminal).
// prog: text like "63"; verb, noun: numbers; flags: lexicon with "PROG" and "OPRERR" booleans (the two
// alarm lights), "ENTRY" (typed text) and optionally "REGS" (the three register texts). Instruments: forward = toward the site (VGU Z), lateral =
// sideways (VGU Y).
FUNCTION display_lines {
  PARAMETER derived, prog, verb, noun, flags.
  LOCAL regs IS LIST(NA, NA, NA).
  IF flags:HASKEY("REGS") { IF flags["REGS"]:LENGTH = 3 { SET regs TO flags["REGS"]. } }
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
    "PROG " + prog + "    VERB " + vn_digits(verb) + "    NOUN " + vn_digits(noun),
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
