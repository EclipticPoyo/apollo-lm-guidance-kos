// test_term.ks -- pad test for the terminal-phase maths (lm/rndz/lm_term.ks): the line-of-sight rate, the gauge's needles, when it shows and the
// docking message; and the vehicle's condition and hook for them (lm_vehicle.ks). Vectors by hand, the nose (+X) up the raw Y axis and the window
// face (+Z) along raw Z, so the crew's right is raw X. The hook reads the ship: run it anywhere but with a CSM in lunar orbit in reach. No window
// is made (LM_VEH has no "GAUGE").
//   RUNPATH("0:/tests/test_term.ks").   Log: 0:/lm/logs/test_term.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/rndz/lm_term.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_term.log").
SET CONFIG:IPU TO 2000.

GLOBAL TTM_NOSE IS V(0, 1, 0).
GLOBAL TTM_FACE IS V(0, 0, 1).

// ttm_los: term_los with the test's attitude.
FUNCTION ttm_los {
  PARAMETER line, line_rate.
  RETURN term_los(line, line_rate, TTM_NOSE, TTM_FACE).
}
// ttm_pair: the needles' two rates (mrad/s) against the expected ones.
FUNCTION ttm_pair {
  PARAMETER name, got, up_want, right_want.
  assert_true(name + ": on axis", got["ONAXIS"]).
  assert_near(name + ": up", got["UP"], up_want, 0.001).
  assert_near(name + ": right", got["RIGHT"], right_want, 0.001).
}
// ttm_off: nothing on the needles.
FUNCTION ttm_off {
  PARAMETER name, got.
  assert_true(name + ": off axis", NOT got["ONAXIS"]).
  assert_near(name + ": up", got["UP"], 0, 0).
  assert_near(name + ": right", got["RIGHT"], 0, 0).
}

// ---- the line-of-sight rate ----
LOCAL ttm_ahead IS V(0, 0, 1000).
ttm_pair("drift to the right", ttm_los(ttm_ahead, V(1, 0, 0)), 0, 1).
ttm_pair("drift up", ttm_los(ttm_ahead, V(0, 2, 0)), 2, 0).
ttm_pair("closing only", ttm_los(ttm_ahead, V(0, 0, -5)), 0, 0).
assert_near("closing only: speed", ttm_los(ttm_ahead, V(0, 0, -5))["SPEED"], 5, 0.001).
assert_near("closing only: range", ttm_los(ttm_ahead, V(0, 0, -5))["RANGE"], 1000, 0.001).
ttm_pair("drift down and left", ttm_los(ttm_ahead, V(-1, -1, 0)), -1, -1).

// The line towards the nose from the face: the needles work to 30 degrees.
LOCAL ttm_l29 IS V(0, SIN(29), COS(29)) * 1000.
ttm_pair("29 deg towards the nose", ttm_los(ttm_l29, V(0, COS(29), -SIN(29)) * 1.5), 1.5, 0).
ttm_pair("29 deg towards the nose, drift down", ttm_los(ttm_l29, V(0, COS(29), -SIN(29)) * -1.5), -1.5, 0).
ttm_off("31 deg towards the nose", ttm_los(V(0, SIN(31), COS(31)) * 1000, V(1, 1, 0))).
ttm_off("the line along the nose", ttm_los(V(0, 1000, 0), V(1, 1, 0))).
ttm_off("a zero line", ttm_los(V(0, 0, 0), V(1, 1, 0))).

// The same directions with everything turned give the same numbers.
LOCAL ttm_turn IS ANGLEAXIS(40, V(1, 1, 0)).
LOCAL ttm_turned IS term_los(ttm_turn * ttm_l29, ttm_turn * (V(1, 0, 0) * 2 + V(0, COS(29), -SIN(29)) * 1.5), ttm_turn * TTM_NOSE, ttm_turn * TTM_FACE).
ttm_pair("all turned", ttm_turned, 1.5, 2).

// ---- the needles ----
assert_near("needle: half", term_needle(10, 20), 0.5, 0.000001).
assert_near("needle: past the stop", term_needle(-30, 20), -1, 0).
assert_near("needle: past the stop, low scale", term_needle(3, 2), 1, 0).
assert_near("needle pixels: centred", term_needle_px(0, 20, 73), 0, 0).
assert_near("needle pixels: a quarter of full scale", term_needle_px(5, 20, 72), 18, 0).
assert_near("needle pixels: half, low scale, the other way", term_needle_px(-1, 2, 72), -36, 0).
assert_near("needle pixels: past the stop", term_needle_px(-30, 20, 73), -73, 0).

