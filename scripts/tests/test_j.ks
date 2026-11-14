// test_j.ks -- pad tests for the J-class descent (release 1.2: Luminary 210, Apollo 17 pad loads). No flight needed.
//   RUNPATH("0:/tests/test_j.ks").
// Expected values come from scripts/tests/reference_j.py or are exact by definition. Results go to 0:/lm/logs/test_j.log.
// The log's last line is "TESTS: N passed, M failed". Everything here is in the J files (scripts/lm/descent_j/); the Apollo 11 files
// have their own tests (test_p63.ks, test_p64.ks, test_p65.ks), which must still pass.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_guidance.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_ignition.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_j.log").

// ---- the pad loads (research note, Apollo 17 column) -----------------------------------------------------------------
assert_vec("J_RBRFG", J_RBRFG, V(-950.4757622, 0, -3578.791217), 1e-9).
assert_vec("J_VBRFG", J_VBRFG, V(-59.88380, 0, -50.828448), 1e-9).
assert_vec("J_ABRFG", J_ABRFG, V(-0.2189220, 0, -2.530587), 1e-9).
assert_vec("J_RAPFG", J_RAPFG, V(48.31080, 0, -8.337926), 1e-9).
assert_vec("J_VAPFG", J_VAPFG, V(-1.077395, 0, 0.0076049), 1e-9).
assert_vec("J_AAPFG", J_AAPFG, V(0.02352395, 0, -0.1797183), 1e-9).
assert_near("8 * J_JBRFG_Z = JBRFG* in m/s^3", 8 * J_JBRFG_Z, -4.609691263e-3, 1e-9).
assert_near("8 * J_JAPFG_Z = JAPFG* in m/s^3", 8 * J_JAPFG_Z, 1.315931328e-2, 1e-9).
assert_near("J_VBRFG:Z is the braking velocity target of the 18 x scale (VBRFG* = 18 x VBRFGz m/cs)", 18 * J_VBRFG:Z / 100, -9.149120640, 1e-6).
assert_near("J_RIGNX", J_RIGNX, -47593.00514, 1e-9).
assert_near("J_RIGNZ", J_RIGNZ, -469983.8606, 1e-9).
assert_near("J_VIGN", J_VIGN, 1689.475188, 1e-9).
assert_near("J_KIGNX", J_KIGNX, -0.334, 0).
assert_near("J_KIGNY", J_KIGNY, -7.240813648e-7, 1e-15).
assert_near("J_KIGNV", J_KIGNV, -498, 0).
assert_near("J_TCGFAPPR is 6 s (Apollo 11: 30)", J_TCGFAPPR, 6, 0).
assert_near("J_DELTTFAP is -70 s (Apollo 11: -110)", J_DELTTFAP, -70, 0).
assert_near("J_TENDAPPR", J_TENDAPPR, 12, 0).
assert_near("J_TENDBRAK", J_TENDBRAK, 62, 0).
assert_near("J_LAG_TAU is 0.2333 (Apollo 11: 0.413333)", J_LAG_TAU, 0.2333, 0).
assert_near("J_TAUHZ", J_TAUHZ, 5, 0).
assert_near("J_QHZ", J_QHZ, 0.4, 0).
assert_near("J_AHZLIM is 1.93898 ft/s^2", J_AHZLIM, 1.93898 * 0.3048, 1e-5).
assert_near("J_ELEACH_RAD is one degree", J_ELEACH_RAD * 180 / CONSTANT:PI, 1, 0.001).
assert_near("J_AZEACH_RAD is one degree", J_AZEACH_RAD * 180 / CONSTANT:PI, 1, 0.001).
assert_near("J_HLROFF is 50 ft", J_HLROFF, 15.24, 1e-9).
// The Apollo 11 constants are not touched by loading the J file.
assert_near("Apollo 11 VIGN unchanged", VIGN, 1690.256208, 1e-9).
assert_near("Apollo 11 DELTTFAP unchanged", DELTTFAP, -110, 0).
assert_near("Apollo 11 TCGFAPPR unchanged", TCGFAPPR, 30, 0).

