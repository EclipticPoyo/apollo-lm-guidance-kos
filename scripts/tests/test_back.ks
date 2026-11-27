// test_back.ks -- pad test for the DSKY core's second programme slot and its priority displays (no ship access).
//   RUNPATH("0:/tests/test_back.ks").   Log: 0:/lm/logs/test_back.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").

test_begin("0:/lm/logs/test_back.log").

GLOBAL TBK_TRACE IS LIST().          // "start1", "end3", "hook2" in the order they happened
GLOBAL TBK_NEXT IS LEXICON().         // programme number as text -> what its next STEP returns
GLOBAL TBK_SEEN IS LEXICON().        // programme number as text -> the answers its last STEP saw
GLOBAL TBK_REFUSE IS LEXICON().      // programme number as text -> a refusal text for its START
GLOBAL TBK_LEAVE_PRO IS FALSE.       // TRUE: no STEP consumes PRO (a programme that reads it only later)
GLOBAL TBK_LOADED IS LIST().         // the values of the last load committed
GLOBAL TBK_EXT_OUT IS LEXICON().     // what the answering display's next STEP returns
GLOBAL TBK_EXT_ANS IS LEXICON().     // the answers its last STEP got
GLOBAL TBK_EXT_ENDS IS 0.            // how often an extended display's END ran

// tbk_out: a quiet programme output for programme number, with an optional request (FALSE for none).
FUNCTION tbk_out {
  PARAMETER number, request IS FALSE.
  RETURN LEXICON("SET_VERB", -1, "SET_NOUN", -1, "EXTRA", LEXICON(), "MSG", "", "KEY_REL", FALSE, "ALT_LAMP", FALSE,
                 "VEL_LAMP", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE, "ENDED", FALSE, "HANDOVER", FALSE,
                 "PROG_NO", number, "REQUEST", request).
}
// tbk_shows: an output that sets verb and noun, as a request too when asked.
FUNCTION tbk_shows {
  PARAMETER number, verb_no, noun_no, asks IS FALSE.
  LOCAL out IS tbk_out(number).
  SET out["SET_VERB"] TO verb_no.
  SET out["SET_NOUN"] TO noun_no.
  IF asks { SET out["REQUEST"] TO LEXICON("VERB", verb_no, "NOUN", noun_no). }
  RETURN out.
}
// tbk_ask: an output with a request only.
FUNCTION tbk_ask {
  PARAMETER number, verb_no, noun_no.
  RETURN tbk_out(number, LEXICON("VERB", verb_no, "NOUN", noun_no)).
}
FUNCTION tbk_start {
  PARAMETER number, prev.
  LOCAL why IS "".
  IF TBK_REFUSE:HASKEY("" + number) { SET why TO TBK_REFUSE["" + number]. }
  IF why = "" { TBK_TRACE:ADD("start" + number). }
  RETURN LEXICON("PROG_NO", number, "REFUSED", why).
}
FUNCTION tbk_step {
  PARAMETER number, prog, nav, ks.
  SET TBK_SEEN["" + number] TO LEXICON("PRO", ks["PRO"], "RECYCLE", ks["RECYCLE"], "TERMINATE", ks["TERMINATE"], "ENTER", ks["ENTER"]).
  IF NOT TBK_LEAVE_PRO { SET ks["PRO"] TO FALSE. }
  RETURN TBK_NEXT["" + number].
}
FUNCTION tbk_end {
  PARAMETER number, prog.
  TBK_TRACE:ADD("end" + number).
}
FUNCTION tbk_entry {
  PARAMETER number, background.
  LOCAL entry IS LEXICON("START", tbk_start@:BIND(number), "STEP", tbk_step@:BIND(number), "END", tbk_end@:BIND(number),
                         "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE).
  IF background { SET entry["BACKGROUND"] TO TRUE. }
  RETURN entry.
}

LOCAL tbk_takeover IS tbk_entry(4, FALSE).
SET tbk_takeover["TAKEOVER"] TO TRUE.
GLOBAL TBK_VEHICLE IS LEXICON(
  "NOUNS", LIST(12, 18, 44, 60, 61, 62, 81), "VERBS", LIST(6, 16, 21, 22, 24, 25, 32, 33, 34, 37, 50), "PROGS", LIST(0, 1, 2, 3, 4),
  "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL"),
  "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON(). },
  "STICKY_PROGS", LIST(),
  "END_REQUEST", LEXICON("VERB", 37, "NOUN", 99, "QUIET", TRUE),
  "V37_HOOK", { PARAMETER number. TBK_TRACE:ADD("hook" + number). },
  "LOADS", LEXICON("81", LEXICON("NCOMP", 1, "DIGITS", LIST(5)), "12", LEXICON("NCOMP", 2, "DIGITS", LIST(5, 5), "OCTAL", TRUE)),
  "LOAD_COMMIT", { PARAMETER noun_no, comps, values. SET TBK_LOADED TO values. RETURN "". },
  "PROGRAMMES", LEXICON("1", tbk_entry(1, FALSE), "2", tbk_entry(2, TRUE), "3", tbk_entry(3, TRUE), "4", tbk_takeover)).
