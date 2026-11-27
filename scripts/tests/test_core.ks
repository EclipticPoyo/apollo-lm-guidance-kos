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

// 6: a START that refuses lights OPR ERR and returns the reason in WARN; nothing is running.
LOCAL refused IS core_request(crun, fake_vehicle, ks, 4).
assert_true("refused start sets OPRERR; a refusal is a warning", ks["OPRERR"] AND refused["WARN"]:CONTAINS("no plan, plan first") AND refused["MSG"] = "" AND NOT crun["PROG"]:ISTYPE("Lexicon")).
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

// 8: P3's NEXT is 99, which is not in the table: the programme ends cleanly with a warning.
core_request(crun, fake_vehicle, ks, 3).
SET NEXT_OUT TO fake_out(3).
SET NEXT_OUT["HANDOVER"] TO TRUE.
LOCAL res8 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("handover to NEXT 99 ends the programme and warns, no crash",
            NOT crun["PROG"]:ISTYPE("Lexicon") AND CALLS["E3"] = 1 AND res8["WARN"]:CONTAINS("Handover failed")).

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

// 9b: with an END_REQUEST, a programme that ends (PRO or V34) leaves a standing flashing request (Luminary GOTOPOOH: V37 N99) that a V37 selection answers.
SET fake_vehicle["END_REQUEST"] TO LEXICON("VERB", 37, "NOUN", 99).
core_request(crun, fake_vehicle, ks, 1).
SET NEXT_OUT TO fake_out(1).
SET NEXT_OUT["ENDED"] TO TRUE.
LOCAL res_e1 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("an ended programme leaves V37 N99 on the display, flashing", ks["VERB"] = 37 AND ks["NOUN"] = 99 AND res_e1["FLAGS"]["FLASH"] AND crun["IDLE_REQUEST"]:ISTYPE("Lexicon")).
LOCAL res_e2 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("and it stays flashing while idle", res_e2["FLAGS"]["FLASH"] AND ks["PENDING"]:ISTYPE("Lexicon") AND res_e2["PROG_TEXT"] = "00").
key_press(ks, "V").
LOCAL res_e3 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("keying over it lights KEY REL", res_e3["FLAGS"]["KEYREL"]).
key_press(ks, "K").
core_step(crun, fake_vehicle, nav, ks).
assert_true("KEY REL puts V37 N99 back", ks["VERB"] = 37 AND ks["NOUN"] = 99 AND NOT ks["KEYREL"]).
core_request(crun, fake_vehicle, ks, 0).
LOCAL res_e4 IS core_step(crun, fake_vehicle, nav, ks).
assert_true("a V37 selection clears the request", NOT crun["IDLE_REQUEST"]:ISTYPE("Lexicon") AND NOT res_e4["FLAGS"]["FLASH"]).
// Through the keys, as the pilot does it: V37 E 00 E and V37 E 03 E over the displayed V37 N99 (an earlier guard ignored V37 E when 37 was already shown).
LOCAL ks_v IS keys_new(fake_vehicle["NOUNS"], fake_vehicle["VERBS"], fake_vehicle["PROGS"]).
SET ks_v["VERB"] TO 37.
SET ks_v["NOUN"] TO 99.
FOR key_char IN LIST("V", "3", "7", "E", "0", "0", "E") { key_press(ks_v, key_char). }
assert_true("V37 E 00 E over V37 N99 asks for no programme", ks_v["PROG_REQ"] = 0 AND NOT ks_v["AWAIT_PROG"] AND NOT ks_v["OPRERR"]).
SET ks_v["PROG_REQ"] TO -1.
FOR key_char IN LIST("V", "3", "7", "E", "0", "3", "E") { key_press(ks_v, key_char). }
assert_true("V37 E 03 E over V37 N99 asks for programme 3", ks_v["PROG_REQ"] = 3 AND NOT ks_v["OPRERR"]).
SET ks_v["PROG_REQ"] TO -1.
FOR key_char IN LIST("E", "0", "0", "E") { key_press(ks_v, key_char). }
assert_true("ENTR alone over V37 N99 also waits for the programme number", ks_v["PROG_REQ"] = 0 AND NOT ks_v["OPRERR"]).
// KEY REL: keying V37 over the standing request lights it, the V37 ENTR and the programme digits leave it out; V or N keyed during the wait light it again.
SET ks_v["PENDING"] TO LEXICON("VERB", 37, "NOUN", 99).
SET ks_v["KEYREL"] TO FALSE.
key_press(ks_v, "V").
assert_true("keying V over the standing request lights KEY REL", ks_v["KEYREL"]).
FOR key_char IN LIST("3", "7", "E") { key_press(ks_v, key_char). }
assert_true("the V37 ENTR puts KEY REL out", NOT ks_v["KEYREL"] AND ks_v["AWAIT_PROG"]).
FOR key_char IN LIST("0", "0") { key_press(ks_v, key_char). }
assert_true("the programme digits do not light KEY REL again", NOT ks_v["KEYREL"]).
key_press(ks_v, "E").
assert_true("the programme number's ENTR does not light it either", NOT ks_v["KEYREL"]).
// A quiet standing request (the LM's V37 N99) never lights KEY REL, for V16 NXX or anything else; a normal one still does.
SET ks_v["PENDING"] TO LEXICON("VERB", 37, "NOUN", 99, "QUIET", TRUE).
SET ks_v["KEYREL"] TO FALSE.
SET ks_v["AWAIT_PROG"] TO FALSE.
FOR key_char IN LIST("V", "1", "6", "N", "6", "2", "E") { key_press(ks_v, key_char). }
assert_true("keying V16 N62 E over a quiet request does not light KEY REL", NOT ks_v["KEYREL"]).
SET ks_v["PENDING"] TO LEXICON("VERB", 6, "NOUN", 61).
key_press(ks_v, "V").
assert_true("keying over an ordinary request still lights KEY REL", ks_v["KEYREL"]).
fake_vehicle:REMOVE("END_REQUEST").

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
assert_true("a step with no WARN key gives an empty warning", res_st["WARN"] = "").
SET NEXT_OUT["WARN"] TO "check the stage".
SET NEXT_OUT["MSG"] TO "engine on".
LOCAL res_wn IS core_step(crun, fake_vehicle, nav, ks).
assert_true("the programme's WARN and MSG come back apart", res_wn["WARN"] = "check the stage" AND res_wn["MSG"] = "engine on").

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
// The vehicle restores the loads a DSKY run saved in LM_STORE_FILE, which would make "nothing loaded" false; the test points it at a file
// that does not exist while the vehicle is made, then puts the real path back.
LOCAL real_store_file IS LM_STORE_FILE.
SET LM_STORE_FILE TO "0:/lm/logs/test_core_no_store.txt".
IF EXISTS(LM_STORE_FILE) { DELETEPATH(LM_STORE_FILE). }
LOCAL lmv IS lm_vehicle_new().
SET LM_STORE_FILE TO real_store_file.
// The programme set and the version come from the saved plan's PROFILE, with no plan from the version saved with the PAD (profile.txt), else the
// default (lm_profile_for).
LOCAL veh_j IS lm_profile_for(plan_read(PLAN_PLAN_FILE)) = "J".
assert_true("LM vehicle: version follows the plan profile",
            lmv["VERSION"] = (CHOOSE "LUMINARY210" IF veh_j ELSE "LUMINARY099") AND LM_VEH["PROFILE"] = (CHOOSE "J" IF veh_j ELSE "A11")).