// ---- ignition algorithm and target sets --------------------------------------------------------------------------------
assert_near("ddum at the J nominal state", j_ign_ddum(V(J_RIGNX, 0, J_RIGNZ), V(0, 0, J_VIGN)), 0, 1e-9).
assert_near("ddum 1 km short", j_ign_ddum(V(J_RIGNX, 0, J_RIGNZ - 1000), V(0, 0, J_VIGN)), 0.5918997846803536, 1e-6).
assert_near("ddum 2 km ahead", j_ign_ddum(V(J_RIGNX, 0, J_RIGNZ + 2000), V(0, 0, J_VIGN)), -1.1837995693607073, 1e-6).
assert_near("ddum high, crossrange, slow", j_ign_ddum(V(J_RIGNX + 500, 800, J_RIGNZ), V(30, 0, J_VIGN - 15)), 4.255704854172393, 1e-6).
LOCAL jt_brake IS j_guid_targets_brake().
LOCAL jt_appr IS j_guid_targets_approach().
assert_vec("brake targets use the J position", jt_brake["R"], J_RBRFG, 0).
assert_near("brake TCGF is 30", jt_brake["TCGF"], 30, 0).
assert_vec("approach targets use the J position", jt_appr["R"], J_RAPFG, 0).
assert_near("approach TCGF is 6", jt_appr["TCGF"], 6, 0).
assert_near("approach TEND is 12", jt_appr["TEND"], 12, 0).
assert_true("handoff below TEND", j_guid_handoff(11.9, 12) AND NOT j_guid_handoff(12.1, 12)).
// Time-to-go cubic and quadratic guidance with the J braking targets (reference_j.py).
LOCAL jt_solved IS j_guid_cubic_tgo(-80000, 1500, J_RBRFG:Z, J_VBRFG:Z, J_ABRFG:Z, J_JBRFG_Z, 500).
assert_true("cubic converges on the J braking targets", jt_solved["OK"]).
assert_near("cubic tgo", jt_solved["TGO"], 171.789992, 1e-3).
LOCAL jt_acg IS j_guid_acg(V(-900, 0, -80000), V(-40, 0, 1500), jt_solved["TGO"], J_RBRFG, J_VBRFG, J_ABRFG, J_LEADTIME).
assert_vec("quadratic guidance acceleration", jt_acg, V(3.081012257, 0, -21.572198125), 1e-5).

// ---- the P66 horizontal law (reference_j.py "hz law") ------------------------------------------------------------------------
assert_vec("hz: no velocity, no command", j_guid_hz(V(0, 0, 0), V(1.6, 0, 0), 1.62), V(1.62, 0, 0), 1e-9).
assert_vec("hz: 2 m/s crossrange, 3 m/s uprange", j_guid_hz(V(0, 2, -3), V(1.6, 0, 0), 1.62), V(1.62, -0.4, 0.591001104), 1e-6).
assert_vec("hz: the previous command is fed back with QHZ", j_guid_hz(V(0, 2, -3), V(1.6, -0.3, 0.5), 1.62), V(1.62, -0.28, 0.4), 1e-6).
assert_vec("hz: limited to AHZLIM each way", j_guid_hz(V(0, 10, -10), V(1.6, 0, 0), 1.62), V(1.62, -0.591001104, 0.591001104), 1e-6).
assert_vec("hz: limited the other way", j_guid_hz(V(0, -10, 10), V(1.6, 0.3, -0.3), 1.62), V(1.62, 0.591001104, -0.591001104), 1e-6).
assert_near("hz: the vertical part is exactly g", j_guid_hz(V(5, 2, 2), V(0, 0, 0), 1.5):X, 1.5, 0).
// Steady state: v / (TAUHZ (1 + QHZ)) = 2 / 7 = 0.285714 reached by repeating the law with the same velocity.
LOCAL jt_a IS V(0, 0, 0).
FROM { LOCAL i IS 0. } UNTIL i >= 30 STEP { SET i TO i + 1. } DO { SET jt_a TO j_guid_hz(V(0, 2, 0), jt_a, 1.62). }
assert_near("hz: steady state command is -v/(TAUHZ(1+QHZ))", jt_a:Y, -2 / (5 * 1.4), 1e-6).

