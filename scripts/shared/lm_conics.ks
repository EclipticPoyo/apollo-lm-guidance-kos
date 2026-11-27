// lm_conics.ks -- conic (two-body) orbit maths for rendezvous targeting. Pure: reads nothing from kOS but constants.
//
// Vectors are in any non-rotating axes with the origin at the body's centre; mu_val is the body's GM (m^3/s^2).
// Luminary does this with the Conic Subroutines (KEPLER, INITV and so on); this is the same universal-variable
// method written for kOS, not a port. Reference model: scripts/tests/reference_rndz.py.
//
// kOS trig takes DEGREES, and kOS has no COSH or SINH, so they are built from CONSTANT:E.

RUNONCEPATH("0:/shared/lm_frame.ks").

// conic_stumpff: the two Stumpff functions c(z) and s(z) as LIST(c, s). z = alpha * chi^2 is positive for an
// ellipse and negative for a hyperbola. Near zero both formulas are 0/0, so a short series is used.
FUNCTION conic_stumpff {
  PARAMETER z.
  IF z > 0.000001 {
    LOCAL root IS SQRT(z).
    LOCAL root_deg IS root * CONSTANT:RADTODEG.
    RETURN LIST((1 - COS(root_deg)) / z, (root - SIN(root_deg)) / (root * z)).
  }
  IF z < -0.000001 {
    LOCAL root IS SQRT(-z).
    LOCAL grow IS CONSTANT:E ^ root.
    LOCAL cosh_val IS (grow + 1 / grow) / 2.
    LOCAL sinh_val IS (grow - 1 / grow) / 2.
    RETURN LIST((cosh_val - 1) / (-z), (sinh_val - root) / (root * (-z))).
  }
  RETURN LIST(0.5 - z / 24, 1 / 6 - z / 120).
}

// conic_kepler_f: Kepler's equation in the universal anomaly chi, as LIST(value, slope). The value rises steadily
// with chi (the slope is the radius there), and is zero at the answer. For z < -2500 the exponentials would
// overflow, so the function is reported as huge with the sign of chi, and slope 0 (the caller then bisects).
FUNCTION conic_kepler_f {
  PARAMETER chi, alpha, r0_mag, rv_term, time_term.
  LOCAL z_val IS alpha * chi * chi.
  IF z_val < -2500 {
    IF chi < 0 { RETURN LIST(-1e30, 0). }
    RETURN LIST(1e30, 0).
  }
  LOCAL cs IS conic_stumpff(z_val).
  LOCAL value IS rv_term * chi * chi * cs[0] + (1 - alpha * r0_mag) * chi ^ 3 * cs[1] + r0_mag * chi - time_term.
  LOCAL slope IS rv_term * chi * (1 - z_val * cs[1]) + (1 - alpha * r0_mag) * chi * chi * cs[0] + r0_mag.
  RETURN LIST(value, slope).
}

