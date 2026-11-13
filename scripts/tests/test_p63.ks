// test_p63.ks -- pad tests for the P63 milestone (run in the kOS terminal, no flight needed).
//   RUNPATH("0:/tests/test_p63.ks").
// Expected values come from scripts/tests/reference.py ("Milestone 3" section). Results go to 0:/lm/logs/test_p63.log.
// The log's last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/descent/lm_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/lm/descent/lm_ignition.ks").
RUNONCEPATH("0:/lm/descent/lm_p63.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_p63.log").

// ---- Task 1: constants (values from the P63 research note; sources in lm_constants.ks) ----------------
assert_vec("RBRFG", RBRFG, V(52.375308, 0, -3254.836061), 1e-9).
assert_vec("VBRFG", VBRFG, V(-32.271005, 0, -0.316992), 1e-9).
assert_vec("ABRFG", ABRFG, V(0.19022568, 0, -2.77502112), 1e-9).
assert_near("JBRFG_Z", JBRFG_Z, -7.173e-4, 1e-9).
// JBRFG* = 8 x JBRFG_z must give back the starred value in the research note.
assert_near("8 * JBRFG_Z = JBRFG*", 8 * JBRFG_Z, -5.7384e-3, 1e-7).
assert_near("GAINBRAK", GAINBRAK, 1, 0).
assert_near("TCGFBRAK", TCGFBRAK, 30, 0).
assert_near("TCGIBRAK", TCGIBRAK, 900, 0).
assert_near("TENDBRAK", TENDBRAK, 62, 0).
assert_near("ZOOMTIME", ZOOMTIME, 26, 0).
assert_near("LEADTIME", LEADTIME, -2.2, 0).
assert_near("DELTTFAP", DELTTFAP, -110, 0).
assert_near("KIGNX", KIGNX, -0.617631, 1e-9).
assert_near("KIGNY", KIGNY, -2.4770341207e-6, 1e-15).
assert_near("KIGNV", KIGNV, -410, 0).
assert_near("DDUMCRIT", DDUMCRIT, 0.08, 0).
assert_near("TRIMACCL", TRIMACCL, 0.350132708, 1e-9).
assert_near("ULLAGE_START_AFTER_TIG30", ULLAGE_START_AFTER_TIG30, 22.4, 0).
assert_near("ULLAGE_OFF_AFTER_IGN", ULLAGE_OFF_AFTER_IGN, 0.5, 0).
assert_true("ullage on at TIG-7.6", ABS((30 - ULLAGE_START_AFTER_TIG30) - 7.6) < 1e-9).
assert_near("DELQFIX", DELQFIX, 60.96, 0).
assert_near("RADAR_DV_FIXED", RADAR_DV_FIXED, 2.286, 1e-9).
assert_near("RADAR_DV_FRAC", RADAR_DV_FRAC, 0.125, 0).
assert_near("RADAR_V_MAX", RADAR_V_MAX, 609.6, 1e-9).
assert_near("RADAR_ALT_MAX_M", RADAR_ALT_MAX_M, 12000, 0).
assert_near("THR_DEAD_LOW", THR_DEAD_LOW, 0.65, 0).
assert_near("THR_DEAD_HIGH", THR_DEAD_HIGH, 0.942, 0).
// The dead band must be a real band, and the zoom must come after the ignition.
assert_true("dead band ordered", THR_DEAD_LOW < THR_DEAD_HIGH AND THR_DEAD_HIGH <= 1).

// ---- Task 3: time-to-go cubic, quadratic guidance, thrust command ------------------------------------------
// Expected values from scripts/tests/reference.py ("Task 3"): braking states from the Apollo 11 simulation,
// tgo is the plain positive time-to-go in seconds.
LOCAL tgo_a IS guid_cubic_tgo(-436655.657, 1636.972015, RBRFG:Z, VBRFG:Z, ABRFG:Z, JBRFG_Z, 600).
assert_true("cubic ignition state OK", tgo_a["OK"]).
assert_near("cubic ignition state tgo", tgo_a["TGO"], 553.1032686418783, 0.01).
LOCAL tgo_b IS guid_cubic_tgo(-122988.425382, 930.934214, RBRFG:Z, VBRFG:Z, ABRFG:Z, JBRFG_Z, 300).
assert_true("cubic mid-burn OK", tgo_b["OK"]).
assert_near("cubic mid-burn tgo", tgo_b["TGO"], 281.46425188226704, 0.01).
LOCAL tgo_c IS guid_cubic_tgo(-15335.901851, 268.673783, RBRFG:Z, VBRFG:Z, ABRFG:Z, JBRFG_Z, 100).
assert_true("cubic near P64 OK", tgo_c["OK"]).
assert_near("cubic near P64 tgo", tgo_c["TGO"], 92.38523772905258, 0.01).
// Sanity: no jerk, no acceleration, equal speeds 100 m/s, 5000 m to go: 50 s.
assert_near("cubic sanity J=A=0 gives distance/speed", guid_cubic_tgo(0, 100, 5000, 100, 0, 0, 30)["TGO"], 50, 1e-3).
// Review focus 3: no root, bad guess, already past the target. Never NaN, never OK, the guess is returned.
LOCAL tgo_d IS guid_cubic_tgo(0, 0, 0, 0, 0, 0, 50).
assert_true("cubic no root not OK", NOT tgo_d["OK"]).
assert_near("cubic no root returns the guess", tgo_d["TGO"], 50, 0).
assert_true("cubic guess 0 not OK", NOT guid_cubic_tgo(-1000, 100, 0, 0, 0, 0, 0)["OK"]).
assert_true("cubic negative guess not OK", NOT guid_cubic_tgo(-1000, 100, 0, 0, 0, 0, -5)["OK"]).
LOCAL tgo_e IS guid_cubic_tgo(5000, 100, 0, 0, 0, 0, 30).
assert_true("cubic past the target not OK", NOT tgo_e["OK"]).
assert_near("cubic past the target returns the guess", tgo_e["TGO"], 30, 0).

LOCAL rg_a IS V(7162.449929, 12, -122988.425382).
LOCAL vg_a IS V(32.715876, -1.5, 930.934214).
assert_vec("acg with lead",    guid_acg(rg_a, vg_a, 281.464252, RBRFG, VBRFG, ABRFG, -2.2),
           V(-0.8820664085322342, 0.029468580467401296, -4.448626648823399), 1e-6).
assert_vec("acg without lead", guid_acg(rg_a, vg_a, 281.464252, RBRFG, VBRFG, ABRFG, 0),
           V(-0.8962408466714391, 0.0301579674031478, -4.47668980936383), 1e-6).
assert_vec("acg late in the burn", guid_acg(rg_a, vg_a, 10, RBRFG, VBRFG, ABRFG, -2.2),
           V(-233.0384825601121, 0.011231999999999853, 3566.522450642258), 1e-4).
