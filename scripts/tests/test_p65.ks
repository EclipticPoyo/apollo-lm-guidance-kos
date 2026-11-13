// test_p65.ks -- pad tests for the P65/P66 milestone (run in the kOS terminal, no flight needed).
//   RUNPATH("0:/tests/test_p65.ks").
// Expected values come from scripts/tests/reference.py ("Milestone 5" section) or are exact by definition. Results go to
// 0:/lm/logs/test_p65.log. The log's last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent/lm_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_p65.log").

// ---- Task 3: constants (pad loads from the research note; sources in lm_constants.ks) -------------------------------
assert_vec("V2FG", V2FG, V(-0.9144, 0, 0), 1e-9).
assert_near("TAUVERT", TAUVERT, 10, 0).
assert_near("RODSCALE is 1 ft/s", RODSCALE, 0.3048, 1e-9).
assert_near("TAUROD", TAUROD, 1.5, 0).
assert_near("LAG_TAU", LAG_TAU, 0.413333, 1e-9).
assert_near("MINFORCE is 980 lbf", MINFORCE, 4360, 0).
assert_near("MAXFORCE is 6300 lbf", MAXFORCE, 28000, 0).

// ---- Task 3: P65 guidance (reference.py: the P64 end, 47.1 m up, 20 m before the site, vg = (-0.92, 2.06)) ---------------
LOCAL v_land IS V(1737400, 0, 0).
LOCAL v_wm IS V(0, 0, 0).
LOCAL v_r IS v_land + V(47.1, 0, -20).
LOCAL v_cg IS guidance_cg(v_land, v_r, V(0, 0, 0), 0).
LOCAL v_state IS LEXICON("BODY_OK", TRUE, "R", v_r, "V", V(-0.92, 0, 2.06), "MASS", 8.095, "THRUST", 43.4547, "MU", 4.9028e12).
LOCAL gp_v IS guid_pass_vert(v_state, v_land, v_wm, 0.3, v_cg).
assert_true("guid_pass_vert VALID", gp_v["VALID"]).
assert_vec("guid_pass_vert VGU", gp_v["VGU"], V(-0.92, 0, 2.06), 1e-9).
assert_vec("guid_pass_vert ACG = (V2FG - VGU)/TAUVERT", gp_v["ACG"], V(0.00056, 0, -0.206), 1e-9).
assert_near("guid_pass_vert AFC up cancels gravity", gp_v["AFC"]:X, 1.6248, 0.002).
// ACG downrange is -0.206; gravity's horizontal part at 20 m off the site (1.6242 x 20/1737447 = 1.9e-5) is subtracted too.
assert_near("guid_pass_vert AFC downrange", gp_v["AFC"]:Z, -0.206, 1e-4).
assert_true("guid_pass_vert throttle in range", gp_v["THR"] > 0.2 AND gp_v["THR"] < 0.4).
assert_true("guid_pass_vert reports the thrust wanted before the curve", gp_v["WANTED"] > 0.28 AND gp_v["WANTED"] < 0.33).
LOCAL v_nobody IS LEXICON("BODY_OK", FALSE).
assert_true("guid_pass_vert off the body is not valid", NOT guid_pass_vert(v_nobody, v_land, v_wm, 0.3, v_cg)["VALID"]).
LOCAL v_nomass IS LEXICON("BODY_OK", TRUE, "R", v_r, "V", V(-0.92, 0, 2.06), "MASS", 0, "THRUST", 43.4547, "MU", 4.9028e12).
assert_near("guid_pass_vert zero mass keeps the throttle", guid_pass_vert(v_nomass, v_land, v_wm, 0.3, v_cg)["THR"], 0.3, 0).
LOCAL v_nothrust IS LEXICON("BODY_OK", TRUE, "R", v_r, "V", V(-0.92, 0, 2.06), "MASS", 8.095, "THRUST", 0, "MU", 4.9028e12).
assert_near("guid_pass_vert zero thrust keeps the throttle", guid_pass_vert(v_nothrust, v_land, v_wm, 0.3, v_cg)["THR"], 0.3, 0).