assert_true("LM vehicle: only P63 is selectable by V37",
            lmv["PROGRAMMES"]["63"]["SELECTABLE"] AND NOT lmv["PROGRAMMES"]["64"]["SELECTABLE"] AND NOT lmv["PROGRAMMES"]["65"]["SELECTABLE"]
            AND NOT lmv["PROGRAMMES"]["66"]["SELECTABLE"]).
assert_true("LM vehicle: P63 hands over to P64, P64 to P65 (J: P66), P65 and P66 to P68, P68 to nothing",
            lmv["PROGRAMMES"]["63"]["NEXT"] = 64 AND lmv["PROGRAMMES"]["64"]["NEXT"] = (CHOOSE 66 IF veh_j ELSE 65)
            AND lmv["PROGRAMMES"]["65"]["NEXT"] = 68 AND lmv["PROGRAMMES"]["66"]["NEXT"] = 68 AND lmv["PROGRAMMES"]["68"]["NEXT"] = -1).
assert_true("LM vehicle: P63, P64 and P65 have a SAMPLE hook (the ROD lever is read from P63 on)",
            NOT lmv["PROGRAMMES"]["63"]["SAMPLE"]:ISTYPE("Boolean") AND NOT lmv["PROGRAMMES"]["64"]["SAMPLE"]:ISTYPE("Boolean") AND NOT lmv["PROGRAMMES"]["65"]["SAMPLE"]:ISTYPE("Boolean")).
