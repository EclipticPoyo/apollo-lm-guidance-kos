// test_p40.ks -- pad test for P40, the DPS burn (lm/burn/lm_p40.ks), N40, N85 and the P40 table entry. No flight: CTL_DRY is TRUE, the ship's state is made up (the DOI case:
// a circular orbit 60 nmi up, r along +X, v along +Z, a delta-V of 23.1 m/s against the motion). The ship's thrust is modelled here as a steady acceleration along the burn
// direction while the programme has the engine lit; the Moon's gravity is zero in the made-up state (MU 0), so the measured delta-V is the thrust alone.
//   RUNPATH("0:/tests/test_p40.ks").   Log: 0:/lm/logs/test_p40.log.
// Written in release 1.4 and not yet run in KSP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").
RUNONCEPATH("0:/lm/burn/lm_servicer.ks").

test_begin("0:/lm/logs/test_p40.log").
SET CTL_DRY TO TRUE.
LOCAL keep_thr IS ENG_THR_CONT.
LOCAL keep_lever IS CTL_DRY_LEVER.
SET ENG_THR_CONT TO "AUTO".

GLOBAL D_V0 IS V(0, 0, 1628.5834302711191).
GLOBAL D_V IS D_V0.
GLOBAL D_T IS 2000.
GLOBAL D_U IS V(0, 0, -1).