// ---- the engine curve: wanted thrust to commanded throttle (measured in the milestone 3 and 4 flights) ----------------
assert_near("curve: below the least thrust gives the minimum throttle", thr_for_thrust(0.1), 0.1, 1e-9).
assert_near("curve: the least thrust", thr_for_thrust(0.182), 0.1, 1e-9).
assert_near("curve: 0.282 thrust needs throttle 0.2", thr_for_thrust(0.282), 0.2, 1e-9).
assert_near("curve: halfway between 0.282 and 0.648", thr_for_thrust(0.465), 0.425, 1e-9).
assert_near("curve: 0.648 thrust needs throttle 0.65", thr_for_thrust(0.648), 0.65, 1e-9).
assert_near("curve: full thrust", thr_for_thrust(1), 1, 1e-9).
assert_near("curve: more than full stays 1", thr_for_thrust(1.2), 1, 1e-9).
assert_near("curve: thr_command passes full throttle through", thr_command(1), 1, 0).

// ---- the thrust trim ----------------------------------------------------------------------------------------
assert_near("trim: moves toward the error (0.02 short for 0.25 s)", trim_step(0, 0.3, 0.28, 0.25), 0.001, 1e-12).
assert_near("trim: and the other way when the engine gives too much", trim_step(0, 0.3, 0.32, 0.25), -0.001, 1e-12).
assert_near("trim: limited to the most allowed", trim_step(0.099, 0.6, 0.2, 10), THR_TRIM_MAX, 1e-12).
assert_near("trim: and the least", trim_step(-0.099, 0.2, 0.6, 10), -THR_TRIM_MAX, 1e-12).
assert_near("trim: nothing wanted, no change", trim_step(0.05, -1, 0.3, 0.25), 0.05, 0).
assert_near("trim: no thrust measured, no change", trim_step(0.05, 0.3, 0, 0.25), 0.05, 0).

// ---- Task 3: P66 throttle (reference.py rod_throttle_ref; mass 8000 kg, 43454.7 N, |g| 1.62) -----------------------------
LOCAL rd_m IS 8000.
LOCAL rd_f IS 43454.7.
LOCAL rd IS guid_rod_throttle(-2, -2, 1, rd_m, rd_f, 0.3, 1.62, 1.62).
assert_near("rod: on the commanded rate it hovers (A_CMD)", rd["A_CMD"], 1.62, 1e-9).
assert_near("rod: and WANTED is the thrust fraction before the curve", rd["WANTED"], 0.298241617, 1e-6).
assert_near("rod: on the commanded rate it hovers (THR, through the engine curve)", rd["THR"], 0.219969201, 1e-6).
SET rd TO guid_rod_throttle(-2, -2, 1, rd_m, rd_f, 0.3, 1.2, 1.62).
assert_near("rod: lag term when the thrust now is below hover (A_CMD)", rd["A_CMD"], 1.79359986, 1e-6).
assert_near("rod: lag term (THR)", rd["THR"], 0.259263906, 1e-6).
SET rd TO guid_rod_throttle(-0.5, -2, 1, rd_m, rd_f, 0.3, 1.62, 1.62).
assert_near("rod: wanting 1.5 m/s less descent adds 1 m/s^2", rd["A_CMD"], 2.62, 1e-9).
SET rd TO guid_rod_throttle(-2, -2, 0.9, rd_m, rd_f, 0.3, 1.62, 1.62).
assert_near("rod: a tilted thrust axis needs more thrust", rd["A_CMD"], 1.87439994, 1e-6).
SET rd TO guid_rod_throttle(100, -2, 1, rd_m, rd_f, 0.3, 1.62, 1.62).
assert_near("rod: a huge command is limited to MAXFORCE/mass", rd["A_CMD"], 3.5, 1e-9).
assert_near("rod: and the throttle is the one that gives MAXFORCE", rd["THR"], 0.645511278, 1e-6).
SET rd TO guid_rod_throttle(100, -2, 1, rd_m, 40000, 0.95, 1.62, 1.62).
assert_near("rod: with less thrust the limit stays under the dead band (A_CMD)", rd["A_CMD"], 3.25, 1e-9).
assert_near("rod: so the throttle never jumps to full", rd["THR"], 0.651988636, 1e-6).
SET rd TO guid_rod_throttle(-100, -2, 1, rd_m, rd_f, 0.3, 1.62, 1.62).
assert_near("rod: a tiny command is limited to the engine's least thrust", rd["A_CMD"], 0.988594425, 1e-6).
assert_near("rod: and the throttle is the engine's minimum", rd["THR"], 0.1, 1e-9).
SET rd TO guid_rod_throttle(-2, -2, 0, rd_m, rd_f, 0.4, 1.62, 1.62).
assert_near("rod: thrust axis horizontal keeps the throttle", rd["THR"], 0.4, 0).
assert_near("rod: and commands nothing", rd["A_CMD"], 0, 0).
SET rd TO guid_rod_throttle(-2, -2, 1, 0, rd_f, 0.4, 1.62, 1.62).
assert_near("rod: zero mass keeps the throttle", rd["THR"], 0.4, 0).
SET rd TO guid_rod_throttle(-2, -2, 1, rd_m, 0, 0.4, 1.62, 1.62).
assert_near("rod: zero thrust keeps the throttle", rd["THR"], 0.4, 0).

