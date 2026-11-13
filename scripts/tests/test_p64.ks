// test_p64.ks -- pad tests for the P64 milestone (run in the kOS terminal, no flight needed).
//   RUNPATH("0:/lm/tests/test_p64.ks").
// Expected values come from scripts/tests/reference.py ("Milestone 4" section) or are exact by definition. Results go to
// 0:/lm/test_p64.log. The log's last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_guidance.ks").
RUNONCEPATH("0:/lm/lm_control.ks").
RUNONCEPATH("0:/lm/lm_p64.ks").
RUNONCEPATH("0:/lm/tests/test_lib.ks").

test_begin("0:/lm/test_p64.log").

// ---- Task 2: approach constants (values from the P63 research note; sources in lm_constants.ks) -----------
assert_vec("RAPFG", RAPFG, V(33.858708, 0, -8.1668112), 1e-9).
assert_vec("VAPFG", VAPFG, V(-1.5218664, 0, 0.0755904), 1e-9).
assert_vec("AAPFG", AAPFG, V(-0.07997952, 0, -0.1560576), 1e-9).
assert_near("8 * JAPFG_Z = JAPFG*", 8 * JAPFG_Z, 5.51e-4, 1e-9).
assert_near("GAINAPPR", GAINAPPR, 0, 0).
assert_near("TCGFAPPR", TCGFAPPR, 30, 0).
assert_near("TCGIAPPR", TCGIAPPR, 200, 0).
assert_near("TENDAPPR", TENDAPPR, 12, 0).
assert_near("P64_PROJMAX", P64_PROJMAX, 0.42262, 1e-9).
assert_near("P64_PROJMIN", P64_PROJMIN, 0.25882, 1e-9).
assert_near("P64_DEPRCRIT", P64_DEPRCRIT, -0.02, 1e-9).
assert_near("P64_ELEACH_RAD is 0.5 deg", P64_ELEACH_RAD * 180 / CONSTANT:PI, 0.5, 0.001).
assert_near("P64_AZEACH_RAD is 2 deg", P64_AZEACH_RAD * 180 / CONSTANT:PI, 2, 0.001).

// ---- Task 2: target sets and the handoff test ----------------------------------------------------------------
assert_near("approach targets: TEND is TENDAPPR", guid_targets_approach()["TEND"], 12, 0).
assert_near("brake targets: TEND is TENDBRAK", guid_targets_brake()["TEND"], 62, 0).
assert_vec("approach targets: R is RAPFG", guid_targets_approach()["R"], RAPFG, 0).
assert_vec("brake targets: R is RBRFG", guid_targets_brake()["R"], RBRFG, 0).
assert_true("handoff at 11.9 s with TEND 12", guid_handoff(11.9, 12)).
assert_true("no handoff at 12.1 s with TEND 12", NOT guid_handoff(12.1, 12)).
assert_true("no handoff at 62 s with TEND 62", NOT guid_handoff(62, 62)).

// ---- Task 2: the guidance axes (CG) freeze outside TCGF..TCGI -----------------------------------------------
// Any state will do: only the returned CG is looked at. The marker is not a frame the real CG could equal.
LOCAL st_c IS LEXICON("BODY_OK", TRUE, "R", V(1737400 + 2000, 0, -9000), "V", V(-40, 0, 170),
                      "MASS", 9, "THRUST", 43.4547, "MU", 4.9028e12).
LOCAL land_c IS V(1737400, 0, 0).
LOCAL wm_c IS V(0, 2.66e-6, 0).
LOCAL marker IS LIST(V(0, 0, 1), V(1, 0, 0), V(0, 1, 0)).
LOCAL gp_frozen IS guid_pass(st_c, land_c, wm_c, 25, 1, guid_targets_approach(), marker).
assert_vec("CG frozen below TCGFAPPR (row 0)", gp_frozen["CG"][0], marker[0], 0).
assert_vec("CG frozen below TCGFAPPR (row 1)", gp_frozen["CG"][1], marker[1], 0).
assert_vec("CG frozen below TCGFAPPR (row 2)", gp_frozen["CG"][2], marker[2], 0).
LOCAL gp_live IS guid_pass(st_c, land_c, wm_c, 100, 1, guid_targets_approach(), marker).
assert_true("CG recomputed at 100 s to go", (gp_live["CG"][0] - marker[0]):MAG > 0.5).
LOCAL gp_old IS guid_pass(st_c, land_c, wm_c, 250, 1, guid_targets_approach(), marker).
assert_true("CG frozen above TCGIAPPR (200 s)", (gp_old["CG"][0] - marker[0]):MAG < 1e-12).
LOCAL gp_brake IS guid_pass(st_c, land_c, wm_c, 500, 1, guid_targets_brake(), marker).
assert_true("braking recomputes CG at 500 s (inside 30..900)", (gp_brake["CG"][0] - marker[0]):MAG > 0.5).
LOCAL gp_nocg IS guid_pass(st_c, land_c, wm_c, 25, 1, guid_targets_approach(), FALSE).
assert_true("no previous CG: computed even below TCGF", gp_nocg["CG"]:LENGTH = 3).

