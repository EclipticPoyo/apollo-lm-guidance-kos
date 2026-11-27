// test_p34.ks -- pad test for P34, TPI targeting, and P35, midcourse targeting (lm/rndz/lm_p34.ks), and their table entries. No flight: both craft come
// from a fake snapshot delegate, and CTL_DRY is TRUE for the check that P41 accepts the burn. The states are those of reference_rndz.py at TPI (after the
// CSI and CDH of the circular case), placed at UT 8000; the AGC clock zero is UT 1000, so TPI is 7000 s on that clock.
//   RUNPATH("0:/tests/test_p34.ks").   Log: 0:/lm/logs/test_p34.log (the programmes' own solution lines go to test_p34_solutions.log).
// Expected numbers: python scripts/tests/reference_rndz.py

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p34.log").
SET CTL_DRY TO TRUE.
LOCAL t34_keep_log IS P34_LOG_PATH.
SET P34_LOG_PATH TO "0:/lm/logs/test_p34_solutions.log".
IF EXISTS(P34_LOG_PATH) { DELETEPATH(P34_LOG_PATH). }

GLOBAL T34_MU IS 4.9028e12.
GLOBAL T34_RADIUS IS 1737400.
GLOBAL T34_R IS V(905666.125472, 0, -1579536.104075).
GLOBAL T34_V IS V(1423.5500524, 0, 816.2276615).
GLOBAL T34_RT IS V(965815.662142, 0, -1576142.854300).
GLOBAL T34_VT IS V(1388.6136673, 0, 850.9030922).
GLOBAL T34_LM_V IS T34_V.                       // the LM's velocity at UT 8000 as the snapshot flies it (P35: after TPI with an error)
GLOBAL T34_ZERO IS 1000.
GLOBAL T34_NOW IS 7400.
GLOBAL T34_LOST IS FALSE.
GLOBAL T34_AX IS LEXICON("P", V(1, 0, 0), "N", V(0, 1, 0)).    // one axes mark: the raw axes stand still

// t34_snap: both craft at T34_NOW.
FUNCTION t34_snap {
  IF T34_LOST { RETURN LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit"). }
  LOCAL lm_now IS conic_kepler(T34_R, T34_LM_V, T34_NOW - 8000, T34_MU).
  LOCAL csm_now IS conic_kepler(T34_RT, T34_VT, T34_NOW - 8000, T34_MU).
  RETURN LEXICON("OK", TRUE, "WHY", "", "T", T34_NOW, "R", lm_now["R"], "V", lm_now["V"], "RT", csm_now["R"], "VT", csm_now["V"],
                 "AX", T34_AX, "MU", T34_MU, "RADIUS", T34_RADIUS).
}
// t34_vault: a fresh store with the TPI time loaded (-1 loads none).
FUNCTION t34_vault {
  PARAMETER profile, ttpi_s.
  LOCAL vault IS store_new(lm_cells_for(profile)).
  IF ttpi_s >= 0 { lm_store_put_time(vault, "TTPI", ttpi_s). }
  SET LM_VEH["STORE"] TO vault.
  SET LM_VEH["XDELV"] TO FALSE.
  RETURN vault.
}
FUNCTION t34_keys { RETURN keys_new(LM_NOUNS, LM_VERBS, LM_PROGS). }
// t34_step: one cycle with the pilot's answer "NONE", "PRO", "V32", "V34", then the answer cleared as the core does.
FUNCTION t34_step {
  PARAMETER prog, key_state, answer.
  SET prog["NOW_UT"] TO T34_NOW.
  SET key_state["PRO"] TO answer = "PRO".
  SET key_state["RECYCLE"] TO answer = "V32".
  SET key_state["TERMINATE"] TO answer = "V34".
  LOCAL out IS p34_step(prog, key_state).
  SET key_state["PRO"] TO FALSE.
  SET key_state["RECYCLE"] TO FALSE.
  SET key_state["TERMINATE"] TO FALSE.
  RETURN out.
}
// t34_shows: the cycle set this verb and noun and asks for an answer to it.
FUNCTION t34_shows {
  PARAMETER out, verb_no, noun_no.
  IF out["SET_VERB"] <> verb_no OR out["SET_NOUN"] <> noun_no { RETURN FALSE. }
  IF NOT out["REQUEST"]:ISTYPE("Lexicon") { RETURN FALSE. }
  RETURN out["REQUEST"]["VERB"] = verb_no AND out["REQUEST"]["NOUN"] = noun_no.
}
FUNCTION t34_regs {
  PARAMETER noun_no, out.
  LOCAL derived IS LEXICON("VALID", FALSE).
  FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
  RETURN noun_registers(noun_no, derived).
}
// t34_to_second: a J profile P34 at its second display, with the elevation angle keyed (0 computes it). LEXICON("PROG", "KS", "VAULT", "OUT").
FUNCTION t34_to_second {
  PARAMETER ttpi_s, elev_deg.
  LOCAL vault IS t34_vault("J", ttpi_s).
  LOCAL prog IS p34_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@).
  LOCAL key_state IS t34_keys().
  t34_step(prog, key_state, "NONE").
  t34_step(prog, key_state, "PRO").
  lm_store_put_n55(vault, -1, elev_deg, -1).
  LOCAL out IS t34_step(prog, key_state, "PRO").
  RETURN LEXICON("PROG", prog, "KS", key_state, "VAULT", vault, "OUT", out).
}

