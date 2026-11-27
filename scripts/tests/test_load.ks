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
  LOCAL ks IS keys_new(LIST(33, 88, 60), LIST(6, 16, 21, 22, 23, 24, 25, 32, 33, 34, 37), LIST(0)).
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
assert_true("RSET leaves the load running and commits nothing (Review Focus 4)", load_active(ks) AND COMMITS:LENGTH = 0 AND NOT ks["OPRERR"]).
ld_type_keys(ks, "V34E").
assert_true("V34 ENTR then ends it", NOT load_active(ks) AND COMMITS:LENGTH = 0).
SET ks TO ld_fresh_keys().
ld_type_keys(ks, "V25N33E+00012EV33E").
assert_true("V33 ENTR during a load acts as PRO: R2 is left as it was and the load goes on, no OPR ERR", load_active(ks) AND NOT ks["OPRERR"] AND ks["VERB"] = 25 AND COMMITS:LENGTH = 0).
ld_type_keys(ks, "V33E").
assert_true("V33 ENTR on the last register ends the load and commits only R1", NOT load_active(ks) AND COMMITS:LENGTH = 1 AND COMMITS[0][2][0] = 12).
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

// ---- N76, the ascent targets (release 1.5): horizontal and radial speed in tenths of ft/s, cross-range in tenths of nm ----------
SET ks TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
SET ks["VEHICLE"] TO LEXICON("LOADS", LM_LOADS, "LOAD_COMMIT", lm_load_commit@).
ld_type_keys(ks, "V25N76E+55349E+00322E+00017E").
assert_true("V25 N76 is accepted", NOT ks["OPRERR"] AND NOT load_active(ks)).
LOCAL n76_loaded IS lm_store_get_asc(lm_vault).
assert_near("N76 R1 is 5534.9 ft/s", n76_loaded["ZDOTD"], 5534.9 * 0.3048, 0.001).
assert_near("N76 R2 is 32.2 ft/s", n76_loaded["RDOTD"], 32.2 * 0.3048, 0.001).
assert_near("N76 R3 is 1.7 nm", n76_loaded["XRANGE"], 1.7 * 1852, 4).
LOCAL n76_regs IS noun_registers(76, LEXICON("VALID", FALSE)).
assert_true("N76 registers show the keyed values", n76_regs[0] = "+55349" AND n76_regs[1] = "+00322" AND n76_regs[2] = "+00017").
ld_type_keys(ks, "V22N76E-00050E").
SET n76_regs TO noun_registers(76, LEXICON("VALID", FALSE)).
assert_true("V22 N76 changes only R2", n76_regs[0] = "+55349" AND n76_regs[1] = "-00050" AND n76_regs[2] = "+00017").

// ---- the ascent and orbit nouns 74, 94 and 44 --------------------------------------------------------------------------------
LOCAL n74_regs IS noun_registers(74, LEXICON("VALID", FALSE, "TTOGO", 125, "P12_YAW", 359.99, "P12_PITCH", 310)).
assert_true("N74 is time from ignition, yaw and pitch", n74_regs[0] = "-02 05" AND n74_regs[1] = "+35999" AND n74_regs[2] = "+31000").
SET n74_regs TO noun_registers(74, LEXICON("VALID", FALSE)).
assert_true("N74 shows zeros outside P12", n74_regs[0] = "+00 00" AND n74_regs[1] = "+00000").
// A valid navigation state always carries VHORIZ, ABVEL, HDOT and HCALC (lm_nav.ks), and noun_registers reads all four.
LOCAL n94_nav IS LEXICON("VALID", TRUE, "P40_VGB", LIST(100, 0, 0), "VHORIZ", 0, "ABVEL", 0, "HDOT", 10, "HCALC", 1000).
LOCAL n94_regs IS noun_registers(94, n94_nav).
assert_true("N94 is VG body X, altitude rate, altitude", n94_regs[0] = "+03281" AND n94_regs[1] = "+00328" AND n94_regs[2] = "+03281").
assert_true("J shows the same N94", j_noun_registers(94, n94_nav)[0] = "+03281").
assert_true("N94 with no navigation is blank", noun_registers(94, LEXICON("VALID", FALSE))[0] = NA).
LOCAL n44_regs IS noun_registers(44, LEXICON("VALID", FALSE, "N44", LIST(83340, -1000000, -1))).
assert_true("N44 is apolune, perilune and -59 59 for no free-fall time", n44_regs[0] = "+00450" AND n44_regs[1] = "-05400" AND n44_regs[2] = "-59 59").
SET n44_regs TO noun_registers(44, LEXICON("VALID", FALSE, "N44", LIST(111120, 27780, 754))).
assert_true("N44 shows the free-fall time counting down", n44_regs[2] = "-12 34").
assert_true("N44 shows zeros before V82", noun_registers(44, LEXICON("VALID", FALSE))[1] = "+00000").