// ---- when it shows, and the docking message ----
// ttm_seen: a snapshot with the CSM range_m ahead, closing at speed_ms.
FUNCTION ttm_seen {
  PARAMETER range_m, speed_ms.
  RETURN LEXICON("OK", TRUE, "WHY", "", "R", V(0, 0, 0), "V", V(0, 0, 0), "RT", V(0, 0, range_m), "VT", V(0, 0, -speed_ms)).
}
FUNCTION ttm_step {
  PARAMETER dock_st, wanted, seen.
  RETURN term_step(dock_st, wanted, seen, TTM_NOSE, TTM_FACE).
}
LOCAL ttm_st IS term_dock_new().
LOCAL ttm_o IS ttm_step(ttm_st, FALSE, ttm_seen(200, 0.1)).
assert_true("not wanted: hidden, silent, nothing armed", NOT ttm_o["SHOW"] AND ttm_o["SAY"] = "" AND NOT ttm_st["ARMED"] AND NOT ttm_o["LOS"]:ISTYPE("Lexicon")).
SET ttm_o TO ttm_step(ttm_st, TRUE, LEXICON("OK", FALSE, "WHY", "the LM is not in lunar orbit")).
assert_true("no CSM or landed: hidden, silent, nothing armed", NOT ttm_o["SHOW"] AND ttm_o["SAY"] = "" AND NOT ttm_st["ARMED"] AND NOT ttm_st["TOLD"]).
SET ttm_o TO ttm_step(ttm_st, TRUE, ttm_seen(20, 0.1)).
assert_true("just undocked (20 m, never further): no message", ttm_o["SAY"] = "" AND ttm_o["SHOW"]).
ttm_step(ttm_st, TRUE, ttm_seen(200, 0.1)).
assert_true("200 m: armed", ttm_st["ARMED"]).
SET ttm_o TO ttm_step(ttm_st, TRUE, ttm_seen(20, 0.3)).
assert_true("20 m at 0.3 m/s: too fast, silent", ttm_o["SAY"] = "").
SET ttm_o TO ttm_step(ttm_st, TRUE, ttm_seen(40, 0.1)).
assert_true("40 m at 0.1 m/s: too far, silent", ttm_o["SAY"] = "").
SET ttm_o TO ttm_step(ttm_st, TRUE, ttm_seen(20, 0.1)).
assert_true("20 m at 0.1 m/s: time to dock", ttm_o["SAY"] = DOCK_TEXT).
assert_true("the line of sight comes with it", ttm_o["LOS"]:ISTYPE("Lexicon")).
IF ttm_o["LOS"]:ISTYPE("Lexicon") { assert_near("its range", ttm_o["LOS"]["RANGE"], 20, 0.001). }
SET ttm_o TO ttm_step(ttm_st, TRUE, ttm_seen(20, 0.1)).
assert_true("said once", ttm_o["SAY"] = "").
assert_true("shown at 74000 m", ttm_step(term_dock_new(), TRUE, ttm_seen(74000, 30))["SHOW"]).
assert_true("hidden at 74200 m", NOT ttm_step(term_dock_new(), TRUE, ttm_seen(74200, 30))["SHOW"]).

// ---- the figures under the dial: range, range rate, next gate ----
assert_near("range rate: closing is negative", ttm_step(term_dock_new(), TRUE, ttm_seen(1000, 5))["LOS"]["RATE"], -5, 0.001).
assert_near("range rate off axis too", term_los(V(1000, 0, 0), V(3, 4, 0), TTM_NOSE, TTM_FACE)["RATE"], 3, 0.001).
assert_true("two decimals keep their zeros", term_fixed(1.5, 2) = "1.50").
assert_true("under one", term_fixed(-0.46, 1) = "-0.5").
assert_true("no minus zero", term_fixed(-0.04, 1) = "0.0").
// ttm_read: the three lines at range_ft closing at speed_fps.
FUNCTION ttm_read {
  PARAMETER range_ft, speed_fps, profile.
  RETURN term_readout(LEXICON("RANGE", range_ft / FT_PER_M, "RATE", -speed_fps / FT_PER_M), profile).
}
LOCAL ttm_lines IS ttm_read(5980, 28.4, "J").
assert_true("range in feet", ttm_lines[0] = "RANGE  5980 FT").
assert_true("range rate", ttm_lines[1] = "RATE  -28.4 FT/S").
assert_true("next gate", ttm_lines[2] = "BY 3000 FT: -20 FT/S").
assert_true("opening is marked plus", ttm_read(5980, -3, "J")[1] = "RATE  +3.0 FT/S" AND ttm_read(5980, 0, "J")[1] = "RATE  +0.0 FT/S").
assert_true("far: nmi and the first gate", ttm_read(12.34 * M_PER_NM * FT_PER_M, 90, "J")[0] = "RANGE  12.34 NM"
            AND ttm_read(75000, 90, "J")[2] = "BY 6000 FT: -30 FT/S").