GLOBAL TBK_NAV IS LEXICON("OK", TRUE, "STATE", LEXICON(), "DERIVED", LEXICON("VALID", FALSE)).

GLOBAL TBK_KS IS 0.
GLOBAL TBK_RUN IS 0.

// tbk_fresh: a new key state and run state, quiet outputs, nothing running.
FUNCTION tbk_fresh {
  SET TBK_KS TO keys_new(TBK_VEHICLE["NOUNS"], TBK_VEHICLE["VERBS"], TBK_VEHICLE["PROGS"]).
  SET TBK_KS["VEHICLE"] TO TBK_VEHICLE.
  SET TBK_RUN TO core_new(TBK_VEHICLE).
  SET TBK_REFUSE TO LEXICON().
  SET TBK_LEAVE_PRO TO FALSE.
  SET TBK_LOADED TO LIST().
  FOR number IN LIST(1, 2, 3, 4) {
    SET TBK_NEXT["" + number] TO tbk_out(number).
    SET TBK_SEEN["" + number] TO LEXICON("PRO", FALSE, "RECYCLE", FALSE, "TERMINATE", FALSE, "ENTER", FALSE).
  }
  TBK_TRACE:CLEAR().
}
FUNCTION tbk_type {
  PARAMETER text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(TBK_KS, text:SUBSTRING(i, 1)). }
}
FUNCTION tbk_cycle {
  RETURN core_step(TBK_RUN, TBK_VEHICLE, TBK_NAV, TBK_KS).
}
FUNCTION tbk_v37 {
  PARAMETER number.
  RETURN core_request(TBK_RUN, TBK_VEHICLE, TBK_KS, number).
}
FUNCTION tbk_vn {
  PARAMETER verb_no, noun_no.
  RETURN TBK_KS["VERB"] = verb_no AND TBK_KS["NOUN"] = noun_no.
}
FUNCTION tbk_traced {
  LOCAL text IS "".
  FOR item IN TBK_TRACE { SET text TO (CHOOSE item IF text = "" ELSE text + " " + item). }
  RETURN text.
}
// tbk_pair: programme 1 showing V06 N61 as a request in the foreground, programme 3 quiet in the background, one cycle run.
FUNCTION tbk_pair {
  tbk_fresh().
  tbk_v37(1).
  tbk_v37(3).
  tbk_v37(1).
  SET TBK_NEXT["1"] TO tbk_shows(1, 6, 61, TRUE).
  tbk_cycle().
  SET TBK_NEXT["1"] TO tbk_out(1, LEXICON("VERB", 6, "NOUN", 61)).
  TBK_TRACE:CLEAR().
}

