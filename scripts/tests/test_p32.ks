// test_p32.ks -- pad test for P32, CSI targeting, and P33, CDH targeting (lm/rndz/lm_p32.ks), and their table entries. No flight: both craft come from a fake snapshot
// delegate, and CTL_DRY is TRUE for the check that P41 accepts the burn. The states are the circular case of reference_rndz.py at UT 2000 (LM at the apolune of a
// 45 x 9 nmi orbit, CSM circular and 8.4 degrees ahead; the P33 part adds the CSI burn to the LM); the AGC clock zero is UT 1000, so CSI is 1000 s and TPI 6800 s on
// that clock.
//   RUNPATH("0:/tests/test_p32.ks").   Log: 0:/lm/logs/test_p32.log (the programme's own solution lines go to test_p32_solutions.log).
// Expected numbers: python scripts/tests/reference_rndz.py

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p32.log").
SET CTL_DRY TO TRUE.
LOCAL t32_keep_log IS P32_LOG_PATH.
SET P32_LOG_PATH TO "0:/lm/logs/test_p32_solutions.log".
IF EXISTS(P32_LOG_PATH) { DELETEPATH(P32_LOG_PATH). }

GLOBAL T32_MU IS 4.9028e12.
GLOBAL T32_RADIUS IS 1737400.
GLOBAL T32_R IS V(T32_RADIUS + 45 * 1852, 0, 0).
GLOBAL T32_V IS V(0, 0, SQRT(T32_MU * (2 / (T32_RADIUS + 45 * 1852) - 2 / (2 * T32_RADIUS + 54 * 1852)))).
GLOBAL T32_RT IS V(COS(8.4), 0, SIN(8.4)) * 1848520.
GLOBAL T32_VT IS V(-SIN(8.4), 0, COS(8.4)) * SQRT(T32_MU / 1848520).
GLOBAL T32_ZERO IS 1000.
GLOBAL T32_NOW IS 1400.
GLOBAL T32_LOST IS FALSE.
GLOBAL T32_AX IS LEXICON("P", V(1, 0, 0), "N", V(0, 1, 0)).    // one axes mark: the raw axes stand still