// ---- Task 3: EXNORM window vector (reference.py "Milestone 4 Task 3") ------------------------------------------
// Site on the raw +X axis (up), nose up. The ship is at LAND + offset; the guidance axes come from lm_frame.ks.
LOCAL wx_land IS V(1737400, 0, 0).
LOCAL wx_nose IS V(1, 0, 0).
LOCAL wx_r IS wx_land + V(3000, 0, -300).
LOCAL wx_cg IS guidance_cg(wx_land, wx_r, V(0, 0, 0), 0).
assert_vec("exnorm (a) nearly overhead: the horizontal axis toward the site", win_exnorm(wx_land, wx_r, wx_nose, wx_cg), wx_cg[2], 1e-9).
SET wx_r TO wx_land + V(1000, 0, -3000).
SET wx_cg TO guidance_cg(wx_land, wx_r, V(0, 0, 0), 0).
assert_vec("exnorm (b) shallow view: the line of sight to the site", win_exnorm(wx_land, wx_r, wx_nose, wx_cg), V(-0.316227766, 0, 0.948683298), 1e-8).
SET wx_r TO wx_land + V(2821.5, 0, -1020).
SET wx_cg TO guidance_cg(wx_land, wx_r, V(0, 0, 0), 0).
assert_vec("exnorm (c) blend", win_exnorm(wx_land, wx_r, wx_nose, wx_cg), V(-0.569237600, 0, 0.822173069), 1e-8).
SET wx_r TO wx_land + V(3000, 0, 0).
SET wx_cg TO guidance_cg(wx_land, wx_r, V(0, 0, 0), 0).
LOCAL wx_d IS win_exnorm(wx_land, wx_r, wx_nose, wx_cg).
assert_near("exnorm (d) directly above: a unit vector", wx_d:MAG, 1, 1e-9).
assert_near("exnorm (d) directly above: horizontal", wx_d:X, 0, 1e-9).
assert_true("exnorm result is unit length in (c)", ABS(win_exnorm(wx_land, wx_land + V(2821.5, 0, -1020), wx_nose, guidance_cg(wx_land, wx_land + V(2821.5, 0, -1020), V(0, 0, 0), 0)):MAG - 1) < 1e-9).

