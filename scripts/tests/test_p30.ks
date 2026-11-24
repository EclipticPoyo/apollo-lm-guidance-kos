// test_p30.ks -- pad test for P30, external delta-V (lm/burn/lm_p30.ks), N42, N45 and the P30 table entry. No ship access: the state at TIG comes from a fake
// predict delegate (the DOI case of reference_burn.py: a circular orbit 60 nmi up, r along +X, v along +Z).
//   RUNPATH("0:/tests/test_p30.ks").   Log: 0:/lm/logs/test_p30.log.
// Expected numbers: python scripts/tests/reference_burn.py (apsides of the DOI orbit: apogee 111230.26 m, perigee 9723.44 m, delta-V 76.43 ft/s).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p30.log").

GLOBAL T30_R IS V(1848520, 0, 0).
GLOBAL T30_V IS V(0, 0, 1628.5834302711191).
GLOBAL T30_CLOCK_ZERO IS 1000.
GLOBAL T30_TIG_S IS 1500.             // seconds from the clock zero: TIG is UT 2500
GLOBAL T30_NOW IS 1100.

FUNCTION t30_predict {
  PARAMETER t_ut.
  RETURN LEXICON("R", T30_R, "V", T30_V, "MU", 4.9028e12, "RADIUS", 1737400).
}

// t30_vault: a store with TIG and/or the DOI delta-V (real DOI: -75.8 ft/s along track, 0 across, +9.8 ft/s in Z, local vertical axes) loaded.
FUNCTION t30_vault {
  PARAMETER tig_s, with_dv.
  LOCAL vault IS store_new(lm_cells_for("A11")).
  IF tig_s >= 0 { lm_store_put_tig(vault, tig_s). }
  IF with_dv { lm_store_put_dv(vault, V(-75.8 * 0.3048, 0, 9.8 * 0.3048)). }
  RETURN vault.
}

FUNCTION t30_start {
  PARAMETER vault, profile.
  RETURN p30_start(FALSE, vault, T30_CLOCK_ZERO, profile, T30_NOW, t30_predict@).
}

// t30_regs: the noun's registers with the step's EXTRA values merged in, as the core does.
FUNCTION t30_regs {
  PARAMETER noun_no, out.
  LOCAL derived IS LEXICON("VALID", FALSE).
  FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
  RETURN noun_registers(noun_no, derived).
}

// ---- refusals ----
LOCAL refused IS t30_start(t30_vault(-1, TRUE), "A11").
assert_true("refuses when TIG is not loaded", refused["REFUSED"]:CONTAINS("TIG is not loaded")).
SET refused TO t30_start(t30_vault(T30_TIG_S, FALSE), "A11").
assert_true("refuses when the delta-V is not loaded", refused["REFUSED"]:CONTAINS("the delta-V is not loaded")).
SET refused TO t30_start(t30_vault(50, TRUE), "A11").
assert_true("refuses when TIG is in the past", refused["REFUSED"]:CONTAINS("TIG has passed")).
assert_true("a good store starts", t30_start(t30_vault(T30_TIG_S, TRUE), "A11")["REFUSED"] = "").

