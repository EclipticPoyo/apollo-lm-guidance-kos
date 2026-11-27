// test_ascent_plan.ks -- pad test for the ascent planner (lm/planner/lm_ascent_plan.ks): phasing, the lift-off search and the ascent PAD.
// No flight and no vessel reads: a made-up Moon spin, a site on its equator and a circular CSM given as a delegate. The CSM plane is the X-Y plane,
// the CSM moving from +X towards +Y, and the spin is chosen so the site moves the same way. Numbers from scripts/tests/reference_ascent.py.
//   RUNPATH("0:/tests/test_ascent_plan.ks").   Log: 0:/lm/logs/test_ascent_plan.log.
// It takes a few minutes (each solve simulates the ascent).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/planner/lm_ascent_plan.ks").

test_begin("0:/lm/logs/test_ascent_plan.log").
LOCAL tap_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.

GLOBAL TAP_MU IS 4.9028e12.
GLOBAL TAP_SITE_R IS 1735750.
GLOBAL TAP_NM IS 1852.
GLOBAL TAP_WM IS V(0, 0, -2.6617e-6).          // through lm_cross this moves a point on +X towards +Y
GLOBAL TAP_T0 IS 5000.

// tap_csm_at: the CSM (circular, radius r_csm, at angle a0_deg at TAP_T0) at UT t_ut, in the axes of TAP_T0.
FUNCTION tap_csm_at {
  PARAMETER r_csm, a0_deg, t_ut.
  LOCAL ang IS a0_deg + SQRT(TAP_MU / r_csm ^ 3) * (t_ut - TAP_T0) * CONSTANT:RADTODEG.
  RETURN V(r_csm * COS(ang), r_csm * SIN(ang), 0).
}
// tap_input: the solver's input for a profile, a site latitude (degrees out of the CSM plane) and a CSM apolune and perilune in nm above the site radius.
FUNCTION tap_input {
  PARAMETER profile, lat_deg, apo_nm, peri_nm.
  LOCAL r_csm IS TAP_SITE_R + (apo_nm + peri_nm) / 2 * TAP_NM.
  LOCAL speed IS SQRT(TAP_MU / r_csm).
  LOCAL at_d IS tap_csm_at@:BIND(r_csm, 40).
  RETURN LEXICON("PROFILE", profile, "SITE", V(COS(lat_deg), 0, SIN(lat_deg)) * TAP_SITE_R, "WM", TAP_WM, "T0", TAP_T0, "MU", TAP_MU,
                 "CSM_AT", at_d, "CSM_R", V(r_csm * COS(40), r_csm * SIN(40), 0), "CSM_V", V(-speed * SIN(40), speed * COS(40), 0),
                 "CSM_APO_R", TAP_SITE_R + apo_nm * TAP_NM, "CSM_PE_R", TAP_SITE_R + peri_nm * TAP_NM,
                 "MASS_KG", 4915.6, "THRUST_N", 15569, "VE", 15569 / 5.135, "PROP_KG", 2500).
}
// tap_warned: is there a warning containing word_text?
FUNCTION tap_warned {
  PARAMETER res, word_text.
  FOR warn_text IN res["WARN"] { IF warn_text:CONTAINS(word_text) { RETURN TRUE. } }
  RETURN FALSE.
}

