// test_plan.ks -- pad tests for the deorbit planner (run in the kOS terminal, no flight needed).
//   RUNPATH("0:/tests/test_plan.ks").
// Expected values come from scripts/tests/reference.py. Results go to 0:/lm/logs/test_plan.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/planner/lm_site.ks").
RUNONCEPATH("0:/lm/planner/lm_plan.ks").
RUNONCEPATH("0:/shared/lm_checks.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_plan.log").

// ---- Task 1: constants and site input ------------------------------------
assert_near("site_wrap_lng(190)",     site_wrap_lng(190),     -170,   1e-9).
assert_near("site_wrap_lng(-190)",    site_wrap_lng(-190),    170,    1e-9).
assert_near("site_wrap_lng(180)",     site_wrap_lng(180),     -180,   1e-9).
assert_near("site_wrap_lng(23.47)",   site_wrap_lng(23.47),   23.47,  1e-9).
assert_near("site_wrap_lng(720.5)",   site_wrap_lng(720.5),   0.5,    1e-9).

LOCAL chk_a IS site_check(91, 0).
assert_true("site_check lat 91 invalid",    NOT chk_a["VALID"] AND chk_a["WHY"]:LENGTH > 0).
assert_true("site_check lat -90.5 invalid", NOT site_check(-90.5, 0)["VALID"]).
assert_true("site_check normal valid",      site_check(0.67, 23.47)["VALID"]).
assert_true("site_check lng 400 invalid",   NOT site_check(0, 400)["VALID"]).
assert_true("site_check swapped-but-legal valid", site_check(23.47, 0.67)["VALID"]).

assert_true("RIGNX negative", RIGNX < 0).
assert_true("RIGNZ negative", RIGNZ < 0).
assert_near("VIGN", VIGN, 1690.256208, 1e-6).

// ---- Task 3: planner geometry ---------------------------------------------
// Expected values from scripts/tests/reference.py ("Task 3" section), 1e-6 relative.
LOCAL geo IS plan_pdi_geometry(1737400, RIGNX, RIGNZ, 1737100).
assert_near("pdi R_PDI",   geo["R_PDI"],   1752875.7792720972, 1.753).
assert_near("pdi PHI",     geo["PHI"],     14.424743871061887, 1.5e-5).
assert_near("pdi ALT_PDI", geo["ALT_PDI"], 15775.779272097163, 0.0158).
assert_true("pdi PHI positive although RIGNZ negative", geo["PHI"] > 0).

// ---- Release 1.2: pad-load profiles (Apollo 17 values, expected from the same formulas in Python, same site and body radii) ----
LOCAL pv_a IS plan_pdi_values("A11").
LOCAL pv_j IS plan_pdi_values("J").
assert_near("profile A11 RIGNX", pv_a["RIGNX"], RIGNX, 1e-9).
assert_near("profile A11 VIGN", pv_a["VIGN"], 1690.256208, 1e-6).
assert_near("profile J RIGNX", pv_j["RIGNX"], -47593.00514, 1e-6).
assert_near("profile J RIGNZ", pv_j["RIGNZ"], -469983.8606, 1e-6).
assert_near("profile J VIGN", pv_j["VIGN"], 1689.475188, 1e-6).
assert_near("profile unknown name is A11", plan_pdi_values("X")["VIGN"], 1690.256208, 1e-6).
LOCAL geo_j IS plan_pdi_geometry(1737400, pv_j["RIGNX"], pv_j["RIGNZ"], 1737100).
assert_near("pdi J R_PDI",   geo_j["R_PDI"],   1753947.6928067908, 1.754).
assert_near("pdi J PHI",     geo_j["PHI"],     15.542776577296411, 1.6e-5).
assert_near("pdi J ALT_PDI", geo_j["ALT_PDI"], 16847.692806790816, 0.017).
assert_true("plan_profile_of: J plan", plan_profile_of(LEXICON("PROFILE", "J")) = "J").
assert_true("plan_profile_of: A11 plan", plan_profile_of(LEXICON("PROFILE", "A11")) = "A11").
assert_true("plan_profile_of: plan without the key (made before 1.2)", plan_profile_of(LEXICON("T_PDI", 1)) = "A11").
assert_true("plan_profile_of: unknown value", plan_profile_of(LEXICON("PROFILE", "Z")) = "A11").
assert_true("plan_profile_of: no plan", plan_profile_of(FALSE) = "A11").
assert_true("the default profile is A11", PAD_PROFILE = "A11").

