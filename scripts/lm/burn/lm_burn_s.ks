// lm_burn_s.ks -- the burn maths of Luminary's P40-P47 (S40.x routines), P41SPOT and the apsides of P30 (release 1.4).
//
// Pure functions: nothing here reads the ship. Vectors are in the same raw axes as the rest of the project, SI units
// (m, m/s, s, kg, N). The numbers are checked against scripts/tests/reference_burn.py by tests/test_burn.ks.
// Source: Luminary 099, P40-P47.agc ("P4:") and P34-35_P74-75.agc; constants in CONTROLLED_CONSTANTS.agc ("CC:"), see lm_constants.ks.
// Not modelled (documented departure): the finite-burn correction of S40.1 (thrust is treated as impulsive at TIG).

RUNONCEPATH("0:/lm/lm_constants.ks").

// s40_1: thrust direction and velocity to be gained at TIG (Luminary S40.1, P4:662-740). Luminary rotates DELVSIN
// by the finite-burn angle THETAT; we leave it out, so VG is the delta-V vector and UT is its unit vector. DELVREF (the delta-V
// measured over the last servicer pass) starts as zero; the burn engine replaces it each pass.
FUNCTION s40_1 {
  PARAMETER delvsin_vec.
  LOCAL vg_mag IS delvsin_vec:MAG.
  LOCAL ut_vec IS V(0, 0, 0).
  IF vg_mag > 0 { SET ut_vec TO delvsin_vec / vg_mag. }
  RETURN LEXICON("VG", delvsin_vec, "UT", ut_vec, "VGMAG", vg_mag, "DELVREF", V(0, 0, 0)).
}

// s40_2_3: the preferred burn orientation (Luminary S40.2,3, P4:825-860). The thrust axis X is UT; Y is unit(UT x RTIG), or
// unit(UT x VTIG) when UT x RTIG is small (FIXY, P4:858-860: here under 1e-3 of the product of the lengths); Z = X x Y
// (P4:839-845: "ZSCREF = - (YSCREF X XSCREF) = + (XSCREF X YSCREF)"). There is no window-face choice: the roll follows from the rule.
FUNCTION s40_2_3 {
  PARAMETER ut_vec, rtig_vec, vtig_vec.
  // No thrust direction (VG = 0): return zero axes instead of dividing by zero; the caller must not steer on them.
  IF ut_vec:MAG < 1e-9 { RETURN LEXICON("X", V(0, 0, 0), "Y", V(0, 0, 0), "Z", V(0, 0, 0)). }
  LOCAL x_axis IS ut_vec:NORMALIZED.
  LOCAL cross_vec IS VCRS(x_axis, rtig_vec).
  IF cross_vec:MAG < 1e-3 * rtig_vec:MAG { SET cross_vec TO VCRS(x_axis, vtig_vec). }
  LOCAL y_axis IS cross_vec:NORMALIZED.
  RETURN LEXICON("X", x_axis, "Y", y_axis, "Z", VCRS(x_axis, y_axis)).
}

// s40_13: burn time at the 10 percent thrust level and the throttle flags (Luminary S40.13, P4:1000-1111; 210 differences from
// 210 P40-P47.agc:1040-1043, 1111-1120). VG is first reduced by the delta-V the ullage jets give (099: 4 s of 2 jets, FRCS2; 210: 6.5 s
// of 4 jets, FRCS4, P4:1005-1010); the burn time is mass x VG / 4671 N (S40.136, P4:1040-1044). NOTHROTL (no throttle-up) is set for
// a burn of 6 s or more and under 95 s (6SEC + 89SECS, S40.127 / S40.138). IMPULSE is a burn under 6 s (S40.132); 099 leaves
// NOTHROTL clear then, 210 sets it too (research 14). A VG that the ullage covers gives a burn time of 0 (no divide).
FUNCTION s40_13 {
  PARAMETER mass_kg, vg_mag, profile.
  LOCAL ullage_dv IS 0.
  IF mass_kg > 0 {
    IF profile = "J" { SET ullage_dv TO ULLAGE4_S * RCS_ULLAGE4_N / mass_kg. } ELSE { SET ullage_dv TO ULLAGE2_S * RCS_ULLAGE2_N / mass_kg. }
  }
  LOCAL vg_corrected IS vg_mag - ullage_dv.
  LOCAL burn_s IS 0.
  IF vg_corrected > 0 { SET burn_s TO mass_kg * vg_corrected / BURN_THRUST_10PCT_N. }
  LOCAL impulse_flag IS burn_s < BURN_IMPULSE_S.
  LOCAL nothrotl_flag IS burn_s < BURN_NOTHROTL_S.
  IF profile <> "J" AND impulse_flag { SET nothrotl_flag TO FALSE. }
  RETURN LEXICON("BURN_S", burn_s, "NOTHROTL", nothrotl_flag, "IMPULSE", impulse_flag).
}

