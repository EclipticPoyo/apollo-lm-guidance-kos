// test_load.ks -- pad test for the keyed loaders V21 to V25 (core/dsky_load.ks and its hooks in dsky_keys.ks), plus the LM's
// own load (N33 and N81 through lm_load_commit). No ship access: a fake vehicle records what a finished load commits.
//   RUNPATH("0:/tests/test_load.ks").
// Log: 0:/lm/logs/test_load.log. The last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_load.log").

GLOBAL COMMITS IS LIST().       // each finished load adds LIST(noun, comps, values)

LOCAL fake_vehicle IS LEXICON(
  "LOADS", LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "88", LEXICON("NCOMP", 2, "DIGITS", LIST(5, 5))),
  "LOAD_COMMIT", { PARAMETER noun_no, comps, values. COMMITS:ADD(LIST(noun_no, comps, values)). RETURN "". }).

// type: key a string one character at a time, as the keyboard does ("E" is ENTR).
FUNCTION ld_type_keys {
  PARAMETER ks, text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks, text:SUBSTRING(i, 1)). }
}

FUNCTION ld_fresh_keys {
  LOCAL ks IS keys_new(LIST(33, 88, 60), LIST(6, 16, 21, 22, 23, 24, 25, 34, 37), LIST(0)).
  SET ks["VEHICLE"] TO fake_vehicle.
  COMMITS:CLEAR().
  RETURN ks.
}

// ---- V25 loads three registers --------------------------------------------------------------------------------------------
LOCAL ks IS ld_fresh_keys().
ld_type_keys(ks, "V25N33E").
assert_true("V25 N33 E starts a load", load_active(ks) AND NOT ks["OPRERR"]).
assert_true("the load shows verb 25 and noun 33", ks["VERB"] = 25 AND ks["NOUN"] = 33).
ld_type_keys(ks, "+00012E").
assert_true("after the first ENTR the load is still active", load_active(ks) AND COMMITS:LENGTH = 0).
ld_type_keys(ks, "+00034E+05678E").
assert_near("one commit after the third ENTR", COMMITS:LENGTH, 1, 0).
assert_true("the load is over", NOT load_active(ks)).
assert_near("commit noun", COMMITS[0][0], 33, 0).
assert_true("commit comps are 1 2 3", COMMITS[0][1][0] = 1 AND COMMITS[0][1][1] = 2 AND COMMITS[0][1][2] = 3).
assert_true("commit values are 12 34 5678", COMMITS[0][2][0] = 12 AND COMMITS[0][2][1] = 34 AND COMMITS[0][2][2] = 5678).
assert_near("the display goes to the monitor verb 16", ks["VERB"], 16, 0).

// ---- V21, V22, V23, V24 pick the registers ---------------------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+00007E").
assert_true("V21 loads only R1", COMMITS:LENGTH = 1 AND COMMITS[0][1]:LENGTH = 1 AND COMMITS[0][1][0] = 1 AND COMMITS[0][2][0] = 7).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V22N33E+00008E").
assert_true("V22 loads only R2", COMMITS[0][1][0] = 2 AND COMMITS[0][2][0] = 8).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V23N33E+00009E").
assert_true("V23 loads only R3", COMMITS[0][1][0] = 3 AND COMMITS[0][2][0] = 9).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V24N33E+00001E+00002E").
assert_true("V24 loads R1 and R2", COMMITS[0][1]:LENGTH = 2 AND COMMITS[0][1][0] = 1 AND COMMITS[0][1][1] = 2).

