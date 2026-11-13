// probe_steer.ks -- turns the lander on RCS alone with several kOS steering settings and logs how each one behaves,
// so the settings P63 uses can be chosen from numbers. Nothing is flown or burned.
//   RUNPATH("0:/lm/tests/probe_steer.ks").
// Log: 0:/lm/probe_steer.log (read it back; the terminal cannot be copied from). It takes about 15 minutes at
// normal speed. Do not time-warp while it runs. Press Ctrl+C in the terminal to stop it early, then type
// UNLOCK STEERING. in the terminal.
//
// Setup: the Moon, any orbit (a coasting lander), the Realism Overhaul LM upright, descent engine OFF (throttle zero),
// RCS thrusters active (stage once, as for P63), SAS OFF, tanks full. Turns are done in the inertial (raw) frame, so the
// orbital motion does not matter.
//
// Round 1 (flight, 2026-11-12) found: with the defaults a 150 degree turn gets within 2 degrees at about 15 s, then
// the error rises again to about 4 degrees (kOS leaves the roll alone until the nose is within 5 degrees) and falls to
// 0; setting ROLLCONTROLANGLERANGE to 180 made it much worse (rebound 16 degrees); afterwards the ship holds at 0
// degrees error but keeps turning at about 0.1 deg/s, firing the RCS all the time (about 57 kg in 70 s).
// Round 2 (this file) keeps the roll range at its default and tests the dead zone (TORQUEEPSILON) against that chatter,
// and the stopping and settling times against the rebound.
//
// What is tested (kOS docs, structures/misc/steeringmanager and commands/flight/cooked, checked 2026-11-12):
//   LOCK STEERING TO a direction: kOS's own "cooked" steering turns the ship with the RCS thrusters.
//   STEERINGMANAGER:MAXSTOPPINGTIME  the ship never turns faster than it can stop in this many seconds (default 2).
//   STEERINGMANAGER:PITCHTS/YAWTS/ROLLTS  settling time of the torque loop; bigger = softer, less overshoot, slower.
//   STEERINGMANAGER:TORQUEEPSILONMIN/MAX  dead zone: a rate error smaller than this is ignored (defaults 0.0002 / 0.001).
//   STEERINGMANAGER:RESETTODEFAULT()  puts every setting back; called before each configuration and at the end.
//
// For each configuration the lander makes four legs: a BIG turn (150 degrees of pitch plus 90 of roll, like the 176
// degree turn to the burn attitude), back, then a SMALL turn (20 degrees), back. Each leg runs until the error has been
// under 0.5 degrees for 3 s (or 60 s), then the ship HOLDS that attitude for 15 s while the probe measures the chatter.
// The summary line of each leg gives: time to first get within 2 degrees, the rebound (the largest error after that;
// 0 = it never came back out), the time it settled, the RCS propellant used up to then (kg, from the ship mass), the
// propellant used during the 15 s hold, and the mean turn rate during the hold (deg/s; 0.1 or more is the chatter).

LOCAL log_path IS "0:/lm/probe_steer.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

SET CONFIG:IPU TO 500.                       // the default 150 is too slow to sample the turn smoothly

GLOBAL STEER_DIR IS SHIP:FACING.             // the direction the lock steers to (a global: the lock reads it every cycle)
GLOBAL SETTLE_ERR_DEG IS 0.5.                // settled: error under this for SETTLE_HOLD_S
GLOBAL SETTLE_HOLD_S IS 3.
GLOBAL TURN_TIMEOUT_S IS 60.
GLOBAL CHATTER_HOLD_S IS 15.                 // how long the ship holds the attitude while the chatter is measured

// err_deg: how far the ship is from STEER_DIR, the larger of the nose (fore) angle and the "top" angle, as P63 measures it.
FUNCTION err_deg {
  RETURN MAX(VANG(SHIP:FACING:FOREVECTOR, STEER_DIR:FOREVECTOR), VANG(SHIP:FACING:TOPVECTOR, STEER_DIR:TOPVECTOR)).
}