// ---- Kepler and phase angles ----
LOCAL tap_rins IS TAP_SITE_R + ASC_HINJECT_M.
LOCAL tap_kep IS asc_kepler_polar(tap_rins, 1686.6141, ASC_PHASE_RDOT, TAP_MU, 3000).
assert_near("kepler radius", tap_kep["R"], 1819054.52, 20).
assert_near("kepler angle", tap_kep["ANG"], 158.92120, 0.001).
assert_near("phase angles A11", asc_phase_angle("A11", TAP_SITE_R, TAP_SITE_R + 60 * TAP_NM, TAP_MU), 15.8695, 0.01).
assert_near("phase angles J", asc_phase_angle("J", TAP_SITE_R, TAP_SITE_R + 60 * TAP_NM, TAP_MU), 8.5828, 0.01).
assert_near("phase scales with height: A11 50 nm", asc_phase_angle("A11", TAP_SITE_R, TAP_SITE_R + 50 * TAP_NM, TAP_MU), 14.8217, 0.01).
assert_near("phase scales with height: A11 70 nm", asc_phase_angle("A11", TAP_SITE_R, TAP_SITE_R + 70 * TAP_NM, TAP_MU), 17.0476, 0.01).
assert_near("phase scales with height: J 50 nm", asc_phase_angle("J", TAP_SITE_R, TAP_SITE_R + 50 * TAP_NM, TAP_MU), 7.1985, 0.01).
assert_near("phase scales with height: J 70 nm", asc_phase_angle("J", TAP_SITE_R, TAP_SITE_R + 70 * TAP_NM, TAP_MU), 9.9759, 0.01).

// ---- Time to apolune and the coelliptic phase (the PAD's rendezvous times) ----
// tap_to_apo: the time to apolune of the planned insertion state, apo_below under a 60 nm CSM.
FUNCTION tap_to_apo {
  PARAMETER apo_below.
  LOCAL r_ins IS TAP_SITE_R + ASC_HINJECT_M.
  RETURN asc_time_to_apo(r_ins, asc_insertion_vh(r_ins, TAP_SITE_R + 60 * TAP_NM - apo_below, TAP_MU, ASC_PHASE_RDOT), ASC_PHASE_RDOT, TAP_MU).
}
assert_near("time to apolune A11", tap_to_apo(ASC_APO_BELOW_A11_M), 3050.6, 1).
assert_near("time to apolune J", tap_to_apo(ASC_APO_BELOW_J_M), 3062.3, 1).
assert_near("no apolune: a circle", asc_time_to_apo(tap_rins, SQRT(TAP_MU / tap_rins), 0, TAP_MU), -1, 0).
assert_near("no apolune: an escape", asc_time_to_apo(tap_rins, 3000, 0, TAP_MU), -1, 0).
assert_near("coelliptic phase J fallback", asc_phase_coelliptic("J", TAP_SITE_R, TAP_SITE_R + 60 * TAP_NM, TAP_MU, ASC_J_FB_CSI_TO_TPI_S), 16.035, 0.01).

// ---- The lift-off search itself, on a made-up error that rises through zero at 1234 s ----
FUNCTION tap_ramp { PARAMETER t_ut. RETURN MOD((t_ut - 1234) * 0.1 + 540, 360) - 180. }
assert_near("find lift-off: the rising crossing", asc_find_liftoff(tap_ramp@, 0, 3000, 60), 1234, 0.01).
assert_near("find lift-off: none in the span", asc_find_liftoff(tap_ramp@, 1300, 600, 20), -1, 0).