// ---- Selecting ----
tbk_fresh().
tbk_v37(1).
TBK_TRACE:CLEAR().
tbk_v37(3).
assert_true("V37 3 over 1 ends 1 and starts 3", tbk_traced() = "end1 hook3 start3").
assert_true("the hook runs after END and before START", tbk_traced():FIND("end1") < tbk_traced():FIND("hook3") AND tbk_traced():FIND("hook3") < tbk_traced():FIND("start3")).
assert_true("3 is in the second slot and the foreground is empty", TBK_RUN["BACK"]:ISTYPE("Lexicon") AND NOT TBK_RUN["PROG"]:ISTYPE("Lexicon")).
TBK_TRACE:CLEAR().
tbk_v37(1).
assert_true("V37 1 keeps 3 running", tbk_traced() = "hook1 start1" AND TBK_RUN["BACK"]:ISTYPE("Lexicon") AND TBK_RUN["PROG"]:ISTYPE("Lexicon")).
TBK_TRACE:CLEAR().
tbk_v37(3).
assert_true("V37 3 again does not START", tbk_traced() = "end1 hook3" AND TBK_RUN["BACK"]:ISTYPE("Lexicon")).
TBK_TRACE:CLEAR().
tbk_v37(2).
assert_true("V37 2 replaces 3", tbk_traced() = "end3 hook2 start2" AND TBK_RUN["BACK"]["PROG_NO"] = 2).
tbk_v37(1).
TBK_TRACE:CLEAR().
tbk_v37(0).
assert_true("V37 0 ends both", tbk_traced() = "end1 end2 hook0" AND NOT TBK_RUN["BACK"]:ISTYPE("Lexicon") AND NOT TBK_RUN["PROG"]:ISTYPE("Lexicon")).
tbk_v37(0).
assert_true("a second V37 0 ends nothing twice", tbk_traced() = "end1 end2 hook0 hook0").
TBK_TRACE:CLEAR().
tbk_v37(9).
assert_true("a refused number calls no hook", TBK_TRACE:LENGTH = 0 AND TBK_KS["OPRERR"]).
tbk_fresh().
SET TBK_REFUSE["3"] TO "no CSM".
LOCAL tbk_res IS tbk_v37(3).
assert_true("a second-slot START that refuses leaves the slot empty", NOT TBK_RUN["BACK"]:ISTYPE("Lexicon") AND TBK_KS["OPRERR"] AND tbk_res["WARN"]:CONTAINS("no CSM")).

// ---- A priority display over the foreground ----
tbk_pair().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
LOCAL tbk_cyc IS tbk_cycle().
assert_true("a request takes the DSKY from a flashing foreground request", tbk_vn(50, 18) AND tbk_cyc["FLAGS"]["FLASH"] AND TBK_KS["PENDING"]["VERB"] = 50).
assert_true("PROG shows the foreground programme", tbk_cyc["PROG_TEXT"] = "1").
SET TBK_NEXT["1"] TO tbk_shows(1, 6, 62, TRUE).
SET TBK_NEXT["1"]["BLANK"] TO TRUE.
SET tbk_cyc TO tbk_cycle().
assert_true("the foreground cannot overwrite it", tbk_vn(50, 18) AND TBK_KS["PENDING"]["NOUN"] = 18 AND NOT tbk_cyc["FLAGS"]["BLANK"]).
assert_true("the foreground's display is kept for later", TBK_KS["PROG_VN"][0] = 6 AND TBK_KS["PROG_VN"][1] = 62).
SET TBK_NEXT["1"] TO tbk_out(1, LEXICON("VERB", 6, "NOUN", 62)).
tbk_type("P").
tbk_cycle().
assert_true("PRO goes to the second slot only", TBK_SEEN["3"]["PRO"] AND NOT TBK_SEEN["1"]["PRO"] AND NOT TBK_KS["PRO"]).
tbk_type("V32E").
tbk_cycle().
assert_true("V32 goes to the second slot only", TBK_SEEN["3"]["RECYCLE"] AND NOT TBK_SEEN["1"]["RECYCLE"]).
tbk_type("V34E").
tbk_cycle().
assert_true("V34 goes to the second slot only", TBK_SEEN["3"]["TERMINATE"] AND NOT TBK_SEEN["1"]["TERMINATE"]).
tbk_type("E").
tbk_cycle().
assert_true("ENTR goes to the second slot only", TBK_SEEN["3"]["ENTER"] AND NOT TBK_SEEN["1"]["ENTER"]).
SET TBK_NEXT["3"] TO tbk_ask(3, 6, 18).
SET tbk_cyc TO tbk_cycle().
assert_true("a changed request changes the verb and noun", tbk_vn(6, 18) AND TBK_KS["PENDING"]["VERB"] = 6 AND tbk_cyc["FLAGS"]["FLASH"]).
SET TBK_NEXT["3"] TO tbk_out(3).
SET tbk_cyc TO tbk_cycle().
assert_true("the display and the foreground request come back", tbk_vn(6, 62) AND TBK_KS["PENDING"]["NOUN"] = 62 AND tbk_cyc["FLAGS"]["FLASH"] AND NOT TBK_KS["PRIO"]:ISTYPE("Lexicon")).
tbk_type("P").
tbk_cycle().
assert_true("with no priority display PRO is the foreground's", TBK_SEEN["1"]["PRO"] AND NOT TBK_SEEN["3"]["PRO"]).

