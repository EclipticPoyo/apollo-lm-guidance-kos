// probe_rcs2.ks -- second RCS probe for the DAP work (docs/superpowers/specs/2026-11-21-dap-design.md). It follows probe_rcs.ks,
// whose log showed: one tick = 20 ms exactly; 1 and 2 tick pulses do nothing; a 5-tick pitch pulse needs about 40 ms to start
// and the rate keeps rising for about 120 ms after the command ends; and the ship's rate then FALLS BACK TO ZERO BY ITSELF
// (time constant about 0.25 s) with SAS off. This probe measures those things properly. Every test is recorded one row per
// physics tick and read afterwards, so no number depends on a rate read some time after the pulse.
//   RUNPATH("0:/tests/probe_rcs2.ks").
// Log: 0:/lm/logs/probe_rcs2.log. About 6 to 10 minutes at normal speed. Do not time-warp. Ctrl+C stops it; then type SAS OFF.
// Setup as probe_rcs.ks: the Moon, a coasting orbit, the LM upright, descent engine OFF (throttle zero), RCS active (staged
// once), SAS off, tanks full, no steering lock. Nothing to press.
//
// Sections (rates in deg/s about the ship axis, signs as kOS gives them; "dv" is the rate minus the rate at the start):
//   0. PARTS: the parts that have modules which could turn or damp the ship (reaction wheel, torque, SAS, gimbal, drag).
//   1. FREE: after a 10-tick and a 25-tick pitch pulse, no input for 8 s. Logs the TOTAL angular speed (frame-free) at
//      0.5, 1, 2, 4 and 8 s, and the time it takes to fall to 37 percent of its peak. Answers: is the self-damping real, is
//      it proportional to the rate (exponential) or constant, and does it hold the same at 1 deg/s and 2 deg/s.
//   2. PULSES: pitch pulses of 3, 4, 5, 6, 8, 10 and 15 ticks, yaw and roll of 5 and 10 ticks, all at input 1: the delay
//      before the rate moves (ms), the peak dv and when it is reached (ms), and the row of rates every tick.
//   3. LEVELS: 10-tick pitch pulses at inputs 0.02 to 1: the peak dv. Is the response a usable impulse scale?
//   4. TRAINS: five repeats of "n ticks on, 5-n off" at input 1 (duty 20, 40 and 60 percent over 25 ticks) against one steady
//      input of the same average (0.2, 0.4, 0.6) for 25 ticks: does pulse-width modulation equal a lower input?
//   5. COUNTER: a 5-tick pulse, 10 ticks of nothing, a 5-tick pulse the other way: does the second cancel the first (the
//      phase-plane law needs this)? Also two same-direction 5-tick pulses 5 ticks apart: do they add?

LOCAL log_path IS "0:/lm/logs/probe_rcs2.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

SET CONFIG:IPU TO 500.

FUNCTION rnd_a { PARAMETER x. RETURN ROUND(x, 3). }
FUNCTION rnd_b { PARAMETER x. RETURN ROUND(x, 4). }

FUNCTION body_rate {
  PARAMETER inv_dir.
  RETURN (inv_dir * SHIP:ANGULARVEL) * (180 / CONSTANT:PI).
}

FUNCTION set_axis {
  PARAMETER axis_name, value.
  IF axis_name = "PITCH" { SET SHIP:CONTROL:PITCH TO value. }
  ELSE IF axis_name = "YAW" { SET SHIP:CONTROL:YAW TO value. }
  ELSE { SET SHIP:CONTROL:ROLL TO value. }
}

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

FUNCTION zero_controls {
  SET SHIP:CONTROL:PITCH TO 0.
  SET SHIP:CONTROL:YAW TO 0.
  SET SHIP:CONTROL:ROLL TO 0.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:STARBOARD TO 0.
  SET SHIP:CONTROL:TOP TO 0.
}

// damp: kill the rotation with SAS, then hand the controls back and let the ship settle. Up to 25 s.
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

