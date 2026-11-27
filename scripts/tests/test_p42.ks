// test_p42.ks -- pad test for P42, the ascent engine burn (lm/burn/lm_p40.ks), its sequence table and table entry. No flight: CTL_DRY is TRUE and the
// states are made up (no gravity, so the measured delta-V is the made-up push alone). The clock zero is UT 1000 and TIG 7000 s (UT 8000).
//   RUNPATH("0:/tests/test_p42.ks").   Log: 0:/lm/logs/test_p42.log. S40.13 numbers: python scripts/tests/reference_burn.py

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p42.log").
SET CTL_DRY TO TRUE.
LOCAL t42_keep_thr IS ENG_THR_CONT.
SET ENG_THR_CONT TO "MAN".          // P42 must not care: the ascent engine has no throttle
GLOBAL T42_V0 IS V(0, 0, 1628.5834302711191).
GLOBAL T42_AX IS LEXICON("P", V(1, 0, 0), "N", V(0, 1, 0)).

FUNCTION t42_state {
  PARAMETER now_ut, gained.
  RETURN LEXICON("R", V(1848520, 0, 0), "V", T42_V0 + V(0, 0, gained), "T", now_ut, "MASS", 4.7, "THRUST", 15.57, "THRUST_NOW", 0, "MU", 0,
                 "BODY_OK", TRUE, "ALT_RADAR", 80000, "XNB", V(1, 0, 0), "AX", T42_AX).
}
FUNCTION t42_xd {
  PARAMETER dv_mag.
  RETURN LEXICON("DELVSIN", V(0, 0, dv_mag), "RTIG", V(1848520, 0, 0), "VTIG", T42_V0, "UT_TIG", 8000, "DELVSAB", dv_mag, "AX0", T42_AX).
}
FUNCTION t42_start {
  PARAMETER profile, dv_mag, attached.
  LOCAL vault IS store_new(lm_cells_for(profile)).
  lm_store_put_tig(vault, 7000).
  RETURN p42_start(FALSE, vault, 1000, profile, 7500, 0, 15570, t42_xd(dv_mag), V(1, 0, 0), V(0, 1, 0), attached).
}
FUNCTION t42_keys { RETURN keys_new(LM_NOUNS, LM_VERBS, LM_PROGS). }
// t42_step: one cycle; the answer "NONE", "PRO", "ENTR" (to V50 N18) or "V34", cleared afterwards.
FUNCTION t42_step {
  PARAMETER prog, now_ut, gained, key_state, answer.
  SET key_state["PRO"] TO answer = "PRO".
  SET key_state["TERMINATE"] TO answer = "V34".
  SET key_state["ENTER"] TO answer = "ENTR".
  IF answer = "ENTR" { SET key_state["VERB"] TO 50. SET key_state["NOUN"] TO 18. }
  LOCAL out IS p40_step(prog, t42_state(now_ut, gained), LEXICON("VALID", FALSE), key_state).
  SET key_state["PRO"] TO FALSE.
  SET key_state["TERMINATE"] TO FALSE.
  SET key_state["ENTER"] TO FALSE.
  RETURN out.
}
// t42_to_burn: R60 skipped, into the countdown.
FUNCTION t42_to_burn {
  PARAMETER prog, key_state.
  t42_step(prog, 7500, 0, key_state, "NONE").
  t42_step(prog, 7500.5, 0, key_state, "NONE").
  t42_step(prog, 7501, 0, key_state, "ENTR").
  RETURN t42_step(prog, 7501.5, 0, key_state, "NONE").
}
// t42_burn: PRO at the prompt, ignition at TIG, then a push of 3.3 m/s^2 along +Z until the programme leaves the BURN phase or 15 s pass.
// Returns LEXICON("OFF", seconds from ignition at the cutoff or -1, "VG", the velocity to be gained then).
FUNCTION t42_burn {
  PARAMETER prog, key_state.
  t42_step(prog, 7966, 0, key_state, "NONE").
  t42_step(prog, 7996, 0, key_state, "NONE").
  t42_step(prog, 7996.5, 0, key_state, "PRO").
  t42_step(prog, 8000, 0, key_state, "NONE").
  LOCAL since IS 0.
  UNTIL since >= 15 OR prog["PHASE"] <> "BURN" {
    SET since TO since + 0.25.
    t42_step(prog, 8000 + since, 3.3 * since, key_state, "NONE").
  }
  IF prog["PHASE"] = "BURN" { RETURN LEXICON("OFF", -1, "VG", prog["VG"]). }
  RETURN LEXICON("OFF", since, "VG", prog["VG"]).
}

// ---- the sequence table ----
assert_near("P42 J: ullage on at TIG - 6", bb_table_p42("J")["ULLAGE_ON"], -6, 0).
assert_near("P42 A11: ullage on at TIG - 3.5", bb_table_p42("A11")["ULLAGE_ON"], -3.5, 0).
assert_true("P42: the V99 prompt, no throttle-up", bb_table_p42("J")["PROMPT"] AND bb_table_p42("J")["ZOOM"] = "NONE" AND bb_table_p42("J")["PROMPT_VN"] = "V99N40").
assert_near("P40's table is unchanged", bb_table_p40("J")["ULLAGE_ON"], -7.5, 0).