// ---- Held back while the pilot has the DSKY ----
tbk_fresh().
tbk_v37(3).
tbk_v37(1).
SET TBK_NEXT["1"] TO tbk_shows(1, 16, 60).
tbk_cycle().
SET TBK_NEXT["1"] TO tbk_out(1).
tbk_type("V21N81E+000").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
SET tbk_cyc TO tbk_cycle().
assert_true("held while a load is active, KEY REL lit", NOT TBK_KS["PRIO"]:ISTYPE("Lexicon") AND tbk_vn(21, 81) AND tbk_cyc["FLAGS"]["KEYREL"]).
tbk_type("12E").
SET tbk_cyc TO tbk_cycle().
assert_true("the load values are committed untouched", TBK_LOADED:LENGTH = 1 AND TBK_LOADED[0] = 12).
assert_true("still held over the pilot's display", tbk_vn(16, 81) AND tbk_cyc["FLAGS"]["KEYREL"]).
tbk_type("K").
SET tbk_cyc TO tbk_cycle().
assert_true("KEY REL lets it in", tbk_vn(50, 18) AND tbk_cyc["FLAGS"]["FLASH"] AND NOT tbk_cyc["FLAGS"]["KEYREL"]).
tbk_type("V16N61E").
SET tbk_cyc TO tbk_cycle().
assert_true("keying over a priority display lights KEY REL", tbk_vn(16, 61) AND tbk_cyc["FLAGS"]["KEYREL"] AND NOT tbk_cyc["FLAGS"]["FLASH"]).
SET TBK_NEXT["3"] TO tbk_out(3).
SET tbk_cyc TO tbk_cycle().
assert_true("a priority display that ends leaves the pilot's display", tbk_vn(16, 61) AND NOT TBK_KS["PRIO"]:ISTYPE("Lexicon")).

tbk_pair().
tbk_type("V16N60E").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
SET tbk_cyc TO tbk_cycle().
assert_true("held while the pilot covers a foreground request", tbk_vn(16, 60) AND tbk_cyc["FLAGS"]["KEYREL"]).
tbk_type("K").
tbk_cycle().
assert_true("and in after KEY REL", tbk_vn(50, 18)).

// ---- Over an extended-verb display ----
tbk_fresh().
tbk_v37(3).
SET TBK_KS["EXT"] TO LEXICON("VERB", 16, "NOUN", 44, "STEP", { PARAMETER nav_in. RETURN LEXICON(). }).
tbk_cycle().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
assert_true("a priority display goes over an extended display", tbk_vn(50, 18)).
tbk_type("P").
tbk_cycle().
assert_true("the extended display does not see its answer", TBK_KS["EXT"]:ISTYPE("Lexicon") AND TBK_SEEN["3"]["PRO"]).
SET TBK_NEXT["3"] TO tbk_out(3).
SET tbk_cyc TO tbk_cycle().
assert_true("and gives it back", tbk_vn(16, 44) AND TBK_KS["PENDING"]["NOUN"] = 44 AND tbk_cyc["FLAGS"]["FLASH"]).

// ---- The second slot alone ----
tbk_fresh().
tbk_v37(3).
SET tbk_cyc TO tbk_cycle().
assert_true("PROG shows 3 with no foreground", tbk_cyc["PROG_TEXT"] = "3").
SET TBK_NEXT["3"] TO tbk_shows(3, 6, 18).
tbk_cycle().
SET TBK_NEXT["3"] TO tbk_out(3).
assert_true("its verb and noun show when it runs alone", tbk_vn(6, 18) AND TBK_KS["PROG_VN"][1] = 18).
tbk_v37(1).
SET TBK_NEXT["3"] TO tbk_shows(3, 6, 61).
SET TBK_NEXT["1"] TO tbk_shows(1, 16, 60).
tbk_cycle().
assert_true("its verb and noun are ignored under a foreground", tbk_vn(16, 60) AND TBK_KS["PROG_VN"][1] = 60).

