// test_aim.ks -- pad test for burns on an aim point (P34, P35) in P40 and P41 (lm/burn/lm_p40.ks, lm_p41.ks). No flight: CTL_DRY is TRUE and the states are
// made up from the TPI case of reference_rndz.py, with the Moon's gravity: the LM at TPI at UT 8000, the intercept 2575.342 s later.
//   RUNPATH("0:/tests/test_aim.ks").   Log: 0:/lm/logs/test_aim.log. Expected numbers: python scripts/tests/reference_rndz.py

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_aim.log").
SET CTL_DRY TO TRUE.
SET CTL_DRY_ATTACHED TO TRUE.

GLOBAL TAM_MU IS 4.9028e12.
GLOBAL TAM_R IS V(905666.125472, 0, -1579536.104075).
GLOBAL TAM_V IS V(1423.5500524, 0, 816.2276615).
GLOBAL TAM_AIM IS V(586581.134, 0, 1752982.819).
GLOBAL TAM_DV IS V(7.47049, 0, 0.43098).
GLOBAL TAM_TPASS IS 10575.342.
GLOBAL TAM_AX IS LEXICON("P", V(1, 0, 0), "N", V(0, 1, 0)).     // the raw axes of the targeting

// tam_state: the LM at UT now_ut on the orbit through (TAM_R, vel_at_tig) at UT 8000, in the axes of the mark ax.
FUNCTION tam_state {
  PARAMETER now_ut, vel_at_tig, ax.
  LOCAL at_now IS conic_kepler(TAM_R, vel_at_tig, now_ut - 8000, TAM_MU).
  RETURN LEXICON("R", axes_carry(at_now["R"], TAM_AX, ax), "V", axes_carry(at_now["V"], TAM_AX, ax), "T", now_ut, "MASS", 4.7, "THRUST", 46.71,
                 "THRUST_NOW", 0, "MU", TAM_MU, "BODY_OK", TRUE, "ALT_RADAR", 80000, "XNB", V(1, 0, 0), "AX", ax).
}
FUNCTION tam_xd {
  PARAMETER tpass_ut.
  RETURN rndz_aim_xdelv(TAM_DV, TAM_R, TAM_V, TAM_AIM, tpass_ut, FALSE, 8000, TAM_AX).
}
FUNCTION tam_vault {
  LOCAL vault IS store_new(lm_cells_for("J")).
  lm_store_put_tig(vault, 7000).
  RETURN vault.
}
FUNCTION tam_p41 {
  PARAMETER tpass_ut, now_ut.
  RETURN p41_start(FALSE, tam_vault(), 1000, "J", now_ut, 0, tam_xd(tpass_ut), V(1, 0, 0), V(0, 1, 0)).
}
FUNCTION tam_p40 {
  PARAMETER tpass_ut, now_ut.
  RETURN p40_start(FALSE, tam_vault(), 1000, "J", now_ut, 0, 46710, tam_xd(tpass_ut), V(1, 0, 0), V(0, 1, 0)).
}
FUNCTION tam_keys { RETURN keys_new(LM_NOUNS, LM_VERBS, LM_PROGS). }

// ---- refusals ----
assert_true("P41 refuses an intercept before TIG", tam_p41(7900, 7000)["REFUSED"]:CONTAINS("intercept time")).
assert_true("P40 refuses it too", tam_p40(7900, 7000)["REFUSED"]:CONTAINS("intercept time")).
assert_true("P41 refuses an intercept already passed", tam_p41(10575, 10600)["REFUSED"]:CONTAINS("intercept time")).
assert_true("with no burn set the text names P34", p41_start(FALSE, tam_vault(), 1000, "J", 7000, 0, FALSE, V(1, 0, 0), V(0, 1, 0))["REFUSED"]:CONTAINS("P34")).

// ---- the velocity to gain at the start (S40.1B) ----
LOCAL prog IS tam_p41(TAM_TPASS, 7500).
assert_true("P41 starts on an aim point", prog["REFUSED"] = "").
LOCAL out IS p41_step(prog, tam_state(7500, TAM_V, TAM_AX), LEXICON("VALID", FALSE), tam_keys()).
assert_vec("P41 start: velocity to gain at TIG", prog["VG"], TAM_DV, 0.001).
assert_near("P41 start: the thrust axis along it", VANG(prog["AXES"]["X"], TAM_DV), 0, 0.01).
LOCAL prog40 IS tam_p40(TAM_TPASS, 7500).
SET out TO p40_step(prog40, tam_state(7500, TAM_V, TAM_AX), LEXICON("VALID", FALSE), tam_keys()).
assert_vec("P40 start: velocity to gain at TIG", prog40["VG"], TAM_DV, 0.001).
assert_true("P40 start: a burn time", prog40["BURN_S"] > 0).
p40_end(prog40).

