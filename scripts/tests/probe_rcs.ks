// SUPERSEDED (2026-11-21): the first runs of this probe were taken with Atmosphere Autopilot on, which damped the rotation, so
// its log is invalid. Use probe_rcs2.ks and probe_rcs3.ks, and keep Atmosphere Autopilot off (see the DAP spec, Probe results).
// probe_rcs.ks -- measures what the lander's RCS does for the DAP (phase-plane attitude controller) work.
//   RUNPATH("0:/tests/probe_rcs.ks").
// Log: 0:/lm/logs/probe_rcs.log (read it back; the terminal cannot be copied from). About 5 to 8 minutes at normal
// speed. Do not time-warp while it runs. Ctrl+C stops it; then type SAS OFF. in the terminal.
//
// Setup: the Moon, any coasting orbit, the Realism Overhaul LM upright, descent engine OFF (throttle zero), RCS thrusters
// active (stage once, as for P63), SAS OFF, tanks full, no steering lock running.
//
// What it answers (the Luminary DAP fires jets for 14 ms to 250 ms on a 100 ms cycle, see note-guidance-rate.md):
//   1. INVENTORY: the RCS parts kOS sees, their thrust and the directions of their thrusters (ship axes).
//   2. TICK: how long one "WAIT 0" takes (the shortest pulse kOS can write) and how much it varies.
//   3. PULSES: for pitch, yaw and roll, both signs, a pulse of 1, 2, 5, 10 and 25 ticks at input 1: the real pulse time
//      (game clock), the change of body rate it gave (deg/s, read 0.3 s after the pulse ends) and the angular
//      acceleration that implies. This is the number the phase-plane law needs (alpha = jet acceleration).
//   4. LEVELS: the same 10-tick pitch pulse at inputs 0.02, 0.04, 0.06, 0.1, 0.3 and 1 (docs say KSP ignores RCS input under
//      0.05: is that so, and is the response linear above it?). 4B (run last): the same with the RCS part DEADBAND set to 0.
//   5. SERIES: the rate every tick during and after a 5-tick pitch pulse (does the jet thrust start and stop at once?).
// Body axes used in the log: x = starboard (pitch axis), y = top (yaw axis), z = fore (roll axis). Rates are read in the
// ship's axes as they were when the pulse started. The sign of each response is logged as it comes (kOS's rotation
// signs are left-handed, so do not assume them).

LOCAL log_path IS "0:/lm/logs/probe_rcs.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

SET CONFIG:IPU TO 500.

FUNCTION rnd_a { PARAMETER x. RETURN ROUND(x, 3). }
FUNCTION rnd_b { PARAMETER x. RETURN ROUND(x, 5). }

// body_rate: the ship's angular velocity in the axes of inv_dir (a facing:inverse taken earlier), deg/s, as a vector.
FUNCTION body_rate {
  PARAMETER inv_dir.
  RETURN (inv_dir * SHIP:ANGULARVEL) * (180 / CONSTANT:PI).
}

// set_axis: write one rotation input. axis_name is "PITCH", "YAW" or "ROLL".
FUNCTION set_axis {
  PARAMETER axis_name, value.
  IF axis_name = "PITCH" { SET SHIP:CONTROL:PITCH TO value. }
  ELSE IF axis_name = "YAW" { SET SHIP:CONTROL:YAW TO value. }
  ELSE { SET SHIP:CONTROL:ROLL TO value. }
}

// axis_index: which body-rate component the axis turns about (0 x, 1 y, 2 z).
FUNCTION axis_index {
  PARAMETER axis_name.
  IF axis_name = "PITCH" { RETURN 0. }
  IF axis_name = "YAW" { RETURN 1. }
  RETURN 2.
}

FUNCTION vec_comp {
  PARAMETER vec, idx.
  IF idx = 0 { RETURN vec:X. }
  IF idx = 1 { RETURN vec:Y. }
  RETURN vec:Z.
}

