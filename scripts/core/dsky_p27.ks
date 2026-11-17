// dsky_p27.ks -- P27, the update program: the ground's way of loading erasable memory (Luminary UPDATE_PROGRAM.agc). Vehicle-
// independent: the store and the rule "when is an update allowed" come from the vehicle LEXICON:
//   "STORE"    the erasable store (dsky_store.ks)
//   "P27_OK"   delegate (prog) -> bool: TRUE when an update may start now (prog is the running programme's LEXICON or FALSE)
// Keystrokes (all numbers octal, as the real update was sent):
//   V71 E  II E  AAAA E  XXXXX E ... XXXXX E  V33 E     block: ECADR AAAA, then II-2 words (3 <= II <= 20 decimal)
//   V72 E  II E  AAAA E XXXXX E ... AAAA E XXXXX E  V33 E   scatter: (II-1)/2 pairs of ECADR and word (II odd, 3 to 19 decimal)
//   V34 E at any point throws the block away. V70 and V73 (clock and liftoff-time increments) are not implemented: OPR ERR.
// The data are held, and written to the store only by V33 E after the last word (the real program shows a flashing V21 N02
// and waits for V33 to verify). A count outside its range, no digits before ENTR, or any word that
// falls in no cell of the store throws the whole block away with OPR ERR and a terminal line; nothing is written. An 8 or 9 is OPR ERR
// and ignored, a sixth digit ignored (as PINBALL does), and the update goes on.
// Departures from Luminary: a bad count or ECADR is OPR ERR and a discard (Luminary asks again or alarms); the component-
// correction loop of the verify display is not implemented; V32 (recycle) is not implemented.
// While P27 is active the PROG display shows 27, V21 N01 (N02 at the verify step) flashes, R1 shows the digits keyed and R3 the
// buffer address (p27_shown).
// UPLINK ACTY: ks["P27"]["ACTY"] is set by the uplink feed (dsky_uplink.ks) when keys arrive from the ground; the core lights the
// lamp while P27 is active and ACTY is set (Luminary UPACTOFF turns it off on every exit from P27).

// p27_new: the state kept in the key state (ks["P27"]).
FUNCTION p27_new {
  RETURN LEXICON("ACTIVE", FALSE, "KIND", 0, "STEP", "", "COUNT", 0, "NEEDED", 0, "BUF", "", "WORDS", LIST(), "ACTY", FALSE,
                 "OLD_NOUN", -1, "MSG", "").
}

FUNCTION p27_active {
  PARAMETER ks.
  RETURN ks["P27"]["ACTIVE"].
}

// p27_cancel: leave P27 without writing anything, restore the display and turn UPLINK ACTY off.
FUNCTION p27_cancel {
  PARAMETER ks.
  LOCAL p27 IS ks["P27"].
  IF NOT p27["ACTIVE"] { RETURN. }
  SET p27["ACTIVE"] TO FALSE.
  SET p27["ACTY"] TO FALSE.
  SET p27["BUF"] TO "".
  SET p27["WORDS"] TO LIST().
  IF p27["OLD_NOUN"] >= 0 {
    SET ks["VERB"] TO 16.
    SET ks["NOUN"] TO p27["OLD_NOUN"].
  } ELSE {
    SET ks["VERB"] TO -1.
    SET ks["NOUN"] TO -1.
  }
}

// p27_discard: throw the block away as an error: OPR ERR, and a terminal line with the reason.
FUNCTION p27_discard {
  PARAMETER ks, reason.
  p27_cancel(ks).
  SET ks["OPRERR"] TO TRUE.
  SET ks["P27"]["MSG"] TO "Update refused: " + reason + ".".
}

