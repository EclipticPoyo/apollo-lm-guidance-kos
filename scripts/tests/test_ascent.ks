// test_ascent.ks -- pad test for the ascent guidance (lm/ascent/lm_ascent_guid.ks). No flight, no ship reads: every state is made up.
// The expected numbers are the KOS TEST VALUES of python scripts/tests/reference_ascent.py, built from the same cases.
//   RUNPATH("0:/tests/test_ascent.ks").   Log: 0:/lm/logs/test_ascent.log.
// Written for release 1.5 and not yet run in KSP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/ascent/lm_ascent_guid.ks").

test_begin("0:/lm/logs/test_ascent.log").

GLOBAL TA_MU IS 4.9028e12.
GLOBAL TA_SITE_R IS 1735750.
GLOBAL TA_RCO IS TA_SITE_R + ASC_HINJECT_M.
GLOBAL TA_CSM_R IS TA_SITE_R + 60 * 1852.
// The CSM plane is the X-Y plane: the CSM over +X, moving toward +Y.
GLOBAL TA_QAXIS IS asc_qaxis(V(TA_CSM_R, 0, 0), V(0, SQRT(TA_MU / TA_CSM_R), 0)).

// ta_state: a flight state given by its parts along the guidance axes (as frame_case in the reference model).
FUNCTION ta_state {
  PARAMETER rmag, cross_slope, rdot, zdot, ydot.
  LOCAL r_vec IS (V(1, 0, 0) + TA_QAXIS * cross_slope):NORMALIZED * rmag.
  LOCAL axes IS asc_state(r_vec, V(0, 0, 0), TA_QAXIS, TA_MU, TA_RCO).
  LOCAL v_vec IS axes["UR"] * rdot + axes["Z"] * zdot + axes["LAT"] * ydot.
  RETURN asc_state(r_vec, v_vec, TA_QAXIS, TA_MU, TA_RCO).
}
FUNCTION ta_guid {
  PARAMETER tgo, tbup.
  LOCAL g IS asc_new("A11").
  SET g["TGO"] TO tgo.
  SET g["TBUP"] TO tbup.
  SET g["AT"] TO ASC_VE / tbup.
  RETURN g.
}
FUNCTION ta_mid { RETURN ta_state(TA_SITE_R + 9000, 0.001, 40, 800, 3). }
FUNCTION ta_tgt {
  PARAMETER yco, zdotd.
  RETURN asc_target(TA_RCO, yco, 9.81456, zdotd).
}

// ---- Engine estimate ----
LOCAL g IS asc_new("A11").
assert_true("engine ignores weak pass", NOT asc_engine(g, 3.0, 2)).
assert_near("a weak pass leaves TBUP", g["TBUP"], 919.02, 0.001).
assert_true("a good pass is counted", asc_engine(g, 6.4, 2)).
assert_near("engine filter 1 pass TBUP", g["TBUP"], 920.2894, 0.01).
assert_near("engine filter 1 pass AT", g["AT"], 3.29244, 0.01).
FOR ta_i IN RANGE(4) { asc_engine(g, 6.4, 2). }
assert_near("engine filter 5 passes TBUP", g["TBUP"], 937.9787, 0.01).
assert_near("engine filter 5 passes AT", g["AT"], 3.23035, 0.01).

// ---- State axes ----
LOCAL st IS asc_state(V(TA_RCO, 0, 0), V(10, 100, 0), TA_QAXIS, TA_MU, TA_RCO).
assert_vec("state axes: Z is the direction of travel", st["Z"], V(0, 1, 0), 1e-6).
assert_vec("state axes: LAT is the Q axis", st["LAT"], TA_QAXIS, 1e-6).
assert_near("state axes: radial speed", st["RDOT"], 10, 1e-6).
assert_near("state axes: downrange speed", st["ZDOT"], 100, 1e-6).
assert_near("state axes: in plane", st["Y"], 0, 0.001).
SET st TO ta_mid().
assert_near("state axes: off plane Y = rco (UR . Q)", st["Y"], 1754.037, 0.01).
assert_near("state: effective gravity", st["GEFF"], -1.243743, 1e-5).

