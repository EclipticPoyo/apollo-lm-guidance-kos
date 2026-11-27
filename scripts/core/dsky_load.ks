// dsky_load.ks -- the keyed loaders V21 to V25 (the DSKY core's "load data" verbs). Vehicle-independent: which nouns can be
// loaded, and what a finished load does, come from the vehicle LEXICON:
//   "LOADS"        LEXICON noun-as-text -> LEXICON("NCOMP", n, "DIGITS", LIST of the digit count of each register[, "OCTAL", TRUE])
//   "LOAD_COMMIT"  delegate (noun_no, comps, values) -> text: comps is a LIST of the registers (1 to 3) that got data, values the
//                  matching signed integers exactly as keyed (octal nouns: the number keyed); returns "" on success, or why it was refused
// A noun with "OCTAL" TRUE is loaded in octal: digits 0 to 7 and no sign (8, 9 or a sign is OPR ERR and the load waits), ENTR after 1 to all
// of the register's digits, and the value committed is the octal number's.
// The pilot keys V21 N33 E (or V22, V23, V24, V25), then for each register to load: a sign (+ or -, required: the loadable nouns are
// decimal only), all of its digits, ENTR. V21 loads R1, V22 R2, V23 R3, V24 R1 then R2, V25 R1, R2, R3. PRO leaves that
// register as it was (ENTR with fewer digits than the register has, or with no sign, is OPR ERR; with no sign the load starts again from R1). CLR drops what is keyed in the register. A digit too many, or a sign anywhere but first, is ignored (no alarm, as in PINBALL). After the last register the vehicle
// commits all the values at once (a load that is abandoned before the end changes nothing) and the display goes to the monitor
// verb (V16) on the same noun. While a load is active the VERB and NOUN cells flash. RSET only clears OPR ERR (as on the real DSKY); the load
// ends without effect on V34 ENTR (Terminate), or when another verb is keyed and entered (V37 and the others replace it), and V33 ENTR acts as PRO.
// Departure from Luminary: PRO on a register keeps the old
// value (Luminary's "proceed without data" is a verb, V33). The pack describes what PRO does here (page 2-4).

// load_octal: is the noun being loaded an octal one ("OCTAL" TRUE in its LOADS entry)?
FUNCTION load_octal {
  PARAMETER ks, vehicle.
  LOCAL entry IS vehicle["LOADS"]["" + ks["LOAD"]["NOUN"]].
  IF NOT entry:HASKEY("OCTAL") { RETURN FALSE. }
  RETURN entry["OCTAL"].
}

// load_new: the load state kept in the key state (ks["LOAD"]).
FUNCTION load_new {
  RETURN LEXICON("ACTIVE", FALSE, "VERB", 0, "NOUN", 0, "COMPS", LIST(), "POS", 0, "BUF", "", "SIGN", "+", "SIGNED", FALSE,
                 "GOT_COMPS", LIST(), "GOT_VALUES", LIST(), "MSG", "").
}

FUNCTION load_active {
  PARAMETER ks.
  RETURN ks["LOAD"]["ACTIVE"].
}

// load_cancel: end an active load; nothing is committed.
FUNCTION load_cancel {
  PARAMETER ks.
  LOCAL ld IS ks["LOAD"].
  SET ld["ACTIVE"] TO FALSE.
  SET ld["BUF"] TO "".
  SET ld["SIGN"] TO "+".
  SET ld["SIGNED"] TO FALSE.
  SET ld["COMPS"] TO LIST().
  SET ld["GOT_COMPS"] TO LIST().
  SET ld["GOT_VALUES"] TO LIST().
}

