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
RUNONCEPATH("0:/lm/descent_j/lm_j_p64.ks").          // j_redes_los (loaded here so that this test also runs on its own)
RUNONCEPATH("0:/lm/descent_j/lm_j_p66.ks").          // j_p66_ms_text, j_p66_hz_due
RUNONCEPATH("0:/core/dsky_display.ks").              // zero_pad, which j_p66_ms_text calls
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
                 "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "HIGHGATE", TRUE, "WARP", warp_new(), "ENGINE", 0,
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
LOCAL jt_is_j IS lm_profile_for(plan_read(PLAN_PLAN_FILE)) = "J".          // plan, else the version saved with the PAD, else the default
assert_true("vehicle: P64 hands over to P66 for J, P65 otherwise", jt_veh["PROGRAMMES"]["64"]["NEXT"] = (CHOOSE 66 IF jt_is_j ELSE 65)).
assert_true("vehicle: P66 is in the table and not selectable by V37", jt_veh["PROGRAMMES"]["66"]["SELECTABLE"] = FALSE).
assert_true("vehicle: P66 hands over to P68", jt_veh["PROGRAMMES"]["66"]["NEXT"] = 68).

// ---- 1.3.1: the J P64 request follows the redesignation window ----
LOCAL jq_prog IS j_p64_start(jt_prog("AUTO"), 0, 23.47, 0).
SET jq_prog["TGO"] TO 100.
LOCAL jq_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jq_out IS j_p64_step(jq_prog, jt_state(2000, jt_r, jt_v, 13.15), nav_derived(jt_state(2000, jt_r, jt_v, 13.15), jt_land, jt_wm), jq_ks).
assert_true("J P64: first step is a V06 N64 request, no KEY_REL", jq_out["REQUEST"]:ISTYPE("Lexicon") AND jq_out["REQUEST"]["NOUN"] = 64 AND NOT jq_out["KEY_REL"] AND jq_out["SET_NOUN"] = 64).
SET jq_ks["RECYCLE"] TO TRUE.
SET jq_out TO j_p64_step(jq_prog, jt_state(2000.25, jt_r, jt_v, 13.15), nav_derived(jt_state(2000.25, jt_r, jt_v, 13.15), jt_land, jt_wm), jq_ks).
assert_true("J P64: V32 re-posts the display", jq_out["SET_VERB"] = 6 AND jq_out["SET_NOUN"] = 64).
SET jq_ks["RECYCLE"] TO FALSE.
SET jq_ks["TERMINATE"] TO TRUE.
SET jq_out TO j_p64_step(jq_prog, jt_state(2000.5, jt_r, jt_v, 13.15), nav_derived(jt_state(2000.5, jt_r, jt_v, 13.15), jt_land, jt_wm), jq_ks).
assert_true("J P64: V34 ends it", jq_out["ENDED"]).
LOCAL jq_prog2 IS j_p64_start(jt_prog("AUTO"), 0, 23.47, 0).
SET jq_prog2["TGO"] TO 1.
LOCAL jq_st2 IS jt_state(2000, V(1737500, 0, 10), V(1, 0, 1), 13.15).      // no time-to-go root: the guidance keeps TGO as set
SET jq_out TO j_p64_step(jq_prog2, jq_st2, nav_derived(jq_st2, jt_land, jt_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_true("J P64: the window is closed with no PRO: no request", NOT jq_out["REQUEST"]:ISTYPE("Lexicon")).

// ---- 1.3.1: the J P63 starts with V06 N61 flashing until PRO (Luminary 210 also has it) ----
LOCAL jn_prog IS jt_prog("AUTO").
SET jn_prog["PROG_NO"] TO 63.
SET jn_prog["SEQ"] TO j_seq_new(2050).
SET jn_prog["ENGINE_LIT"] TO FALSE.
SET jn_prog["ZOOMED"] TO FALSE.
SET jn_prog["THR"] TO 0.
SET jn_prog["HIGHGATE"] TO FALSE.
SET jn_prog["GO"] TO FALSE.
SET jn_prog["N61_SHOWN"] TO FALSE.
SET jn_prog["LR_PERMIT"] TO FALSE.
SET jn_prog["N63_SHOWN"] TO FALSE.
SET jn_prog["LAST_REQ"] TO FALSE.
SET jn_prog["T_LAST"] TO 1999.75.
SET jn_prog["HANDOFF_T"] TO -1.
LOCAL jn_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jn_out IS j_p63_step(jn_prog, jt_state(2000, jt_r, jt_v, 0), nav_derived(jt_st, jt_land, jt_wm), jn_ks).
assert_true("J P63: first cycle shows V06 N61 as a request", jn_out["SET_VERB"] = 6 AND jn_out["SET_NOUN"] = 61 AND jn_out["REQUEST"]:ISTYPE("Lexicon") AND NOT jn_prog["GO"]).
SET jn_ks["PRO"] TO TRUE.
SET jn_out TO j_p63_step(jn_prog, jt_state(2000.25, jt_r, jt_v, 0), nav_derived(jt_st, jt_land, jt_wm), jn_ks).
assert_true("J P63: PRO sets GO and ends the request", jn_prog["GO"] AND NOT jn_out["REQUEST"]:ISTYPE("Lexicon")).

// ---- 1.3.1: J P63 flashes V06 N63 from ignition until V57, again after V58; PRO, ENTER and V34 do nothing to it ----
LOCAL jf_prog IS jt_prog("AUTO").
SET jf_prog["PROG_NO"] TO 63.
SET jf_prog["SEQ"] TO j_seq_new(2050).
SET jf_prog["SEQ"]["IGN_T"] TO 2051.
SET jf_prog["ZOOMED"] TO FALSE.
SET jf_prog["THR"] TO 0.1.
SET jf_prog["HIGHGATE"] TO FALSE.
SET jf_prog["GO"] TO TRUE.
SET jf_prog["N61_SHOWN"] TO TRUE.
SET jf_prog["LAST_REQ"] TO FALSE.
SET jf_prog["LR_PERMIT"] TO FALSE.
SET jf_prog["N63_SHOWN"] TO FALSE.
SET jf_prog["HANDOFF_T"] TO -1.
SET jf_prog["T_LAST"] TO 2051.75.
LOCAL jf_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jf_none IS LEXICON("VALID", FALSE).
LOCAL jf_out IS j_p63_step(jf_prog, jt_state(2052, jt_r, jt_v, 13.15), jf_none, jf_ks).
assert_true("J P63: flashing V06 N63 request from ignition", jf_out["REQUEST"]:ISTYPE("Lexicon") AND jf_out["REQUEST"]["NOUN"] = 63 AND jf_out["SET_VERB"] = 6 AND jf_out["SET_NOUN"] = 63).
SET jf_ks["PRO"] TO TRUE.
SET jf_ks["ENTER"] TO TRUE.
SET jf_ks["TERMINATE"] TO TRUE.
SET jf_out TO j_p63_step(jf_prog, jt_state(2052.25, jt_r, jt_v, 13.15), jf_none, jf_ks).
assert_true("J P63: PRO, ENTER and V34 do nothing while N63 flashes", jf_out["REQUEST"]:ISTYPE("Lexicon") AND NOT jf_out["ENDED"] AND jf_out["SET_VERB"] < 0).
SET jf_ks["PRO"] TO FALSE.
SET jf_ks["ENTER"] TO FALSE.
SET jf_ks["TERMINATE"] TO FALSE.
SET jf_prog["LR_PERMIT"] TO TRUE.
SET jf_out TO j_p63_step(jf_prog, jt_state(2052.5, jt_r, jt_v, 13.15), jf_none, jf_ks).
assert_true("J P63: V57 (permit) ends the flash: steady display", NOT jf_out["REQUEST"]:ISTYPE("Lexicon")).
SET jf_prog["LR_PERMIT"] TO FALSE.
SET jf_out TO j_p63_step(jf_prog, jt_state(2052.75, jt_r, jt_v, 13.15), jf_none, jf_ks).
assert_true("J P63: V58 makes it flash again and re-posts the display", jf_out["REQUEST"]:ISTYPE("Lexicon") AND jf_out["SET_NOUN"] = 63).

// ---- 1.3.1: J P66 flashes V06 N60; V34 ends it; PRO or V32 hold the last direction; N92 ----
LOCAL jg_prog IS j_p66_start(jt_prog("AUTO")).
LOCAL jg_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jg_st IS jt_state(3000, jt_r, jt_v, 13.15).
LOCAL jg_out IS j_p66_step(jg_prog, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_true("J P66: V06 N60 request on the first cycle", jg_out["REQUEST"]:ISTYPE("Lexicon") AND jg_out["REQUEST"]["NOUN"] = 60 AND jg_out["REQUEST"]["VERB"] = 6).
SET jg_st TO jt_state(3000.25, jt_r, jt_v, 13.15).
SET jg_out TO j_p66_step(jg_prog, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_true("J P66: the request stays every cycle", jg_out["REQUEST"]:ISTYPE("Lexicon") AND jg_out["SET_VERB"] < 0).
assert_true("J P66: the horizontal law is on at first", NOT jg_prog["HZ_OFF"]).
SET jg_ks["PRO"] TO TRUE.
SET jg_st TO jt_state(3002.5, jt_r, jt_v, 13.15).
SET jg_out TO j_p66_step(jg_prog, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_true("J P66: PRO switches the horizontal law off", jg_prog["HZ_OFF"]).
LOCAL jg_held IS jg_prog["BURN_DIR"].
SET jg_st TO jt_state(3006, jt_r, jt_v, 13.15).
SET jg_out TO j_p66_step(jg_prog, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_vec("J P66: the commanded direction is held", jg_prog["BURN_DIR"], jg_held, 1e-9).
LOCAL jg_prog2 IS j_p66_start(jt_prog("AUTO")).
SET jg_ks["RECYCLE"] TO TRUE.
SET jg_st TO jt_state(3000, jt_r, jt_v, 13.15).
j_p66_step(jg_prog2, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_true("J P66: V32 switches it off too", jg_prog2["HZ_OFF"]).
SET jg_ks["RECYCLE"] TO FALSE.
SET jg_ks["TERMINATE"] TO TRUE.
SET jg_out TO j_p66_step(jg_prog2, jg_st, nav_derived(jg_st, jt_land, jt_wm), jg_ks).
assert_true("J P66: V34 ends it", jg_out["ENDED"]).
assert_near("N92 thrust percent: 0.5 of 46.92 kN against 46.71 kN rated is 50.2", j_thr_percent(0.5, LEXICON("THRUST", 46.92)), 50.2246, 0.01).
LOCAL jg_regs IS noun_registers(92, LEXICON("VALID", TRUE, "THR_PCT", 50.2246, "HDOT", -1.0, "HCALC", 100)).
assert_true("N92 R1 is whole percent +00050", jg_regs[0] = "+00050").
assert_true("N92 is in the table", LM_NOUNS:CONTAINS(92)).

// ---- 1.3.1: the noun contents Luminary 210 changed (N60 R1 FORVEL, N63 R1 DELTAH, N68 R1 downrange and R3 ABVEL) ----
assert_near("lm_forvel: 3 m/s along the forward axis", lm_forvel(V(0, 2, 3), V(1737447, 0, 0), V(0, 0, 1)), 3, 1e-9).
assert_near("lm_forvel: crossrange speed is not forward", lm_forvel(V(0, 2, 0), V(1737447, 0, 0), V(0, 0, 1)), 0, 1e-9).
assert_near("lm_forvel: the vertical part of the speed does not count", lm_forvel(V(-5, 0, 3), V(1737447, 0, 0), V(0.5, 0, 1)), 3, 1e-9).
assert_near("lm_forvel: forward axis vertical gives 0", lm_forvel(V(0, 2, 3), V(1737447, 0, 0), V(1, 0, 0)), 0, 1e-9).
LOCAL jr_st IS jt_state(2000, jt_r, jt_v, 13.15).
LOCAL jr_d IS nav_derived(jr_st, jt_land, jt_wm).
SET jr_d["FORVEL"] TO 3.
LOCAL jr_099 IS noun_registers(60, jr_d).
LOCAL jr_j IS j_noun_registers(60, jr_d).
assert_true("J N60 R1 is FORVEL, 3 m/s = 9.8 ft/s", jr_j[0] = "+00098").
assert_true("J N60 R2 and R3 are as 099", jr_j[1] = jr_099[1] AND jr_j[2] = jr_099[2]).
assert_true("099 N60 R1 is still VHORIZ", jr_099[0] = fmt_reg(ms_to_fps(jr_d["VHORIZ"]), 1)).
LOCAL jr_j63 IS j_noun_registers(63, jr_d).
assert_true("J N63 R1 is DELTAH in whole feet", jr_j63[0] = fmt_reg(m_to_ft(jr_d["DELTAH"]), 0)).
assert_true("J N63 R2 and R3 as 099", jr_j63[1] = noun_registers(63, jr_d)[1] AND jr_j63[2] = noun_registers(63, jr_d)[2]).
LOCAL jr_j68 IS j_noun_registers(68, jr_d).
assert_true("J N68 R1 is the downrange component in nm", jr_j68[0] = fmt_reg(m_to_nm(jr_d["RGU"]:Z), 1)).
assert_true("J N68 R3 is ABVEL in ft/s", jr_j68[2] = fmt_reg(ms_to_fps(jr_d["ABVEL"]), 1)).
assert_true("J N68 R2 as 099", jr_j68[1] = noun_registers(68, jr_d)[1]).
assert_true("a noun J did not change is the same", j_noun_registers(62, jr_d)[0] = noun_registers(62, jr_d)[0]).
assert_true("no derived data: the same NA registers", j_noun_registers(60, LEXICON("VALID", FALSE))[0] = NA).

// ---- 1.3.1: J P63 V97 (the same monitor): a failed monitor flashes V97 N62; PRO resets; ENTR re-ignites 5 s later ----
LOCAL jv_prog IS jt_prog("AUTO").
SET jv_prog["PROG_NO"] TO 63.
SET jv_prog["SEQ"] TO j_seq_new(2050).
SET jv_prog["SEQ"]["IGN_T"] TO 2051.
SET jv_prog["ZOOMED"] TO FALSE.
SET jv_prog["THR"] TO 0.1.
SET jv_prog["HIGHGATE"] TO FALSE.
SET jv_prog["GO"] TO TRUE.
SET jv_prog["N61_SHOWN"] TO TRUE.
SET jv_prog["LAST_REQ"] TO FALSE.
SET jv_prog["LR_PERMIT"] TO TRUE.
SET jv_prog["N63_SHOWN"] TO TRUE.
SET jv_prog["HANDOFF_T"] TO -1.
SET jv_prog["T_LAST"] TO 2051.75.
SET jv_prog["DVMON"] TO dvmon_new().
SET jv_prog["DVSHOWN"] TO FALSE.
SET jv_prog["DVMON"]["FAILED"] TO TRUE.
LOCAL jv_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL jv_out IS j_p63_step(jv_prog, jt_state(2052, jt_r, jt_v, 0), jf_none, jv_ks).
assert_true("J P63: a failed thrust monitor shows a flashing V97 N62", jv_out["REQUEST"]:ISTYPE("Lexicon") AND jv_out["REQUEST"]["VERB"] = 97 AND jv_out["REQUEST"]["NOUN"] = 62 AND jv_out["SET_VERB"] = 97 AND jv_out["SET_NOUN"] = 62).
SET jv_ks["ENTER"] TO TRUE.
SET jv_out TO j_p63_step(jv_prog, jt_state(2052.25, jt_r, jt_v, 0), jf_none, jv_ks).
SET jv_ks["ENTER"] TO FALSE.
assert_true("J P63: ENTR at V97 puts the engine out and sets a new ignition 5 s later", NOT jv_prog["ENGINE_LIT"] AND ABS(jv_prog["TIG"] - 2057.25) < 0.001 AND NOT jv_prog["DVMON"]["FAILED"]).
SET jv_prog["ENGINE_LIT"] TO TRUE.
SET jv_prog["DVMON"]["FAILED"] TO TRUE.
SET jv_ks["PRO"] TO TRUE.
SET jv_out TO j_p63_step(jv_prog, jt_state(2052.5, jt_r, jt_v, 0), jf_none, jv_ks).
assert_true("J P63: PRO resets the monitor", NOT jv_prog["DVMON"]["FAILED"]).

test_end().