assert_true("LM vehicle: the ATT HOLD lamp key is in the lamp table", lmv["LAMPS"]["ATT_HOLD"] = "ATTHOLD").
assert_true("ATT HOLD lamp: lit when the attitude mode is HOLD", lm_att_lamp(LEXICON(), LEXICON("ATT", LEXICON("MODE", "HOLD")))["ATT_HOLD"]).
assert_true("ATT HOLD lamp: dark in AUTO", NOT lm_att_lamp(LEXICON(), LEXICON("ATT", LEXICON("MODE", "AUTO")))["ATT_HOLD"]).
assert_true("ATT HOLD lamp: dark when the programme has no attitude mode", NOT lm_att_lamp(LEXICON(), LEXICON())["ATT_HOLD"]).
assert_true("ATT HOLD lamp: keeps the step's other keys", lm_att_lamp(LEXICON("MSG", "x"), LEXICON())["MSG"] = "x").
FOR tc_abort IN LIST("70", "71") {
  LOCAL tc_entry IS lmv["PROGRAMMES"][tc_abort].
  assert_true("LM vehicle: P" + tc_abort + " is selectable and takes over", tc_entry["SELECTABLE"] AND tc_entry["TAKEOVER"] AND tc_entry["NEXT"] = -1).
}
assert_true("LM vehicle: P63 does not take over", NOT lmv["PROGRAMMES"]["63"]:HASKEY("TAKEOVER")).
assert_true("LM vehicle: V37 accepts 70 and 71", LM_PROGS:CONTAINS(70) AND LM_PROGS:CONTAINS(71)).
assert_true("LM vehicle: no CONTACT lamp idle before a landing", NOT lmv["IDLE_LAMPS"]:CALL("00")["CONTACT"]).
SET LM_VEH["LANDED_POS"] TO LEXICON("LAT", 0, "LNG", 0, "ALT", 0).
assert_true("LM vehicle: CONTACT stays lit after P68 (the landing position is kept)", lmv["IDLE_LAMPS"]:CALL("00")["CONTACT"]).
LM_VEH:REMOVE("LANDED_POS").
assert_true("LM vehicle: no sticky programme, and a flashing V37 N99 request after a programme ends", lmv["STICKY_PROGS"]:LENGTH = 0 AND lmv["END_REQUEST"]["VERB"] = 37 AND lmv["END_REQUEST"]["NOUN"] = 99).
IF EXISTS(PLAN_PLAN_FILE) {
  report("SKIPPED LM vehicle no-plan checks: " + PLAN_PLAN_FILE + " exists").
} ELSE {
  LOCAL lm_nav_res IS lmv["NAV"]:CALL(FALSE).
  assert_true("LM vehicle: no plan gives no data (VALID FALSE)", NOT lm_nav_res["DERIVED"]["VALID"]).
  LOCAL lm_refusal IS lmv["PROGRAMMES"]["63"]["START"]:CALL(FALSE).
  assert_true("LM vehicle: P63 START with nothing loaded refuses and says the site is not loaded", lm_refusal["REFUSED"]:CONTAINS("is not loaded")).
}

