// test_v82.ks -- pad test for V82, the orbit display (release 1.5): the numbers (s30_tff, lm_v82_values) and the core's extended-verb display
// (ks["EXT"], core/dsky_core.ks) with a made-up vehicle and programme. No flight. The free-fall time is from scripts/tests/reference_ascent.py.
//   RUNPATH("0:/tests/test_v82.ks").   Log: 0:/lm/logs/test_v82.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_v82.log").

GLOBAL TV_MU IS 4.9028e12.
GLOBAL TV_SITE_R IS 1735750.

// ---- the numbers ----
LOCAL tv_r IS TV_SITE_R + 111120.
LOCAL tv_vals IS lm_v82_values(V(tv_r, 0, 0), V(0, SQRT(TV_MU / tv_r), 0), TV_MU, TV_SITE_R).
assert_near("v82 values circular: apolune", tv_vals[0], 111120, 1).
assert_near("v82 values circular: perilune", tv_vals[1], 111120, 1).
assert_near("v82 values circular: no free-fall time", tv_vals[2], -1, 0).

LOCAL tv_ra IS TV_SITE_R + 111120.
LOCAL tv_rp IS TV_SITE_R - 50000.
LOCAL tv_va IS SQRT(TV_MU * (2 / tv_ra - 2 / (tv_ra + tv_rp))).
SET tv_vals TO lm_v82_values(V(tv_ra, 0, 0), V(0, tv_va, 0), TV_MU, TV_SITE_R).
assert_near("v82 tff descending: apolune", tv_vals[0], 111120, 1).
assert_near("v82 tff descending: perilune", tv_vals[1], -50000, 1).
assert_near("v82 tff descending", tv_vals[2], 1976.695, 1).
// The same orbit going up from perilune side: the next DESCENDING crossing is more than half a period away.
LOCAL tv_tff_up IS s30_tff(V(tv_ra, 0, 0), V(0, -tv_va, 0), TV_MU, TV_SITE_R + 10668).
assert_near("v82 tff the other way round is the same from apolune", tv_tff_up, 1976.695, 1).
assert_near("v82 tff below the limit radius", s30_tff(V(TV_SITE_R + 5000, 0, 0), V(0, tv_va, 0), TV_MU, TV_SITE_R + 10668), -1, 0).
assert_near("v82 tff hyperbolic", s30_tff(V(tv_ra, 0, 0), V(0, 3000, 0), TV_MU, TV_SITE_R + 10668), -1, 0).
SET tv_vals TO lm_v82_values(V(TV_SITE_R, 0, 0), V(0, 4.6, 0), TV_MU, TV_SITE_R).
assert_true("v82 landed: finite apolune and perilune", ABS(tv_vals[0]) < 100000000 AND ABS(tv_vals[1]) < 100000000).
assert_near("v82 landed: no free-fall time", tv_vals[2], -1, 0).
SET tv_vals TO lm_v82_values(V(TV_SITE_R, 0, 0), V(0, 0, 0), TV_MU, TV_SITE_R).
assert_true("v82 at rest does not divide by zero", ABS(tv_vals[0]) < 100000000 AND ABS(tv_vals[1]) < 100000000 AND tv_vals[2] = -1).

// ---- the core's extended-verb display ----
GLOBAL TV_STEPS IS 0.
GLOBAL TV_ENDS IS 0.
GLOBAL TV_SAW IS LEXICON("PRO", FALSE, "TERMINATE", FALSE, "ENTER", FALSE, "RECYCLE", FALSE).
GLOBAL TV_COUNT IS 0.      // how often V82's STEP ran

FUNCTION tv_out {
  PARAMETER set_verb, set_noun, request, ended.
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "EXTRA", LEXICON(), "MSG", "", "KEY_REL", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE,
                 "REQUEST", request, "ENDED", ended, "HANDOVER", FALSE, "PROG_NO", 12).
}
GLOBAL TV_NEXT IS tv_out(-1, -1, FALSE, FALSE).

