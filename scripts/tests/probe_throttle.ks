// probe_throttle.ks -- how do the RCS "fore by throttle" option, the engine shutdown and the throttle lever interact?
//   RUNPATH("0:/tests/probe_throttle.ks").
// Craft: the RO LM undocked in lunar orbit, descent engine OFF (not activated), RCS ON, SAS OFF, attitude steady.
// Log: 0:/lm/logs/probe_throttle.log. The script walks through numbered phases; each waits for a press of AG1.
// Why: design call 9 of release 1.4 (docs/superpowers/archive/plans/2026-11-23-burn-programmes.md) assumes that with the engine shut
// down and RCS on, the throttle lever fires the RCS forward (KSP's "RCS responds to throttle"), and that a LOCK THROTTLE
// blocks it. This probe measures it instead of assuming it. Tasks 5, 8 and 9 read the result.
//
// kOS cannot catch a missing suffix, so FOREBYTHROTTLE is looked up in SUFFIXNAMES before it is read.

IF EXISTS("0:/lm/logs/probe_throttle.log") { DELETEPATH("0:/lm/logs/probe_throttle.log"). }
FUNCTION pt_say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/probe_throttle.log".
}

// pt_wait: show a prompt and wait for the pilot to press action group 1 in the game (AG1 latches, so each press is one
// change of its state; the terminal need not have focus, so the keys stay free for the flight controls).
FUNCTION pt_wait {
  PARAMETER prompt_text.
  PRINT prompt_text + " (press AG1 in the game)".
  LOCAL ag_start IS AG1.
  UNTIL AG1 <> ag_start { WAIT 0.05. }
}

// pt_zero: put the throttle back to zero after a test. A momentary LOCK THROTTLE TO 0 writes the main throttle, then the lock
// is dropped so the next phase starts with no lock; the pilot lever value is also set to 0 (the lever is a key-driven value).
FUNCTION pt_zero {
  LOCK THROTTLE TO 0.
  WAIT 0.2.
  UNLOCK THROTTLE.
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
}

// pt_window: sample for window_s seconds; logs the speed change along the ship's fore axis, the lever and the engine.
FUNCTION pt_window {
  PARAMETER label, window_s.
  LOCAL fore_unit IS SHIP:FACING:FOREVECTOR.
  LOCAL v_start IS SHIP:VELOCITY:ORBIT.
  LOCAL start_lever IS SHIP:CONTROL:PILOTMAINTHROTTLE.
  LOCAL max_lever IS 0.
  LOCAL max_thrust IS 0.
  // Gravity is integrated each step and taken out, so only RCS, engine and drag show (the raw velocity change is
  // dominated by gravity, about 1.4 m/s2 in low lunar orbit).
  LOCAL grav_dv IS V(0, 0, 0).
  LOCAL t_prev IS TIME:SECONDS.
  LOCAL t_start IS t_prev.
  UNTIL TIME:SECONDS - t_start >= window_s {
    SET max_lever TO MAX(max_lever, SHIP:CONTROL:PILOTMAINTHROTTLE).
    FOR eng IN SHIP:ENGINES { SET max_thrust TO MAX(max_thrust, eng:THRUST). }
    LOCAL r_vec IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL t_now IS TIME:SECONDS.
    SET grav_dv TO grav_dv - r_vec * (SHIP:BODY:MU / r_vec:MAG ^ 3) * (t_now - t_prev).
    SET t_prev TO t_now.
    WAIT 0.1.
  }
  LOCAL dv_vec IS SHIP:VELOCITY:ORBIT - v_start - grav_dv.
  pt_say(label + ": non-gravity dv along fore " + ROUND(VDOT(dv_vec, fore_unit), 4) + " m/s in " + window_s + " s, |dv| " + ROUND(dv_vec:MAG, 4)
    + ", lever at start " + ROUND(start_lever, 3) + ", max lever " + ROUND(max_lever, 3) + ", max engine thrust " + ROUND(max_thrust, 3) + " kN").
  pt_zero().
}