// ---- the rendezvous nouns (release 1.5): times N11, N13, N37, then N55, N75, N81 as N82, and N45 --------------------------
SET LM_VEH TO LEXICON("STORE", store_new(lm_cells_for("A11"))).
SET lm_vault TO LM_VEH["STORE"].
LOCAL ld_blank IS LEXICON("VALID", FALSE).
assert_true("the rendezvous nouns are in the noun table", LM_NOUNS:CONTAINS(11) AND LM_NOUNS:CONTAINS(13) AND LM_NOUNS:CONTAINS(37) AND LM_NOUNS:CONTAINS(55) AND LM_NOUNS:CONTAINS(75) AND LM_NOUNS:CONTAINS(82)).
assert_true("N11 shows zeros and TCSI reads -1 before any load", noun_registers(11, ld_blank)[2] = "+00000" AND lm_store_get_time(lm_vault, "TCSI") = -1).
ld_type_keys(ks, "V25N11E+00001E+00002E+00345E").
assert_true("V25 N11 is accepted", NOT ks["OPRERR"] AND NOT load_active(ks)).
assert_near("TCSI is 1 h 2 min 3.45 s", lm_store_get_time(lm_vault, "TCSI"), 3600 + 120 + 3.45, 0.01).
LOCAL n11_regs IS noun_registers(11, ld_blank).
assert_true("N11 registers show 1, 2, 345", n11_regs[0] = "+00001" AND n11_regs[1] = "+00002" AND n11_regs[2] = "+00345").
assert_true("N11 leaves N33 alone", lm_store_get_tig(lm_vault) = -1).
LOCAL n11_refusal IS lm_load_commit(11, LIST(2), LIST(60)).
assert_true("N11 minutes 60 is refused, naming N11", n11_refusal:STARTSWITH("N11 takes")).
assert_near("the refused load leaves TCSI alone", lm_store_get_time(lm_vault, "TCSI"), 3723.45, 0.01).
assert_true("N13 loads TCDH", lm_load_commit(13, LIST(1, 2, 3), LIST(2, 0, 0)) = "").
assert_near("TCDH is 2 h", lm_store_get_time(lm_vault, "TCDH"), 7200, 0.01).
assert_true("N37 loads TTPI", lm_load_commit(37, LIST(1, 2, 3), LIST(3, 0, 0)) = "").
assert_near("TTPI is 3 h", lm_store_get_time(lm_vault, "TTPI"), 10800, 0.01).
assert_true("N13 and N37 registers show the hours", noun_registers(13, ld_blank)[0] = "+00002" AND noun_registers(37, ld_blank)[0] = "+00003").

LOCAL n55_regs IS noun_registers(55, ld_blank).
assert_true("N55 shows zeros before any load", n55_regs[0] = "+00000" AND n55_regs[1] = "+00000" AND n55_regs[2] = "+00000").
ld_type_keys(ks, "V22N55E+02660E").
SET n55_regs TO noun_registers(55, ld_blank).
assert_true("V22 N55 alone shows the elevation 26.60", n55_regs[0] = "+00000" AND n55_regs[1] = "+02660" AND n55_regs[2] = "+00000").
LOCAL n55_vals IS lm_store_get_n55(lm_vault).
assert_true("V22 N55 leaves NN and the central angle unloaded", n55_vals["NN"] = -1 AND n55_vals["CENTANG"] = -1).
ld_type_keys(ks, "V25N55E+00001E+02000E+13000E").
SET n55_vals TO lm_store_get_n55(lm_vault).
assert_near("N55 NN", n55_vals["NN"], 1, 0).
assert_near("N55 elevation", n55_vals["ELEV"], 20, 0.001).
assert_near("N55 central angle", n55_vals["CENTANG"], 130, 0.001).
ld_type_keys(ks, "V22N55E+02660E").
SET n55_regs TO noun_registers(55, ld_blank).
assert_true("V22 N55 changes only the elevation", n55_regs[0] = "+00001" AND n55_regs[1] = "+02660" AND n55_regs[2] = "+13000").
assert_true("NN 100 is refused", lm_load_commit(55, LIST(1), LIST(100)) <> "").
assert_true("a negative angle is refused", lm_load_commit(55, LIST(2), LIST(-1)) <> "").
assert_true("an angle of 360 is refused", lm_load_commit(55, LIST(3), LIST(36000)) <> "").
assert_true("NN 99 and 359.99 are accepted", lm_load_commit(55, LIST(1, 3), LIST(99, 35999)) = "").
SET n55_regs TO noun_registers(55, ld_blank).
assert_true("the refused N55 loads changed nothing, the good one did", n55_regs[0] = "+00099" AND n55_regs[1] = "+02660" AND n55_regs[2] = "+35999").