LOCAL wm_t IS V(0, 1e-5, 0).
LOCAL rot_a IS V(1737000, 0, 0).
assert_vec("spin rotate 1 rad",  plan_spin_rotate(rot_a, wm_t, 1e5),  V(938505.1052929588, 0, 1461635.100611316),  1.8).
assert_vec("spin rotate -1 rad", plan_spin_rotate(rot_a, wm_t, -1e5), V(938505.1052929588, 0, -1461635.100611316), 1.8).
assert_near("spin rotate keeps length", plan_spin_rotate(rot_a, wm_t, 1e5):MAG, 1737000, 1e-6).
assert_vec("spin rotate dt 0",   plan_spin_rotate(rot_a, wm_t, 0),    rot_a, 0).
assert_vec("spin rotate no spin", plan_spin_rotate(rot_a, V(0, 0, 0), 1e5), rot_a, 0).

LOCAL tn_a IS plan_target_normal(V(0, 1, 0), V(0.6, 0.8, 0)).
assert_true("target normal OK",     tn_a["OK"]).
assert_vec("target normal N_T",     tn_a["N_T"], V(-0.8, 0.6, 0), 1e-6).
assert_near("target normal TILT",   tn_a["TILT"], 53.13010235415599, 1e-4).
assert_near("target normal N_T . site = 0", VDOT(tn_a["N_T"], V(0.6, 0.8, 0)), 0, 1e-9).
assert_near("target normal length", tn_a["N_T"]:MAG, 1, 1e-9).
LOCAL tn_b IS plan_target_normal(V(0, 1, 0), V(1, 0.01, 0):NORMALIZED).
assert_vec("target normal small tilt N_T", tn_b["N_T"], V(-0.009999500037496877, 0.9999500037496875, 0), 1e-9).
assert_near("target normal small tilt",    tn_b["TILT"], 0.572938697683486, 1e-6).
LOCAL tn_c IS plan_target_normal(V(0, 1, 0), V(1, 0, 0)).
assert_near("target normal in-plane tilt 0", tn_c["TILT"], 0, 1e-9).
assert_vec("target normal in-plane N_T = n_cur", tn_c["N_T"], V(0, 1, 0), 1e-9).
// Review focus 1: the site on the orbit's pole direction has no unique plane.
LOCAL tn_d IS plan_target_normal(V(0, 1, 0), V(0, 1, 0)).
assert_true("target normal at pole: OK false", NOT tn_d["OK"]).
assert_true("target normal at pole: no NaN",   tn_d["N_T"]:MAG > 0.5 AND tn_d["N_T"]:MAG < 1.5).

assert_vec("point ahead 90",  plan_point_ahead(V(0, 1, 0), V(1, 0, 0), 90),  V(0, 0, -1), 1e-9).
assert_vec("point ahead -90", plan_point_ahead(V(0, 1, 0), V(1, 0, 0), -90), V(0, 0, 1),  1e-9).
assert_vec("point ahead 0",   plan_point_ahead(V(0, 1, 0), V(1, 0, 0), 0),   V(1, 0, 0),  1e-9).
assert_vec("point ahead 360", plan_point_ahead(V(0, 1, 0), V(1, 0, 0), 360), V(1, 0, 0),  1e-9).

LOCAL ip_vec IS plan_in_plane(V(1, 0.3, 0.2):NORMALIZED, V(0, 1, 0)).
assert_near("in_plane perpendicular to normal", VDOT(ip_vec, V(0, 1, 0)), 0, 1e-9).
assert_near("in_plane unit length", ip_vec:MAG, 1, 1e-9).

// ---- Task 4: burns and node components ------------------------------------
// Values from reference.py ("Task 4"): 110 km circular orbit, mu = 4.9028e12, PDI radius 1752.5 km.
LOCAL mu_t IS 4.9028e12.
LOCAL r_circ IS V(1847100, 0, 0).
LOCAL v_circ IS V(0, 0, 1629.20931521997).
LOCAL n_circ IS V(0, -1, 0).                    // = unit(VCRS(r, v))

