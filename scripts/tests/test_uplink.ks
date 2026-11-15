// test_uplink.ks -- pad test for the uplink feed (core/dsky_uplink.ks): a key file pressed into the DSKY's keys. No ship access;
// the clock is a number the test advances. Keystrokes are the ones `python scripts/tests/reference_loads.py` prints.
//   RUNPATH("0:/tests/test_uplink.ks").
// Log: 0:/lm/logs/test_uplink.log. The last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").

test_begin("0:/lm/logs/test_uplink.log").

LOCAL feed_path IS "0:/lm/logs/test_uplink_keys.txt".
GLOBAL UP_P00 IS TRUE.

FUNCTION up_make_vehicle {
  RETURN LEXICON("STORE", store_new(lm_cells_for("A11")), "P27_OK", { PARAMETER prog. RETURN UP_P00. }).
}

FUNCTION up_fresh_keys {
  PARAMETER vehicle.
  LOCAL ks IS keys_new(LIST(60), LIST(6, 16, 21, 25, 33, 34, 37, 71, 72), LIST(0)).
  SET ks["VEHICLE"] TO vehicle.
  RETURN ks.
}

// write_keys: a fresh uplink file holding the key names of text, one per line.
FUNCTION write_keys {
  PARAMETER file_path, text.
  IF EXISTS(file_path) { DELETEPATH(file_path). }
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { LOG text:SUBSTRING(i, 1) TO file_path. }
}

// ---- parsing ---------------------------------------------------------------------------------------------------------------
LOCAL parsed IS uplink_parse("v" + CHAR(10) + "7" + CHAR(10) + CHAR(10) + "x" + CHAR(10) + "ab" + CHAR(10) + " e " + CHAR(13) + CHAR(10) + "-").
assert_near("uplink_parse keeps v 7 e - and drops blank, x and ab", parsed:LENGTH, 4, 0).
assert_true("uplink_parse upper-cases and trims", parsed[0] = "V" AND parsed[1] = "7" AND parsed[2] = "E" AND parsed[3] = "-").

// ---- a feed writes the same words as keying by hand --------------------------------------------------------------------------
LOCAL veh IS up_make_vehicle().
LOCAL vault IS veh["STORE"].
LOCAL ks IS up_fresh_keys(veh).
LOCAL feed IS uplink_new(feed_path).
write_keys(feed_path, "V71E04E2400E03447E01600EV33E").
LOCAL now IS 0.
LOCAL polls IS 0.
LOCAL saw_acty IS FALSE.
LOCAL saw_active_midway IS FALSE.
LOCAL res IS uplink_poll(feed, ks, veh, UP_P00, now).
SET polls TO 1.
assert_true("the first poll takes the file and is active", res["ACTIVE"] AND NOT EXISTS(feed_path)).
UNTIL NOT res["ACTIVE"] OR polls > 200 {
  SET now TO now + UPLINK_KEY_PERIOD_S.
  SET res TO uplink_poll(feed, ks, veh, UP_P00, now).
  SET polls TO polls + 1.
  IF p27_active(ks) AND ks["P27"]["ACTY"] { SET saw_acty TO TRUE. }
  IF res["ACTIVE"] { SET saw_active_midway TO TRUE. }
}
assert_true("UPLINK ACTY was on while P27 was active", saw_acty).
assert_true("the feed ended before the safety limit", polls <= 200).
assert_true("TLAND is loaded by the feed", store_loaded(vault, "TLAND")).
LOCAL fed_words IS store_words(vault, "TLAND").
assert_true("the fed words are 03447 and 01600 octal (1831, 896)", fed_words[0] = 1831 AND fed_words[1] = 896).
assert_true("P27 is over and UPLINK ACTY is off after the V33", NOT p27_active(ks) AND NOT ks["P27"]["ACTY"]).
assert_true("the feed file is gone", NOT EXISTS(feed_path)).
assert_true("one key per period: the stream took at least 28 polls (28 keys)", polls >= 28).

// ---- same result as typing the keys -------------------------------------------------------------------------------------------
LOCAL veh_hand IS up_make_vehicle().
LOCAL ks_hand IS up_fresh_keys(veh_hand).
LOCAL hand_text IS "V71E04E2400E03447E01600EV33E".
FROM { LOCAL i IS 0. } UNTIL i >= hand_text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks_hand, hand_text:SUBSTRING(i, 1)). }
LOCAL hand_words IS store_words(veh_hand["STORE"], "TLAND").
assert_true("hand-keyed words equal the fed words", hand_words[0] = fed_words[0] AND hand_words[1] = fed_words[1]).

// ---- a programme running: the file stays (Review Focus 2) ---------------------------------------------------------------------
SET UP_P00 TO FALSE.
LOCAL veh_busy IS up_make_vehicle().
LOCAL ks_busy IS up_fresh_keys(veh_busy).
LOCAL feed_busy IS uplink_new(feed_path).
write_keys(feed_path, "V71E04E2400E03447E01600EV33E").
SET now TO 0.
LOCAL busy_res IS uplink_poll(feed_busy, ks_busy, veh_busy, UP_P00, now).
assert_true("not in P00: the file is left alone and the feed is not active", EXISTS(feed_path) AND NOT busy_res["ACTIVE"]).
assert_true("not in P00: a message says why", busy_res["MSG"] <> "").
SET now TO now + 2.
SET busy_res TO uplink_poll(feed_busy, ks_busy, veh_busy, UP_P00, now).
assert_true("the reason is said once, not every second", busy_res["MSG"] = "").
assert_true("nothing was written and P27 never started", NOT store_loaded(veh_busy["STORE"], "TLAND") AND NOT p27_active(ks_busy)).
SET UP_P00 TO TRUE.
SET now TO now + 2.
SET busy_res TO uplink_poll(feed_busy, ks_busy, veh_busy, UP_P00, now).
assert_true("back in P00 the waiting file is taken", busy_res["ACTIVE"] AND NOT EXISTS(feed_path)).
IF EXISTS(feed_path) { DELETEPATH(feed_path). }

// ---- a keyed load active: the file stays -------------------------------------------------------------------------------------------
LOCAL veh_load IS up_make_vehicle().
SET veh_load["LOADS"] TO LEXICON("60", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))).
SET veh_load["LOAD_COMMIT"] TO { PARAMETER noun_no, comps, values. RETURN "". }.
LOCAL ks_load IS up_fresh_keys(veh_load).
key_press(ks_load, "V").
key_press(ks_load, "2").
key_press(ks_load, "1").
key_press(ks_load, "E").
assert_true("a keyed load V21 N60 is active", load_active(ks_load)).
LOCAL feed_load IS uplink_new(feed_path).
write_keys(feed_path, "V71E04E2400E03447E01600EV33E").
LOCAL load_res IS uplink_poll(feed_load, ks_load, veh_load, TRUE, 0).
assert_true("a load in progress: the file stays", EXISTS(feed_path) AND NOT load_res["ACTIVE"] AND load_active(ks_load)).
DELETEPATH(feed_path).

// ---- an empty or unreadable file --------------------------------------------------------------------------------------------------
write_keys(feed_path, "xyz").
LOCAL feed_junk IS uplink_new(feed_path).
LOCAL junk_res IS uplink_poll(feed_junk, up_fresh_keys(up_make_vehicle()), up_make_vehicle(), TRUE, 0).
assert_true("a file with no valid keys is deleted and starts nothing", NOT junk_res["ACTIVE"] AND NOT EXISTS(feed_path)).

test_end().