// zero_controls: write 0 to every raw control. (The kOS docs do not say whether NEUTRALIZE keeps overriding later writes, so
// it is used only at the very end; in between every control is set back to zero by hand, which the docs describe as freeing it.)
FUNCTION zero_controls {
  SET SHIP:CONTROL:PITCH TO 0.
  SET SHIP:CONTROL:YAW TO 0.
  SET SHIP:CONTROL:ROLL TO 0.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:STARBOARD TO 0.
  SET SHIP:CONTROL:TOP TO 0.
}

// damp: kill the rotation with SAS (stability assist), then hand the controls back. Up to 25 s.
FUNCTION damp {
  zero_controls().
  RCS ON.
  SAS ON.
  SET SASMODE TO "STABILITYASSIST".
  LOCAL t0 IS TIME:SECONDS.
  UNTIL SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI < 0.01 OR TIME:SECONDS - t0 > 25 { WAIT 0.1. }
  SAS OFF.
  zero_controls().
  WAIT 1.
}

// pulse: write value on axis_name for ticks physics ticks, then zero it. Returns LIST(pulse_s, rate_change_deg_s) where
// pulse_s is the game-clock time between the two writes and rate_change is read 0.3 s after the pulse ended.
FUNCTION pulse {
  PARAMETER axis_name, value, ticks.
  LOCAL inv_dir IS SHIP:FACING:INVERSE.
  LOCAL idx IS axis_index(axis_name).
  LOCAL before IS vec_comp(body_rate(inv_dir), idx).
  LOCAL t_on IS TIME:SECONDS.
  set_axis(axis_name, value).
  FROM { LOCAL i IS 0. } UNTIL i >= ticks STEP { SET i TO i + 1. } DO { WAIT 0. }
  set_axis(axis_name, 0).
  LOCAL t_off IS TIME:SECONDS.
  WAIT 0.3.
  LOCAL after IS vec_comp(body_rate(inv_dir), idx).
  RETURN LIST(t_off - t_on, after - before).
}

// ---- start -------------------------------------------------------------------------------------------------------
say("probe_rcs  ship=" + SHIP:NAME + "  mass_t=" + rnd_a(SHIP:MASS) + "  IPU=" + CONFIG:IPU).
RCS ON.
SAS OFF.
UNLOCK STEERING.
zero_controls().
WAIT 1.

// 1. inventory
say("== 1 INVENTORY (thruster directions in ship axes x starboard, y top, z fore; the direction the exhaust pushes the ship)").
LOCAL inv0 IS SHIP:FACING:INVERSE.
LOCAL rcs_parts IS SHIP:RCS.
say("rcs parts kOS sees: " + rcs_parts:LENGTH).
FOR part_rcs IN rcs_parts {
  say("part " + part_rcs:TITLE + "  maxthrust_kN=" + rnd_a(part_rcs:MAXTHRUST) + "  isp=" + rnd_a(part_rcs:ISP)
      + "  enabled pitch/yaw/roll/fore/star/top=" + part_rcs:PITCHENABLED + "/" + part_rcs:YAWENABLED + "/" + part_rcs:ROLLENABLED
      + "/" + part_rcs:FOREENABLED + "/" + part_rcs:STARBOARDENABLED + "/" + part_rcs:TOPENABLED
      + "  thrusters=" + part_rcs:THRUSTVECTORS:LENGTH).
  LOCAL n IS 0.
  FOR tv IN part_rcs:THRUSTVECTORS {
    LOCAL b IS inv0 * tv.
    say("  thruster " + n + "  dir x=" + rnd_a(b:X) + " y=" + rnd_a(b:Y) + " z=" + rnd_a(b:Z)).
    SET n TO n + 1.
  }
}

