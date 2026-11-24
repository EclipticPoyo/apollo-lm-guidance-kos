// test_burnctl.ks -- pad tests for the burn control layer (lm/descent/lm_control.ks, release 1.4). No flight needed.
//   RUNPATH("0:/tests/test_burnctl.ks").  Results go to 0:/lm/logs/test_burnctl.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_burnctl.log").
SET CTL_DRY TO TRUE.

// the dry lever
assert_near("dry lever default 0.5", ctl_pilot_throttle(), 0.5, 0.0001).
assert_near("MAN throttle at lever 0.5", ctl_man_throttle(), 0.5, 0.0001).
SET CTL_DRY_LEVER TO 0.
assert_near("MAN throttle floored at the minimum", ctl_man_throttle(), THR_MIN_FRAC, 0.0001).
SET CTL_DRY_LEVER TO 1.
assert_near("MAN throttle at full lever", ctl_man_throttle(), 1, 0.0001).
SET CTL_DRY_LEVER TO 1.5.
assert_near("MAN throttle capped at 1", ctl_man_throttle(), 1, 0.0001).
SET CTL_DRY_LEVER TO 0.5.
// ctl_man_direct on the pad (no lever to move, the lock is not touched): the same value as ctl_man_throttle
assert_near("direct MAN throttle at lever 0.5", ctl_man_direct(), 0.5, 0.0001).
SET CTL_DRY_LEVER TO 0.
assert_near("direct MAN throttle floored at the minimum", ctl_man_direct(), THR_MIN_FRAC, 0.0001).
SET CTL_DRY_LEVER TO 1.5.
assert_near("direct MAN throttle capped at 1", ctl_man_direct(), 1, 0.0001).
SET CTL_DRY_LEVER TO 0.5.
assert_true("the throttle lock flag starts clear on the pad", NOT CTL_THR_LOCKED).

// thrust percent
assert_near("thrust percent 18000 of 43670", ctl_thrust_pct(18000, 43670), 41.2, 0.1).
assert_near("no full thrust gives 0", ctl_thrust_pct(1, 0), 0, 0.0001).
assert_near("thrust percent capped at 100", ctl_thrust_pct(60000, 43670), 100, 0.0001).
assert_near("thrust percent not negative", ctl_thrust_pct(-5, 43670), 0, 0.0001).

// arm, disarm, end (dry: no engine, so 0 stands in for it)
SET CTL_THR TO 0.7.
ctl_arm(0).
assert_near("ctl_arm sets the minimum throttle", CTL_THR, THR_MIN_FRAC, 0.0001).
ctl_disarm(0).
assert_near("ctl_disarm sets zero throttle", CTL_THR, 0, 0.0001).
SET CTL_THR TO 0.4.
ctl_burn_end(0, TRUE).
assert_near("ctl_burn_end leaves zero throttle", CTL_THR, 0, 0.0001).
ctl_release_throttle_lock().
assert_true("ctl_release_throttle_lock runs dry", TRUE).

test_end().
