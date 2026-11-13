// test_math.ks -- pad tests (run in the kOS terminal, no flight needed).
//   RUNPATH("0:/lm/tests/test_math.ks").
// Expected values come from scripts/tests/reference.py.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_nav.ks").
RUNONCEPATH("0:/lm/lm_display.ks").

GLOBAL TESTS_PASSED IS 0.
GLOBAL TESTS_FAILED IS 0.

// report: print a line to the terminal and append it to a log file Claude can read.
// LOG appends, so delete the old file first.
GLOBAL TEST_LOG IS "0:/lm/test_math.log".
IF EXISTS(TEST_LOG) { DELETEPATH(TEST_LOG). }
FUNCTION report {
  PARAMETER text.
  PRINT text.
  LOG text TO TEST_LOG.
}

// assert_near: pass when |actual - expected| <= tol, otherwise print both values.
FUNCTION assert_near {
  PARAMETER name, actual, expected, tol.
  IF ABS(actual - expected) <= tol {
    report("PASS " + name).
    SET TESTS_PASSED TO TESTS_PASSED + 1.
  } ELSE {
    report("FAIL " + name + " got " + actual + " expected " + expected).
    SET TESTS_FAILED TO TESTS_FAILED + 1.
  }
}

// assert_true: pass when the condition is true (booleans can't go through assert_near).
FUNCTION assert_true {
  PARAMETER name, condition.
  IF condition {
    report("PASS " + name).
    SET TESTS_PASSED TO TESTS_PASSED + 1.
  } ELSE {
    report("FAIL " + name).
    SET TESTS_FAILED TO TESTS_FAILED + 1.
  }
}

// ---- Task 2: units -------------------------------------------------------
assert_near("m_to_ft(1)",     m_to_ft(1),     3.28084, 1e-5).
assert_near("ms_to_fps(100)", ms_to_fps(100), 328.084, 1e-3).
assert_near("m_to_nm(1852)",  m_to_nm(1852),  1,       1e-9).

// ---- Task 3: landing-site frame (pure maths, no flight data) -------------
// assert_vec: a vector is "near" another when the length of their difference is within tol.
FUNCTION assert_vec {
  PARAMETER name, actual, expected, tol.
  assert_near(name, (actual - expected):MAG, 0, tol).
}

LOCAL site_vec IS V(0, 1737000, 0).                  // landing site straight up the +Y axis

// A point 100 m directly above the site: RGU is 100 m "up", nothing sideways. This also
// exercises the "ship directly above the site" fallback in guidance_cg.
LOCAL over_vec IS V(0, 1737100, 0).
LOCAL cg_over IS guidance_cg(site_vec, over_vec, V(0, 0, 0), 0).
assert_vec("rgu 100 m above LAND", rgu(cg_over, over_vec, site_vec), V(100, 0, 0), 1e-6).

// Orientation: ship 500 m back along -X and 100 m higher. Row 0 is up, row 2 points toward the
// site (+X), row 1 is sideways with its sign set by FRAME_SIGN (the handedness check).
LOCAL back_vec IS V(-500, 1737100, 0).
LOCAL cg_back IS guidance_cg(site_vec, back_vec, V(0, 0, 0), 0).
assert_vec("cg row 0 is up",          cg_back[0], V(0, 1, 0),          1e-9).
assert_vec("cg row 1 handedness",     cg_back[1], V(0, 0, FRAME_SIGN), 1e-9).
assert_vec("cg row 2 toward site",    cg_back[2], V(1, 0, 0),          1e-9).
assert_vec("vgu 3 m/s toward site",   vgu(cg_back, V(3, 0, 0), back_vec, V(0, 0, 0)), V(0, 0, 3), 1e-9).

// Rows orthonormal.
assert_near("cg row 0 length",   cg_back[0]:MAG, 1, 1e-9).
assert_near("cg row 1 length",   cg_back[1]:MAG, 1, 1e-9).
assert_near("cg row 2 length",   cg_back[2]:MAG, 1, 1e-9).
assert_near("cg rows 0.1 ortho", VDOT(cg_back[0], cg_back[1]), 0, 1e-9).
assert_near("cg rows 0.2 ortho", VDOT(cg_back[0], cg_back[2]), 0, 1e-9).
assert_near("cg rows 1.2 ortho", VDOT(cg_back[1], cg_back[2]), 0, 1e-9).