LOCAL doi_a IS plan_doi(r_circ, v_circ, n_circ, 1752500, mu_t).
assert_true("doi circular OK", doi_a["OK"]).
assert_vec("doi circular DV",   doi_a["DV"], V(0, 0, -21.550914870151246), 2.2e-5).
assert_near("doi circular |DV| is the spec 21.6 within 0.1", doi_a["DV"]:MAG, 21.6, 0.1).
assert_true("doi circular is retrograde", VDOT(doi_a["DV"], v_circ) < 0).
assert_near("doi circular V_APO", doi_a["V_APO"], 1607.6584003498187, 1.7e-3).
assert_near("doi circular V_PDI", doi_a["V_PDI"], 1694.439846668274,  1.7e-3).
assert_near("doi circular T_HALF", doi_a["T_HALF"], 3425.816961012604, 3.5e-3).

LOCAL v_ell IS V(30, 0, 1600).                  // radial speed 30 m/s: the burn must remove it
LOCAL doi_b IS plan_doi(r_circ, v_ell, VCRS(r_circ, v_ell):NORMALIZED, 1752500, mu_t).
assert_vec("doi elliptic DV includes radial part", doi_b["DV"], V(-30, 0, 7.6584003498187485), 1e-5).
// Review focus 3: orbit lower than the PDI radius has no descent orbit; exactly at it is a circular one.
assert_true("doi 10 km orbit refused", NOT plan_doi(V(1747100, 0, 0), V(0, 0, 1650), n_circ, 1752500, mu_t)["OK"]).
LOCAL doi_c IS plan_doi(V(1752500, 0, 0), V(0, 0, 1650), n_circ, 1752500, mu_t).
assert_true("doi at PDI radius OK", doi_c["OK"]).
assert_vec("doi at PDI radius finite DV", doi_c["DV"], V(0, 0, 22.603785623019576), 2.3e-5).

// Plane change of +2 and -2 degrees at the line of nodes (r along +X).
LOCAL ntgt_a IS V(0, -0.9993908270190958, -0.03489949670250097).
LOCAL ntgt_b IS V(0, -0.9993908270190958, 0.03489949670250097).
LOCAL pc_a IS plan_plane_change(r_circ, v_circ, n_circ, ntgt_a).
LOCAL pc_b IS plan_plane_change(r_circ, v_circ, n_circ, ntgt_b).
assert_vec("plane change +2 deg", pc_a, V(0, -56.8585851242017, -0.9924702950695519), 6e-5).
assert_vec("plane change -2 deg", pc_b, V(0, 56.8585851242017, -0.9924702950695519),  6e-5).
assert_near("plane change |dv| = 2 vc sin(1 deg)", pc_a:MAG, 56.86724628125303, 6e-5).
assert_vec("plane change result normal is n_tgt", VCRS(r_circ, v_circ + pc_a):NORMALIZED, ntgt_a, 1e-9).
assert_vec("plane change (-) result normal is n_tgt", VCRS(r_circ, v_circ + pc_b):NORMALIZED, ntgt_b, 1e-9).
assert_near("plane change keeps speed", (v_circ + pc_a):MAG, v_circ:MAG, 1e-9).
assert_vec("plane change zero tilt", plan_plane_change(r_circ, v_circ, n_circ, n_circ), V(0, 0, 0), 0).

// plan_rotate_about (double-precision rotation used by the plane change): 90 degrees about +Y turns +X to -Z
// (the VCRS direction), -90 gives +Z, the length is kept, and 0 degrees is the identity.
assert_vec("rotate_about +90", plan_rotate_about(V(1, 0, 0), V(0, 1, 0), 90), V(0, 0, -1), 1e-12).
assert_vec("rotate_about -90", plan_rotate_about(V(1, 0, 0), V(0, 1, 0), -90), V(0, 0, 1), 1e-12).
assert_vec("rotate_about 0",   plan_rotate_about(V(3, 4, 5), V(0, 1, 0), 0), V(3, 4, 5), 1e-12).
assert_near("rotate_about keeps length", plan_rotate_about(V(3, 4, 5), V(1, 0, 0), 37):MAG, V(3, 4, 5):MAG, 1e-12).

