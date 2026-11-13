// lm_plan.ks -- the deorbit planner's pure functions (milestone 2).
//
// Nothing here reads flight data: every function takes vectors and numbers as parameters, so the
// functions are tested on the pad against scripts/tests/reference.py (see tests/test_plan.ks).
// lm_deorbit.ks is the only script that reads the orbit and calls these.
// Equations: docs/superpowers/specs/2026-11-12-site-selection-deorbit-planner-design.md section 6.
//
// Orbit normals and "ahead" directions use plain VCRS (n = VCRS(r, v)), so they are consistent with
// each other whatever the handedness of kOS. Only the physical Moon-spin rotation uses lm_cross.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").

// ---- Spec 6A: where powered descent starts -----------------------------------
// The pad loads RIGNX, RIGNZ give the PDI position relative to the site (x up, z downrange).
// Seen from the Moon's centre the PDI point is (site_radius + RIGNX) up and RIGNZ along the ground:
//   R_PDI   its distance from the centre        ALT_PDI  its height above the body radius
//   PHI     the angle (degrees, positive) between PDI and the site, seen from the centre
FUNCTION plan_pdi_geometry {
  PARAMETER site_radius, rignx, rignz, body_radius.
  LOCAL up_part IS site_radius + rignx.
  LOCAL r_pdi IS SQRT(up_part ^ 2 + rignz ^ 2).
  RETURN LEXICON("R_PDI", r_pdi, "PHI", ARCTAN2(ABS(rignz), up_part), "ALT_PDI", r_pdi - body_radius).
}

// ---- Moon spin ------------------------------------------------------------------
// plan_spin_rotate: turn a vector about the Moon's spin axis by |WM| * dt radians, the same physical
// direction as Luminary's WM x R (cross products through lm_cross). This is the exact (Rodrigues)
// rotation, not the first-order step land_update uses, because planning steps are hours long:
//   v cos(a) + (k x v) sin(a) + k (k . v)(1 - cos(a))      k = unit(WM), a = |WM| dt
// kOS trig functions take DEGREES, so the angle is converted.
FUNCTION plan_spin_rotate {
  PARAMETER vec, wm_vec, dt.
  IF wm_vec:MAG = 0 OR dt = 0 { RETURN vec. }
  LOCAL axis_vec IS wm_vec:NORMALIZED.
  LOCAL angle_deg IS wm_vec:MAG * dt * 180 / CONSTANT:PI.
  RETURN vec * COS(angle_deg) + lm_cross(axis_vec, vec) * SIN(angle_deg)
         + axis_vec * (VDOT(axis_vec, vec) * (1 - COS(angle_deg))).
}

// plan_site_at: where the landing site is, dt seconds from now, in the axes the orbit prediction
// (POSITIONAT) uses. If those axes stay fixed while the Moon turns (PREDICT_AXES_INERTIAL, measured
// by probe_predict.ks) the site moves with the spin; otherwise it stays where it is.
FUNCTION plan_site_at {
  PARAMETER land_vec, wm_vec, dt.
  IF PREDICT_AXES_INERTIAL { RETURN plan_spin_rotate(land_vec, wm_vec, dt). }
  RETURN land_vec.
}

// ---- Spec 6B: the target plane ---------------------------------------------------
// The plane through the Moon's centre and the site that is closest to the current plane:
//   n_t = unit(n_c - (n_c . s) s)      (remove the part of n_c that points at the site)
// TILT = asin(n_c . s) is how far the site is out of the current plane (signed, degrees).
// n_cur and site_dir are unit vectors. If the site lies on the orbit's pole direction (n_c . s ~ +-1)
// every plane through the site is equally close and there is no answer: OK is false.
FUNCTION plan_target_normal {
  PARAMETER n_cur, site_dir.
  LOCAL along IS VDOT(n_cur, site_dir).
  LOCAL proj_vec IS n_cur - site_dir * along.
  IF proj_vec:MAG < 1e-6 { RETURN LEXICON("OK", FALSE, "N_T", n_cur, "TILT", 90 * (CHOOSE 1 IF along >= 0 ELSE -1)). }
  RETURN LEXICON("OK", TRUE, "N_T", proj_vec:NORMALIZED, "TILT", ARCSIN(MAX(-1, MIN(1, along)))).
}

// plan_point_ahead: the unit direction theta_deg ahead of u_vec, in the direction of travel of an
// orbit whose normal is n_unit (negative theta = behind). "Ahead" is VCRS(n, u): for n = VCRS(r, v)
// that is the direction the ship moves.
FUNCTION plan_point_ahead {
  PARAMETER n_unit, u_vec, theta_deg.
  RETURN (u_vec * COS(theta_deg) + VCRS(n_unit, u_vec):NORMALIZED * SIN(theta_deg)):NORMALIZED.
}

// plan_in_plane: the site direction projected into the plane whose normal is n_unit (used when no
// plane change is made, because the site is then slightly out of the plane).
FUNCTION plan_in_plane {
  PARAMETER site_dir, n_unit.
  RETURN (site_dir - n_unit * VDOT(site_dir, n_unit)):NORMALIZED.
}

