// test_core.ks -- pad test for the DSKY core's programme table (no ship access: the programmes are fakes).
//   RUNPATH("0:/tests/test_core.ks").
// Log: 0:/lm/logs/test_core.log. The last line is "TESTS: N passed, M failed".
// A fake vehicle holds four fake programmes in the table shape dsky_core.ks reads:
//   1: selectable, NEXT 2          2: not selectable, NEXT -1          3: selectable, NEXT 99 (no such programme)
//   4: selectable, START refuses (REFUSED text)
// Every fake START / END adds to the global CALLS lexicon, so the tests can count calls.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_core.log").

GLOBAL CALLS IS LEXICON("S1", 0, "E1", 0, "S2", 0, "E2", 0, "S3", 0, "E3", 0, "S4", 0, "P2_PREV", FALSE).

// fake_out: what a programme's step returns (the keys core_step reads), all quiet.
FUNCTION fake_out {
  PARAMETER prog_no.
  RETURN LEXICON("SET_VERB", -1, "SET_NOUN", -1, "EXTRA", LEXICON(), "MSG", "", "KEY_REL", FALSE, "ALT_LAMP", FALSE,
                 "VEL_LAMP", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE, "ENDED", FALSE, "HANDOVER", FALSE,
                 "PROG_NO", prog_no).
}
GLOBAL NEXT_OUT IS fake_out(1).      // what every fake step returns; each test sets it first

// fake_entry: a table entry whose START and END count their calls under the keys "S<n>" and "E<n>".
FUNCTION fake_entry {
  PARAMETER n, next_no, selectable, refuse_text.
  RETURN LEXICON(
    "START", { PARAMETER prev.
               SET CALLS["S" + n] TO CALLS["S" + n] + 1.
               IF n = 2 { SET CALLS["P2_PREV"] TO prev. }
               RETURN LEXICON("PROG_NO", n, "REFUSED", refuse_text). },
    "STEP", { PARAMETER prog, nav, ks. RETURN NEXT_OUT. },
    "END", { PARAMETER prog. IF CALLS:HASKEY("E" + n) { SET CALLS["E" + n] TO CALLS["E" + n] + 1. } },
    "SAMPLE", FALSE,
    "NEXT", next_no,
    "SELECTABLE", selectable).
}

LOCAL fake_vehicle IS LEXICON(
  "NOUNS", LIST(60), "VERBS", LIST(6, 16, 34, 37), "PROGS", LIST(0, 1, 3, 4),
  "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL", "CONTACT", "CONTACT"),
  "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON("CONTACT", idle_text = "68"). },
  "STICKY_PROGS", LIST(68),
  "PROGRAMMES", LEXICON("1", fake_entry(1, 2, TRUE, ""), "2", fake_entry(2, -1, FALSE, ""),
                        "3", fake_entry(3, 99, TRUE, ""), "4", fake_entry(4, -1, TRUE, "no plan, plan first"))).
LOCAL ks IS keys_new(fake_vehicle["NOUNS"], fake_vehicle["VERBS"], fake_vehicle["PROGS"]).
LOCAL nav IS LEXICON("OK", TRUE, "STATE", LEXICON(), "DERIVED", LEXICON("VALID", FALSE)).

// A fresh run state for each test.
LOCAL crun IS core_new(fake_vehicle).
assert_true("core_new has no programme", NOT crun["PROG"]:ISTYPE("Lexicon")).
assert_true("core_new idle text is 00", crun["IDLE_TEXT"] = "00").

// 1 and 2: a request that is not in the table, or not selectable, lights OPR ERR and starts nothing.
core_request(crun, fake_vehicle, ks, 77).
assert_true("request unknown number sets OPRERR", ks["OPRERR"]).
assert_true("request unknown number starts nothing", NOT crun["PROG"]:ISTYPE("Lexicon")).
SET ks["OPRERR"] TO FALSE.
core_request(crun, fake_vehicle, ks, 2).
assert_true("request non-selectable (P2) sets OPRERR and starts nothing", ks["OPRERR"] AND NOT crun["PROG"]:ISTYPE("Lexicon") AND CALLS["S2"] = 0).
SET ks["OPRERR"] TO FALSE.

// 3: P1 starts. 4: asking for it again ends it (END once) and starts it again (START twice).
core_request(crun, fake_vehicle, ks, 1).
assert_true("request P1 starts it", crun["PROG"]:ISTYPE("Lexicon") AND CALLS["S1"] = 1 AND NOT ks["OPRERR"]).
core_request(crun, fake_vehicle, ks, 1).
assert_true("reselect P1 calls END once and START twice", CALLS["E1"] = 1 AND CALLS["S1"] = 2).

