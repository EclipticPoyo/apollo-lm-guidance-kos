// test_p27.ks -- pad test for the update programme P27 (core/dsky_p27.ks): V71, V72, V33, V34 against a store. No ship access.
//   RUNPATH("0:/tests/test_p27.ks").
// Log: 0:/lm/logs/test_p27.log. The last line is "TESTS: N passed, M failed".
// Keystrokes are the ones `python scripts/tests/reference_loads.py` prints; the LM cells (RLS and so on) are the real table.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").

test_begin("0:/lm/logs/test_p27.log").

GLOBAL IN_P00 IS TRUE.          // what the fake vehicle's P27_OK answers

// p27_make_vehicle: a fake vehicle holding a store of the cells of one software version ("A11" or "J").
FUNCTION p27_make_vehicle {
  PARAMETER profile.
  RETURN LEXICON("STORE", store_new(lm_cells_for(profile)), "P27_OK", { PARAMETER prog. RETURN IN_P00. }, "P27_ADDR", lm_p27_addr(profile)).
}

FUNCTION p27_fresh_keys {
  PARAMETER vehicle.
  LOCAL ks IS keys_new(LIST(60), LIST(6, 16, 21, 25, 33, 34, 37, 71, 72), LIST(0)).
  SET ks["VEHICLE"] TO vehicle.
  RETURN ks.
}

FUNCTION p27_type_keys {
  PARAMETER ks, text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks, text:SUBSTRING(i, 1)). }
}

// ---- V71 block, written by V33 -------------------------------------------------------------------------------------------
LOCAL veh IS p27_make_vehicle("A11").
LOCAL vault IS veh["STORE"].
LOCAL ks IS p27_fresh_keys(veh).
// RLS ECADR 2022 octal. Six words 00302 11604 00124 14046 00002 17576 (the site 0.674 N 23.473 E, -1930 m).
p27_type_keys(ks, "V71E").
assert_true("V71 E starts P27 in P00", p27_active(ks) AND NOT ks["OPRERR"]).
assert_true("the display shows V21 N01 while P27 waits for data", ks["VERB"] = 21 AND ks["NOUN"] = 1).
p27_type_keys(ks, "10E2022E00302E11604E00124E14046E00002E").
assert_true("P27 still waits for the last word", p27_active(ks) AND NOT store_loaded(vault, "RLS")).
p27_type_keys(ks, "17576E").
assert_true("after the last word nothing is written yet", NOT store_loaded(vault, "RLS") AND p27_active(ks)).
assert_near("the verify step shows noun 02", ks["NOUN"], 2, 0).
p27_type_keys(ks, "V33E").
assert_true("V33 E writes the block and leaves P27", store_loaded(vault, "RLS") AND NOT p27_active(ks) AND NOT ks["OPRERR"]).
LOCAL rls_back IS lm_store_get_rls(vault).
LOCAL expect_rls IS lm_site_to_rls(0.674, 23.473, -1930, 1737400).
assert_vec("the uplinked RLS is the site vector", rls_back, expect_rls, 1).
assert_near("the display went back to verb 16", ks["VERB"], 16, 0).

// ---- V72 scatter write ----------------------------------------------------------------------------------------------------
SET ks TO p27_fresh_keys(veh).
p27_type_keys(ks, "V72E05E2400E03447E2401E01600EV33E").        // TLAND (099, ECADR 2400 octal): two words, as a scatter write
assert_true("V72 writes both words of TLAND", store_loaded(vault, "TLAND") AND NOT p27_active(ks)).
assert_near("TLAND reads back as 30000000 cs (400000 s from clock zero 100000)", lm_store_get_tland_ut(vault, 100000), 400000, 0.01).

// ---- the burn block: DELVLVC (six words) and TIG (two) in one V71 block across two cells ----------------------------------------
// Words from the PAD (DOI, 30 m/s retrograde at 299000 s from the clock zero): ECADR 3433 octal, index 12 octal (8 words).
SET ks TO p27_fresh_keys(veh).
p27_type_keys(ks, "V71E12E3433E77731E63145E00000E00000E00000E00000E03440E36340EV33E").
assert_true("an 8 word block across DELVLVC and TIG is written and P27 ends", store_loaded(vault, "DELVLVC") AND store_loaded(vault, "TIG") AND NOT p27_active(ks) AND NOT ks["OPRERR"]).
assert_near("the uplinked burn delta-v x is -30 m/s", lm_store_get_dv(vault):X, -30, 0.01).
assert_near("the uplinked burn delta-v y and z are zero", ABS(lm_store_get_dv(vault):Y) + ABS(lm_store_get_dv(vault):Z), 0, 0.001).
assert_near("the uplinked burn TIG is 299000 s from the clock zero", lm_store_get_tig(vault), 299000, 0.01).