// ---- Guidance, mid ascent ----
SET g TO ta_guid(250, 700).
LOCAL cmd IS asc_guide(g, st, ta_tgt(500, 1686.9)).
assert_near("guide mid ascent TGO", cmd["TGO"], 181.8241, 0.18).
assert_near("guide mid ascent AR", cmd["AR"], 1.854220, 0.002).
assert_near("guide mid ascent AY", cmd["AY"], -0.265499, 0.0003).
assert_near("guide mid ascent AP", cmd["AP"], 3.902295, 0.004).
assert_near("guide mid ascent A", g["A"], 432.92025, 0.43).
assert_near("guide mid ascent B", g["B"], -5.586307, 0.0056).
assert_near("guide mid ascent C", g["C"], -187.71111, 0.19).
assert_near("guide mid ascent D", g["D"], 1.861849, 0.0019).
assert_near("guide: the direction is a unit vector", cmd["DIR"]:MAG, 1, 1e-6).
LOCAL ta_angles IS asc_yaw_pitch(cmd, st).
assert_near("guide mid ascent yaw", ta_angles[0], 356.1078, 0.05).
assert_near("guide mid ascent pitch", ta_angles[1], 295.3640, 0.05).

// ---- The radial rate limits ----
SET g TO ta_guid(100, 700).
asc_guide(g, ta_state(TA_SITE_R + 500, 0.001, 0, 1300, 3), ta_tgt(500, 1686.9)).
assert_near("radial rate limited", g["B"], ASC_PRLIMIT * 700, 1e-6).
SET g TO ta_guid(250, 700).
asc_guide(g, ta_state(TA_SITE_R + 25000, 0.001, 5, 800, 3), ta_tgt(500, 1686.9)).
assert_near("radial rate may not be positive", g["B"], 0, 1e-9).
assert_true("position control still on", NOT g["FLPC"]).

// ---- Under 10 s, and under 2 s ----
SET g TO ta_guid(8, 480).
SET cmd TO asc_guide(g, ta_state(TA_RCO, 0.001, 9.81456, 1655, 0), ta_tgt(500, 1686.9)).
assert_true("no position control under 10 s: TGO", cmd["TGO"] < 10 AND cmd["TGO"] > 2).
assert_true("no position control under 10 s: flag", g["FLPC"]).
assert_near("no position control under 10 s: B", g["B"], 0, 1e-9).
assert_near("no position control under 10 s: D", g["D"], 0, 1e-9).
SET g["TGO"] TO 250.
SET g["TBUP"] TO 700.
asc_guide(g, ta_mid(), ta_tgt(500, 1686.9)).
assert_true("position control stays off with a longer TGO", g["FLPC"] AND g["B"] = 0 AND g["D"] = 0).

SET g TO ta_guid(250, 700).
asc_guide(g, ta_mid(), ta_tgt(500, 1686.9)).
LOCAL ta_a IS g["A"].
LOCAL ta_b IS g["B"].
LOCAL ta_c IS g["C"].
LOCAL ta_d IS g["D"].
SET g["TGO"] TO 1.5.
SET g["TBUP"] TO 480.
SET cmd TO asc_guide(g, ta_state(TA_RCO, 0.001, 9.81456, 1681, 0), ta_tgt(500, 1686.9)).
assert_true("coefficients held under 2 s: TGO", cmd["TGO"] < 2).
assert_true("coefficients held under 2 s", g["A"] = ta_a AND g["B"] = ta_b AND g["C"] = ta_c AND g["D"] = ta_d).

// ---- Acceleration limit ----
SET g TO ta_guid(250, 700).
SET cmd TO asc_guide(g, ta_mid(), ta_tgt(600000, 1686.9)).
assert_near("acceleration limited: no downrange part", cmd["AP"], 0, 1e-9).
assert_near("acceleration limited: unit direction", cmd["DIR"]:MAG, 1, 1e-6).

// ---- Rise exit ----
assert_true("rise A11 waits for yaw", NOT asc_rise_done("A11", 100, 13, 6)).
assert_true("rise A11 ends with yaw", asc_rise_done("A11", 100, 13, 4)).
assert_true("rise A11 ends with yaw the other way", asc_rise_done("A11", 100, 13, -4)).
assert_true("rise A11 waits for 40 ft/s", NOT asc_rise_done("A11", 100, 12, 0)).
assert_true("rise J needs no yaw", asc_rise_done("J", 100, 13, 90)).
assert_true("no rise above 25000 ft", asc_rise_done("A11", 8000, 0, 90)).