// conic_kepler: the state dt seconds later (dt may be negative), for any conic.
// Returns LEXICON("OK", "R", "V", "PASSES"). On failure OK is FALSE and R, V are the inputs.
// Method: bracket the root of Kepler's equation between 0 and a first guess (doubled until it passes the root),
// then Newton's method, falling back to bisection whenever a Newton step would leave the bracket.
FUNCTION conic_kepler {
  PARAMETER pos0, vel0, dt, mu_val.
  LOCAL failed IS LEXICON("OK", FALSE, "R", pos0, "V", vel0, "PASSES", 0).
  LOCAL r0_mag IS pos0:MAG.
  IF r0_mag <= 0 OR mu_val <= 0 { RETURN failed. }
  IF dt = 0 { RETURN LEXICON("OK", TRUE, "R", pos0, "V", vel0, "PASSES", 0). }
  LOCAL root_mu IS SQRT(mu_val).
  LOCAL rv_term IS VDOT(pos0, vel0) / root_mu.
  LOCAL alpha IS 2 / r0_mag - vel0:SQRMAGNITUDE / mu_val.         // 1 / semi-major axis; <= 0 when not an ellipse
  LOCAL time_term IS root_mu * dt.

  LOCAL far_chi IS root_mu * ABS(dt) / r0_mag.
  IF alpha > 0 { SET far_chi TO root_mu * alpha * ABS(dt). }
  IF far_chi < 1 { SET far_chi TO 1. }
  IF dt < 0 { SET far_chi TO -far_chi. }
  LOCAL near_chi IS 0.
  LOCAL doublings IS 0.
  UNTIL conic_kepler_f(far_chi, alpha, r0_mag, rv_term, time_term)[0] * dt >= 0 {
    IF doublings >= 100 { RETURN failed. }
    SET near_chi TO far_chi.
    SET far_chi TO far_chi * 2.
    SET doublings TO doublings + 1.
  }

  LOCAL low IS MIN(near_chi, far_chi).
  LOCAL high IS MAX(near_chi, far_chi).
  LOCAL chi IS far_chi.
  LOCAL passes IS 0.
  LOCAL done IS FALSE.
  UNTIL done OR passes >= 80 {
    SET passes TO passes + 1.
    LOCAL fs IS conic_kepler_f(chi, alpha, r0_mag, rv_term, time_term).
    IF fs[0] > 0 { SET high TO chi. } ELSE { SET low TO chi. }
    IF fs[1] > 0 AND ABS(fs[0]) < 0.000001 * fs[1] {
      SET chi TO chi - fs[0] / fs[1].
      SET done TO TRUE.
    } ELSE {
      LOCAL trial IS low.
      IF fs[1] > 0 { SET trial TO chi - fs[0] / fs[1]. }
      IF trial <= low OR trial >= high { SET trial TO (low + high) / 2. }
      SET done TO ABS(trial - chi) < 0.000001.
      SET chi TO trial.
    }
  }
  IF NOT done { RETURN failed. }

  // The f and g functions: the new state is a mix of the old position and velocity.
  LOCAL z_val IS alpha * chi * chi.
  LOCAL cs IS conic_stumpff(z_val).
  LOCAL pos1 IS pos0 * (1 - chi * chi / r0_mag * cs[0]) + vel0 * (dt - chi ^ 3 * cs[1] / root_mu).
  LOCAL r1_mag IS pos1:MAG.
  IF r1_mag <= 0 { RETURN failed. }
  LOCAL vel1 IS pos0 * (root_mu / (r1_mag * r0_mag) * chi * (z_val * cs[1] - 1))
      + vel0 * (1 - chi * chi / r1_mag * cs[0]).
  RETURN LEXICON("OK", TRUE, "R", pos1, "V", vel1, "PASSES", passes).
}

// conic_elements: the shape of the orbit as seen from the present point.
//   P     semi-latus rectum, m          EC    e * cos(true anomaly)      ES     e * sin(true anomaly)
//   ECC   eccentricity                  ALPHA 1 / semi-major axis        RDOT   radial speed, m/s (+ = rising)
// A zero radius gives all zeros.
FUNCTION conic_elements {
  PARAMETER pos_vec, vel_vec, mu_val.
  LOCAL r_mag IS pos_vec:MAG.
  IF r_mag <= 0 OR mu_val <= 0 { RETURN LEXICON("P", 0, "EC", 0, "ES", 0, "ECC", 0, "ALPHA", 0, "RDOT", 0). }
  LOCAL semi_latus IS lm_cross(pos_vec, vel_vec):SQRMAGNITUDE / mu_val.
  LOCAL ecos IS semi_latus / r_mag - 1.
  LOCAL rdot IS VDOT(pos_vec, vel_vec) / r_mag.
  LOCAL esin IS rdot * SQRT(semi_latus / mu_val).
  RETURN LEXICON("P", semi_latus, "EC", ecos, "ES", esin, "ECC", SQRT(ecos * ecos + esin * esin),
      "ALPHA", 2 / r_mag - vel_vec:SQRMAGNITUDE / mu_val, "RDOT", rdot).
}

// conic_time_from_peri: seconds from periapsis to the true anomaly whose sine and cosine are given (negative
// before periapsis), for an ellipse of eccentricity ecc < 1 and semi-major axis sma.
// E is the eccentric anomaly; Kepler's equation M = E - e sin E gives the time.
FUNCTION conic_time_from_peri {
  PARAMETER ecc, sin_f, cos_f, sma, mu_val.
  LOCAL ecc_deg IS ARCTAN2(SQRT(MAX(0, 1 - ecc * ecc)) * sin_f, ecc + cos_f).
  LOCAL mean_rad IS ecc_deg * CONSTANT:DEGTORAD - ecc * SIN(ecc_deg).
  RETURN mean_rad * SQRT(sma ^ 3 / mu_val).
}

// conic_time_to_apo: seconds to the next apoapsis, in (0, period]. A nearly circular orbit (ECC < 0.0001) has no
// useful apoapsis, so half a period is returned. -1 when the orbit is not an ellipse.
FUNCTION conic_time_to_apo {
  PARAMETER pos_vec, vel_vec, mu_val.
  LOCAL el IS conic_elements(pos_vec, vel_vec, mu_val).
  IF el["ALPHA"] <= 0 { RETURN -1. }
  LOCAL sma IS 1 / el["ALPHA"].
  LOCAL half IS CONSTANT:PI * SQRT(sma ^ 3 / mu_val).
  IF el["ECC"] < 0.0001 { RETURN half. }
  LOCAL left IS half - conic_time_from_peri(el["ECC"], el["ES"] / el["ECC"], el["EC"] / el["ECC"], sma, mu_val).
  IF left <= 0 { SET left TO left + 2 * half. }
  RETURN left.
}

