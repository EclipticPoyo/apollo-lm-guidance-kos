// probe_rod.ks -- can the Shift / Ctrl throttle keys be read while a programme holds the throttle (milestone 5 task 2)?
//   RUNPATH("0:/lm/tests/probe_rod.ks").
// Log: 0:/lm/probe_rod.log (read it back; the terminal cannot be copied from).
//
// Milestone 5 uses the pilot's throttle keys as the P66 rate-of-descent (ROD) clicks. The lever is SHIP:CONTROL:PILOTMAINTHROTTLE
// (get and set, 0 to 1; names as in lm_control.ks ctl_release and probe_control.ks, kOS docs commands/flight/pilot.rst). The
// programme locks the throttle (LOCK THROTTLE TO ...), so the question is whether the lever still follows the keys then, and
// whether writing it (to re-centre it at 0.5) sticks. This probe does NOT light the engine: the throttle lock is at 0.
//
// Setup: the Moon, any orbit, the Realism Overhaul LM upright, engines OFF, SAS OFF. Click into the KSP window for the keys.
// The script asks for: a Shift tap, a Ctrl tap, Shift held for 2 s, Ctrl held for 2 s, then nothing for 2 s.

LOCAL log_path IS "0:/lm/probe_rod.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

// trace: log the lever every 0.05 s for secs seconds as "time since start, lever, change since the last sample".
// Returns the lever's lowest and highest values seen, as a list.
FUNCTION trace {
  PARAMETER label, secs.
  say("--- " + label + " (" + secs + " s) ---").
  LOCAL t_end IS TIME:SECONDS + secs.
  LOCAL t_begin IS TIME:SECONDS.
  LOCAL last IS SHIP:CONTROL:PILOTMAINTHROTTLE.
  LOCAL lo IS last.
  LOCAL hi IS last.
  UNTIL TIME:SECONDS >= t_end {
    LOCAL now_val IS SHIP:CONTROL:PILOTMAINTHROTTLE.
    IF now_val < lo { SET lo TO now_val. }
    IF now_val > hi { SET hi TO now_val. }
    IF ABS(now_val - last) > 0.0005 { LOG ROUND(TIME:SECONDS - t_begin, 2) + "," + ROUND(now_val, 4) + "," + ROUND(now_val - last, 4) TO log_path. }
    SET last TO now_val.
    WAIT 0.05.
  }
  say(label + ": lever went from low " + ROUND(lo, 4) + " to high " + ROUND(hi, 4) + ", ends at " + ROUND(last, 4)).
  RETURN LIST(lo, hi).
}

// countdown: "3 2 1 NOW" one second apart, so the key press starts when the trace does (the first run's presses were late).
FUNCTION countdown {
  PARAMETER what.
  say("GET READY: " + what).
  PRINT "3".
  WAIT 1.
  PRINT "2".
  WAIT 1.
  PRINT "1".
  WAIT 1.
  say("NOW").
}

say("probe_rod: " + SHIP:NAME + " at " + SHIP:BODY:NAME + ", UT " + ROUND(TIME:SECONDS)).
say("SAS " + SAS + ", engines must be off. The throttle is locked at 0 for this probe (no engine is lit).").

LOCK THROTTLE TO 0.
WAIT 0.2.
say("lever at the start: " + ROUND(SHIP:CONTROL:PILOTMAINTHROTTLE, 4)).

// ---- 1. Can the lever be written while the throttle is locked? ----
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
WAIT 0.3.
LOCAL after_write IS SHIP:CONTROL:PILOTMAINTHROTTLE.
say("wrote the lever to 0.5, it reads " + ROUND(after_write, 4) + (CHOOSE "  (WRITE STICKS)" IF ABS(after_write - 0.5) < 0.01 ELSE "  (WRITE IGNORED)")).

// ---- 2. Do the keys move it? ----
countdown("TAP SHIFT once (left Shift, KSP window focused)").
LOCAL r1 IS trace("one Shift tap", 4).
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
WAIT 0.3.
say("lever re-centred, reads " + ROUND(SHIP:CONTROL:PILOTMAINTHROTTLE, 4)).
countdown("TAP CTRL once").
LOCAL r2 IS trace("one Ctrl tap", 4).
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
WAIT 0.3.
countdown("HOLD SHIFT for 2 s").
LOCAL r3 IS trace("Shift held 2 s", 4).
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
WAIT 0.3.
countdown("HOLD CTRL for 2 s").
LOCAL r4 IS trace("Ctrl held 2 s", 4).
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.
WAIT 0.3.
countdown("DO NOT PRESS ANY KEY").
LOCAL r5 IS trace("no keys", 2).

// ---- verdict ----
UNLOCK THROTTLE.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
LOCAL moves_up IS r1[1] - 0.5 > 0.02 OR r3[1] - 0.5 > 0.02.
LOCAL moves_down IS 0.5 - r2[0] > 0.02 OR 0.5 - r4[0] > 0.02.
LOCAL quiet IS r5[1] - r5[0] < 0.01.
say("VERDICT: Shift moves the lever up " + moves_up + ", Ctrl moves it down " + moves_down + ", still when no key is pressed " + quiet + ", write sticks " + (ABS(after_write - 0.5) < 0.01)).
say("probe_rod done. Log: " + log_path).