// Under a second to go the guidance holds the target acceleration (no division by a tiny time).
assert_vec("acg tgo < 1 returns ADG", guid_acg(rg_a, vg_a, 0.5, RBRFG, VBRFG, ABRFG, -2.2), ABRFG, 0).

// Gravity: magnitude mu/r^2, pointing at the centre.
assert_vec("gravity", guid_gravity(V(0, 0, 1737400), 4.9028e12), V(0, 0, -4.9028e12 / 1737400 ^ 2), 1e-9).
assert_vec("gravity at the centre is zero", guid_gravity(V(0, 0, 0), 4.9028e12), V(0, 0, 0), 0).

// Thrust limit: |AFC| <= f_max/mass keeping up and crossrange, shrinking downrange.
assert_vec("afc unlimited",       guid_afc(V(1, 0.5, -1), V(0, 0, 0), 15000, 43454.7), V(1, 0.5, -1), 1e-9).
assert_vec("afc minus gravity",   guid_afc(V(1, 0.5, -1), V(-1.6, 0, 0), 15000, 43454.7), V(2.6, 0.5, -1), 1e-9).
assert_vec("afc limited",         guid_afc(V(1, 0.5, -5), V(0, 0, 0), 15000, 43454.7), V(1, 0.5, -2.672544315890758), 1e-9).
assert_vec("afc vertical alone over the limit", guid_afc(V(4, 0.5, -1), V(0, 0, 0), 15000, 43454.7), V(4, 0.5, 0), 1e-9).
// Review focus 4: no mass or no thrust: the command is returned as it is, no division by zero.
assert_vec("afc mass 0",          guid_afc(V(1, 0.5, -5), V(0, 0, 0), 0, 43454.7), V(1, 0.5, -5), 0).
assert_vec("afc f_max 0",         guid_afc(V(1, 0.5, -5), V(0, 0, 0), 15000, 0), V(1, 0.5, -5), 0).

// ---- Task 4: throttle logic, handoff, one guidance pass ----------------------------------------------------
// guid_throttle(fc_n, f_max_n, min_frac, prev_frac). The edges are not asserted exactly (floating point could land on
// either side): each case sits clear of an edge. f_max here is 43454.7 N (FMAXPOS).
LOCAL f_full IS 43454.7.
assert_near("throttle far above the band", guid_throttle(0.99 * f_full, f_full, 0.1, 1), 1, 0).
assert_near("throttle just above the band, from partial", guid_throttle(0.9421 * f_full, f_full, 0.1, 0.3), 1, 0).
assert_near("throttle in the band, already full: stay full", guid_throttle(0.80 * f_full, f_full, 0.1, 1), 1, 0).
assert_near("throttle in the band, from partial: highest partial thrust", guid_throttle(0.80 * f_full, f_full, 0.1, 0.3), 0.65, 0).
assert_near("throttle just below the band, from full: leaves full", guid_throttle(0.6499 * f_full, f_full, 0.1, 1), 0.6499, 1e-9).
assert_near("throttle low", guid_throttle(0.50 * f_full, f_full, 0.1, 1), 0.5, 1e-9).
assert_near("throttle never below the minimum", guid_throttle(0.05 * f_full, f_full, 0.1, 0.5), 0.1, 0).
// Review focus 4: no engine thrust available: nothing to divide by, the previous setting is kept.
assert_near("throttle f_max 0 keeps the previous", guid_throttle(1000, 0, 0.1, 0.7), 0.7, 0).
assert_near("throttle f_max negative keeps the previous", guid_throttle(1000, -5, 0.1, 0.7), 0.7, 0).
assert_near("THR_MIN_FRAC", THR_MIN_FRAC, 0.1, 0).

assert_true("handoff at 553 s: no",  NOT guid_handoff(553, TENDBRAK)).
assert_true("handoff at 62 s: no",   NOT guid_handoff(62, TENDBRAK)).
assert_true("handoff at 61.9 s: yes", guid_handoff(61.9, TENDBRAK)).

// guid_pass on the Apollo 11 ignition conditions (site on the raw +X axis, ship 436 km before it, speed VIGN).
// Mass is in tonnes and thrust in kN, the units kOS gives (SHIP:MASS, SHIP:AVAILABLETHRUST).
LOCAL st_a IS LEXICON("BODY_OK", TRUE, "R", V(1737400 + RIGNX, 0, RIGNZ), "V", V(421.056611, 0, 1636.972015),
                      "MASS", 15.2697, "THRUST", 43.4547, "MU", 4.9028e12).
LOCAL land_a IS V(1737400, 0, 0).
LOCAL wm_a IS V(0, 2.66e-6, 0).
LOCAL gp IS guid_pass(st_a, land_a, wm_a, 553, 1, guid_targets_brake(), FALSE).
assert_true("guid_pass valid", gp["VALID"]).
assert_true("guid_pass converged", gp["OK"]).
assert_near("guid_pass alarm 0", gp["ALARM"], 0, 0).
assert_near("guid_pass TGO", gp["TGO"], 553.6470665649779, 0.01).
assert_vec("guid_pass RGU", gp["RGU"], V(-39782.453327999916, 0, -436655.657), 0.01).
assert_vec("guid_pass VGU", gp["VGU"], V(419.89510695238, 0, 1632.4563523258525), 0.01).
assert_vec("guid_pass ACG", gp["ACG"], V(-2.4331257433450357, 0, -3.4886031429500157), 2e-3).
assert_vec("guid_pass AFC", gp["AFC"], V(-0.8877623780735533, 0, -2.703798361211865), 2e-3).
assert_near("guid_pass THR full", gp["THR"], 1, 0).
assert_true("guid_pass no handoff yet", NOT gp["HANDOFF"]).
// Review focus 3: a bad previous time-to-go: alarm 1406, finite answers, no crash.
LOCAL gp_bad IS guid_pass(st_a, land_a, wm_a, 0, 1, guid_targets_brake(), FALSE).
assert_near("guid_pass bad tgo raises alarm 1406", gp_bad["ALARM"], 1406, 0).
assert_true("guid_pass bad tgo not OK", NOT gp_bad["OK"]).
assert_true("guid_pass bad tgo result finite", ABS(gp_bad["AFC"]:MAG) < 1e9).
// Review focus 4: engine off (no available thrust): the command is not limited and the throttle keeps its value.
LOCAL st_off IS LEXICON("BODY_OK", TRUE, "R", V(1737400 + RIGNX, 0, RIGNZ), "V", V(421.056611, 0, 1636.972015),
                        "MASS", 15.2697, "THRUST", 0, "MU", 4.9028e12).
LOCAL gp_off IS guid_pass(st_off, land_a, wm_a, 553, 0.5, guid_targets_brake(), FALSE).
assert_near("guid_pass engine off keeps the throttle", gp_off["THR"], 0.5, 0).
assert_true("guid_pass wrong body is not valid", NOT guid_pass(LEXICON("BODY_OK", FALSE), land_a, wm_a, 553, 1, guid_targets_brake(), FALSE)["VALID"]).