// ---- Task 4: click detector (keyboard: -1, 0 or 1 per axis, held while the key is down) --------------------
// Each case is a list of (pitch, yaw) samples fed one after another into a fresh detector; the signed sums are taken at the end.
FUNCTION clk_run {
  PARAMETER samples.
  LOCAL clk IS clk_new().
  FOR smp IN samples { clk_sample(clk, smp[0], smp[1]). }
  RETURN clk.
}
LOCAL clk_a IS clk_run(LIST(LIST(1, 0), LIST(1, 0), LIST(1, 0), LIST(0, 0))).
assert_near("a held key is one click (pitch count)", clk_a["COUNT"], 1, 0).
assert_near("a held key is one click (signed sum)", clk_a["EL"], P64_PITCH_SIGN, 0).
assert_near("a single short pulse is one click", clk_run(LIST(LIST(0, 0), LIST(1, 0), LIST(0, 0)))["COUNT"], 1, 0).
assert_near("a dip to 0.3 (above the rearm) is not a release", clk_run(LIST(LIST(1, 0), LIST(0.3, 0), LIST(1, 0)))["COUNT"], 1, 0).
assert_near("a dip to 0.1 (below the rearm) is a release", clk_run(LIST(LIST(1, 0), LIST(0.1, 0), LIST(1, 0)))["COUNT"], 2, 0).
assert_near("0.49 is below the threshold", clk_run(LIST(LIST(0.49, 0)))["COUNT"], 0, 0).
assert_near("0.5 is a click (threshold included)", clk_run(LIST(LIST(0.5, 0)))["COUNT"], 1, 0).
LOCAL clk_rev IS clk_run(LIST(LIST(1, 0), LIST(-1, 0))).
assert_near("a direct reversal counts a second click", clk_rev["COUNT"], 2, 0).
assert_near("a direct reversal: signed sum is zero", clk_rev["EL"], 0, 0).
LOCAL clk_yaw IS clk_run(LIST(LIST(0, 1))).
assert_near("yaw gives an azimuth click with the yaw sign", clk_yaw["AZ"], P64_YAW_SIGN, 0).
assert_near("yaw gives no elevation click", clk_yaw["EL"], 0, 0).
LOCAL clk_t IS clk_run(LIST(LIST(1, 0))).
LOCAL taken IS clk_take(clk_t).
assert_near("clk_take returns the elevation sum", taken["EL"], P64_PITCH_SIGN, 0).
assert_near("clk_take zeroes the pending sum", clk_t["EL"], 0, 0).
clk_sample(clk_t, 1, 0).
assert_near("the key is still held after clk_take: no new click", clk_t["EL"], 0, 0).
LOCAL clk_d IS clk_run(LIST(LIST(1, 1))).
clk_discard(clk_d).
assert_near("clk_discard zeroes elevation", clk_d["EL"], 0, 0).
assert_near("clk_discard zeroes azimuth", clk_d["AZ"], 0, 0).

// ---- Task 4: redesignation of the landing point (reference.py "Milestone 4 Task 4") ---------------------------
// Site on the raw +X axis (up); ship 3000 m above it and 6000 m before it; crossrange axis +Y.
LOCAL rd_land IS V(1737400, 0, 0).
LOCAL rd_r IS rd_land + V(3000, 0, -6000).
LOCAL rd_y IS V(0, 1, 0).
LOCAL rd_los IS rd_land - rd_r.
assert_vec("no clicks returns LAND", redes_los(rd_land, rd_r, rd_y, 0, 0), rd_land, 0).
LOCAL rd_el IS redes_los(rd_land, rd_r, rd_y, P64_ELEACH_RAD, 0).
assert_vec("one elevation click", rd_el, V(1737399.994888, 0, 133.277016), 1e-3).
assert_near("an elevation click turns the line of sight 0.5 deg", VANG(rd_los, rd_el - rd_r), 0.5, 0.05).
assert_near("and keeps |LAND|", rd_el:MAG, 1737400, 1e-3).
LOCAL rd_az IS redes_los(rd_land, rd_r, rd_y, 0, P64_AZEACH_RAD).
assert_vec("one azimuth click", rd_az, V(1737399.984217, -234.183397, 0), 1e-3).
assert_near("an azimuth click turns the line of sight 2 deg", VANG(rd_los, rd_az - rd_r), 2, 0.05).
assert_vec("both clicks", redes_los(rd_land, rd_r, rd_y, P64_ELEACH_RAD, P64_AZEACH_RAD), V(1737399.978539, -238.344898, 133.277015), 1e-3).
assert_vec("a down click", redes_los(rd_land, rd_r, rd_y, -P64_ELEACH_RAD, 0), V(1737399.995233, 0, -128.702848), 1e-3).
// A click that would raise the line of sight above the limit is clamped (DEPRCRIT).
LOCAL rd_r2 IS rd_land + V(100, 0, -6000).
LOCAL rd_cl IS redes_los(rd_land, rd_r2, rd_y, P64_ELEACH_RAD, 0).
assert_vec("a clamped click", rd_cl, V(1737399.712233, 0, -999.966735), 1e-3).
assert_true("the clamped line of sight stays below the horizon limit", VDOT((rd_cl - rd_r2):NORMALIZED, rd_land:NORMALIZED) < -0.0199).
// Degenerate geometry never gives NaN: the ship exactly above the site, exactly at it, and below its height.
LOCAL rd_over IS redes_los(rd_land, rd_land + V(3000, 0, 0), rd_y, P64_ELEACH_RAD, P64_AZEACH_RAD).
assert_near("directly above: finite and |LAND| kept", rd_over:MAG, 1737400, 1e-3).
assert_vec("ship at the site: LAND unchanged", redes_los(rd_land, rd_land, rd_y, P64_ELEACH_RAD, 0), rd_land, 0).
assert_vec("ship below the site's height: LAND unchanged", redes_los(rd_land, rd_land + V(-50, 0, -500), rd_y, P64_ELEACH_RAD, 0), rd_land, 0).

