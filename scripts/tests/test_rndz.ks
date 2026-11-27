// test_rndz.ks -- pad test for the rendezvous maths (lm/rndz/lm_rndz.ks). No ship access.
//   RUNPATH("0:/tests/test_rndz.ks").   Log: 0:/lm/logs/test_rndz.log. Numbers: python scripts/tests/reference_rndz.py

RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/rndz/lm_rndz.ks").

test_begin("0:/lm/logs/test_rndz.log").
SET CONFIG:IPU TO 2000.

// The shared scenario: the LM at the apolune of a 45 x 9 nmi orbit, the CSM 8.4 degrees ahead, in the x-z plane.
GLOBAL TR_MU IS 4.9028e12.
GLOBAL TR_RADIUS IS 1737400.
GLOBAL TR_APO IS TR_RADIUS + 45 * 1852.
GLOBAL TR_PERI IS TR_RADIUS + 9 * 1852.
GLOBAL TR_RA IS V(TR_APO, 0, 0).
GLOBAL TR_VA IS V(0, 0, SQRT(TR_MU * (2 / TR_APO - 2 / (TR_APO + TR_PERI)))).

// tr_csm: a CSM state at the given radius and speed, the given angle ahead, moving level.
FUNCTION tr_csm {
  PARAMETER radius, speed, angle.
  RETURN LEXICON("R", V(COS(angle), 0, SIN(angle)) * radius, "V", V(-SIN(angle), 0, COS(angle)) * speed).
}
FUNCTION tr_circular {
  PARAMETER radius, angle.
  RETURN tr_csm(radius, SQRT(TR_MU / radius), angle).
}
FUNCTION tr_input {
  PARAMETER csm.
  RETURN LEXICON("R1", TR_RA, "V1", TR_VA, "RT", csm["R"], "VT", csm["V"], "TCSI", 0, "TTPI", 5800, "NN", 1,
      "ELEV", 26.6, "FORCE_HALF", FALSE, "MU", TR_MU, "RADIUS", TR_RADIUS).
}
// tr_row: one line of the plan's table: signed CSI delta-V, TCDH, DH and the CDH delta-V in local vertical axes.
FUNCTION tr_row {
  PARAMETER name, inp, want_dv, want_tcdh, want_dh, want_lv.
  LOCAL out IS rndz_csi(inp).
  assert_true(name + ": solved, alarm " + out["ALARM"], out["OK"]).
  IF NOT out["OK"] { RETURN out. }
  assert_near(name + ": CSI delta-V", out["DV"], want_dv, 0.001).
  assert_near(name + ": time of CDH", out["TCDH"], want_tcdh, 0.05).
  assert_near(name + ": height difference", out["DH"], want_dh, 1).
  LOCAL ahead IS rndz_fwd(out["NORMAL"], out["R2"]).
  LOCAL lv IS V(VDOT(out["DV2"], ahead), -VDOT(out["DV2"], out["NORMAL"]), -VDOT(out["DV2"], out["R2"]:NORMALIZED)).
  assert_vec(name + ": CDH delta-V, local vertical", lv, want_lv, 0.001).
  RETURN out.
}

// ---- the table ----
LOCAL tr_circ IS tr_circular(1848520, 8.4).
LOCAL tr_first IS tr_row("circular CSM", tr_input(tr_circ), 15.37881, 3485.806, 27760.41, V(0.0044, 0, 0)).
IF tr_first["OK"] { assert_near("circular CSM: three passes", tr_first["COUNT"], 3, 0). }

LOCAL tr_peri_r IS TR_RADIUS + 58 * 1852.
LOCAL tr_apo_r IS TR_RADIUS + 64 * 1852.
LOCAL tr_ecc IS tr_csm(tr_peri_r, SQRT(TR_MU * (2 / tr_peri_r - 2 / (tr_peri_r + tr_apo_r))), 8.4).
tr_row("eccentric CSM", tr_input(tr_ecc), 16.67926, 3494.113, 29325.25, V(-1.1705, 0, -0.7313)).