// ---- The solve ----
LOCAL tap_in IS tap_input("A11", 0, 60, 60).
LOCAL tap_res IS asc_plan_solve(tap_in).
assert_true("liftoff solve: ok", tap_res["OK"]).
assert_true("liftoff solve: at least 10 minutes ahead", tap_res["T1"] >= TAP_T0 + ASC_LEAD_S).
LOCAL tap_n IS VCRS(tap_in["CSM_R"], tap_in["CSM_V"]):NORMALIZED.
LOCAL tap_r0 IS plan_site_at(tap_in["SITE"], TAP_WM, tap_res["T1"] - TAP_T0).
LOCAL tap_tgt IS asc_target(tap_rins, 0, tap_res["RDOTD"], tap_res["ZDOTD"]).
LOCAL tap_sim IS asc_sim("A11", tap_r0, lm_cross(TAP_WM, tap_r0), asc_qaxis(tap_in["CSM_R"], tap_in["CSM_V"]), TAP_MU, tap_tgt, 4915.6, 15569, 15569 / 5.135, ASC_SIM_DT).
LOCAL tap_lead IS plan_phase(tap_csm_at(TAP_SITE_R + 60 * TAP_NM, 40, tap_res["T1"] + tap_sim["BURN_S"]), tap_n, plan_in_plane(tap_sim["R_END"]:NORMALIZED, tap_n)).
assert_near("liftoff solve: the CSM is the phase angle ahead at insertion", tap_lead, tap_res["PHASE"], 0.02).
assert_near("liftoff solve: the phase angle", tap_res["PHASE"], 15.8695, 0.01).
assert_near("liftoff solve: ZDOTD for a 45 nm apolune", tap_res["ZDOTD"], 1686.6141, 0.1).
assert_near("liftoff solve: RDOTD", tap_res["RDOTD"], ASC_PHASE_RDOT, 0.001).
assert_near("liftoff solve: burn time", tap_res["BURN_S"], tap_sim["BURN_S"], 1).
LOCAL tap_synodic IS 2 * CONSTANT:PI / (SQRT(TAP_MU / (TAP_SITE_R + 60 * TAP_NM) ^ 3) - TAP_WM:MAG).
assert_near("liftoff solve: the next one a synodic period later", tap_res["T2"] - tap_res["T1"], tap_synodic, 0.02 * tap_synodic).
LOCAL tap_over IS plan_phase(tap_csm_at(TAP_SITE_R + 60 * TAP_NM, 40, tap_res["T_OVER"]), tap_n,
                             plan_in_plane(plan_site_at(tap_in["SITE"], TAP_WM, tap_res["T_OVER"] - TAP_T0):NORMALIZED, tap_n)).
assert_near("liftoff solve: overhead pass", tap_over, 0, 0.05).
assert_true("liftoff solve: the overhead pass is the one nearest lift-off", ABS(tap_res["T_OVER"] - tap_res["T1"]) < tap_synodic / 2 + 1).
assert_near("in plane: no cross-range", tap_res["XRANGE"], 0, 1).
assert_near("in plane: nothing left over", tap_res["LEFT_M"], 0, 0.5).
assert_near("60 nm: no warnings", tap_res["WARN"]:LENGTH, 0, 0).
assert_near("A11 times: CSI at the planned apolune", tap_res["T_CSI"] - tap_res["T1"] - tap_res["BURN_S"], 3050.6, 2).
assert_near("A11 times: TPI", tap_res["T_TPI"] - tap_res["T1"] - tap_res["BURN_S"], 8940, 0.1).
assert_true("A11 times: no fallback", NOT tap_res["FB"]:ISTYPE("Lexicon")).

// ---- Cross-range ----
SET tap_res TO asc_plan_solve(tap_input("A11", 1, 60, 60)).
LOCAL tap_y IS tap_rins * SIN(1).
assert_true("crossrange limited: ok", tap_res["OK"]).
assert_near("crossrange limited: XRANGE is 8 nm towards the plane", tap_res["XRANGE"], -ASC_XRANGE_PAD_M, 1).
assert_near("crossrange limited: left over", tap_res["LEFT_M"], tap_y - ASC_XRANGE_PAD_M, 50).
assert_true("crossrange limited: one warning", tap_res["WARN"]:LENGTH = 1 AND tap_warned(tap_res, "cross-range")).
SET tap_res TO asc_plan_solve(tap_input("J", -0.2, 60, 60)).
assert_near("small crossrange: XRANGE = -Y", tap_res["XRANGE"], tap_rins * SIN(0.2), 20).
assert_near("small crossrange: nothing left over", tap_res["LEFT_M"], 0, 0.5).
assert_near("J solve: the phase angle", tap_res["PHASE"], 8.5828, 0.01).
assert_near("J times: no CSI in the direct set", tap_res["T_CSI"], -1, 0).
assert_near("J times: TPI", tap_res["T_TPI"] - tap_res["T1"] - tap_res["BURN_S"], 2700, 0.1).
assert_true("J fallback: found", tap_res["FB"]:ISTYPE("Lexicon")).
IF tap_res["FB"]:ISTYPE("Lexicon") {
  LOCAL tap_fb IS tap_res["FB"].
  assert_near("J fallback: lift-off 120 to 180 s after the direct one", tap_fb["T1"] - tap_res["T1"], 150, 30).
  assert_near("J fallback: CSI at the planned apolune", tap_fb["T_CSI"] - tap_fb["T1"] - tap_res["BURN_S"], 3062.3, 2).
  assert_near("J fallback: TPI", tap_fb["T_TPI"] - tap_fb["T1"] - tap_res["BURN_S"], 9712, 0.1).
}

