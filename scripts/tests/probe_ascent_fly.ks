// probe_ascent_fly.ks -- throwaway probe for release 1.5 (ascent). IT SEPARATES THE STAGES, LIGHTS THE ASCENT ENGINE AND
// FLIES TO ORBIT. QUICKSAVE (F5) FIRST; quickload (hold F9) to get the landed ship back.
//   RUNPATH("0:/tests/probe_ascent_fly.ks").
// Setup: the lander landed on the Moon, upright, throttle at zero. Optionally target the CSM first: the probe then flies in
// the CSM's direction of travel; with no target it flies west. No time warp. About 8 minutes. Ctrl+C stops it (then
// type UNLOCK ALL. and use X for the throttle). Log: 0:/lm/logs/probe_ascent_fly.log
//
// Questions it answers: (1) can kOS separate and light in one go, and what does separation do to the ascent stage;
// (2) can kOS steering hold the ascent stage on RCS alone for the whole burn (no gimbal), and how much RCS propellant
// does it cost; (3) how exactly does a timed engine cut-off land on the target speed.
// The steering law here is a stand-in, NOT the Luminary guidance: vertical rise to 40 ft/s, then a pitch that aims for
// 60 000 ft, 32 ft/s up and 5535 ft/s forward (Apollo 11 targets). Pitch command moves at most 10 deg/s.

SET CONFIG:IPU TO 500.
LOCAL log_path IS "0:/lm/logs/probe_ascent_fly.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

// fly_say, not say: probe_ascent_all runs probe_ascent.ks first, and its say() would win over a second one.
FUNCTION fly_say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/probe_ascent_fly.log".
}

LOCAL g_zero IS 9.80665.
LOCAL rise_speed IS 12.19.        // m/s, 40 ft/s
LOCAL target_height IS 18288.     // m above the launch radius, 60 000 ft
LOCAL target_climb IS 9.81.       // m/s, 32.2 ft/s
LOCAL target_speed IS 1687.07.    // m/s, 5535 ft/s
LOCAL pitch_rate IS 10.           // deg/s

// ---- find what we need; stop before touching anything if something is missing ----
LOCAL ascent_eng IS 0.
LOCAL engines_list IS LIST().
LIST ENGINES IN engines_list.
FOR eng IN engines_list { IF eng:NAME:CONTAINS("LMAE") { SET ascent_eng TO eng. } }

LOCAL sep_module IS 0.
LOCAL sep_event IS "".
FOR prt IN SHIP:PARTS {
  IF prt:NAME:CONTAINS("LEMDecoupler") {
    FOR module_name IN prt:MODULES {
      IF module_name:CONTAINS("Decouple") {
        LOCAL mdl IS prt:GETMODULE(module_name).
        FOR event_name IN mdl:ALLEVENTNAMES {
          IF event_name:CONTAINS("decouple") AND NOT event_name:CONTAINS("staging") AND sep_event = "" {
            SET sep_module TO mdl.
            SET sep_event TO event_name.
          }
        }
      }
    }
  }
}

LOCAL problem IS "".
IF ascent_eng:ISTYPE("Scalar") { SET problem TO "no ascent engine (LMAE) found". }
IF sep_event = "" { SET problem TO "no decouple event found on the LM decoupler (run probe_ascent.ks and send the log)". }
IF CORE:PART:DECOUPLEDIN >= 0 { SET problem TO "this kOS processor would be left on the descent stage". }
IF SHIP:STATUS <> "LANDED" { SET problem TO "the ship is not landed (status " + SHIP:STATUS + ")". }