// Node components. The round trip works for any sign constants; the pure-prograde case holds too.
LOCAL dv_t IS V(3, -2, 5).
LOCAL comp_a IS plan_node_components(dv_t, r_circ, v_ell).
assert_vec("node components round trip",
  plan_components_to_dv(comp_a["RADIAL"], comp_a["NORMAL"], comp_a["PROGRADE"], r_circ, v_ell), dv_t, 1e-9).
assert_near("node components PROGRADE", comp_a["PROGRADE"], 5.055361440336018, 1e-6).
assert_near("node components |NORMAL|", ABS(comp_a["NORMAL"]), 2, 1e-6).
assert_near("node components |RADIAL|", ABS(comp_a["RADIAL"]), 2.9057392704032736, 1e-6).
LOCAL comp_b IS plan_node_components(v_ell:NORMALIZED * 5, r_circ, v_ell).
assert_vec("node components pure prograde", V(comp_b["RADIAL"], comp_b["NORMAL"], comp_b["PROGRADE"]), V(0, 0, 5), 1e-9).

// ---- Task 5: crossing-time search -----------------------------------------
// A fake circular orbit: radius 1.8e6 m, period 7000 s, starting along +X. fake_pos is turned into a
// delegate with the @ suffix, like the real search gets from lm_deorbit.ks.
GLOBAL fake_n IS V(0, 1, 0).
FUNCTION fake_pos {
  PARAMETER t.
  LOCAL ang IS 360 * t / 7000.
  RETURN (V(1, 0, 0) * COS(ang) + VCRS(fake_n, V(1, 0, 0)):NORMALIZED * SIN(ang)) * 1.8e6.
}
LOCAL pos_d IS fake_pos@.
LOCAL ref_90 IS plan_point_ahead(fake_n, V(1, 0, 0), 90).

assert_near("phase quarter behind", plan_phase(V(1, 0, 0) * 1e6, fake_n, plan_point_ahead(fake_n, V(1, 0, 0), 90)), -90, 1e-9).
assert_near("phase quarter ahead",  plan_phase(V(1, 0, 0) * 1e6, fake_n, plan_point_ahead(fake_n, V(1, 0, 0), -90)), 90, 1e-9).
assert_near("phase at reference",   plan_phase(V(1, 0, 0) * 1e6, fake_n, V(1, 0, 0)), 0, 1e-9).

assert_near("find_pass quarter orbit", plan_find_pass(pos_d, fake_n, ref_90, 0, 7000), 1750, 1e-3).
assert_near("find_pass next orbit",    plan_find_pass(pos_d, fake_n, ref_90, 2000, 7000), 8750, 1e-3).
LOCAL under IS plan_find_pass(pos_d, fake_n, V(1, 0, 0), 0, 7500).
assert_true("find_pass reference under the ship", under >= 0 AND (under < 1e-3 OR ABS(under - 7000) < 1e-3)).
assert_near("find_pass none in 1000 s", plan_find_pass(pos_d, fake_n, ref_90, 0, 1000), -1, 0).
SET fake_n TO V(0, -1, 0).
assert_near("find_pass retrograde orbit", plan_find_pass(pos_d, fake_n, plan_point_ahead(fake_n, V(1, 0, 0), 90), 0, 7000), 1750, 1e-3).

// ---- Task 6: sanity checks, post-check, plan file --------------------------
LOCAL NO_TERRAIN IS -999999.                    // "terrain not measured"
FUNCTION good_pre {
  RETURN LEXICON("LEAD_S", 900, "DV_DOI", 21.6, "DV_PC", 0, "MAX_PC_DV", 200, "ALT_PDI", 15800, "ALT_PDI_NOM", 15776,
                 "V_PDI", 1694, "WARP_RATE", 1, "NODES_OK", TRUE, "TERRAIN_CLEAR_MIN", 8000).
}
FUNCTION count_text {
  PARAMETER text_list, fragment.
  LOCAL n IS 0.
  FOR item IN text_list { IF item:CONTAINS(fragment) { SET n TO n + 1. } }
  RETURN n.
}
LOCAL pre_ok IS check_plan_pre(good_pre()).
assert_true("pre good: no errors",   pre_ok["ERRORS"]:LENGTH = 0).
assert_true("pre good: no warnings", pre_ok["WARNINGS"]:LENGTH = 0).