// ---- the close cross: quit_step (IDLE, ASK, QUIT) and V34 no longer ending the DSKY ----
assert_true("quit: the cross asks", quit_step("IDLE", TRUE, FALSE, FALSE) = "ASK").
assert_true("quit: YES with no question is ignored", quit_step("IDLE", FALSE, TRUE, FALSE) = "IDLE").
assert_true("quit: NO with no question is ignored", quit_step("IDLE", FALSE, FALSE, TRUE) = "IDLE").
assert_true("quit: YES ends", quit_step("ASK", FALSE, TRUE, FALSE) = "QUIT").
assert_true("quit: NO goes back", quit_step("ASK", FALSE, FALSE, TRUE) = "IDLE").
assert_true("quit: NO beats YES in the same cycle", quit_step("ASK", FALSE, TRUE, TRUE) = "IDLE").
assert_true("quit: the cross again changes nothing", quit_step("ASK", TRUE, FALSE, FALSE) = "ASK").
assert_true("quit: nothing pressed keeps asking", quit_step("ASK", FALSE, FALSE, FALSE) = "ASK").
assert_true("quit: QUIT is final", quit_step("QUIT", FALSE, FALSE, TRUE) = "QUIT").
LOCAL quit_keys IS keys_new(LIST(60), LIST(6, 16, 34, 37), LIST(0)).
assert_true("a fresh key state is not quitting", NOT quit_keys["QUIT"]).
FOR quit_char IN LIST("V", "3", "4", "E") { key_press(quit_keys, quit_char). }
assert_true("V34 E with nothing pending shows verb 34, no OPR ERR, and does not quit", quit_keys["VERB"] = 34 AND NOT quit_keys["OPRERR"] AND NOT quit_keys["QUIT"]).
FOR quit_char IN LIST("V", "3", "7", "E", "0", "0", "E") { key_press(quit_keys, quit_char). }
assert_true("V37 E 00 E after a V34 leaves a blank display, not V34 again", quit_keys["VERB"] = -1 AND quit_keys["NOUN"] = -1).

// V35, the lamp test (1.3.1): runs for KEYS_LAMPTEST_S, needs no noun, and leaves the verb and noun as they were. The display itself is checked in KSP.
LOCAL lt_keys IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
assert_true("lamp test: off at the start", NOT key_lamptest_on(lt_keys, TIME:SECONDS)).
LOCAL lt_verb IS lt_keys["VERB"].
LOCAL lt_noun IS lt_keys["NOUN"].
FOR lt_char IN LIST("V", "3", "5", "E") { key_press(lt_keys, lt_char). }
assert_true("V35 E needs no noun: no OPR ERR", NOT lt_keys["OPRERR"]).
assert_true("V35 E starts the lamp test", key_lamptest_on(lt_keys, TIME:SECONDS)).
assert_true("the test is still on just before the time is up", key_lamptest_on(lt_keys, TIME:SECONDS + KEYS_LAMPTEST_S - 0.5)).
assert_true("and off after it", NOT key_lamptest_on(lt_keys, TIME:SECONDS + KEYS_LAMPTEST_S + 0.5)).
assert_true("the verb and noun shown do not change", lt_keys["VERB"] = lt_verb AND lt_keys["NOUN"] = lt_noun).

// ---- messages under a status readout: word wrap (core_wrap) and the fixed message area (core_message) ----
LOCAL wr IS core_wrap("P65: STEERING TARGET DROPPED (CHANGE THE ATTITUDE MODE TO TAKE IT BACK).", 48).
assert_true("a long message wraps to lines of at most 48 characters", wr:LENGTH = 2 AND wr[0]:LENGTH <= 48 AND wr[1]:LENGTH <= 48).
assert_true("the wrapped lines join back to the message", wr[0] + " " + wr[1] = "P65: STEERING TARGET DROPPED (CHANGE THE ATTITUDE MODE TO TAKE IT BACK).").
assert_true("a short message stays one line", core_wrap("hello there", 48):LENGTH = 1).
assert_true("an empty message gives no lines", core_wrap("", 48):LENGTH = 0).
LOCAL wr_long IS core_wrap("ABCDEFGHIJ", 4).
assert_true("a word longer than a line is cut", wr_long:LENGTH = 3 AND wr_long[0] = "ABCD" AND wr_long[2] = "IJ").