// plan_rotate_about: vec turned by angle_deg about the unit vector axis_unit (Rodrigues, standard
// component cross product; the turning direction is whatever VCRS gives, callers pick the sign they need).
FUNCTION plan_rotate_about {
  PARAMETER vec, axis_unit, angle_deg.
  RETURN vec * COS(angle_deg) + VCRS(axis_unit, vec) * SIN(angle_deg)
         + axis_unit * (VDOT(axis_unit, vec) * (1 - COS(angle_deg))).
}

// ---- Spec 6C: plane-change burn ------------------------------------------------
// plan_plane_change: the delta-v, at a point on the line where the current and target planes cross,
// that turns the orbit normal from n_cur to n_tgt without changing the speed. At that point the
// position r_vec lies in both planes, so rotating the velocity about r_vec by the angle between the
// normals swings the orbit plane onto the target plane (a circular orbit costs 2 v sin(angle/2)).
// plan_rotate_about turns vec about axis_unit. Its turning direction (and the sign of the
// normals) is easy to get backwards, so both signs are tried and the one whose resulting normal
// VCRS(r, new_v) is closer to n_tgt is kept: the choice is made from the result, not from a convention.
FUNCTION plan_plane_change {
  PARAMETER r_vec, v_vec, n_cur, n_tgt.
  LOCAL angle IS VANG(n_cur, n_tgt).
  IF angle < 1e-9 { RETURN V(0, 0, 0). }
  LOCAL axis_vec IS r_vec:NORMALIZED.
  // Rodrigues rotation in double precision (ANGLEAXIS wraps a single-precision quaternion, which would
  // add about 1e-4 m/s of error on a 1600 m/s vector). Same formula as plan_spin_rotate, with VCRS.
  LOCAL cand_a IS plan_rotate_about(v_vec, axis_vec, angle).
  LOCAL cand_b IS plan_rotate_about(v_vec, axis_vec, -angle).
  LOCAL err_a IS (VCRS(r_vec, cand_a):NORMALIZED - n_tgt):MAG.
  LOCAL err_b IS (VCRS(r_vec, cand_b):NORMALIZED - n_tgt):MAG.
  IF err_a <= err_b { RETURN cand_a - v_vec. }
  RETURN cand_b - v_vec.
}

// ---- Spec 6D: descent orbit insertion (DOI) burn ----------------------------------
// The descent orbit has its apolune at the DOI point (radius RA = |r_doi_vec|) and its perilune at the
// PDI point (radius r_pdi), half an orbit later. With a = (RA + r_pdi) / 2 the vis-viva equation
//   v^2 = mu (2/r - 1/a)
// gives the speed needed at DOI (V_APO) and the speed the LM will have at PDI (V_PDI, to compare with
// VIGN). V_APO acts along the direction of travel perpendicular to the radius, VCRS(n, r). The burn is
// that target velocity minus the current velocity, so it also removes any radial speed the current
// orbit has there. T_HALF is half the descent orbit's period (DOI to PDI).
// If the DOI point is lower than the PDI radius (RA < r_pdi) there is no such orbit: OK is false.
FUNCTION plan_doi {
  PARAMETER r_doi_vec, v_doi_vec, n_unit, r_pdi, mu.
  LOCAL ra IS r_doi_vec:MAG.
  IF ra < r_pdi { RETURN LEXICON("OK", FALSE, "DV", V(0, 0, 0), "RA", ra). }
  LOCAL a IS (ra + r_pdi) / 2.
  LOCAL v_apo IS SQRT(mu * (2 / ra - 1 / a)).
  LOCAL target_vec IS VCRS(n_unit, r_doi_vec):NORMALIZED * v_apo.
  RETURN LEXICON("OK", TRUE, "DV", target_vec - v_doi_vec, "RA", ra, "A", a, "V_APO", v_apo,
                 "V_PDI", SQRT(mu * (2 / r_pdi - 1 / a)),
                 "T_HALF", CONSTANT:PI * SQRT(a ^ 3 / mu)).
}

// ---- Spec 7: delta-v vector <-> maneuver node components ----------------------------
// A kOS node takes three numbers in m/s: radial, normal, prograde, measured along axes that depend on
// the orbit at the node: prograde = along the velocity, normal = along r x v, radial = the third axis
// (pointing away from the Moon: VCRS(prograde, normal)). NODE_NORMAL_SIGN and NODE_RADIAL_SIGN
// (measured by probe_predict.ks) say which way kOS counts positive. lm_deorbit.ks also compares the
// node's BURNVECTOR with the intended vector after ADD, as a runtime check of this conversion.
FUNCTION plan_node_axes {
  PARAMETER r_vec, v_vec.
  LOCAL pro_vec IS v_vec:NORMALIZED.
  LOCAL nrm_vec IS VCRS(r_vec, v_vec):NORMALIZED.
  RETURN LIST(VCRS(pro_vec, nrm_vec):NORMALIZED * NODE_RADIAL_SIGN, nrm_vec * NODE_NORMAL_SIGN, pro_vec).
}