// ---- Task 5: attitude mode and radar lamps ---------------------------------------------------------------------
// att_step(att, sas_on): the SAS button is the AUTO / ATT HOLD switch (on = ATT HOLD). Only the switch changes the mode.
LOCAL at IS att_new().
assert_true("attitude mode starts in AUTO", at["MODE"] = "AUTO").
att_step(at, FALSE).
assert_true("SAS off stays AUTO", at["MODE"] = "AUTO").
att_step(at, TRUE).
assert_true("SAS on gives HOLD", at["MODE"] = "HOLD").
att_step(at, TRUE).
assert_true("SAS still on stays HOLD", at["MODE"] = "HOLD").
att_step(at, FALSE).
assert_true("SAS off returns to AUTO", at["MODE"] = "AUTO").

// radar_step(rad, h_calc, h_radar, speed_surf, v_err): the ALT and VEL lamps.
// Altitude test: fail when |h_radar - h_calc| > DELQFIX + h_calc/8. A failing test lights the lamp only when another
// test failed within the previous three; a passing test clears it. No altitude data above RADAR_ALT_MAX_M: lamp on.
LOCAL rd IS radar_new().
radar_step(rd, 20000, 20000, 1000, 0).
assert_true("ALT lamp on with no altitude data", rd["ALT_LAMP"]).
assert_true("VEL lamp on with no velocity data (speed above 2000 ft/s)", rd["VEL_LAMP"]).
radar_step(rd, 5000, 5000, 300, 0).
assert_true("ALT lamp off after a good test", NOT rd["ALT_LAMP"]).
assert_true("VEL lamp off after a good test", NOT rd["VEL_LAMP"]).
// h_calc 1000: the allowance is 60.96 + 125 = 185.96 m. 300 m off fails, 100 m off passes.
SET rd TO radar_new().
radar_step(rd, 1000, 1300, 100, 0).
assert_true("one bad altitude test does not light the lamp", NOT rd["ALT_LAMP"]).
radar_step(rd, 1000, 1300, 100, 0).
assert_true("two bad altitude tests in a row light it", rd["ALT_LAMP"]).
radar_step(rd, 1000, 1100, 100, 0).
assert_true("a good altitude test clears it", NOT rd["ALT_LAMP"]).
SET rd TO radar_new().
radar_step(rd, 1000, 1300, 100, 0).
radar_step(rd, 1000, 1100, 100, 0).
radar_step(rd, 1000, 1100, 100, 0).
radar_step(rd, 1000, 1300, 100, 0).
assert_true("bad, good, good, bad: two within four, lit", rd["ALT_LAMP"]).
SET rd TO radar_new().
radar_step(rd, 1000, 1300, 100, 0).
radar_step(rd, 1000, 1100, 100, 0).
radar_step(rd, 1000, 1100, 100, 0).
radar_step(rd, 1000, 1100, 100, 0).
radar_step(rd, 1000, 1300, 100, 0).
assert_true("bad, then three good, then bad: not within four, dark", NOT rd["ALT_LAMP"]).
// Velocity test: fail when |v_err| > 2.286 + speed/8 (speed 100: 14.786 m/s).
SET rd TO radar_new().
radar_step(rd, 1000, 1000, 100, 20).
assert_true("one bad velocity test does not light the lamp", NOT rd["VEL_LAMP"]).
radar_step(rd, 1000, 1000, 100, 20).
assert_true("two bad velocity tests light it", rd["VEL_LAMP"]).
radar_step(rd, 1000, 1000, 100, 5).
assert_true("a good velocity test clears it", NOT rd["VEL_LAMP"]).
// No NaN, no crash at the edges.
SET rd TO radar_new().
radar_step(rd, 0, 0, 0, 0).
assert_true("h_calc 0 and speed 0: lamps dark", NOT rd["ALT_LAMP"] AND NOT rd["VEL_LAMP"]).
radar_step(rd, -50, 10, 0, 0).
assert_true("negative h_calc does not crash", TRUE).

// ---- Task 6: IGNALG ------------------------------------------------------------------------------------------
// ign_ddum(rgu_vec, vgu_vec): the time correction in seconds. Zero at the pad-load conditions; 1 km short of the
// nominal downrange position at 1690 m/s needs about 0.59 s more.
assert_near("ddum at the nominal state", ign_ddum(V(RIGNX, 0, RIGNZ), V(0, 0, VIGN)), 0, 1e-9).
assert_near("ddum 1 km short", ign_ddum(V(RIGNX, 0, RIGNZ - 1000), V(0, 0, VIGN)), 0.5916262843863491, 1e-6).
assert_near("ddum 2 km ahead", ign_ddum(V(RIGNX, 0, RIGNZ + 2000), V(0, 0, VIGN)), -1.1832525687726982, 1e-6).
assert_near("ddum high, crossrange, slow", ign_ddum(V(RIGNX + 500, 800, RIGNZ), V(30, 0, VIGN - 15)), 3.3826460569346115, 1e-6).
// ign_trim_dv(afc_guid, cg): the speed gained during the zoom, ZOOMTIME x TRIMACCL = 9.1 m/s along the thrust.
LOCAL cg_a IS LIST(V(1, 0, 0), V(0, -1, 0), V(0, 0, 1)).
assert_vec("trim dv", ign_trim_dv(V(-0.887762, 0, -2.703798), cg_a), V(-2.8398565376297404, 0, -8.649163206726822), 1e-4).
assert_near("trim dv size is ZOOMTIME x TRIMACCL", ign_trim_dv(V(-0.887762, 0, -2.703798), cg_a):MAG, ZOOMTIME * TRIMACCL, 1e-6).
assert_vec("trim dv for no thrust is zero", ign_trim_dv(V(0, 0, 0), cg_a), V(0, 0, 0), 0).
// ign_out_of_plane(r_vec, v_vec, land_vec): signed distance of the site from the orbit plane at ignition.
assert_near("out of plane, site to one side", ign_out_of_plane(V(1737400 + RIGNX, 3000, RIGNZ), V(421, 0, 1637), V(1737400, 0, 0)), 2879.7984603659984, 1e-3).
assert_near("out of plane, other side", ign_out_of_plane(V(1737400 + RIGNX, -3000, RIGNZ), V(421, 0, 1637), V(1737400, 0, 0)), -2879.7984603659984, 1e-3).
assert_near("out of plane, no velocity gives zero not NaN", ign_out_of_plane(V(1737400, 0, 0), V(0, 0, 0), V(1737400, 0, 0)), 0, 0).