// LAND = 0: identity, no NaN.
LOCAL cg_zero IS guidance_cg(V(0, 0, 0), back_vec, V(0, 0, 0), 0).
assert_vec("cg identity row 0", cg_zero[0], V(1, 0, 0), 1e-12).
assert_vec("cg identity row 1", cg_zero[1], V(0, 1, 0), 1e-12).
assert_vec("cg identity row 2", cg_zero[2], V(0, 0, 1), 1e-12).

// VGU spin term: identity frame, WM = (0,0.001,0), R = (0,0,100), V = (1,2,3).
// Expected V - FRAME_SIGN*(WM x R) = (1 - FRAME_SIGN*0.1, 2, 3), so (1.1, 2, 3) when FRAME_SIGN = -1.
assert_vec("vgu spin term", vgu(cg_zero, V(1, 2, 3), V(0, 0, 100), V(0, 0.001, 0)),
           V(1 - FRAME_SIGN * 0.1, 2, 3), 1e-12).

// land_update: w = 0.01 rad/s, dt = 10 s, WM perpendicular to LAND. Luminary's first-order
// formula turns LAND by atan(w*dt) = 5.710593137 degrees (reference.py) and keeps its length.
LOCAL spin_vec IS V(0, 0.01, 0).
LOCAL flat_vec IS V(1737000, 0, 0).
LOCAL moved_vec IS land_update(flat_vec, spin_vec, 10).
assert_near("land_update length", moved_vec:MAG, flat_vec:MAG, 1e-6).
assert_near("land_update angle",  VANG(flat_vec, moved_vec), 5.710593137, 1e-6).
// ...and it turns the way Luminary's WM x LAND says: the new unit vector, projected on the tangent
// unit(WM x LAND), is sin(atan(w*dt)) = 0.1/sqrt(1.01) = 0.0995037190 (positive = right direction).
// (The chord moved - flat is NOT along the tangent: it is tilted by half the turn angle.)
assert_near("land_update direction", VDOT(moved_vec:NORMALIZED, lm_cross(spin_vec, flat_vec):NORMALIZED), 0.0995037190, 1e-9).
assert_vec("land_update dt = 0",  land_update(flat_vec, spin_vec, 0),  flat_vec, 0).
assert_vec("land_update dt = -5", land_update(flat_vec, spin_vec, -5), flat_vec, 0).
LOCAL big_vec IS land_update(flat_vec, V(0, 0.001, 0), 1e6).
assert_near("land_update dt = 1e6 length", big_vec:MAG, flat_vec:MAG, 1e-6).

// ---- Task 4: navigation (nav_derived on fabricated states, no flight data) ----
// fake_state: a state lexicon like nav_state() returns, with the given position, velocity and
// radar altitude. XNB is the ship's up axis; here straight along +Y.
FUNCTION fake_state {
  PARAMETER pos_vec, vel_vec, radar, body_ok.
  RETURN LEXICON("R", pos_vec, "V", vel_vec, "T", 0, "MASS", 15000, "THRUST", 0,
                 "BODY_OK", body_ok, "ALT_RADAR", radar, "XNB", V(0, 1, 0)).
}
LOCAL no_spin IS V(0, 0, 0).

// Vertical descent at 10 m/s, 100 m above the site.
LOCAL d1 IS nav_derived(fake_state(over_vec, V(0, -10, 0), 100, TRUE), site_vec, no_spin).
assert_near("nav vertical HDOT",    d1["HDOT"],    -10, 1e-9).
assert_near("nav vertical VHORIZ",  d1["VHORIZ"],  0,   1e-9).
assert_near("nav vertical ABVEL",   d1["ABVEL"],   10,  1e-9).
assert_near("nav vertical HCALC",   d1["HCALC"],   100, 1e-6).
assert_near("nav vertical RANGEDSP",d1["RANGEDSP"],100, 1e-6).
assert_near("nav vertical DELTAH",  d1["DELTAH"],  0,   1e-6).
assert_near("nav vertical LOOKANGL",d1["LOOKANGL"],90,  1e-6).