pt_say("probe_throttle: " + SHIP:NAME + " at UT " + ROUND(TIME:SECONDS) + ", body " + SHIP:BODY:NAME).
pt_say("RCS " + RCS + ", SAS " + SAS + ", engines: " + SHIP:ENGINES:LENGTH).

// Phase 1: is the suffix there, and what is its value?
LOCAL rcs_parts IS SHIP:RCS.
pt_say("phase 1: RCS parts found: " + rcs_parts:LENGTH).
LOCAL fbt_known IS FALSE.
IF rcs_parts:LENGTH > 0 {
  IF rcs_parts[0]:SUFFIXNAMES:CONTAINS("FOREBYTHROTTLE") {
    SET fbt_known TO TRUE.
    pt_say("phase 1: FOREBYTHROTTLE available, first RCS part reads " + rcs_parts[0]:FOREBYTHROTTLE).
  }
}
IF NOT fbt_known { pt_say("phase 1: FOREBYTHROTTLE NOT AVAILABLE on this kOS (the throttle-fires-RCS test below still runs)"). }

// Phase 2: engine off, no throttle lock: lever up fires the RCS?
pt_wait("phase 2: engine off, NO throttle lock. Press AG1, then Z (full throttle) at once; the window is 3 s, then press X (throttle cut)").
pt_window("phase 2 (no lock, engine off)", 3).

// Phase 3: the same with LOCK THROTTLE TO 0.
LOCK THROTTLE TO 0.
pt_wait("phase 3: LOCK THROTTLE TO 0 is now set. Press AG1, then Z (full throttle) at once; the window is 3 s, then press X").
pt_window("phase 3 (throttle locked to 0)", 3).
UNLOCK THROTTLE.

// Phase 4: FOREBYTHROTTLE off on every RCS part (only if the suffix exists).
IF fbt_known {
  FOR rcs_part IN rcs_parts { SET rcs_part:FOREBYTHROTTLE TO FALSE. }
  pt_wait("phase 4: FOREBYTHROTTLE set FALSE on all RCS parts. Press AG1, then Z (full throttle) at once; the window is 3 s, then press X").
  pt_window("phase 4 (FOREBYTHROTTLE off)", 3).
  FOR rcs_part IN rcs_parts { SET rcs_part:FOREBYTHROTTLE TO TRUE. }
  pt_say("phase 4: FOREBYTHROTTLE set back to TRUE").
}

// Phase 5: light the descent engine at lever zero, then shut it down; does the lever fire the RCS afterwards?
pt_wait("phase 5: press X so the lever is at zero, then press AG1 to activate the descent engine; do NOT touch the lever after").
pt_say("phase 5: lever before activation " + ROUND(SHIP:CONTROL:PILOTMAINTHROTTLE, 3)).
LOCAL dps IS SHIP:ENGINES[0].
// The descent engine is the throttleable one (the ascent engine has min throttle 1); MAXTHRUST of an inactive engine can read 0.
FOR eng IN SHIP:ENGINES { IF eng:MINTHROTTLE < 0.99 { SET dps TO eng. } }
pt_say("phase 5: engine " + dps:TITLE + ", min throttle " + ROUND(dps:MINTHROTTLE, 3) + ", ignitions left " + dps:IGNITIONS).
dps:ACTIVATE().
WAIT 3.
pt_say("phase 5: lever zero, engine lit: thrust " + ROUND(dps:THRUST, 3) + " kN, throttle fraction " + ROUND(dps:THRUST / MAX(dps:MAXTHRUST, 0.001), 3)).
dps:SHUTDOWN().
WAIT 1.
pt_wait("phase 5b: engine shut down. Press AG1, then Z (full throttle) at once; the window is 3 s, then press X").
pt_window("phase 5b (engine shut down after use)", 3).

pt_say("probe_throttle: done. Send back 0:/lm/logs/probe_throttle.log").
