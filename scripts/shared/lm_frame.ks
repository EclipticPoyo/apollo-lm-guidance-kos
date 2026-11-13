// lm_frame.ks -- landing-site vector, Moon spin, guidance frame (plan Task 3).
//
// Ported from Luminary 099, LUNAR_LANDING_GUIDANCE_EQUATIONS.agc:
//   TTFINCR (lines 281-283)  -> land_update
//   RGVGCALC (lines 414-422) -> rgu, vgu
//   CGCALC (lines 641-682)   -> guidance_cg
// Only land_vector and moon_spin read kOS. Everything else takes values as parameters,
// so it can be tested on the pad with made-up numbers.
//
// Naming: kOS rejects names like R, V or Q (built-in functions), so Luminary's R, V, LAND,
// WM become r_vec, v_vec, land_vec, wm_vec. Matrices (CG) are a LIST of 3 row vectors.

RUNONCEPATH("0:/lm/lm_constants.ks").

// ---- Handedness ----------------------------------------------------------
// Luminary's cross products are right-handed. kOS is left-handed, so VCRS gives the opposite
// physical direction. Multiplying by FRAME_SIGN (measured in KSP, -1) restores Luminary's meaning,
// so "WM x R" here is the same physical vector as in the AGC source.
FUNCTION lm_cross {
  PARAMETER a_vec, b_vec.
  RETURN FRAME_SIGN * VCRS(a_vec, b_vec).
}

// ---- The two functions that read kOS ---------------------------------------

// LAND: the landing site as a vector from the Moon's centre.
// LATLNG(...):ALTITUDEPOSITION(h) is the point h metres above sea level, measured from the ship
// ("ship-raw"). Subtracting SHIP:BODY:POSITION (the Moon's centre, also from the ship) moves the
// origin to the Moon's centre.
FUNCTION land_vector {
  PARAMETER lat, lng, alt_m.
  RETURN LATLNG(lat, lng):ALTITUDEPOSITION(alt_m) - SHIP:BODY:POSITION.
}

// WM: the Moon's spin vector, rad/s, built from the north pole because BODY:ANGULARVEL is
// ~23 degrees wrong in this install (TiltEm; see spec section 6).
FUNCTION moon_spin {
  LOCAL pole_vec IS LATLNG(90, 0):POSITION - SHIP:BODY:POSITION.
  RETURN pole_vec:NORMALIZED * 2 * CONSTANT:PI / SHIP:BODY:ROTATIONPERIOD.
}

// ---- Pure maths --------------------------------------------------------------

// TTFINCR: LAND = |LAND| * unit(LAND - LAND x WM * dt), the site carried round by the Moon's spin.
// Only needed when the axes do NOT turn with the Moon (AXES_ROTATE = false). Luminary's formula is
// first-order, so one step turns LAND by atan(|WM| dt), which equals |WM| dt for small steps.
// No update for dt <= 0 (e.g. a paused or backwards clock).
FUNCTION land_update {
  PARAMETER land_vec, wm_vec, dt.
  LOCAL length IS land_vec:MAG.
  IF dt <= 0 OR length = 0 { RETURN land_vec. }
  RETURN (land_vec - lm_cross(land_vec, wm_vec) * dt):NORMALIZED * length.
}

// CGCALC: the guidance frame, a matrix whose rows are the guidance axes written in kOS raw axes.
//   row 0 = unit(LAND)                  "up" at the landing site
//   row 1 = unit(aim x LAND)            horizontal, sideways
//   row 2 = row 0 x row 1               horizontal, toward the site
// where aim = LAND + lead*ANGTERM - R, the direction from the ship toward the (lead-corrected)
// landing point. Luminary's lead is TTF/8 * GAINBRAK; GAINBRAK is pad-loaded, so milestone 1 passes
// lead = 0 and milestone 2 supplies the real value (the function does not change).
// Degenerate cases never produce NaN: LAND = 0 gives the identity, and an aim that is zero or
// parallel to LAND (ship directly above the site) uses an arbitrary horizontal direction instead.
FUNCTION guidance_cg {
  PARAMETER land_vec, r_vec, angterm_vec, lead.
  IF land_vec:MAG = 0 { RETURN LIST(V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)). }
  LOCAL up_vec IS land_vec:NORMALIZED.
  LOCAL aim_vec IS land_vec + angterm_vec * lead - r_vec.
  IF lm_cross(aim_vec, up_vec):MAG <= 1e-9 * aim_vec:MAG {
    // Pick the coordinate axis least aligned with "up" so the cross product is well defined.
    IF ABS(up_vec:X) < 0.9 { SET aim_vec TO V(1, 0, 0). } ELSE { SET aim_vec TO V(0, 1, 0). }
  }
  LOCAL side_vec IS lm_cross(aim_vec, up_vec):NORMALIZED.
  RETURN LIST(up_vec, side_vec, lm_cross(up_vec, side_vec)).
}

// CG v: the matrix times a vector. Each result component is the vector's dot product with one row.
FUNCTION cg_apply {
  PARAMETER cg, vec.
  RETURN V(VDOT(cg[0], vec), VDOT(cg[1], vec), VDOT(cg[2], vec)).
}

// CG^T v: the inverse of cg_apply. A vector given in guidance axes goes back to raw axes by adding up its three
// components times the three rows (the rows are unit vectors at right angles, so the transpose is the inverse).
FUNCTION cg_unapply {
  PARAMETER cg, vec.
  RETURN cg[0] * vec:X + cg[1] * vec:Y + cg[2] * vec:Z.
}

// RGU = CG (R - LAND): position relative to the landing site, in guidance axes.
FUNCTION rgu {
  PARAMETER cg, r_vec, land_vec.
  RETURN cg_apply(cg, r_vec - land_vec).
}

// VGU = CG (V - WM x R): velocity relative to the surface, in guidance axes.
FUNCTION vgu {
  PARAMETER cg, v_vec, r_vec, wm_vec.
  RETURN cg_apply(cg, v_vec - lm_cross(wm_vec, r_vec)).
}