FUNCTION rate_dps {
  RETURN SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI.
}

// run_leg: steer to target_dir, watch until the ship has settled (or TURN_TIMEOUT_S), then watch it hold the attitude for
// CHATTER_HOLD_S. Logs a row every 0.5 s during the turn and one summary line.
FUNCTION run_leg {
  PARAMETER cfg_name, leg_name, target_dir.
  SET STEER_DIR TO target_dir.
  LOCAL t_start IS TIME:SECONDS.
  LOCAL mass_start IS SHIP:MASS.
  LOCAL first_in IS -1.                      // first time (s since the command) the error was under 2 degrees
  LOCAL rebound IS 0.                        // the largest error seen after that
  LOCAL settled_since IS -1.
  LOCAL settle_time IS -1.
  LOCAL next_row IS 0.
  LOCAL elapsed IS 0.
  LOCAL finished IS FALSE.
  UNTIL finished {
    SET elapsed TO TIME:SECONDS - t_start.
    LOCAL err IS err_deg().
    LOCAL spin IS rate_dps().
    IF elapsed >= next_row {
      LOG cfg_name + "," + leg_name + "," + ROUND(elapsed, 1) + "," + ROUND(err, 2) + "," + ROUND(spin, 3) TO log_path.
      SET next_row TO next_row + 0.5.
    }
    IF first_in < 0 AND err < 2 { SET first_in TO elapsed. }
    IF first_in >= 0 AND err > rebound { SET rebound TO err. }
    IF err < SETTLE_ERR_DEG {
      IF settled_since < 0 { SET settled_since TO elapsed. }
      IF elapsed - settled_since >= SETTLE_HOLD_S { SET settle_time TO settled_since. SET finished TO TRUE. }
    } ELSE {
      SET settled_since TO -1.
    }
    IF elapsed > TURN_TIMEOUT_S { SET finished TO TRUE. }
    WAIT 0.1.
  }
  LOCAL mass_settled IS SHIP:MASS.
  // the hold: how much propellant the chatter uses, and how fast the ship is still turning on average
  LOCAL hold_start IS TIME:SECONDS.
  LOCAL rate_sum IS 0.
  LOCAL samples IS 0.
  LOCAL err_worst IS 0.
  UNTIL TIME:SECONDS - hold_start >= CHATTER_HOLD_S {
    SET rate_sum TO rate_sum + rate_dps().
    SET samples TO samples + 1.
    SET err_worst TO MAX(err_worst, err_deg()).
    WAIT 0.1.
  }
  say("RESULT " + cfg_name + " " + leg_name + ": within 2 deg at " + ROUND(first_in, 1) + " s, rebound " + ROUND(rebound, 2) +
      " deg, settled at " + ROUND(settle_time, 1) + " s, propellant to settle " + ROUND((mass_start - mass_settled) * 1000, 1) +
      " kg, hold " + CHATTER_HOLD_S + " s: used " + ROUND((mass_settled - SHIP:MASS) * 1000, 1) + " kg, mean rate " +
      ROUND(rate_sum / MAX(samples, 1), 3) + " deg/s, worst error " + ROUND(err_worst, 2) + " deg   (-1 = never within the time limit)").
}

// cfg: a lexicon of the settings to try, as multipliers of the defaults read at the start.
FUNCTION cfg {
  PARAMETER name, stop_mult, ts_mult, eps_mult.
  RETURN LEXICON("NAME", name, "MST", stop_mult, "TS", ts_mult, "EPS", eps_mult).
}

// ---- Main ------------------------------------------------------------------------------------------------------
say("probe_steer round 2: LM at " + BODY:NAME + ", mass " + ROUND(SHIP:MASS, 3) + " t, UT " + ROUND(TIME:SECONDS)).
IF SAS {
  SAS OFF.
  say("SAS was on: switched off (SAS and LOCK STEERING must not both be on)").
}
RCS ON.
LOCK THROTTLE TO 0.                          // the engine must stay off