// conic_time_theta: seconds to sweep angle_deg (0 to under 360) of true anomaly from this state (Luminary TIMETHET,
// which gives P34 the intercept time from the central angle). -1 when the orbit is not an ellipse.
// The present true anomaly comes from (e cos f, e sin f); a circular orbit has none, and any start serves.
FUNCTION conic_time_theta {
  PARAMETER pos_vec, vel_vec, angle_deg, mu_val.
  LOCAL el IS conic_elements(pos_vec, vel_vec, mu_val).
  IF el["ALPHA"] <= 0 { RETURN -1. }
  LOCAL sma IS 1 / el["ALPHA"].
  LOCAL start_f IS ARCTAN2(el["ES"], el["EC"]).
  LOCAL end_f IS start_f + angle_deg.
  LOCAL gap IS conic_time_from_peri(el["ECC"], SIN(end_f), COS(end_f), sma, mu_val)
      - conic_time_from_peri(el["ECC"], SIN(start_f), COS(start_f), sma, mu_val).
  IF gap < -0.000001 { SET gap TO gap + 2 * CONSTANT:PI * SQRT(sma ^ 3 / mu_val). }       // past periapsis the other way
  RETURN MAX(0, gap).
}

// ---- Lambert: the orbit between two points ------------------------------------

// conic_lambert_curve: the time equation at z, as LIST(f, y, c, s). f is zero when the orbit with that z takes
// the wanted time (time_term = SQRT(mu) * time), and rises with z. y is a length that must be positive; where it
// is not, f counts as negative (z is too low).
FUNCTION conic_lambert_curve {
  PARAMETER z_val, r_sum, big_a, time_term.
  LOCAL cs IS conic_stumpff(z_val).
  IF cs[0] <= 0 { RETURN LIST(1e30, 0, cs[0], cs[1]). }
  LOCAL y_val IS r_sum + big_a * (z_val * cs[1] - 1) / SQRT(cs[0]).
  IF y_val < 0 { RETURN LIST(-1e30, y_val, cs[0], cs[1]). }
  RETURN LIST((y_val / cs[0]) ^ 1.5 * cs[1] + big_a * SQRT(y_val) - time_term, y_val, cs[0], cs[1]).
}

// conic_lambert_result: the answer of conic_lambert. An empty reason means solved.
FUNCTION conic_lambert_result {
  PARAMETER why, vel1, vel2, aim, rotated, theta.
  RETURN LEXICON("OK", why = "", "WHY", why, "V1", vel1, "V2", vel2, "AIM", aim, "ROTATED", rotated,
      "ANGLE", theta).
}