LOCAL n75_regs IS noun_registers(75, LEXICON("VALID", FALSE, "RN_DH", 27760.41, "RN_T12", 3485.8, "RN_T23", -65)).
assert_true("N75 is height difference, CSI to CDH and CDH to TPI", n75_regs[0] = "+00150" AND n75_regs[1] = "+58 06" AND n75_regs[2] = "-01 05").
SET n75_regs TO noun_registers(75, ld_blank).
assert_true("N75 shows zeros with nothing supplied", n75_regs[0] = "+00000" AND n75_regs[1] = "+00 00" AND n75_regs[2] = "+00 00").
lm_load_commit(81, LIST(1, 2, 3), LIST(504, 0, -12)).
LOCAL n82_regs IS noun_registers(82, ld_blank).
assert_true("N82 shows the stored delta-v as N81", n82_regs[0] = "+00504" AND n82_regs[1] = "+00000" AND n82_regs[2] = "-00012").
assert_true("N82 has no load", NOT LM_LOADS:HASKEY("82") AND lm_load_commit(82, LIST(1), LIST(1)) <> "").
LOCAL n45_regs IS noun_registers(45, LEXICON("VALID", FALSE, "P30_TTOGO", 125, "P30_MGA", 12.5)).
assert_true("N45 needs only the time to go and the gimbal angle", n45_regs[0] = "+00000" AND n45_regs[1] = "+02 05" AND n45_regs[2] = "+01250").
SET n45_regs TO noun_registers(45, LEXICON("VALID", FALSE, "P30_TTOGO", 125, "P30_MGA", -0.01)).
assert_true("N45 shows -00.01 for a gimbal angle not yet computed", n45_regs[2] = "-00001").

// ---- N52, N58, N59 (P34 and P35) and the intercept time cell ----
LOCAL n52_regs IS noun_registers(52, LEXICON("VALID", FALSE, "RN_CENT", 131.67)).
assert_true("N52 is the central angle, R2 and R3 blank", n52_regs[0] = "+13167" AND n52_regs[1] = NA AND n52_regs[2] = NA).
LOCAL n58_regs IS noun_registers(58, LEXICON("VALID", FALSE, "RN_PERI", 82904.88, "RN_DVTPI", 7.48291, "RN_DVTPF", 9.61701)).
assert_true("N58 is perilune, TPI delta-V and intercept delta-V", n58_regs[0] = "+00448" AND n58_regs[1] = "+00246" AND n58_regs[2] = "+00316").
LOCAL n59_regs IS noun_registers(59, LEXICON("VALID", FALSE, "RN_DVLOS", V(7.4829, -0.3048, 0.6096))).
assert_true("N59 is the delta-V along the sight line, right and down", n59_regs[0] = "+00246" AND n59_regs[1] = "-00010" AND n59_regs[2] = "+00020").
assert_true("N52, N58 and N59 show zeros with nothing supplied", noun_registers(52, ld_blank)[0] = "+00000" AND noun_registers(58, ld_blank)[1] = "+00000" AND noun_registers(59, ld_blank)[2] = "+00000").
assert_true("none of them loads", NOT LM_LOADS:HASKEY("52") AND NOT LM_LOADS:HASKEY("58") AND NOT LM_LOADS:HASKEY("59")).
LOCAL tp_vault IS store_new(lm_cells_for("J")).
assert_near("the intercept time is not loaded at first", lm_store_get_time(tp_vault, "TPASS4"), -1, 0).
lm_store_put_time(tp_vault, "TPASS4", 8123.45).
assert_near("the intercept time cell round trip", lm_store_get_time(tp_vault, "TPASS4"), 8123.45, 0.005).

