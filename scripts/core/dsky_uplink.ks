// dsky_uplink.ks -- the uplink feed: the ground's data arrive as a stream of key presses (Luminary's UPRUPT takes a key code from
// the uplink and handles it like a keypad key). Here the stream is a text file the planner writes (the vehicle's "UPLINK_FILE",
// the LM's is 0:/lm/uplink.txt), one key name per line: V N E + - C P R and the digits 0 to 9. The DSKY's main loop checks for the
// file once a second; when it finds one and the DSKY can take it, it reads the keys, deletes the file, and presses one key every
// UPLINK_KEY_PERIOD_S through key_press, the same handler the keypad uses. UPLINK ACTY (ks["P27"]["ACTY"], see dsky_p27.ks) comes
// on with the first key and the feed counts as active until the last key is pressed.
// The DSKY can take the file only when the vehicle allows an update (the LM: P00, no programme running) and no keyed load or update
// is already active; otherwise the file stays, untouched, and one warning says why. The same keys typed by hand have the same effect.
// Needs dsky_keys.ks (key_press) and dsky_p27.ks.

GLOBAL UPLINK_KEY_PERIOD_S IS 0.2.
GLOBAL UPLINK_CHECK_PERIOD_S IS 1.
GLOBAL UPLINK_VALID_KEYS IS "VNE+-CPR0123456789".

// uplink_new: a feed reading the file at path.
FUNCTION uplink_new {
  PARAMETER file_path.
  RETURN LEXICON("PATH", file_path, "KEYS", LIST(), "NEXT_T", 0, "ACTIVE", FALSE, "CHECK_T", 0, "WARNED", FALSE).
}

// uplink_parse: the text of an uplink file as a LIST of key names. Blank lines, unknown names and anything longer than one
// character are skipped; names are upper-cased.
FUNCTION uplink_parse {
  PARAMETER text.
  LOCAL keys IS LIST().
  FOR line IN text:SPLIT(CHAR(10)) {
    LOCAL name IS line:TRIM():TOUPPER.
    IF name:LENGTH = 1 { IF UPLINK_VALID_KEYS:CONTAINS(name) { keys:ADD(name). } }
  }
  RETURN keys.
}

// uplink_poll: one call per main-loop cycle. in_p00: the vehicle's answer to "may an update start now". now: the clock (seconds).
// Returns LEXICON("ACTIVE", TRUE while keys remain to be pressed, "MSG", a line to print or "").
FUNCTION uplink_poll {
  PARAMETER feed, ks, vehicle, in_p00, now.
  LOCAL msg IS "".
  IF feed["KEYS"]:LENGTH = 0 {
    IF now >= feed["CHECK_T"] {
      SET feed["CHECK_T"] TO now + UPLINK_CHECK_PERIOD_S.
      IF EXISTS(feed["PATH"]) {
        IF NOT in_p00 {
          IF NOT feed["WARNED"] { SET msg TO "Uplink waiting: not in P00 (V37 E 00 E to end the programme).". SET feed["WARNED"] TO TRUE. }
        } ELSE IF load_active(ks) OR p27_active(ks) {
          IF NOT feed["WARNED"] { SET msg TO "Uplink waiting: a load or update is in progress (V34 E ends it).". SET feed["WARNED"] TO TRUE. }
        } ELSE {
          LOCAL keys IS uplink_parse(OPEN(feed["PATH"]):READALL:STRING).
          DELETEPATH(feed["PATH"]).
          SET feed["WARNED"] TO FALSE.
          IF keys:LENGTH > 0 {
            SET feed["KEYS"] TO keys.
            SET feed["NEXT_T"] TO now.
            SET feed["ACTIVE"] TO TRUE.
          }
        }
      } ELSE {
        SET feed["WARNED"] TO FALSE.
      }
    }
  }
  IF feed["KEYS"]:LENGTH > 0 AND now >= feed["NEXT_T"] {
    LOCAL key IS feed["KEYS"][0].
    feed["KEYS"]:REMOVE(0).
    SET ks["P27"]["ACTY"] TO TRUE.            // a key from the ground: UPLINK ACTY (shown while P27 is active)
    key_press(ks, key).
    SET feed["NEXT_T"] TO now + UPLINK_KEY_PERIOD_S.
    IF feed["KEYS"]:LENGTH = 0 {
      SET feed["ACTIVE"] TO FALSE.
      IF NOT p27_active(ks) { SET ks["P27"]["ACTY"] TO FALSE. }
    }
  }
  RETURN LEXICON("ACTIVE", feed["ACTIVE"], "MSG", msg).
}