LOCAL tr_lm_early IS conic_kepler(TR_RA, TR_VA, -600, TR_MU).
LOCAL tr_tg_early IS conic_kepler(tr_circ["R"], tr_circ["V"], -600, TR_MU).
LOCAL tr_in IS tr_input(tr_tg_early).
SET tr_in["R1"] TO tr_lm_early["R"].
SET tr_in["V1"] TO tr_lm_early["V"].
SET tr_in["TCSI"] TO -600.
SET tr_in["NN"] TO 2.
tr_row("from -600 s, NN 2", tr_in, 16.42746, 5088.81, 44291.07, V(-8.5441, 0, 0)).

// ---- alarms ----
SET tr_in TO tr_input(tr_circ).
SET tr_in["TTPI"] TO 1800.
assert_near("TPI at 1800 s: alarm 604", rndz_csi(tr_in)["ALARM"], 604, 0).
assert_near("CSM 60 degrees ahead: alarm 601", rndz_csi(tr_input(tr_circular(1848520, 60)))["ALARM"], 601, 0).
SET tr_in TO tr_input(tr_circular(TR_RADIUS + 18520, 8.4)).
SET tr_in["ELEV"] TO 0.
assert_near("low CSM, elevation 0: alarm 600", rndz_csi(tr_in)["ALARM"], 600, 0).

// ---- helpers ----
LOCAL tr_nrm IS lm_cross(tr_circ["R"], tr_circ["V"]):NORMALIZED.
LOCAL tr_tilted IS tr_circ["V"] * COS(0.5) + tr_nrm * (tr_circ["V"]:MAG * SIN(0.5)).
LOCAL tr_flat IS rndz_into_plane(tr_tilted, tr_nrm).
assert_near("into plane keeps the length", tr_flat:MAG, tr_tilted:MAG, 0.000001).
assert_near("into plane leaves no normal part", VDOT(tr_flat, tr_nrm), 0, 0.000001).
assert_vec("forward of the LM is along its velocity", rndz_fwd(tr_nrm, TR_RA), TR_VA:NORMALIZED, 0.000001).

LOCAL tr_here IS rndz_target_at(tr_ecc["R"], tr_ecc["V"], tr_ecc["R"]:NORMALIZED, tr_nrm, TR_MU).
assert_vec("target at its own direction: position", tr_here["R"], tr_ecc["R"], 0.01).
assert_vec("target at its own direction: velocity", tr_here["V"], tr_ecc["V"], 0.00001).
LOCAL tr_moved IS conic_kepler(tr_ecc["R"], tr_ecc["V"], 1700, TR_MU).
LOCAL tr_there IS rndz_target_at(tr_ecc["R"], tr_ecc["V"], tr_moved["R"]:NORMALIZED, tr_nrm, TR_MU).
assert_vec("target at a later direction: position", tr_there["R"], tr_moved["R"], 0.01).
assert_vec("target at a later direction: velocity", tr_there["V"], tr_moved["V"], 0.00001).

LOCAL tr_late IS conic_kepler(TR_RA, TR_VA, 600, TR_MU).
assert_near("apsis time from +600 s", rndz_apsis_time(tr_late["R"], tr_late["V"], TR_MU, 1, FALSE), 2790.49, 0.1).
assert_near("apsis time from -600 s",
    rndz_apsis_time(tr_lm_early["R"], tr_lm_early["V"], TR_MU, 1, FALSE), 600, 0.1).
assert_near("apsis time, NN 2 from +600 s",
    rndz_apsis_time(tr_late["R"], tr_late["V"], TR_MU, 2, FALSE), 6180.97, 0.1).
assert_near("apsis time, NN 2 from -600 s",
    rndz_apsis_time(tr_lm_early["R"], tr_lm_early["V"], TR_MU, 2, FALSE), 3990.49, 0.1).