// ---- Alarms, messages and values ----
tbk_pair().
SET TBK_NEXT["3"]["ALARM"] TO 526.
SET TBK_NEXT["3"]["MSG"] TO "three".
SET TBK_NEXT["3"]["STATUS"] TO LIST("not shown").
SET TBK_NEXT["3"]["EXTRA"] TO LEXICON("BOTH", 3, "BACKONLY", 3).
SET TBK_NEXT["1"]["EXTRA"] TO LEXICON("BOTH", 1).
SET TBK_NEXT["1"]["MSG"] TO "one".
SET tbk_cyc TO tbk_cycle().
assert_true("both messages arrive", tbk_cyc["MSG"] = "one three").
SET TBK_NEXT["1"]["WARN"] TO "first warning".
SET TBK_NEXT["3"]["WARN"] TO "third warning".
assert_true("both slots' warnings arrive", tbk_cycle()["WARN"] = "first warning third warning").
assert_true("the second slot's status line comes apart from the foreground's", tbk_cyc["STATUS"]:LENGTH = 0 AND tbk_cyc["UNDER"] = "not shown").
assert_true("the foreground's value wins", TBK_NAV["DERIVED"]["BOTH"] = 1 AND TBK_NAV["DERIVED"]["BACKONLY"] = 3).
assert_true("its alarm is raised", TBK_KS["ALARM"]["CODES"][0] = 526).
tbk_cycle().
assert_true("and only once", TBK_KS["ALARM"]["CODES"][1] = 0).

// ---- Ending ----
tbk_pair().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
SET TBK_KS["END_BACK"] TO TRUE.
SET tbk_cyc TO tbk_cycle().
assert_true("END_BACK ends the second slot, the foreground goes on", tbk_traced() = "end3" AND TBK_RUN["PROG"]:ISTYPE("Lexicon")).
assert_true("and gives the display back", tbk_vn(6, 61) AND TBK_KS["PENDING"]["NOUN"] = 61 AND tbk_cyc["FLAGS"]["FLASH"] AND NOT TBK_KS["END_BACK"]).
tbk_fresh().
tbk_v37(3).
tbk_cycle().
SET TBK_KS["END_BACK"] TO TRUE.
SET tbk_cyc TO tbk_cycle().
assert_true("END_BACK with no foreground posts V37 N99", tbk_vn(37, 99) AND tbk_cyc["FLAGS"]["FLASH"] AND tbk_cyc["PROG_TEXT"] = "00").
tbk_fresh().
SET TBK_KS["END_BACK"] TO TRUE.
tbk_cycle().
assert_true("END_BACK with nothing in the slot does nothing", TBK_TRACE:LENGTH = 0 AND NOT TBK_KS["END_BACK"] AND NOT tbk_vn(37, 99)).
tbk_fresh().
tbk_v37(3).
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
SET TBK_NEXT["3"] TO tbk_out(3).
SET TBK_NEXT["3"]["ENDED"] TO TRUE.
SET tbk_cyc TO tbk_cycle().
assert_true("a second-slot ENDED ends it once and posts V37 N99", tbk_traced() = "hook3 start3 end3" AND tbk_vn(37, 99) AND tbk_cyc["FLAGS"]["FLASH"]).
assert_true("the priority display went with it", NOT TBK_KS["PRIO"]:ISTYPE("Lexicon")).
tbk_pair().
SET TBK_NEXT["1"] TO tbk_out(1).
SET TBK_NEXT["1"]["ENDED"] TO TRUE.
tbk_cycle().
assert_true("a foreground that ends leaves the second slot", tbk_traced() = "end1" AND TBK_RUN["BACK"]:ISTYPE("Lexicon") AND tbk_vn(37, 99)).
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
assert_true("which can still ask", tbk_vn(50, 18)).
SET TBK_NEXT["3"] TO tbk_out(3).
tbk_cycle().
assert_true("and V37 N99 comes back after it", tbk_vn(37, 99) AND TBK_KS["PENDING"]["NOUN"] = 99).
tbk_type("V16N60E").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
SET tbk_cyc TO tbk_cycle().
assert_true("held while the pilot covers V37 N99", tbk_vn(16, 60) AND tbk_cyc["FLAGS"]["KEYREL"]).

// ---- V37 and a takeover under a priority display ----
tbk_pair().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
tbk_v37(4).
assert_true("a takeover drops the priority display and calls the hook after START", tbk_traced() = "start4 hook4" AND NOT TBK_KS["PRIO"]:ISTYPE("Lexicon") AND tbk_vn(6, 61)).
assert_true("and keeps the second slot", TBK_RUN["BACK"]:ISTYPE("Lexicon")).
tbk_pair().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
tbk_v37(1).
assert_true("V37 drops the priority display", NOT TBK_KS["PRIO"]:ISTYPE("Lexicon") AND tbk_vn(6, 61)).