// ---- signs, ENTR on nothing, PRO, CLR ----------------------------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E-00034E").
ld_type_keys(ks, "E").
assert_true("ENTR on an empty buffer is OPR ERR and the load keeps waiting (PINBALL: a decimal load needs all five characters)", ks["OPRERR"] AND load_active(ks) AND COMMITS:LENGTH = 0).
ld_type_keys(ks, "PP").      // PRO skips R2, PRO skips R3: the load ends with only R1 keyed (an empty ENTR no longer skips a register)
assert_true("a minus sign gives a negative value", COMMITS[0][2][0] = -34).
assert_true("PRO keeps the old R2 and R3 (only R1 committed)", COMMITS[0][1]:LENGTH = 1 AND COMMITS[0][1][0] = 1 AND NOT load_active(ks)).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+123C+00044E").
assert_true("CLR empties the buffer before ENTR", COMMITS[0][2][0] = 44).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E-E").
assert_true("a sign with no digits and ENTR is OPR ERR and the load keeps waiting", ks["OPRERR"] AND load_active(ks) AND COMMITS:LENGTH = 0).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+25E").
assert_true("ENTR after fewer than five digits is OPR ERR, nothing is committed and the load waits (it is not read as 25)", ks["OPRERR"] AND load_active(ks) AND COMMITS:LENGTH = 0).
ld_type_keys(ks, "R").
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+25E").
ld_type_keys(ks, "000E").
assert_true("the missing digits can be keyed after the alarm (the buffer is kept) and 25000 is committed", COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 25000).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+00025E").
assert_true("five digits with leading zeros are accepted: 25", COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 25 AND NOT ks["OPRERR"]).

// ---- too many digits -------------------------------------------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+123456").
assert_true("a sixth digit is ignored with no alarm (PINBALL NUM: DSPCOUNT is negative, ENDOFJOB)", NOT ks["OPRERR"]).
ld_type_keys(ks, "E").
assert_true("the buffer kept five digits", COMMITS[0][2][0] = 12345).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+12-").
assert_true("a sign after digits is ignored with no alarm (PINBALL SIGNTEST: sign only at the first digit)", NOT ks["OPRERR"]).
ld_type_keys(ks, "345E").
assert_true("the ignored sign leaves the load as it was: +12345", COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 12345).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N33E+-00007E").
assert_true("a second sign is ignored (only the first of consecutive signs counts)", NOT ks["OPRERR"] AND COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 7).

// ---- digits without a sign: PINBALL reads them as octal, N33 and N81 are decimal only, so it alarms and recycles the load -------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E+00001E").
ld_type_keys(ks, "00002E").
assert_true("five digits with no sign on a decimal-only noun: OPR ERR, nothing committed, the load is still active", ks["OPRERR"] AND load_active(ks) AND COMMITS:LENGTH = 0).
ld_type_keys(ks, "+00007E+00008E+00009E").
assert_true("the load restarted at R1 (ALMCYCLE): the earlier +00001 is gone", COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 7 AND COMMITS[0][2][1] = 8 AND COMMITS[0][2][2] = 9).

// ---- abandoning a load changes nothing (Review Focus 3) --------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E+00012ER").
assert_true("RSET ends the load and commits nothing", NOT load_active(ks) AND COMMITS:LENGTH = 0 AND NOT ks["OPRERR"]).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E+00012EV34E").
assert_true("V34 ENTR ends the load, commits nothing", NOT load_active(ks) AND COMMITS:LENGTH = 0).
assert_true("V34 ENTR during a load does not end the DSKY (verb is the monitor, not 34)", ks["VERB"] = 16).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V34E").
assert_near("V34 ENTR with no load shows verb 34 (a running programme reads it as Terminate; the DSKY keeps running)", ks["VERB"], 34, 0).

// ---- refusals --------------------------------------------------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V21N60E").
assert_true("V21 on a noun with no load lights OPRERR and starts no load", ks["OPRERR"] AND NOT load_active(ks)).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V23N88E").
assert_true("V23 on a two-register noun lights OPRERR", ks["OPRERR"] AND NOT load_active(ks)).
LOCAL ks_novehicle IS keys_new(LIST(33), LIST(6, 21, 34), LIST(0)).
ld_type_keys(ks_novehicle, "V21N33E").
assert_true("a load with no vehicle set lights OPRERR", ks_novehicle["OPRERR"] AND NOT load_active(ks_novehicle)).