// ---- the display sequence, Apollo 11 profile ----
SET LM_VEH["XDELV"] TO FALSE.
LOCAL ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL prog IS t30_start(t30_vault(T30_TIG_S, TRUE), "A11").
LOCAL out IS p30_step(prog, ks).
assert_true("first cycle shows V06 N33", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 33).
assert_true("and requests it", out["REQUEST"]:ISTYPE("Lexicon") AND out["REQUEST"]["VERB"] = 6 AND out["REQUEST"]["NOUN"] = 33).
assert_near("PROG shows 30", out["PROG_NO"], 30, 0).
SET out TO p30_step(prog, ks).
assert_true("the request stays, the display is not set again", out["SET_VERB"] < 0 AND out["REQUEST"]:ISTYPE("Lexicon")).
SET ks["RECYCLE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("V32 at N33 shows it again without advancing", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 33 AND NOT out["ENDED"]).
SET ks["RECYCLE"] TO FALSE.
SET ks["VERB"] TO 6.
SET ks["NOUN"] TO 33.
SET ks["ENTER"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("ENTR answering the displayed N33 shows it again", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 33).
SET ks["VERB"] TO 21.
SET out TO p30_step(prog, ks).
assert_true("an ENTR that ends a keyed verb does not redisplay", out["SET_VERB"] < 0 AND NOT out["ENDED"]).
SET ks["ENTER"] TO FALSE.
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("PRO at N33 shows V06 N81", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 81 AND NOT out["ENDED"]).
assert_true("PRO is consumed", NOT ks["PRO"]).
SET ks["RECYCLE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("V32 at N81 shows N81 again", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 81).
SET ks["RECYCLE"] TO FALSE.
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("PRO at N81 shows V06 N42", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 42 AND NOT out["ENDED"]).
assert_near("N42 apogee altitude (m)", out["EXTRA"]["P30_APO"], 111230.261, 0.5).
assert_near("N42 perigee altitude (m)", out["EXTRA"]["P30_PERI"], 9723.441, 0.5).
assert_near("N42 delta-V magnitude (m/s)", out["EXTRA"]["P30_DV"], 76.43088381 / 3.280839895, 1e-3).
LOCAL regs IS t30_regs(42, out).
assert_true("N42 R1 apogee 60.1 nm", regs[0] = "+00601").
assert_true("N42 R2 perigee 5.3 nm", regs[1] = "+00053").
assert_true("N42 R3 delta-V 76.4 ft/s", regs[2] = "+00764").
assert_true("099: XDELVFLG is not set while N42 is up", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET ks["TERMINATE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("V34 at N42 ends P30", out["ENDED"] AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET ks["TERMINATE"] TO FALSE.
assert_true("099: V34 at N42 leaves XDELVFLG clear", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).

// again to the end: PRO at N42 sets the flag, N45 shows, PRO ends
SET LM_VEH["XDELV"] TO FALSE.
SET prog TO t30_start(t30_vault(T30_TIG_S, TRUE), "A11").
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
SET prog["NOW_UT"] TO 2440.
SET out TO p30_step(prog, ks).
assert_true("PRO at N42 shows V16 N45", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 45).
assert_true("N45 is requested", out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 45).
assert_true("099: XDELVFLG is set after N42", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
LOCAL xd IS LM_VEH["XDELV"].
LOCAL expect_dv IS plan_lv_to_dv(LIST(-75.8 * 0.3048, 0, 9.8 * 0.3048), T30_R, T30_V).
assert_vec("XDELV DELVSIN is plan_lv_to_dv of the loaded delta-V", xd["DELVSIN"], expect_dv, 1e-3).
assert_vec("XDELV DELVSIN for the DOI: -9.8 ft/s up, -75.8 ft/s along", xd["DELVSIN"], V(-9.8 * 0.3048, 0, -75.8 * 0.3048), 1e-3).
assert_vec("XDELV RTIG", xd["RTIG"], T30_R, 1e-9).
assert_vec("XDELV VTIG", xd["VTIG"], T30_V, 1e-9).
assert_near("XDELV UT_TIG", xd["UT_TIG"], 2500, 1e-6).
assert_near("XDELV DELVSAB", xd["DELVSAB"], 76.43088381 / 3.280839895, 1e-3).
SET regs TO t30_regs(45, out).
assert_true("N45 R1 marks 0", regs[0] = "+00000").
assert_true("N45 R2 time to go 60 s is 01 00", regs[1] = "+01 00").
assert_true("N45 R3 middle gimbal angle 0 for an in-plane burn", regs[2] = "+00000").
SET prog["NOW_UT"] TO 2470.
SET out TO p30_step(prog, ks).
assert_true("N45 counts down: 30 s", t30_regs(45, out)[1] = "+00 30").
SET ks["RECYCLE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("V32 at N45 shows it again", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 45 AND NOT out["ENDED"]).
SET ks["RECYCLE"] TO FALSE.
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("PRO at N45 ends P30", out["ENDED"]).

// ---- J profile: XDELVFLG is set before N42 ----
SET LM_VEH["XDELV"] TO FALSE.
SET prog TO t30_start(t30_vault(T30_TIG_S, TRUE), "J").
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("210: XDELVFLG is set when N42 shows", LM_VEH["XDELV"]:ISTYPE("Lexicon") AND out["SET_NOUN"] = 42).
SET ks["TERMINATE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("210: V34 at N42 leaves XDELVFLG set", out["ENDED"] AND LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET ks["TERMINATE"] TO FALSE.

// ---- V34 at N33 and N81 ends it with nothing set ----
SET LM_VEH["XDELV"] TO FALSE.
SET prog TO t30_start(t30_vault(T30_TIG_S, TRUE), "A11").
p30_step(prog, ks).
SET ks["TERMINATE"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("V34 at N33 ends P30", out["ENDED"] AND NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET ks["TERMINATE"] TO FALSE.

// ---- TIG passes while the displays are up ----
SET prog TO t30_start(t30_vault(T30_TIG_S, TRUE), "A11").
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET prog["NOW_UT"] TO 2600.
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("TIG passed before N81 was answered: ends with a message", out["ENDED"] AND out["MSG"]:CONTAINS("TIG has passed")).

// ---- a delta-V out of plane: the middle gimbal angle ----
LOCAL vault_y IS store_new(lm_cells_for("A11")).
lm_store_put_tig(vault_y, T30_TIG_S).
lm_store_put_dv(vault_y, V(-23.1, 1.0, 2.99)).
SET prog TO p30_start(FALSE, vault_y, T30_CLOCK_ZERO, "A11", T30_NOW, t30_predict@).
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
LOCAL dv_y IS plan_lv_to_dv(LIST(-23.1, 1.0, 2.99), T30_R, T30_V).
LOCAL expect_mga IS ARCSIN(VDOT(dv_y:NORMALIZED, VCRS(T30_R, T30_V):NORMALIZED)).
IF expect_mga < 0 { SET expect_mga TO expect_mga + 360. }
assert_near("MGA is arcsin(burn direction . orbit normal), plus 360 when negative", out["EXTRA"]["P30_MGA"], expect_mga, 1e-3).
assert_true("an out-of-plane delta-V gives a non-zero MGA", out["EXTRA"]["P30_MGA"] > 0.1).

// ---- zero delta-V: completes, shows zeros, no NaN ----
LOCAL vault_z IS store_new(lm_cells_for("A11")).
lm_store_put_tig(vault_z, T30_TIG_S).
lm_store_put_dv(vault_z, V(0, 0, 0)).
SET prog TO p30_start(FALSE, vault_z, T30_CLOCK_ZERO, "A11", T30_NOW, t30_predict@).
assert_true("a zero delta-V is loaded, so P30 starts", prog["REFUSED"] = "").
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
SET ks["PRO"] TO TRUE.
SET out TO p30_step(prog, ks).
assert_true("zero delta-V reaches N42", out["SET_NOUN"] = 42 AND NOT out["ENDED"]).
assert_near("zero delta-V: magnitude 0", out["EXTRA"]["P30_DV"], 0, 0).
assert_near("zero delta-V: MGA 0", out["EXTRA"]["P30_MGA"], 0, 0).
assert_near("zero delta-V: apogee is the present orbit (111120 m)", out["EXTRA"]["P30_APO"], 111120, 1).
assert_near("zero delta-V: perigee is the present orbit", out["EXTRA"]["P30_PERI"], 111120, 1).
assert_true("zero delta-V: no NaN in the apsides", out["EXTRA"]["P30_APO"] = out["EXTRA"]["P30_APO"] AND out["EXTRA"]["P30_PERI"] = out["EXTRA"]["P30_PERI"]).
SET regs TO t30_regs(42, out).
assert_true("zero delta-V: N42 R3 is +00000", regs[2] = "+00000").
SET LM_VEH["XDELV"] TO FALSE.
SET ks["PRO"] TO TRUE.
p30_step(prog, ks).
assert_true("zero delta-V: XDELV is set with a zero DELVSAB and a finite DELVSIN", LM_VEH["XDELV"]:ISTYPE("Lexicon") AND LM_VEH["XDELV"]["DELVSAB"] = 0 AND LM_VEH["XDELV"]["DELVSIN"]:MAG = 0).

// ---- N42 and N45 outside P30 show zeros ----
SET regs TO noun_registers(42, LEXICON("VALID", FALSE)).
assert_true("N42 outside P30 shows zeros", regs[0] = "+00000" AND regs[1] = "+00000" AND regs[2] = "+00000").
SET regs TO noun_registers(45, LEXICON("VALID", FALSE)).
assert_true("N45 outside P30 shows zeros", regs[0] = "+00000" AND regs[1] = "+00 00" AND regs[2] = "+00000").

// ---- the table ----
LOCAL table30 IS lm_programme_table().
assert_true("P30 is in the table and selectable", table30:HASKEY("30") AND table30["30"]["SELECTABLE"]).
assert_true("V37 can select P30", LM_PROGS:CONTAINS(30)).
assert_true("N42 and N45 are in the noun table", LM_NOUNS:CONTAINS(42) AND LM_NOUNS:CONTAINS(45)).
assert_near("P30 hands over to nothing", table30["30"]["NEXT"], -1, 0).

test_end().