// conic_lambert: the velocity that carries a craft from pos1 to pos2 in tof_s seconds (less than one revolution).
// vref is the present velocity; it only fixes the direction of travel (and the plane near 180 degrees).
// cone_deg is INITVEL's E4 (Luminary 210): within that many degrees of a 180 degree transfer the plane through
// pos1 and pos2 is badly defined, so the target is first turned into the plane of pos1 and vref.
// Returns LEXICON("OK", "WHY", "V1", "V2", "AIM", "ROTATED", "ANGLE"): V1 and V2 are the velocities at the start
// and the end, AIM the point really aimed at, ANGLE the transfer angle in degrees. WHY is "" when solved, else
// "input", "time", "direction", "geometry", "bracket", "conic" or "miss".
// Method (our own universal-variable one, not the AGC's iteration): bisect z in the time equation.
FUNCTION conic_lambert {
  PARAMETER pos1, pos2, tof_s, mu_val, vref, cone_deg.
  LOCAL none IS V(0, 0, 0).
  LOCAL r1_mag IS pos1:MAG.
  IF r1_mag <= 0 OR pos2:MAG <= 0 OR mu_val <= 0 { RETURN conic_lambert_result("input", none, none, pos2, FALSE, 0). }
  IF tof_s <= 0 { RETURN conic_lambert_result("time", none, none, pos2, FALSE, 0). }

  // Unit vectors are made from the length: NORMALIZED returns zero for very short vectors. Multiply by 1 / length,
  // never vector / number: kOS 1.6.0.1 rounds the result of that to single precision (a 4 cm miss here).
  LOCAL u1 IS pos1 * (1 / r1_mag).
  LOCAL ahead IS vref - u1 * VDOT(vref, u1).             // the part of vref across the radius
  IF ahead:MAG < 0.000001 { RETURN conic_lambert_result("direction", none, none, pos2, FALSE, 0). }
  SET ahead TO ahead * (1 / ahead:MAG).
  LOCAL u2 IS pos2 * (1 / pos2:MAG).
  LOCAL side IS u2 - u1 * VDOT(u2, u1).                  // length = sine of the angle between the points
  LOCAL between IS ARCTAN2(side:MAG, VDOT(u2, u1)).      // 0 to 180

  LOCAL aim IS pos2.
  LOCAL rotated IS FALSE.
  LOCAL theta IS between.
  LOCAL tdir IS ahead.                                   // direction of travel at the start, across the radius
  IF ABS(180 - between) < cone_deg {
    LOCAL nrm IS lm_cross(u1, ahead).
    LOCAL flat IS pos2 - nrm * VDOT(pos2, nrm).
    IF flat:MAG < 0.000001 { RETURN conic_lambert_result("geometry", none, none, pos2, FALSE, 0). }
    SET aim TO flat * (pos2:MAG / flat:MAG).
    SET rotated TO TRUE.
    SET theta TO ARCTAN2(VDOT(aim, ahead), VDOT(aim, u1)).
    IF theta < 0 { SET theta TO theta + 360. }
  } ELSE {
    IF side:MAG < 0.000001 { RETURN conic_lambert_result("geometry", none, none, pos2, FALSE, between). }
    SET tdir TO side * (1 / side:MAG).
    IF VDOT(side, ahead) < 0 {                           // the long way round
      SET theta TO 360 - between.
      SET tdir TO -tdir.
    }
  }
  LOCAL turn IS 1 - COS(theta).
  IF turn < 0.00000001 { RETURN conic_lambert_result("geometry", none, none, aim, rotated, theta). }

  LOCAL r2_mag IS aim:MAG.
  LOCAL r_sum IS r1_mag + r2_mag.
  LOCAL big_a IS SIN(theta) * SQRT(r1_mag * r2_mag / turn).
  LOCAL root_mu IS SQRT(mu_val).
  LOCAL time_term IS root_mu * tof_s.

  // z runs from hyperbolas (negative) to just under one full revolution (4 pi^2).
  LOCAL high IS 4 * CONSTANT:PI ^ 2 - 0.0001.
  LOCAL low IS -4 * CONSTANT:PI ^ 2.
  UNTIL low <= -2500 OR conic_lambert_curve(low, r_sum, big_a, time_term)[0] <= 0 { SET low TO MAX(low * 2, -2500). }
  IF conic_lambert_curve(low, r_sum, big_a, time_term)[0] > 0
      OR conic_lambert_curve(high, r_sum, big_a, time_term)[0] < 0 {
    RETURN conic_lambert_result("bracket", none, none, aim, rotated, theta).
  }
  LOCAL passes IS 0.
  UNTIL passes >= 100 OR high - low < 0.00000000001 {
    LOCAL mid IS (low + high) / 2.
    IF conic_lambert_curve(mid, r_sum, big_a, time_term)[0] < 0 { SET low TO mid. } ELSE { SET high TO mid. }
    SET passes TO passes + 1.
  }

  LOCAL z_val IS (low + high) / 2.
  LOCAL curve IS conic_lambert_curve(z_val, r_sum, big_a, time_term).
  LOCAL y_val IS curve[1].
  IF y_val <= 0 { RETURN conic_lambert_result("bracket", none, none, aim, rotated, theta). }
  LOCAL chi IS SQRT(y_val / curve[2]).
  LOCAL alpha IS z_val / (chi * chi).
  // Radial part from Kepler's equation (r1 . v1); sideways part from the semi-latus rectum. Good at 180 too.
  LOCAL rv_dot IS root_mu * (time_term - (1 - alpha * r1_mag) * chi ^ 3 * curve[3] - r1_mag * chi)
      / (chi * chi * curve[2]).
  LOCAL semi_latus IS r1_mag * r2_mag * turn / y_val.
  LOCAL vel1 IS u1 * (rv_dot / r1_mag) + tdir * (SQRT(mu_val * semi_latus) / r1_mag).
  LOCAL flown IS conic_kepler(pos1, vel1, tof_s, mu_val).
  IF NOT flown["OK"] { RETURN conic_lambert_result("conic", none, none, aim, rotated, theta). }
  // Absurdly long or short times run out of precision: never hand out a solution that misses by over 100 m.
  IF (flown["R"] - aim):MAG > 100 { RETURN conic_lambert_result("miss", none, none, aim, rotated, theta). }
  RETURN conic_lambert_result("", vel1, flown["V"], aim, rotated, theta).
}