// s40_8: VG update and time to go (Luminary S40.8, P4:904-961). vg_vec is the previous VG (VGPREV), delvref_vec the delta-V measured
// in the last servicer pass (DELVREF, BURN_PASS_S seconds). New VG = VGPREV - DELVREF. With dv the part of VG along DELVREF and
// a = |DELVREF| / pass the measured acceleration, the time to go is  pass * dv / |DELVREF| * (1 - dv / (2 vex)) + tdecay:
// the burn time at the measured acceleration, corrected to first order for the acceleration rising as the propellant is used
// (the source line "DAD DPHALF" is the 1/2 + x term, x = -dv / (4 vex) in its scaling), plus the tail-off (negative).
// ALARM 1407 when VG and DELVREF are more than 90 degrees apart (the source header: "IF VG . DELVREF IS NEGATIVE"), or DELVREF is zero:
// the TGO update is skipped (TGO comes back as -1 = keep the old one), steering goes on, no cutoff is sent.
// STEER is false and IMPULSE true when TGO is under 4 s (P4:944-949: IMPULSW set, STEERSW cleared; the cutoff then runs on the timer).
FUNCTION s40_8 {
  PARAMETER vg_vec, delvref_vec, tdecay_s, vex.
  RETURN s40_8_pass(vg_vec, delvref_vec, BURN_PASS_S, tdecay_s, vex).
}

// s40_8_pass: s40_8 for a pass that lasted pass_s seconds (the programme's loop does not fall exactly on the 2 s of the servicer, so it
// measures the delta-V over the time that really passed). Same maths, with pass_s in place of BURN_PASS_S.
FUNCTION s40_8_pass {
  PARAMETER vg_vec, delvref_vec, pass_s, tdecay_s, vex.
  LOCAL new_vg IS vg_vec - delvref_vec.
  LOCAL ref_mag IS delvref_vec:MAG.
  IF ref_mag <= 0 OR VDOT(new_vg, delvref_vec) <= 0 {
    RETURN LEXICON("VG", new_vg, "TGO", -1, "ALARM", 1407, "STEER", TRUE, "IMPULSE", FALSE).
  }
  LOCAL dv_along IS VDOT(new_vg, delvref_vec) / ref_mag.
  LOCAL tgo_s IS pass_s * dv_along / ref_mag * (1 - dv_along / (2 * vex)) + tdecay_s.
  LOCAL steer_flag IS tgo_s >= BURN_STEER_STOP_S.
  RETURN LEXICON("VG", new_vg, "TGO", tgo_s, "ALARM", 0, "STEER", steer_flag, "IMPULSE", NOT steer_flag).
}

// s41_1: VG (or any vector) in the current body axes (Luminary S41.1, P4:1467-1471: REFSMMAT, then the CDU angles). Here the ship's own
// facing does it: X along the nose (the thrust axis), Y starboard, Z top. The Y and Z mapping to the LM's own Y and Z is a placeholder
// until the burn display is flown (the burn programmes show N85/N83 from this).
FUNCTION s41_1 {
  PARAMETER vg_vec, facing_dir.
  RETURN V(VDOT(vg_vec, facing_dir:FOREVECTOR), VDOT(vg_vec, facing_dir:STARVECTOR), VDOT(vg_vec, facing_dir:TOPVECTOR)).
}

// p41spot: the TIG timing check (Luminary P41SPOT, BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc:188-221; NOTIME and alarm 1703, INTEGRATION_INITIALIZATION.agc:1015-1025; the stale "45 s" in the P40-P47.agc header comment is not what the code does). The servicer must start at TIG - 29.9 s. If that is
// earlier than now + 20 s (TIMEDELT), or TIG is already past, alarm 1703 and TIG is set automatically to now + 49.9 s (no response).
FUNCTION p41spot {
  PARAMETER tig_ut, now_ut.
  IF tig_ut - TIG_TDEC1_S < now_ut + TIG_SLIP_MIN_S {
    RETURN LEXICON("TIG", now_ut + TIG_SLIP_AHEAD_S, "SLIPPED", TRUE, "ALARM", 1703).
  }
  RETURN LEXICON("TIG", tig_ut, "SLIPPED", FALSE, "ALARM", 0).
}