LOCAL tv_vehicle IS LEXICON(
  "NOUNS", LIST(60, 25, 33, 44, 74), "VERBS", LIST(6, 16, 21, 32, 33, 34, 37, 50, 82), "PROGS", LIST(0, 12),
  "NO_NOUN_VERBS", LIST(82),
  "VERB_ACTIONS", LEXICON("82", lm_verb_82@),
  "LOADS", LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))),
  "LOAD_COMMIT", { PARAMETER noun_no, comps, values. RETURN "". },
  "LAMPS", LEXICON("KEY_REL", "KEYREL"),
  "IDLE_LAMPS", { PARAMETER idle_text. RETURN LEXICON(). },
  "STICKY_PROGS", LIST(),
  "END_REQUEST", LEXICON("VERB", 37, "NOUN", 99, "QUIET", TRUE),
  "PROGRAMMES", LEXICON("12", LEXICON(
    "START", { PARAMETER prev. RETURN LEXICON("REFUSED", ""). },
    "STEP", { PARAMETER prog, nav, ks.
              SET TV_STEPS TO TV_STEPS + 1.
              FOR tv_key IN LIST("PRO", "TERMINATE", "ENTER", "RECYCLE") { IF ks[tv_key] { SET TV_SAW[tv_key] TO TRUE. } }
              SET ks["PRO"] TO FALSE.
              RETURN TV_NEXT. },
    "END", { PARAMETER prog. SET TV_ENDS TO TV_ENDS + 1. },
    "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE))).

FUNCTION tv_keys {
  PARAMETER ks, text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks, text:SUBSTRING(i, 1)). }
}
FUNCTION tv_fresh {
  LOCAL ks IS keys_new(tv_vehicle["NOUNS"], tv_vehicle["VERBS"], tv_vehicle["PROGS"], LIST(), tv_vehicle["NO_NOUN_VERBS"]).
  SET ks["VEHICLE"] TO tv_vehicle.
  SET TV_STEPS TO 0.
  SET TV_ENDS TO 0.
  SET TV_COUNT TO 0.
  FOR tv_key IN LIST("PRO", "TERMINATE", "ENTER", "RECYCLE") { SET TV_SAW[tv_key] TO FALSE. }
  RETURN ks.
}
// tv_cycle: one core cycle; returns the core's output, with derived for checking in "DERIVED".
FUNCTION tv_cycle {
  PARAMETER crun, ks.
  LOCAL derived IS LEXICON("VALID", FALSE).
  LOCAL out IS core_step(crun, tv_vehicle, LEXICON("OK", TRUE, "STATE", LEXICON(), "DERIVED", derived), ks).
  SET out["DERIVED"] TO derived.
  RETURN out.
}
// tv_ext_fake: replace V82's STEP (which reads the ship) by a counting fake, after V82 E.
FUNCTION tv_ext_fake {
  PARAMETER ks.
  SET ks["EXT"]["STEP"] TO { PARAMETER nav. SET TV_COUNT TO TV_COUNT + 1. RETURN LEXICON("N44", LIST(1852, 3704, -1)). }.
}

// V82 during a programme.
LOCAL ks IS tv_fresh().
LOCAL crun IS core_new(tv_vehicle).
core_request(crun, tv_vehicle, ks, 12).
SET TV_NEXT TO tv_out(50, 25, LEXICON("VERB", 50, "NOUN", 25), FALSE).
tv_cycle(crun, ks).
assert_true("v82 during programme: the programme's request shows first", ks["VERB"] = 50 AND ks["NOUN"] = 25).
tv_keys(ks, "V82E").
assert_true("V82 E is accepted with no noun", NOT ks["OPRERR"] AND ks["EXT"]:ISTYPE("Lexicon")).
tv_ext_fake(ks).
SET TV_NEXT TO tv_out(6, 74, LEXICON("VERB", 50, "NOUN", 25), FALSE).
LOCAL tv_res IS tv_cycle(crun, ks).
assert_true("v82 during programme: V16 N44 shows", ks["VERB"] = 16 AND ks["NOUN"] = 44).
assert_true("v82 during programme: it flashes", tv_res["FLAGS"]["FLASH"]).
assert_true("v82 during programme: the step still runs", TV_STEPS = 2).
assert_true("v82 during programme: V82's values reach derived", tv_res["DERIVED"]:HASKEY("N44") AND TV_COUNT = 1).
assert_true("v82 during programme: SET_VERB goes only to PROG_VN", ks["PROG_VN"][0] = 6 AND ks["PROG_VN"][1] = 74 AND ks["VERB"] = 16).
assert_true("v82 during programme: ENTR of V82 E is not the programme's", NOT TV_SAW["ENTER"]).
tv_keys(ks, "V32E").
tv_cycle(crun, ks).
assert_true("V32 under V82 keeps the display and is not the programme's", ks["VERB"] = 16 AND ks["NOUN"] = 44 AND ks["EXT"]:ISTYPE("Lexicon") AND NOT TV_SAW["RECYCLE"] AND TV_COUNT = 2).
tv_keys(ks, "V34E").
SET tv_res TO tv_cycle(crun, ks).
assert_true("v34 ends v82 only: V82 is gone", NOT ks["EXT"]:ISTYPE("Lexicon")).
assert_true("v34 ends v82 only: the programme runs on", crun["PROG"]:ISTYPE("Lexicon") AND TV_ENDS = 0 AND NOT TV_SAW["TERMINATE"]).
assert_true("v34 ends v82 only: the programme's request is displayed again", ks["VERB"] = 50 AND ks["NOUN"] = 25 AND tv_res["FLAGS"]["FLASH"]).