// on_ticks: a schedule (a list, one input per tick) of value for n ticks.
FUNCTION on_ticks {
  PARAMETER value, n.
  LOCAL sched IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO { sched:ADD(value). }
  RETURN sched.
}

// sched_join: schedule a followed by schedule b.
FUNCTION sched_join {
  PARAMETER first_part, second_part.
  FOR item IN second_part { first_part:ADD(item). }
  RETURN first_part.
}

// record: write the schedule on one axis (one value per tick, zero after the end) for total ticks. Each tick it first reads
// the rate about the axis (in the ship's axes as they were at the start) and the total angular speed, then writes the input,
// then WAIT 0. Returns LIST(axis rates, total speeds), both in deg/s, one entry per tick. Nothing is printed inside the loop.
FUNCTION record {
  PARAMETER axis_name, sched, total.
  LOCAL inv_dir IS SHIP:FACING:INVERSE.
  LOCAL idx IS axis_index(axis_name).
  LOCAL rate_list IS LIST().
  LOCAL mag_list IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= total STEP { SET i TO i + 1. } DO {
    rate_list:ADD(vec_comp(body_rate(inv_dir), idx)).
    mag_list:ADD(SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI).
    IF i < sched:LENGTH { set_axis(axis_name, sched[i]). } ELSE { set_axis(axis_name, 0). }
    WAIT 0.
  }
  set_axis(axis_name, 0).
  RETURN LIST(rate_list, mag_list).
}

// csv_of: the list as text, every step-th entry, rounded.
FUNCTION csv_of {
  PARAMETER data, step.
  LOCAL out IS "".
  FROM { LOCAL i IS 0. } UNTIL i >= data:LENGTH STEP { SET i TO i + step. } DO {
    SET out TO out + ROUND(data[i], 3) + " ".
  }
  RETURN out.
}

// summarize: delay (first tick where the dv passes 0.02 deg/s, in ms), peak dv and the time of the peak, for one recording.
FUNCTION summarize {
  PARAMETER label, rate_list.
  LOCAL start_rate IS rate_list[0].
  LOCAL pk IS 0.
  LOCAL pk_i IS 0.
  LOCAL dly IS -1.
  FROM { LOCAL i IS 0. } UNTIL i >= rate_list:LENGTH STEP { SET i TO i + 1. } DO {
    LOCAL d IS rate_list[i] - start_rate.
    IF dly < 0 AND ABS(d) > 0.02 { SET dly TO i * 20. }
    IF ABS(d) > ABS(pk) { SET pk TO d. SET pk_i TO i. }
  }
  say(label + "  delay_ms=" + dly + "  peak_dv=" + rnd_b(pk) + "  at_ms=" + (pk_i * 20)).
  say("    rates " + csv_of(rate_list, 1)).
}

// ---- start -------------------------------------------------------------------------------------------------------
say("probe_rcs2  ship=" + SHIP:NAME + "  mass_t=" + rnd_a(SHIP:MASS) + "  IPU=" + CONFIG:IPU).
RCS ON.
SAS OFF.
UNLOCK STEERING.
zero_controls().
WAIT 1.

// 0. parts with modules that could turn or damp the ship
say("== 0 PARTS (modules whose name has Wheel, Torque, SAS, Gimbal, Drag or Inertia)").
FOR part_any IN SHIP:PARTS {
  FOR mod_name IN part_any:MODULES {
    IF mod_name:CONTAINS("Wheel") OR mod_name:CONTAINS("Torque") OR mod_name:CONTAINS("SAS") OR mod_name:CONTAINS("Gimbal") OR mod_name:CONTAINS("Drag") OR mod_name:CONTAINS("Inertia") {
      say("  " + part_any:TITLE + "  :  " + mod_name).
    }
  }
}
say("SAS=" + SAS + "  RCS=" + RCS).