// ---- An extended display that takes the answers ----
FUNCTION tbk_ext_result {
  PARAMETER verb_no, noun_no, flashing, ended.
  RETURN LEXICON("DERIVED", LEXICON("TBKEXT", noun_no), "VERB", verb_no, "NOUN", noun_no, "FLASH", flashing, "ENDED", ended, "MSG", "").
}
FUNCTION tbk_ext_step {
  PARAMETER nav_in, ans.
  SET TBK_EXT_ANS TO ans.
  RETURN TBK_EXT_OUT.
}
FUNCTION tbk_ext_end {
  SET TBK_EXT_ENDS TO TBK_EXT_ENDS + 1.
}
// tbk_answering: programme 1 showing V06 N61 as a request, then an answering display V06 N44 asked for by a verb's ENTR, one cycle run.
FUNCTION tbk_answering {
  tbk_pair().
  SET TBK_EXT_ENDS TO 0.
  SET TBK_EXT_OUT TO tbk_ext_result(6, 44, TRUE, FALSE).
  SET TBK_KS["EXT"] TO LEXICON("VERB", 6, "NOUN", 44, "ANSWERS", TRUE, "STEP", tbk_ext_step@, "END", tbk_ext_end@).
  SET TBK_KS["ENTER"] TO TRUE.
  RETURN tbk_cycle().
}

SET tbk_cyc TO tbk_answering().
assert_true("the ENTR that started it is no answer", NOT TBK_EXT_ANS["ENTER"] AND tbk_vn(6, 44) AND tbk_cyc["FLAGS"]["FLASH"]).
SET TBK_EXT_OUT["WARN"] TO "ext warning".
assert_true("an answering display's warning arrives", tbk_cycle()["WARN"]:CONTAINS("ext warning")).
TBK_EXT_OUT:REMOVE("WARN").
assert_true("its values reach the display", TBK_NAV["DERIVED"]["TBKEXT"] = 44).
tbk_type("P").
tbk_cycle().
assert_true("an answering display gets PRO and stays up", TBK_EXT_ANS["PRO"] AND TBK_KS["EXT"]:ISTYPE("Lexicon")).
assert_true("the programme does not see that PRO", NOT TBK_SEEN["1"]["PRO"]).
tbk_type("V32E").
tbk_cycle().
assert_true("it gets V32", TBK_EXT_ANS["V32"] AND NOT TBK_EXT_ANS["PRO"]).
tbk_type("V34E").
tbk_cycle().
assert_true("it gets V34 and stays up", TBK_EXT_ANS["TERM"] AND TBK_KS["EXT"]:ISTYPE("Lexicon") AND NOT TBK_SEEN["1"]["TERMINATE"]).
tbk_type("E").
tbk_cycle().
assert_true("it gets ENTR", TBK_EXT_ANS["ENTER"] AND NOT TBK_SEEN["1"]["ENTER"]).
tbk_type("K").
SET TBK_EXT_OUT TO tbk_ext_result(6, 18, FALSE, FALSE).
SET tbk_cyc TO tbk_cycle().
assert_true("a changed verb and noun show, static when it says so", tbk_vn(6, 18) AND TBK_KS["PENDING"]["NOUN"] = 18 AND NOT tbk_cyc["FLAGS"]["FLASH"]).
SET TBK_EXT_OUT TO tbk_ext_result(6, 18, FALSE, TRUE).
SET tbk_cyc TO tbk_cycle().
assert_true("ENDED closes it and restores the request", NOT TBK_KS["EXT"]:ISTYPE("Lexicon") AND tbk_vn(6, 61) AND tbk_cyc["FLAGS"]["FLASH"]).
assert_true("END runs once on ENDED", TBK_EXT_ENDS = 1).
tbk_cycle().
assert_true("and not again", TBK_EXT_ENDS = 1).

tbk_answering().
tbk_type("V16N60E").
SET TBK_EXT_OUT TO tbk_ext_result(6, 44, TRUE, TRUE).
tbk_cycle().
assert_true("a display the pilot keyed over it stays when it ends", tbk_vn(16, 60) AND NOT TBK_KS["EXT"]:ISTYPE("Lexicon")).

tbk_answering().
tbk_v37(1).
tbk_cycle().
assert_true("END once on V37", TBK_EXT_ENDS = 1 AND NOT TBK_KS["EXT"]:ISTYPE("Lexicon")).