// load_begin: start a load for verb (21 to 25) and noun. FALSE (the caller lights OPR ERR) when the vehicle has no loadable
// register for it: no "LOADS", a noun not in it, or a verb that names a register the noun does not have.
FUNCTION load_begin {
  PARAMETER ks, vehicle, verb, noun.
  IF NOT vehicle:ISTYPE("Lexicon") { RETURN FALSE. }
  IF NOT vehicle:HASKEY("LOADS") { RETURN FALSE. }
  IF NOT vehicle["LOADS"]:HASKEY("" + noun) { RETURN FALSE. }
  LOCAL ncomp IS vehicle["LOADS"]["" + noun]["NCOMP"].
  LOCAL comps IS LIST().
  IF verb = 21 { comps:ADD(1). }
  IF verb = 22 { comps:ADD(2). }
  IF verb = 23 { comps:ADD(3). }
  IF verb = 24 { comps:ADD(1). comps:ADD(2). }
  IF verb = 25 { comps:ADD(1). comps:ADD(2). comps:ADD(3). }
  IF comps:LENGTH = 0 { RETURN FALSE. }
  FOR reg IN comps { IF reg > ncomp { RETURN FALSE. } }
  load_cancel(ks).
  LOCAL ld IS ks["LOAD"].
  SET ld["ACTIVE"] TO TRUE.
  SET ld["VERB"] TO verb.
  SET ld["NOUN"] TO noun.
  SET ld["COMPS"] TO comps.
  SET ld["POS"] TO 0.
  RETURN TRUE.
}

// load_digits: how many digits the register being loaded takes.
FUNCTION load_digits {
  PARAMETER ks, vehicle.
  LOCAL ld IS ks["LOAD"].
  LOCAL reg IS ld["COMPS"][ld["POS"]].
  RETURN vehicle["LOADS"]["" + ld["NOUN"]]["DIGITS"][reg - 1].
}

// load_advance: move to the next register, or finish the load: commit the values and go to the monitor verb.
FUNCTION load_advance {
  PARAMETER ks, vehicle.
  LOCAL ld IS ks["LOAD"].
  SET ld["BUF"] TO "".
  SET ld["SIGN"] TO "+".
  SET ld["SIGNED"] TO FALSE.
  SET ld["POS"] TO ld["POS"] + 1.
  IF ld["POS"] < ld["COMPS"]:LENGTH { RETURN. }
  LOCAL noun IS ld["NOUN"].
  LOCAL got_comps IS ld["GOT_COMPS"].
  LOCAL got_values IS ld["GOT_VALUES"].
  SET ld["ACTIVE"] TO FALSE.
  SET ld["COMPS"] TO LIST().
  SET ld["GOT_COMPS"] TO LIST().
  SET ld["GOT_VALUES"] TO LIST().
  SET ks["VERB"] TO 16.
  IF got_comps:LENGTH > 0 {
    LOCAL refusal IS vehicle["LOAD_COMMIT"]:CALL(noun, got_comps, got_values).
    IF refusal <> "" {
      SET ks["OPRERR"] TO TRUE.
      SET ld["MSG"] TO "Load refused: " + refusal + ".".
    }
  }
}