// ---- Warnings ----
SET tap_res TO asc_plan_solve(tap_input("A11", 0, 45, 45)).
assert_true("warnings: CSM 45 nm", tap_res["OK"] AND tap_warned(tap_res, "outside")).
SET tap_res TO asc_plan_solve(tap_input("A11", 0, 75, 60)).
assert_true("warnings: 75 by 60 nm", tap_res["OK"] AND tap_warned(tap_res, "apart")).
LOCAL tap_low_prop IS tap_input("A11", 0, 60, 60).
SET tap_low_prop["PROP_KG"] TO 500.
SET tap_res TO asc_plan_solve(tap_low_prop).
assert_true("warnings: propellant", tap_res["OK"] AND tap_warned(tap_res, "propellant")).

// ---- Unreachable ----
LOCAL tap_weak IS tap_input("A11", 0, 60, 60).
SET tap_weak["THRUST_N"] TO 5000.
SET tap_res TO asc_plan_solve(tap_weak).
assert_true("unreachable: too little thrust is refused with a reason", NOT tap_res["OK"] AND tap_res["WHY"] <> "").
SET tap_res TO asc_plan_solve(tap_input("A11", 90, 60, 60)).
assert_true("unreachable: a site on the orbit pole is refused with a reason", NOT tap_res["OK"] AND tap_res["WHY"] <> "").
SET tap_res TO asc_plan_solve(tap_input("A11", 0, 20, 20)).
assert_true("unreachable: a CSM too low is refused with a reason", NOT tap_res["OK"] AND tap_res["WHY"] <> "").

// ---- The PAD ----
LOCAL tap_fixed IS LEXICON("OK", TRUE, "WHY", "", "T1", 12345.67, "T2", 19489.5, "T_OVER", 12266.0, "ZDOTD", 5533.9 * 0.3048, "RDOTD", 32.2 * 0.3048,
                           "XRANGE", -1.7 * 1852, "LEFT_M", 0, "BURN_S", 434, "PHASE", 15.87, "WARN", LIST(),
                           "T_CSI", 15830.25, "T_TPI", 21770.5, "FB", FALSE).
