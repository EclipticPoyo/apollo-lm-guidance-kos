// test_axes.ks -- pad test for the measured axes conversion (shared/lm_axes.ks). The carry is pure maths on made-up marks; the last part reads one live mark.
//   RUNPATH("0:/tests/test_axes.ks").   Log: 0:/lm/logs/test_axes.log.

RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/shared/lm_axes.ks").

test_begin("0:/lm/logs/test_axes.log").
SET CONFIG:IPU TO 2000.

// An hour of the Moon's spin: 2.66e-6 rad/s for 3600 s is 0.5487 degrees. The pole is +Y, the fixed direction in the pole's equator +X before and turned by that angle after.
LOCAL ta_deg IS 2.66e-6 * 3600 * 180 / CONSTANT:PI.
LOCAL ta_a IS LEXICON("P", V(1, 0, 0), "N", V(0, 1, 0)).
LOCAL ta_b IS LEXICON("P", V(COS(ta_deg), 0, SIN(ta_deg)), "N", V(0, 1, 0)).

assert_vec("the fixed direction carries to its new place", axes_carry(V(1, 0, 0), ta_a, ta_b), ta_b["P"], 1e-9).
assert_vec("a vector square to it turns by the same angle", axes_carry(V(0, 0, 1), ta_a, ta_b), V(-SIN(ta_deg), 0, COS(ta_deg)), 1e-9).
assert_vec("the pole is unchanged", axes_carry(V(0, 1, 0), ta_a, ta_b), V(0, 1, 0), 1e-9).
LOCAL ta_v IS V(1200000, -340000, 910000).
assert_vec("there and back returns the vector", axes_carry(axes_carry(ta_v, ta_a, ta_b), ta_b, ta_a), ta_v, 1e-6).
assert_near("the length is kept", axes_carry(ta_v, ta_a, ta_b):MAG, ta_v:MAG, 1e-6).
assert_vec("equal marks leave a vector unchanged", axes_carry(ta_v, ta_b, ta_b), ta_v, 1e-6).

// A general turn, pole and all: 30 degrees about (1, 2, 2). Numbers: python scripts/tests/reference_rndz.py (a rotation matrix, independent of the carry).
LOCAL ta_c IS LEXICON("P", V(0.880911470031, 0.363105465826, -0.303561200841), "N", V(-0.303561200841, 0.925569668769, 0.226210931651)).
assert_vec("a turn about a tilted axis carries the vector", axes_carry(ta_v, ta_a, ta_c), V(1490730.5462, 23551.4861, 401083.2408), 0.001).

// ---- the live mark ----
LOCAL ta_live IS axes_mark().
assert_near("live mark: P is a unit vector", ta_live["P"]:MAG, 1, 1e-9).
assert_near("live mark: N is a unit vector", ta_live["N"]:MAG, 1, 1e-9).
assert_near("live mark: P is square to N", VDOT(ta_live["P"], ta_live["N"]), 0, 1e-9).

test_end().
