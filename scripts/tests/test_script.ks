// test_script.ks -- pad test for the scripted alarms: the schedule parser (lm_alarms.ks), the vehicle's alarm source, the core's display
// restart and the ALARMS setting (no ship access). Numbers: python scripts/tests/reference_alarm.py.
//   RUNPATH("0:/tests/test_script.ks").   Log: 0:/lm/logs/test_script.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_script.log").

// ---- parse and due ----
LOCAL a11 IS alarm_script_parse("A11", "A11").
assert_true("A11 parses to five pairs in time order", a11:LENGTH = 5 AND a11[0][0] = 301 AND a11[0][1] = 1202 AND a11[2][0] = 560 AND a11[2][1] = 1201 AND a11[4][0] = 600).
assert_true("A11 under profile J is empty", alarm_script_parse("A11", "J"):LENGTH = 0).
assert_true("OFF gives an empty schedule", alarm_script_parse("OFF", "A11"):LENGTH = 0).
assert_true("the default setting is OFF", ALARMS = "OFF").
LOCAL own IS alarm_script_parse("1202@315,1201@548", "A11").
assert_true("1202@315,1201@548 parses", own:LENGTH = 2 AND own[0][0] = 315 AND own[0][1] = 1202 AND own[1][0] = 548 AND own[1][1] = 1201).
LOCAL unsorted IS alarm_script_parse("1201@548,1202@315", "A11").
assert_true("a list typed out of order is sorted", unsorted[0][1] = 1202 AND unsorted[1][1] = 1201).
assert_true("abc is not a schedule", alarm_script_parse("abc", "A11"):ISTYPE("Boolean")).
assert_true("1202@ is not a schedule", alarm_script_parse("1202@", "A11"):ISTYPE("Boolean")).
assert_true("a three-digit code is not a schedule", alarm_script_parse("120@30", "A11"):ISTYPE("Boolean")).
assert_true("due (299, 302) is 1202", alarm_script_due(a11, 299, 302):LENGTH = 1 AND alarm_script_due(a11, 299, 302)[0] = 1202).
assert_true("due (300, 301) is 1202 (inclusive of the upper bound)", alarm_script_due(a11, 300, 301):LENGTH = 1).
assert_true("due (301, 363) is empty (exclusive of the lower bound)", alarm_script_due(a11, 301, 363):LENGTH = 0).
assert_true("due (363, 365) is 1202", alarm_script_due(a11, 363, 365)[0] = 1202).
LOCAL all_due IS alarm_script_due(a11, 0, 700).
assert_true("a jump (0, 700) returns all five in order", all_due:LENGTH = 5 AND all_due[2] = 1201).

// ---- the vehicle's alarm source: nothing before ignition ----
SET LM_VEH["ALARM_SCHED"] TO a11.
SET LM_VEH["ALARM_T"] TO -1.
assert_true("no programme: no alarm, clock reset", lm_alarm_source(FALSE, 5000):LENGTH = 0 AND LM_VEH["ALARM_T"] = -1).
LOCAL prog IS LEXICON("SEQ", LEXICON("IGN_T", -1)).
assert_true("engine not lit: no alarm even late", lm_alarm_source(prog, 5000):LENGTH = 0).
SET prog["SEQ"]["IGN_T"] TO 1000.
assert_true("299 s after ignition: nothing", lm_alarm_source(prog, 1299):LENGTH = 0).
LOCAL fired IS lm_alarm_source(prog, 1302).
assert_true("302 s after ignition: 1202", fired:LENGTH = 1 AND fired[0] = 1202).
assert_true("the next cycle: nothing again", lm_alarm_source(prog, 1303):LENGTH = 0).
SET LM_VEH["ALARM_SCHED"] TO LIST().
SET LM_VEH["ALARM_T"] TO -1.
assert_true("an empty schedule fires nothing (OFF)", lm_alarm_source(prog, 1302):LENGTH = 0).

