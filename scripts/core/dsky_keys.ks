// dsky_keys.ks -- the DSKY core's key entry: the keypad state and what each key does. Vehicle-independent.
//
// keys_new is given the vehicle's lists of valid nouns, verbs and programme numbers (V37 targets); key_enter and
// key_enter_prog check what the pilot typed against them, and light OPR ERR for anything else.
// Keyboard: V, N, two digits, E = ENTR, P = PRO, C = CLR, R = RSET (Enter/Return also work as ENTR).

RUNONCEPATH("0:/core/dsky_store.ks").      // octal_parse, octal_text, store_locate (P27)
RUNONCEPATH("0:/core/dsky_load.ks").       // the keyed loaders V21 to V25 (load_new, load_key, load_begin)
RUNONCEPATH("0:/core/dsky_p27.ks").        // the update programme V71, V72, V33, V34 (p27_new, p27_key, p27_begin, p27_verify)

// ---- Key entry -------------------------------------------------------------
// The key state is a lexicon: VERB, NOUN (committed numbers), MODE ("" / "V" / "N": which buffer is
// being typed), VBUF, NBUF (digits typed so far), OPRERR, PRO (PRO pressed, caller clears it).

// Programme selection (V37 ENTR, then the two-digit programme number and ENTR, as on the DSKY): AWAIT_PROG is TRUE
// between V37 ENTR and the programme number's ENTR, PBUF the digits typed so far, VERB_BEFORE the verb to go back to,
// PROG_REQ the programme asked for (-1 none; the main loop reads it and sets it back to -1).
// nouns, verbs, progs: LISTs of the numbers the vehicle accepts (stored as "NOUNS", "VERBS", "PROGS").
// "LOAD" is the keyed-loader state (dsky_load.ks) and "P27" the update-programme state (dsky_p27.ks); "VEHICLE" is the vehicle
// LEXICON and "PROGRAM" the running programme's LEXICON or FALSE, both set by core_run, which the loaders and P27 read (FALSE
// until then: a load or update verb is then OPR ERR).
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
                 "NOUNS", nouns, "VERBS", verbs, "PROGS", progs,
                 "LOAD", load_new(), "P27", p27_new(), "VEHICLE", FALSE, "PROGRAM", FALSE, "QUIT", FALSE).
}

// quit_step: the DSKY window's close cross. state is "IDLE" (cross showing), "ASK" (the End DSKY? question showing) or "QUIT"
// (confirmed, final). The arguments say which of the cross, YES and NO were pressed since the last call. NO beats YES pressed
// in the same cycle, so a double click cannot end the DSKY by accident; YES and NO do nothing while no question is showing.
FUNCTION quit_step {
  PARAMETER state, close_pressed, yes_pressed, no_pressed.
  IF state = "QUIT" { RETURN "QUIT". }
  IF state = "ASK" {
    IF no_pressed { RETURN "IDLE". }
    IF yes_pressed { RETURN "QUIT". }
    RETURN "ASK".
  }
  IF close_pressed { RETURN "ASK". }
  RETURN "IDLE".
}

// key_prog_cancel: stop waiting for a programme number and put the verb back.
FUNCTION key_prog_cancel {
  PARAMETER ks.
  IF ks["AWAIT_PROG"] {
    SET ks["AWAIT_PROG"] TO FALSE.
    SET ks["PBUF"] TO "".
    SET ks["VERB"] TO ks["VERB_BEFORE"].
    // A V34 left on the display (it ran nothing) is not worth putting back: show a blank display, as at a fresh start.
    IF ks["VERB"] = 34 { SET ks["VERB"] TO -1. }
    IF ks["VERB"] < 0 { SET ks["NOUN"] TO -1. }
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
  IF noun_new < 0 AND verb_new <> 37 AND verb_new <> 34 AND verb_new <> 33 AND verb_new <> 71 AND verb_new <> 72 { SET bad TO TRUE. }
  IF bad { SET ks["OPRERR"] TO TRUE. }
  ELSE {
    // During P27 only V33 (verify and store) and V34 (throw the block away) are taken; any other verb is OPR ERR.
    IF p27_active(ks) {
      IF verb_new = 33 { p27_verify(ks, ks["VEHICLE"]). }
      ELSE IF verb_new = 34 { p27_cancel(ks). }
      ELSE { SET ks["OPRERR"] TO TRUE. }
      SET ks["VBUF"] TO "".
      SET ks["NBUF"] TO "".
      SET ks["MODE"] TO "".
      RETURN.
    }
    // V33 means "proceed" and has nothing to proceed with here.
    IF verb_new = 33 {
      SET ks["OPRERR"] TO TRUE.
      SET ks["VBUF"] TO "".
      SET ks["NBUF"] TO "".
      SET ks["MODE"] TO "".
      RETURN.
    }
    // A verb keyed and entered during a keyed load ends that load first (nothing is committed). V34 then ends only the load
    // (the display goes to the monitor verb). With no load active V34 just shows verb 34 (a running programme reads it as Terminate); the DSKY
    // itself is ended from the window's close cross (quit_step), never by a verb.
    IF load_active(ks) {
      load_cancel(ks).
      IF verb_new = 34 { SET verb_new TO 16. }
    }
    // V37 ENTR: the DSKY now waits for the programme number. VERB shows 37 meanwhile.
    IF verb_new = 37 AND ks["VERB"] <> 37 {
      SET ks["VERB_BEFORE"] TO ks["VERB"].
      SET ks["AWAIT_PROG"] TO TRUE.
      SET ks["PBUF"] TO "".
    }
    SET ks["VERB"] TO verb_new.
    SET ks["NOUN"] TO noun_new.
    IF verb_new >= 21 AND verb_new <= 25 {
      IF NOT load_begin(ks, ks["VEHICLE"], verb_new, noun_new) { SET ks["OPRERR"] TO TRUE. }
    }
    IF verb_new = 71 OR verb_new = 72 {
      IF NOT p27_begin(ks, ks["VEHICLE"], verb_new) { SET ks["OPRERR"] TO TRUE. }
    }
  }
  SET ks["VBUF"] TO "".
  SET ks["NBUF"] TO "".
  SET ks["MODE"] TO "".
}

// key_press: handle one typed character (one-character string).
FUNCTION key_press {
  PARAMETER ks, ch.
  LOCAL key IS ch:TOUPPER.
  // A keyed load (V21 to V25) takes digits, signs, CLR, RSET and ENTR/PRO while it is active; V and N are not its keys.
  LOCAL load_name IS key.
  IF ch = CHAR(13) OR ch = CHAR(10) { SET load_name TO "E". }
  IF load_key(ks, ks["VEHICLE"], load_name) { RETURN. }
  IF p27_key(ks, ks["VEHICLE"], load_name) { RETURN. }
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