STEERINGMANAGER:RESETTODEFAULT().
LOCAL mst_default IS STEERINGMANAGER:MAXSTOPPINGTIME.
LOCAL pts_default IS STEERINGMANAGER:PITCHTS.
LOCAL yts_default IS STEERINGMANAGER:YAWTS.
LOCAL rts_default IS STEERINGMANAGER:ROLLTS.
LOCAL emin_default IS STEERINGMANAGER:TORQUEEPSILONMIN.
LOCAL emax_default IS STEERINGMANAGER:TORQUEEPSILONMAX.
say("defaults: MAXSTOPPINGTIME " + mst_default + ", PITCHTS " + pts_default + ", YAWTS " + yts_default + ", ROLLTS " + rts_default +
    ", ROLLCONTROLANGLERANGE " + STEERINGMANAGER:ROLLCONTROLANGLERANGE + ", TORQUEEPSILONMIN " + emin_default +
    ", TORQUEEPSILONMAX " + emax_default).
say("log rows are: config,leg,seconds,error_deg,rate_deg_per_s").

LOCAL configs IS LIST(
  cfg("DEFAULT", 1, 1, 1),
  cfg("EPS10", 1, 1, 10),
  cfg("EPS50", 1, 1, 50),
  cfg("STOP1_EPS10", 0.5, 1, 10),
  cfg("TS2_EPS10", 1, 2, 10)
).

// The base attitude the legs return to, and the two target attitudes (turns in the raw frame about the base axes).
LOCAL base_dir IS SHIP:FACING.
LOCAL big_dir IS ANGLEAXIS(90, base_dir:FOREVECTOR) * ANGLEAXIS(150, base_dir:STARVECTOR) * base_dir.
LOCAL small_dir IS ANGLEAXIS(20, base_dir:STARVECTOR) * base_dir.

LOCK STEERING TO STEER_DIR.
SET STEER_DIR TO base_dir.
say("holding the start attitude for 10 s to settle").
WAIT 10.

FOR one IN configs {
  STEERINGMANAGER:RESETTODEFAULT().
  SET STEERINGMANAGER:MAXSTOPPINGTIME TO mst_default * one["MST"].
  SET STEERINGMANAGER:PITCHTS TO pts_default * one["TS"].
  SET STEERINGMANAGER:YAWTS TO yts_default * one["TS"].
  SET STEERINGMANAGER:ROLLTS TO rts_default * one["TS"].
  // the docs: setting MIN above MAX raises MAX, setting MAX below MIN lowers MIN, so set MAX first when growing them
  SET STEERINGMANAGER:TORQUEEPSILONMAX TO emax_default * one["EPS"].
  SET STEERINGMANAGER:TORQUEEPSILONMIN TO emin_default * one["EPS"].
  say("---- configuration " + one["NAME"] + ": MAXSTOPPINGTIME " + ROUND(STEERINGMANAGER:MAXSTOPPINGTIME, 2) + ", TS x" +
      one["TS"] + ", TORQUEEPSILON x" + one["EPS"] + " (" + STEERINGMANAGER:TORQUEEPSILONMIN + " / " +
      STEERINGMANAGER:TORQUEEPSILONMAX + ")").
  run_leg(one["NAME"], "BIG_OUT", big_dir).
  run_leg(one["NAME"], "BIG_BACK", base_dir).
  run_leg(one["NAME"], "SMALL_OUT", small_dir).
  run_leg(one["NAME"], "SMALL_BACK", base_dir).
}

STEERINGMANAGER:RESETTODEFAULT().
UNLOCK STEERING.
UNLOCK THROTTLE.
say("probe_steer done. Log: 0:/lm/probe_steer.log").