assert_true("550 ft, 210: the 500 ft gate", ttm_read(550, 6, "J")[2] = "BY 500 FT: -5 FT/S").
assert_true("550 ft, 099: past the 600 ft gate", ttm_read(550, 4, "A11")[2] = "BY 100 FT: -0.5 FT/S").
assert_true("80 ft: docking", ttm_read(80, 0.3, "A11")[2] = "DOCK: -0.5 FT/S").

// ---- the physics warp warning near the CSM ----
LOCAL ttm_warp IS LEXICON("ON", FALSE).
assert_true("no warp: silent", term_warp_step(ttm_warp, "PHYSICS", 1, 500) = "").
assert_true("physics warp near: told", term_warp_step(ttm_warp, "PHYSICS", 2, 500) = WARP_NEAR_TEXT).
assert_true("once", term_warp_step(ttm_warp, "PHYSICS", 4, 400) = "").
assert_true("rails warp: silent", term_warp_step(ttm_warp, "RAILS", 10, 500) = "").
assert_true("the next one is told again", term_warp_step(ttm_warp, "PHYSICS", 2, 500) = WARP_NEAR_TEXT).
assert_true("far: silent", term_warp_step(ttm_warp, "PHYSICS", 2, 2600) = "").

// ---- the vehicle: when the gauge is wanted, and the per-cycle hook with no window ----
LOCAL ttm_had IS LEXICON().
FOR ttm_key IN LIST("TRK_RUN", "DOCK", "TERM_NEXT", "TERM_CSM", "GAUGE", "STORE") {
  IF LM_VEH:HASKEY(ttm_key) {
    SET ttm_had[ttm_key] TO LM_VEH[ttm_key].
    LM_VEH:REMOVE(ttm_key).
  }
}
SET LM_VEH["STORE"] TO store_new(lm_cells_for("A11")).
assert_true("wanted: P47", lm_term_wanted(LEXICON("PROG_NO", 47))).
assert_true("not wanted: P40", NOT lm_term_wanted(LEXICON("PROG_NO", 40))).
assert_true("not wanted: nothing running", NOT lm_term_wanted(FALSE)).
SET LM_VEH["TRK_RUN"] TO TRUE.
assert_true("wanted: P20 or P25 with no programme", lm_term_wanted(FALSE)).
assert_true("wanted: P20 or P25 under P40", lm_term_wanted(LEXICON("PROG_NO", 40))).
lm_term_hook(FALSE).
lm_term_hook(LEXICON("PROG_NO", 47)).
assert_true("hook with no window and no CSM: it runs on", LM_VEH:HASKEY("DOCK") AND LM_VEH:HASKEY("TERM_NEXT")).
lm_term_tick().                                      // no window: nothing to move
SET LM_VEH["GAUGE"] TO LEXICON("SHOWN", FALSE).
lm_term_tick().                                      // no CSM found yet
SET LM_VEH["TERM_CSM"] TO SHIP.
lm_term_tick().                                      // window hidden: the needles are left alone
assert_true("tick with no window, no CSM or a hidden window: it runs on", TRUE).
LM_VEH:REMOVE("GAUGE").
LM_VEH:REMOVE("TERM_CSM").
SET LM_VEH["TRK_RUN"] TO FALSE.
lm_term_hook(FALSE).
assert_true("hook when not wanted: it runs on", NOT LM_VEH["DOCK"]["TOLD"]).
FOR ttm_key IN LIST("TRK_RUN", "DOCK", "TERM_NEXT", "TERM_CSM", "STORE") { IF LM_VEH:HASKEY(ttm_key) { LM_VEH:REMOVE(ttm_key). } }
FOR ttm_key IN ttm_had:KEYS { SET LM_VEH[ttm_key] TO ttm_had[ttm_key]. }

test_end().
