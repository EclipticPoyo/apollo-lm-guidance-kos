// test_csm.ks -- pad test for the choice of the CSM (lm/lm_csm.ks). No ship access.
//   RUNPATH("0:/tests/test_csm.ks").   Log: 0:/lm/logs/test_csm.log.

RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/lm_csm.ks").

test_begin("0:/lm/logs/test_csm.log").
SET CONFIG:IPU TO 2000.

// All eight inputs as LIST(has a name, the named vessel is ok, the target is ok), and the answer each order must give.
LOCAL tm_inputs IS LIST(
    LIST(TRUE, TRUE, TRUE), LIST(TRUE, TRUE, FALSE), LIST(TRUE, FALSE, TRUE), LIST(TRUE, FALSE, FALSE),
    LIST(FALSE, TRUE, TRUE), LIST(FALSE, TRUE, FALSE), LIST(FALSE, FALSE, TRUE), LIST(FALSE, FALSE, FALSE)).
LOCAL tm_expected IS LEXICON(
    // P12: a name binds; the target counts only without one.
    "NAMED_ONLY", LIST("NAMED", "NAMED", "NONE", "NONE", "TARGET", "NONE", "TARGET", "NONE"),
    // The aborts.
    "TARGET_FIRST", LIST("TARGET", "NAMED", "TARGET", "NONE", "TARGET", "NONE", "TARGET", "NONE"),
    // P32 and P33.
    "NAMED_FIRST", LIST("NAMED", "NAMED", "TARGET", "NONE", "TARGET", "NONE", "TARGET", "NONE")).

FOR tm_order IN tm_expected:KEYS {
  LOCAL tm_index IS 0.
  UNTIL tm_index >= tm_inputs:LENGTH {
    LOCAL inputs IS tm_inputs[tm_index].
    LOCAL want IS tm_expected[tm_order][tm_index].
    LOCAL got IS csm_choice(tm_order, inputs[0], inputs[1], inputs[2]).
    assert_true(tm_order + " name " + inputs[0] + ", named ok " + inputs[1] + ", target ok " + inputs[2]
        + ": " + want + " (got " + got + ")", got = want).
    SET tm_index TO tm_index + 1.
  }
}
assert_true("an unknown order chooses nothing", csm_choice("OTHER", TRUE, TRUE, TRUE) = "NONE").

test_end().