// ign_solve with a straight-line predictor: the ship starts 30 km before the pad-load point and flies +Z at VIGN.
// The converged time and the pass count come from the Python mirror (reference.py, "Task 6").
FUNCTION pred_line {
  PARAMETER t_ut.
  RETURN LEXICON("R", V(1737400 + RIGNX, 0, RIGNZ - 30000 + VIGN * (t_ut - 1000)), "V", V(0, 0, VIGN)).
}
FUNCTION pred_still {
  PARAMETER t_ut.
  RETURN LEXICON("R", V(1737400 + RIGNX, 0, RIGNZ - 20000), "V", V(0, 0, VIGN)).
}
FUNCTION pred_fast {
  PARAMETER t_ut.
  RETURN LEXICON("R", V(1737400 + RIGNX, 0, RIGNZ), "V", V(0, 0, 3000)).
}
LOCAL ign_a IS ign_solve(pred_line@, V(1737400, 0, 0), V(0, 2.66e-6, 0), 15269.7, 43454.7, 4.9028e12, 1000).
assert_true("ign_solve converges", ign_a["OK"]).
assert_true("ign_solve within 3 passes", ign_a["ITER"] <= 3).
assert_near("ign_solve converged time", ign_a["T_CONV"], 1018.8358994311296, 0.01).
assert_near("ign_solve TIG is the converged time minus ZOOMTIME", ign_a["TIG"], ign_a["T_CONV"] - ZOOMTIME, 1e-9).
assert_near("ign_solve out of plane (site in the plane)", ign_a["OUTOFPLN"], 0, 1e-3).
// Failure paths: a guess 700 s from the truth, a ship that never gets there, an unbound state.
LOCAL ign_far IS ign_solve(pred_line@, V(1737400, 0, 0), V(0, 2.66e-6, 0), 15269.7, 43454.7, 4.9028e12, ign_a["T_CONV"] - 700).
assert_true("ign_solve guess 700 s away fails", NOT ign_far["OK"]).
assert_true("ign_solve says why (far)", ign_far["WHY"]:LENGTH > 0).
LOCAL ign_still IS ign_solve(pred_still@, V(1737400, 0, 0), V(0, 2.66e-6, 0), 15269.7, 43454.7, 4.9028e12, 1000).
assert_true("ign_solve stationary ship fails", NOT ign_still["OK"]).
assert_true("ign_solve says why (no convergence)", ign_still["WHY"]:LENGTH > 0).
LOCAL ign_fast IS ign_solve(pred_fast@, V(1737400, 0, 0), V(0, 2.66e-6, 0), 15269.7, 43454.7, 4.9028e12, 1000).
assert_true("ign_solve unbound state fails", NOT ign_fast["OK"]).
assert_true("ign_solve says why (unbound)", ign_fast["WHY"]:LENGTH > 0).
// A zero mass and thrust must not crash the pass (guid_afc then returns the unlimited command).
LOCAL ign_nomass IS ign_solve(pred_line@, V(1737400, 0, 0), V(0, 2.66e-6, 0), 0, 0, 4.9028e12, 1000).
assert_true("ign_solve with no mass or thrust still answers", ign_nomass["OK"] OR ign_nomass["WHY"]:LENGTH > 0).

// ---- Task 7: the BURNBABY sequence -----------------------------------------------------------------------------
// seq_step(seq, now, pro_pressed, terminate). TIG is UT 1000 here, so dt = now - 1000.
// A nominal run, stepping every 0.25 s from dt = -40 to +30, with PRO pressed once at dt = -3.
LOCAL sq IS seq_new(1000).
LOCAL first_dt IS LEXICON().
LOCAL ull_on IS -999.
LOCAL ull_off IS -999.
LOCAL eng_on IS -999.
LOCAL zoom_at IS -999.
LOCAL prompt_ok IS TRUE.
LOCAL dt_now IS -40.
UNTIL dt_now > 30 {
  LOCAL out_s IS seq_step(sq, 1000 + dt_now, ABS(dt_now + 3) < 0.01, FALSE).
  IF NOT first_dt:HASKEY(out_s["STATE"]) { SET first_dt[out_s["STATE"]] TO dt_now. }
  IF out_s["ULLAGE"] AND ull_on = -999 { SET ull_on TO dt_now. }
  IF ull_on <> -999 AND NOT out_s["ULLAGE"] AND ull_off = -999 { SET ull_off TO dt_now. }
  IF out_s["ENGINE_ON"] AND eng_on = -999 { SET eng_on TO dt_now. }
  IF out_s["ZOOM"] AND zoom_at = -999 { SET zoom_at TO dt_now. }
  IF out_s["STATE"] = "PROMPT" AND NOT (out_s["PROMPT"] AND out_s["KEY_REL"] AND out_s["VN"] = "V99N62") { SET prompt_ok TO FALSE. }
  SET dt_now TO dt_now + 0.25.
}
assert_near("COAST from the start",    first_dt["COAST"],   -40, 0).
assert_near("BLANK at TIG-35",         first_dt["BLANK"],   -35, 0).
assert_near("COUNT at TIG-30",         first_dt["COUNT"],   -30, 0).
assert_near("PROMPT at TIG-5",         first_dt["PROMPT"],  -5,  0).
assert_near("BURN at TIG",             first_dt["BURN"],    0,   0).
assert_near("BRAKING at TIG+26",       first_dt["BRAKING"], 26,  0).
assert_near("ullage on at TIG-7.6 (first step at or after it)", ull_on, -7.5, 0).
assert_near("ullage off 0.5 s after light-up", ull_off, 0.5, 0).
assert_near("engine on at TIG when PRO came earlier", eng_on, 0, 0).
assert_near("zoom at TIG+26", zoom_at, 26, 0).
assert_true("the prompt state shows V99N62 with the enable prompt and KEY REL", prompt_ok).
// What the display and burn states show.
LOCAL sq2 IS seq_new(1000).
assert_true("COAST shows no sequence display", seq_step(sq2, 940, FALSE, FALSE)["VN"] = "").
assert_true("BLANK blanks the DSKY", seq_step(sq2, 965.5, FALSE, FALSE)["BLANK"]).
assert_true("COUNT shows V06N62", seq_step(sq2, 980, FALSE, FALSE)["VN"] = "V06N62").
assert_near("time to go to TIG", seq_step(sq2, 980, FALSE, FALSE)["TTOGO"], 20, 1e-9).
// Review focus 1: a late call (warp, a long cycle) still gives the right outputs.
LOCAL sq3 IS seq_new(1000).
seq_step(sq3, 900, FALSE, FALSE).
LOCAL late_a IS seq_step(sq3, 998, FALSE, FALSE).
assert_true("a jump from dt=-100 to -2 gives PROMPT", late_a["STATE"] = "PROMPT").
assert_true("a jump from dt=-100 to -2 has the ullage on", late_a["ULLAGE"]).
LOCAL late_b IS seq_step(sq3, 1040, FALSE, FALSE).
assert_true("past TIG with no PRO the engine stays off", NOT late_b["ENGINE_ON"]).
assert_true("past TIG with no PRO the prompt stays up", late_b["PROMPT"] AND late_b["STATE"] = "PROMPT").
assert_true("past TIG with no PRO the ullage stays on", late_b["ULLAGE"]).
// Review focus 2: PRO before the prompt is ignored; PRO in the prompt before TIG waits for TIG; a late PRO lights at once.
LOCAL sq4 IS seq_new(1000).
seq_step(sq4, 980, TRUE, FALSE).
LOCAL early_a IS seq_step(sq4, 1000, FALSE, FALSE).
assert_true("PRO at dt=-20 is ignored: no ignition at TIG", NOT early_a["ENGINE_ON"]).
LOCAL early_b IS seq_step(sq4, 1001, TRUE, FALSE).
assert_true("a PRO in the prompt after TIG lights at once", early_b["ENGINE_ON"] AND early_b["STATE"] = "BURN").
LOCAL sq5 IS seq_new(1000).
LOCAL wait_a IS seq_step(sq5, 997, TRUE, FALSE).
assert_true("PRO at dt=-3 does not light before TIG", NOT wait_a["ENGINE_ON"]).
LOCAL wait_b IS seq_step(sq5, 999.75, FALSE, FALSE).
assert_true("still not lit at dt=-0.25", NOT wait_b["ENGINE_ON"]).
LOCAL wait_c IS seq_step(sq5, 1000, FALSE, FALSE).
assert_true("lights exactly at TIG", wait_c["ENGINE_ON"]).
LOCAL twice IS seq_step(sq5, 1002, TRUE, FALSE).
assert_true("a second PRO changes nothing", twice["ENGINE_ON"] AND twice["STATE"] = "BURN").
// Zoom is measured from the nominal TIG: a PRO after TIG+26 zooms in the same call.
LOCAL sq6 IS seq_new(1000).
LOCAL slow IS seq_step(sq6, 1040, TRUE, FALSE).
assert_true("a PRO after TIG+26 lights", slow["ENGINE_ON"]).
assert_true("and zooms on the same call", slow["ZOOM"] AND slow["STATE"] = "BRAKING").
assert_true("zoom fires only once", NOT seq_step(sq6, 1041, FALSE, FALSE)["ZOOM"]).
// Terminate in every state ends the sequence and stops the ullage.
FUNCTION seq_term_at {
  PARAMETER now_ut, pro_first.
  LOCAL sq_t IS seq_new(1000).
  IF pro_first { seq_step(sq_t, 997, TRUE, FALSE). }
  RETURN seq_step(sq_t, now_ut, FALSE, TRUE).
}
assert_true("terminate in COAST",   seq_term_at(960, FALSE)["ENDED"] AND NOT seq_term_at(960, FALSE)["ULLAGE"]).
assert_true("terminate in BLANK",   seq_term_at(965.5, FALSE)["ENDED"]).
assert_true("terminate in COUNT",   seq_term_at(980, FALSE)["ENDED"]).
assert_true("terminate in PROMPT stops the ullage", seq_term_at(997, FALSE)["ENDED"] AND NOT seq_term_at(997, FALSE)["ULLAGE"]).
assert_true("terminate with PRO armed before TIG: ended and no ignition", seq_term_at(1010, TRUE)["ENDED"] AND NOT seq_term_at(1010, TRUE)["ENGINE_ON"]).
LOCAL sq7 IS seq_new(1000).
seq_step(sq7, 997, TRUE, FALSE).
seq_step(sq7, 1000, FALSE, FALSE).
LOCAL after_t IS seq_step(sq7, 1010, FALSE, TRUE).
assert_true("terminate after ignition: ended, ullage off, engine state kept", after_t["ENDED"] AND NOT after_t["ULLAGE"] AND after_t["ENGINE_ON"]).