FUNCTION plan_node_components {
  PARAMETER dv_vec, r_vec, v_vec.
  LOCAL axes IS plan_node_axes(r_vec, v_vec).
  RETURN LEXICON("RADIAL", VDOT(dv_vec, axes[0]), "NORMAL", VDOT(dv_vec, axes[1]), "PROGRADE", VDOT(dv_vec, axes[2])).
}

FUNCTION plan_components_to_dv {
  PARAMETER rad_comp, nrm_comp, pro_comp, r_vec, v_vec.
  LOCAL axes IS plan_node_axes(r_vec, v_vec).
  RETURN axes[0] * rad_comp + axes[1] * nrm_comp + axes[2] * pro_comp.
}

// ---- Spec 6E: when does the orbit pass a given direction? ----------------------------
// plan_phase: the signed angle (degrees, -180..180) of the position pos_vec measured from ref_dir
// in the plane with normal n_unit. Negative while the ship is still behind ref_dir (in the direction of
// travel), zero at the reference, positive after it. So as the ship moves forward the phase goes
// from negative to positive: that change of sign marks a pass.
FUNCTION plan_phase {
  PARAMETER pos_vec, n_unit, ref_dir.
  RETURN ARCTAN2(VDOT(pos_vec, VCRS(n_unit, ref_dir)), VDOT(pos_vec, ref_dir)).
}

// plan_find_pass: the first UT in [t_from, t_from + t_span] at which the orbit passes ref_dir, or -1.
// pos_at is a delegate (pos_at:CALL(t) = Moon-centred position at UT t). lm_deorbit.ks passes one that
// wraps POSITIONAT, so the search follows kOS's own orbit prediction and no Kepler solver is needed.
// 36 equal steps look for a change of sign from <= 0 to > 0; both samples must be within 90 degrees of
// the reference so the jump from +180 to -180 behind the planet is not mistaken for a pass. The
// bracket is then halved 40 times (an error far below a millisecond).
FUNCTION plan_find_pass {
  PARAMETER pos_at, n_unit, ref_dir, t_from, t_span.
  LOCAL steps IS 36.
  LOCAL t_prev IS t_from.
  LOCAL ph_prev IS plan_phase(pos_at:CALL(t_prev), n_unit, ref_dir).
  FROM { LOCAL i IS 1. } UNTIL i > steps STEP { SET i TO i + 1. } DO {
    LOCAL t_now IS t_from + t_span * i / steps.
    LOCAL ph_now IS plan_phase(pos_at:CALL(t_now), n_unit, ref_dir).
    IF ph_prev <= 0 AND ph_now > 0 AND ph_prev > -90 AND ph_now < 90 {
      LOCAL lo IS t_prev.
      LOCAL hi IS t_now.
      FROM { LOCAL k IS 0. } UNTIL k >= 40 STEP { SET k TO k + 1. } DO {
        LOCAL mid IS (lo + hi) / 2.
        IF plan_phase(pos_at:CALL(mid), n_unit, ref_dir) <= 0 { SET lo TO mid. } ELSE { SET hi TO mid. }
      }
      RETURN (lo + hi) / 2.
    }
    SET t_prev TO t_now.
    SET ph_prev TO ph_now.
  }
  RETURN -1.
}

// ---- The plan file -------------------------------------------------------------------
// lm_deorbit.ks writes the plan so later programmes (P63) can read it. Keys: SITE_LAT, SITE_LNG,
// SITE_ALT, T_MADE (UT the plan was made), T_DOI, T_PDI, T_LAND, T_PC (-1 when no plane change),
// DV_DOI, DV_PC (m/s), V_PDI (m/s), ALT_PDI (m), WINDOW_MODE ("UP" or "KEEP": the crew window in P63, chosen in the planner window).
// WRITEJSON/READJSON store a LEXICON as JSON text. The old file is deleted first so a failed write
// never leaves a stale plan looking valid.
FUNCTION plan_write {
  PARAMETER path_str, plan_lex.
  IF EXISTS(path_str) { DELETEPATH(path_str). }
  WRITEJSON(plan_lex, path_str).
}

// plan_read: the stored plan, or FALSE when there is no file.
FUNCTION plan_read {
  PARAMETER path_str.
  IF NOT EXISTS(path_str) { RETURN FALSE. }
  RETURN READJSON(path_str).
}

// plan_is_stale: the Moon keeps turning, so an old plan no longer points at the site. True when the
// plan is older than max_age seconds, or has no made-at time.
FUNCTION plan_is_stale {
  PARAMETER plan_lex, now_s, max_age.
  IF NOT plan_lex:HASKEY("T_MADE") { RETURN TRUE. }
  RETURN now_s - plan_lex["T_MADE"] > max_age.
}