// ---- PROG shows 27 while the update runs (UPDATE_PROGRAM.agc: NEWMODEX, DEC 27), the old programme number otherwise ---------------
SET ks TO p27_fresh_keys(veh).
assert_true("before P27 the programme text is unchanged", p27_prog_text(ks, "00") = "00" AND p27_prog_text(ks, "63") = "63").
p27_type_keys(ks, "V71E").
assert_true("during P27 the programme text is 27", p27_prog_text(ks, "00") = "27").
p27_type_keys(ks, "V34E").
assert_true("after P27 the old programme text is back", p27_prog_text(ks, "00") = "00").

// ---- the display during an update: R1 the word being keyed (left to right, not padded), R3 the address stream ---------------------
// Luminary UPDATE_PROGRAM.agc puts the ECADR of UPBUFF + the number of items received so far in R3 (V21 N01 flashing), and the ECADR of
// UPTEMP at the verify step (V21 N02). 099: UPBUFF 1174 octal, UPTEMP 1167 (ERASABLE_ASSIGNMENTS listing); 210: 1173 and 1166.
SET ks TO p27_fresh_keys(veh).
assert_true("no update: nothing shown", NOT p27_shown(ks, veh)["ACTIVE"]).
p27_type_keys(ks, "V71E").
LOCAL pv IS p27_shown(ks, veh).
assert_true("waiting for II: R3 is the UPBUFF address 01174 (A11)", pv["ACTIVE"] AND pv["R3"] = " 01174" AND pv["R1"] = "").
p27_type_keys(ks, "04E").
assert_true("waiting for the ECADR: R3 is UPBUFF + 1", p27_shown(ks, veh)["R3"] = " 01175").
p27_type_keys(ks, "2400E").
assert_true("waiting for the first word: R3 is UPBUFF + 2", p27_shown(ks, veh)["R3"] = " 01176").
p27_type_keys(ks, "25").
assert_true("R1 shows 25 at the left (sign cell blank), not as 00025", p27_shown(ks, veh)["R1"] = " 25   ").
p27_type_keys(ks, "E").
assert_true("after the word R3 counts on to UPBUFF + 3 and R1 is blank again", p27_shown(ks, veh)["R3"] = " 01177" AND p27_shown(ks, veh)["R1"] = "").
p27_type_keys(ks, "01600E").
assert_true("at the verify step R3 is the UPTEMP address 01167", p27_shown(ks, veh)["R3"] = " 01167").
p27_type_keys(ks, "V34E").
assert_true("after the update nothing is shown", NOT p27_shown(ks, veh)["ACTIVE"]).
LOCAL veh_j IS p27_make_vehicle("J").
SET ks TO p27_fresh_keys(veh_j).
p27_type_keys(ks, "V71E").
assert_true("210: waiting for II, R3 is 01173", p27_shown(ks, veh_j)["R3"] = " 01173").
p27_type_keys(ks, "04E2026E03447E01600E").
assert_true("210: at the verify step R3 is 01166", p27_shown(ks, veh_j)["R3"] = " 01166").
LOCAL veh_plain IS LEXICON("STORE", store_new(lm_cells_for("A11")), "P27_OK", { PARAMETER prog. RETURN IN_P00. }).
SET ks TO p27_fresh_keys(veh_plain).
p27_type_keys(ks, "V71E").
assert_true("a vehicle without P27_ADDR shows no R3", p27_shown(ks, veh_plain)["ACTIVE"] AND p27_shown(ks, veh_plain)["R3"] = "").

// ---- V34 throws the block away ---------------------------------------------------------------------------------------------
LOCAL veh2 IS p27_make_vehicle("A11").
SET ks TO p27_fresh_keys(veh2).
p27_type_keys(ks, "V71E04E2400E03447E").
p27_type_keys(ks, "V34E").
assert_true("V34 E leaves P27 and writes nothing", NOT p27_active(ks) AND NOT store_loaded(veh2["STORE"], "TLAND")).
assert_near("V34 E during P27 does not end the DSKY (verb is not 34)", ks["VERB"], 16, 0).