// 2. tick length
say("== 2 TICK (WAIT 0 x 100)").
LOCAL tick_min IS 99.
LOCAL tick_max IS 0.
LOCAL tick_t0 IS TIME:SECONDS.
FROM { LOCAL i IS 0. } UNTIL i >= 100 STEP { SET i TO i + 1. } DO {
  LOCAL a IS TIME:SECONDS.
  WAIT 0.
  LOCAL dt IS TIME:SECONDS - a.
  IF dt < tick_min { SET tick_min TO dt. }
  IF dt > tick_max { SET tick_max TO dt. }
}
say("mean_ms=" + rnd_a((TIME:SECONDS - tick_t0) / 100 * 1000) + "  min_ms=" + rnd_a(tick_min * 1000) + "  max_ms=" + rnd_a(tick_max * 1000)).

// 3. pulses
say("== 3 PULSES  (axis, input, ticks, pulse_ms, rate_change_deg_s, alpha_deg_s2 = rate_change / pulse_s, mass_t)").
FOR axis_name IN LIST("PITCH", "YAW", "ROLL") {
  FOR dir_sign IN LIST(1, -1) {
    FOR ticks IN LIST(1, 2, 5, 10, 25) {
      damp().
      LOCAL res IS pulse(axis_name, dir_sign, ticks).
      LOCAL alpha IS 0.
      IF res[0] > 0 { SET alpha TO res[1] / res[0]. }
      say(axis_name + "  in=" + dir_sign + "  ticks=" + ticks + "  pulse_ms=" + rnd_a(res[0] * 1000)
          + "  dRate=" + rnd_b(res[1]) + "  alpha=" + rnd_b(alpha) + "  mass_t=" + rnd_a(SHIP:MASS)).
    }
  }
}

// 4. input levels
say("== 4 LEVELS  (PITCH, 10 ticks)").
// (the game's null zone is 0.05; the docs say 0.049 is ignored and 0.051 responds, so the levels straddle it)
FOR level IN LIST(0.02, 0.04, 0.06, 0.1, 0.3, 1) {
  damp().
  LOCAL res IS pulse("PITCH", level, 10).
  say("PITCH  in=" + level + "  pulse_ms=" + rnd_a(res[0] * 1000) + "  dRate=" + rnd_b(res[1])).
}

// 5. series (rows are collected and logged afterwards: a file write every tick could disturb the timing)
say("== 5 SERIES  (PITCH input 1 for 5 ticks; t_ms from the first write, pitch rate deg/s, one row per tick, 40 ticks)").
damp().
LOCAL inv1 IS SHIP:FACING:INVERSE.
LOCAL s_t0 IS TIME:SECONDS.
LOCAL rows IS LIST().
set_axis("PITCH", 1).
FROM { LOCAL i IS 0. } UNTIL i >= 40 STEP { SET i TO i + 1. } DO {
  IF i = 5 { set_axis("PITCH", 0). }
  rows:ADD("t_ms=" + rnd_a((TIME:SECONDS - s_t0) * 1000) + "  rate=" + rnd_b(body_rate(inv1):X)).
  WAIT 0.
}
set_axis("PITCH", 0).
FOR row IN rows { say(row). }

// 4B. deadband (last on purpose: it uses the RCS DEADBAND suffix, listed in the kOS docs for RCS parts, default 0.05; if the
// suffix does not exist the script stops here and everything above is already in the log)
say("== 4B DEADBAND  (RCS part DEADBAND set to 0, then small PITCH inputs, 10 ticks; the original value is put back)").
LOCAL old_db IS LIST().
FOR rp IN SHIP:RCS {
  old_db:ADD(rp:DEADBAND).
  say("part " + rp:TITLE + "  deadband=" + rp:DEADBAND).
  SET rp:DEADBAND TO 0.
}
FOR level IN LIST(0.01, 0.02, 0.04) {
  damp().
  LOCAL res IS pulse("PITCH", level, 10).
  say("PITCH  deadband=0  in=" + level + "  pulse_ms=" + rnd_a(res[0] * 1000) + "  dRate=" + rnd_b(res[1])).
}
LOCAL db_idx IS 0.
FOR rp IN SHIP:RCS {
  SET rp:DEADBAND TO old_db[db_idx].
  SET db_idx TO db_idx + 1.
}

damp().
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
say("probe_rcs done").