// t32_snap: both craft at T32_NOW.
FUNCTION t32_snap {
  IF T32_LOST { RETURN LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit"). }
  LOCAL lm_now IS conic_kepler(T32_R, T32_V, T32_NOW - 2000, T32_MU).
  LOCAL csm_now IS conic_kepler(T32_RT, T32_VT, T32_NOW - 2000, T32_MU).
  RETURN LEXICON("OK", TRUE, "WHY", "", "T", T32_NOW, "R", lm_now["R"], "V", lm_now["V"], "RT", csm_now["R"], "VT", csm_now["V"],
                 "AX", T32_AX, "MU", T32_MU, "RADIUS", T32_RADIUS).
}

FUNCTION t32_vault { RETURN store_new(lm_cells_for("A11")). }

FUNCTION t32_start {
  PARAMETER vault.
  RETURN p32_start(FALSE, vault, T32_ZERO, "A11", T32_NOW, t32_snap@).
}

FUNCTION t32_keys { RETURN keys_new(LM_NOUNS, LM_VERBS, LM_PROGS). }

// t32_step: one cycle with the pilot's answer "NONE", "PRO", "V32", "V34", then the answer cleared as the core does.
FUNCTION t32_step {
  PARAMETER prog, key_state, answer.
  SET prog["NOW_UT"] TO T32_NOW.
  SET key_state["PRO"] TO answer = "PRO".
  SET key_state["RECYCLE"] TO answer = "V32".
  SET key_state["TERMINATE"] TO answer = "V34".
  LOCAL out IS p32_step(prog, key_state).
  SET key_state["PRO"] TO FALSE.
  SET key_state["RECYCLE"] TO FALSE.
  SET key_state["TERMINATE"] TO FALSE.
  RETURN out.
}

// t32_shows: the cycle set this verb and noun and asks for an answer to it.
FUNCTION t32_shows {
  PARAMETER out, verb_no, noun_no.
  IF out["SET_VERB"] <> verb_no OR out["SET_NOUN"] <> noun_no { RETURN FALSE. }
  IF NOT out["REQUEST"]:ISTYPE("Lexicon") { RETURN FALSE. }
  RETURN out["REQUEST"]["VERB"] = verb_no AND out["REQUEST"]["NOUN"] = noun_no.
}

FUNCTION t32_regs {
  PARAMETER noun_no, out.
  LOCAL derived IS LEXICON("VALID", FALSE).
  FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
  RETURN noun_registers(noun_no, derived).
}

// t32_to_n75: a started programme with CSI and TPI loaded, taken to the N75 display. Returns LEXICON("PROG", "KS", "VAULT", "OUT").
FUNCTION t32_to_n75 {
  PARAMETER tpi_s.
  LOCAL vault IS t32_vault().
  SET LM_VEH["STORE"] TO vault.
  LOCAL prog IS t32_start(vault).
  LOCAL key_state IS t32_keys().
  t32_step(prog, key_state, "NONE").
  lm_store_put_time(vault, "TCSI", 1000).
  t32_step(prog, key_state, "PRO").
  t32_step(prog, key_state, "PRO").
  lm_store_put_time(vault, "TTPI", tpi_s).
  LOCAL out IS t32_step(prog, key_state, "PRO").
  RETURN LEXICON("PROG", prog, "KS", key_state, "VAULT", vault, "OUT", out).
}

LOCAL keep_store IS FALSE.
IF LM_VEH:HASKEY("STORE") { SET keep_store TO LM_VEH["STORE"]. }
SET LM_VEH["XDELV"] TO FALSE.

// ---- start ----
LOCAL vault IS t32_vault().
SET LM_VEH["STORE"] TO vault.
lm_store_put_time(vault, "TCSI", 5000).
lm_store_put_n55(vault, -1, -1, 130).
LOCAL prog IS t32_start(vault).
assert_true("starts with a good snapshot", prog["REFUSED"] = "").
assert_near("start zeroes TCSI", lm_store_get_time(vault, "TCSI"), 0, 0).
assert_near("start zeroes the central angle", lm_store_get_n55(vault)["CENTANG"], 0, 0.001).
assert_near("an unloaded NN becomes 1", lm_store_get_n55(vault)["NN"], 1, 0).
assert_near("an unloaded elevation becomes 26.60", lm_store_get_n55(vault)["ELEV"], 26.6, 0.001).

// ---- N11 ----
LOCAL key_state IS t32_keys().
LOCAL out IS t32_step(prog, key_state, "NONE").
assert_true("first cycle shows V06 N11", t32_shows(out, 6, 11)).
assert_near("PROG shows 32", out["PROG_NO"], 32, 0).
SET out TO t32_step(prog, key_state, "V32").
assert_true("V32 at N11 shows it again", t32_shows(out, 6, 11)).
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO on a zero N11 stays at N11", t32_shows(out, 6, 11) AND NOT out["ENDED"]).
assert_near("and loads the next apolune (s)", lm_store_get_time(vault, "TCSI"), 1000, 1).
lm_store_put_time(vault, "TCSI", 300).          // UT 1300, already past
SET out TO t32_step(prog, key_state, "PRO").
assert_true("a past CSI time stays at N11 with a warning", t32_shows(out, 6, 11) AND out["WARN"]:LENGTH > 0 AND NOT out["ENDED"]).
lm_store_put_time(vault, "TCSI", 1000).

// ---- N55, N37, N75 ----
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N11 shows V06 N55", t32_shows(out, 6, 55)).
LOCAL regs IS t32_regs(55, out).
assert_true("N55 shows +00001, +02660, +00000", regs[0] = "+00001" AND regs[1] = "+02660" AND regs[2] = "+00000").
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N55 shows V06 N37", t32_shows(out, 6, 37)).
lm_store_put_time(vault, "TTPI", 6800).
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N37 computes and shows V06 N75", t32_shows(out, 6, 75) AND out["ALARM"] = 0).
assert_near("height difference at CDH (m)", out["EXTRA"]["RN_DH"], 27760.41, 1).
assert_near("CSI to CDH (s)", out["EXTRA"]["RN_T12"], 3485.806, 0.1).
assert_near("CDH to TPI (s)", out["EXTRA"]["RN_T23"], 2314.194, 0.1).
assert_near("TCDH is stored", lm_store_get_time(vault, "TCDH"), 4485.806, 0.05).
SET out TO t32_step(prog, key_state, "V32").
assert_true("V32 at N75 shows it again without advancing", t32_shows(out, 6, 75)).

// ---- N81, N82 ----
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N75 shows V06 N81", t32_shows(out, 6, 81)).
assert_near("CSI delta-V along track (m/s)", lm_store_get_dv(vault):X, 15.3788, 0.002).
assert_near("CSI delta-V across", lm_store_get_dv(vault):Y, 0, 0.002).
assert_near("CSI delta-V down", lm_store_get_dv(vault):Z, 0, 0.002).
assert_true("no burn is set before N81 is answered", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N81 shows V06 N82", t32_shows(out, 6, 82)).
assert_true("and sets the burn", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
IF LM_VEH["XDELV"]:ISTYPE("Lexicon") {
  LOCAL xd IS LM_VEH["XDELV"].
  assert_vec("DELVSIN (m/s, the case's axes)", xd["DELVSIN"], V(0, 0, 15.3788), 0.002).
  assert_near("DELVSAB (m/s)", xd["DELVSAB"], 15.3788, 0.002).
  assert_near("UT_TIG", xd["UT_TIG"], 2000, 0.01).
  assert_vec("RTIG is the LM position at CSI (m)", xd["RTIG"], T32_R, 1).
  assert_vec("VTIG is the LM velocity at CSI (m/s)", xd["VTIG"], T32_V, 0.001).
  assert_true("AX0 is the snapshot's mark", (xd["AX0"]["P"] - T32_AX["P"]):MAG = 0 AND (xd["AX0"]["N"] - T32_AX["N"]):MAG = 0).
  LOCAL burn IS p41_start(FALSE, vault, T32_ZERO, "A11", T32_NOW, 0, xd, V(1, 0, 0), V(0, 1, 0)).
  assert_true("P41 accepts the burn", burn["REFUSED"] = "").
  IF burn["REFUSED"] = "" { p41_end(burn). }
}
assert_near("TIG is the CSI time (s)", lm_store_get_tig(vault), 1000, 0.01).
assert_near("N82 holds the CDH delta-V along track (m/s)", lm_store_get_dv(vault):X, 0.0044, 0.002).

// ---- N45 and the final computation ----
SET out TO t32_step(prog, key_state, "PRO").
assert_true("PRO at N82 shows V16 N45", t32_shows(out, 16, 45)).
assert_near("TTPI0 takes the TPI time (s)", lm_store_get_time(vault, "TTPI0"), 6800, 0.01).
assert_near("N45 time to go (s)", out["EXTRA"]["P30_TTOGO"], 600, 0.01).
assert_near("N45 gimbal angle is -00.01 before the final computation", out["EXTRA"]["P30_MGA"], -0.01, 1e-9).
SET out TO t32_step(prog, key_state, "V32").
assert_true("V32 at N45 computes again (N75)", t32_shows(out, 6, 75)).
t32_step(prog, key_state, "PRO").
t32_step(prog, key_state, "PRO").
t32_step(prog, key_state, "PRO").
SET out TO t32_step(prog, key_state, "PRO").
assert_true("the first PRO at N45 makes the final computation (N75)", t32_shows(out, 6, 75) AND NOT out["ENDED"]).
t32_step(prog, key_state, "PRO").
t32_step(prog, key_state, "PRO").
SET out TO t32_step(prog, key_state, "PRO").
assert_true("back at N45", t32_shows(out, 16, 45)).
assert_near("the final computation shows the gimbal angle (in-plane burn)", SIN(out["EXTRA"]["P30_MGA"]), 0, 0.0001).
SET out TO t32_step(prog, key_state, "PRO").
assert_true("the next PRO at N45 ends P32", out["ENDED"]).

// ---- a keyed N81 register is used ----
LOCAL t32_run IS t32_to_n75(6800).
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").
LOCAL dv_shown IS lm_store_get_dv(t32_run["VAULT"]).
lm_store_put_dv(t32_run["VAULT"], V(dv_shown:X, 1, dv_shown:Z)).
SET LM_VEH["XDELV"] TO FALSE.
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("the keyed burn is set", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
IF LM_VEH["XDELV"]:ISTYPE("Lexicon") {
  assert_near("a keyed Y of 1 m/s is out of plane", ABS(LM_VEH["XDELV"]["DELVSIN"]:Y), 1, 0.002).
  assert_near("and leaves X alone", LM_VEH["XDELV"]["DELVSIN"]:Z, 15.3788, 0.002).
}

// ---- an alarm: TPI before CDH ----
SET LM_VEH["XDELV"] TO FALSE.
SET t32_run TO t32_to_n75(2800).
SET out TO t32_run["OUT"].
assert_true("TPI too soon shows V05 N09", t32_shows(out, 5, 9)).
assert_near("with alarm 604", out["ALARM"], 604, 0).
SET out TO t32_step(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("PRO shows the alarm again", t32_shows(out, 5, 9) AND NOT out["ENDED"] AND out["ALARM"] = 604).
SET out TO t32_step(t32_run["PROG"], t32_run["KS"], "V32").
assert_true("V32 restarts P32 at N11", t32_shows(out, 6, 11) AND out["ALARM"] = 0).
assert_near("with TCSI zero", lm_store_get_time(t32_run["VAULT"], "TCSI"), 0, 0).
SET out TO t32_step(t32_run["PROG"], t32_run["KS"], "V34").
assert_true("V34 ends P32", out["ENDED"]).
assert_true("and no burn is set", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).

// ---- the CSM is lost (Review Focus 1) ----
SET t32_run TO t32_to_n75(6800).
SET T32_LOST TO TRUE.
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N75
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N81
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N82
SET out TO t32_step(t32_run["PROG"], t32_run["KS"], "V32").
assert_true("a recompute with no CSM ends P32 with a warning", out["ENDED"] AND out["WARN"]:LENGTH > 0).
LOCAL refused IS t32_start(t32_vault()).
assert_true("and P32 refuses to start without it", refused["REFUSED"]:CONTAINS("no CSM")).
SET T32_LOST TO FALSE.

// ---- CSI passes while the displays wait (Review Focus 2) ----
SET LM_VEH["XDELV"] TO FALSE.
SET vault TO t32_vault().
SET prog TO t32_start(vault).
SET key_state TO t32_keys().
t32_step(prog, key_state, "NONE").
lm_store_put_time(vault, "TCSI", 1000).
t32_step(prog, key_state, "PRO").
t32_step(prog, key_state, "PRO").
lm_store_put_time(vault, "TTPI", 6800).
SET T32_NOW TO 2100.
SET out TO t32_step(prog, key_state, "PRO").
assert_true("a past CSI at N37 goes back to N11 with a warning", t32_shows(out, 6, 11) AND out["WARN"]:LENGTH > 0).
assert_true("and sets no burn", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
assert_near("and stores no CDH time", lm_store_get_time(vault, "TCDH"), -1, 0).
SET T32_NOW TO 1400.

// ======== P33, CDH targeting ========

FUNCTION t32_start_33 {
  PARAMETER vault_in.
  RETURN p33_start(FALSE, vault_in, T32_ZERO, "A11", T32_NOW, t32_snap@).
}

// t32_step_33: t32_step for P33.
FUNCTION t32_step_33 {
  PARAMETER prog_in, keys_in, answer.
  SET prog_in["NOW_UT"] TO T32_NOW.
  SET keys_in["PRO"] TO answer = "PRO".
  SET keys_in["RECYCLE"] TO answer = "V32".
  SET keys_in["TERMINATE"] TO answer = "V34".
  LOCAL stepped IS p33_step(prog_in, keys_in).
  SET keys_in["PRO"] TO FALSE.
  SET keys_in["RECYCLE"] TO FALSE.
  SET keys_in["TERMINATE"] TO FALSE.
  RETURN stepped.
}

// t32_vault_33: a store holding only the CDH time and the TPI time of P32, as after a DSKY restart.
FUNCTION t32_vault_33 {
  LOCAL made IS t32_vault().
  lm_store_put_time(made, "TCDH", 4485.806).
  lm_store_put_time(made, "TTPI0", 6800).
  RETURN made.
}

// t32_begin_33: a started P33 showing N13. Returns LEXICON("PROG", "KS", "VAULT", "OUT").
FUNCTION t32_begin_33 {
  LOCAL made IS t32_vault_33().
  SET LM_VEH["STORE"] TO made.
  SET LM_VEH["XDELV"] TO FALSE.
  LOCAL prog_made IS t32_start_33(made).
  LOCAL keys_made IS t32_keys().
  LOCAL first IS t32_step_33(prog_made, keys_made, "NONE").
  RETURN LEXICON("PROG", prog_made, "KS", keys_made, "VAULT", made, "OUT", first).
}

// P32 and then P33 on one store: the CDH and TPI times carry over (run first: it needs the orbit before CSI).
SET T32_NOW TO 1400.
SET t32_run TO t32_to_n75(6800).
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N75 -> N81
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N81 -> N82
t32_step(t32_run["PROG"], t32_run["KS"], "PRO").          // N82 -> N45
t32_step(t32_run["PROG"], t32_run["KS"], "V34").
LOCAL t32_carried IS t32_run["VAULT"].

// from here the LM is in the orbit after the CSI burn.
SET T32_V TO T32_V + V(0, 0, 15.37881).

SET prog TO t32_start_33(t32_carried).
assert_true("P33 starts on P32's store", prog["REFUSED"] = "").
SET key_state TO t32_keys().
SET out TO t32_step_33(prog, key_state, "NONE").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("and computes at the first PRO (N75)", t32_shows(out, 6, 75) AND out["ALARM"] = 0).
assert_near("TCDH carried over (s)", lm_store_get_time(t32_carried, "TCDH"), 4485.806, 0.05).
assert_near("TTPI from TTPI0 and the search (s)", lm_store_get_time(t32_carried, "TTPI"), 6806.381, 0.05).

// ---- N13, N75, N81, N45 from a store holding only TCDH and TTPI0 (Review Focus 5) ----
SET t32_run TO t32_begin_33().
SET prog TO t32_run["PROG"].
SET key_state TO t32_run["KS"].
SET vault TO t32_run["VAULT"].
SET out TO t32_run["OUT"].
assert_true("P33 starts without a burn set", prog["REFUSED"] = "").
assert_near("an unloaded elevation becomes 26.60 in P33", lm_store_get_n55(vault)["ELEV"], 26.6, 0.001).
assert_true("first cycle shows V06 N13", t32_shows(out, 6, 13)).
assert_near("PROG shows 33", out["PROG_NO"], 33, 0).
SET out TO t32_step_33(prog, key_state, "V32").
assert_true("V32 at N13 shows it again", t32_shows(out, 6, 13)).
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("PRO at N13 computes and shows V06 N75", t32_shows(out, 6, 75) AND out["ALARM"] = 0).
assert_near("P33 TPI time stored (s)", lm_store_get_time(vault, "TTPI"), 6806.381, 0.05).
assert_near("P33 height difference (m)", out["EXTRA"]["RN_DH"], 27760.41, 1).
assert_near("P33 CDH to TPI (s)", out["EXTRA"]["RN_T12"], 2320.575, 0.1).
assert_near("P33 TPI time less the nominal (s)", out["EXTRA"]["RN_T23"], 6.381, 0.05).
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("PRO at N75 shows V06 N81 in P33", t32_shows(out, 6, 81)).
assert_near("CDH delta-V along track (m/s)", lm_store_get_dv(vault):X, 0.0044, 0.002).
assert_near("CDH delta-V across", lm_store_get_dv(vault):Y, 0, 0.002).
assert_near("CDH delta-V down", lm_store_get_dv(vault):Z, 0, 0.002).
LOCAL t32_early IS p41_start(FALSE, vault, T32_ZERO, "A11", T32_NOW, 0, LM_VEH["XDELV"], V(1, 0, 0), V(0, 1, 0)).
assert_true("P41 refuses before N81 is answered", t32_early["REFUSED"] <> "").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("PRO at N81 shows V16 N45 in P33", t32_shows(out, 16, 45)).
assert_true("and sets the CDH burn", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
IF LM_VEH["XDELV"]:ISTYPE("Lexicon") {
  LOCAL xd IS LM_VEH["XDELV"].
  assert_near("CDH UT_TIG", xd["UT_TIG"], T32_ZERO + 4485.806, 0.02).
  assert_near("CDH DELVSAB (m/s)", xd["DELVSAB"], 0.0044, 0.002).
  LOCAL burn IS p41_start(FALSE, vault, T32_ZERO, "A11", T32_NOW, 0, xd, V(1, 0, 0), V(0, 1, 0)).
  assert_true("P41 accepts the CDH burn", burn["REFUSED"] = "").
  IF burn["REFUSED"] = "" { p41_end(burn). }
}
assert_near("TIG is the CDH time (s)", lm_store_get_tig(vault), 4485.806, 0.02).
assert_near("P33 N45 time to go (s)", out["EXTRA"]["P30_TTOGO"], 4085.806, 0.02).
assert_near("P33 N45 gimbal angle is -00.01 before the final computation", out["EXTRA"]["P30_MGA"], -0.01, 1e-9).

// ---- N45 and the final computation ----
SET out TO t32_step_33(prog, key_state, "V32").
assert_true("V32 at N45 computes again in P33 (N75)", t32_shows(out, 6, 75)).
assert_near("a recompute starts from the current TPI time (s)", lm_store_get_time(vault, "TTPI"), 6806.381, 0.1).
t32_step_33(prog, key_state, "PRO").
t32_step_33(prog, key_state, "PRO").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("the first PRO at N45 makes P33's final computation (N75)", t32_shows(out, 6, 75) AND NOT out["ENDED"]).
t32_step_33(prog, key_state, "PRO").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("P33 back at N45", t32_shows(out, 16, 45)).
assert_near("P33's final computation shows the gimbal angle (in-plane burn)", SIN(out["EXTRA"]["P30_MGA"]), 0, 0.0001).
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("the next PRO at N45 ends P33", out["ENDED"]).

// ---- the elevation cannot be reached: alarm 611 ----
SET t32_run TO t32_begin_33().
lm_store_put_n55(t32_run["VAULT"], -1, 200, -1).
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("elevation 200 shows V05 N09", t32_shows(out, 5, 9)).
assert_near("with alarm 611", out["ALARM"], 611, 0).
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("PRO uses the nominal time and shows N75", t32_shows(out, 6, 75) AND out["ALARM"] = 0).
assert_near("TPI less nominal is zero (s)", out["EXTRA"]["RN_T23"], 0, 0.001).
assert_near("and the nominal TPI time is stored (s)", lm_store_get_time(t32_run["VAULT"], "TTPI"), 6800, 0.01).
SET t32_run TO t32_begin_33().
lm_store_put_n55(t32_run["VAULT"], -1, 200, -1).
t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "V32").
assert_true("V32 at 611 restarts at N13", t32_shows(out, 6, 13) AND out["ALARM"] = 0).
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "V34").
assert_true("V34 ends P33", out["ENDED"]).
assert_true("and P33 set no burn", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).

// ---- refusals, a past CDH time and a lost CSM ----
SET vault TO t32_vault().
LOCAL t32_no_tpi IS t32_start_33(vault).
assert_true("P33 refuses with no TPI time", t32_no_tpi["REFUSED"]:CONTAINS("TPI")).
lm_store_put_time(vault, "TTPI", 6800).                   // keyed with V25 N37 E, no P32
SET LM_VEH["STORE"] TO vault.
SET prog TO t32_start_33(vault).
assert_true("a keyed TPI time alone starts P33", prog["REFUSED"] = "").
SET key_state TO t32_keys().
t32_step_33(prog, key_state, "NONE").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_true("PRO on an unloaded CDH time stays at N13", t32_shows(out, 6, 13) AND out["WARN"]:LENGTH > 0).
lm_store_put_time(vault, "TCDH", 4485.806).
t32_step_33(prog, key_state, "PRO").
assert_near("the keyed TPI time is the nominal one (s)", prog["NOMINAL_S"], 6800, 0.01).
assert_true("and is not kept as P32's", lm_store_get_time(vault, "TTPI0") <= 0).
t32_step_33(prog, key_state, "V34").
lm_store_put_time(vault, "TTPI", 6900).                   // a newer time keyed before a second P33, still no P32
SET prog TO t32_start_33(vault).
t32_step_33(prog, key_state, "NONE").
SET out TO t32_step_33(prog, key_state, "PRO").
assert_near("a newer keyed TPI time is not overwritten (s)", prog["NOMINAL_S"], 6900, 0.01).
assert_near("TPI less the newer time (s)", out["EXTRA"]["RN_T23"], lm_store_get_time(vault, "TTPI") - 6900, 0.01).
assert_near("and the search still finds the TPI time (s)", lm_store_get_time(vault, "TTPI"), 6806.381, 0.5).

SET t32_run TO t32_begin_33().
lm_store_put_time(t32_run["VAULT"], "TCDH", 300).         // UT 1300, already past
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("a past CDH time stays at N13 with a warning", t32_shows(out, 6, 13) AND out["WARN"]:LENGTH > 0 AND NOT out["ENDED"]).
assert_true("and P33 sets no burn then", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).

SET t32_run TO t32_begin_33().
t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").       // N75
t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").       // N81
t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").       // N45
SET T32_NOW TO 5600.                                      // past CDH (UT 5485.806)
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "V32").
assert_true("a recompute after the CDH time goes back to N13", t32_shows(out, 6, 13) AND out["WARN"]:LENGTH > 0).
SET T32_NOW TO 1400.

SET t32_run TO t32_begin_33().
SET T32_LOST TO TRUE.
SET out TO t32_step_33(t32_run["PROG"], t32_run["KS"], "PRO").
assert_true("P33 with the CSM lost ends with a warning", out["ENDED"] AND out["WARN"]:LENGTH > 0).
SET refused TO t32_start_33(t32_vault_33()).
assert_true("and P33 refuses to start without it", refused["REFUSED"]:CONTAINS("no CSM")).
SET T32_LOST TO FALSE.

// ---- registration ----
assert_true("the vehicle table has P32", lm_programme_table():HASKEY("32")).
assert_true("V37 can select 32", LM_PROGS:CONTAINS(32)).
assert_true("the vehicle table has P33", lm_programme_table():HASKEY("33")).
assert_true("V37 can select 33", LM_PROGS:CONTAINS(33)).

SET LM_VEH["XDELV"] TO FALSE.
IF keep_store:ISTYPE("Lexicon") { SET LM_VEH["STORE"] TO keep_store. }
SET P32_LOG_PATH TO t32_keep_log.
SET CTL_DRY TO FALSE.
test_end().