tbk_answering().
core_shutdown(TBK_RUN, TBK_VEHICLE, TBK_KS).
core_shutdown(TBK_RUN, TBK_VEHICLE, TBK_KS).
assert_true("END once on the quit path", TBK_EXT_ENDS = 1 AND NOT TBK_RUN["PROG"]:ISTYPE("Lexicon")).

tbk_answering().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
tbk_type("P").
tbk_cycle().
assert_true("under a priority display it gets no answers and keeps running", NOT TBK_EXT_ANS["PRO"] AND TBK_SEEN["3"]["PRO"] AND TBK_KS["EXT"]:ISTYPE("Lexicon") AND tbk_vn(50, 18)).
SET TBK_EXT_OUT TO tbk_ext_result(6, 44, TRUE, TRUE).
tbk_cycle().
SET TBK_NEXT["3"] TO tbk_out(3).
tbk_cycle().
assert_true("one that ends under a priority display leaves the programme's display after it", tbk_vn(6, 61) AND TBK_EXT_ENDS = 1).

tbk_pair().
SET TBK_EXT_ENDS TO 0.
SET TBK_KS["EXT"] TO LEXICON("VERB", 16, "NOUN", 44, "STEP", { PARAMETER nav_in. RETURN LEXICON(). }, "END", tbk_ext_end@).
tbk_cycle().
tbk_type("P").
tbk_cycle().
assert_true("a plain display still ends on PRO, END once", NOT TBK_KS["EXT"]:ISTYPE("Lexicon") AND TBK_EXT_ENDS = 1 AND tbk_vn(6, 61)).

// ---- Octal loads (N12) ----
tbk_fresh().
tbk_type("V22N12E").
tbk_type("8").
assert_true("octal refuses 8 and keeps the load", TBK_KS["OPRERR"] AND load_active(TBK_KS) AND TBK_KS["LOAD"]["BUF"] = "").
tbk_type("R+").
assert_true("octal refuses a sign", TBK_KS["OPRERR"] AND load_active(TBK_KS) AND NOT TBK_KS["LOAD"]["SIGNED"]).
tbk_type("RE").
assert_true("octal ENTR with no digit is OPR ERR", TBK_KS["OPRERR"] AND load_active(TBK_KS)).
tbk_type("R2").
assert_true("octal shows the digits with no sign", load_shown(TBK_KS, TBK_VEHICLE)["TEXT"] = " 2    ").
tbk_type("E").
assert_true("octal 2 E commits 2", TBK_LOADED:LENGTH = 1 AND TBK_LOADED[0] = 2 AND NOT TBK_KS["OPRERR"] AND NOT load_active(TBK_KS)).
tbk_type("V25N81E").
assert_true("a noun with one register refuses V25", TBK_KS["OPRERR"]).
tbk_type("RV21N12E17E").
assert_true("octal 17 commits 15", TBK_LOADED[0] = 15).
tbk_type("V24N12E3E").
assert_true("an entered octal register keeps showing its digits", load_shown(TBK_KS, TBK_VEHICLE)["DONE"][0][1] = " 00003").
tbk_type("V34E").
tbk_type("V21N81E+00089E").
assert_true("a decimal load is unchanged", TBK_LOADED[0] = 89 AND NOT TBK_KS["OPRERR"]).

// ---- The pilot's own display, stale answers, and ending while the pilot types ----
tbk_fresh().
tbk_v37(3).
tbk_cycle().
tbk_type("V16N60E").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
SET tbk_cyc TO tbk_cycle().
assert_true("held over a monitor the pilot keyed with nothing else shown", tbk_vn(16, 60) AND tbk_cyc["FLAGS"]["KEYREL"]).
tbk_type("K").
tbk_cycle().
assert_true("and in after KEY REL", tbk_vn(50, 18)).

tbk_pair().
tbk_type("V16N60EV32E").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
assert_true("held after V32 put the lamp out", tbk_vn(16, 60)).

tbk_fresh().
tbk_v37(3).
tbk_cycle().
tbk_type("V16N60E").
tbk_v37(1).
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
assert_true("a V37 selection lets go of the pilot's display", tbk_vn(50, 18)).

tbk_pair().
SET TBK_LEAVE_PRO TO TRUE.
tbk_type("P").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
tbk_cycle().
assert_true("a PRO pressed before the request appeared does not answer it", NOT TBK_SEEN["3"]["PRO"]).