// ---- Task 9: guidance axes back to raw axes, programme selection keys and the P63 nouns ----------------------------
// cg_unapply undoes cg_apply for a matrix whose rows are unit vectors at right angles.
LOCAL cg_t IS LIST(V(0, 0, 1), V(1, 0, 0), V(0, 1, 0)).
assert_vec("cg_apply on a permutation matrix", cg_apply(cg_t, V(1, 2, 3)), V(3, 1, 2), 1e-12).
assert_vec("cg_unapply undoes cg_apply", cg_unapply(cg_t, cg_apply(cg_t, V(1, 2, 3))), V(1, 2, 3), 1e-12).
LOCAL cg_u IS guidance_cg(V(1737400, 0, 0), V(1697618, 0, -436656), V(421, 0, 1637), -69).
assert_vec("cg_unapply undoes cg_apply on a real guidance matrix", cg_unapply(cg_u, cg_apply(cg_u, V(5, -7, 11))), V(5, -7, 11), 1e-9).
RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
FUNCTION press_all {
  PARAMETER kk, chars.
  FOR ch IN chars { key_press(kk, ch). }
}
// V37 ENTR 63 ENTR selects P63 (Luminary: V37 = change programme).
LOCAL kk IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
assert_near("no programme requested at the start", kk["PROG_REQ"], -1, 0).
press_all(kk, LIST("V", "3", "7", "E")).
assert_true("V37 E waits for a programme number", kk["AWAIT_PROG"] AND NOT kk["OPRERR"]).
assert_near("V37 shows verb 37 while waiting", kk["VERB"], 37, 0).
press_all(kk, LIST("6", "3")).
assert_true("digits go to the programme number, no OPR ERR", kk["PBUF"] = "63" AND NOT kk["OPRERR"]).
// The window shows the typed programme number in the NOUN cells while waiting (flags the GUI reads), the verb 37 stays.
LOCAL pk IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
assert_true("no programme entry shown before V37", NOT flags_from_keys(pk, FALSE)["PROGKEY"]).
press_all(pk, LIST("V", "3", "7", "E")).
assert_true("V37 E: the programme entry is active with nothing typed", flags_from_keys(pk, FALSE)["PROGKEY"] AND flags_from_keys(pk, FALSE)["PBUF"] = "").
press_all(pk, LIST("6")).
assert_true("one digit typed shows in the entry", flags_from_keys(pk, FALSE)["PBUF"] = "6").
press_all(pk, LIST("3")).
assert_true("both digits show in the entry", flags_from_keys(pk, FALSE)["PBUF"] = "63").
assert_true("the terminal entry line reads V37 P63", flags_from_keys(pk, FALSE)["ENTRY"] = "V37 P63").
assert_near("the verb shown is still 37", pk["VERB"], 37, 0).
press_all(pk, LIST("E")).
assert_true("after ENTR the entry is gone", NOT flags_from_keys(pk, FALSE)["PROGKEY"]).
press_all(kk, LIST("E")).
assert_near("ENTR requests programme 63", kk["PROG_REQ"], 63, 0).
assert_true("no longer waiting after ENTR", NOT kk["AWAIT_PROG"]).
assert_near("the verb returns to the monitor verb", kk["VERB"], 16, 0).
// V37 E 00 E ends the programme (P00).
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("V", "3", "7", "E", "0", "0", "E")).
assert_near("V37 E 00 E requests P00", kk["PROG_REQ"], 0, 0).
// A programme that does not exist, or one digit only, gives OPR ERR and no request.
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("V", "3", "7", "E", "9", "9", "E")).
assert_true("P99 does not exist: OPR ERR", kk["OPRERR"]).
assert_near("and no request is made", kk["PROG_REQ"], -1, 0).
assert_true("and it stops waiting", NOT kk["AWAIT_PROG"]).
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("V", "3", "7", "E", "6", "E")).
assert_true("one digit is not a programme number: OPR ERR", kk["OPRERR"] AND kk["PROG_REQ"] = -1).
// Pressing V while waiting cancels the wait; digits with no V, N or wait still give OPR ERR as before.
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("V", "3", "7", "E", "V")).
assert_true("V cancels the wait", NOT kk["AWAIT_PROG"] AND kk["MODE"] = "V").
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("5")).
assert_true("a stray digit is still OPR ERR", kk["OPRERR"]).
// Existing entry still works: V16 N63 E.
SET kk TO keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
press_all(kk, LIST("V", "1", "6", "N", "6", "3", "E")).
assert_true("V16 N63 E still sets verb 16 noun 63", kk["VERB"] = 16 AND kk["NOUN"] = 63 AND NOT kk["OPRERR"]).
press_all(kk, LIST("V", "9", "9", "E")).
assert_true("V99 is not a typed verb (the programme shows it): OPR ERR", kk["OPRERR"]).