// p30_apsides: apogee and perigee altitudes (m above radius) of the orbit through r_vec with velocity v_vec + dv_vec (Luminary
// PERIAPO1 on VTIG + DELVSIN, P30 N42; each capped at 9999.9 nmi). With h = |r x v|, energy E = v^2/2 - mu/r and eccentricity
// e = sqrt(1 + 2 E h^2 / mu^2) the apsides are at radii h^2/mu / (1 - e) and h^2/mu / (1 + e). At or above escape energy the apogee is the cap.
FUNCTION p30_apsides {
  PARAMETER r_vec, v_vec, dv_vec, mu, radius.
  LOCAL v_new IS v_vec + dv_vec.
  LOCAL h_val IS VCRS(r_vec, v_new):MAG.
  LOCAL energy IS v_new:SQRMAGNITUDE / 2 - mu / r_vec:MAG.
  LOCAL cap_m IS APSIDE_CAP_NM * M_PER_NM.
  LOCAL ecc IS SQRT(MAX(0, 1 + 2 * energy * h_val * h_val / (mu * mu))).
  LOCAL semi_p IS h_val * h_val / mu.
  LOCAL apo_m IS cap_m.
  IF energy < 0 AND ecc < 1 { SET apo_m TO MIN(cap_m, semi_p / (1 - ecc) - radius). }
  RETURN LEXICON("APO_M", apo_m, "PERI_M", MIN(cap_m, semi_p / (1 + ecc) - radius)).
}

// s30_tff: the time of free fall (Luminary CALCTFF, R30.agc): seconds until the path next comes DOWN through limit_radius, or -1 when it never does
// (perigee at or above it, or no closed orbit) or the ship is already below it. Two-body: the time between the two true anomalies by Kepler's equation.
FUNCTION s30_tff {
  PARAMETER r_vec, v_vec, mu, limit_radius.
  LOCAL r_mag IS r_vec:MAG.
  IF r_mag < limit_radius { RETURN -1. }
  LOCAL energy IS v_vec:SQRMAGNITUDE / 2 - mu / r_mag.
  IF energy >= 0 { RETURN -1. }
  LOCAL semi_p IS VCRS(r_vec, v_vec):SQRMAGNITUDE / mu.
  LOCAL semi_a IS -mu / (2 * energy).
  LOCAL ecc IS SQRT(MAX(0, 1 - semi_p / semi_a)).
  IF ecc < 1e-9 OR semi_a * (1 - ecc) >= limit_radius { RETURN -1. }
  // True anomaly now (rising from perigee: 0 to 180) and at the descending crossing of the limit radius (180 to 360), degrees.
  LOCAL nu_now IS ARCCOS(MAX(-1, MIN(1, (semi_p / r_mag - 1) / ecc))).
  IF VDOT(r_vec, v_vec) < 0 { SET nu_now TO 360 - nu_now. }
  LOCAL nu_cross IS 360 - ARCCOS(MAX(-1, MIN(1, (semi_p / limit_radius - 1) / ecc))).
  LOCAL mean_rate IS SQRT(mu / semi_a ^ 3).                // radians per second
  LOCAL gap_rad IS s30_mean_anomaly(nu_cross, ecc) - s30_mean_anomaly(nu_now, ecc).
  LOCAL two_pi IS 2 * CONSTANT:PI.
  IF gap_rad < 0 { SET gap_rad TO gap_rad + two_pi. }
  RETURN gap_rad / mean_rate.
}

// s30_mean_anomaly: the mean anomaly (radians, -pi to pi) at true anomaly nu_deg on an ellipse of eccentricity ecc.
FUNCTION s30_mean_anomaly {
  PARAMETER nu_deg, ecc.
  LOCAL ecc_deg IS 2 * ARCTAN2(SQRT(1 - ecc) * SIN(nu_deg / 2), SQRT(1 + ecc) * COS(nu_deg / 2)).
  IF ecc_deg > 180 { SET ecc_deg TO ecc_deg - 360. }
  IF ecc_deg < -180 { SET ecc_deg TO ecc_deg + 360. }
  RETURN ecc_deg * CONSTANT:DEGTORAD - ecc * SIN(ecc_deg).
}

// p30_mga: the middle gimbal angle shown by N45 R3, degrees (Luminary GET+MGA, P34-35_P74-75.agc:1406-1415): arcsin of the unit thrust
// direction dotted with the reference Y axis; a negative angle has one revolution added (two HALFREV adds). We have no gimbals: the
// caller passes an assumed reference Y axis (design call 4).
FUNCTION p30_mga {
  PARAMETER ut_vec, ref_y_vec.
  LOCAL dot_val IS MAX(-1, MIN(1, VDOT(ut_vec:NORMALIZED, ref_y_vec:NORMALIZED))).
  LOCAL ang IS ARCSIN(dot_val).
  IF ang < 0 { SET ang TO ang + 360. }
  // A tiny negative angle (a burn exactly in the orbit plane, rounding noise) plus 360 would show as +36000 (360.00 degrees, the same as 0):
  // anything that rounds to 360.00 on the display is zero. A departure from Luminary, which would show the same noise as 35999 or 36000.
  IF ang >= 359.995 { SET ang TO 0. }
  RETURN ang.
}