// ---- Yaw, pitch and the window ----
SET st TO asc_state(V(TA_RCO, 0, 0), V(0, 0, 0), TA_QAXIS, TA_MU, TA_RCO).
LOCAL ta_dir IS st["UR"] * COS(50) + st["Z"] * SIN(50).
SET ta_angles TO asc_yaw_pitch(LEXICON("AY", 0, "AP", 2.0, "DIR", ta_dir), st).
assert_near("yaw pitch: forward yaw 0", ta_angles[0], 0, 0.001).
assert_near("yaw pitch: 50 deg from vertical is 310", ta_angles[1], 310, 0.001).
SET ta_angles TO asc_yaw_pitch(LEXICON("AY", 0, "AP", 0, "DIR", st["UR"]), st).
assert_near("yaw pitch: no horizontal part gives yaw 0", ta_angles[0], 0, 0.001).
LOCAL ta_win_a IS asc_window_down(st["UR"] * COS(4.9) + st["Z"] * SIN(4.9), st).
LOCAL ta_win_b IS asc_window_down(st["UR"] * COS(5.1) + st["Z"] * SIN(5.1), st).
assert_true("window continuous across 5 deg", VANG(ta_win_a, ta_win_b) < 6).
assert_true("window near the vertical points downrange", VANG(ta_win_a, st["Z"]) < 6).
assert_true("window past 5 deg points downrange and down", VANG(ta_win_b, st["Z"]) < 6).
assert_near("window square to the direction", VDOT(ta_win_b, st["UR"] * COS(5.1) + st["Z"] * SIN(5.1)), 0, 1e-6).
assert_near("window straight up", asc_window_down(st["UR"], st):MAG, 1, 1e-6).

// ---- Trim ----
SET g TO ta_guid(250, 700).
LOCAL ta_vg IS asc_trim(g, ta_mid(), ta_tgt(500, 1686.9)).
assert_near("trim", g["TGO"], ta_vg:MAG / ASC_AT_RCS, 1e-6).

// ---- Bad loads stay finite ----
FUNCTION ta_bad {
  PARAMETER label_text, yco, zdotd, tbup.
  LOCAL guid IS ta_guid(250, tbup).
  LOCAL out IS asc_guide(guid, ta_mid(), ta_tgt(yco, zdotd)).
  assert_true("bad loads stay finite: " + label_text + " TGO", out["TGO"] > 0 AND out["TGO"] < 1000).
  assert_near("bad loads stay finite: " + label_text + " direction", out["DIR"]:MAG, 1, 1e-6).
}
ta_bad("ZDOTD 18000", 500, 18000, 700).
ta_bad("ZDOTD -500", 500, -500, 700).
ta_bad("YCO 600000", 600000, 1686.9, 700).
ta_bad("VG beyond TBUP", 500, 40000, 200).

// ---- The ascent simulation (the Apollo 11 case) ----
LOCAL ta_r0 IS V(TA_SITE_R, 0, 0).
LOCAL ta_v0 IS V(0, 2.6617e-6 * TA_SITE_R, 0).
LOCAL ta_load IS asc_target(TA_RCO, 0, 32.2 * 0.3048, 5534.9 * 0.3048).
LOCAL ta_sim IS asc_sim("A11", ta_r0, ta_v0, TA_QAXIS, TA_MU, ta_load, 4915.6, 15569, 15569 / 5.135, ASC_SIM_DT).
assert_true("simulation reaches orbit", ta_sim["OK"]).
assert_near("simulation burn time", ta_sim["BURN_S"], 434.424, 1).
assert_near("simulation end radius", ta_sim["R_END"]:MAG, 1754041.5, 100).
SET st TO asc_state(ta_sim["R_END"], ta_sim["V_END"], TA_QAXIS, TA_MU, TA_RCO).
assert_near("simulation horizontal speed", st["ZDOT"], 1686.4614, 0.5).
assert_near("simulation radial speed", st["RDOT"], 9.9086, 0.5).
assert_near("simulation pitch after rise", ta_sim["PITCH_RISE"], 309.3318, 0.5).
SET ta_sim TO asc_sim("A11", ta_r0, ta_v0, TA_QAXIS, TA_MU, ta_load, 4915, 7000, ASC_VE, ASC_SIM_DT).
assert_true("simulation cannot reach", NOT ta_sim["OK"]).
assert_true("simulation cannot reach: stops at the guard", ta_sim["BURN_S"] <= ASC_SIM_MAX_S + ASC_SIM_DT).

test_end().
