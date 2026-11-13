// probe_control.ks -- reads and exercises the kOS controls that P63's control layer (lm_control.ks) will use.
//   RUNPATH("0:/tests/probe_control.ks").
// Log: 0:/lm/logs/probe_control.log (read it back; the terminal cannot be copied from).
//
// Names checked against the kOS docs (KOS_DOC _sources, 2026-11-12) before this was written:
//   SHIP:CONTROL:PILOTPITCH / PILOTYAW / PILOTROLL   get-only, scalar [-1,1], what the PLAYER is doing
//                                                    (commands/flight/pilot.rst)
//   SHIP:CONTROL:FORE                                raw translation fore/aft [-1,1], needs RCS ON, 5 % null zone
//                                                    (commands/flight/raw.rst); SHIP:CONTROL:NEUTRALIZE gives control back
//   RCS, SAS                                         ON/OFF toggles (commands/flight/systems.rst)
//   SASMODE                                          string; "STABILITYASSIST" is valid; do not use it together with
//                                                    LOCK STEERING, so unlock steering first (same page)
//   SHIP:FACING:FOREVECTOR / TOPVECTOR / STARVECTOR  ship axes in raw coordinates (math/direction.rst)
//   SHIP:RCS                                         list of the RCS thrusters (structures/vessels/vessel.rst)
//
// Setup: the Moon, any orbit, the Realism Overhaul LM upright (engine down, nose up), tanks full, SAS and RCS OFF.
// The script asks you to move the stick fully for 5 s, then to leave it alone for 5 s.

LOCAL log_path IS "0:/lm/logs/probe_control.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

// vec_text: a vector as three rounded numbers, for the log.
FUNCTION vec_text {
  PARAMETER vec.
  RETURN "(" + ROUND(vec:X, 4) + ", " + ROUND(vec:Y, 4) + ", " + ROUND(vec:Z, 4) + ")".
}

// watch: the largest absolute pilot input seen over secs seconds, sampled every 0.05 s.
FUNCTION watch {
  PARAMETER secs.
  LOCAL biggest IS 0.
  LOCAL t_end IS TIME:SECONDS + secs.
  UNTIL TIME:SECONDS >= t_end {
    LOCAL now_max IS MAX(ABS(SHIP:CONTROL:PILOTPITCH), MAX(ABS(SHIP:CONTROL:PILOTYAW), ABS(SHIP:CONTROL:PILOTROLL))).
    IF now_max > biggest { SET biggest TO now_max. }
    WAIT 0.05.
  }
  RETURN biggest.
}

say("probe_control: " + SHIP:NAME + " at " + SHIP:BODY:NAME + ", UT " + ROUND(TIME:SECONDS)).

// ---- Pilot input names: read now (the stick should be centred) ----
say("PILOTPITCH " + SHIP:CONTROL:PILOTPITCH + "  PILOTYAW " + SHIP:CONTROL:PILOTYAW + "  PILOTROLL " + SHIP:CONTROL:PILOTROLL).

// ---- SAS and RCS toggles, SASMODE read-back ----
say("start: SAS " + SAS + ", RCS " + RCS + ", SASMODE " + SASMODE).
RCS ON.
say("RCS set ON, reads " + RCS).
RCS OFF.
SAS ON.
SET SASMODE TO "STABILITYASSIST".
say("SAS set ON + STABILITYASSIST, SAS reads " + SAS + ", SASMODE reads " + SASMODE).
SAS OFF.
say("SAS set OFF, reads " + SAS).

// ---- Ship axes in raw coordinates, and against the local vertical ----
LOCAL up_vec IS SHIP:UP:VECTOR.
say("FACING fore " + vec_text(SHIP:FACING:FOREVECTOR) + "  top " + vec_text(SHIP:FACING:TOPVECTOR) + "  star " + vec_text(SHIP:FACING:STARVECTOR)).
say("angle to local up (deg): fore " + ROUND(VANG(SHIP:FACING:FOREVECTOR, up_vec), 1) + ", top " + ROUND(VANG(SHIP:FACING:TOPVECTOR, up_vec), 1)
    + ", star " + ROUND(VANG(SHIP:FACING:STARVECTOR, up_vec), 1)).
say("Which face is the crew window on (TOP / BOTTOM / STAR / PORT)? Tell Claude; it sets WINDOW_AXIS in lm_constants.ks.").

// ---- RCS thrusters, mass, thrust ----
LOCAL rcs_count IS 0.
LOCAL rcs_fore IS 0.
FOR thruster IN SHIP:RCS {
  SET rcs_count TO rcs_count + 1.
  IF thruster:FOREENABLED { SET rcs_fore TO rcs_fore + 1. }
}
say("RCS thrusters: " + rcs_count + " (fore/aft enabled on " + rcs_fore + ")").
say("MASS " + ROUND(SHIP:MASS, 3) + " t, AVAILABLETHRUST " + ROUND(SHIP:AVAILABLETHRUST, 2) + " kN").

// ---- Ullage push: RCS ON, FORE 1 for 1 s, then give the controls back ----
// The orbital velocity changes by gravity alone (about 1.6 m/s per second at the Moon), which swamped the push in the
// first run. So the change is measured twice, once coasting (baseline) and once pushing, and the difference is the push.
RCS ON.
LOCAL v_before IS SHIP:VELOCITY:ORBIT.
WAIT 1.
LOCAL coast_dv IS VDOT(SHIP:VELOCITY:ORBIT - v_before, SHIP:FACING:FOREVECTOR).
SET v_before TO SHIP:VELOCITY:ORBIT.
SET SHIP:CONTROL:FORE TO 1.
WAIT 1.
LOCAL push_dv IS VDOT(SHIP:VELOCITY:ORBIT - v_before, SHIP:FACING:FOREVECTOR).
SET SHIP:CONTROL:FORE TO 0.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
RCS OFF.
say("coasting 1 s: change along fore " + ROUND(coast_dv, 4) + " m/s; pushing FORE 1 for 1 s: " + ROUND(push_dv, 4) + " m/s").
say("RCS push (difference) " + ROUND(push_dv - coast_dv, 4) + " m/s (expect about +0.1 for a 16 t lander and 4 jets)").

// ---- Stick: full for 5 s, then still for 5 s ----
say("MOVE THE STICK FULLY (any axis) for 5 s, starting now.").
LOCAL deflected IS watch(5).
say("max |pilot input| while moving: " + ROUND(deflected, 3)).
say("LET GO OF THE STICK NOW. Reading starts in 2 s and lasts 5 s.").
WAIT 2.                                   // time to react: the reading must not include the end of the movement
LOCAL still IS watch(5).
say("max |pilot input| while still: " + ROUND(still, 3)).
say("probe_control done. Log: " + log_path).