// p27_begin: V71 or V72 keyed. FALSE (the caller lights OPR ERR) when the vehicle has no store or does not allow an update now
// (the LM: only in P00), or a keyed load is active.
FUNCTION p27_begin {
  PARAMETER ks, vehicle, verb.
  IF NOT vehicle:ISTYPE("Lexicon") { RETURN FALSE. }
  IF NOT (vehicle:HASKEY("STORE") AND vehicle:HASKEY("P27_OK")) { RETURN FALSE. }
  IF NOT vehicle["P27_OK"]:CALL(ks["PROGRAM"]) { RETURN FALSE. }
  IF load_active(ks) OR p27_active(ks) { RETURN FALSE. }
  LOCAL p27 IS ks["P27"].
  SET p27["ACTIVE"] TO TRUE.
  SET p27["KIND"] TO verb.
  SET p27["STEP"] TO "COUNT".
  SET p27["COUNT"] TO 0.
  SET p27["NEEDED"] TO 0.
  SET p27["BUF"] TO "".
  SET p27["WORDS"] TO LIST().
  SET p27["OLD_NOUN"] TO ks["NOUN"].
  SET ks["VERB"] TO 21.
  SET ks["NOUN"] TO 1.
  RETURN TRUE.
}

// p27_key: one key (upper case, "E" for ENTR) while P27 may be active. TRUE when P27 took the key. V and N (the start of a verb
// or noun, so V33 and V34 can be keyed) and anything typed while one is being keyed are not P27's: FALSE.
FUNCTION p27_key {
  PARAMETER ks, vehicle, key.
  IF NOT ks["P27"]["ACTIVE"] { RETURN FALSE. }
  IF ks["MODE"] <> "" OR key = "V" OR key = "N" { RETURN FALSE. }
  LOCAL p27 IS ks["P27"].
  IF "0123456789":CONTAINS(key) AND key:LENGTH = 1 {
    IF p27["STEP"] = "VERIFY" { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    // PINBALL: an 8 or 9 in an octal word turns OPR ERR on and the key is ignored (89TEST, CHARALRM); a digit after the fifth is
    // ignored with no alarm (NUM). Neither ends the update.
    IF "89":CONTAINS(key) { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }
    IF p27["BUF"]:LENGTH < 5 { SET p27["BUF"] TO p27["BUF"] + key. }
    RETURN TRUE.
  }
  IF key = "C" { SET p27["BUF"] TO "". RETURN TRUE. }
  IF key = "R" { SET ks["OPRERR"] TO FALSE. RETURN TRUE. }          // RSET leaves the update running; V34 ENTR throws it away
  IF key = "E" {
    IF p27["STEP"] = "VERIFY" { SET ks["OPRERR"] TO TRUE. RETURN TRUE. }     // waiting for V33 (store) or V34 (throw away)
    LOCAL value IS octal_parse(p27["BUF"]).
    SET p27["BUF"] TO "".
    IF value < 0 { p27_discard(ks, "nothing keyed before ENTR"). RETURN TRUE. }
    IF p27["STEP"] = "COUNT" {
      LOCAL limit IS (CHOOSE 20 IF p27["KIND"] = 71 ELSE 19).
      LOCAL odd_ok IS (p27["KIND"] = 71 OR MOD(value, 2) = 1).
      IF value < 3 OR value > limit OR NOT odd_ok { p27_discard(ks, "bad component count"). RETURN TRUE. }
      SET p27["COUNT"] TO value.
      SET p27["NEEDED"] TO value - 1.         // V71: the ECADR and II-2 words; V72: II-1 = 2 x pairs
      SET p27["STEP"] TO "DATA".
      RETURN TRUE.
    }
    p27["WORDS"]:ADD(value).
    IF p27["WORDS"]:LENGTH >= p27["NEEDED"] {
      SET p27["STEP"] TO "VERIFY".
      SET ks["NOUN"] TO 2.
    }
    RETURN TRUE.
  }
  RETURN TRUE.          // any other key does nothing during P27
}

// p27_verify: V33 keyed. At the verify step: check that every word lands in a cell of the store, then write them all and leave P27.
// Anywhere else it is OPR ERR and the block is kept.
FUNCTION p27_verify {
  PARAMETER ks, vehicle.
  LOCAL p27 IS ks["P27"].
  IF p27["STEP"] <> "VERIFY" { SET ks["OPRERR"] TO TRUE. RETURN. }
  LOCAL vault IS vehicle["STORE"].
  LOCAL targets IS LIST().          // LIST of LIST(cell name, word index, value)
  LOCAL words IS p27["WORDS"].
  IF p27["KIND"] = 71 {
    FROM { LOCAL k IS 1. } UNTIL k >= words:LENGTH STEP { SET k TO k + 1. } DO {
      LOCAL hit IS store_locate(vault, words[0] + k - 1).
      IF hit["NAME"] = "" { p27_discard(ks, "ECADR " + octal_text(words[0] + k - 1, 4) + " is not in the store"). RETURN. }
      targets:ADD(LIST(hit["NAME"], hit["INDEX"], words[k])).
    }
  } ELSE {
    FROM { LOCAL k IS 0. } UNTIL k >= words:LENGTH STEP { SET k TO k + 2. } DO {
      LOCAL hit IS store_locate(vault, words[k]).
      IF hit["NAME"] = "" { p27_discard(ks, "ECADR " + octal_text(words[k], 4) + " is not in the store"). RETURN. }
      targets:ADD(LIST(hit["NAME"], hit["INDEX"], words[k + 1])).
    }
  }
  FOR entry_t IN targets { store_put(vault, entry_t[0], entry_t[1], entry_t[2]). }
  p27_cancel(ks).                   // normal exit: display restored, UPLINK ACTY off
}

// p27_prog_text: the programme number the DSKY shows: 27 while an update is active (Luminary sets the major mode to 27 and restores
// the old one at the end), else default_text (the programme number as the core would show it).
FUNCTION p27_prog_text {
  PARAMETER ks, default_text.
  IF p27_active(ks) { RETURN "27". }
  RETURN default_text.
}

// p27_shown: what P27 puts on the registers: LEXICON("ACTIVE", bool, "R1", text, "R3", text). R1 is the octal word being keyed, the
// sign cell blank and the digits filling from the left as they are keyed (the real DSKY does not pad with zeros; blank when nothing is keyed).
// R3 is the address stream of UPDATE_PROGRAM.agc: the ECADR of UPBUFF plus the number of items received so far (II, the ECADR and the
// words) while it asks for data (V21 N01), the ECADR of UPTEMP at the verify step (V21 N02). It needs the vehicle's "P27_ADDR"
// (LEXICON "BUFF", "TEMP": the update program's real addresses, which differ by software version); without it R3 is blank.
FUNCTION p27_shown {
  PARAMETER ks, vehicle.
  LOCAL p27 IS ks["P27"].
  IF NOT p27["ACTIVE"] { RETURN LEXICON("ACTIVE", FALSE, "R1", "", "R3", ""). }
  LOCAL r1_text IS "".
  IF p27["BUF"]:LENGTH > 0 {
    SET r1_text TO " " + p27["BUF"].
    UNTIL r1_text:LENGTH >= 6 { SET r1_text TO r1_text + " ". }
  }
  LOCAL r3_text IS "".
  IF vehicle:ISTYPE("Lexicon") {
    IF vehicle:HASKEY("P27_ADDR") {
      LOCAL slot IS vehicle["P27_ADDR"]["TEMP"].
      IF p27["STEP"] <> "VERIFY" {
        LOCAL received IS 0.
        IF p27["STEP"] = "DATA" { SET received TO 1 + p27["WORDS"]:LENGTH. }
        SET slot TO vehicle["P27_ADDR"]["BUFF"] + received.
      }
      SET r3_text TO " " + octal_text(slot, 5).
    }
  }
  RETURN LEXICON("ACTIVE", TRUE, "R1", r1_text, "R3", r3_text).
}
