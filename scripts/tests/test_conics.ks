// test_conics.ks -- pad test for the conic maths (shared/lm_conics.ks). No ship access.
//   RUNPATH("0:/tests/test_conics.ks").   Log: 0:/lm/logs/test_conics.log. Numbers: python scripts/tests/reference_rndz.py

RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/shared/lm_conics.ks").

test_begin("0:/lm/logs/test_conics.log").
SET CONFIG:IPU TO 2000.

// The shared scenario: MU of the Moon, the LM at the apolune of a 45 x 9 nmi orbit, in the x-z plane.
LOCAL tc_mu IS 4.9028e12.
LOCAL tc_apo IS 1737400 + 45 * 1852.
LOCAL tc_peri IS 1737400 + 9 * 1852.
LOCAL tc_ra IS V(tc_apo, 0, 0).
LOCAL tc_va IS V(0, 0, SQRT(tc_mu * (2 / tc_apo - 2 / (tc_apo + tc_peri)))).

// ---- the propagator ----
LOCAL tc_out IS conic_kepler(tc_ra, tc_va, 1000, tc_mu).
assert_true("dt 1000 solved", tc_out["OK"]).
assert_vec("dt 1000 position", tc_out["R"], V(1127742.019, 0, 1412938.022), 0.5).
assert_vec("dt 1000 velocity", tc_out["V"], V(-1294.6588, 0, 1002.4428), 0.001).

LOCAL tc_back IS conic_kepler(tc_out["R"], tc_out["V"], -1000, tc_mu).
assert_vec("there and back returns the start", tc_back["R"], tc_ra, 0.01).

LOCAL tc_alpha IS 2 / tc_apo - tc_va:SQRMAGNITUDE / tc_mu.
LOCAL tc_period IS 2 * CONSTANT:PI * SQRT((1 / tc_alpha) ^ 3 / tc_mu).
LOCAL tc_full IS conic_kepler(tc_ra, tc_va, tc_period, tc_mu).
assert_vec("a full period returns the start", tc_full["R"], tc_ra, 0.1).

LOCAL tc_hyp IS conic_kepler(tc_ra, tc_va * 1.6, 900, tc_mu).
assert_true("hyperbola solved", tc_hyp["OK"]).
assert_vec("hyperbola dt 900 position", tc_hyp["R"], V(1342367.638, 0, 2161204.187), 0.5).
assert_vec("hyperbola dt 900 velocity", tc_hyp["V"], V(-879.4629, 0, 2111.8897), 0.001).
LOCAL tc_hyp_back IS conic_kepler(tc_hyp["R"], tc_hyp["V"], -900, tc_mu).
assert_vec("hyperbola there and back", tc_hyp_back["R"], tc_ra, 0.01).

LOCAL tc_still IS conic_kepler(tc_ra, tc_va, 0, tc_mu).
assert_true("dt 0 solved", tc_still["OK"]).
assert_vec("dt 0 position unchanged", tc_still["R"], tc_ra, 0).
assert_vec("dt 0 velocity unchanged", tc_still["V"], tc_va, 0).
assert_true("zero position fails", NOT conic_kepler(V(0, 0, 0), tc_va, 100, tc_mu)["OK"]).

// ---- Stumpff functions on both sides of the series ----
LOCAL tc_cs IS conic_stumpff(0).
assert_near("stumpff c at 0", tc_cs[0], 0.5, 1e-12).
assert_near("stumpff s at 0", tc_cs[1], 1 / 6, 1e-12).
SET tc_cs TO conic_stumpff(CONSTANT:PI ^ 2).
assert_near("stumpff c at pi^2", tc_cs[0], 2 / CONSTANT:PI ^ 2, 1e-9).
SET tc_cs TO conic_stumpff(-4).
assert_near("stumpff c at -4", tc_cs[0], 0.690548923, 1e-8).
assert_near("stumpff s at -4", tc_cs[1], 0.203357551, 1e-8).

// ---- elements and apolune time ----
LOCAL tc_el IS conic_elements(tc_ra, tc_va, tc_mu).
assert_near("at apolune r.v is zero", tc_el["RDOT"], 0, 1e-6).
assert_near("at apolune e cos f = -e", tc_el["EC"] + tc_el["ECC"], 0, 1e-9).
assert_near("eccentricity of 45 x 9", tc_el["ECC"], (tc_apo - tc_peri) / (tc_apo + tc_peri), 1e-9).