// d_state: the ship's state at now_ut with velocity v_vec and the thrust the engine gives, kN.
FUNCTION d_state {
  PARAMETER now_ut, v_vec, thrust_kn.
  RETURN LEXICON("R", V(1848520, 0, 0), "V", v_vec, "T", now_ut, "MASS", 15.2697, "THRUST", 46.71, "THRUST_NOW", thrust_kn, "MU", 0,
                 "BODY_OK", TRUE, "ALT_RADAR", 15000, "XNB", V(0, 0, 1)).
}
FUNCTION d_keys {
  PARAMETER verb_no, noun_no.
  LOCAL key_state IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
  SET key_state["VERB"] TO verb_no.
  SET key_state["NOUN"] TO noun_no.
  RETURN key_state.
}
FUNCTION d_clear {
  PARAMETER key_state.
  SET key_state["PRO"] TO FALSE.
  SET key_state["RECYCLE"] TO FALSE.
  SET key_state["TERMINATE"] TO FALSE.
  SET key_state["ENTER"] TO FALSE.
}
// d_xd: what P30 keeps (frame 0 = the axes of UT 1100): the DOI delta-V direction scaled to dv_mag.
FUNCTION d_xd {
  PARAMETER dv_mag.
  LOCAL dir_vec IS V(-9.8 * 0.3048, 0, -75.8 * 0.3048):NORMALIZED.
  RETURN LEXICON("DELVSIN", dir_vec * dv_mag, "RTIG", V(1848520, 0, 0), "VTIG", V(0, 0, 1628.5834302711191), "UT_TIG", 2500, "DELVSAB", dv_mag, "T0", 1100).
}
// d_start: P40 started at UT 2000 with TIG at UT 2500 (clock zero 1000, TIG 1500 s on the clock), the engine thrust 46.71 kN, the Moon's spin zero.
FUNCTION d_start {
  PARAMETER dv_mag.
  LOCAL vault IS store_new(lm_cells_for("A11")).
  lm_store_put_tig(vault, 1500).
  RETURN p40_start(FALSE, vault, 1000, "A11", 2000, 0, 46710, d_xd(dv_mag), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
}
// d_step: one cycle at now_ut with the key state; the keys are cleared after, as the core does.
FUNCTION d_step {
  PARAMETER prog, now_ut, v_vec, thrust_kn, key_state.
  LOCAL out IS p40_step(prog, d_state(now_ut, v_vec, thrust_kn), LEXICON("VALID", FALSE), key_state).
  d_clear(key_state).
  RETURN out.
}
// d_to_burn: R60 skipped with ENTR, then (MAN: the 203 request answered with ENTR) into the BURN phase, all at UT 2000.
FUNCTION d_to_burn {
  PARAMETER prog.
  LOCAL ks IS d_keys(16, 60).
  d_step(prog, 2000, D_V0, 0, ks).                    // CHECK
  d_step(prog, 2000, D_V0, 0, ks).                    // R60 shown
  SET ks["VERB"] TO 50.
  SET ks["NOUN"] TO 18.
  SET ks["ENTER"] TO TRUE.
  d_step(prog, 2000, D_V0, 0, ks).                    // ENTR: R60 done
  IF prog["MAN"] {
    d_step(prog, 2000, D_V0, 0, ks).                  // the 203 request shown
    SET ks["VERB"] TO 50.
    SET ks["NOUN"] TO 25.
    SET ks["ENTER"] TO TRUE.
  }
  d_step(prog, 2000, D_V0, 0, ks).                    // P40AUTO answered: P41SPOT, the sequence made
}
// d_loop: step in 0.25 s cycles from D_T to t_to; the thrust is accel m/s2 along D_U while the engine is lit. Returns the last output; stops when the phase leaves BURN or the programme ends.
FUNCTION d_loop {
  PARAMETER prog, key_state, t_to, accel.
  LOCAL out IS LEXICON().
  UNTIL D_T >= t_to - 0.001 OR prog["PHASE"] <> "BURN" OR prog["ENDED"] {
    SET D_T TO D_T + 0.25.
    IF prog["ENGINE_LIT"] { SET D_V TO D_V + D_U * accel * 0.25. }
    SET out TO d_step(prog, D_T, D_V, (CHOOSE 8.5 IF prog["ENGINE_LIT"] ELSE 0), key_state).
  }
  RETURN out.
}
FUNCTION d_regs {
  PARAMETER noun_no, out.
  LOCAL derived IS LEXICON("VALID", FALSE).
  FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
  RETURN noun_registers(noun_no, derived).
}

// ---- refusals ----
LOCAL vault_ok IS store_new(lm_cells_for("A11")).
lm_store_put_tig(vault_ok, 1500).
LOCAL refused IS p40_start(FALSE, vault_ok, 1000, "A11", 2000, 0, 46710, FALSE, V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("refuses before P30 has run, and says so", refused["REFUSED"]:CONTAINS("run P30 first")).
SET refused TO p40_start(FALSE, store_new(lm_cells_for("A11")), 1000, "A11", 2000, 0, 46710, d_xd(23.1), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("refuses when TIG is not loaded", refused["REFUSED"]:CONTAINS("TIG is not loaded")).
SET refused TO p40_start(FALSE, vault_ok, 1000, "A11", 2000, 0, 46710, d_xd(0), V(0, 0, 0), V(1, 0, 0), V(0, 1, 0)).
assert_true("refuses a delta-V of zero", refused["REFUSED"]:CONTAINS("zero")).
assert_true("a good start is not refused", d_start(23.1)["REFUSED"] = "").

// ---- the frames: P30's vectors are turned to the live axes by the Moon's spin ----
LOCAL pspin IS d_start(23.1).
SET pspin["WM"] TO V(0, 2.66e-6, 0).
LOCAL spun IS servicer_live(pspin, V(1, 0, 0), 1100 + 3600).
assert_near("an hour of the Moon's spin turns the vector 0.5487 degrees", VANG(spun, V(1, 0, 0)), 2.66e-6 * 3600 * 180 / CONSTANT:PI, 1e-4).
assert_vec("and servicer_to0 turns it back", servicer_to0(pspin, spun, 1100 + 3600), V(1, 0, 0), 1e-9).

// ---- the servicer pass does not see the Moon's spin as a velocity change (the raw axes turn with the Moon) ----
LOCAL ppass IS d_start(23.1).
SET ppass["WM"] TO V(0, 2.66e-6, 0).
LOCAL v_inertial IS V(0, 0, 1630).         // a ship drifting at constant inertial velocity, no gravity (MU 0): nothing is gained
LOCAL pass_state IS LEXICON("V", servicer_live(ppass, v_inertial, 3000), "R", V(1850000, 0, 0), "MU", 0).
servicer_pass(ppass, pass_state, 3000, FALSE).
SET pass_state["V"] TO servicer_live(ppass, v_inertial, 3002).
LOCAL pass_data IS servicer_pass(ppass, pass_state, 3002, FALSE).
assert_true("the pass closes after 2 s", pass_data:ISTYPE("Lexicon")).
assert_near("a ship drifting inertially gains nothing, whatever the Moon's spin", pass_data["DELVREF"]:MAG, 0, 1e-6).

// ---- alarm 1706: the descent stage is gone ----
LOCAL pstg IS d_start(23.1).
SET pstg["F_MAX_N"] TO 15570.
LOCAL ks_stg IS d_keys(16, 60).
LOCAL out IS d_step(pstg, 2000, D_V0, 0, ks_stg).
assert_true("with only the ascent engine the first cycle is the stage alarm", pstg["PHASE"] = "STAGED" AND NOT out["ENDED"]).
SET out TO d_step(pstg, 2000.25, D_V0, 0, ks_stg).
assert_true("the alarm 1706 display is flashing V05 N09", out["ALARM"] = 1706 AND out["SET_VERB"] = 5 AND out["SET_NOUN"] = 9 AND out["REQUEST"]["VERB"] = 5 AND out["REQUEST"]["NOUN"] = 9).
SET out TO d_step(pstg, 2000.5, D_V0, 0, ks_stg).
assert_true("and stays up without raising the alarm again", out["ALARM"] = 0 AND out["SET_VERB"] < 0 AND out["REQUEST"]:ISTYPE("Lexicon")).
SET ks_stg["PRO"] TO TRUE.
SET out TO d_step(pstg, 2000.75, D_V0, 0, ks_stg).
assert_true("PRO with the stage still gone looks again: the alarm comes back", pstg["PHASE"] = "STAGED" AND out["ALARM"] = 1706).
SET pstg["F_MAX_N"] TO 46710.
SET ks_stg["RECYCLE"] TO TRUE.
SET out TO d_step(pstg, 2001.25, D_V0, 0, ks_stg).
assert_true("V32 with the engine back goes on to the checks", pstg["PHASE"] = "CHECK").
LOCAL pstg2 IS d_start(23.1).
SET pstg2["F_MAX_N"] TO 15570.
LOCAL ks_stg2 IS d_keys(16, 60).
d_step(pstg2, 2000, D_V0, 0, ks_stg2).
d_step(pstg2, 2000.25, D_V0, 0, ks_stg2).
SET ks_stg2["TERMINATE"] TO TRUE.
SET out TO d_step(pstg2, 2000.5, D_V0, 0, ks_stg2).
assert_true("V34 at the alarm display ends the programme", out["ENDED"]).
p40_end(pstg2).
assert_near("and leaves the throttle at zero", CTL_THR, 0, 0).

// ---- R02: IMU alarms ----
LOCAL pimu IS d_start(23.1).
SET pimu["IMU_OK"] TO FALSE.
SET out TO d_step(pimu, 2000, D_V0, 0, d_keys(16, 60)).
assert_true("IMU on but its orientation unknown: alarm 220 and the programme ends", out["ALARM"] = 220 AND out["ENDED"] AND out["SET_VERB"] < 0).
SET pimu TO d_start(23.1).
SET pimu["IMU_OK"] TO FALSE.
SET pimu["IMU_ON"] TO FALSE.
SET out TO d_step(pimu, 2000, D_V0, 0, d_keys(16, 60)).
assert_true("IMU off: alarm 210", out["ALARM"] = 210 AND out["ENDED"]).

// ---- S40 and R60 ----
LOCAL pr IS d_start(23.1).
LOCAL ks_r IS d_keys(16, 60).
SET out TO d_step(pr, 2000, D_V0, 0, ks_r).
assert_true("the first cycle does the checks and goes to R60", pr["PHASE"] = "R60").
assert_near("S40.1: VG is the delta-V", pr["VG"]:MAG, 23.1, 1e-6).
assert_true("S40.13: a 23.1 m/s burn is under 95 s at the minimum thrust: NOTHROTL", pr["NOTHROTL"]).
assert_true("S40.2,3: the thrust axis is the delta-V direction", VANG(pr["AXES"]["X"], pr["VG"]) < 0.001).
assert_true("N18 has three angles", pr["N18"]:LENGTH = 3 AND ABS(pr["N18"][0]) < 360 AND ABS(pr["N18"][1]) < 360 AND ABS(pr["N18"][2]) < 360).
SET out TO d_step(pr, 2000.25, D_V0, 0, ks_r).
assert_true("R60 shows V50 N18 flashing", out["SET_VERB"] = 50 AND out["SET_NOUN"] = 18 AND out["REQUEST"]["VERB"] = 50 AND out["REQUEST"]["NOUN"] = 18).
SET ks_r["PRO"] TO TRUE.
SET out TO d_step(pr, 2000.5, D_V0, 0, ks_r).
assert_true("PRO starts the manoeuvre: a steady V06 N18", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 18 AND NOT out["REQUEST"]:ISTYPE("Lexicon") AND pr["CMD_BURN"]).
assert_true("and the command is the burn attitude", VANG(CTL_GOAL_DIR, pr["AXES"]["X"]) < 0.001).
LOCAL regs_n18 IS d_regs(18, out).
assert_true("N18 shows the angles", regs_n18[0]:LENGTH = 6).
LOCAL regs_n25 IS d_regs(25, out).
assert_true("N25 shows the code 00203", regs_n25[0] = " 00203").
// V34 at the R60 request ends the programme.
LOCAL pr2 IS d_start(23.1).
LOCAL ks_r2 IS d_keys(16, 60).
d_step(pr2, 2000, D_V0, 0, ks_r2).
d_step(pr2, 2000.25, D_V0, 0, ks_r2).
SET ks_r2["TERMINATE"] TO TRUE.
SET out TO d_step(pr2, 2000.5, D_V0, 0, ks_r2).
assert_true("V34 at the R60 request ends P40", out["ENDED"]).

// ---- P40AUTO, AUTO: no prompt; MAN: the 203 request with its three returns ----
LOCAL pa IS d_start(23.1).
d_to_burn(pa).
assert_true("ENG_THR_CONT AUTO and attitude AUTO: no checklist request, straight into the burn phase", pa["PHASE"] = "BURN" AND pa["BB"]:ISTYPE("Lexicon")).
assert_near("TIG is as loaded (no slip 500 s ahead)", pa["TIG"], 2500, 1e-6).
SET ENG_THR_CONT TO "MAN".
LOCAL pm IS d_start(23.1).
LOCAL ks_m IS d_keys(16, 60).
d_step(pm, 2000, D_V0, 0, ks_m).
d_step(pm, 2000, D_V0, 0, ks_m).
SET ks_m["VERB"] TO 50.
SET ks_m["NOUN"] TO 18.
SET ks_m["ENTER"] TO TRUE.
d_step(pm, 2000, D_V0, 0, ks_m).
SET out TO d_step(pm, 2000.25, D_V0, 0, ks_m).
assert_true("MAN: the checklist request V50 N25 flashes", pm["PHASE"] = "AUTO" AND out["SET_VERB"] = 50 AND out["SET_NOUN"] = 25 AND out["REQUEST"]["VERB"] = 50 AND out["REQUEST"]["NOUN"] = 25).
assert_true("and N25 shows 00203", d_regs(25, out)[0] = " 00203").
SET ks_m["PRO"] TO TRUE.
SET out TO d_step(pm, 2000.5, D_V0, 0, ks_m).
SET out TO d_step(pm, 2000.75, D_V0, 0, ks_m).
assert_true("PRO re-checks: MAN is still set, so the request stays", pm["PHASE"] = "AUTO" AND out["REQUEST"]:ISTYPE("Lexicon")).
SET ks_m["VERB"] TO 50.
SET ks_m["NOUN"] TO 25.
SET ks_m["ENTER"] TO TRUE.
d_step(pm, 2001, D_V0, 0, ks_m).
assert_true("ENTR goes on without re-checking", pm["PHASE"] = "BURN").
assert_true("MAN throttle is remembered from the setting", pm["MAN"]).
LOCAL pm2 IS d_start(23.1).
LOCAL ks_m2 IS d_keys(16, 60).
d_step(pm2, 2000, D_V0, 0, ks_m2).
d_step(pm2, 2000, D_V0, 0, ks_m2).
SET ks_m2["VERB"] TO 50.
SET ks_m2["NOUN"] TO 18.
SET ks_m2["ENTER"] TO TRUE.
d_step(pm2, 2000, D_V0, 0, ks_m2).
d_step(pm2, 2000.25, D_V0, 0, ks_m2).
SET ks_m2["TERMINATE"] TO TRUE.
SET out TO d_step(pm2, 2000.5, D_V0, 0, ks_m2).
assert_true("V34 at the 203 request ends P40", out["ENDED"]).
SET ENG_THR_CONT TO "AUTO".

// ---- P41SPOT: alarm 1703 ----
FUNCTION d_to_burn_at {
  PARAMETER prog, now_ut.
  LOCAL ks IS d_keys(16, 60).
  d_step(prog, now_ut, D_V0, 0, ks).
  d_step(prog, now_ut, D_V0, 0, ks).
  SET ks["VERB"] TO 50.
  SET ks["NOUN"] TO 18.
  SET ks["ENTER"] TO TRUE.
  d_step(prog, now_ut, D_V0, 0, ks).
  RETURN d_step(prog, now_ut, D_V0, 0, ks).
}
LOCAL ps1 IS d_start(23.1).
SET out TO d_to_burn_at(ps1, 2480).
assert_true("TIG 20 s ahead is slipped: alarm 1703", out["ALARM"] = 1703).
assert_near("and the new TIG is now + 49.9", ps1["TIG"], 2480 + 49.9, 1e-6).
assert_near("the sequence is made for the new TIG", ps1["BB"]["TIG"], 2480 + 49.9, 1e-6).
LOCAL ps2 IS d_start(23.1).
SET out TO d_to_burn_at(ps2, 2600).
assert_true("TIG in the past is slipped too", out["ALARM"] = 1703 AND ABS(ps2["TIG"] - 2649.9) < 1e-6).
LOCAL ps3 IS d_start(23.1).
SET out TO d_to_burn_at(ps3, 2420).
assert_true("TIG 80 s ahead is not slipped", out["ALARM"] = 0 AND ps3["TIG"] = 2500).

// ---- the countdown, the prompt, ignition (AUTO) ----
LOCAL pb IS d_start(23.1).
d_to_burn(pb).
LOCAL ks_b IS d_keys(6, 40).
SET D_T TO 2000.
SET D_V TO D_V0.
SET out TO d_step(pb, 2001, D_V0, 0, ks_b).
assert_true("the clock display V06 N40 is set as the burn phase starts", out["SET_VERB"] = 6 AND out["SET_NOUN"] = 40).
SET out TO d_step(pb, 2450, D_V0, 0, ks_b).
LOCAL regs_n40 IS d_regs(40, out).
assert_true("N40 R1 is -00 50 fifty seconds before ignition", regs_n40[0] = "-00 50").
assert_true("N40 R2 is the 23.1 m/s to be gained in ft/s (0.1)", regs_n40[1] = fmt_reg(ms_to_fps(23.1), 1)).
SET out TO d_step(pb, 2465.2, D_V0, 0, ks_b).
assert_true("the display is blank from TIG - 34.9 to TIG - 29.9", out["BLANK"]).
SET out TO d_step(pb, 2475, D_V0, 0, ks_b).
assert_true("and back after, with V06 N40", NOT out["BLANK"] AND out["SET_VERB"] = 6 AND out["SET_NOUN"] = 40).
d_step(pb, 2492.4, D_V0, 0, ks_b).
assert_true("no ullage at TIG - 7.6 (the P40 table has TIG - 7.5)", NOT pb["ULLAGE_ON"]).
d_step(pb, 2492.6, D_V0, 0, ks_b).
assert_true("ullage on at TIG - 7.4", pb["ULLAGE_ON"]).
SET out TO d_step(pb, 2496, D_V0, 0, ks_b).
assert_true("the prompt: flashing V99 N40", out["SET_VERB"] = 99 AND out["SET_NOUN"] = 40 AND out["REQUEST"]["VERB"] = 99 AND out["REQUEST"]["NOUN"] = 40).
assert_true("S40.13 at the prompt: NOTHROTL stays set for 23.1 m/s", pb["NOTHROTL"] AND pb["BB"]["NOTHROTL"]).
// a V34 outside a request does nothing (no request up in the coast)
LOCAL pcoast IS d_start(23.1).
d_to_burn(pcoast).
LOCAL ks_coast IS d_keys(6, 40).
d_step(pcoast, 2001, D_V0, 0, ks_coast).
SET ks_coast["TERMINATE"] TO TRUE.
SET out TO d_step(pcoast, 2002, D_V0, 0, ks_coast).
assert_true("V34 in the coast with no request up does nothing", NOT out["ENDED"]).
// PRO enables, ignition at TIG
SET ks_b["PRO"] TO TRUE.
d_step(pb, 2497, D_V0, 0, ks_b).
assert_true("PRO enables the engine, which waits for TIG", NOT pb["ENGINE_LIT"]).
SET D_T TO 2499.75.
SET out TO d_step(pb, 2500, D_V0, 0, ks_b).
assert_true("ignition at TIG", pb["ENGINE_LIT"] AND pb["IGN_T"] = 2500).
assert_near("lit at the minimum throttle", CTL_THR, THR_MIN_FRAC, 0).
SET D_T TO 2500.
SET D_V TO D_V0.
// fly the burn: 0.5 m/s2 while lit; the time to go comes from the measured delta-V, so the cutoff is on the true 46 s, not the 74 s estimate
SET out TO d_loop(pb, ks_b, 2525, 0.5).
assert_true("NOTHROTL: no throttle-up at ignition + 26 s", NOT pb["BB"]["ZOOMED"] AND pb["THR"] = THR_MIN_FRAC).
assert_true("the status readout says AUTO throttle", out["STATUS"][0]:CONTAINS("AUTO")).
assert_true("VG is being brought down by the measured delta-V", pb["VG"]:MAG < 23.1 - 8 AND pb["VG"]:MAG > 23.1 - 14).
assert_true("the time to go has been measured: a cutoff is set", pb["BB"]["CUT_UT"] > 0 AND pb["BB"]["CUT_UT"] < 2500 + 50).
SET out TO d_loop(pb, ks_b, 2600, 0.5).
assert_true("the cutoff fires and P40 goes to the post-burn phase", pb["PHASE"] = "POST").
assert_near("the delta-V gained at cutoff is the 23.1 m/s (within 0.8)", (D_V - D_V0):MAG, 23.1, 0.8).
assert_near("the throttle command is zero after the cutoff", CTL_THR, 0, 0).
assert_true("the steering had stopped under 4 s to go", NOT pb["STEER"]).
assert_true("the engine is no longer lit", NOT pb["ENGINE_LIT"]).
SET out TO d_step(pb, D_T + 0.25, D_V, 0, ks_b).
SET out TO d_step(pb, D_T + 0.5, D_V, 0, ks_b).
assert_true("POST: flashing V16 N40", out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 40).
SET ks_b["RECYCLE"] TO TRUE.
SET out TO d_step(pb, D_T + 0.75, D_V, 0, ks_b).
assert_true("V32 shows it again", out["SET_VERB"] = 16 AND out["SET_NOUN"] = 40 AND pb["PHASE"] = "POST").
SET ks_b["PRO"] TO TRUE.
d_step(pb, D_T + 1, D_V, 0, ks_b).
SET out TO d_step(pb, D_T + 1.25, D_V, 0, ks_b).
assert_true("PRO goes to TIGNOW: flashing V16 N85", pb["PHASE"] = "TRIM" AND out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 85).
assert_true("N85 has the three body-axis components", out["EXTRA"]["P40_VGB"]:LENGTH = 3).
SET ks_b["ENTER"] TO TRUE.
SET ks_b["VERB"] TO 16.
SET ks_b["NOUN"] TO 85.
SET out TO d_step(pb, D_T + 1.5, D_V, 0, ks_b).
assert_true("ENTR at N85 shows it again and does not end", NOT out["ENDED"] AND pb["PHASE"] = "TRIM").
SET ks_b["PRO"] TO TRUE.
SET out TO d_step(pb, D_T + 1.75, D_V, 0, ks_b).
assert_true("PRO at N85 ends the programme", out["ENDED"]).
p40_end(pb).
assert_near("p40_end leaves the throttle at zero", CTL_THR, 0, 0).

// ---- V34 at the V99 prompt: the engine is never lit, the ullage goes off ----
LOCAL pt IS d_start(23.1).
d_to_burn(pt).
LOCAL ks_t IS d_keys(6, 40).
d_step(pt, 2496, D_V0, 0, ks_t).
assert_true("the ullage is on at the prompt", pt["ULLAGE_ON"]).
SET ks_t["TERMINATE"] TO TRUE.
SET out TO d_step(pt, 2496.25, D_V0, 0, ks_t).
assert_true("V34 at the prompt ends the programme with the engine not lit and the ullage off", out["ENDED"] AND NOT pt["ENGINE_LIT"] AND NOT pt["ULLAGE_ON"]).
p40_end(pt).

// ---- ENTR at the prompt: the burn is skipped (GOPOST) ----
LOCAL pg IS d_start(23.1).
d_to_burn(pg).
LOCAL ks_g IS d_keys(6, 40).
d_step(pg, 2496, D_V0, 0, ks_g).
SET ks_g["VERB"] TO 99.
SET ks_g["NOUN"] TO 40.
SET ks_g["ENTER"] TO TRUE.
SET out TO d_step(pg, 2496.25, D_V0, 0, ks_g).
assert_true("ENTR at the prompt goes to the post-burn display with no ignition", pg["PHASE"] = "POST" AND NOT pg["ENGINE_LIT"] AND NOT out["ENDED"]).
SET out TO d_step(pg, 2496.5, D_V0, 0, ks_g).
assert_true("flashing V16 N40", out["REQUEST"]["VERB"] = 16 AND out["REQUEST"]["NOUN"] = 40).
SET ks_g["TERMINATE"] TO TRUE.
SET out TO d_step(pg, 2496.75, D_V0, 0, ks_g).
assert_true("V34 there ends P40", out["ENDED"]).

// ---- a long burn zooms; MAN does not and follows the lever ----
LOCAL pz IS d_start(60).
d_to_burn(pz).
assert_true("S40.13: 60 m/s is over 95 s at the minimum thrust, no NOTHROTL", NOT pz["NOTHROTL"]).
LOCAL ks_z IS d_keys(6, 40).
SET D_T TO 2495.
SET D_V TO D_V0.
SET D_U TO pz["VG"]:NORMALIZED.
d_step(pz, 2496, D_V0, 0, ks_z).
SET ks_z["PRO"] TO TRUE.
d_step(pz, 2497, D_V0, 0, ks_z).
SET D_T TO 2500.
SET out TO d_step(pz, 2500, D_V0, 0, ks_z).
assert_true("a long burn lights the engine", pz["ENGINE_LIT"]).
d_loop(pz, ks_z, 2525.5, 0.5).
assert_true("not zoomed before ignition + 26 s", pz["THR"] = THR_MIN_FRAC).
d_loop(pz, ks_z, 2527, 0.5).
assert_true("zoomed to full throttle at ignition + 26 s", pz["THR"] = 1 AND CTL_THR = 1).

SET ENG_THR_CONT TO "MAN".
LOCAL pl IS d_start(60).
SET ENG_THR_CONT TO "AUTO".
SET D_T TO 2000.
d_to_burn(pl).
LOCAL ks_l IS d_keys(6, 40).
SET D_U TO pl["VG"]:NORMALIZED.
d_step(pl, 2496, D_V0, 0, ks_l).
SET ks_l["PRO"] TO TRUE.
d_step(pl, 2497, D_V0, 0, ks_l).
SET D_T TO 2500.
SET D_V TO D_V0.
d_step(pl, 2500, D_V0, 0, ks_l).
SET CTL_DRY_LEVER TO 1.
d_loop(pl, ks_l, 2512, 0.5).
assert_near("MAN: the throttle is the lever from ignition, not held at the minimum", pl["THR"], 1, 0).
assert_true("MAN: the cue has not come before ignition + 15 s", NOT pl["MAN_MSG"]).
SET out TO d_loop(pl, ks_l, 2515.5, 0.5).
assert_true("MAN: at +15 s the terminal says RAISE THROTTLE", pl["MAN_MSG"]).
assert_true("and then the throttle is the lever", pl["THR"] = 1).
assert_true("the status readout says MAN", out["STATUS"][0]:CONTAINS("MAN") AND out["STATUS"][1]:CONTAINS("RAISE THROTTLE")).
SET CTL_DRY_LEVER TO 0.
d_loop(pl, ks_l, 2517, 0.5).
assert_near("MAN: a lever at zero gives the minimum throttle, not zero", pl["THR"], THR_MIN_FRAC, 0).
SET CTL_DRY_LEVER TO 0.4.
d_loop(pl, ks_l, 2518, 0.5).
assert_near("MAN: the lever at 0.4 gives 0.4", pl["THR"], 0.4, 1e-9).
d_loop(pl, ks_l, 2530, 0.5).
assert_true("MAN: no zoom at ignition + 26 s", pl["THR"] = 0.4).
SET CTL_DRY_LEVER TO keep_lever.

// ---- alarm 1407: the measured delta-V points away from VG; no cutoff is scheduled ----
LOCAL pw IS d_start(23.1).
d_to_burn(pw).
LOCAL ks_w IS d_keys(6, 40).
SET D_T TO 2495.
SET D_V TO D_V0.
SET D_U TO pw["VG"]:NORMALIZED * (-1).
d_step(pw, 2496, D_V0, 0, ks_w).
SET ks_w["PRO"] TO TRUE.
d_step(pw, 2497, D_V0, 0, ks_w).
d_step(pw, 2500, D_V0, 0, ks_w).
SET D_T TO 2500.
LOCAL saw_1407 IS FALSE.
LOCAL tick IS 0.
UNTIL tick >= 24 {
  SET D_T TO D_T + 0.25.
  SET D_V TO D_V + D_U * 0.5 * 0.25.
  SET out TO d_step(pw, D_T, D_V, 8.5, ks_w).
  IF out["ALARM"] = 1407 { SET saw_1407 TO TRUE. }
  SET tick TO tick + 1.
}
assert_true("thrust against VG: alarm 1407", saw_1407).
assert_true("and no cutoff is scheduled", pw["BB"]["CUT_UT"] < 0 AND pw["PHASE"] = "BURN").

// ---- V97: no thrust after ignition ----
LOCAL pv IS d_start(23.1).
d_to_burn(pv).
LOCAL ks_v IS d_keys(6, 40).
d_step(pv, 2496, D_V0, 0, ks_v).
SET ks_v["PRO"] TO TRUE.
d_step(pv, 2497, D_V0, 0, ks_v).
d_step(pv, 2500, D_V0, 0, ks_v).
SET D_T TO 2500.
SET D_U TO V(0, 0, 0).
LOCAL saw_v97 IS FALSE.
SET tick TO 0.
UNTIL tick >= 120 OR saw_v97 {
  SET D_T TO D_T + 0.25.
  SET out TO d_step(pv, D_T, D_V0, 0, ks_v).
  IF out["REQUEST"]:ISTYPE("Lexicon") { IF out["REQUEST"]["VERB"] = 97 { SET saw_v97 TO TRUE. } }
  SET tick TO tick + 1.
}
assert_true("no thrust after ignition: flashing V97 N40", saw_v97 AND out["REQUEST"]["NOUN"] = 40).
SET ks_v["PRO"] TO TRUE.
SET out TO d_step(pv, D_T + 0.25, D_V0, 0, ks_v).
assert_true("PRO resets the thrust monitor", NOT pv["DVMON"]["FAILED"] AND pv["ENGINE_LIT"]).
LOCAL pv2 IS d_start(23.1).
d_to_burn(pv2).
LOCAL ks_v2 IS d_keys(6, 40).
d_step(pv2, 2496, D_V0, 0, ks_v2).
SET ks_v2["PRO"] TO TRUE.
d_step(pv2, 2497, D_V0, 0, ks_v2).
d_step(pv2, 2500, D_V0, 0, ks_v2).
SET D_T TO 2500.
SET saw_v97 TO FALSE.
SET tick TO 0.
UNTIL tick >= 120 OR saw_v97 {
  SET D_T TO D_T + 0.25.
  SET out TO d_step(pv2, D_T, D_V0, 0, ks_v2).
  IF out["REQUEST"]:ISTYPE("Lexicon") { IF out["REQUEST"]["VERB"] = 97 { SET saw_v97 TO TRUE. } }
  SET tick TO tick + 1.
}
SET ks_v2["VERB"] TO 97.
SET ks_v2["NOUN"] TO 40.
SET ks_v2["ENTER"] TO TRUE.
SET out TO d_step(pv2, D_T + 0.25, D_V0, 0, ks_v2).
assert_true("ENTR at V97: the engine is off and the burn is retried in DVMON_RETRY_S", NOT pv2["ENGINE_LIT"] AND ABS(pv2["TIG"] - (D_T + 0.25 + DVMON_RETRY_S)) < 1e-6 AND CTL_THR = 0).
SET ks_v2["VERB"] TO 6.
SET ks_v2["NOUN"] TO 40.
SET out TO d_step(pv2, D_T + 0.5, D_V0, 0, ks_v2).
assert_true("the retry goes straight to the prompt (TIG is 5 s away)", out["REQUEST"]:ISTYPE("Lexicon") AND out["REQUEST"]["VERB"] = 99).
// V34 at the V97 display ends the programme
LOCAL pv3 IS d_start(23.1).
d_to_burn(pv3).
LOCAL ks_v3 IS d_keys(6, 40).
d_step(pv3, 2496, D_V0, 0, ks_v3).
SET ks_v3["PRO"] TO TRUE.
d_step(pv3, 2497, D_V0, 0, ks_v3).
d_step(pv3, 2500, D_V0, 0, ks_v3).
SET D_T TO 2500.
SET saw_v97 TO FALSE.
SET tick TO 0.
UNTIL tick >= 120 OR saw_v97 {
  SET D_T TO D_T + 0.25.
  SET out TO d_step(pv3, D_T, D_V0, 0, ks_v3).
  IF out["REQUEST"]:ISTYPE("Lexicon") { IF out["REQUEST"]["VERB"] = 97 { SET saw_v97 TO TRUE. } }
  SET tick TO tick + 1.
}
SET ks_v3["TERMINATE"] TO TRUE.
SET out TO d_step(pv3, D_T + 0.25, D_V0, 0, ks_v3).
assert_true("V34 at the V97 display ends the programme", out["ENDED"]).
p40_end(pv3).
assert_near("and p40_end leaves the throttle at zero after a lit engine", CTL_THR, 0, 0).

// ---- an impulse burn: under 6 s, no steering, the timer cuts ----
LOCAL pimp IS d_start(1.0).
d_to_burn(pimp).
assert_true("S40.13: 1 m/s is an impulse burn", pimp["IMPULSE"]).
LOCAL ks_i IS d_keys(6, 40).
SET D_T TO 2495.
SET D_V TO D_V0.
SET D_U TO pimp["VG"]:NORMALIZED.
d_step(pimp, 2496, D_V0, 0, ks_i).
SET ks_i["PRO"] TO TRUE.
d_step(pimp, 2497, D_V0, 0, ks_i).
SET D_T TO 2499.75.
d_step(pimp, 2500, D_V0, 0, ks_i).
assert_true("the impulse burn lights the engine with no steering", pimp["ENGINE_LIT"] AND NOT pimp["STEER"]).
assert_true("the cutoff is on the timer: 1.0 m/s at the minimum thrust is about 1.8 s less the tail-off", ABS(pimp["BB"]["CUT_UT"] - 2500 - 1.4) < 0.1).
SET D_T TO 2500.
d_loop(pimp, ks_i, 2503, 0.5).
assert_true("and the burn ends and goes to the post-burn display", pimp["PHASE"] = "POST").
assert_true("no thrust-monitor failure on an impulse burn", NOT pimp["DVMON"]["FAILED"]).

// ---- the programme table ----
RUNONCEPATH("0:/lm/lm_vehicle.ks").
LOCAL vehicle_table IS lm_programme_table().
assert_true("P40 is in the programme table and selectable", vehicle_table:HASKEY("40") AND vehicle_table["40"]["SELECTABLE"]).
assert_true("V37 can select 40", LM_PROGS:CONTAINS(40)).
assert_true("N40 and N85 are nouns", LM_NOUNS:CONTAINS(40) AND LM_NOUNS:CONTAINS(85)).
assert_true("N40 outside P40 shows zeros", noun_registers(40, LEXICON("VALID", FALSE))[0] = "+00 00").

SET ENG_THR_CONT TO keep_thr.
SET CTL_DRY_LEVER TO keep_lever.
test_end().