// ---- Task 4: ROD clicks from the throttle lever (probe: 0.01 per 0.02 s sample while a key is down) -------------------
// rod_ramp: feed `count` samples, 0.02 s apart from time t0, with the lever going from lever0 by `delta` each sample (never past 0 or 1);
// then, like the main loop, re-centre the lever when the detector asks. Returns the time after the last sample. The lever now
// is kept in the global rod_lever (a kOS function cannot return two values).
GLOBAL rod_lever IS 0.5.
FUNCTION rod_ramp {
  PARAMETER rod, lever0, delta, count, t0.
  LOCAL t_now IS t0.
  SET rod_lever TO lever0.
  FROM { LOCAL i IS 0. } UNTIL i >= count STEP { SET i TO i + 1. } DO {
    SET rod_lever TO MAX(0, MIN(1, rod_lever + delta)).
    rod_sample(rod, rod_lever, t_now).
    IF rod["RECENTRE"] { SET rod["RECENTRE"] TO FALSE. SET rod_lever TO 0.5. }
    SET t_now TO t_now + 0.02.
  }
  RETURN t_now.
}

LOCAL rd_a IS rod_new().
LOCAL rd_t IS rod_ramp(rd_a, 0.5, 0.01, 20, 0).               // Shift held 0.4 s: the lever goes 0.5 to 0.7
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).            // key released: still for 0.24 s
assert_near("rod: a ramp up then still is one click", rod_take(rd_a), 1, 0).
assert_near("rod: the lever is re-centred afterwards", rod_lever, 0.5, 0).
assert_near("rod: and the waiting count was cleared", rod_take(rd_a), 0, 0).

SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 4, 0).                   // a short Shift tap: the lever moves 0.04 (probe) and stays there
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: a short tap is one click", rod_take(rd_a), 1, 0).

SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 60, 0).                  // Shift held 1.2 s (the lever is written back to 0.5 every sample, so it never reaches an end stop)
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: a long hold is one click, not one per step", rod_take(rd_a), 1, 0).
SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 150, 0).                 // Shift held 3 s
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: a 3 s hold is still one click", rod_take(rd_a), 1, 0).
assert_near("rod: and the lever ends centred", rod_lever, 0.5, 0).
// KSP X (cut throttle: lever to 0) and Z (full throttle: lever to 1) are not clicks; nor is a lever that starts at 0.
SET rd_a TO rod_new().
rod_sample(rd_a, 0.5, 0).
rod_sample(rd_a, 0, 0.02).
assert_near("rod: the X key (lever jumps to 0) is not a click", rod_take(rd_a), 0, 0).
assert_true("rod: and the lever is to be re-centred", rd_a["RECENTRE"]).
SET rd_a TO rod_new().
rod_sample(rd_a, 0, 0).
assert_near("rod: a lever that starts at 0 is not a click", rod_take(rd_a), 0, 0).
SET rd_a TO rod_new().
rod_sample(rd_a, 1, 0).
assert_near("rod: the Z key (lever jumps to 1) is not a click", rod_take(rd_a), 0, 0).

SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, -0.01, 20, 0).                 // Ctrl held: the lever goes 0.5 down to 0.3
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: a ramp down is one click down", rod_take(rd_a), -1, 0).

SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 6, 0).                   // a tap up, release, then a tap down
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: tap up then still: +1", rod_take(rd_a), 1, 0).
SET rd_t TO rod_ramp(rd_a, 0.5, -0.01, 6, rd_t).
SET rd_t TO rod_ramp(rd_a, rod_lever, 0, 12, rd_t).
assert_near("rod: then a tap down: -1", rod_take(rd_a), -1, 0).

SET rd_a TO rod_new().
SET rd_t TO 0.
FROM { LOCAL i IS 0. } UNTIL i >= 50 STEP { SET i TO i + 1. } DO {
  rod_sample(rd_a, 0.5 + MOD(i, 2) * 0.002, rd_t).               // noise of 0.002 between samples, under ROD_LEVER_STEP (0.004)
  SET rd_t TO rd_t + 0.02.
}
assert_near("rod: noise under the step makes no click", rod_take(rd_a), 0, 0).

SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 6, 0).
assert_near("rod: rod_take returns the waiting click", rod_take(rd_a), 1, 0).
assert_near("rod: and a second take is empty", rod_take(rd_a), 0, 0).
SET rd_a TO rod_new().
SET rd_t TO rod_ramp(rd_a, 0.5, 0.01, 6, 0).
rod_discard(rd_a).
assert_near("rod: discard forgets the waiting clicks", rod_take(rd_a), 0, 0).

// ---- Task 5: contact and cut-off -----------------------------------------------------------------------------------
assert_true("contact: LANDED", contact_test("LANDED", 5, -3)).
assert_true("contact: SPLASHED", contact_test("SPLASHED", 5, -3)).
assert_true("contact: the height-and-speed fallback is off by default", NOT contact_test("FLYING", 0.5, -0.2)).
SET P66_CONTACT_FALLBACK TO TRUE.
assert_true("contact: fallback on, almost on the surface and slow", contact_test("FLYING", 0.5, -0.2)).
assert_true("contact: fallback on, not while still sinking fast", NOT contact_test("FLYING", 0.5, -2)).
assert_true("contact: fallback on, not high up and still", NOT contact_test("FLYING", 30, 0)).
SET P66_CONTACT_FALLBACK TO FALSE.
assert_true("contact: not high up and still", NOT contact_test("FLYING", 30, 0)).
LOCAL ct_a IS contact_new().
LOCAL ct_r IS contact_step(ct_a, FALSE, 100, FALSE).
assert_true("contact: no lamp before contact", NOT ct_r["LAMP"]).
assert_true("contact: no cut-off before contact", NOT ct_r["CUT_NOW"]).
SET ct_r TO contact_step(ct_a, TRUE, 200, FALSE).
assert_true("contact: the lamp lights at once", ct_r["LAMP"]).
assert_true("contact: cut-off not yet at 0 s", NOT ct_r["CUT_NOW"]).
SET ct_r TO contact_step(ct_a, TRUE, 200.1, FALSE).
assert_true("contact: cut-off not yet at 0.1 s", NOT ct_r["CUT_NOW"]).
SET ct_r TO contact_step(ct_a, TRUE, 200 + P66_CUTOFF_DELAY_S, FALSE).
assert_true("contact: cut-off at the delay (one cycle)", ct_r["CUT_NOW"] AND ct_r["DONE"]).
SET ct_r TO contact_step(ct_a, TRUE, 200.4, FALSE).
assert_true("contact: cut-off once only", NOT ct_r["CUT_NOW"]).
assert_true("contact: the lamp stays lit", ct_r["LAMP"]).
SET ct_a TO contact_new().
contact_step(ct_a, TRUE, 300, FALSE).
SET ct_r TO contact_step(ct_a, TRUE, 300.1, TRUE).
SET ct_r TO contact_step(ct_a, TRUE, 300.5, TRUE).
assert_true("contact: a pilot engine stop cancels the cut-off", NOT ct_r["CUT_NOW"]).
assert_true("contact: but the landing still ends (P68)", ct_r["DONE"]).
assert_true("contact: and the lamp is lit", ct_r["LAMP"]).
SET ct_a TO contact_new().
contact_step(ct_a, FALSE, 400, FALSE).
SET ct_r TO contact_step(ct_a, FALSE, 410, FALSE).
assert_true("contact: no contact at all, no lamp", NOT ct_r["LAMP"]).