// ---- Task 4: the window in which redesignation is possible ------------------------------------------------------
assert_true("redesignation open at 40 s to go", p64_redes_open(40)).
assert_true("redesignation closed at 34 s (TCGFAPPR + 4)", NOT p64_redes_open(34)).
assert_true("redesignation open at 34.1 s", p64_redes_open(34.1)).
assert_true("redesignation closed at 12 s", NOT p64_redes_open(12)).

// ---- Task 6: the programme on the pad (CTL_DRY: the ship's controls are not touched) ---------------------------
// States are from reference.py sim_approach (the Apollo 11 braking-then-approach point-mass run), site on the raw +X axis.
RUNONCEPATH("0:/lm/lm_nav.ks").
RUNONCEPATH("0:/lm/lm_display.ks").               // keys_new
SET CTL_DRY TO TRUE.
FUNCTION d4_prog {
  RETURN LEXICON("REFUSED", "", "WINDOW_MODE", "UP", "TURNED", FALSE, "FORE0", V(1, 0, 0), "WIN0", V(0, 1, 0), "WCMD", V(0, 1, 0),
                 "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "WARP", warp_new(), "ENGINE", 0,
                 "LAND", V(1737400, 0, 0), "WM", V(0, 2.66e-6, 0), "TIG", 1000, "BURN_DIR", V(0, 0, 1), "OUTOFPLN", 0,
                 "TGO", 60, "THR", 1, "GP", LEXICON(), "ZOOMED", TRUE, "ENGINE_LIT", TRUE, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", 1999.75, "HANDOFF_T", 1999, "LAST_STATE", "", "LAST_ALARM", 0, "ENDED", FALSE).
}
FUNCTION d4_state {
  PARAMETER now_ut, r_vec, v_vec.
  RETURN LEXICON("R", r_vec, "V", v_vec, "T", now_ut, "MASS", 15.2697, "THRUST", 43.4547,
                 "THRUST_NOW", 43.4547, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 2400, "XNB", V(1, 0, 0)).
}
LOCAL d4_land IS V(1737400, 0, 0).
LOCAL d4_wm IS V(0, 2.66e-6, 0).
LOCAL d4_r0 IS V(1739767.504, 0, -8502.208).
LOCAL d4_v0 IS V(-42.2285, 0, 178.0790).
LOCAL d4_ks IS keys_new().
LOCAL p4 IS p64_start(d4_prog(), 0, 23.47, 0).
assert_near("p64_start: programme number", p4["PROG_NO"], 64, 0).
assert_near("p64_start: time-to-go gets the DELTTFAP step (60 + 110)", p4["TGO"], 170, 1e-9).
assert_true("p64_start: redesignation not permitted yet", NOT p4["PERMIT"]).
assert_near("p64_start: the handoff time is reset", p4["HANDOFF_T"], -1, 0).
assert_near("p64_start keeps the site latitude", p4["SITE_LAT"], 0, 0).
assert_near("p64_start keeps the site longitude", p4["SITE_LNG"], 23.47, 0).

LOCAL st4 IS d4_state(2000, d4_r0, d4_v0).
LOCAL out4 IS p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_near("first step sets verb 6", out4["SET_VERB"], 6, 0).
assert_near("first step sets noun 64", out4["SET_NOUN"], 64, 0).
assert_true("first step flashes with KEY REL until PRO", out4["FLASH"] AND out4["KEY_REL"]).
assert_near("p64_step reports PROG_NO 64", out4["PROG_NO"], 64, 0).
assert_true("p64_step never asks for a handover", NOT out4["HANDOVER"]).
assert_near("approach guidance converges: no alarm", out4["ALARM"], 0, 0).
assert_near("approach time-to-go near the reference simulation (169.5 s)", p4["GP"]["TGO"], 169.5, 2).
assert_true("the displayed time-to-go (TTFDISP) is the guidance time-to-go", ABS(out4["EXTRA"]["TTFDISP"] - p4["GP"]["TGO"]) < 1e-9).
SET st4 TO d4_state(2000.25, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_near("the display is requested only once", out4["SET_VERB"], -1, 0).

// Clicks before PRO are thrown away (Review Focus 3).
LOCAL land_before IS p4["LAND"].
clk_sample(p4["CLK"], 1, 0).
SET st4 TO d4_state(2000.5, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_vec("a click before PRO does not move the site", p4["LAND"], land_before, 0).
assert_near("and is not kept for later", p4["CLK"]["EL"], 0, 0).
clk_sample(p4["CLK"], 0, 0).

// PRO permits redesignation: the flashing stops.
SET d4_ks["PRO"] TO TRUE.
SET st4 TO d4_state(2000.75, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_true("PRO permits redesignation", p4["PERMIT"]).
assert_true("PRO stops the flashing and releases KEY REL", NOT out4["FLASH"] AND NOT out4["KEY_REL"]).
assert_true("PRO is cleared by the step", NOT d4_ks["PRO"]).

// A click after PRO in AUTO moves the site.
clk_sample(p4["CLK"], 1, 0).
SET st4 TO d4_state(2001, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_true("a click after PRO moves the site", (p4["LAND"] - land_before):MAG > 10).
assert_near("the moved site keeps its radius", p4["LAND"]:MAG, 1737400, 1e-3).
assert_true("and the step says so", out4["MSG"]:CONTAINS("REDESIGNATED")).
assert_near("the applied clicks are counted", p4["EL_TOTAL"], P64_PITCH_SIGN, 0).
clk_sample(p4["CLK"], 0, 0).

// In ATT HOLD the clicks are ignored (Review Focus 3), and are not kept for later.
SET p4["ATT"]["MODE"] TO "HOLD".
LOCAL land_hold IS p4["LAND"].
clk_sample(p4["CLK"], 1, 0).
SET st4 TO d4_state(2001.25, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_vec("a click in ATT HOLD does not move the site", p4["LAND"], land_hold, 0).
SET p4["ATT"]["MODE"] TO "AUTO".
clk_sample(p4["CLK"], 0, 0).
SET st4 TO d4_state(2001.5, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_vec("the click made in ATT HOLD is not applied after the return to AUTO", p4["LAND"], land_hold, 0).

// Too late: inside TCGFAPPR + 4 s the window is closed.
SET p4["TGO"] TO 33.5.
clk_sample(p4["CLK"], 1, 0).
SET st4 TO d4_state(2001.75, d4_r0, d4_v0).
SET out4 TO p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), d4_ks).
assert_vec("a click inside 34 s to go does not move the site", p4["LAND"], land_hold, 0).
clk_sample(p4["CLK"], 0, 0).

// The handover to P65: at the end of the sim (time-to-go 11.56 s) the step asks for it once and does not end the programme.
LOCAL p4e IS d4_prog().
SET p4e TO p64_start(p4e, 0, 23.47, 0).
SET p4e["TGO"] TO 11.8.
LOCAL d4_re IS V(1737447.083, 0, -20.009).
LOCAL d4_ve IS V(-0.9239, 0, 6.6854).
LOCAL st4e IS d4_state(3000, d4_re, d4_ve).
SET p4e["T_LAST"] TO 2999.75.
LOCAL out4e IS p64_step(p4e, st4e, nav_derived(st4e, d4_land, d4_wm), keys_new()).
assert_true("handover: asked for at the end of the approach", out4e["HANDOVER"]).
assert_true("handover: the message names P65", out4e["MSG"]:CONTAINS("P65")).
assert_true("handover: the programme does not end itself", NOT out4e["ENDED"]).
SET st4e TO d4_state(3000.25, d4_re, d4_ve).
SET out4e TO p64_step(p4e, st4e, nav_derived(st4e, d4_land, d4_wm), keys_new()).
assert_true("handover: asked for once only", NOT out4e["HANDOVER"]).
// V34 ENTR ends P64 at once.
LOCAL k34 IS keys_new().
SET k34["VERB"] TO 34.
SET st4 TO d4_state(2002, d4_r0, d4_v0).
assert_true("V34 ends P64", p64_step(p4, st4, nav_derived(st4, d4_land, d4_wm), k34)["ENDED"]).
SET CTL_DRY TO FALSE.

test_end().