assert_near("forced half periods", rndz_apsis_time(tr_late["R"], tr_late["V"], TR_MU, 1, TRUE), 3390.49, 0.1).

// ---- TPI time for an elevation: the circular case's states at the nominal TPI time, shifted by an offset ----
IF tr_first["OK"] {
  FOR tr_case IN LIST(LIST(0, 6.381, -1), LIST(240, -233.619, 31.082), LIST(-600, 606.381, 18.883)) {
    LOCAL lm_now IS conic_kepler(tr_first["R3"], tr_first["V3T"], tr_case[0], TR_MU).
    LOCAL tg_now IS conic_kepler(tr_first["RT3"], tr_first["VT3"], tr_case[0], TR_MU).
    LOCAL label IS "TPI search, offset " + tr_case[0].
    IF tr_case[2] >= 0 {
      assert_near(label + ": starting elevation",
          rndz_elevation(lm_now["R"], lm_now["V"], tg_now["R"]), tr_case[2], 0.001).
    }
    LOCAL found IS rndz_tpi_time(lm_now["R"], lm_now["V"], tg_now["R"], tg_now["V"], 26.6, TR_MU).
    assert_true(label + ": solved " + found["WHY"], found["OK"]).
    assert_near(label + ": time change", found["DT"], tr_case[1], 0.05).
    assert_near(label + ": elevation found", rndz_elevation(found["RA"], found["VA"], found["RT"]), 26.6, 0.1).
  }
}

LOCAL tr_low IS tr_circular(TR_APO, 0).
LOCAL tr_high IS tr_circular(TR_APO + 20000, 8.4).
LOCAL tr_found IS rndz_tpi_time(tr_low["R"], tr_low["V"], tr_high["R"], tr_high["V"], 200, TR_MU).
assert_true("TPI elevation 200, CSM higher: geometry",
    NOT tr_found["OK"] AND tr_found["WHY"] = "geometry").
SET tr_high TO tr_circular(TR_APO + 100, 8.4).
SET tr_found TO rndz_tpi_time(tr_low["R"], tr_low["V"], tr_high["R"], tr_high["V"], 5, TR_MU).
assert_true("TPI elevation 5, CSM 100 m higher: returns (" + tr_found["WHY"] + ")", TRUE).
SET tr_found TO rndz_tpi_time(tr_low["R"], tr_low["V"], tr_low["R"], tr_low["V"], 26.6, TR_MU).
assert_true("TPI with the CSM on top of the LM fails", NOT tr_found["OK"]).
SET tr_high TO tr_circular(TR_APO, 8.4).
SET tr_found TO rndz_tpi_time(tr_low["R"], tr_low["V"], tr_high["R"], tr_high["V"], 26.6, TR_MU).
assert_true("TPI with both craft in the same circular orbit fails", NOT tr_found["OK"]).

// ---- odd inputs: an answer or an alarm, never a kOS error ----
FUNCTION tr_odd {
  PARAMETER name, inp.
  LOCAL out IS rndz_csi(inp).
  assert_true(name + ": solved or alarm 600-606 (alarm " + out["ALARM"] + ")",
      out["OK"] OR (out["ALARM"] >= 600 AND out["ALARM"] <= 606)).
}
FOR tr_change IN LIST(LIST("NN", 0), LIST("NN", 99), LIST("ELEV", 0), LIST("ELEV", 90), LIST("ELEV", 180),
    LIST("ELEV", 270), LIST("TTPI", -100)) {
  SET tr_in TO tr_input(tr_circ).
  SET tr_in[tr_change[0]] TO tr_change[1].
  tr_odd(tr_change[0] + " " + tr_change[1], tr_in).
}
SET tr_in TO tr_input(tr_circular(TR_APO, 8.4)).
SET tr_in["V1"] TO V(0, 0, SQRT(TR_MU / TR_APO)).
tr_odd("LM and CSM in the same circular orbit", tr_in).