tbk_pair().
SET TBK_NEXT["1"] TO tbk_out(1).
SET TBK_NEXT["1"]["ENDED"] TO TRUE.
SET TBK_NEXT["3"] TO tbk_shows(3, 6, 18).
tbk_cycle().
assert_true("the second slot's verb and noun leave V37 N99 up", tbk_vn(37, 99)).

tbk_pair().
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
tbk_v37(0).
tbk_v37(3).
tbk_cycle().
tbk_type("V16N61E").
SET TBK_NEXT["3"] TO tbk_shows(3, 6, 18).
tbk_cycle().
assert_true("the second slot's verb and noun leave the pilot's display", tbk_vn(16, 61)).

tbk_fresh().
tbk_v37(3).
tbk_cycle().
tbk_type("V21N81E+000").
SET TBK_NEXT["3"]["ENDED"] TO TRUE.
tbk_cycle().
assert_true("ending by itself leaves a load on the display", tbk_vn(21, 81) AND load_active(TBK_KS) AND TBK_RUN["IDLE_REQUEST"]["NOUN"] = 99).

tbk_fresh().
tbk_v37(3).
assert_true("the update gate is asked about the second slot alone", core_running(TBK_RUN)["PROG_NO"] = 3).
tbk_v37(1).
assert_true("and about the foreground when there is one", core_running(TBK_RUN)["PROG_NO"] = 1).
tbk_v37(0).
assert_true("and gets FALSE with nothing running", NOT core_running(TBK_RUN):ISTYPE("Lexicon")).

tbk_answering().
tbk_type("V16N60E").
SET TBK_EXT_OUT TO tbk_ext_result(6, 18, TRUE, FALSE).
tbk_cycle().
assert_true("a changed answering display leaves the pilot's display", tbk_vn(16, 60) AND NOT TBK_EXT_ANS["ENTER"]).
tbk_type("K").
tbk_cycle().
assert_true("KEY REL shows the changed one", tbk_vn(6, 18)).
tbk_type("V16N60EP").
SET TBK_EXT_OUT TO tbk_ext_result(6, 44, TRUE, FALSE).
tbk_cycle().
assert_true("an answered display shows its next one", tbk_vn(6, 44)).

tbk_answering().
SET TBK_NEXT["3"]["EXTRA"] TO LEXICON("TBKEXT", 3).
tbk_cycle().
assert_true("the extended display's value wins over the second slot's", TBK_NAV["DERIVED"]["TBKEXT"] = 44).

tbk_pair().
tbk_type("E").
tbk_cycle().
assert_true("an ENTR that only answers a request does not make the display the pilot's", NOT TBK_KS["OWN"]).
tbk_type("K").
SET TBK_NEXT["3"] TO tbk_ask(3, 50, 18).
tbk_cycle().
assert_true("so a request comes in after KEY REL", tbk_vn(50, 18)).

// ---- Selecting a second-slot programme over the standing request ----
tbk_pair().
SET TBK_NEXT["1"] TO tbk_out(1).
SET TBK_NEXT["1"]["ENDED"] TO TRUE.
tbk_cycle().
tbk_type("V37E03E").
tbk_v37(TBK_KS["PROG_REQ"]).
SET tbk_cyc TO tbk_cycle().
assert_true("re-selecting the second slot over V37 N99 blanks it", tbk_vn(-1, -1) AND NOT tbk_cyc["FLAGS"]["FLASH"] AND tbk_cyc["PROG_TEXT"] = "3").
tbk_fresh().
tbk_v37(3).
tbk_cycle().
SET TBK_KS["END_BACK"] TO TRUE.
tbk_cycle().
tbk_type("V37E02E").
tbk_v37(TBK_KS["PROG_REQ"]).
tbk_cycle().
assert_true("so does starting one", tbk_vn(-1, -1)).
tbk_fresh().
tbk_type("V16N60E").
tbk_v37(3).
tbk_cycle().
assert_true("any other display is left alone", tbk_vn(16, 60)).

// ---- The second slot's line in the status area ----
LOCAL tbk_rows IS core_status_texts(LIST(), "second slot: test").
assert_true("alone it takes the top row", tbk_rows[0] = "second slot: test" AND tbk_rows[1] = "").
SET tbk_rows TO core_status_texts(LIST(), "").
assert_true("it leaves its row when the slot has nothing to say", tbk_rows[0] = "").
tbk_fresh().
tbk_v37(3).
assert_true("a slot with no status gives no line", tbk_cycle()["UNDER"] = "").

test_end().
