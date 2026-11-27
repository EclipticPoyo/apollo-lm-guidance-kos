// test_keyrel.ks -- pad test for the pending request, KEY REL, V32, V33, V34, verb actions and no-noun verbs in the DSKY core (no ship access).
//   RUNPATH("0:/tests/test_keyrel.ks").   Log: 0:/lm/logs/test_keyrel.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").

test_begin("0:/lm/logs/test_keyrel.log").

GLOBAL KR_NEXT IS LEXICON().
GLOBAL KR_ACTION_CALLS IS 0.
GLOBAL KR_ACTION_RESULT IS FALSE.
GLOBAL KR_SEEN IS LEXICON("PRO", FALSE, "RECYCLE", FALSE, "TERMINATE", FALSE, "ENTER", FALSE).

// kr_out: a quiet programme output, with an optional request (FALSE for none).
FUNCTION kr_out {
  PARAMETER request.
  RETURN LEXICON("SET_VERB", -1, "SET_NOUN", -1, "EXTRA", LEXICON(), "MSG", "", "KEY_REL", FALSE, "ALT_LAMP", FALSE,
                 "VEL_LAMP", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE, "ENDED", FALSE, "HANDOVER", FALSE,
                 "PROG_NO", 63, "REQUEST", request).
}

LOCAL fake_vehicle IS LEXICON(
  "NOUNS", LIST(60, 61), "VERBS", LIST(6, 16, 32, 33, 34, 37, 57, 59), "PROGS", LIST(0, 1),
  "NO_NOUN_VERBS", LIST(59),
  "VERB_ACTIONS", LEXICON("57", { PARAMETER ks. SET KR_ACTION_CALLS TO KR_ACTION_CALLS + 1. RETURN KR_ACTION_RESULT. },
                          "59", { PARAMETER ks. SET KR_ACTION_CALLS TO KR_ACTION_CALLS + 1. RETURN TRUE. }),
  "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL"),
  "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON(). },
  "STICKY_PROGS", LIST(68),
  "PROGRAMMES", LEXICON("1", LEXICON("START", { PARAMETER prev. RETURN LEXICON("PROG_NO", 1, "REFUSED", ""). },
                                      "STEP", { PARAMETER prog, nav, ks.
                                                SET KR_SEEN["PRO"] TO ks["PRO"].
                                                SET KR_SEEN["RECYCLE"] TO ks["RECYCLE"].
                                                SET KR_SEEN["TERMINATE"] TO ks["TERMINATE"].
                                                SET KR_SEEN["ENTER"] TO ks["ENTER"].
                                                SET ks["PRO"] TO FALSE.
                                                RETURN KR_NEXT. },
                                      "END", { PARAMETER prog. },
                                      "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE))).
LOCAL nav IS LEXICON("OK", TRUE, "STATE", LEXICON(), "DERIVED", LEXICON("VALID", FALSE)).

// kr_fresh: a new key state and run state with programme 1 running.
FUNCTION kr_fresh {
  LOCAL ks IS keys_new(fake_vehicle["NOUNS"], fake_vehicle["VERBS"], fake_vehicle["PROGS"], LIST(), fake_vehicle["NO_NOUN_VERBS"]).
  SET ks["VEHICLE"] TO fake_vehicle.
  RETURN ks.
}
FUNCTION kr_type {
  PARAMETER ks, text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks, text:SUBSTRING(i, 1)). }
}
FUNCTION kr_step {
  PARAMETER crun, ks, nav_in.
  RETURN core_step(crun, fake_vehicle, nav_in, ks).
}

LOCAL ks IS kr_fresh().
LOCAL crun IS core_new(fake_vehicle).
core_request(crun, fake_vehicle, ks, 1).
SET KR_NEXT TO kr_out(LEXICON("VERB", 6, "NOUN", 61)).
SET KR_NEXT["SET_VERB"] TO 6.
SET KR_NEXT["SET_NOUN"] TO 61.
LOCAL res IS kr_step(crun, ks, nav).
SET KR_NEXT["SET_VERB"] TO -1.
SET KR_NEXT["SET_NOUN"] TO -1.
assert_true("a request flashes the display and is pending", res["FLAGS"]["FLASH"] AND ks["PENDING"]:ISTYPE("Lexicon")).
assert_true("KEY REL is dark before the pilot keys anything", NOT res["FLAGS"]["KEYREL"]).