// ---- the terminal's three areas: the live rows, the warnings block and the messages block ----
LOCAL tco_rows IS core_status_texts(LIST("a"), "u").
assert_true("the second slot's line takes the first free live row", tco_rows:LENGTH = CORE_STATUS_ROWS AND tco_rows[0] = "a" AND tco_rows[1] = "u" AND tco_rows[2] = "").
SET tco_rows TO core_status_texts(LIST("a", "b", "c"), "u").
assert_true("three foreground lines leave it out", tco_rows:LENGTH = 3 AND tco_rows[0] = "a" AND tco_rows[2] = "c").
assert_true("alone it takes the top row", core_status_texts(LIST(), "u")[0] = "u").
assert_true("lines over the live rows are cut", core_status_texts(LIST("a", "b", "c", "d"), ""):LENGTH = 3).

LOCAL tco_block IS LIST().
FROM { LOCAL i IS 0. } UNTIL i >= 10 STEP { SET i TO i + 1. } DO { core_block_add(tco_block, "message number " + i, 6, FALSE). }
LOCAL tco_lines IS core_block_lines(tco_block, 6).
assert_true("a full block drops its oldest line, the newest last", tco_lines:LENGTH = 6 AND tco_lines[0] = "message number 4" AND tco_lines[5] = "message number 9").
LOCAL tco_twice IS LIST().
assert_true("a warning is added", core_block_add(tco_twice, "stage alarm", 6, TRUE)).
assert_true("the same warning twice is one entry", NOT core_block_add(tco_twice, "stage alarm", 6, TRUE) AND tco_twice:LENGTH = 1).
assert_true("a message may repeat", core_block_add(tco_twice, "stage alarm", 6, FALSE) AND tco_twice:LENGTH = 2).
assert_true("an empty text adds nothing", NOT core_block_add(tco_twice, "", 6, FALSE) AND tco_twice:LENGTH = 2).
LOCAL tco_long IS "".
FROM { LOCAL i IS 0. } UNTIL i >= 8 STEP { SET i TO i + 1. } DO { SET tco_long TO tco_long + "word" + i + "_abcdefghijklmnopqrstuvwxyzabcdefgh ". }
LOCAL tco_over IS LIST("short").
core_block_add(tco_over, tco_long, 6, TRUE).
SET tco_lines TO core_block_lines(tco_over, 6).
assert_true("an over-long warning alone keeps its first lines, and the call returns", tco_over:LENGTH = 1 AND tco_lines:LENGTH = 6 AND tco_lines[0]:STARTSWITH("word0")).
assert_true("the message block: 8 rows at height 36", core_message_rows(36) = 8).
assert_true("the message block shrinks on a low terminal", core_message_rows(18) = 4 AND core_message_rows(10) = 1).

assert_true("a log line: clock, two spaces, the text", core_log_line("1:02:03", "engine on", FALSE) = "1:02:03  engine on").
assert_true("a warning is marked in the log", core_log_line("1:02:03", "no CSM", TRUE) = "1:02:03  WARNING: no CSM").
LOCAL tco_log IS "0:/lm/logs/test_core_dsky.log".
IF EXISTS(tco_log) { DELETEPATH(tco_log). }
SET fake_vehicle["LOG_FILE"] TO tco_log.
SET fake_vehicle["LOG_CLOCK"] TO { RETURN "0:00:05". }.
LOCAL tco_cl IS core_new(fake_vehicle).
core_message(tco_cl, "hello").
core_warning(tco_cl, "trouble").
core_warning(tco_cl, "trouble").
LOCAL tco_text IS OPEN(tco_log):READALL:STRING.
assert_true("messages and warnings are logged with the clock", tco_text:CONTAINS("0:00:05  hello") AND tco_text:CONTAINS("0:00:05  WARNING: trouble")).
assert_true("a repeated warning is logged once", tco_text:SPLIT("trouble"):LENGTH = 2).
fake_vehicle:REMOVE("LOG_FILE").
fake_vehicle:REMOVE("LOG_CLOCK").
assert_true("a vehicle with no log file logs nothing", core_new(fake_vehicle)["LOG"] = "").

