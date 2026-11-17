// test_alarm.ks -- pad test for the alarm facility (dsky_alarm.ks), its wiring in the core and N09 (no ship access).
//   RUNPATH("0:/tests/test_alarm.ks").   Log: 0:/lm/logs/test_alarm.log. Numbers: python scripts/tests/reference_alarm.py

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").

test_begin("0:/lm/logs/test_alarm.log").

// ---- the facility itself ----
LOCAL al IS alarm_new().
assert_true("new alarm: codes 0,0,0 and lamp dark", al["CODES"][0] = 0 AND al["CODES"][1] = 0 AND al["CODES"][2] = 0 AND NOT al["LAMP"]).
alarm_raise(al, 1406).
assert_true("one raise: 1406,0,0 and lamp lit", al["CODES"][0] = 1406 AND al["CODES"][1] = 0 AND al["LAMP"]).
alarm_raise(al, 1202).
alarm_raise(al, 1201).
assert_true("three raises fill the slots in order", al["CODES"][0] = 1406 AND al["CODES"][1] = 1202 AND al["CODES"][2] = 1201).
alarm_raise(al, 1210).
assert_true("a fourth replaces slot 3 with bit 15 added: 41210", al["CODES"][2] = 41210 AND al["CODES"][0] = 1406 AND al["LAMP"]).
alarm_raise(al, 1202).
assert_true("a fifth: slot 3 = 41202", al["CODES"][2] = 41202).
alarm_reset(al).
assert_true("alarm_reset zeroes the codes and clears the lamp", al["CODES"][0] = 0 AND al["CODES"][2] = 0 AND NOT al["LAMP"]).
assert_true("alarm_text 1202 is 01202", alarm_text(1202) = "01202").
assert_true("alarm_text 41210 is 41210", alarm_text(41210) = "41210").

// ---- through core_step with a fake programme ----
GLOBAL ALM_OUT IS LEXICON("SET_VERB", -1, "SET_NOUN", -1, "EXTRA", LEXICON(), "MSG", "", "KEY_REL", FALSE, "ALT_LAMP", FALSE,
                          "VEL_LAMP", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE, "ENDED", FALSE, "HANDOVER", FALSE, "PROG_NO", 63).
LOCAL fake_vehicle IS LEXICON(
  "NOUNS", LIST(60, 9), "VERBS", LIST(5, 6, 16, 34, 37), "PROGS", LIST(0, 1),
  "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL"),
  "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON(). },
  "STICKY_PROGS", LIST(68),
  "PROGRAMMES", LEXICON("1", LEXICON("START", { PARAMETER prev. RETURN LEXICON("PROG_NO", 1, "REFUSED", ""). },
                                      "STEP", { PARAMETER prog, nav, ks. RETURN ALM_OUT. },
                                      "END", { PARAMETER prog. },
                                      "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE))).
LOCAL ks IS keys_new(fake_vehicle["NOUNS"], fake_vehicle["VERBS"], fake_vehicle["PROGS"]).
LOCAL nav IS LEXICON("OK", TRUE, "STATE", LEXICON(), "DERIVED", LEXICON("VALID", FALSE)).
LOCAL crun IS core_new(fake_vehicle).
core_request(crun, fake_vehicle, ks, 1).
SET ALM_OUT["ALARM"] TO 1406.
LOCAL cycle_count IS 0.
UNTIL cycle_count >= 5 { core_step(crun, fake_vehicle, nav, ks). SET cycle_count TO cycle_count + 1. }
assert_true("a steady alarm for five cycles fills one slot", ks["ALARM"]["CODES"][0] = 1406 AND ks["ALARM"]["CODES"][1] = 0 AND ks["ALARM"]["CODES"][2] = 0).
SET ALM_OUT["ALARM"] TO 0.
LOCAL res_after IS core_step(crun, fake_vehicle, nav, ks).
assert_true("PROG stays lit after the alarm stops (latched)", res_after["FLAGS"]["PROG"]).
assert_true("derived carries the alarm codes", nav["DERIVED"]["ALARM_CODES"][0] = 1406).
SET ALM_OUT["ALARM"] TO 1406.
core_step(crun, fake_vehicle, nav, ks).
assert_true("the same alarm back after a quiet cycle is a new alarm: slot 2", ks["ALARM"]["CODES"][1] = 1406).
SET ALM_OUT["ALARM"] TO 0.
key_press(ks, "R").
assert_true("RSET clears the lamp and the codes", NOT ks["ALARM"]["LAMP"] AND ks["ALARM"]["CODES"][0] = 0 AND NOT core_step(crun, fake_vehicle, nav, ks)["FLAGS"]["PROG"]).

// ---- N09 ----
LOCAL regs IS noun_registers(9, LEXICON("VALID", FALSE, "ALARM_CODES", LIST(1202, 1201, 0))).
assert_true("N09 shows the codes as octal digits", regs:LENGTH = 3 AND regs[0]:TRIM = "01202" AND regs[1]:TRIM = "01201" AND regs[2]:TRIM = "00000").
assert_true("N09 and V05 are in the LM tables", LM_NOUNS:CONTAINS(9) AND LM_VERBS:CONTAINS(5)).
assert_true("N09 with no alarm codes in derived shows zeros", noun_registers(9, LEXICON("VALID", FALSE))[0]:TRIM = "00000").

test_end().