// ---- display while loading ------------------------------------------------------------------------------------------------
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E-12").
LOCAL shown IS load_shown(ks, fake_vehicle).
assert_near("the register being loaded is R1", shown["REG"], 1, 0).
assert_true("the keyed text is the sign and digits, left-aligned and not zero-padded", shown["TEXT"]:STARTSWITH("-12 ")).
ld_type_keys(ks, "345E").
LOCAL shown2 IS load_shown(ks, fake_vehicle).
assert_near("after ENTR the register being loaded is R2", shown2["REG"], 2, 0).
assert_true("after ENTR R1 keeps showing the keyed value (-12345)", shown2["DONE"]:LENGTH = 1 AND shown2["DONE"][0][0] = 1 AND shown2["DONE"][0][1] = "-12345").
ld_type_keys(ks, "+00007E").
LOCAL shown2b IS load_shown(ks, fake_vehicle).
assert_true("a small value is zero-padded to the register width when shown", shown2b["DONE"]:LENGTH = 2 AND shown2b["DONE"][1][1] = "+00007").

// ---- the LM's own load: N33 and N81 into its store -------------------------------------------------------------------------
SET LM_VEH TO LEXICON("STORE", store_new(lm_cells_for("A11"))).      // LM_VEH already exists (lm_vehicle.ks)
LOCAL lm_vault IS LM_VEH["STORE"].
LOCAL n33_zero IS noun_registers(33, LEXICON("VALID", FALSE)).
assert_true("N33 shows zeros before any load", n33_zero[0] = "+00000" AND n33_zero[2] = "+00000").
assert_true("lm_load_commit N33 R1 and R2", lm_load_commit(33, LIST(1, 2), LIST(3, 25)) = "").
assert_near("TIG is now 3 h 25 min", lm_store_get_tig(lm_vault), 3 * 3600 + 25 * 60, 0.01).
assert_true("lm_load_commit N33 R3 (12.34 s)", lm_load_commit(33, LIST(3), LIST(1234)) = "").
assert_near("TIG is 3 h 25 min 12.34 s", lm_store_get_tig(lm_vault), 3 * 3600 + 25 * 60 + 12.34, 0.01).
LOCAL n33_regs IS noun_registers(33, LEXICON("VALID", FALSE)).
assert_true("N33 registers show 3, 25, 1234", n33_regs[0] = "+00003" AND n33_regs[1] = "+00025" AND n33_regs[2] = "+01234").
assert_true("minutes above 59 are refused", lm_load_commit(33, LIST(2), LIST(60)) <> "").
assert_near("a refused N33 load leaves TIG alone", lm_store_get_tig(lm_vault), 3 * 3600 + 25 * 60 + 12.34, 0.01).
assert_true("a negative hour is refused", lm_load_commit(33, LIST(1), LIST(-1)) <> "").
assert_true("lm_load_commit N81 all three (tenths of ft/s)", lm_load_commit(81, LIST(1, 2, 3), LIST(-984, 0, 25)) = "").
LOCAL dv_now IS lm_store_get_dv(lm_vault).
assert_near("N81 R1 is -98.4 ft/s in m/s", dv_now:X, -98.4 * 0.3048, 0.001).
assert_near("N81 R3 is 2.5 ft/s in m/s", dv_now:Z, 2.5 * 0.3048, 0.001).
LOCAL n81_regs IS noun_registers(81, LEXICON("VALID", FALSE)).
assert_true("N81 registers show the tenths of ft/s", n81_regs[0] = "-00984" AND n81_regs[1] = "+00000" AND n81_regs[2] = "+00025").
assert_true("an unknown noun has no load", lm_load_commit(60, LIST(1), LIST(1)) <> "").

test_end().
