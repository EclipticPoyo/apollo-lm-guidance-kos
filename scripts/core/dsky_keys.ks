// dsky_keys.ks -- the DSKY core's key entry: the keypad state and what each key does. Vehicle-independent.
//
// keys_new is given the vehicle's lists of valid nouns, verbs and programme numbers (V37 targets); key_enter and
// key_enter_prog check what the pilot typed against them, and light OPR ERR for anything else.
// Keyboard: V, N, two digits, E = ENTR, P = PRO, C = CLR, R = RSET (Enter/Return also work as ENTR).

// ---- Key entry -------------------------------------------------------------
// The key state is a lexicon: VERB, NOUN (committed numbers), MODE ("" / "V" / "N": which buffer is
// being typed), VBUF, NBUF (digits typed so far), OPRERR, PRO (PRO pressed, caller clears it).

// Programme selection (V37 ENTR, then the two-digit programme number and ENTR, as on the DSKY): AWAIT_PROG is TRUE
// between V37 ENTR and the programme number's ENTR, PBUF the digits typed so far, VERB_BEFORE the verb to go back to,
// PROG_REQ the programme asked for (-1 none; the main loop reads it and sets it back to -1).
// nouns, verbs, progs: LISTs of the numbers the vehicle accepts (stored as "NOUNS", "VERBS", "PROGS").
// start_vn (optional): LIST(verb, noun) shown at start. -1 for both is a blank display (no verb or noun, the registers dark),
// as a real DSKY powers up. Without it the start is V16 and the vehicle's first noun.
FUNCTION keys_new {
  PARAMETER nouns, verbs, progs, start_vn IS LIST().
  LOCAL first_noun IS 0.
  IF nouns:LENGTH > 0 { SET first_noun TO nouns[0]. }     // the noun shown at start is the vehicle's first
  LOCAL start_verb IS 16.
  LOCAL start_noun IS first_noun.
  IF start_vn:LENGTH = 2 { SET start_verb TO start_vn[0]. SET start_noun TO start_vn[1]. }
  RETURN LEXICON("VERB", start_verb, "NOUN", start_noun, "MODE", "", "VBUF", "", "NBUF", "", "OPRERR", FALSE, "PRO", FALSE,
                 "AWAIT_PROG", FALSE, "PBUF", "", "PROG_REQ", -1, "VERB_BEFORE", start_verb,
                 "NOUNS", nouns, "VERBS", verbs, "PROGS", progs).
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

// key_enter_prog: ENTR while waiting for a programme number. Two digits naming a programme in the vehicle's list (ks["PROGS"]) make the
// request; anything else is OPR ERR. Either way the wait ends.
FUNCTION key_enter_prog {
  PARAMETER ks.
  LOCAL number IS -1.
  IF ks["PBUF"]:LENGTH = 2 { SET number TO ks["PBUF"]:TONUMBER(-1). }
  IF ks["PROGS"]:CONTAINS(number) { SET ks["PROG_REQ"] TO number. } ELSE { SET ks["OPRERR"] TO TRUE. }
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
    IF ks["VBUF"]:LENGTH = 2 AND ks["VERBS"]:CONTAINS(ks["VBUF"]:TONUMBER(-1)) { SET verb_new TO ks["VBUF"]:TONUMBER(-1). }
    ELSE { SET bad TO TRUE. }
  }
  IF ks["NBUF"]:LENGTH > 0 {
    IF ks["NBUF"]:LENGTH = 2 AND ks["NOUNS"]:CONTAINS(ks["NBUF"]:TONUMBER(-1)) { SET noun_new TO ks["NBUF"]:TONUMBER(-1). }
    ELSE { SET bad TO TRUE. }
  }
  // A blank verb (-1) means nothing is displayed yet: ENTR needs a verb, and a noun unless it is V37 (programme change) or
  // V34 (terminate), which take none.
  IF verb_new < 0 { SET bad TO TRUE. }
  IF noun_new < 0 AND verb_new <> 37 AND verb_new <> 34 { SET bad TO TRUE. }
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

// entry_text: what the pilot has typed so far, like the DSKY entry: "V16 N25", "V1", "N", or "".
// A buffer shows once its key was pressed (MODE) or it holds digits.
FUNCTION entry_text {
  PARAMETER ks.
  LOCAL out IS "".
  // After V37 ENTR the DSKY is waiting for the programme number: "V37 P12" (P = the programme number being keyed).
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