// ---- start and alarm 1706 ----
SET CTL_DRY_ATTACHED TO FALSE.
SET CTL_DRY_TUNES TO 0.
SET CTL_DRY_COAST_TUNES TO 0.
LOCAL prog IS t42_start("J", 25, TRUE).
assert_true("P42 starts", prog["REFUSED"] = "").
assert_true("the coast tuning of the ascent stage from the start", CTL_DRY_COAST_TUNES = 1 AND CTL_DRY_TUNES = 0).
LOCAL ks IS t42_keys().
LOCAL out IS t42_step(prog, 7500, 0, ks, "NONE").
SET out TO t42_step(prog, 7500.25, 0, ks, "NONE").
assert_true("the descent stage still on: alarm 1706 with V05 N09", prog["PHASE"] = "STAGED" AND out["REQUEST"]["VERB"] = 5 AND out["REQUEST"]["NOUN"] = 9).
assert_near("PROG shows 42", out["PROG_NO"], 42, 0).
SET out TO t42_step(prog, 7501, 0, ks, "PRO").
SET out TO t42_step(prog, 7501.25, 0, ks, "NONE").
assert_true("PRO with it still on stays at the alarm", prog["PHASE"] = "STAGED" AND NOT out["ENDED"]).
SET prog["ATTACHED"] TO FALSE.
t42_step(prog, 7502, 0, ks, "PRO").
SET out TO t42_step(prog, 7502.25, 0, ks, "NONE").
assert_true("PRO once it is gone goes on to R60", prog["PHASE"] = "R60").
SET out TO t42_step(prog, 7502.5, 0, ks, "V34").
assert_true("V34 ends P42", out["ENDED"]).
p40_end(prog).

// ---- a steered burn, J profile ----
SET CTL_DRY_TUNES TO 0.
SET CTL_DRY_COAST_TUNES TO 0.
SET prog TO t42_start("J", 25, FALSE).
SET ks TO t42_keys().
SET out TO t42_to_burn(prog, ks).
assert_true("no V50 N25 whatever the throttle switch says", prog["PHASE"] = "BURN").
assert_near("S40.13 for the ascent engine (s)", prog["BURN_S"], 6.804239, 0.001).
assert_true("a steered burn", NOT prog["IMPULSE"]).
assert_near("the thrust monitor's threshold", prog["DVMON"]["MIN"], ASC_DVMON_ACCEL_MS2, 0).
t42_step(prog, 7993.9, 0, ks, "NONE").
assert_true("no ullage before TIG - 6", NOT prog["ULLAGE_ON"]).
t42_step(prog, 7994.1, 0, ks, "NONE").
assert_true("ullage from TIG - 6", prog["ULLAGE_ON"]).
SET out TO t42_step(prog, 7995.2, 0, ks, "NONE").
assert_true("the engine prompt V99 N40", out["REQUEST"]["VERB"] = 99 AND out["REQUEST"]["NOUN"] = 40).
t42_step(prog, 7996, 0, ks, "PRO").
SET out TO t42_step(prog, 8000, 0, ks, "NONE").
assert_true("ignition at TIG at full throttle", prog["ENGINE_LIT"] AND prog["THR"] = 1 AND CTL_THR = 1).
assert_true("the powered ascent tuning at ignition", CTL_DRY_TUNES = 1).
LOCAL since IS 0.
UNTIL since >= 15 OR prog["PHASE"] <> "BURN" {
  SET since TO since + 0.25.
  t42_step(prog, 8000 + since, 3.3 * since, ks, "NONE").
}
assert_near("cut-off about 7.4 s after ignition at 3.3 m/s^2", since, 7.4, 0.6).
t42_step(prog, 8000 + since + 2.5, 3.3 * since, ks, "NONE").
assert_true("little left to gain", prog["VG"]:MAG < 1.5).
assert_true("throttle zero and the coast tuning again", prog["THR"] = 0 AND CTL_DRY_COAST_TUNES = 2).
p40_end(prog).

// ---- an impulse burn: the timer alone ----
SET prog TO t42_start("J", 12, FALSE).
SET ks TO t42_keys().
t42_to_burn(prog, ks).
assert_near("impulse burn time (s)", prog["BURN_S"], 2.972210, 0.001).
assert_true("an impulse burn", prog["IMPULSE"]).
LOCAL res IS t42_burn(prog, ks).
assert_near("cut off by the timer at the S40.13 time", res["OFF"], 3.0, 0.26).
p40_end(prog).

// ---- the Apollo 11 profile ----
SET prog TO t42_start("A11", 25, FALSE).
SET ks TO t42_keys().
t42_to_burn(prog, ks).
assert_near("A11 S40.13 (s)", prog["BURN_S"], 7.318492, 0.001).
assert_near("A11 tail-off", prog["TDECAY"], -ASC_TAILOFF_A11, 0).
p40_end(prog).

// ---- P40 is unchanged ----
LOCAL vault IS store_new(lm_cells_for("J")).
lm_store_put_tig(vault, 7000).
LOCAL p40prog IS p40_start(FALSE, vault, 1000, "J", 7500, 0, 46710, t42_xd(25), V(1, 0, 0), V(0, 1, 0)).
assert_true("P40 keeps the descent engine's numbers", p40prog["PROG_NO"] = 40 AND NOT p40prog["APS"] AND p40prog["VEX"] = DPSVEX AND p40prog["MAN"]).
p40_end(p40prog).

// ---- the vehicle table ----
assert_true("the table has P42", lm_programme_table():HASKEY("42")).
assert_true("V37 can select it", LM_PROGS:CONTAINS(42)).

SET ENG_THR_CONT TO t42_keep_thr.
SET CTL_DRY_ATTACHED TO TRUE.
SET CTL_DRY TO FALSE.
test_end().