LOCAL tco_cv IS core_new(fake_vehicle).
core_warning(tco_cv, "old").
core_request(tco_cv, fake_vehicle, ks, 77).
assert_true("a refused number leaves the warnings", tco_cv["WARNS"]:LENGTH = 1).
LOCAL tco_ref IS core_request(tco_cv, fake_vehicle, ks, 4).
core_warning(tco_cv, tco_ref["WARN"]).
assert_true("V37 clears old warnings and keeps the refusal's", tco_cv["WARNS"]:LENGTH = 1 AND tco_cv["WARNS"][0]:CONTAINS("no plan")).
core_message(tco_cv, "kept").
core_request(tco_cv, fake_vehicle, ks, 0).
assert_true("V37 00 clears the warnings and not the messages", tco_cv["WARNS"]:LENGTH = 0 AND tco_cv["MSGS"]:LENGTH = 1).
SET ks["OPRERR"] TO FALSE.

LOCAL tco_kr IS keys_new(LIST(60), LIST(6, 16, 34, 37), LIST(0)).
assert_true("a fresh key state has no RSET", NOT tco_kr["RSET"]).
key_press(tco_kr, "R").
assert_true("R sets ks RSET", tco_kr["RSET"]).

CORE_OUTBOX:CLEAR().
LOCAL tco_cd IS core_new(fake_vehicle).
core_say("said").
core_warn("warned").
core_drain(tco_cd).
assert_true("core_say and core_warn reach their blocks", tco_cd["MSGS"]:LENGTH = 1 AND tco_cd["MSGS"][0] = "said" AND tco_cd["WARNS"]:LENGTH = 1 AND tco_cd["WARNS"][0] = "warned").
assert_true("the queue is empty afterwards", CORE_OUTBOX:LENGTH = 0).
SET tco_cd["LOG"] TO tco_log.
core_note("for the log only").
core_drain(tco_cd).
assert_true("core_note goes to the log and to neither block", tco_cd["MSGS"]:LENGTH = 1 AND tco_cd["WARNS"]:LENGTH = 1 AND OPEN(tco_log):READALL:STRING:CONTAINS("for the log only")).
LOCAL tco_av IS LEXICON("ALARM_SOURCE", { PARAMETER prog, now_ut. RETURN LIST(1202). }).
core_scripted_alarms(ks, tco_av, FALSE, 0).
assert_true("a scripted alarm is a warning", CORE_OUTBOX:LENGTH = 1 AND CORE_OUTBOX[0]["WARN"] AND CORE_OUTBOX[0]["TEXT"] = "ALARM 01202.").
CORE_OUTBOX:CLEAR().

// ---- 1.5: a programme that takes over the running one (TAKEOVER), and a vehicle that asks for a programme ----
// P5 takes over: its START gets the running programme (FALSE when idle) and refuses with TCO_REFUSE when that is not "".
GLOBAL TCO_REFUSE IS "".
GLOBAL TCO_PREV IS 0.
GLOBAL TCO_ASK IS -1.
CALLS:ADD("S5", 0).
CALLS:ADD("E5", 0).
fake_vehicle["PROGRAMMES"]:ADD("5", LEXICON(
  "START", { PARAMETER prev.
             SET CALLS["S5"] TO CALLS["S5"] + 1.
             SET TCO_PREV TO prev.
             RETURN LEXICON("PROG_NO", 5, "REFUSED", TCO_REFUSE). },
  "STEP", { PARAMETER prog, nav, ks. RETURN NEXT_OUT. },
  "END", { PARAMETER prog. SET CALLS["E5"] TO CALLS["E5"] + 1. },
  "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE, "TAKEOVER", TRUE)).
SET fake_vehicle["PROGS"] TO LIST(0, 1, 3, 4, 5).
fake_vehicle["NOUNS"]:ADD(33).
fake_vehicle["VERBS"]:ADD(21).
SET fake_vehicle["LOADS"] TO LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))).
SET fake_vehicle["LOAD_COMMIT"] TO { PARAMETER noun_no, comps, values. RETURN "". }.

// tco_keys: a key state with the vehicle (so the keyed loaders work) and a V21 N33 load under way.
FUNCTION tco_keys {
  PARAMETER vehicle.
  LOCAL kt IS keys_new(vehicle["NOUNS"], vehicle["VERBS"], vehicle["PROGS"]).
  SET kt["VEHICLE"] TO vehicle.
  FOR tco_char IN LIST("V", "2", "1", "N", "3", "3", "E") { key_press(kt, tco_char). }
  RETURN kt.
}