// Each single bad input gives exactly its one error (review focus 5).
LOCAL bad IS good_pre().
SET bad["LEAD_S"] TO 100.
assert_true("pre lead 100 s", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["DV_DOI"] TO 150.
assert_true("pre DOI dv 150", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["DV_PC"] TO 250.
assert_true("pre PC dv above accepted", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["WARP_RATE"] TO 4.
assert_true("pre warp running", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["NODES_OK"] TO FALSE.
assert_true("pre nodes not available", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["TERRAIN_CLEAR_MIN"] TO 1500.
assert_true("pre terrain 1500 m", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["TERRAIN_CLEAR_MIN"] TO -500.
assert_true("pre below terrain is an error, not unmeasured", check_plan_pre(bad)["ERRORS"]:LENGTH = 1).
SET bad TO good_pre().
SET bad["TERRAIN_CLEAR_MIN"] TO NO_TERRAIN.
LOCAL pre_t IS check_plan_pre(bad).
assert_true("pre terrain unmeasured: no error", pre_t["ERRORS"]:LENGTH = 0).
assert_true("pre terrain unmeasured: one warning", pre_t["WARNINGS"]:LENGTH = 1 AND count_text(pre_t["WARNINGS"], "terrain not checked") = 1).
assert_true("pre terrain unmeasured: never says clear", count_text(pre_t["WARNINGS"], "clear") = 0).
SET bad TO good_pre().
SET bad["V_PDI"] TO 1710.
assert_true("pre V_PDI 1710 warns", check_plan_pre(bad)["WARNINGS"]:LENGTH = 1).
assert_true("pre V_PDI 1694 does not warn", check_plan_pre(good_pre())["WARNINGS"]:LENGTH = 0).

FUNCTION good_post {
  RETURN LEXICON("ALT_PDI_PRED", 15900, "ALT_PDI_NOM", 15776, "RANGE_PRED", 437000, "RANGE_NOM", 436656,
                 "SPEED_PRED", 1694.5, "SPEED_PLAN", 1694.4, "XRANGE_PRED", 500, "BURN_ERR", 0.001).
}
LOCAL post_ok IS check_plan_post(good_post()).
assert_true("post good passes", post_ok["PASS"]).
assert_true("post good has 5 lines", post_ok["LINES"]:LENGTH = 5).
LOCAL post_keys IS LIST("ALT_PDI_PRED", "RANGE_PRED", "SPEED_PRED", "XRANGE_PRED", "BURN_ERR").
LOCAL post_bad IS LIST(17000, 443000, 1701, 2500, 0.5).
LOCAL post_name IS LIST("PDI altitude", "ground range", "PDI speed", "crossrange", "node burn").
FROM { LOCAL i IS 0. } UNTIL i >= post_keys:LENGTH STEP { SET i TO i + 1. } DO {
  LOCAL post_in IS good_post().
  SET post_in[post_keys[i]] TO post_bad[i].
  LOCAL res IS check_plan_post(post_in).
  // The failing quantity's own line must say FAIL and carry the quantity's name.
  assert_true("post fails on " + post_name[i], NOT res["PASS"] AND res["LINES"][i]:CONTAINS("FAIL") AND res["LINES"][i]:CONTAINS(post_name[i])).
}

LOCAL tmp_path IS "0:/lm/test_plan_tmp.json".
LOCAL plan_a IS LEXICON("SITE_LAT", 0.67, "SITE_LNG", 23.47, "SITE_ALT", -2600, "T_MADE", 1000, "T_DOI", 4000, "T_PDI", 7400,
                        "T_LAND", 8155, "T_PC", -1, "DV_DOI", 21.55, "DV_PC", 0, "V_PDI", 1694.4, "ALT_PDI", 15776).
plan_write(tmp_path, plan_a).
LOCAL plan_b IS plan_read(tmp_path).
assert_true("plan file read back", plan_b:ISTYPE("Lexicon")).
FOR key IN plan_a:KEYS { assert_near("plan file key " + key, plan_b[key], plan_a[key], 1e-9). }
plan_write(tmp_path, plan_a).
assert_true("plan file rewritten", plan_read(tmp_path)["T_DOI"] = 4000).
IF EXISTS(tmp_path) { DELETEPATH(tmp_path). }
assert_true("plan_read missing file is FALSE", NOT plan_read(tmp_path)).
assert_true("plan fresh at 100 s", NOT plan_is_stale(plan_a, 1100, PLAN_MAX_AGE_S)).
assert_true("plan stale at 7300 s", plan_is_stale(plan_a, 8300, PLAN_MAX_AGE_S)).
assert_true("plan without T_MADE is stale", plan_is_stale(LEXICON("T_DOI", 1), 1100, PLAN_MAX_AGE_S)).

// ---- 1.3: delta-v in local vertical axes for the PAD (plan_lv_components) ---------------------------------------------------------
LOCAL lv_r IS V(1737400 + 15000, 0, 0).
LOCAL lv_v IS V(0, 1600, 0).
LOCAL lv_pro IS plan_lv_components(V(0, 10, 0), lv_r, lv_v).
assert_near("LV: a prograde burn is +x", lv_pro[0], 10, 1e-6).
assert_near("LV: a prograde burn has no y", lv_pro[1], 0, 1e-6).
assert_near("LV: a prograde burn has no z", lv_pro[2], 0, 1e-6).
LOCAL lv_up IS plan_lv_components(V(3, 0, 0), lv_r, lv_v).
assert_near("LV: a burn away from the Moon is -z (Z is down)", lv_up[2], -3, 1e-6).
// An elliptical orbit: the velocity is tilted 3.58 degrees from the local horizontal (flight-path angle: sin 0.062378, cos 0.998053).
// Luminary's local vertical has Z along the radius and X along the horizontal part of the velocity, so a burn along the velocity
// splits into x = 10 cos(g) and z = -10 sin(g) (z is down, the burn points a little away from the Moon), and a burn along the
// horizontal is exactly x. The velocity-tied axes of a node would give x = 10 and z = 0 for the first.
LOCAL lv_ev IS V(100, 1600, 0).
LOCAL lv_along_v IS plan_lv_components(lv_ev:NORMALIZED * 10, lv_r, lv_ev).
assert_near("LV elliptical: a burn along the velocity, x is 10 cos(g)", lv_along_v[0], 9.98053, 1e-4).
assert_near("LV elliptical: a burn along the velocity, z is -10 sin(g)", lv_along_v[2], -0.62378, 1e-4).
assert_near("LV elliptical: a burn along the velocity has no y", lv_along_v[1], 0, 1e-6).
LOCAL lv_horiz IS plan_lv_components(V(0, 10, 0), lv_r, lv_ev).
assert_near("LV elliptical: a burn along the local horizontal is exactly +x", lv_horiz[0], 10, 1e-6).
assert_near("LV elliptical: a burn along the local horizontal has no z", lv_horiz[2], 0, 1e-6).
LOCAL lv_axes IS plan_node_axes(lv_r, lv_v).
LOCAL lv_nrm IS plan_lv_components(lv_axes[1] * 4, lv_r, lv_v).
assert_near("LV: a burn along the node normal is -y (Y is opposite the normal)", lv_nrm[1], -4, 1e-6).

// ---- 1.4: plan_lv_to_dv is the inverse of plan_lv_components (round trip within 1e-9, reference_burn.py checks the same cases) ----
LOCAL lvd_in IS LIST(V(3, -2, 5), V(0, 0, 7), V(1, 2, 3), V(0, -4, 0)).
FOR lvd_dv IN lvd_in {
  assert_vec("LV round trip circular " + lvd_dv, plan_lv_to_dv(plan_lv_components(lvd_dv, lv_r, lv_v), lv_r, lv_v), lvd_dv, 1e-9).
  assert_vec("LV round trip elliptical " + lvd_dv, plan_lv_to_dv(plan_lv_components(lvd_dv, lv_r, lv_ev), lv_r, lv_ev), lvd_dv, 1e-9).
}
// An out-of-plane burn (along the node normal) comes back along the normal, and a burn of x = 10 is along the horizontal track.
assert_vec("LV to dv: y = -4 is along the node normal", plan_lv_to_dv(LIST(0, -4, 0), lv_r, lv_v), lv_axes[1] * 4, 1e-9).
assert_vec("LV to dv: x = 10 is along the local horizontal", plan_lv_to_dv(LIST(10, 0, 0), lv_r, lv_ev), V(0, 10, 0), 1e-9).
assert_vec("LV to dv: z = 3 is towards the Moon (down)", plan_lv_to_dv(LIST(0, 0, 3), lv_r, lv_v), V(-3, 0, 0), 1e-9).

test_end().