// ---- Task 6: the programme on the pad (CTL_DRY: the ship's controls are not touched) ---------------------------------
// The state is the end of P64 in reference.py (47.1 m up, 20 m before the site, vg = (-0.92, 2.06)), the site on the raw +X axis.
RUNONCEPATH("0:/shared/lm_nav.ks").
RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
RUNONCEPATH("0:/lm/descent/lm_p65.ks").
SET CTL_DRY TO TRUE.
FUNCTION p5_prog {
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
FUNCTION p5_state {
  PARAMETER now_ut, r_vec, v_vec, thrust_now.
  RETURN LEXICON("R", r_vec, "V", v_vec, "T", now_ut, "MASS", 8.095, "THRUST", 43.4547,
                 "THRUST_NOW", thrust_now, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 47, "XNB", V(1, 0, 0)).
}
LOCAL p5_land IS V(1737400, 0, 0).
LOCAL p5_wm IS V(0, 0, 0).
LOCAL p5_r IS V(1737447.1, 0, -20).
LOCAL p5_v IS V(-0.92, 0, 2.06).
LOCAL p5_ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL p5 IS p65_start(p5_prog("AUTO")).
assert_near("p65_start: programme number", p5["PROG_NO"], 65, 0).
assert_true("p65_start: mode P65", p5["MODE"] = "P65").
assert_true("p65_start: keeps the guidance axes P64 left", p5["CG"]:ISTYPE("List")).
assert_true("p65_start: keeps the engine state", p5["ENGINE_LIT"]).
assert_true("p65_start: starts in AUTO attitude", p5["ATT"]["MODE"] = "AUTO").

LOCAL st5 IS p5_state(2000, p5_r, p5_v, 13.15).
LOCAL out5 IS p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_near("first step sets verb 6", out5["SET_VERB"], 6, 0).
assert_near("first step sets noun 60", out5["SET_NOUN"], 60, 0).
assert_near("p65_step reports PROG_NO 65", out5["PROG_NO"], 65, 0).
assert_true("p65_step never asks for a handover", NOT out5["HANDOVER"]).
assert_true("p65_step: no contact lamp in the air", NOT out5["CONTACT"]).
assert_true("p65_step: the throttle is a sensible fraction", CTL_THR > 0.2 AND CTL_THR < 0.4).
assert_near("p65_step: the thrust direction is nearly up (raw X)", p5["BURN_DIR"]:NORMALIZED:X, 0.992, 0.002).
assert_near("p65_step: and tilted back toward the site (the site is 20 m ahead, the ship 2 m/s too fast)", p5["BURN_DIR"]:NORMALIZED:Z, -0.1258, 0.005).
SET st5 TO p5_state(2000.25, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_near("the display is requested only once", out5["SET_VERB"], -1, 0).
assert_true("still P65 with no clicks", p5["MODE"] = "P65").

// In AUTO a ROD click is thrown away (Luminary GUILDEN zeroes the count every AUTO pass): P66 needs ATT HOLD (SAS on).
LOCAL p5_rt IS rod_ramp(p5["ROD"], 0.5, 0.01, 6, 0).
SET p5_rt TO rod_ramp(p5["ROD"], rod_lever, 0, 12, p5_rt).      // the key is released: the detector re-arms
SET st5 TO p5_state(2000.4, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_true("a ROD click in AUTO does not start P66", p5["MODE"] = "P65").
assert_true("and the message says to switch SAS on", out5["MSG"]:CONTAINS("AUTO")).
assert_near("and the click is not kept for later", rod_take(p5["ROD"]), 0, 0).
// SAS on alone does nothing; SAS on plus a click starts P66.
SET p5["ATT"]["MODE"] TO "HOLD".
SET st5 TO p5_state(2000.45, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_true("SAS on alone does not start P66", p5["MODE"] = "P65").
// The first ROD click with SAS on starts P66: VDG starts at the vertical speed and the click counts, as in Luminary (STARTP66 then RODCOMP).
SET p5_rt TO rod_ramp(p5["ROD"], 0.5, 0.01, 6, p5_rt).
SET p5_rt TO rod_ramp(p5["ROD"], rod_lever, 0, 12, p5_rt).
SET st5 TO p5_state(2000.5, p5_r, p5_v, 13.15).
LOCAL d5 IS nav_derived(st5, p5_land, p5_wm).
SET out5 TO p65_step(p5, st5, d5, p5_ks).
assert_true("a ROD click with SAS on starts P66", p5["MODE"] = "P66").
assert_near("and the programme number is 66", out5["PROG_NO"], 66, 0).
assert_near("VDG started at HDOT plus the click", p5["VDG"], d5["HDOT"] + RODSCALE * P66_ROD_SIGN, 1e-9).
assert_near("the display is requested again for P66", out5["SET_NOUN"], 60, 0).
assert_true("the message does not repeat the new rate (the status readout shows it)", NOT out5["MSG"]:CONTAINS("FT/S") AND NOT out5["MSG"]:CONTAINS("COMMANDED DESCENT RATE")).
assert_true("and says P66 has started", out5["MSG"]:CONTAINS("RATE OF DESCENT")).
// The terminal status readout: two fixed lines, descent rate positive going down, in m/s.
assert_true("status has three lines", out5["STATUS"]:LENGTH = 3).
assert_true("P66 status line 3 is the key hint", out5["STATUS"][2]:CONTAINS("SHIFT")).
assert_true("status line 1 is the descent rate in m/s (down positive)", out5["STATUS"][0] = "DESCENT RATE  " + p65_ms_text(-d5["HDOT"]) + " m/s").
assert_true("P66 status line 2 is the commanded rate in m/s", out5["STATUS"][1] = "P66 COMMANDED " + p65_ms_text(-p5["VDG"]) + " m/s").
assert_true("p65_ms_text 0.9144", p65_ms_text(0.9144) = "0.91").
assert_true("p65_ms_text negative", p65_ms_text(-0.304) = "-0.30").
assert_true("p65_ms_text tiny negative has no minus", p65_ms_text(-0.001) = "0.00").
assert_true("p65_ms_text two digits", p65_ms_text(12.346) = "12.35").
assert_true("p65_ms_text zero", p65_ms_text(0) = "0.00").
LOCAL st_p65 IS p65_status(LEXICON("MODE", "P65", "VDG", 0), LEXICON("VALID", TRUE, "HDOT", -1.2)).
assert_true("P65 status shows the rate and the target", st_p65[0] = "DESCENT RATE  1.20 m/s" AND st_p65[1] = "P65 TARGET    0.91 m/s" AND st_p65:LENGTH = 3 AND st_p65[2]:CONTAINS("P66")).
assert_true("status with no data shows -----", p65_status(LEXICON("MODE", "P65", "VDG", 0), LEXICON("VALID", FALSE))[0] = "DESCENT RATE  ----- m/s").
SET p5_rt TO rod_ramp(p5["ROD"], 0.5, 0.01, 6, p5_rt).
SET p5_rt TO rod_ramp(p5["ROD"], rod_lever, 0, 12, p5_rt).
LOCAL vdg_before IS p5["VDG"].
SET st5 TO p5_state(2000.75, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_near("a second click changes VDG by exactly RODSCALE", p5["VDG"] - vdg_before, RODSCALE * P66_ROD_SIGN, 1e-9).
SET p5_rt TO rod_ramp(p5["ROD"], 0.5, -0.01, 6, p5_rt).
SET p5_rt TO rod_ramp(p5["ROD"], rod_lever, 0, 12, p5_rt).
SET vdg_before TO p5["VDG"].
SET st5 TO p5_state(2001, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_near("a click the other way lowers VDG by RODSCALE", vdg_before - p5["VDG"], RODSCALE * P66_ROD_SIGN, 1e-9).
assert_true("P66 throttle is a sensible fraction", CTL_THR > 0.1 AND CTL_THR < 0.7).
LOCAL dir_p66 IS p5["BURN_DIR"].
SET st5 TO p5_state(2001.25, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_vec("P66 keeps the last P65 thrust direction", p5["BURN_DIR"], dir_p66, 0).
// In P66 a click in AUTO is also thrown away, and going back to AUTO does not end P66.
SET p5["ATT"]["MODE"] TO "AUTO".
SET p5_rt TO rod_ramp(p5["ROD"], 0.5, 0.01, 6, p5_rt).
SET p5_rt TO rod_ramp(p5["ROD"], rod_lever, 0, 12, p5_rt).
SET vdg_before TO p5["VDG"].
SET st5 TO p5_state(2001.5, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_near("a click in AUTO leaves VDG alone in P66", p5["VDG"], vdg_before, 0).
assert_true("and P66 goes on in AUTO", p5["MODE"] = "P66").

// SAS already on at the start: nothing happens until a click.
LOCAL p5t IS p65_start(p5_prog("HOLD")).
SET st5 TO p5_state(2003, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5t, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
SET st5 TO p5_state(2003.25, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5t, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_true("SAS already on at the start does not start P66 by itself", p5t["MODE"] = "P65").
LOCAL p5_rt2 IS rod_ramp(p5t["ROD"], 0.5, 0.01, 6, 20).
SET st5 TO p5_state(2003.5, p5_r, p5_v, 13.15).
SET out5 TO p65_step(p5t, st5, nav_derived(st5, p5_land, p5_wm), p5_ks).
assert_true("but a ROD click with SAS on starts P66", p5t["MODE"] = "P66").

// The thrust trim in the programme: the engine gives less than wanted, so the throttle goes up cycle by cycle.
LOCAL p5r IS p65_start(p5_prog("AUTO")).
SET p5r["T_LAST"] TO 2029.75.                      // so the first step is one 0.25 s cycle, not 30 s
LOCAL st5r IS p5_state(2030, p5_r, p5_v, 10).
SET out5 TO p65_step(p5r, st5r, nav_derived(st5r, p5_land, p5_wm), p5_ks).
LOCAL thr_first IS CTL_THR.
LOCAL trim_first IS p5r["TRIM"].
assert_true("trim: grows when the thrust measured is below the thrust wanted", trim_first > 0).
SET st5r TO p5_state(2030.25, p5_r, p5_v, 10).
SET out5 TO p65_step(p5r, st5r, nav_derived(st5r, p5_land, p5_wm), p5_ks).
assert_true("trim: keeps growing while the error stays", p5r["TRIM"] > trim_first).
assert_true("and the throttle goes up with it", CTL_THR > thr_first).

// Zero thrust: the throttle stays finite and unchanged.
LOCAL p5z IS p65_start(p5_prog("AUTO")).
LOCAL st5z IS LEXICON("R", p5_r, "V", p5_v, "T", 2004, "MASS", 8.095, "THRUST", 0, "THRUST_NOW", 0, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 47, "XNB", V(1, 0, 0)).
SET out5 TO p65_step(p5z, st5z, nav_derived(st5z, p5_land, p5_wm), p5_ks).
assert_near("zero thrust keeps the throttle (P65)", CTL_THR, 0.3, 1e-9).

// Contact (the ship status turns LANDED): lamp at once, cut-off one cycle (0.25 s) later, P68, and the programme ends.
SET CTL_DRY_STATUS TO "LANDED".
LOCAL p5c IS p65_start(p5_prog("AUTO")).
LOCAL st5c IS p5_state(2005, V(1737400.5, 0, 0), V(-0.2, 0, 0), 13.15).
SET out5 TO p65_step(p5c, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
assert_true("contact: the lamp lights", out5["CONTACT"]).
assert_true("contact: not ended yet", NOT out5["ENDED"]).
assert_true("contact: the message says so", out5["MSG"]:CONTAINS("CONTACT")).
SET st5c TO p5_state(2005.1, V(1737400.5, 0, 0), V(-0.2, 0, 0), 13.15).
SET out5 TO p65_step(p5c, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
assert_true("contact: still burning at 0.1 s", NOT out5["ENDED"]).
SET st5c TO p5_state(2005.25, V(1737400.5, 0, 0), V(-0.2, 0, 0), 13.15).
SET out5 TO p65_step(p5c, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
assert_true("contact: the engine is cut off one cycle after contact and the programme ends", out5["ENDED"]).
assert_near("contact: the cut-off cycle reports P68", out5["PROG_NO"], 68, 0).
assert_near("contact: the throttle is zero", CTL_THR, 0, 0).
assert_true("contact: the engine is no longer lit", NOT p5c["ENGINE_LIT"]).
LOCAL p5d IS p65_start(p5_prog("AUTO")).
SET st5c TO p5_state(2010, V(1737400.5, 0, 0), V(-0.2, 0, 0), 13.15).
SET out5 TO p65_step(p5d, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
SET st5c TO p5_state(2010.1, V(1737400.5, 0, 0), V(-0.2, 0, 0), 0).
SET out5 TO p65_step(p5d, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
SET st5c TO p5_state(2010.5, V(1737400.5, 0, 0), V(-0.2, 0, 0), 0).
SET out5 TO p65_step(p5d, st5c, nav_derived(st5c, p5_land, p5_wm), p5_ks).
assert_true("contact: a pilot engine stop does not stop the landing from ending", out5["ENDED"]).
assert_near("contact: and P68 is reported", out5["PROG_NO"], 68, 0).
assert_true("contact: without cutting the engine off again", out5["MSG"]:CONTAINS("ALREADY STOPPED")).
SET CTL_DRY_STATUS TO "FLYING".

// V34 ends P65 at once.
LOCAL k34 IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
SET k34["VERB"] TO 34.
LOCAL p5v IS p65_start(p5_prog("AUTO")).
SET st5 TO p5_state(2020, p5_r, p5_v, 13.15).
assert_true("V34 ends P65", p65_step(p5v, st5, nav_derived(st5, p5_land, p5_wm), k34)["ENDED"]).
SET CTL_DRY TO FALSE.

test_end().