// ---- stage 3: N12 (octal), N16, N54, N90, the mark count in N45 and the no-effect verbs ------------------------------------
SET LM_VEH TO LEXICON("STORE", store_new(lm_cells_for("A11"))).
SET ks TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
SET ks["VEHICLE"] TO LEXICON("LOADS", LM_LOADS, "LOAD_COMMIT", lm_load_commit@).
ld_type_keys(ks, "V24N12E3E1E").
assert_true("V24 N12 loads two octal registers", NOT ks["OPRERR"] AND LM_VEH["N12"][0] = 3 AND LM_VEH["N12"][1] = 1).
ld_type_keys(ks, "V22N12E2E").
assert_true("V22 N12 changes only the option", LM_VEH["N12"][0] = 3 AND LM_VEH["N12"][1] = 2).
LOCAL n12_regs IS noun_registers(12, LEXICON("VALID", FALSE, "N12", LM_VEH["N12"])).
assert_true("N12 shows five octal digits, R3 blank", n12_regs[0] = " 00003" AND n12_regs[1] = " 00002" AND n12_regs[2] = NA).
ld_type_keys(ks, "V25N16E+00001E+00002E+00345E").
assert_true("V25 N16 is accepted", NOT ks["OPRERR"] AND NOT load_active(ks)).
assert_near("N16 holds 1 h 2 min 3.45 s", LM_VEH["N16"], 3723.45, 0.01).
LOCAL n16_regs IS noun_registers(16, LEXICON("VALID", FALSE, "N16", LM_VEH["N16"])).
assert_true("N16 shows hours, minutes and seconds", n16_regs[0] = "+00001" AND n16_regs[1] = "+00002" AND n16_regs[2] = "+00345").
assert_true("N16 refuses minutes above 59", lm_load_commit(16, LIST(2), LIST(60)) <> "" AND ABS(LM_VEH["N16"] - 3723.45) < 0.01).
assert_true("N16 shows zeros without a time", noun_registers(16, LEXICON("VALID", FALSE))[2] = "+00000").
LOCAL n54_regs IS noun_registers(54, LEXICON("VALID", FALSE, "N54", LIST(1852, -3.048, 26.6))).
assert_true("N54 is range in nm, rate in ft/s and theta", n54_regs[0] = fmt_reg(1.00, 2) AND n54_regs[1] = fmt_reg(-10.0, 1) AND n54_regs[2] = fmt_reg(26.6, 2)).
LOCAL n90_regs IS noun_registers(90, LEXICON("VALID", FALSE, "N90", LIST(1852, -3.048, 26.6))).
assert_true("N90 is Y in nm, Y rate in ft/s and psi", n90_regs[0] = fmt_reg(1.00, 2) AND n90_regs[1] = fmt_reg(-10.0, 1) AND n90_regs[2] = fmt_reg(26.6, 2)).
assert_true("N54 and N90 show zeros without values", noun_registers(54, LEXICON("VALID", FALSE))[0] = "+00000" AND noun_registers(90, LEXICON("VALID", FALSE))[2] = "+00000").
assert_true("N45 R1 is the mark count", noun_registers(45, LEXICON("VALID", FALSE, "MARKS", 7))[0] = fmt_reg(7, 0)).
assert_true("N45 R1 is 0 without one", noun_registers(45, LEXICON("VALID", FALSE))[0] = "+00000").
assert_true("the stage 3 nouns are in the noun table", LM_NOUNS:CONTAINS(12) AND LM_NOUNS:CONTAINS(16) AND LM_NOUNS:CONTAINS(54) AND LM_NOUNS:CONTAINS(90)).
LOCAL stage3_verbs IS lm_verbs_for("A11").
assert_true("V04 and the no-effect verbs are accepted", stage3_verbs:CONTAINS(4) AND stage3_verbs:CONTAINS(76) AND stage3_verbs:CONTAINS(80) AND stage3_verbs:CONTAINS(81) AND stage3_verbs:CONTAINS(95)).

// ---- the clock on the DSKY log's lines ----
assert_true("lm_clock_text: h:mm:ss", lm_clock_text(3723.4) = "1:02:03").
assert_true("lm_clock_text: zero, and never negative", lm_clock_text(0) = "0:00:00" AND lm_clock_text(-5) = "0:00:00").

test_end().