// Pure horizontal motion, 100 m above the site, 25 m/s sideways. (HDOT uses unit(R), so the ship
// must be straight above the origin-to-site line for HDOT to be exactly 0.)
LOCAL d2 IS nav_derived(fake_state(over_vec, V(25, 0, 0), 90, TRUE), site_vec, no_spin).
assert_near("nav horizontal HDOT",   d2["HDOT"],   0,  1e-6).
assert_near("nav horizontal VHORIZ", d2["VHORIZ"], 25, 1e-6).
assert_near("nav DELTAH = radar - HCALC", d2["DELTAH"], 90 - d2["HCALC"], 1e-9).

// Ship exactly at the site: no NaN, no error.
LOCAL d3 IS nav_derived(fake_state(site_vec, V(0, 0, 0), 0, TRUE), site_vec, no_spin).
assert_near("nav at LAND RANGEDSP", d3["RANGEDSP"], 0, 1e-9).
assert_near("nav at LAND HCALC",    d3["HCALC"],    0, 1e-9).
assert_near("nav at LAND LOOKANGL", d3["LOOKANGL"], 0, 1e-9).

// Wrong body: invalid, and nothing else computed.
LOCAL d4 IS nav_derived(fake_state(over_vec, V(0, -10, 0), 100, FALSE), site_vec, no_spin).
assert_true("nav wrong body VALID is false", NOT d4["VALID"]).
assert_true("nav wrong body no HDOT",        NOT d4:HASKEY("HDOT")).
assert_true("nav good body VALID",           d1["VALID"]).

// ---- Task 5: display formatting, noun table, key entry (no flight data) ----
assert_true("fmt_reg(12345,0)",     fmt_reg(12345, 0) = "+12345").
assert_true("fmt_reg(-12,0)",       fmt_reg(-12, 0) = "-00012").
assert_true("fmt_reg(123456,0)",    fmt_reg(123456, 0) = "+99999").
assert_true("fmt_reg(-123456,0)",   fmt_reg(-123456, 0) = "-99999").
assert_true("fmt_reg(123.46,1)",    fmt_reg(123.46, 1) = "+123.5").
assert_true("fmt_reg(-0.04,0) no negative zero", fmt_reg(-0.04, 0) = "+00000").
assert_true("fmt_minsec(125)",      fmt_minsec(125) = "+02 05").
assert_true("fmt_minsec(-35)",      fmt_minsec(-35) = "-00 35").
assert_true("fmt_minsec(-0.2) has no minus", fmt_minsec(-0.2) = "+00 00").

assert_true("pad_right pads",        pad_right("ab", 5) = "ab   ").
assert_true("pad_right cuts",        pad_right("abcdef", 3) = "abc").

// Plain-text terminal display: display_lines returns the screen as a list of lines.
LOCAL d_disp IS LEXICON("VALID", TRUE, "HDOT", -3, "VHORIZ", 25, "ABVEL", 25.2, "RANGEDSP", 5000,
                        "LOOKANGL", 42.3, "HCALC", 120, "ALT_RADAR", 118, "DELTAH", -2, "VGU", V(-3, 4, 25)).