// ---- stage 2: the transfer of P34 and P35 (states at TPI after the CSI and CDH of the circular case) ----
GLOBAL TR_TA IS V(905666.125472, 0, -1579536.104075).
GLOBAL TR_TVA IS V(1423.5500524, 0, 816.2276615).
GLOBAL TR_TT IS V(965815.662142, 0, -1576142.854300).
GLOBAL TR_TVT IS V(1388.6136673, 0, 850.9030922).

assert_near("time theta: 130 degrees of the circular CSM", conic_time_theta(TR_TT, TR_TVT, 130, TR_MU), 2575.3417, 0.01).
assert_near("time theta: zero angle", conic_time_theta(TR_TT, TR_TVT, 0, TR_MU), 0, 0.001).
SET tr_oval_pe TO TR_RADIUS + 58 * 1852.
SET tr_oval TO tr_csm(tr_oval_pe, SQRT(TR_MU * (2 / tr_oval_pe - 2 / (tr_oval_pe + TR_RADIUS + 64 * 1852))), 8.4).
assert_near("time theta: 200 degrees of an eccentric orbit", conic_time_theta(tr_oval["R"], tr_oval["V"], 200, TR_MU), 3970.3597, 0.01).
assert_true("time theta: a hyperbola gives -1", conic_time_theta(TR_RA, TR_VA * 1.6, 90, TR_MU) = -1).

SET tr_xf TO rndz_transfer(TR_TA, TR_TVA, TR_TT, TR_TVT, 2575.3417, TR_MU).
assert_true("transfer: solved (" + tr_xf["WHY"] + ")", tr_xf["OK"]).
assert_vec("transfer: delta-V", tr_xf["DV"], V(7.47049, 0, 0.43098), 0.001).
assert_vec("transfer: aim point", tr_xf["AIM"], V(586581.134, 0, 1752982.819), 1).
assert_near("transfer: intercept delta-V", tr_xf["DVTPF"], 9.61701, 0.001).
assert_near("transfer: central angle", tr_xf["ANGLE"], 131.6699, 0.001).
assert_true("transfer: not rotated", NOT tr_xf["ROTATED"]).
assert_vec("transfer: line-of-sight delta-V", rndz_los_dv(tr_xf["DV"], TR_TA, TR_TVA, TR_TT), V(7.48290, 0, 0.00953), 0.001).
// the line-of-sight axes: forward along the line, right = against the LM's orbit normal, down
SET tr_ahead TO rndz_fwd(lm_cross(TR_TA, TR_TVA):NORMALIZED, TR_TA).
SET tr_right TO -lm_cross(TR_TA, TR_TVA):NORMALIZED.
SET tr_down TO -TR_TA:NORMALIZED.
assert_vec("N59: forward, right, down",
    rndz_los_dv(tr_ahead + tr_right * 2 + tr_down * 3, TR_TA, TR_TVA, TR_TA + tr_ahead * 1000), V(1, 2, 3), 0.0001).
assert_true("transfer: no time of flight fails", NOT rndz_transfer(TR_TA, TR_TVA, TR_TT, TR_TVT, 0, TR_MU)["OK"]).

// a midcourse 900 s after a TPI with an error
SET tr_bad TO TR_TVA + tr_xf["DV"] + V(0.2, 0.3, -0.1).
SET tr_mid TO conic_kepler(TR_TA, tr_bad, 900, TR_MU).
SET tr_midt TO conic_kepler(TR_TT, TR_TVT, 900, TR_MU).
SET tr_fix TO rndz_transfer(tr_mid["R"], tr_mid["V"], tr_midt["R"], tr_midt["V"], 1675.3417, TR_MU).
assert_vec("midcourse: delta-V", tr_fix["DV"], V(-0.58154, -0.22405, 0.17317), 0.001).