// keying over the request lights KEY REL; RSET does not
kr_type(ks, "R").
assert_true("RSET does not light KEY REL", NOT ks["KEYREL"]).
kr_type(ks, "V16E").
SET res TO kr_step(crun, ks, nav).
assert_true("V16 ENTR over a request lights KEY REL", res["FLAGS"]["KEYREL"] AND ks["VERB"] = 16).
assert_true("the flash stops while the display shows something else", NOT res["FLAGS"]["FLASH"]).
kr_type(ks, "K").
SET res TO kr_step(crun, ks, nav).
assert_true("KEY REL restores the request's verb and noun and puts the lamp out", ks["VERB"] = 6 AND ks["NOUN"] = 61 AND NOT res["FLAGS"]["KEYREL"] AND res["FLAGS"]["FLASH"]).
kr_type(ks, "V1").
SET res TO kr_step(crun, ks, nav).
assert_true("a half-typed verb lights KEY REL and stops the flash", res["FLAGS"]["KEYREL"] AND NOT res["FLAGS"]["FLASH"]).
kr_type(ks, "K").
assert_true("KEY REL drops the half-typed verb", ks["MODE"] = "" AND ks["VBUF"] = "" AND ks["VERB"] = 6).

// V33 / V32 / V34 and the response flags
kr_type(ks, "V33E").
assert_true("V33 ENTR over a request: PRO set, no OPR ERR, display unchanged", ks["PRO"] AND NOT ks["OPRERR"] AND ks["VERB"] = 6 AND ks["NOUN"] = 61).
SET res TO kr_step(crun, ks, nav).
assert_true("the step sees PRO and clears it", KR_SEEN["PRO"] AND NOT ks["PRO"]).
kr_type(ks, "V32E").
SET res TO kr_step(crun, ks, nav).
assert_true("V32 ENTR is seen as RECYCLE for one cycle", KR_SEEN["RECYCLE"] AND NOT ks["RECYCLE"] AND NOT ks["OPRERR"]).
SET res TO kr_step(crun, ks, nav).
assert_true("RECYCLE is gone the next cycle", NOT KR_SEEN["RECYCLE"]).
kr_type(ks, "V34E").
assert_true("V34 ENTR with a request pending sets TERMINATE and leaves the display", ks["TERMINATE"] AND ks["VERB"] = 6 AND NOT ks["OPRERR"]).
SET res TO kr_step(crun, ks, nav).
assert_true("the step saw TERMINATE for one cycle", KR_SEEN["TERMINATE"] AND NOT ks["TERMINATE"]).
kr_type(ks, "E").
SET res TO kr_step(crun, ks, nav).
assert_true("any ENTR is seen as ENTER for one cycle", KR_SEEN["ENTER"] AND NOT ks["ENTER"]).

// nothing pending
SET KR_NEXT TO kr_out(FALSE).
SET res TO kr_step(crun, ks, nav).
assert_true("the request ends with the step: nothing pending, no flash", NOT ks["PENDING"]:ISTYPE("Lexicon") AND NOT res["FLAGS"]["FLASH"]).
SET ks TO kr_fresh().
core_request(crun, fake_vehicle, ks, 1).
SET KR_NEXT TO kr_out(FALSE).
kr_type(ks, "V33E").
assert_true("V33 with nothing pending sets PRO, no OPR ERR, the verb is left alone", ks["PRO"] AND NOT ks["OPRERR"] AND ks["VERB"] = 16).
kr_type(ks, "V34E").
assert_true("V34 with nothing pending sets no TERMINATE and no OPR ERR", NOT ks["TERMINATE"] AND NOT ks["OPRERR"]).
SET ks TO kr_fresh().
SET KR_NEXT TO kr_out(FALSE).
kr_type(ks, "K").
assert_true("KEY REL with nothing pending and no programme display: no crash, lamp dark, nothing changed (Review Focus 6)", NOT ks["KEYREL"] AND ks["VERB"] = 16 AND NOT ks["OPRERR"]).
kr_type(ks, "V16N60").
SET KR_NEXT TO kr_out(FALSE).
SET KR_NEXT["SET_VERB"] TO 16.
SET KR_NEXT["SET_NOUN"] TO 61.
core_request(crun, fake_vehicle, ks, 1).
kr_step(crun, ks, nav).
SET KR_NEXT["SET_VERB"] TO -1.
SET KR_NEXT["SET_NOUN"] TO -1.
kr_type(ks, "V16N60E").
kr_type(ks, "K").
assert_true("KEY REL with no request restores the programme's last verb and noun", ks["VERB"] = 16 AND ks["NOUN"] = 61).