// V33 and PRO end it the same way, and the programme does not see them.
FOR tv_end_key IN LIST("V33E", "P") {
  SET ks TO tv_fresh().
  SET crun TO core_new(tv_vehicle).
  core_request(crun, tv_vehicle, ks, 12).
  SET TV_NEXT TO tv_out(50, 25, LEXICON("VERB", 50, "NOUN", 25), FALSE).
  tv_cycle(crun, ks).
  tv_keys(ks, "V82E").
  tv_ext_fake(ks).
  tv_cycle(crun, ks).
  tv_keys(ks, tv_end_key).
  tv_cycle(crun, ks).
  assert_true(tv_end_key + " ends V82", NOT ks["EXT"]:ISTYPE("Lexicon")).
  assert_true(tv_end_key + " is not the programme's PRO", NOT TV_SAW["PRO"] AND TV_ENDS = 0).
  assert_true(tv_end_key + " gives the request back", ks["VERB"] = 50 AND ks["NOUN"] = 25).
}

// A programme with no request: its last verb and noun come back.
SET ks TO tv_fresh().
SET crun TO core_new(tv_vehicle).
core_request(crun, tv_vehicle, ks, 12).
SET TV_NEXT TO tv_out(6, 74, FALSE, FALSE).
tv_cycle(crun, ks).
tv_keys(ks, "V82E").
tv_ext_fake(ks).
SET TV_NEXT TO tv_out(-1, -1, FALSE, FALSE).
tv_cycle(crun, ks).
tv_keys(ks, "P").
tv_cycle(crun, ks).
assert_true("v82 ends to the programme's verb and noun", ks["VERB"] = 6 AND ks["NOUN"] = 74).

// V82 from P00.
SET ks TO tv_fresh().
SET crun TO core_new(tv_vehicle).
SET ks["VERB"] TO 16.
SET ks["NOUN"] TO 60.
tv_cycle(crun, ks).
tv_keys(ks, "V82E").
tv_ext_fake(ks).
SET tv_res TO tv_cycle(crun, ks).
assert_true("v82 from P00 shows V16 N44 flashing", ks["VERB"] = 16 AND ks["NOUN"] = 44 AND tv_res["FLAGS"]["FLASH"]).
tv_keys(ks, "V82E").
tv_ext_fake(ks).
tv_cycle(crun, ks).
tv_keys(ks, "P").
tv_cycle(crun, ks).
assert_true("v82 from P00 ends to the display shown before it (V82 twice)", ks["VERB"] = 16 AND ks["NOUN"] = 60 AND NOT ks["EXT"]:ISTYPE("Lexicon")).

// V37 clears it.
SET ks TO tv_fresh().
SET crun TO core_new(tv_vehicle).
tv_keys(ks, "V82E").
tv_ext_fake(ks).
tv_cycle(crun, ks).
core_request(crun, tv_vehicle, ks, 12).
assert_true("v37 clears v82", NOT ks["EXT"]:ISTYPE("Lexicon")).
SET TV_NEXT TO tv_out(6, 74, FALSE, FALSE).
tv_cycle(crun, ks).
assert_true("v37 clears v82: the new programme displays", ks["VERB"] = 6 AND ks["NOUN"] = 74).

// A programme that ends while V82 is up leaves V82 displayed; PRO then shows the standing V37 N99 request.
SET ks TO tv_fresh().
SET crun TO core_new(tv_vehicle).
core_request(crun, tv_vehicle, ks, 12).
SET TV_NEXT TO tv_out(6, 74, FALSE, FALSE).
tv_cycle(crun, ks).
tv_keys(ks, "V82E").
tv_ext_fake(ks).
tv_cycle(crun, ks).
SET TV_NEXT TO tv_out(-1, -1, FALSE, TRUE).
tv_cycle(crun, ks).
assert_true("a programme ending under V82 leaves V82 up", TV_ENDS = 1 AND ks["VERB"] = 16 AND ks["NOUN"] = 44 AND ks["EXT"]:ISTYPE("Lexicon")).
tv_cycle(crun, ks).
assert_true("v82 stays up with no programme", ks["VERB"] = 16 AND ks["NOUN"] = 44).
tv_keys(ks, "P").
tv_cycle(crun, ks).
assert_true("then PRO shows the V37 N99 request", ks["VERB"] = 37 AND ks["NOUN"] = 99).

// V82 during a keyed load is refused and the load goes on.
SET ks TO tv_fresh().
tv_keys(ks, "V21N33E+000").
tv_keys(ks, "V82E").
assert_true("v82 during load refused", ks["OPRERR"] AND load_active(ks) AND NOT ks["EXT"]:ISTYPE("Lexicon")).

// The LM's tables.
assert_true("V82 is a LM verb with no noun", LM_VERBS:CONTAINS(82)).
assert_true("N44, N74, N76 and N94 are LM nouns", LM_NOUNS:CONTAINS(44) AND LM_NOUNS:CONTAINS(74) AND LM_NOUNS:CONTAINS(76) AND LM_NOUNS:CONTAINS(94)).

test_end().