LOCAL keep_store IS FALSE.
IF LM_VEH:HASKEY("STORE") { SET keep_store TO LM_VEH["STORE"]. }

// ---- P34, J profile, elevation computed ----
LOCAL vault IS t34_vault("J", -1).
LOCAL prog IS p34_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@).
assert_true("starts with a good snapshot", prog["REFUSED"] = "").
LOCAL key_state IS t34_keys().
LOCAL out IS t34_step(prog, key_state, "NONE").
assert_true("first cycle shows V06 N37", t34_shows(out, 6, 37)).
assert_near("PROG shows 34", out["PROG_NO"], 34, 0).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("no TPI time stays at N37 with a warning", t34_shows(out, 6, 37) AND out["WARN"]:LENGTH > 0).
lm_store_put_time(vault, "TTPI", 6300).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("a past TPI time stays at N37 with a warning", t34_shows(out, 6, 37) AND out["WARN"]:LENGTH > 0 AND NOT out["ENDED"]).
lm_store_put_time(vault, "TTPI", 7000).
lm_store_put_n55(vault, 5, 33, 90).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("PRO at N37 shows V06 N55", t34_shows(out, 6, 55)).
LOCAL regs IS t34_regs(55, out).
assert_true("J: N55 shows NN 0, elevation 0, central angle 130", regs[0] = "+00000" AND regs[1] = "+00000" AND regs[2] = "+13000").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("elevation zero: V06 N55 again", t34_shows(out, 6, 55) AND out["ALARM"] = 0).
assert_near("with the elevation worked out (deg)", lm_store_get_n55(vault)["ELEV"], 26.6, 0.001).
assert_near("and the TPI time as keyed", lm_store_get_time(vault, "TTPI"), 7000, 0.01).
assert_true("no burn is set yet", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("PRO computes the transfer and shows V06 N58", t34_shows(out, 6, 58) AND out["ALARM"] = 0).
SET regs TO t34_regs(58, out).
assert_true("N58 perilune, TPI and intercept delta-V", regs[0] = "+00448" AND regs[1] = "+00246" AND regs[2] = "+00316").
assert_near("N52 central angle (deg)", out["EXTRA"]["RN_CENT"], 131.6699, 0.001).
assert_vec("N59 along, right, down (m/s)", out["EXTRA"]["RN_DVLOS"], V(7.48290, 0, 0.00953), 0.001).
assert_near("intercept time stored (s)", lm_store_get_time(vault, "TPASS4"), 9575.342, 0.01).
assert_near("TIG is the TPI time (s)", lm_store_get_tig(vault), 7000, 0.01).
assert_vec("N81 holds the TPI delta-V, local vertical (m/s)", lm_store_get_dv(vault), V(6.69513, 0, -3.34202), 0.001).
assert_true("the burn is set", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
IF LM_VEH["XDELV"]:ISTYPE("Lexicon") {
  LOCAL xd IS LM_VEH["XDELV"].
  assert_vec("DELVSIN (m/s)", xd["DELVSIN"], V(7.47049, 0, 0.43098), 0.001).
  assert_near("UT_TIG", xd["UT_TIG"], 8000, 0.01).
  assert_vec("RTIG is the LM at TPI (m)", xd["RTIG"], T34_R, 1).
  assert_vec("the aim point (m)", xd["AIM"]["R"], V(586581.134, 0, 1752982.819), 1).
  assert_near("the intercept UT", xd["AIM"]["UT"], 10575.342, 0.01).
  assert_true("not rotated", NOT xd["AIM"]["ROTATED"]).
  LOCAL burn IS p41_start(FALSE, vault, T34_ZERO, "J", T34_NOW, 0, xd, V(1, 0, 0), V(0, 1, 0)).
  assert_true("P41 accepts the burn", burn["REFUSED"] = "").
  IF burn["REFUSED"] = "" { p41_end(burn). }
}
SET out TO t34_step(prog, key_state, "V32").
assert_true("V32 at N58 shows it again without advancing", t34_shows(out, 6, 58)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("J: PRO at N58 shows V06 N81", t34_shows(out, 6, 81)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("J: PRO at N81 shows V16 N45", t34_shows(out, 16, 45)).
assert_near("N45 time to go (s)", out["EXTRA"]["P30_TTOGO"], 600, 0.01).
assert_near("N45 gimbal angle is -00.01 before the final computation", out["EXTRA"]["P30_MGA"], -0.01, 1e-9).
SET out TO t34_step(prog, key_state, "V32").
assert_true("V32 at N45 computes again (the elevation display)", t34_shows(out, 6, 55)).
t34_step(prog, key_state, "PRO").
t34_step(prog, key_state, "PRO").
t34_step(prog, key_state, "PRO").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("the first PRO at N45 makes the final computation (N55 again)", t34_shows(out, 6, 55) AND NOT out["ENDED"]).
t34_step(prog, key_state, "PRO").
t34_step(prog, key_state, "PRO").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("back at N45", t34_shows(out, 16, 45)).
assert_near("the final computation shows the gimbal angle (in-plane burn)", SIN(out["EXTRA"]["P30_MGA"]), 0, 0.0001).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("the next PRO at N45 ends P34", out["ENDED"]).

// ---- the elevation angle keyed: the TPI time is moved ----
LOCAL t34_run IS t34_to_second(7240, 26.6).
assert_true("elevation keyed: V06 N37 shows the time found", t34_shows(t34_run["OUT"], 6, 37) AND t34_run["OUT"]["ALARM"] = 0).
assert_near("within 10 s of the 26.6 degree time", lm_store_get_time(t34_run["VAULT"], "TTPI"), 7000, 10).
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
assert_true("then the transfer (N58)", t34_shows(out, 6, 58)).
assert_near("TIG is the time found (s)", lm_store_get_tig(t34_run["VAULT"]), lm_store_get_time(t34_run["VAULT"], "TTPI"), 0.01).

// ---- alarm 611 ----
SET t34_run TO t34_to_second(7000, 200).
SET out TO t34_run["OUT"].
assert_true("an angle that cannot be reached: alarm 611, V05 N09", t34_shows(out, 5, 9) AND out["ALARM"] = 611).
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "V32").
assert_true("V32 shows the alarm again", t34_shows(out, 5, 9) AND out["ALARM"] = 611).
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
assert_true("PRO starts again at V06 N37", t34_shows(out, 6, 37) AND out["ALARM"] = 0).
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "V34").
assert_true("V34 ends P34", out["ENDED"]).

// ---- a keyed N81 gives a new aim point ----
SET t34_run TO t34_to_second(7000, 0).
t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
LOCAL was_aim IS LM_VEH["XDELV"]["AIM"]["R"].
LOCAL was_dv IS LM_VEH["XDELV"]["DELVSIN"].
LOCAL dv_shown IS lm_store_get_dv(t34_run["VAULT"]).
lm_store_put_dv(t34_run["VAULT"], V(dv_shown:X, dv_shown:Y + 0.5, dv_shown:Z)).
t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
LOCAL keyed IS LM_VEH["XDELV"].
assert_near("the keyed 0.5 m/s is in the burn", (keyed["DELVSIN"] - was_dv):MAG, 0.5, 0.001).
assert_true("the aim point moves with it", (keyed["AIM"]["R"] - was_aim):MAG > 100).
assert_vec("and the velocity to gain for it is the keyed delta-V",
    s40_aim(keyed["RTIG"], keyed["VTIG"], keyed["AIM"]["R"], keyed["AIM"]["UT"] - keyed["UT_TIG"], T34_MU, keyed["AIM"]["ROTATED"])["VG"], keyed["DELVSIN"], 0.001).

// ---- odd central angles ----
SET t34_run TO t34_to_second(7000, 0).
lm_store_put_n55(t34_run["VAULT"], -1, -1, 0).
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
assert_true("central angle 0: alarm 20607 and P34 ends", out["ALARM"] = 20607 AND out["ENDED"]).
assert_true("with no burn set", NOT LM_VEH["XDELV"]:ISTYPE("Lexicon")).
FOR t34_angle IN LIST(1, 180, 359.99) {
  SET t34_run TO t34_to_second(7000, 0).
  lm_store_put_n55(t34_run["VAULT"], 99, -1, t34_angle).
  SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
  assert_true("central angle " + t34_angle + ": a solution or alarm 20607", t34_shows(out, 6, 58) OR out["ALARM"] = 20607).
}

// ---- P34, Apollo 11: the elevation angle is kept, N59 flashes, N81 comes with the final computation ----
SET vault TO t34_vault("A11", 7000).
SET prog TO p34_start(FALSE, vault, T34_ZERO, "A11", T34_NOW, t34_snap@).
SET key_state TO t34_keys().
t34_step(prog, key_state, "NONE").
SET out TO t34_step(prog, key_state, "PRO").
SET regs TO t34_regs(55, out).
assert_true("A11: an unloaded elevation shows 26.60", regs[0] = "+00000" AND regs[1] = "+02660" AND regs[2] = "+13000").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11: the time is searched (V06 N37)", t34_shows(out, 6, 37)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11: N58", t34_shows(out, 6, 58)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11 first pass: N59, no N81", t34_shows(out, 6, 59)).
assert_true("A11: the burn is already set", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("then N45", t34_shows(out, 16, 45)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("the final computation: N37", t34_shows(out, 6, 37)).
t34_step(prog, key_state, "PRO").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11 final: N81", t34_shows(out, 6, 81)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("then N59", t34_shows(out, 6, 59)).
t34_step(prog, key_state, "PRO").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11: the last PRO ends P34", out["ENDED"]).
lm_store_put_n55(vault, -1, 30, -1).
SET prog TO p34_start(FALSE, vault, T34_ZERO, "A11", T34_NOW, t34_snap@).
SET key_state TO t34_keys().
t34_step(prog, key_state, "NONE").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11 keeps a stored elevation of 30", t34_regs(55, out)[1] = "+03000").

// ---- the CSM lost ----
SET t34_run TO t34_to_second(7000, 0).
SET T34_LOST TO TRUE.
SET out TO t34_step(t34_run["PROG"], t34_run["KS"], "PRO").
assert_true("the CSM lost: a warning and P34 ends", out["ENDED"] AND out["WARN"]:LENGTH > 0).
assert_true("and a start is refused", p34_start(FALSE, t34_run["VAULT"], T34_ZERO, "J", T34_NOW, t34_snap@)["REFUSED"] <> "").
assert_true("P35 too", p35_start(FALSE, t34_run["VAULT"], T34_ZERO, "J", T34_NOW, t34_snap@)["REFUSED"] <> "").
SET T34_LOST TO FALSE.

// ---- P35: 900 s after a TPI with an error, from a store that holds only the intercept time (a DSKY restart) ----
SET T34_LM_V TO T34_V + V(7.47049, 0, 0.43098) + V(0.2, 0.3, -0.1).
SET T34_NOW TO 8720.
SET vault TO t34_vault("J", -1).
assert_true("P35 with no intercept time is refused", p35_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@)["REFUSED"] <> "").
lm_store_put_time(vault, "TPASS4", 7870).
assert_true("P35 with the intercept under 3 minutes away is refused", p35_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@)["REFUSED"] <> "").
lm_store_put_time(vault, "TPASS4", 9575.342).
SET prog TO p35_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@).
assert_true("P35 starts from the stored intercept time", prog["REFUSED"] = "").
SET key_state TO t34_keys().
SET out TO t34_step(prog, key_state, "NONE").
assert_true("P35 computes at once and shows V06 N81 (J)", t34_shows(out, 6, 81) AND out["PROG_NO"] = 35).
assert_near("TIG is 180 s from now (s)", lm_store_get_tig(vault), 7900, 0.01).
assert_true("the midcourse burn is set", LM_VEH["XDELV"]:ISTYPE("Lexicon")).
IF LM_VEH["XDELV"]:ISTYPE("Lexicon") {
  assert_vec("midcourse delta-V (m/s)", LM_VEH["XDELV"]["DELVSIN"], V(-0.58154, -0.22405, 0.17317), 0.002).
  assert_near("the intercept UT is unchanged", LM_VEH["XDELV"]["AIM"]["UT"], 10575.342, 0.01).
  LOCAL burn35 IS p41_start(FALSE, vault, T34_ZERO, "J", T34_NOW, 0, LM_VEH["XDELV"], V(1, 0, 0), V(0, 1, 0)).
  assert_true("P41 accepts the midcourse", burn35["REFUSED"] = "").
  IF burn35["REFUSED"] = "" { p41_end(burn35). }
}
SET out TO t34_step(prog, key_state, "PRO").
assert_true("PRO at N81 shows V16 N45", t34_shows(out, 16, 45)).
assert_near("N45 time to go (s)", out["EXTRA"]["P30_TTOGO"], 180, 0.01).
assert_near("P35 N45 gimbal angle is -00.01 before the final computation", out["EXTRA"]["P30_MGA"], -0.01, 1e-9).
SET T34_NOW TO 8750.
SET out TO t34_step(prog, key_state, "PRO").
assert_true("the final computation shows N81 again", t34_shows(out, 6, 81)).
assert_near("with a new TIG (s)", lm_store_get_tig(vault), 7930, 0.01).
t34_step(prog, key_state, "PRO").
SET out TO t34_step(prog, key_state, "PRO").
assert_true("the next PRO at N45 ends P35", out["ENDED"]).
SET prog TO p35_start(FALSE, vault, T34_ZERO, "J", T34_NOW, t34_snap@).
t34_step(prog, key_state, "NONE").
t34_step(prog, key_state, "PRO").
SET T34_NOW TO 10450.
SET out TO t34_step(prog, key_state, "V32").
assert_true("a recompute too close to the intercept ends P35 with a warning", out["ENDED"] AND out["WARN"]:LENGTH > 0).
SET T34_NOW TO 8720.
SET vault TO t34_vault("A11", -1).
lm_store_put_time(vault, "TPASS4", 9575.342).
SET prog TO p35_start(FALSE, vault, T34_ZERO, "A11", T34_NOW, t34_snap@).
SET key_state TO t34_keys().
SET out TO t34_step(prog, key_state, "NONE").
assert_true("A11 P35 first shows V06 N59", t34_shows(out, 6, 59)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("then N45", t34_shows(out, 16, 45)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("A11 final: N81", t34_shows(out, 6, 81)).
SET out TO t34_step(prog, key_state, "PRO").
assert_true("then N59", t34_shows(out, 6, 59)).

// ---- the vehicle table ----
assert_true("the table has P34 and P35", lm_programme_table():HASKEY("34") AND lm_programme_table():HASKEY("35")).
assert_true("V37 can select them", LM_PROGS:CONTAINS(34) AND LM_PROGS:CONTAINS(35)).

SET LM_VEH["XDELV"] TO FALSE.
IF keep_store:ISTYPE("Lexicon") { SET LM_VEH["STORE"] TO keep_store. }
SET P34_LOG_PATH TO t34_keep_log.
SET CTL_DRY TO FALSE.
test_end().