IF problem <> "" {
  fly_say("STOPPED, nothing was fired: " + problem).
} ELSE {
  LOCAL up0 IS (-SHIP:BODY:POSITION):NORMALIZED.
  LOCAL forward0 IS VXCL(up0, HEADING(270, 0):VECTOR):NORMALIZED.
  LOCAL heading_source IS "west (no target)".
  IF HASTARGET {
    LOCAL tgt_pos IS TARGET:POSITION - SHIP:BODY:POSITION.
    LOCAL tgt_normal IS VCRS(tgt_pos, TARGET:VELOCITY:ORBIT).
    SET forward0 TO VXCL(up0, VCRS(tgt_normal, up0)):NORMALIZED.
    SET heading_source TO "the plane of " + TARGET:NAME.
  }
  LOCAL plane_normal IS VCRS(up0, forward0).
  LOCAL start_radius IS SHIP:BODY:POSITION:MAG.

  fly_say("== Ascent fly probe, heading from " + heading_source + " ==").
  fly_say("decouple event '" + sep_event + "'  engine " + ascent_eng:NAME + "  fuel stability " + ROUND(ascent_eng:FUELSTABILITY, 3)
      + "  ignitions " + ascent_eng:IGNITIONS).
  fly_say("mass before t " + ROUND(SHIP:MASS, 3)).
  fly_say("mission time before separation s " + ROUND(MISSIONTIME, 1) + " (does separating restart it? compare with the end)").
  PRINT "Did you quicksave (F5)? Separation in 10 s, Ctrl+C to stop.".
  FROM { LOCAL n IS 10. } UNTIL n = 0 STEP { SET n TO n - 1. } DO { PRINT n. WAIT 1. }

  GLOBAL probe_dir IS up0.
  GLOBAL probe_top IS -forward0.
  GLOBAL probe_thr IS 0.
  SAS OFF.
  RCS ON.
  LOCK THROTTLE TO probe_thr.
  STEERINGMANAGER:RESETTODEFAULT().
  FOR eng IN engines_list { IF eng:NAME:CONTAINS("LMDE") { eng:SHUTDOWN(). } }

  // ---- separate and light in the same tick ----
  sep_module:DOEVENT(sep_event).
  ascent_eng:ACTIVATE().
  SET probe_thr TO 1.
  LOCAL t0 IS TIME:SECONDS.
  LOCK STEERING TO LOOKDIRUP(probe_dir, probe_top).

  LOCAL burn_done IS FALSE.
  LOCAL refound IS FALSE.
  LOCAL reason IS "".
  LOCAL pitched IS FALSE.
  LOCAL pitch_cmd IS 0.             // degrees from the vertical
  LOCAL last_time IS t0.
  LOCAL next_row IS 0.
  LOCAL mass0 IS 0.
  LOCAL rcs_kg IS 0.
  LOCAL engine_kg IS 0.             // ascent engine propellant since mass0, from its thrust
  LOCAL max_error IS 0.
  LOCAL max_rate IS 0.
  LOCAL bad_since IS -1.

  fly_say("columns: t s | height m | climb m/s | forward m/s | side m/s | pitch cmd deg | attitude error deg | roll error deg | rates deg/s x y z | mass t | thrust kN | rcs used kg").
  UNTIL burn_done {
    IF NOT refound {
      WAIT 0.
      LIST ENGINES IN engines_list.
      FOR eng IN engines_list { IF eng:NAME:CONTAINS("LMAE") { SET ascent_eng TO eng. } }
      SET refound TO TRUE.
    }
    LOCAL now_t IS TIME:SECONDS.
    LOCAL tick IS now_t - last_time.
    SET last_time TO now_t.
    LOCAL elapsed IS now_t - t0.
    IF mass0 = 0 AND elapsed > 0.5 { SET mass0 TO SHIP:MASS. fly_say("mass after separation t " + ROUND(mass0, 3) + " at t " + ROUND(elapsed, 2)). }

    LOCAL up_now IS (-SHIP:BODY:POSITION):NORMALIZED.
    LOCAL fwd_now IS VCRS(plane_normal, up_now):NORMALIZED.
    LOCAL side_now IS plane_normal:NORMALIZED.
    LOCAL radius_now IS SHIP:BODY:POSITION:MAG.
    LOCAL height_now IS radius_now - start_radius.
    LOCAL vel IS SHIP:VELOCITY:ORBIT.
    LOCAL climb IS VDOT(vel, up_now).
    LOCAL fwd_speed IS VDOT(vel, fwd_now).
    LOCAL side_speed IS VDOT(vel, side_now).
    LOCAL gravity IS SHIP:BODY:MU / radius_now ^ 2.
    LOCAL g_eff IS gravity - fwd_speed ^ 2 / radius_now.
    LOCAL thrust_kn IS ascent_eng:THRUST.
    LOCAL accel IS MAX(0.5, ascent_eng:AVAILABLETHRUST / SHIP:MASS).

    // time to go from the rocket equation on the forward speed still needed
    LOCAL exhaust IS ascent_eng:VACUUMISP * g_zero.
    LOCAL burn_up IS exhaust / accel.
    LOCAL speed_left IS target_speed - fwd_speed.
    LOCAL time_left IS burn_up * (1 - CONSTANT:E ^ (-speed_left / exhaust)).

    IF NOT pitched AND climb >= rise_speed { SET pitched TO TRUE. fly_say("pitchover at t " + ROUND(elapsed, 1) + " height " + ROUND(height_now)). }
    IF pitched {
      LOCAL climb_left IS target_climb - climb.
      LOCAL radial IS 0.
      IF time_left > 10 {
        SET radial TO 6 * (target_height - height_now - climb * time_left) / time_left ^ 2 - 2 * climb_left / time_left.
      } ELSE {
        SET radial TO climb_left / MAX(time_left, 2).
      }
      LOCAL wanted IS ARCCOS(MAX(0, MIN(1, (radial + g_eff) / accel))).
      SET pitch_cmd TO pitch_cmd + MAX(-pitch_rate * tick, MIN(pitch_rate * tick, wanted - pitch_cmd)).
    }
    LOCAL side_cmd IS 0.
    IF pitched { SET side_cmd TO MAX(-0.1, MIN(0.1, -side_speed / 20 / accel)). }
    SET probe_dir TO (up_now * COS(pitch_cmd) + fwd_now * SIN(pitch_cmd) + side_now * side_cmd):NORMALIZED.
    // the top of the ship points away from the ground once pitched, so the window faces down, as on the real ascent
    SET probe_top TO up_now * SIN(pitch_cmd) - fwd_now * COS(pitch_cmd).

    LOCAL att_error IS VANG(SHIP:FACING:FOREVECTOR, probe_dir).
    LOCAL roll_error IS VANG(VXCL(probe_dir, SHIP:FACING:TOPVECTOR), VXCL(probe_dir, probe_top)).
    LOCAL rates IS (SHIP:FACING:INVERSE * SHIP:ANGULARVEL) * (180 / CONSTANT:PI).
    // RCS parts give no current thrust on this install: RCS use = mass lost since mass0 less the engine's share
    // (thrust over exhaust speed is t/s).
    IF mass0 > 0 {
      SET engine_kg TO engine_kg + thrust_kn / exhaust * 1000 * tick.
      SET rcs_kg TO (mass0 - SHIP:MASS) * 1000 - engine_kg.
    }
    IF elapsed > 1 {
      SET max_error TO MAX(max_error, att_error).
      SET max_rate TO MAX(max_rate, rates:MAG).
    }

    IF elapsed >= next_row {
      LOG ROUND(elapsed, 2) + " | " + ROUND(height_now) + " | " + ROUND(climb, 2) + " | " + ROUND(fwd_speed, 1) + " | " + ROUND(side_speed, 2)
          + " | " + ROUND(pitch_cmd, 1) + " | " + ROUND(att_error, 2) + " | " + ROUND(roll_error, 2)
          + " | " + ROUND(rates:X, 2) + " " + ROUND(rates:Y, 2) + " " + ROUND(rates:Z, 2)
          + " | " + ROUND(SHIP:MASS, 4) + " | " + ROUND(thrust_kn, 3) + " | " + ROUND(rcs_kg, 1) TO log_path.
      IF elapsed < 20 { SET next_row TO elapsed + 0.2. } ELSE { SET next_row TO elapsed + 5. }
      PRINT "t " + ROUND(elapsed) + "  h " + ROUND(height_now) + "  fwd " + ROUND(fwd_speed) + "  err " + ROUND(att_error, 1) + "      ".
    }

    // ---- cut-off and safety stops ----
    LOCAL forward_accel IS MAX(0.5, accel * SIN(pitch_cmd)).
    IF pitched AND speed_left <= forward_accel * 0.3 {
      WAIT MAX(0, speed_left / forward_accel).
      SET reason TO "target speed".
    }
    IF elapsed > 3 AND thrust_kn < 0.1 { SET reason TO "no thrust (flameout, or the engine did not light)". }
    IF elapsed > 700 { SET reason TO "time limit". }
    IF pitched AND (climb < -30 OR height_now < -100) { SET reason TO "falling". }
    IF att_error > 45 AND elapsed > 3 {
      IF bad_since < 0 { SET bad_since TO elapsed. }
      IF elapsed - bad_since > 10 { SET reason TO "lost attitude control". }
    } ELSE { SET bad_since TO -1. }
    IF reason <> "" { SET burn_done TO TRUE. } ELSE { WAIT 0. }
  }

  SET probe_thr TO 0.
  LOCAL cut_time IS TIME:SECONDS - t0.
  fly_say("CUT-OFF at t " + ROUND(cut_time, 2) + ": " + reason).
  WAIT 3.
  LOCAL up_end IS (-SHIP:BODY:POSITION):NORMALIZED.
  LOCAL fwd_end IS VCRS(plane_normal, up_end):NORMALIZED.
  fly_say("3 s after cut-off: height m " + ROUND(SHIP:BODY:POSITION:MAG - start_radius) + "  climb " + ROUND(VDOT(SHIP:VELOCITY:ORBIT, up_end), 2)
      + "  forward " + ROUND(VDOT(SHIP:VELOCITY:ORBIT, fwd_end), 2) + " (target " + target_speed + ")  side "
      + ROUND(VDOT(SHIP:VELOCITY:ORBIT, plane_normal:NORMALIZED), 2)).
  fly_say("orbit: apoapsis m " + ROUND(SHIP:ORBIT:APOAPSIS) + "  periapsis m " + ROUND(SHIP:ORBIT:PERIAPSIS)).
  fly_say("largest attitude error deg " + ROUND(max_error, 2) + "  largest rate deg/s " + ROUND(max_rate, 2)).
  fly_say("mass t: after separation " + ROUND(mass0, 3) + "  now " + ROUND(SHIP:MASS, 3)).
  fly_say("mission time at the end s " + ROUND(MISSIONTIME, 1)).
  fly_say("RCS propellant used kg (mass lost less engine, up to the last pass) " + ROUND(rcs_kg, 1) + "  engine at rated flow over the burn kg "
      + ROUND(ascent_eng:MAXMASSFLOW * 1000 * cut_time, 1)).
  FOR res IN SHIP:RESOURCES { fly_say("left: " + res:NAME + " " + ROUND(res:AMOUNT, 1)). }

  UNLOCK STEERING.
  UNLOCK THROTTLE.
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  SAS ON.
  fly_say("== done ==").
}