// load_key: one key (upper case, "E" for ENTR) while a load may be active. Returns TRUE when the load took the key. Keys
// typed while a verb or noun is being keyed (ks["MODE"] is "V" or "N"), and the V and N keys themselves, are not the load's:
// they return FALSE and the normal key handler deals with them.
FUNCTION load_key {
  PARAMETER ks, vehicle, key.
  IF NOT ks["LOAD"]["ACTIVE"] { RETURN FALSE. }
  IF ks["MODE"] <> "" OR key = "V" OR key = "N" { RETURN FALSE. }
  LOCAL ld IS ks["LOAD"].
  LOCAL octal IS load_octal(ks, vehicle).
  IF "0123456789":CONTAINS(key) AND key:LENGTH = 1 {
    IF octal AND "89":CONTAINS(key) { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    // A digit after the register is full is ignored, with no alarm (PINBALL NUM: DSPCOUNT negative, ENDOFJOB).
    IF ld["BUF"]:LENGTH < load_digits(ks, vehicle) { SET ld["BUF"] TO ld["BUF"] + key. }
    RETURN TRUE.
  }
  IF key = "+" OR key = "-" {
    IF octal { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    // A sign is taken only as the first character of a register and only the first of consecutive signs; any other sign is
    // ignored with no alarm (PINBALL SIGNTEST: "NO MATCH FOUND. SIGN ILLEGAL" and "SIGN FOR THIS WORD ALREADY IN. REJECT" both ENDOFJOB).
    IF ld["BUF"]:LENGTH = 0 AND NOT ld["SIGNED"] { SET ld["SIGN"] TO key. SET ld["SIGNED"] TO TRUE. }
    RETURN TRUE.
  }
  IF key = "C" {
    SET ld["BUF"] TO "".
    SET ld["SIGN"] TO "+".
    SET ld["SIGNED"] TO FALSE.
    RETURN TRUE.
  }
  IF key = "R" {
    SET ks["OPRERR"] TO FALSE.          // RSET leaves the load running (Luminary ERROR clears OPR ERR and restores the display lock only)
    RETURN TRUE.
  }
  IF key = "E" OR key = "P" {
    // PINBALL ENTER: a decimal register needs all its characters; with fewer it alarms and leaves the load waiting (and the buffer
    // as it was) so the pilot can key the missing digits. PRO is the way to leave a register as it was.
    // An octal register takes any number of digits up to its width, at least one.
    IF key = "E" AND octal AND ld["BUF"]:LENGTH = 0 { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    IF key = "E" AND NOT octal AND ld["BUF"]:LENGTH <> load_digits(ks, vehicle) { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    // Digits keyed with no sign are an octal load in PINBALL; a decimal noun (PINBALL_NOUN_TABLES.agc) then alarms and recycles the verb
    // (ALMCYCLE: OPR ERR, the verb and noun start again from the first register).
    IF key = "E" AND NOT octal AND NOT ld["SIGNED"] {
      SET ks["OPRERR"] TO TRUE.
      SET ld["POS"] TO 0.
      SET ld["BUF"] TO "".
      SET ld["SIGN"] TO "+".
      SET ld["SIGNED"] TO FALSE.
      SET ld["GOT_COMPS"] TO LIST().
      SET ld["GOT_VALUES"] TO LIST().
      RETURN TRUE.
    }
    IF key = "E" {
      LOCAL magnitude IS 0.
      IF octal { SET magnitude TO octal_parse(ld["BUF"]). } ELSE { SET magnitude TO ld["BUF"]:TONUMBER(0). }
      LOCAL reg IS ld["COMPS"][ld["POS"]].
      ld["GOT_COMPS"]:ADD(reg).
      ld["GOT_VALUES"]:ADD((CHOOSE -magnitude IF ld["SIGN"] = "-" ELSE magnitude)).
    }
    load_advance(ks, vehicle).
    RETURN TRUE.
  }
  RETURN TRUE.          // any other key does nothing during a load
}

// load_shown: what to show in the register being loaded: LEXICON("REG", 1 to 3 or 0 when no load, "TEXT", the keyed sign and
// digits left-aligned in the register's width; blank until the pilot keys something, "DONE", a LIST of LIST(register, text) for the
// registers already entered with ENTR in this load: they keep showing the value keyed (as on the real DSKY) while the next one is keyed,
// as a sign and zero-padded digits, e.g. "+00083"). An octal register shows its digits with a blank in the sign's place.
FUNCTION load_shown {
  PARAMETER ks, vehicle.
  LOCAL ld IS ks["LOAD"].
  IF NOT ld["ACTIVE"] { RETURN LEXICON("REG", 0, "TEXT", "", "DONE", LIST()). }
  LOCAL done IS LIST().
  LOCAL i IS 0.
  UNTIL i >= ld["GOT_COMPS"]:LENGTH {
    LOCAL got_reg IS ld["GOT_COMPS"][i].
    LOCAL got_value IS ld["GOT_VALUES"][i].
    LOCAL got_width IS vehicle["LOADS"]["" + ld["NOUN"]]["DIGITS"][got_reg - 1].
    IF load_octal(ks, vehicle) {
      done:ADD(LIST(got_reg, " " + octal_text(got_value, got_width))).
    } ELSE {
      LOCAL digits IS "" + ABS(got_value).
      UNTIL digits:LENGTH >= got_width { SET digits TO "0" + digits. }
      done:ADD(LIST(got_reg, (CHOOSE "-" IF got_value < 0 ELSE "+") + digits)).
    }
    SET i TO i + 1.
  }
  LOCAL width IS load_digits(ks, vehicle).
  LOCAL text IS "".
  IF ld["SIGNED"] OR ld["BUF"]:LENGTH > 0 {
    LOCAL sign_char IS " ".
    IF ld["SIGNED"] { SET sign_char TO ld["SIGN"]. }
    SET text TO sign_char + ld["BUF"].
    UNTIL text:LENGTH >= width + 1 { SET text TO text + " ". }
  }
  RETURN LEXICON("REG", ld["COMPS"][ld["POS"]], "TEXT", text, "DONE", done).
}