// 1. free rotation
say("== 1 FREE  (pitch pulse, then no input for 8 s = 400 ticks; total angular speed deg/s)").
FOR pulse_ticks IN LIST(10, 25) {
  damp().
  LOCAL free_rec IS record("PITCH", on_ticks(1, pulse_ticks), 400).
  LOCAL mags IS free_rec[1].
  LOCAL mag_pk IS 0.
  LOCAL mag_pk_i IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= mags:LENGTH STEP { SET i TO i + 1. } DO {
    IF mags[i] > mag_pk { SET mag_pk TO mags[i]. SET mag_pk_i TO i. }
  }
  LOCAL t37 IS -1.
  FROM { LOCAL i IS mag_pk_i. } UNTIL i >= mags:LENGTH STEP { SET i TO i + 1. } DO {
    IF t37 < 0 AND mags[i] < mag_pk * 0.37 { SET t37 TO (i - mag_pk_i) * 20. }
  }
  say("pulse " + pulse_ticks + " ticks: peak=" + rnd_b(mag_pk) + " at_ms=" + (mag_pk_i * 20) + "  to_37pct_ms=" + t37
      + "  at 0.5s=" + rnd_b(mags[25]) + " 1s=" + rnd_b(mags[50]) + " 2s=" + rnd_b(mags[100]) + " 4s=" + rnd_b(mags[200]) + " 8s=" + rnd_b(mags[399])).
  say("    total speed every 10 ticks: " + csv_of(mags, 10)).
}

// 2. pulses at input 1, every tick
say("== 2 PULSES  (input 1; rates every tick for 30 ticks = 600 ms from the first write)").
FOR n_ticks IN LIST(3, 4, 5, 6, 8, 10, 15) {
  damp().
  LOCAL res IS record("PITCH", on_ticks(1, n_ticks), 30).
  summarize("PITCH ticks=" + n_ticks, res[0]).
}
FOR axis_name IN LIST("YAW", "ROLL") {
  FOR n_ticks IN LIST(5, 10) {
    damp().
    LOCAL res IS record(axis_name, on_ticks(1, n_ticks), 30).
    summarize(axis_name + " ticks=" + n_ticks, res[0]).
  }
}

// 3. levels
say("== 3 LEVELS  (PITCH, 10 ticks, 30 ticks recorded)").
FOR level IN LIST(0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1) {
  damp().
  LOCAL res IS record("PITCH", on_ticks(level, 10), 30).
  summarize("PITCH in=" + level, res[0]).
}

// 4. trains against steady inputs
say("== 4 TRAINS  (PITCH, 25 ticks of schedule, 45 ticks recorded)").
FOR n_on IN LIST(1, 2, 3) {
  LOCAL train IS LIST().
  FROM { LOCAL k IS 0. } UNTIL k >= 5 STEP { SET k TO k + 1. } DO {
    SET train TO sched_join(train, sched_join(on_ticks(1, n_on), on_ticks(0, 5 - n_on))).
  }
  damp().
  LOCAL res_train IS record("PITCH", train, 45).
  summarize("TRAIN " + n_on + " on of 5 (duty " + (n_on * 20) + "pct)", res_train[0]).
  damp().
  LOCAL res_steady IS record("PITCH", on_ticks(n_on / 5, 25), 45).
  summarize("STEADY in=" + (n_on / 5) + " for 25 ticks", res_steady[0]).
}

// 5. counter pulse and double pulse
say("== 5 COUNTER  (PITCH, 60 ticks recorded)").
damp().
LOCAL res_counter IS record("PITCH", sched_join(on_ticks(1, 5), sched_join(on_ticks(0, 10), on_ticks(-1, 5))), 60).
summarize("PLUS 5, wait 10, MINUS 5", res_counter[0]).
damp().
LOCAL res_double IS record("PITCH", sched_join(on_ticks(1, 5), sched_join(on_ticks(0, 5), on_ticks(1, 5))), 60).
summarize("PLUS 5, wait 5, PLUS 5", res_double[0]).

damp().
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
say("probe_rcs2 done").