// 5: request 0 ends the running programme once and starts nothing.
core_request(crun, fake_vehicle, ks, 0).
assert_true("request 0 ends the running programme once", CALLS["E1"] = 2 AND NOT crun["PROG"]:ISTYPE("Lexicon") AND NOT ks["OPRERR"]).
core_request(crun, fake_vehicle, ks, 0).
assert_true("request 0 with nothing running changes nothing", CALLS["E1"] = 2 AND NOT ks["OPRERR"]).

// 6: a START that refuses lights OPR ERR and returns the reason in MSG; nothing is running.
LOCAL refused IS core_request(crun, fake_vehicle, ks, 4).
assert_true("refused start sets OPRERR and returns the reason in MSG", ks["OPRERR"] AND refused["MSG"]:CONTAINS("no plan, plan first") AND NOT crun["PROG"]:ISTYPE("Lexicon")).
SET ks["OPRERR"] TO FALSE.

// 7: handover P1 to P2: P2's START gets the old programme, and END is not called on the old one.
core_request(crun, fake_vehicle, ks, 1).
LOCAL e1_before IS CALLS["E1"].
SET NEXT_OUT TO fake_out(1).
SET NEXT_OUT["HANDOVER"] TO TRUE.
core_step(crun, fake_vehicle, nav, ks).
assert_true("handover P1 to P2 passes the old programme to P2's START",
            CALLS["S2"] = 1 AND CALLS["P2_PREV"]:ISTYPE("Lexicon") AND CALLS["P2_PREV"]["PROG_NO"] = 1 AND crun["PROG"]["PROG_NO"] = 2).
assert_true("handover does not call END on the old programme", CALLS["E1"] = e1_before).
core_end(crun, fake_vehicle).

// 8: P3's NEXT is 99, which is not in the table: the programme ends cleanly with a message.
core_request(crun, fake_vehicle, ks, 3).
SET NEXT_OUT TO fake_out(3).
SET NEXT_OUT["HANDOVER"] TO TRUE.
LOCAL res8 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("handover to NEXT 99 ends the programme and gives a message, no crash",
            NOT crun["PROG"]:ISTYPE("Lexicon") AND CALLS["E3"] = 1 AND res8["MSG"] <> "").

// 9: ENDED with a PROG_NO in STICKY_PROGS leaves that number as the idle programme text.
core_request(crun, fake_vehicle, ks, 1).
SET NEXT_OUT TO fake_out(68).
SET NEXT_OUT["ENDED"] TO TRUE.
LOCAL e1_b9 IS CALLS["E1"].
core_step(crun, fake_vehicle, nav, ks).
assert_true("ENDED with PROG_NO 68 in STICKY_PROGS leaves IDLE_TEXT 68", crun["IDLE_TEXT"] = "68" AND NOT crun["PROG"]:ISTYPE("Lexicon") AND CALLS["E1"] = e1_b9 + 1).
LOCAL idle_res IS core_step(crun, fake_vehicle, nav, ks).
assert_true("idle text shows in PROG_TEXT and lights CONTACT via IDLE_LAMPS", idle_res["PROG_TEXT"] = "68" AND idle_res["FLAGS"]["CONTACT"]).
core_request(crun, fake_vehicle, ks, 0).
assert_true("a later request clears the idle text", crun["IDLE_TEXT"] = "00").

// 10: a lamp key in the programme's output reaches the flag the vehicle names.
core_request(crun, fake_vehicle, ks, 1).
SET NEXT_OUT TO fake_out(1).
SET NEXT_OUT["CONTACT"] TO TRUE.
SET NEXT_OUT["KEY_REL"] TO TRUE.
LOCAL res10 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("lamp key CONTACT maps to flags CONTACT", res10["FLAGS"]["CONTACT"]).
assert_true("lamp key KEY_REL maps to flags KEYREL", res10["FLAGS"]["KEYREL"] AND NOT res10["FLAGS"]["ALT"]).
assert_true("PROG_TEXT is the programme number while running", res10["PROG_TEXT"] = "1").

// 10b: SET_VERB, SET_NOUN and EXTRA reach the key state and the derived values.
SET NEXT_OUT TO fake_out(1).
SET NEXT_OUT["SET_VERB"] TO 6.
SET NEXT_OUT["SET_NOUN"] TO 60.
SET NEXT_OUT["EXTRA"] TO LEXICON("TTOGO", 12).
core_step(crun, fake_vehicle, nav, ks).
assert_true("SET_VERB and SET_NOUN reach the key state", ks["VERB"] = 6 AND ks["NOUN"] = 60).
assert_true("EXTRA reaches the derived values", nav["DERIVED"]:HASKEY("TTOGO") AND nav["DERIVED"]["TTOGO"] = 12).