// ---- refusals leave the store untouched (Review Focus 1 and 5) ---------------------------------------------------------------
FUNCTION refused_with {
  PARAMETER label, profile, text.
  LOCAL veh_r IS p27_make_vehicle(profile).
  LOCAL k IS p27_fresh_keys(veh_r).
  p27_type_keys(k, text).
  assert_true(label + ": OPRERR, P27 over", k["OPRERR"] AND NOT p27_active(k)).
  assert_true(label + ": store untouched", NOT store_loaded(veh_r["STORE"], "RLS") AND NOT store_loaded(veh_r["STORE"], "TLAND") AND NOT store_loaded(veh_r["STORE"], "TIG")).
}
refused_with("an ECADR the store does not model", "A11", "V71E04E0001E00001E00002EV33E").
refused_with("a block that runs past the last cell", "A11", "V71E04E3777E00001E00002EV33E").
refused_with("a 099 ECADR (TLAND, 2400) in a 210 store", "J", "V71E04E2400E03447E01600EV33E").
// An 8 or 9 in an octal word is rejected with OPR ERR but the update goes on (PINBALL 89TEST: CHARALRM turns the lamp on and ignores the
// key); a digit after the fifth is ignored without an alarm (NUM: DSPCOUNT negative, ENDOFJOB).
LOCAL veh_d IS p27_make_vehicle("A11").
SET ks TO p27_fresh_keys(veh_d).
p27_type_keys(ks, "V71E04E2400E0344").
p27_type_keys(ks, "8").
assert_true("a digit 8 lights OPR ERR but P27 goes on", ks["OPRERR"] AND p27_active(ks)).
SET ks["OPRERR"] TO FALSE.
p27_type_keys(ks, "7E01600EV33E").
assert_true("the 8 was ignored: the word is 03447 and the block is stored", NOT p27_active(ks) AND store_loaded(veh_d["STORE"], "TLAND") AND ABS(lm_store_get_tland_ut(veh_d["STORE"], 100000) - 400000) < 0.01).
SET ks TO p27_fresh_keys(veh_d).
p27_type_keys(ks, "V71E04E2400E034470").
assert_true("a sixth digit is ignored with no alarm", NOT ks["OPRERR"] AND p27_active(ks)).
p27_type_keys(ks, "E").
assert_true("the word kept its five digits (03447), so P27 now waits for the next word (R3 is UPBUFF + 3)", p27_active(ks) AND NOT ks["OPRERR"] AND p27_shown(ks, veh_d)["R3"] = " 01177").
refused_with("a count of 2", "A11", "V71E02E").
refused_with("a count above 20 decimal (25 octal)", "A11", "V71E25E").
refused_with("a V72 with an even count", "A11", "V72E04E").
refused_with("ENTR with nothing keyed", "A11", "V71E04EE").
LOCAL v_after IS p27_make_vehicle("A11").
SET ks TO p27_fresh_keys(v_after).
p27_type_keys(ks, "V71E04E2400E03447E01600E").
p27_type_keys(ks, "E").
assert_true("ENTR at the verify step does not write (V33 or V34 only)", p27_active(ks) AND ks["OPRERR"] AND NOT store_loaded(v_after["STORE"], "TLAND")).
p27_type_keys(ks, "R").
assert_true("RSET leaves P27 and clears OPRERR", NOT p27_active(ks) AND NOT ks["OPRERR"]).

// ---- not allowed outside P00; V70 and V73 are not implemented ----------------------------------------------------------------
SET IN_P00 TO FALSE.
SET ks TO p27_fresh_keys(p27_make_vehicle("A11")).
p27_type_keys(ks, "V71E").
assert_true("V71 with a programme running lights OPRERR and does not start P27", ks["OPRERR"] AND NOT p27_active(ks)).
SET IN_P00 TO TRUE.
SET ks TO p27_fresh_keys(p27_make_vehicle("A11")).
p27_type_keys(ks, "V70E").
assert_true("V70 is not a verb: OPRERR", ks["OPRERR"] AND NOT p27_active(ks)).
SET ks TO p27_fresh_keys(p27_make_vehicle("A11")).
p27_type_keys(ks, "V73E").
assert_true("V73 is not a verb: OPRERR", ks["OPRERR"] AND NOT p27_active(ks)).
SET ks TO p27_fresh_keys(p27_make_vehicle("A11")).
p27_type_keys(ks, "V33E").
assert_true("V33 outside P27 lights OPRERR", ks["OPRERR"]).

// ---- a keyed load and P27 do not overlap -----------------------------------------------------------------------------------
SET ks TO p27_fresh_keys(p27_make_vehicle("A11")).
p27_type_keys(ks, "V71E").
p27_type_keys(ks, "V25N60E").
assert_true("another verb during P27 is OPRERR and P27 stays", ks["OPRERR"] AND p27_active(ks)).

test_end().