LOCAL tap_info IS LEXICON("CSM", "Columbia", "APO_NM", 60.2, "PERI_NM", 59.8, "PROFILE", "A11", "CLOCK_ZERO", 1000).
// tap_has: is there a PAD line containing text?
FUNCTION tap_has {
  PARAMETER lines, text.
  FOR line_text IN lines { IF line_text:CONTAINS(text) { RETURN TRUE. } }
  RETURN FALSE.
}
// tap_find: the number of the first PAD line from start on that contains text, or -1.
FUNCTION tap_find {
  PARAMETER lines, text, start.
  FROM { LOCAL i IS MAX(0, start). } UNTIL i >= lines:LENGTH STEP { SET i TO i + 1. } DO {
    IF lines[i]:CONTAINS(text) { RETURN i. }
  }
  RETURN -1.
}
// tap_count: how many PAD lines contain text.
FUNCTION tap_count {
  PARAMETER lines, text.
  LOCAL n IS 0.
  FOR line_text IN lines { IF line_text:CONTAINS(text) { SET n TO n + 1. } }
  RETURN n.
}
LOCAL tap_lines IS asc_pad_lines(tap_fixed, tap_info).
LOCAL tap_hms IS lm_hms_cs(12345.67 - 1000).
assert_true("pad lines: the N33 keys", tap_has(tap_lines, "V25 N33 E " + pad_signed5(tap_hms[0]) + " E " + pad_signed5(tap_hms[1]) + " E " + pad_signed5(tap_hms[2]) + " E")).
assert_true("pad lines: the N76 keys", tap_has(tap_lines, "V25 N76 E +55339 E +00322 E -00017 E")).
assert_true("pad lines: the CSM and its orbit", tap_has(tap_lines, "Columbia") AND tap_has(tap_lines, "60.2 x 59.8 nm")).
assert_true("pad lines: the version", tap_has(tap_lines, "LUMINARY099")).
assert_true("pad lines: the overhead pass", tap_has(tap_lines, "OVERHEAD") AND tap_has(tap_lines, pad_clock_text(12266.0 - 1000))).
assert_true("pad lines: the next lift-off", tap_has(tap_lines, "NEXT") AND tap_has(tap_lines, pad_clock_text(19489.5 - 1000))).
assert_true("pad lines: nothing left over, no line", NOT tap_has(tap_lines, "LEFT OVER")).
assert_true("pad lines: no warnings", NOT tap_has(tap_lines, "WARNING")).
assert_true("pad lines A11: the N11 keys", tap_has(tap_lines, "V25 N11 E +00004 E +00007 E +01025 E")).
assert_true("pad lines A11: the N37 keys", tap_has(tap_lines, "V25 N37 E +00005 E +00046 E +01050 E")).
assert_true("pad lines A11: the CSI and TPI times", tap_has(tap_lines, "CSI  " + pad_clock_text(15830.25 - 1000)) AND tap_has(tap_lines, "TPI  " + pad_clock_text(21770.5 - 1000))).
assert_true("pad lines A11: no fallback", NOT tap_has(tap_lines, "FALLBACK")).
SET tap_fixed["LEFT_M"] TO 2.5 * 1852.
SET tap_fixed["WARN"] TO LIST("first thing", "second thing").
SET tap_info["PROFILE"] TO "J".
SET tap_lines TO asc_pad_lines(tap_fixed, tap_info).
assert_true("pad lines: the left over", tap_has(tap_lines, "LEFT OVER") AND tap_has(tap_lines, "2.5 nm")).
assert_true("pad lines: each warning", tap_has(tap_lines, "WARNING: first thing") AND tap_has(tap_lines, "WARNING: second thing")).
assert_true("pad lines: the J version", tap_has(tap_lines, "LUMINARY210")).
assert_true("pad lines J, no fallback found: no fallback block", NOT tap_has(tap_lines, "FALLBACK")).
SET tap_fixed["T_CSI"] TO -1.
SET tap_fixed["T_TPI"] TO 15479.67.
SET tap_fixed["FB"] TO LEXICON("T1", 12493.5, "T_CSI", 18000.12, "T_TPI", 24712.34).
SET tap_lines TO asc_pad_lines(tap_fixed, tap_info).
LOCAL tap_fb_at IS tap_find(tap_lines, "FALLBACK", 0).
assert_true("pad lines J: the fallback block", tap_fb_at >= 0).
LOCAL tap_direct_at IS tap_find(tap_lines, "V25 N37 E +00004 E +00001 E +01967 E", 0).
assert_true("pad lines J: the direct TPI before the fallback", tap_direct_at >= 0 AND tap_direct_at < tap_fb_at).
assert_true("pad lines J: no direct CSI", tap_find(tap_lines, "V25 N11 E", 0) > tap_fb_at).
assert_near("pad lines J: two N37 lines", tap_count(tap_lines, "V25 N37 E"), 2, 0).
LOCAL tap_n33_at IS tap_find(tap_lines, "V25 N33 E +00003 E +00011 E +03350 E", tap_fb_at).
LOCAL tap_n11_at IS tap_find(tap_lines, "V25 N11 E +00004 E +00043 E +02012 E", tap_fb_at).
LOCAL tap_n37_at IS tap_find(tap_lines, "V25 N37 E +00006 E +00035 E +01234 E", tap_fb_at).
assert_true("pad lines J: the fallback keys, N33 then N11 then N37", tap_n33_at > tap_fb_at AND tap_n11_at > tap_n33_at AND tap_n37_at > tap_n11_at).