// verb actions and verbs that take no noun
SET ks TO kr_fresh().
SET KR_ACTION_CALLS TO 0.
SET KR_ACTION_RESULT TO FALSE.
kr_type(ks, "V57N60E").
assert_true("a verb action is called once; FALSE is OPR ERR and the display is not changed", KR_ACTION_CALLS = 1 AND ks["OPRERR"] AND ks["VERB"] = 16 AND ks["NOUN"] = 60).
SET ks TO kr_fresh().
SET KR_ACTION_RESULT TO TRUE.
kr_type(ks, "V57N60E").
assert_true("a verb action that returns TRUE is not an error and leaves the display", NOT ks["OPRERR"] AND ks["VERB"] = 16 AND ks["NOUN"] = 60 AND KR_ACTION_CALLS = 2).
SET ks TO kr_fresh().
SET ks["NOUN"] TO -1.
SET ks["VERB"] TO -1.
kr_type(ks, "V59E").
assert_true("a verb in NO_NOUN_VERBS is accepted with no noun", NOT ks["OPRERR"] AND KR_ACTION_CALLS = 3).
kr_type(ks, "V57E").
assert_true("another verb with no noun is still OPR ERR", ks["OPRERR"]).

// a programme's steady display covered by the pilot's (Luminary: the programme finds the display held and lights KEY REL)
SET ks TO kr_fresh().
SET crun TO core_new(fake_vehicle).
core_request(crun, fake_vehicle, ks, 1).
SET KR_NEXT TO kr_out(FALSE).
SET KR_NEXT["SET_VERB"] TO 6.
SET KR_NEXT["SET_NOUN"] TO 61.
SET res TO kr_step(crun, ks, nav).
SET KR_NEXT["SET_VERB"] TO -1.
SET KR_NEXT["SET_NOUN"] TO -1.
assert_true("the programme's own display leaves KEY REL dark", NOT res["FLAGS"]["KEYREL"]).
kr_type(ks, "V16N60E").
SET res TO kr_step(crun, ks, nav).
assert_true("a monitor over the programme's steady display lights KEY REL", res["FLAGS"]["KEYREL"] AND ks["VERB"] = 16 AND ks["NOUN"] = 60).
SET res TO kr_step(crun, ks, nav).
assert_true("the lamp stays while the monitor is up", res["FLAGS"]["KEYREL"]).
kr_type(ks, "R").
SET res TO kr_step(crun, ks, nav).
assert_true("RSET leaves the monitor and the lamp", res["FLAGS"]["KEYREL"] AND ks["VERB"] = 16).
kr_type(ks, "K").
SET res TO kr_step(crun, ks, nav).
assert_true("KEY REL brings the programme's display back and puts the lamp out", ks["VERB"] = 6 AND ks["NOUN"] = 61 AND NOT res["FLAGS"]["KEYREL"]).
kr_type(ks, "V1").
SET res TO kr_step(crun, ks, nav).
assert_true("a half-typed verb over a steady display lights KEY REL", res["FLAGS"]["KEYREL"]).
kr_type(ks, "K").
kr_type(ks, "V37E").
SET res TO kr_step(crun, ks, nav).
assert_true("keying the programme number does not light it (V37 releases the display)", NOT res["FLAGS"]["KEYREL"]).
SET ks TO kr_fresh().
SET crun TO core_new(fake_vehicle).
kr_type(ks, "V16N60E").
SET res TO kr_step(crun, ks, nav).
assert_true("with no programme running a monitor leaves KEY REL dark", NOT res["FLAGS"]["KEYREL"]).

// Clicked keys: queued by the button callbacks, pressed in click order, one ENTR or PRO a cycle.
SET ks TO kr_fresh().
LOCAL kr_clicks IS QUEUE().
FOR kr_key IN LIST("V", "3", "7", "E", "0", "0") { keys_click(kr_clicks, kr_key). }
keys_drain(ks, kr_clicks).
assert_true("clicks are pressed in click order and stop after ENTR (V37, programme not yet keyed)", ks["AWAIT_PROG"] AND ks["PBUF"] = "").
assert_near("the keys after ENTR wait for the next cycle", kr_clicks:LENGTH, 2, 0).
keys_drain(ks, kr_clicks).
assert_true("the next cycle presses them, the same key twice", ks["PBUF"] = "00" AND kr_clicks:LENGTH = 0).
SET ks TO kr_fresh().
keys_click(kr_clicks, "P").
keys_click(kr_clicks, "V").
keys_drain(ks, kr_clicks).
assert_true("clicks stop after PRO too", ks["PRO"] AND kr_clicks:LENGTH = 1).

// V34 during a load or update is covered in test_load.ks and test_p27.ks; the PROG alarm in test_alarm.ks
test_end().
