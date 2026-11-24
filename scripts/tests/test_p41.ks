// test_p41.ks -- pad test for P41, the RCS burn, and P47, the thrust monitor (lm/burn/lm_p41.ks), N83, N85 and the table entries. No flight: CTL_DRY is TRUE and the state is
// made up (the DOI case, as test_p40.ks; the Moon's gravity is zero in it, so the measured delta-V is the made-up push alone). The ship faces world +X with its top toward +Y.
//   RUNPATH("0:/tests/test_p41.ks").   Log: 0:/lm/logs/test_p41.log.
// Written in release 1.4 and not yet run in KSP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p41.log").
SET CTL_DRY TO TRUE.
LOCAL keep_thr IS ENG_THR_CONT.
SET ENG_THR_CONT TO "MAN".          // P41 must not care: no V50 N25 whatever the switch says
GLOBAL T41_V0 IS V(0, 0, 1628.5834302711191).

FUNCTION t41_state {
  PARAMETER now_ut, v_vec.
  RETURN LEXICON("R", V(1848520, 0, 0), "V", v_vec, "T", now_ut, "MASS", 15.2697, "THRUST", 46.71, "THRUST_NOW", 0, "MU", 0,
                 "BODY_OK", TRUE, "ALT_RADAR", 15000, "XNB", V(1, 0, 0)).
}
FUNCTION t41_keys {
  PARAMETER verb_no, noun_no.
  LOCAL key_state IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
  SET key_state["VERB"] TO verb_no.
  SET key_state["NOUN"] TO noun_no.
  RETURN key_state.
}
FUNCTION t41_clear {
  PARAMETER key_state.
  SET key_state["PRO"] TO FALSE.
  SET key_state["RECYCLE"] TO FALSE.
  SET key_state["TERMINATE"] TO FALSE.
  SET key_state["ENTER"] TO FALSE.
}
FUNCTION t41_xd {
  PARAMETER dv_mag.
  LOCAL dir_vec IS V(-9.8 * 0.3048, 0, -75.8 * 0.3048):NORMALIZED.
  RETURN LEXICON("DELVSIN", dir_vec * dv_mag, "RTIG", V(1848520, 0, 0), "VTIG", V(0, 0, 1628.5834302711191), "UT_TIG", 2500, "DELVSAB", dv_mag, "T0", 1100).
}
FUNCTION t41_vault {
  LOCAL vault IS store_new(lm_cells_for("A11")).
  lm_store_put_tig(vault, 1500).
  RETURN vault.
}
FUNCTION t41_start {
  PARAMETER dv_mag.
  RETURN p41_start(FALSE, t41_vault(), 1000, "A11", 2000, 0, t41_xd(dv_mag), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
}
FUNCTION t41_step {
  PARAMETER prog, now_ut, v_vec, key_state.
  LOCAL out IS p41_step(prog, t41_state(now_ut, v_vec), LEXICON("VALID", FALSE), key_state).
  t41_clear(key_state).
  RETURN out.
}
FUNCTION t41_regs {
  PARAMETER noun_no, out.
  LOCAL derived IS LEXICON("VALID", FALSE).
  FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
  RETURN noun_registers(noun_no, derived).
}
// t41_to_burn: R60 skipped with ENTR at UT now_ut; returns the output of the cycle that makes the sequence.
FUNCTION t41_to_burn {
  PARAMETER prog, now_ut.
  LOCAL ks IS t41_keys(16, 60).
  t41_step(prog, now_ut, T41_V0, ks).
  t41_step(prog, now_ut, T41_V0, ks).
  SET ks["VERB"] TO 50.
  SET ks["NOUN"] TO 18.
  SET ks["ENTER"] TO TRUE.
  RETURN t41_step(prog, now_ut, T41_V0, ks).
}

// ---- P41: refusals and checks ----
LOCAL refused IS p41_start(FALSE, t41_vault(), 1000, "A11", 2000, 0, FALSE, V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("P41 refuses before P30 has run", refused["REFUSED"]:CONTAINS("run P30 first")).
SET refused TO p41_start(FALSE, store_new(lm_cells_for("A11")), 1000, "A11", 2000, 0, t41_xd(23.1), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("P41 refuses when TIG is not loaded", refused["REFUSED"]:CONTAINS("TIG is not loaded")).
SET refused TO p41_start(FALSE, t41_vault(), 1000, "A11", 2000, 0, t41_xd(0), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("P41 refuses a delta-V of zero", refused["REFUSED"]:CONTAINS("zero")).
LOCAL pimu IS t41_start(23.1).
SET pimu["IMU_OK"] TO FALSE.
LOCAL out IS t41_step(pimu, 2000, T41_V0, t41_keys(16, 60)).
assert_true("R02: the orientation unknown gives alarm 220 and ends P41", out["ALARM"] = 220 AND out["ENDED"]).

// ---- P41: R60, the countdown ----
LOCAL pa IS t41_start(23.1).
LOCAL ks_a IS t41_keys(16, 60).
SET out TO t41_step(pa, 2000, T41_V0, ks_a).
assert_true("the first cycle does the checks and goes to R60", pa["PHASE"] = "R60").
SET out TO t41_step(pa, 2000.25, T41_V0, ks_a).
assert_true("R60 shows V50 N18 flashing", out["REQUEST"]["VERB"] = 50 AND out["REQUEST"]["NOUN"] = 18).
SET ks_a["VERB"] TO 50.
SET ks_a["NOUN"] TO 18.
SET ks_a["ENTER"] TO TRUE.
SET out TO t41_step(pa, 2000.5, T41_V0, ks_a).
assert_true("ENTR ends R60 and P41 goes straight on (no V50 N25 with ENG_THR_CONT MAN, no alarm 1706 check)", pa["PHASE"] = "BURN" AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
assert_near("TIG 500 s ahead is not slipped", pa["TIG"], 2500, 1e-6).
SET out TO t41_step(pa, 2001, T41_V0, ks_a).
assert_true("V16 N85 is set, steady (no request)", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 85 AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
// N85 in the ship's axes: facing +X, top +Y
LOCAL vg_world IS pa["VG"].
LOCAL regs IS t41_regs(85, out).
assert_true("N85 R1 is VG along the nose in ft/s (0.1)", regs[0] = fmt_reg(ms_to_fps(VDOT(vg_world, V(1, 0, 0))), 1)).
SET P40_DRY_FACING TO LOOKDIRUP(V(1, 0, 0), V(0, 0, 1)).
SET out TO t41_step(pa, 2002, T41_V0, ks_a).
SET regs TO t41_regs(85, out).
assert_true("rolled 90 degrees (top toward +Z): R3 is VG along world Z", regs[2] = fmt_reg(ms_to_fps(VDOT(vg_world, V(0, 0, 1))), 1)).
SET P40_DRY_FACING TO LOOKDIRUP(V(1, 0, 0), V(0, 1, 0)).
SET out TO t41_step(pa, 2465.2, T41_V0, ks_a).
assert_true("blank from TIG - 34.9", out["BLANK"]).
SET out TO t41_step(pa, 2475, T41_V0, ks_a).
assert_true("and back after TIG - 29.9", NOT out["BLANK"]).
assert_true("the terminal reads 0:25 at 25 s to go", out["STATUS"][0]:CONTAINS("TIG IN 0:25")).
SET out TO t41_step(pa, 2492.6, T41_V0, ks_a).
assert_true("no ullage in the P41 table: P41 has no ullage output at all", NOT out:HASKEY("ULLAGE") AND NOT pa["BB"]["TABLE"]["PROMPT"] AND NOT bb_has_ullage(pa["BB"]["TABLE"])).
SET out TO t41_step(pa, 2499, T41_V0, ks_a).
assert_true("still counting down before TIG: not flashing", NOT out["REQUEST"]:ISTYPE("Lexicon") AND pa["PHASE"] = "BURN").
assert_true("the terminal counts down to TIG (1 s to go: 0:01)", out["STATUS"][0]:CONTAINS("TIG IN 0:01")).
SET ks_a["PRO"] TO TRUE.
SET out TO t41_step(pa, 2499.5, T41_V0, ks_a).
assert_true("PRO before TIG is ignored and consumed", pa["PHASE"] = "BURN" AND NOT ks_a["PRO"] AND NOT out["ENDED"]).
SET out TO t41_step(pa, 2500, T41_V0, ks_a).
SET out TO t41_step(pa, 2500.25, T41_V0, ks_a).
assert_true("at TIG the display flashes V16 N85", pa["PHASE"] = "TIGNOW" AND out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 85).
assert_true("and the terminal says TIG has passed", out["STATUS"][0]:CONTAINS("TIG PASSED")).
assert_true("the engine was never lit", pa["IGN_T"] = -1).
// The pilot translates: 6 m/s along VG's direction over 6 s; VG falls by the same.
LOCAL u IS pa["VG"]:NORMALIZED.
LOCAL vg_before IS pa["VG"]:MAG.
LOCAL v_now IS T41_V0.
LOCAL t_now IS 2500.25.
LOCAL tick IS 0.
UNTIL tick >= 24 {
  SET t_now TO t_now + 0.25.
  SET v_now TO v_now + u * 1.0 * 0.25.
  SET out TO t41_step(pa, t_now, v_now, ks_a).
  SET tick TO tick + 1.
}
assert_true("VG falls as the pilot pushes (6 m/s in 6 s, seen in 2 s passes)", pa["VG"]:MAG < vg_before - 3.5 AND pa["VG"]:MAG > vg_before - 6.5).
assert_true("the velocity gained (N40 R3) counts it", pa["DV"] > 3.5).
SET ks_a["RECYCLE"] TO TRUE.
SET out TO t41_step(pa, t_now + 0.25, v_now, ks_a).
assert_true("V32 shows N85 again without ending", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 85 AND NOT out["ENDED"]).
SET ks_a["VERB"] TO 16.
SET ks_a["NOUN"] TO 85.
SET ks_a["ENTER"] TO TRUE.
SET out TO t41_step(pa, t_now + 0.5, v_now, ks_a).
assert_true("ENTR shows it again too", out["SET_VERB"] = 16 AND NOT out["ENDED"]).
SET ks_a["PRO"] TO TRUE.
SET out TO t41_step(pa, t_now + 0.75, v_now, ks_a).
assert_true("PRO ends P41", out["ENDED"]).
p41_end(pa).
assert_near("p41_end leaves the throttle at zero", CTL_THR, 0, 0).
LOCAL pb IS t41_start(23.1).
t41_to_burn(pb, 2000).
LOCAL ks_b IS t41_keys(16, 85).
t41_step(pb, 2500, T41_V0, ks_b).
t41_step(pb, 2500.25, T41_V0, ks_b).
SET ks_b["TERMINATE"] TO TRUE.
SET out TO t41_step(pb, 2500.5, T41_V0, ks_b).
assert_true("V34 at the TIG display ends P41", out["ENDED"]).

// ---- P41: the 1703 slip, and a V34 in the coast does nothing ----
LOCAL ps IS t41_start(23.1).
SET out TO t41_to_burn(ps, 2480).
assert_true("TIG 20 s ahead is slipped: alarm 1703", out["ALARM"] = 1703 AND ABS(ps["TIG"] - 2529.9) < 1e-6).
LOCAL pc IS t41_start(23.1).
t41_to_burn(pc, 2000).
LOCAL ks_c IS t41_keys(16, 85).
t41_step(pc, 2001, T41_V0, ks_c).
SET ks_c["TERMINATE"] TO TRUE.
SET out TO t41_step(pc, 2002, T41_V0, ks_c).
assert_true("V34 in the coast, with no request up, does nothing", NOT out["ENDED"]).

// ---- P47 ----
LOCAL pt IS p47_start(FALSE, 2000, V(0, 0, 0)).
LOCAL ks_t IS t41_keys(16, 83).
SET out TO p47_step(pt, t41_state(2000, T41_V0), LEXICON("VALID", FALSE), ks_t).
assert_true("P47: no display at the start", NOT out["REQUEST"]:ISTYPE("Lexicon") AND out["SET_VERB"] < 0 AND out["PROG_NO"] = 47).
SET out TO p47_step(pt, t41_state(2002, T41_V0 + V(0.9144, 0, 0)), LEXICON("VALID", FALSE), ks_t).
SET out TO p47_step(pt, t41_state(2010, T41_V0 + V(0.9144, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("P47: still no display 10 s in", NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET out TO p47_step(pt, t41_state(2020.25, T41_V0 + V(0.9144, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("P47: flashing V16 N83 about 20 s after selection", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 83 AND out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 83).
assert_true("3 ft/s along the nose shows as 3.0 in R1 (0.1 ft/s units: +00030)", t41_regs(83, out)[0] = "+00030").
assert_true("and nothing in R2 and R3", t41_regs(83, out)[1] = "+00000" AND t41_regs(83, out)[2] = "+00000").
SET ks_t["VERB"] TO 16.
SET ks_t["NOUN"] TO 83.
SET ks_t["ENTER"] TO TRUE.
SET out TO p47_step(pt, t41_state(2020.5, T41_V0 + V(0.9144, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("ENTR zeroes the count and shows it again", t41_regs(83, out)[0] = "+00000" AND out["SET_VERB"] = 16 AND NOT out["ENDED"]).
t41_clear(ks_t).                // the core clears the keys after each cycle; without this ENTR would repeat at the next pass
SET out TO p47_step(pt, t41_state(2024, T41_V0 + V(1.8288, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("the next pass counts the new push from zero (3 ft/s more)", t41_regs(83, out)[0] = "+00030").
SET ks_t["RECYCLE"] TO TRUE.
SET out TO p47_step(pt, t41_state(2024.25, T41_V0 + V(1.8288, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("V32 zeroes it too", t41_regs(83, out)[0] = "+00000").
SET ks_t["PRO"] TO TRUE.
SET out TO p47_step(pt, t41_state(2024.5, T41_V0 + V(1.8288, 0, 0)), LEXICON("VALID", FALSE), ks_t).
assert_true("PRO ends P47", out["ENDED"]).
LOCAL pt2 IS p47_start(FALSE, 2000, V(0, 0, 0)).
SET pt2["IMU_OK"] TO FALSE.
SET out TO p47_step(pt2, t41_state(2000, T41_V0), LEXICON("VALID", FALSE), t41_keys(16, 83)).
assert_true("P47: R02 alarm 220 ends it", out["ALARM"] = 220 AND out["ENDED"]).
LOCAL pt3 IS p47_start(FALSE, 2000, V(0, 0, 0)).
LOCAL ks_t3 IS t41_keys(16, 83).
p47_step(pt3, t41_state(2000, T41_V0), LEXICON("VALID", FALSE), ks_t3).
p47_step(pt3, t41_state(2021, T41_V0), LEXICON("VALID", FALSE), ks_t3).
SET ks_t3["TERMINATE"] TO TRUE.
SET out TO p47_step(pt3, t41_state(2021.25, T41_V0), LEXICON("VALID", FALSE), ks_t3).
assert_true("V34 ends P47", out["ENDED"]).
p47_end(pt3).

// ---- the tables ----
LOCAL vehicle_table IS lm_programme_table().
assert_true("P41 and P47 are in the programme table and selectable", vehicle_table["41"]["SELECTABLE"] AND vehicle_table["47"]["SELECTABLE"]).
assert_true("V37 can select 41 and 47", LM_PROGS:CONTAINS(41) AND LM_PROGS:CONTAINS(47)).
assert_true("N83 is a noun and shows zeros outside P47", LM_NOUNS:CONTAINS(83) AND noun_registers(83, LEXICON("VALID", FALSE))[0] = "+00000").

SET ENG_THR_CONT TO keep_thr.
test_end().