// ---- When the planner refuses ----
assert_true("run refuses: in orbit", asc_plan_refusal("ORBITING", TRUE, BODY_NAME, TRUE) <> "").
assert_true("run refuses: no target", asc_plan_refusal("LANDED", FALSE, "", TRUE):CONTAINS("target")).
assert_true("run refuses: a target around Kerbin", asc_plan_refusal("LANDED", TRUE, "Kerbin", TRUE):CONTAINS("Kerbin") = FALSE AND asc_plan_refusal("LANDED", TRUE, "Kerbin", TRUE) <> "").
assert_true("run refuses: no ascent engine", asc_plan_refusal("LANDED", TRUE, BODY_NAME, FALSE):CONTAINS("engine")).
assert_true("run refuses: nothing when all is good", asc_plan_refusal("LANDED", TRUE, BODY_NAME, TRUE) = "").

// ---- The aborts' check of the CSM (deorbit planner): where it is at PDI against where a DOI flown beside it puts it ----
GLOBAL TAP_R60 IS TAP_SITE_R + 60 * TAP_NM.
GLOBAL TAP_PDI_R IS TAP_SITE_R + 15240.          // 50 000 ft
// tap_amber: how many lines of a check are warnings; tap_says: is there a warning containing text?
FUNCTION tap_amber {
  PARAMETER checks.
  LOCAL n IS 0.
  FOR one_check IN checks { IF one_check["WARN"] { SET n TO n + 1. } }
  RETURN n.
}
FUNCTION tap_says {
  PARAMETER checks, text.
  FOR one_check IN checks { IF one_check["WARN"] AND one_check["TEXT"]:CONTAINS(text) { RETURN TRUE. } }
  RETURN FALSE.
}
assert_near("CSM check: expected lead for a 60 nmi CSM", abt_expected_lead(TAP_R60, TAP_PDI_R), -6.96, 0.05).
LOCAL tap_c1 IS abt_plan_check("A11", -7, TAP_SITE_R, TAP_R60, TAP_R60, TAP_PDI_R, TAP_MU).
assert_true("CSM check A11 in place: the lead, no warning", tap_c1:LENGTH = 1 AND tap_amber(tap_c1) = 0 AND tap_c1[0]["TEXT"]:CONTAINS("behind")).
assert_true("CSM check A11 4 degrees off: a warning about the timing", tap_says(abt_plan_check("A11", -11, TAP_SITE_R, TAP_R60, TAP_R60, TAP_PDI_R, TAP_MU), "timing")).
assert_true("CSM check J 9 degrees off: no warning", tap_amber(abt_plan_check("J", -16, TAP_SITE_R, TAP_R60, TAP_R60, TAP_PDI_R, TAP_MU)) = 0).
assert_true("CSM check J 13 degrees off: the apolune an abort would target", tap_says(abt_plan_check("J", -20, TAP_SITE_R, TAP_R60, TAP_R60, TAP_PDI_R, TAP_MU), "177 nm")).
LOCAL tap_r40 IS TAP_SITE_R + 40 * TAP_NM.
assert_true("CSM check: a 40 nmi CSM adds the orbit warning", tap_says(abt_plan_check("A11", abt_expected_lead(tap_r40, TAP_PDI_R), TAP_SITE_R, tap_r40, tap_r40, TAP_PDI_R, TAP_MU), "outside")).
assert_true("CSM orbit warnings: none for 60 nmi", asc_csm_orbit_warnings(TAP_SITE_R, TAP_R60, TAP_R60):LENGTH = 0).

SET CONFIG:IPU TO tap_ipu.
test_end().