// ---- stage 3: pointing and relative motion (the same cases as reference_rndz.py: up = +x, forward = +y, right = -z) ----
GLOBAL TR_POS IS V(1800000, 0, 0).
GLOBAL TR_VEL IS V(0, 1600, 0).
LOCAL tr_up IS V(1, 0, 0).
LOCAL tr_fwd_axis IS V(0, 1, 0).
// "Right" as these right-handed cases have it: fwd x up through the project's cross product.
LOCAL tr_right IS lm_cross(tr_fwd_axis, tr_up).
FUNCTION tr_theta {
  PARAMETER name, axis_vec, want.
  LOCAL got IS rndz_theta(TR_POS, TR_VEL, axis_vec:NORMALIZED).
  IF got > 359.999 { SET got TO got - 360. }
  assert_near(name, got, want, 0.001).
}
tr_theta("theta forward is 0", tr_fwd_axis, 0).
tr_theta("theta up is 90", tr_up, 90).
tr_theta("theta back is 180", -tr_fwd_axis, 180).
tr_theta("theta down is 270", -tr_up, 270).
tr_theta("theta forward and up is 45", tr_fwd_axis + tr_up, 45).
tr_theta("theta back and down is 225", -tr_fwd_axis - tr_up, 225).
tr_theta("theta 30 up and to the right is 30", tr_up * 0.5 + tr_right * SQRT(0.75), 30).
// The out-of-plane cases are built from the right-hand direction, so they hold in kOS's axes whichever way its cross product turns.
LOCAL tr_r36 IS rndz_r36(TR_POS + tr_right * 1000, TR_VEL + tr_right * 2, TR_POS, TR_VEL).
assert_near("r36 Y is 1000 m to the CSM's right", tr_r36[0], 1000, 0.01).
assert_near("r36 YDOT is 2", tr_r36[1], 2, 0.001).
assert_near("r36 psi, the CSM to the left, is 270", tr_r36[2], 270, 0.1).
LOCAL tr_ahead IS rndz_r36(TR_POS, TR_VEL, TR_POS + tr_fwd_axis * 1000, TR_VEL)[2].
IF tr_ahead > 359 { SET tr_ahead TO tr_ahead - 360. }
assert_near("r36 psi, the CSM ahead, is 0", tr_ahead, 0, 0.05).
// A hair to the left of straight ahead is 0, not 360.00 (seen in flight).
assert_near("r36 psi just left of ahead shows 0", rndz_r36(TR_POS, TR_VEL, TR_POS + tr_fwd_axis * 100000 - tr_right * 0.001, TR_VEL)[2], 0, 0).
assert_near("theta just below forward shows 0", rndz_theta(TR_POS, TR_VEL, (tr_fwd_axis - tr_up * 0.00000001):NORMALIZED), 0, 0).
assert_near("r36 psi, the CSM to the right, is 90", rndz_r36(TR_POS, TR_VEL, TR_POS + tr_right * 1000, TR_VEL)[2], 90, 0.05).
LOCAL tr_rr IS rndz_range_rate(TR_POS, TR_VEL, TR_POS + V(0, 1000, 0), V(0, 1590, 0)).
assert_near("range", tr_rr[0], 1000, 0.001).
assert_near("range rate, closing", tr_rr[1], -10, 0.0001).
assert_true("the Moon between hides the CSM", NOT rndz_los_clear(TR_POS, V(-1800000, 0, 0), 1738000)).
assert_true("a clear line of sight", rndz_los_clear(TR_POS, V(1800000, 1000, 0), 1738000)).
assert_vec("aim axis: z is left alone", rndz_aim_axis(V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)), V(0, 0, 1), 0.00001).
assert_vec("aim axis: y follows the turn", rndz_aim_axis(V(1, 0, 0), V(0, 1, 0), V(0, 1, 0)), V(-1, 0, 0), 0.00001).
assert_vec("aim axis: turned right round, unchanged", rndz_aim_axis(V(1, 0, 0), V(-1, 0, 0), V(0, 1, 0)), V(0, 1, 0), 0.00001).

test_end().