// ---- the core: a fired alarm and the display restart ----
GLOBAL SC_CALLS IS LEXICON("START", 0, "END", 0).
GLOBAL SC_COMMITS IS LIST().
GLOBAL SC_DUE IS LIST().
LOCAL fake_vehicle IS LEXICON(
  "NOUNS", LIST(33, 60), "VERBS", LIST(6, 16, 21, 25, 33, 34, 37), "PROGS", LIST(0, 1),
  "LAMPS", LEXICON(), "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON(). }, "STICKY_PROGS", LIST(),
  "LOADS", LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))),
  "LOAD_COMMIT", { PARAMETER noun_no, comps, values. SC_COMMITS:ADD(noun_no). RETURN "". },
  "ALARM_SOURCE", { PARAMETER prog_in, now_ut. RETURN SC_DUE. },
  "PROGRAMMES", LEXICON("1", LEXICON("START", { PARAMETER prev. SET SC_CALLS["START"] TO SC_CALLS["START"] + 1. RETURN LEXICON("PROG_NO", 1, "REFUSED", ""). },
                                      "STEP", { PARAMETER prog_in, nav_in, ks_in. RETURN LEXICON(). },
                                      "END", { PARAMETER prog_in. SET SC_CALLS["END"] TO SC_CALLS["END"] + 1. },
                                      "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE))).
LOCAL ks IS keys_new(fake_vehicle["NOUNS"], fake_vehicle["VERBS"], fake_vehicle["PROGS"]).
SET ks["VEHICLE"] TO fake_vehicle.
LOCAL crun IS core_new(fake_vehicle).
core_request(crun, fake_vehicle, ks, 1).
LOCAL vault IS store_new(lm_cells_for("A11")).
lm_store_put_tig(vault, 1234.5).
FOR key_char IN LIST("V", "2", "5", "N", "3", "3", "E", "+", "0", "0", "0", "1", "2", "E", "V", "1") { key_press(ks, key_char). }
SET ks["AWAIT_PROG"] TO TRUE.
SET ks["PBUF"] TO "6".
assert_true("setup: a load is active and a verb is half typed", load_active(ks) AND ks["MODE"] = "V").
SET SC_DUE TO LIST(1202).
LOCAL raised IS core_scripted_alarms(ks, fake_vehicle, crun["PROG"], 0).
assert_true("one code was raised", raised = 1 AND ks["ALARM"]["CODES"][0] = 1202 AND ks["ALARM"]["LAMP"]).
assert_true("the restart drops the half-typed verb and the V37 wait", ks["MODE"] = "" AND ks["VBUF"] = "" AND NOT ks["AWAIT_PROG"] AND ks["PBUF"] = "").
assert_true("the restart ends the load and commits nothing", NOT load_active(ks) AND SC_COMMITS:LENGTH = 0).
assert_true("the store is unchanged (Review Focus 5)", ABS(lm_store_get_tig(vault) - 1234.5) < 0.01).
assert_true("the programme's START and END were not called again", SC_CALLS["START"] = 1 AND SC_CALLS["END"] = 0).
SET SC_DUE TO LIST().
assert_true("no alarm due: nothing raised, display untouched", core_scripted_alarms(ks, fake_vehicle, crun["PROG"], 0) = 0).

// ---- the ALARMS setting ----
cfg_apply_line("ALARMS = 1202@315,1201@548").
assert_true("ALARMS accepts a list", ALARMS = "1202@315,1201@548").
LOCAL warn_count IS CFG_WARNINGS:LENGTH.
assert_true("ALARMS rejects a bad text and says so", cfg_apply_line("ALARMS = bogus") <> "" AND CFG_WARNINGS:LENGTH = warn_count + 1 AND ALARMS = "1202@315,1201@548").
cfg_apply_line("ALARMS = a11").
assert_true("ALARMS accepts A11 in any case", ALARMS = "A11").
cfg_apply_line("ALARMS = OFF").
assert_true("ALARMS accepts OFF", ALARMS = "OFF").
assert_true("ALARMS is a known setting", CFG_NAMES:CONTAINS("ALARMS")).

test_end().