LOCAL flags_none IS LEXICON("PROG", FALSE, "OPRERR", FALSE, "ENTRY", "").
LOCAL lines_a IS display_lines(d_disp, "63", 16, 60, flags_none).
assert_true("display_lines count",     lines_a:LENGTH = 17).
assert_true("display_lines PVN",       lines_a[2] = "PROG 63    VERB 16    NOUN 60").
assert_true("display_lines no alarms", lines_a[3] = "ALARMS:").
assert_true("display_lines R1",        lines_a[5] = "R1  +00082").
assert_true("display_lines R2",        lines_a[6] = "R2  -00010").
assert_true("display_lines R3",        lines_a[7] = "R3  +00394").
assert_true("display_lines ALT",       lines_a[11] = "ALT      +00394 ft").
assert_true("display_lines ALT RATE",  lines_a[12] = "ALT RATE -00010 ft/s").
assert_true("display_lines FWD VEL",   lines_a[13] = "FWD VEL  +00082 ft/s").
assert_true("display_lines LAT VEL",   lines_a[14] = "LAT VEL  +00013 ft/s").
LOCAL flags_err IS LEXICON("PROG", TRUE, "OPRERR", TRUE, "ENTRY", "V99").
LOCAL lines_b IS display_lines(d_disp, "63", 99, 60, flags_err).
assert_true("display_lines alarms",    lines_b[3] = "ALARMS: [PROG] [OPR ERR]").
assert_true("display_lines entry",     lines_b[9] = "ENTRY: V99").
LOCAL lines_c IS display_lines(LEXICON("VALID", FALSE), "63", 16, 60, flags_none).
assert_true("display_lines invalid R1", lines_c[5] = "R1  -----").
assert_true("display_lines invalid ALT", lines_c[11] = "ALT      ----- ft").
assert_true("display_lines noun 99 blank regs", display_lines(d_disp, "63", 16, 99, flags_none)[5] = "R1  -----").

// entry_text: V16 then N pressed must read "V16 N", not "N16" (the old demo bug).
LOCAL ks_e IS keys_new().
assert_true("entry_text empty",      entry_text(ks_e) = "").
key_press(ks_e, "V").
assert_true("entry_text V",          entry_text(ks_e) = "V").
key_press(ks_e, "1").
key_press(ks_e, "6").
assert_true("entry_text V16",        entry_text(ks_e) = "V16").
key_press(ks_e, "N").
assert_true("entry_text V16 N",      entry_text(ks_e) = "V16 N").
key_press(ks_e, "6").
key_press(ks_e, "0").
assert_true("entry_text V16 N60",    entry_text(ks_e) = "V16 N60").
key_press(ks_e, "E").
assert_true("entry_text after ENTR", entry_text(ks_e) = "").

// Noun 60: VHORIZ, HDOT (ft/s) and HCALC (ft). Reuse d2: VHORIZ 25 m/s, HDOT 0.
LOCAL n60 IS noun_registers(60, d2).
assert_true("noun 60 has 3 registers", n60:LENGTH = 3).
assert_true("noun 60 R1 = VHORIZ ft/s", n60[0] = fmt_reg(ms_to_fps(d2["VHORIZ"]), 0)).
assert_true("noun 60 R2 = HDOT ft/s",   n60[1] = fmt_reg(ms_to_fps(d2["HDOT"]), 0)).
assert_true("noun 60 R3 = HCALC ft",    n60[2] = fmt_reg(m_to_ft(d2["HCALC"]), 0)).
LOCAL n61 IS noun_registers(61, d2).
assert_true("noun 61 all unavailable", n61:LENGTH = 3 AND n61[0] = "-----" AND n61[1] = "-----" AND n61[2] = "-----").
assert_true("noun 99 is empty", noun_registers(99, d2):LENGTH = 0).

// Key entry: V16 N60 ENTR commits; V99 ENTR lights OPR ERR; RSET clears it.
FUNCTION type_keys {
  PARAMETER ks, text.
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { key_press(ks, text:SUBSTRING(i, 1)). }
}
LOCAL ks IS keys_new().
type_keys(ks, "V16N60E").
assert_true("V16 N60 ENTR sets verb",  ks["VERB"] = 16).
assert_true("V16 N60 ENTR sets noun",  ks["NOUN"] = 60).
assert_true("V16 N60 ENTR no error",   NOT ks["OPRERR"]).
type_keys(ks, "V99E").
assert_true("V99 ENTR lights OPR ERR", ks["OPRERR"]).
assert_true("V99 ENTR keeps old verb", ks["VERB"] = 16).
type_keys(ks, "R").
assert_true("RSET clears OPR ERR",     NOT ks["OPRERR"]).
type_keys(ks, "N99E").
assert_true("N99 ENTR lights OPR ERR", ks["OPRERR"]).
assert_true("N99 ENTR keeps old noun", ks["NOUN"] = 60).

report("TESTS: " + TESTS_PASSED + " passed, " + TESTS_FAILED + " failed").