LOCAL crun_t IS core_new(fake_vehicle).
LOCAL ks_t IS tco_keys(fake_vehicle).
assert_true("take-over set-up: a load is under way", load_active(ks_t)).
core_request(crun_t, fake_vehicle, ks_t, 1).
LOCAL tco_e1 IS CALLS["E1"].
SET ks_t TO tco_keys(fake_vehicle).
SET TCO_REFUSE TO "no engine".
core_warning(crun_t, "old").
LOCAL tco_res IS core_request(crun_t, fake_vehicle, ks_t, 5).
assert_true("take-over refused: the running programme carries on, not ended", crun_t["PROG"]["PROG_NO"] = 1 AND CALLS["E1"] = tco_e1).
assert_true("take-over refused: OPR ERR and the reason as a warning", ks_t["OPRERR"] AND tco_res["WARN"]:CONTAINS("no engine")).
assert_true("take-over refused: the old warnings stay", crun_t["WARNS"]:LENGTH = 1).
assert_true("take-over refused: the load and the display are left alone", load_active(ks_t) AND ks_t["VERB"] = 21 AND ks_t["NOUN"] = 33).
SET TCO_REFUSE TO "".
SET ks_t TO tco_keys(fake_vehicle).
SET ks_t["PENDING"] TO LEXICON("VERB", 6, "NOUN", 60).
SET ks_t["EXT"] TO LEXICON("VERB", 16, "NOUN", 60, "STEP", FALSE).
SET ks_t["PRO"] TO TRUE.
SET ks_t["ENTER"] TO TRUE.
core_request(crun_t, fake_vehicle, ks_t, 5).
assert_true("take-over: START gets the running programme, which is not ended", CALLS["E1"] = tco_e1 AND TCO_PREV:ISTYPE("Lexicon") AND TCO_PREV["PROG_NO"] = 1 AND crun_t["PROG"]["PROG_NO"] = 5).
assert_true("take-over: the load, the request and the extended display are gone", NOT load_active(ks_t) AND NOT ks_t["PENDING"]:ISTYPE("Lexicon") AND NOT ks_t["EXT"]:ISTYPE("Lexicon")).
assert_true("take-over: no answer left over for the new programme", NOT ks_t["PRO"] AND NOT ks_t["ENTER"] AND NOT ks_t["OPRERR"]).
assert_true("take-over: the old warnings are cleared", crun_t["WARNS"]:LENGTH = 0).
core_end(crun_t, fake_vehicle).
core_request(crun_t, fake_vehicle, ks_t, 5).
assert_true("take-over with nothing running: START gets FALSE", TCO_PREV:ISTYPE("Boolean") AND crun_t["PROG"]["PROG_NO"] = 5).
core_end(crun_t, fake_vehicle).

core_request(crun_t, fake_vehicle, ks_t, 1).
LOCAL tco_s5 IS CALLS["S5"].
LOCAL tco_none IS core_vehicle_request(crun_t, fake_vehicle, ks_t, 100).
assert_true("a vehicle with no request source asks for nothing", tco_none["MSG"] = "" AND tco_none["WARN"] = "" AND CALLS["S5"] = tco_s5).
SET fake_vehicle["REQUEST_SOURCE"] TO { PARAMETER prog, now_ut. RETURN TCO_ASK. }.
core_vehicle_request(crun_t, fake_vehicle, ks_t, 100).
assert_true("request source -1: nothing changes", CALLS["S5"] = tco_s5 AND crun_t["PROG"]["PROG_NO"] = 1).
SET TCO_ASK TO 5.
core_vehicle_request(crun_t, fake_vehicle, ks_t, 100).
assert_true("request source 5: P5 takes over", CALLS["S5"] = tco_s5 + 1 AND crun_t["PROG"]["PROG_NO"] = 5).
core_end(crun_t, fake_vehicle).
fake_vehicle:REMOVE("REQUEST_SOURCE").

test_end().