// ---- redesignation click size and small helpers --------------------------------------------------------------------------------
assert_vec("redes: no clicks leaves the site", j_redes_los(V(1737400, 0, 0), V(1737500, 0, -300), V(0, 1, 0), 0, 0), V(1737400, 0, 0), 0).
LOCAL jt_new IS j_redes_los(V(1737400, 0, 0), V(1737500, 0, -300), V(0, 1, 0), 0, J_AZEACH_RAD).
assert_true("redes: one yaw click moves the aim point sideways by about 1 degree of the line of sight (a few metres at this range)", ABS(jt_new:Y) > 3 AND ABS(jt_new:Y) < 8).
assert_true("j_p66_ms_text 0.9144", j_p66_ms_text(0.9144) = "0.91").
assert_true("j_p66_ms_text negative", j_p66_ms_text(-0.304) = "-0.30").
assert_true("hz pass is due the first time", j_p66_hz_due(-1, 100)).
assert_true("hz pass is not due after 0.25 s", NOT j_p66_hz_due(100, 100.25)).
assert_true("hz pass is due after 2 s", j_p66_hz_due(100, 102)).

// ---- the programme on the pad (CTL_DRY: the ship's controls are not touched) ---------------------------------------------------
// The state is the P64 end for the J targets simplified: 47.1 m up, 20 m before the site, vg = (-0.92, 2.06); site on the raw +X axis.
RUNONCEPATH("0:/shared/lm_nav.ks").
RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_p66.ks").
SET CTL_DRY TO TRUE.
GLOBAL jt_lever IS 0.5.
FUNCTION jt_ramp {
  PARAMETER rod, lever0, delta, count, t0.
  LOCAL t_now IS t0.
  SET jt_lever TO lever0.
  FROM { LOCAL i IS 0. } UNTIL i >= count STEP { SET i TO i + 1. } DO {
    SET jt_lever TO MAX(0, MIN(1, jt_lever + delta)).
    rod_sample(rod, jt_lever, t_now).
    IF rod["RECENTRE"] { SET rod["RECENTRE"] TO FALSE. SET jt_lever TO 0.5. }
    SET t_now TO t_now + 0.02.
  }
  RETURN t_now.
}
FUNCTION jt_prog {
  PARAMETER att_mode.
  LOCAL pr IS LEXICON("REFUSED", "", "PROG_NO", 64, "WINDOW_MODE", "UP", "TURNED", FALSE, "FORE0", V(1, 0, 0), "WIN0", V(0, 1, 0), "WCMD", V(0, 1, 0),
                 "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "WARP", warp_new(), "ENGINE", 0,
                 "LAND", V(1737400, 0, 0), "WM", V(0, 0, 0), "TIG", 1000, "BURN_DIR", V(1, 0, 0), "OUTOFPLN", 0,
                 "TGO", 11, "THR", 0.3, "GP", LEXICON(), "ZOOMED", TRUE, "ENGINE_LIT", TRUE, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", 1999.75, "HANDOFF_T", 1999, "LAST_STATE", "", "LAST_ALARM", 0, "ENDED", FALSE).
  SET pr["ATT"]["MODE"] TO att_mode.
  SET pr["GP"]["CG"] TO guidance_cg(V(1737400, 0, 0), V(1737447.1, 0, -20), V(0, 0, 0), 0).
  RETURN pr.
}
FUNCTION jt_state {
  PARAMETER now_ut, r_vec, v_vec, thrust_now.
  RETURN LEXICON("R", r_vec, "V", v_vec, "T", now_ut, "MASS", 8.095, "THRUST", 43.4547,
                 "THRUST_NOW", thrust_now, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 47, "XNB", V(1, 0, 0)).
}
LOCAL jt_land IS V(1737400, 0, 0).
LOCAL jt_wm IS V(0, 0, 0).
LOCAL jt_r IS V(1737447.1, 0, -20).
LOCAL jt_v IS V(-0.92, 0, 2.06).
LOCAL jt_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jp IS j_p66_start(jt_prog("AUTO")).
assert_near("j_p66_start: programme number", jp["PROG_NO"], 66, 0).
assert_true("j_p66_start: keeps the guidance axes P64 left", jp["CG"]:ISTYPE("List")).
assert_true("j_p66_start: keeps the engine state", jp["ENGINE_LIT"]).
assert_true("j_p66_start: VDG is not set until there is data", NOT jp["VDG_SET"]).

LOCAL jt_st IS jt_state(2000, jt_r, jt_v, 13.15).
LOCAL jt_d IS nav_derived(jt_st, jt_land, jt_wm).
LOCAL jt_out IS j_p66_step(jp, jt_st, jt_d, jt_ks).
assert_near("first step sets verb 6", jt_out["SET_VERB"], 6, 0).
assert_near("first step sets noun 60", jt_out["SET_NOUN"], 60, 0).
assert_near("reports PROG_NO 66", jt_out["PROG_NO"], 66, 0).
assert_true("never asks for a handover", NOT jt_out["HANDOVER"]).
assert_true("no contact lamp in the air", NOT jt_out["CONTACT"]).
assert_true("VDG is set to the rate now (HDOT) at the first valid cycle", jp["VDG_SET"] AND ABS(jp["VDG"] - jt_d["HDOT"]) < 1e-9).
assert_true("the message says P66 has started", jt_out["MSG"]:CONTAINS("RATE OF DESCENT")).
assert_true("the throttle is a sensible fraction (weight about 30 % of full thrust)", CTL_THR > 0.2 AND CTL_THR < 0.4).
// Horizontal: 2.06 m/s downrange (+Z) is nulled by tilting the thrust back (reference: g 1.62413, a_z = -2.06/5).
assert_near("thrust direction: up part", jp["BURN_DIR"]:NORMALIZED:X, 0.969299, 0.002).
assert_near("thrust direction: tilted back against the downrange speed", jp["BURN_DIR"]:NORMALIZED:Z, -0.245886, 0.002).
assert_near("thrust direction: no crossrange", jp["BURN_DIR"]:NORMALIZED:Y, 0, 0.001).
assert_true("status has three lines", jt_out["STATUS"]:LENGTH = 3).
assert_true("status line 3 gives the horizontal speed, 2.06 m/s", jt_out["STATUS"][2]:CONTAINS("2.06")).
LOCAL jt_held IS jp["BURN_DIR"].
SET jt_st TO jt_state(2000.25, jt_r, jt_v, 13.15).
SET jt_out TO j_p66_step(jp, jt_st, nav_derived(jt_st, jt_land, jt_wm), jt_ks).
assert_near("the display is requested only once", jt_out["SET_VERB"], -1, 0).
assert_vec("0.25 s later the horizontal command is held (not due)", jp["BURN_DIR"], jt_held, 1e-9).
SET jt_st TO jt_state(2002, jt_r, jt_v, 13.15).
SET jt_out TO j_p66_step(jp, jt_st, nav_derived(jt_st, jt_land, jt_wm), jt_ks).
assert_near("2 s later the law runs again and feeds back its last command (a_z -0.2472)", jp["BURN_DIR"]:NORMALIZED:Z, -0.150472, 0.002).
// ROD clicks work in AUTO in J's P66 (no switch SAS on first).
LOCAL jt_vdg IS jp["VDG"].
LOCAL jt_rt IS jt_ramp(jp["ROD"], 0.5, 0.01, 6, 0).
SET jt_rt TO jt_ramp(jp["ROD"], jt_lever, 0, 12, jt_rt).
SET jt_st TO jt_state(2002.5, jt_r, jt_v, 13.15).
SET jt_out TO j_p66_step(jp, jt_st, nav_derived(jt_st, jt_land, jt_wm), jt_ks).
assert_near("a ROD click in AUTO changes VDG by RODSCALE", jp["VDG"], jt_vdg + J_RODSCALE * P66_ROD_SIGN, 1e-9).
assert_true("and no 'switch SAS on' message", NOT jt_out["MSG"]:CONTAINS("SWITCH")).

// ---- the vehicle: programme table and profile (lm_vehicle.ks) -----------------------------------------------------------------------
RUNONCEPATH("0:/lm/lm_vehicle.ks").
LOCAL jt_veh IS lm_vehicle_new().
LOCAL jt_is_j IS plan_profile_of(plan_read(PLAN_PLAN_FILE)) = "J".
assert_true("vehicle: P64 hands over to P66 for J, P65 otherwise", jt_veh["PROGRAMMES"]["64"]["NEXT"] = (CHOOSE 66 IF jt_is_j ELSE 65)).
assert_true("vehicle: P66 is in the table and not selectable by V37", jt_veh["PROGRAMMES"]["66"]["SELECTABLE"] = FALSE).
assert_true("vehicle: P66 hands over to nothing", jt_veh["PROGRAMMES"]["66"]["NEXT"] = -1).

test_end().