// ---- each pass: from the present state to the aim point ----
LOCAL early IS p40_vg_pass(prog, tam_state(7970, TAM_V, TAM_AX), 7970, V(5, 5, 5)).
assert_vec("30 s before TIG: from the present state, not the measured delta-V", early, V(7.32165, 0, 0.56143), 0.001).
LOCAL gained IS tam_state(8000, TAM_V, TAM_AX).
SET gained["V"] TO gained["V"] + TAM_DV.
assert_vec("nothing left once it is gained", p40_vg_pass(prog, gained, 8000, TAM_DV), V(0, 0, 0), 0.001).
assert_vec("nor 60 s later on the transfer orbit", p40_vg_pass(prog, tam_state(8060, TAM_V + TAM_DV, TAM_AX), 8060, V(0, 0, 0)), V(0, 0, 0), 0.01).

// ---- the raw axes turned since the targeting ----
LOCAL turned IS LEXICON("P", ANGLEAXIS(10, TAM_AX["N"]) * TAM_AX["P"], "N", TAM_AX["N"]).
assert_vec("turned axes: the same velocity to gain in the burn's axes",
    p40_vg_pass(prog, tam_state(7970, TAM_V, turned), 7970, V(0, 0, 0)), V(7.32165, 0, 0.56143), 0.002).
LOCAL prog_turned IS tam_p41(TAM_TPASS, 7500).
p41_step(prog_turned, tam_state(7500, TAM_V, turned), LEXICON("VALID", FALSE), tam_keys()).
assert_vec("turned axes: the start too", prog_turned["VG"], TAM_DV, 0.002).
p41_end(prog_turned).

// ---- the solution lost: the measured delta-V is counted instead, said once ----
SET prog["VG"] TO V(3, 0, 0).
SET prog["NOTE"] TO "".
LOCAL lost IS p40_vg_pass(prog, tam_state(10600, TAM_V, TAM_AX), 10600, V(1, 0, 0)).
assert_vec("lost: the old velocity to gain less the measured delta-V", lost, V(2, 0, 0), 0.000001).
assert_true("lost: a message", prog["NOTE"]:LENGTH > 0).
SET prog["NOTE"] TO "".
p40_vg_pass(prog, tam_state(10602, TAM_V, TAM_AX), 10602, V(1, 0, 0)).
assert_true("lost: not said again", prog["NOTE"] = "").
p41_end(prog).

// ---- an external delta-V is counted down as before ----
LOCAL external IS LEXICON("DELVSIN", V(7, 0, 0), "RTIG", TAM_R, "VTIG", TAM_V, "UT_TIG", 8000, "DELVSAB", 7, "AX0", TAM_AX).
LOCAL prog_ext IS p41_start(FALSE, tam_vault(), 1000, "J", 7500, 0, external, V(1, 0, 0), V(0, 1, 0)).
p41_step(prog_ext, tam_state(7500, TAM_V, TAM_AX), LEXICON("VALID", FALSE), tam_keys()).
assert_vec("external: VG at the start is the delta-V", prog_ext["VG"], V(7, 0, 0), 0.000001).
assert_vec("external: a pass counts the measured delta-V", p40_vg_pass(prog_ext, tam_state(7970, TAM_V, TAM_AX), 7970, V(1, 2, 0)), V(6, -2, 0), 0.000001).
p41_end(prog_ext).

// ---- P41 through TIG: the pass after the burn reads zero ----
SET prog TO tam_p41(TAM_TPASS, 7500).
LOCAL ks IS tam_keys().
p41_step(prog, tam_state(7500, TAM_V, TAM_AX), LEXICON("VALID", FALSE), ks).
p41_step(prog, tam_state(7500.5, TAM_V, TAM_AX), LEXICON("VALID", FALSE), ks).
SET ks["VERB"] TO 50.
SET ks["NOUN"] TO 18.
SET ks["ENTER"] TO TRUE.
p41_step(prog, tam_state(7501, TAM_V, TAM_AX), LEXICON("VALID", FALSE), ks).
SET ks["ENTER"] TO FALSE.
assert_true("R60 skipped: the countdown", prog["PHASE"] = "BURN").
p41_step(prog, tam_state(7972, TAM_V, TAM_AX), LEXICON("VALID", FALSE), ks).
p41_step(prog, tam_state(7975, TAM_V, TAM_AX), LEXICON("VALID", FALSE), ks).
assert_near("countdown: N85 from the aim point (m/s)", prog["VG"]:MAG, 7.35, 0.1).
p41_step(prog, tam_state(8000.5, TAM_V + TAM_DV, TAM_AX), LEXICON("VALID", FALSE), ks).
SET out TO p41_step(prog, tam_state(8003, TAM_V + TAM_DV, TAM_AX), LEXICON("VALID", FALSE), ks).
assert_true("TIG passed", prog["PHASE"] = "TIGNOW").
assert_near("after the burn N85 reads zero (m/s)", prog["VG"]:MAG, 0, 0.02).
p41_end(prog).

SET CTL_DRY TO FALSE.
test_end().