// p63_start refusals that need no flight state (they only look at the plan argument first).
LOCAL ref_a IS p63_start(FALSE, 0, 0, V(1, 0, 0), V(0, 0, 0)).
assert_true("P63 refuses with no saved plan", ref_a["REFUSED"]:CONTAINS("plan")).
LOCAL ref_b IS p63_start(LEXICON(), 0, 0, V(1, 0, 0), V(0, 0, 0)).
assert_true("P63 refuses an incomplete plan", ref_b["REFUSED"]:CONTAINS("incomplete")).
LOCAL ref_c IS p63_start(LEXICON("T_PDI", 1e9, "SITE_LAT", 10, "SITE_LNG", 20), 0, 0, V(1, 0, 0), V(0, 0, 0)).
assert_true("P63 refuses a plan for another site", ref_c["REFUSED"]:CONTAINS("another landing site")).
// T_PDI 0 is in the past, so this can never get as far as taking control of the ship on the pad.
LOCAL ref_d IS p63_start(LEXICON("T_PDI", 0, "SITE_LAT", 10, "SITE_LNG", 20), 10, 380, V(1, 0, 0), V(0, 0, 0)).
assert_true("a longitude 360 degrees round is the same site (refused for another reason, not the site)", NOT ref_d["REFUSED"]:CONTAINS("another landing site")).

// Nouns 61, 62, 63 with the P63 values: N61 time-to-go in braking, time to go to TIG, out of plane distance;
// N62 speed, time to go, delta-v gained; N63 speed, vertical speed, height. Time registers are mm:ss.
LOCAL nd IS LEXICON("VALID", TRUE, "VHORIZ", 0, "ABVEL", 100, "HDOT", -10, "HCALC", 1000, "RANGEDSP", 5000, "LOOKANGL", 0,
                    "DELTAH", 0, "TTOGO", 75, "TTFDISP", 300, "OUTOFPLN", 1852, "DVTOTAL", 10).
LOCAL n61 IS noun_registers(61, nd).
assert_true("N61 R1 braking time to go", n61[0] = "+05 00").
assert_true("N61 R2 time to ignition (plus before TIG)", n61[1] = "+01 15").
assert_true("N61 R3 out of plane in nautical miles", n61[2] = "+001.0").
LOCAL n62 IS noun_registers(62, nd).
assert_true("N62 R1 speed in ft/s", n62[0] = "+00328").
assert_true("N62 R2 time to ignition (plus before TIG)", n62[1] = "+01 15").
assert_true("N62 R3 delta-v gained in ft/s", n62[2] = "+00033").
LOCAL nd2 IS LEXICON("VALID", TRUE, "VHORIZ", 0, "ABVEL", 100, "HDOT", -10, "HCALC", 1000, "RANGEDSP", 5000, "LOOKANGL", 0, "DELTAH", 0).
assert_true("N62 without P63 values is as before: speed then no data", noun_registers(62, nd2)[0] = "+00328" AND noun_registers(62, nd2)[1] = NA AND noun_registers(62, nd2)[2] = NA).
assert_true("N61 without P63 values: no data", noun_registers(61, nd2)[0] = NA).
assert_true("N63 unchanged", noun_registers(63, nd)[0] = "+00328" AND noun_registers(63, nd)[1] = "-00033").