// 10b2: a STATUS list from the programme comes back for the terminal readout; no STATUS gives an empty list.
SET NEXT_OUT TO fake_out(1).
assert_true("no STATUS key gives an empty status list", core_step(crun, fake_vehicle, nav, ks)["STATUS"]:LENGTH = 0).
SET NEXT_OUT["STATUS"] TO LIST("line one", "line two").
LOCAL res_st IS core_step(crun, fake_vehicle, nav, ks).
assert_true("STATUS lines are passed on", res_st["STATUS"]:LENGTH = 2 AND res_st["STATUS"][1] = "line two").
assert_true("core_new has no status rows drawn", crun["STATUS_ROWS"] = 0).

// 10c: alarm lights the PROG lamp, as 1406 does.
SET NEXT_OUT TO fake_out(1).
SET NEXT_OUT["ALARM"] TO 1406.
assert_true("ALARM > 0 lights the PROG flag", core_step(crun, fake_vehicle, nav, ks)["FLAGS"]["PROG"]).

// 11: ending twice calls END once.
core_end(crun, fake_vehicle).
LOCAL e1_b11 IS CALLS["E1"].
core_end(crun, fake_vehicle).
assert_true("core_end twice calls END once", CALLS["E1"] = e1_b11).

// 12: the LM vehicle (lm_vehicle.ks): its table has the shape the core reads, and with no saved plan the registers have no
// data and P63 refuses with the reason. Needs no flight; the no-plan checks are skipped when a plan.json exists.
LOCAL lmv IS lm_vehicle_new().
// Release 1.2: the saved plan's PROFILE ("A11" or "J"; none = A11) picks the programme set and the version.
LOCAL veh_j IS plan_profile_of(plan_read(PLAN_PLAN_FILE)) = "J".
assert_true("LM vehicle: version follows the plan profile",
            lmv["VERSION"] = (CHOOSE "LUMINARY210" IF veh_j ELSE "LUMINARY099") AND LM_VEH["PROFILE"] = (CHOOSE "J" IF veh_j ELSE "A11")).
assert_true("LM vehicle: only P63 is selectable by V37",
            lmv["PROGRAMMES"]["63"]["SELECTABLE"] AND NOT lmv["PROGRAMMES"]["64"]["SELECTABLE"] AND NOT lmv["PROGRAMMES"]["65"]["SELECTABLE"]
            AND NOT lmv["PROGRAMMES"]["66"]["SELECTABLE"]).
assert_true("LM vehicle: P63 hands over to P64, P64 to P65 (J: P66), P65 and P66 to nothing",
            lmv["PROGRAMMES"]["63"]["NEXT"] = 64 AND lmv["PROGRAMMES"]["64"]["NEXT"] = (CHOOSE 66 IF veh_j ELSE 65)
            AND lmv["PROGRAMMES"]["65"]["NEXT"] = -1 AND lmv["PROGRAMMES"]["66"]["NEXT"] = -1).
assert_true("LM vehicle: only P64 and P65 have a SAMPLE hook",
            lmv["PROGRAMMES"]["63"]["SAMPLE"]:ISTYPE("Boolean") AND NOT lmv["PROGRAMMES"]["64"]["SAMPLE"]:ISTYPE("Boolean") AND NOT lmv["PROGRAMMES"]["65"]["SAMPLE"]:ISTYPE("Boolean")).
assert_true("LM vehicle: CONTACT stays lit while PROG shows 68", lmv["IDLE_LAMPS"]:CALL("68")["CONTACT"] AND NOT lmv["IDLE_LAMPS"]:CALL("00")["CONTACT"]).
assert_true("LM vehicle: 68 is a sticky programme", lmv["STICKY_PROGS"]:CONTAINS(68)).
IF EXISTS(PLAN_PLAN_FILE) {
  report("SKIPPED LM vehicle no-plan checks: " + PLAN_PLAN_FILE + " exists").
} ELSE {
  LOCAL lm_nav_res IS lmv["NAV"]:CALL(FALSE).
  assert_true("LM vehicle: no plan gives no data (VALID FALSE)", NOT lm_nav_res["DERIVED"]["VALID"]).
  LOCAL lm_refusal IS lmv["PROGRAMMES"]["63"]["START"]:CALL(FALSE).
  assert_true("LM vehicle: P63 START with no plan refuses and says to run the planner first", lm_refusal["REFUSED"]:CONTAINS("run the planner first")).
}

test_end().