LOCAL tc_later IS conic_kepler(tc_ra, tc_va, 600, tc_mu).
assert_near("apolune time from +600 s", conic_time_to_apo(tc_later["R"], tc_later["V"], tc_mu), 6180.97, 0.1).
LOCAL tc_early IS conic_kepler(tc_ra, tc_va, -600, tc_mu).
assert_near("apolune time from -600 s", conic_time_to_apo(tc_early["R"], tc_early["V"], tc_mu), 600, 0.1).
LOCAL tc_round IS V(0, 0, SQRT(tc_mu / tc_apo)).
assert_near("circular: apolune time is half a period", conic_time_to_apo(tc_ra, tc_round, tc_mu),
    CONSTANT:PI * SQRT(tc_apo ^ 3 / tc_mu), 0.001).
assert_near("hyperbola has no apolune", conic_time_to_apo(tc_ra, tc_va * 1.6, tc_mu), -1, 0).

// ---- Lambert: from the same start to a target at radius 1848520 m, theta degrees on, cone 15 ----
FUNCTION tc_target {
  PARAMETER theta.
  RETURN V(1848520 * COS(theta), 0, 1848520 * SIN(theta)).
}

// tc_lambert_row: one solved case. The V1 numbers come from reference_rndz.py.
FUNCTION tc_lambert_row {
  PARAMETER label, goal, tof_s, want_v1, want_rotated, pos0, vel0, mu_val.
  LOCAL sol IS conic_lambert(pos0, goal, tof_s, mu_val, vel0, 15).
  assert_true(label + " solved " + sol["WHY"], sol["OK"]).
  assert_vec(label + " V1", sol["V1"], want_v1, 0.001).
  assert_true(label + " ROTATED is " + want_rotated, sol["ROTATED"] = want_rotated).
  LOCAL flown IS conic_kepler(pos0, sol["V1"], tof_s, mu_val).
  assert_vec(label + " V1 flies to AIM", flown["R"], sol["AIM"], 0.01).
  assert_vec(label + " V2 is the arrival velocity", sol["V2"], flown["V"], 0.001).
  RETURN sol.
}

LOCAL tc_lam IS tc_lambert_row("lambert 130", tc_target(130), 2400, V(-87.4407, 0, 1669.2219), FALSE,
    tc_ra, tc_va, tc_mu).
assert_vec("lambert 130 V2", tc_lam["V2"], V(-1323.2064, 0, -980.8862), 0.001).
assert_near("lambert 130 angle", tc_lam["ANGLE"], 130, 0.000001).
SET tc_lam TO tc_lambert_row("lambert 180", tc_target(180), 3500, V(-9.4378, 0, 1647.1607), TRUE,
    tc_ra, tc_va, tc_mu).
SET tc_lam TO tc_lambert_row("lambert 250", tc_target(250), 5000, V(8.4121, 0, 1653.2075), FALSE,
    tc_ra, tc_va, tc_mu).
assert_near("lambert 250 angle", tc_lam["ANGLE"], 250, 0.000001).
SET tc_lam TO tc_lambert_row("lambert 40 hyperbola", tc_target(40), 400, V(-713.7277, 0, 3041.6300), FALSE,
    tc_ra, tc_va, tc_mu).
LOCAL tc_moved IS tc_target(179) + V(0, 20000, 0).
SET tc_lam TO tc_lambert_row("lambert 179 out of plane", tc_moved, 3500, V(-2.2161, 0, 1647.1948), TRUE,
    tc_ra, tc_va, tc_mu).
assert_near("lambert 179 AIM is in the plane", tc_lam["AIM"]:Y, 0, 0.01).
assert_near("lambert 179 AIM keeps the radius", tc_lam["AIM"]:MAG, tc_moved:MAG, 0.01).

// ---- Lambert refusals: OK FALSE and a reason, never a kOS error ----
FUNCTION tc_refused {
  PARAMETER label, sol.
  assert_true(label + " refused", NOT sol["OK"]).
  assert_true(label + " says why (" + sol["WHY"] + ")", sol["WHY"]:LENGTH > 0).
}

tc_refused("lambert theta 0", conic_lambert(tc_ra, tc_target(0), 2400, tc_mu, tc_va, 15)).
tc_refused("lambert tof 0", conic_lambert(tc_ra, tc_target(130), 0, tc_mu, tc_va, 15)).
tc_refused("lambert radial vref", conic_lambert(tc_ra, tc_target(180), 3500, tc_mu, V(100, 0, 0), 15)).
tc_refused("lambert zero target", conic_lambert(tc_ra, V(0, 0, 0), 2400, tc_mu, tc_va, 15)).
tc_refused("lambert 180 with cone 0", conic_lambert(tc_ra, tc_target(180), 3500, tc_mu, tc_va, 0)).
tc_refused("lambert far too short", conic_lambert(tc_ra, tc_target(130), 0.000000001, tc_mu, tc_va, 15)).
tc_refused("lambert 1e7 s", conic_lambert(tc_ra, tc_target(130), 10000000, tc_mu, tc_va, 15)).

test_end().