// ---- Turn, then warp (warp_step is pure: attitude error and turn rate come in as numbers) ----
LOCAL wt IS warp_new().
assert_near("warp: not settled, no warp", warp_step(wt, 100, 1000, 30, 0), -1, 0).
assert_near("warp: settled but not yet held, no warp", warp_step(wt, 110, 1000, 1, 0.1), -1, 0).
assert_near("warp: still settled after 4 s, no warp", warp_step(wt, 114, 1000, 1, 0.1), -1, 0).
assert_near("warp: settled for 5 s warps to TIG - lead", warp_step(wt, 115, 1000, 1, 0.1), 1000 - P63_WARP_LEAD_S, 0).
assert_true("warp: done after the warp", wt["DONE"]).
assert_near("warp: only once (a cancelled warp is not restarted)", warp_step(wt, 200, 1000, 1, 0.1), -1, 0).
SET wt TO warp_new().
warp_step(wt, 100, 1000, 1, 0.1).
assert_near("warp: still turning resets the timer", warp_step(wt, 104, 1000, 1, 0.5), -1, 0).
assert_near("warp: timer restarted, 4 s later no warp", warp_step(wt, 108, 1000, 1, 0.1), -1, 0).
assert_near("warp: 5 s after the restart it warps", warp_step(wt, 113, 1000, 1, 0.1), 1000 - P63_WARP_LEAD_S, 0).
SET wt TO warp_new().
warp_step(wt, 100, 1000, 1, 0.1).
assert_near("warp: a large attitude error resets the timer", warp_step(wt, 104, 1000, 5, 0.1), -1, 0).
SET wt TO warp_new().
assert_near("warp: already inside the lead, no warp", warp_step(wt, 1000 - P63_WARP_LEAD_S + 20, 1000, 1, 0.1), -1, 0).
assert_true("warp: and marked done so the countdown never warps", wt["DONE"]).
SET wt TO warp_new().
assert_near("warp: stop time less than the minimum ahead, no warp", warp_step(wt, 1000 - P63_WARP_LEAD_S - 5, 1000, 1, 0.1), -1, 0).
SET wt TO warp_new().
assert_near("warp: stop time just over the minimum ahead, waits for settling", warp_step(wt, 1000 - P63_WARP_LEAD_S - 11, 1000, 1, 0.1), -1, 0).
assert_true("warp: and is not done yet", NOT wt["DONE"]).
// ---- window roll as in Luminary: shortest turn before ignition, rate-limited roll to windows-up after ----
LOCAL wt1 IS win_min_rotation(V(1, 0, 0), V(0, 1, 0), V(0, -1, 0)).
assert_true("window: a 90 degree turn about z takes the window from +y to +x", VANG(wt1, V(1, 0, 0)) < 1e-6).
assert_true("window: stays perpendicular to the new thrust axis", ABS(VDOT(wt1, V(0, -1, 0))) < 1e-9).
assert_true("window: a turn about the window vector itself leaves it alone", VANG(win_min_rotation(V(1, 0, 0), V(0, 0, 1), V(0, 1, 0)), V(0, 0, 1)) < 1e-6).
assert_true("window: no turn leaves it alone", VANG(win_min_rotation(V(1, 0, 0), V(0, 1, 0), V(1, 0, 0)), V(0, 1, 0)) < 1e-6).
assert_true("window: exactly opposite thrust axis leaves it alone", VANG(win_min_rotation(V(1, 0, 0), V(0, 1, 0), V(-1, 0, 0)), V(0, 1, 0)) < 1e-6).
LOCAL wt2 IS win_min_rotation(V(1, 0, 0), V(0, 1, 0), V(-1, 0.05, 0)).
assert_true("window: a near-opposite turn stays perpendicular to the thrust axis", ABS(VDOT(wt2, V(-1, 0.05, 0):NORMALIZED)) < 1e-9).
// win_hold: the ship's own window vector projected onto the plane perpendicular to the thrust axis, led by the stick
assert_true("hold: no stick keeps the ship's own roll (projected)", VANG(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), 0), V(0, 1, 0)) < 1e-6).
assert_true("hold: a vector off the plane is projected (1,1,0) with thrust x gives +y", VANG(win_hold(V(1, 1, 0), V(1, 0, 0), V(0, 0, 1), 0), V(0, 1, 0)) < 1e-6).
assert_true("hold: inside the detent counts as no stick", VANG(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), P63_ROLL_DETENT * 0.5), V(0, 1, 0)) < 1e-6).
assert_near("hold: full stick leads the ship's roll by the lead angle", VANG(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), 1), V(0, 1, 0)), P63_ROLL_STICK_LEAD_DEG, 1e-6).
assert_near("hold: half stick leads by half the angle", VANG(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), 0.5), V(0, 1, 0)), P63_ROLL_STICK_LEAD_DEG / 2, 1e-6).
assert_true("hold: the opposite stick leads the other way", VANG(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), 1), win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), -1)) > 2 * P63_ROLL_STICK_LEAD_DEG - 1e-6).
assert_true("hold: stays perpendicular to the thrust axis", ABS(VDOT(win_hold(V(0, 1, 0), V(1, 0, 0), V(0, 0, 1), 1), V(1, 0, 0))) < 1e-9).
assert_true("hold: a window vector along the thrust axis keeps the old command", VANG(win_hold(V(1, 0, 0), V(1, 0, 0), V(0, 0, 1), 0), V(0, 0, 1)) < 1e-6).
assert_true("window mode: the plan's KEEP is used", p63_pick_window(LEXICON("WINDOW_MODE", "KEEP")) = "KEEP").
assert_true("window mode: the plan's UP is used", p63_pick_window(LEXICON("WINDOW_MODE", "UP")) = "UP").
assert_true("window mode: a plan without the key gets the default", p63_pick_window(LEXICON("T_PDI", 1)) = P63_WINDOW_MODE).
assert_true("window mode: an unknown value gets the default", p63_pick_window(LEXICON("WINDOW_MODE", "SIDEWAYS")) = P63_WINDOW_MODE).
assert_true("window mode: no plan gets the default", p63_pick_window(FALSE) = P63_WINDOW_MODE).
assert_true("window mode: the default is UP", P63_WINDOW_MODE = "UP").
// ---- coast deadband (db_step): release inside 0.5 deg and slow, re-lock past 1.0 deg, hysteresis between ----
LOCAL dbt IS db_new().
assert_true("deadband: starts locked", dbt["LOCKED"]).
db_step(dbt, 3, 0.5, FALSE).
assert_true("deadband: far from the attitude stays locked", dbt["LOCKED"]).
db_step(dbt, 0.4, 0.4, FALSE).
assert_true("deadband: close but still turning fast stays locked", dbt["LOCKED"]).
db_step(dbt, 0.7, 0.05, FALSE).
assert_true("deadband: slow but error above the release angle stays locked", dbt["LOCKED"]).
db_step(dbt, 0.4, 0.05, FALSE).
assert_true("deadband: close and slow releases the lock", NOT dbt["LOCKED"]).
db_step(dbt, 0.9, 0.3, FALSE).
assert_true("deadband: drifting to 0.9 deg stays released (between 0.5 and 1.0)", NOT dbt["LOCKED"]).
db_step(dbt, 1.2, 0.1, FALSE).
assert_true("deadband: past 1.0 deg takes the lock again", dbt["LOCKED"]).
db_step(dbt, 0.9, 0.05, FALSE).
assert_true("deadband: back at 0.9 deg stays locked (not released until 0.5)", dbt["LOCKED"]).
db_step(dbt, 0.3, 0.02, FALSE).
assert_true("deadband: released again once close", NOT dbt["LOCKED"]).
db_step(dbt, 0.1, 0.01, TRUE).
assert_true("deadband: must_lock (countdown, ullage, burn) locks at any error", dbt["LOCKED"]).
db_step(dbt, 0.1, 0.01, TRUE).
assert_true("deadband: must_lock keeps it locked even when close and slow", dbt["LOCKED"]).
// On the pad (CTL_DRY) the readings are 999, so the deadband never releases there.
SET CTL_DRY TO TRUE.
SET dbt TO db_new().
db_step(dbt, ctl_att_error_deg(), ctl_rate_deg_s(), FALSE).
assert_true("pad: the deadband never releases without a ship", dbt["LOCKED"]).
SET CTL_DRY TO FALSE.
// On the pad (CTL_DRY) the ship readings never count as settled, so p63_step never warps there.
SET CTL_DRY TO TRUE.
assert_true("pad: attitude error never settled", ctl_att_error_deg() > P63_SETTLE_ERR_DEG).
assert_true("pad: rate never settled", ctl_rate_deg_s() > P63_SETTLE_RATE_DEG_S).

// ---- Review fixes: p63_step on the pad with the control writes switched off (CTL_DRY) ----------------------------
// The whole-branch review found the programme glue untested: V34 blocked in the enable prompt, alarm 1406 not shown.
// CTL_DRY makes every ctl_* function that writes the ship's controls do nothing, so p63_step can run here.
RUNONCEPATH("0:/shared/lm_nav.ks").
SET CTL_DRY TO TRUE.
FUNCTION dry_prog {
  PARAMETER seq_lex, lit, t_last.
  RETURN LEXICON("REFUSED", "", "SEQ", seq_lex, "WINDOW_MODE", "UP", "TURNED", FALSE, "FORE0", V(1, 0, 0), "WIN0", V(0, 1, 0), "WCMD", V(0, 1, 0), "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "WARP", warp_new(), "ENGINE", 0,
                 "LAND", V(1737400, 0, 0), "WM", V(0, 2.66e-6, 0), "TIG", 1000, "BURN_DIR", V(0, 0, 1), "OUTOFPLN", 0,
                 "TGO", IGN_TGO_SEED, "THR", 0, "GP", LEXICON(), "ZOOMED", FALSE, "ENGINE_LIT", lit, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", t_last, "HANDOFF_T", -1, "LAST_STATE", "", "LAST_ALARM", 0, "ENDED", FALSE).
}
FUNCTION dry_state_v {
  PARAMETER now_ut, r_vec, v_vec, thrust_kn.
  RETURN LEXICON("R", r_vec, "V", v_vec, "T", now_ut, "MASS", 15.2697, "THRUST", thrust_kn,
                 "THRUST_NOW", thrust_kn, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 15000, "XNB", V(1, 0, 0)).
}
FUNCTION dry_state {
  PARAMETER now_ut, r_vec, thrust_kn.
  RETURN dry_state_v(now_ut, r_vec, V(421.056611, 0, 1636.972015), thrust_kn).
}
LOCAL d_land IS V(1737400, 0, 0).
LOCAL d_wm IS V(0, 2.66e-6, 0).
LOCAL d_r IS V(1737400 + RIGNX, 0, RIGNZ).
// In the enable prompt (dt = -2): V99 N62 flashes, KEY REL lights, the ullage is on.
LOCAL dp IS dry_prog(seq_new(1000), FALSE, 997.75).
LOCAL dk IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL dst IS dry_state(998, d_r, 0).
LOCAL dout IS p63_step(dp, dst, nav_derived(dst, d_land, d_wm), dk).
assert_near("prompt sets verb 99", dout["SET_VERB"], 99, 0).
assert_near("prompt sets noun 62", dout["SET_NOUN"], 62, 0).
assert_true("prompt flashes and lights KEY REL", dout["FLASH"] AND dout["KEY_REL"]).
assert_true("prompt: ullage on", dp["ULLAGE_ON"]).
assert_true("prompt: not ended", NOT dout["ENDED"]).
// Review critical 1: V34 ENTR in the prompt ends the programme, does not force V99 back on, and stops the ullage.
SET dk["VERB"] TO 34.
SET dst TO dry_state(998.25, d_r, 0).
SET dout TO p63_step(dp, dst, nav_derived(dst, d_land, d_wm), dk).
assert_true("V34 in the prompt ends the programme", dout["ENDED"]).
assert_near("V34 in the prompt does not set a new verb", dout["SET_VERB"], -1, 0).
assert_true("V34 in the prompt stops the ullage", NOT dp["ULLAGE_ON"]).
// Review critical 3: alarm 1406 reaches the display: the lander almost at the site and nearly stationary (V(1, 0, 1)) has no positive
// time-to-go root (checked with reference.py's guid_pass_ref: ok False). The earlier state, 50 km on in z, does solve (tgo about 705 s).
LOCAL burn_seq IS LEXICON("TIG", 1000, "ARMED", TRUE, "IGN_T", 1000, "ZOOMED", FALSE, "ENDED", FALSE).
LOCAL dp2 IS dry_prog(burn_seq, TRUE, 1004.75).
LOCAL dst2 IS dry_state_v(1005, V(1737400 + 100, 0, 10), V(1, 0, 1), 43.4547).
LOCAL dout2 IS p63_step(dp2, dst2, nav_derived(dst2, d_land, d_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_near("an unsolvable time-to-go gives alarm 1406", dout2["ALARM"], 1406, 0).
assert_true("and says so in a message", dout2["MSG"]:CONTAINS("1406")).
LOCAL dout3 IS p63_step(dp2, dry_state_v(1005.25, V(1737400 + 100, 0, 10), V(1, 0, 1), 43.4547), nav_derived(dst2, d_land, d_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_true("the alarm message is not repeated every cycle", NOT dout3["MSG"]:CONTAINS("1406")).
assert_near("but the alarm stays on", dout3["ALARM"], 1406, 0).
// A normal burn state gives no alarm.
LOCAL dp4 IS dry_prog(burn_seq, TRUE, 1004.75).
LOCAL dst4 IS dry_state(1005, d_r, 43.4547).
LOCAL dout4 IS p63_step(dp4, dst4, nav_derived(dst4, d_land, d_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_near("a normal burn state gives no alarm", dout4["ALARM"], 0, 0).
assert_true("and the guidance is not at the handoff", NOT dp4["GP"]["HANDOFF"]).
assert_true("a normal burn is not a handover", NOT dout4["HANDOVER"]).
assert_near("p63_step reports PROG_NO 63", dout4["PROG_NO"], 63, 0).
// Milestone 4: when braking is over (time-to-go below TENDBRAK) the step asks for P64, once. The state is the braking sim
// of reference.py about 50 s before the braking target (tgo 50.3 s), guidance axes with the site on the raw +X axis.
LOCAL dp6 IS dry_prog(LEXICON("TIG", 1000, "ARMED", TRUE, "IGN_T", 1000, "ZOOMED", FALSE, "ENDED", FALSE), TRUE, 1004.75).
SET dp6["ZOOMED"] TO TRUE.
SET dp6["TGO"] TO 50.5.
LOCAL dst6 IS dry_state_v(1005, V(1739309.437, 0, -6771.996), V(-40.965, 0, 145.871), 43.4547).
LOCAL dout6 IS p63_step(dp6, dst6, nav_derived(dst6, d_land, d_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_true("braking over: HANDOVER", dout6["HANDOVER"]).
assert_true("handover message says P64 starts", dout6["MSG"]:CONTAINS("P64 STARTS")).
assert_true("handover does not end the programme", NOT dout6["ENDED"]).
SET dout6 TO p63_step(dp6, dry_state_v(1005.25, V(1739309.437, 0, -6771.996), V(-40.965, 0, 145.871), 43.4547), nav_derived(dst6, d_land, d_wm), keys_new(LM_NOUNS, LM_VERBS, LM_PROGS)).
assert_true("HANDOVER is returned only once", NOT dout6["HANDOVER"]).
// The PRO flag is cleared by the step.
LOCAL dk5 IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
SET dk5["PRO"] TO TRUE.
p63_step(dry_prog(seq_new(1000), FALSE, 949.75), dry_state(950, d_r, 0), nav_derived(dry_state(950, d_r, 0), d_land, d_wm), dk5).
assert_true("p63_step clears PRO", NOT dk5["PRO"]).
SET CTL_DRY TO FALSE.

test_end().
