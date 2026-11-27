// probe_abort_stage.ks -- throwaway probe for the 1.5 aborts, approach A. QUICKSAVE (F5) FIRST; IT WAITS FOR YOU TO STAGE.
//   RUNPATH("0:/tests/probe_abort_stage.ks").            abort stage with the descent engine burning
//   RUNPATH("0:/tests/probe_abort_stage.ks", "OFF").     abort stage after the descent engine has stopped
//   RUNPATH("0:/tests/probe_abort_stage.ks", "LIGHT").   as the first, with the descent tanks burnt down first (the worst case)
// Setup: the lander in lunar orbit (OFF may also be run landed), the descent stage activated (Space once), no time warp.
// Log: 0:/lm/logs/probe_abort_stage_<n>.log, a new number each run.
//
// Questions: (1) does Backspace show up in ABORT, also with the terminal clicked; (2) does kOS see the descent stage leave;
// (3) what does the dropped stage do (thrust, distance, damage); (4) does the ascent engine light; (5) does steering hold.
// After the staging the probe does what P71 would: throttle full, ascent engine activated, attitude held.

PARAMETER probe_mode IS "BURN".

SET CONFIG:IPU TO 2000.
GLOBAL ab_log IS "".
LOCAL run_no IS 1.
UNTIL NOT EXISTS("0:/lm/logs/probe_abort_stage_" + run_no + ".log") { SET run_no TO run_no + 1. }
SET ab_log TO "0:/lm/logs/probe_abort_stage_" + run_no + ".log".

FUNCTION ab_say {
  PARAMETER text.
  PRINT text.
  LOG text TO ab_log.
}

// ab_engine: the engine whose part name contains name_part, or 0.
FUNCTION ab_engine {
  PARAMETER name_part.
  LOCAL eng_list IS LIST().
  LIST ENGINES IN eng_list.
  FOR eng IN eng_list { IF eng:NAME:CONTAINS(name_part) { RETURN eng. } }
  RETURN 0.
}

// ab_watch_keys: log every change of ABORT for span_s seconds.
FUNCTION ab_watch_keys {
  PARAMETER label, span_s.
  LOCAL last_value IS ABORT.
  LOCAL changes IS 0.
  LOCAL stop_t IS TIME:SECONDS + span_s.
  UNTIL TIME:SECONDS >= stop_t {
    IF ABORT <> last_value {
      SET last_value TO ABORT.
      SET changes TO changes + 1.
      ab_say("  " + label + ": ABORT is now " + last_value).
    }
    WAIT 0.
  }
  ab_say(label + ": " + changes + " change(s) of ABORT").
}

LOCAL burn_mode IS probe_mode <> "OFF".
LOCAL light_mode IS probe_mode = "LIGHT".
LOCAL light_mass_t IS 8.2.        // total mass to burn down to: the descent stage then weighs about what it does at landing
LOCAL descent_eng IS ab_engine("LMDE").
LOCAL ascent_eng IS ab_engine("LMAE").

LOCAL problem IS "".
IF descent_eng:ISTYPE("Scalar") { SET problem TO "no descent engine (LMDE) found". }
ELSE IF NOT descent_eng:IGNITION { SET problem TO "the descent stage is not activated: press Space once, then run the probe again". }
IF ascent_eng:ISTYPE("Scalar") { SET problem TO "no ascent engine (LMAE) found". }
IF CORE:PART:DECOUPLEDIN >= 0 { SET problem TO "this kOS processor would be left on the descent stage". }
IF burn_mode AND SHIP:STATUS = "LANDED" { SET problem TO "landed: use the OFF run on the surface". }

IF problem <> "" {
  ab_say("STOPPED, nothing was done: " + problem).
} ELSE {
  ab_say("== Abort stage probe, " + SHIP:NAME + ", mode " + probe_mode + ", " + SHIP:STATUS + " ==").
  ab_say("mass t " + ROUND(SHIP:MASS, 3) + "  parts " + SHIP:PARTS:LENGTH + "  stage " + STAGE:NUMBER).

  // ---- Backspace ----
  ABORT OFF.
  PRINT " ".
  PRINT "1. CLICK OUTSIDE THE TERMINAL. Press Backspace 3 times, about 2 s apart.".
  ab_watch_keys("outside the terminal", 10).
  PRINT "2. CLICK THE TERMINAL. Press Backspace once.".
  ab_watch_keys("terminal clicked", 8).
  ABORT OFF.

  // ---- set up the descent burn ----
  GLOBAL ab_thr IS 0.
  GLOBAL ab_hold IS SHIP:FACING.
  SAS OFF.
  RCS ON.
  LOCK THROTTLE TO ab_thr.
  IF SHIP:STATUS <> "LANDED" {
    IF light_mode { SET ab_hold TO SHIP:UP. }      // burn away from the Moon, so the long burn cannot hit it
    LOCK STEERING TO ab_hold.
    IF light_mode {
      PRINT "Turning away from the Moon.".
      LOCAL turn_end IS TIME:SECONDS + 60.
      WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, ab_hold:FOREVECTOR) < 3 OR TIME:SECONDS > turn_end.
    }
    PRINT "Settling the propellant, then the descent engine lights.".
    SET SHIP:CONTROL:FORE TO 1.
    WAIT 8.
    SET ab_thr TO 1.
    LOCAL give_up IS TIME:SECONDS + 10.
    WAIT UNTIL descent_eng:THRUST > 0.5 * descent_eng:POSSIBLETHRUSTAT(0) OR TIME:SECONDS > give_up.
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
    WAIT 4.
    ab_say("descent engine thrust kN " + ROUND(descent_eng:THRUST, 2)).
    IF light_mode {
      PRINT "Burning the descent tanks down at 4x physics warp (about 2 minutes). Wait.".
      SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
      SET KUNIVERSE:TIMEWARP:WARP TO 3.
      WAIT UNTIL SHIP:MASS <= light_mass_t OR descent_eng:THRUST < 0.5 * descent_eng:POSSIBLETHRUSTAT(0).
      SET KUNIVERSE:TIMEWARP:WARP TO 0.
      WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
      WAIT 3.
      ab_say("burnt down: mass t " + ROUND(SHIP:MASS, 3) + "  descent thrust kN " + ROUND(descent_eng:THRUST, 2)).
    }
    IF NOT burn_mode {
      SET ab_thr TO 0.
      WAIT 8.
      ab_say("descent engine stopped, thrust kN " + ROUND(descent_eng:THRUST, 2)).
    }
  } ELSE {
    LOCK STEERING TO ab_hold.
  }

  LOCAL before_names IS LIST().
  LOCAL all_targets IS LIST().
  LIST TARGETS IN all_targets.
  FOR one_target IN all_targets { before_names:ADD(one_target:NAME). }
  LOCAL parts_before IS SHIP:PARTS:LENGTH.
  LOCAL stage_before IS STAGE:NUMBER.
  LOCAL mass_before IS SHIP:MASS.
  ab_say("before staging: ascent fuel stability " + ROUND(ascent_eng:FUELSTABILITY, 3) + "  ignitions " + ascent_eng:IGNITIONS
      + "  ascent ignition " + ascent_eng:IGNITION + "  descent thrust kN " + ROUND(descent_eng:THRUST, 2)).

  PRINT " ".
  PRINT "3. CLICK OUTSIDE THE TERMINAL, then press SPACE ONCE. (Waits 120 s.)".
  LOCAL wait_end IS TIME:SECONDS + 120.
  UNTIL SHIP:PARTS:LENGTH < parts_before OR TIME:SECONDS > wait_end { WAIT 0. }

  IF SHIP:PARTS:LENGTH >= parts_before {
    ab_say("NOTHING SEPARATED: parts " + SHIP:PARTS:LENGTH + "  stage " + stage_before + " -> " + STAGE:NUMBER).
  } ELSE {
    // ---- what P71 would do ----
    LOCAL t0 IS TIME:SECONDS.
    SET ab_thr TO 1.
    SET ascent_eng TO ab_engine("LMAE").
    LOCAL lit_by_stage IS FALSE.
    IF ascent_eng:ISTYPE("Engine") {
      SET lit_by_stage TO ascent_eng:IGNITION.
      IF NOT lit_by_stage { ascent_eng:ACTIVATE(). }
    }
    LOCAL parts_after IS SHIP:PARTS:LENGTH.
    ab_say("SEPARATED: parts " + parts_before + " -> " + parts_after + "  stage " + stage_before + " -> " + STAGE:NUMBER
        + "  mass t " + ROUND(mass_before, 3) + " -> " + ROUND(SHIP:MASS, 3)).
    ab_say("ascent engine already activated by the staging: " + lit_by_stage).

    // the dropped stage: the nearest vessel within 500 m
    LOCAL dropped IS 0.
    LOCAL nearest_m IS 500.
    LIST TARGETS IN all_targets.
    FOR one_target IN all_targets {
      IF one_target:POSITION:MAG < nearest_m {
        SET dropped TO one_target.
        SET nearest_m TO one_target:POSITION:MAG.
      }
    }
    IF dropped:ISTYPE("Vessel") {
      ab_say("dropped stage: " + dropped:NAME + " at " + ROUND(nearest_m, 2) + " m, parts " + dropped:PARTS:LENGTH
          + " (vessels listed before " + before_names:LENGTH + ", now " + all_targets:LENGTH + ")").
    } ELSE {
      ab_say("the dropped stage is NOT in LIST TARGETS: watch it and write down what it does").
    }

    ab_say("columns: t s | ascent thrust kN | ascent parts | attitude error deg | rate deg/s || dropped: distance m | closing m/s | ahead m | thrust kN | mass t").
    LOCAL next_row IS 0.
    LOCAL max_error IS 0.
    LOCAL max_rate IS 0.
    LOCAL light_t IS -1.
    LOCAL least_parts IS parts_after.
    LOCAL gone_said IS FALSE.
    UNTIL TIME:SECONDS - t0 > 20 {
      LOCAL elapsed IS TIME:SECONDS - t0.
      LOCAL thrust_kn IS 0.
      LOCAL eng_now IS ab_engine("LMAE").
      IF eng_now:ISTYPE("Engine") {
        SET thrust_kn TO eng_now:THRUST.
        IF light_t < 0 AND thrust_kn > 0.6 * eng_now:POSSIBLETHRUSTAT(0) { SET light_t TO elapsed. }
      }
      LOCAL own_parts IS SHIP:PARTS:LENGTH.
      SET least_parts TO MIN(least_parts, own_parts).
      LOCAL att_error IS VANG(SHIP:FACING:FOREVECTOR, ab_hold:FOREVECTOR).
      LOCAL rate_now IS SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI.
      SET max_error TO MAX(max_error, att_error).
      SET max_rate TO MAX(max_rate, rate_now).
      IF elapsed >= next_row {
        LOCAL row IS ROUND(elapsed, 2) + " | " + ROUND(thrust_kn, 2) + " | " + own_parts + " | " + ROUND(att_error, 2) + " | " + ROUND(rate_now, 2) + " || ".
        IF dropped:ISTYPE("Vessel") {
          IF dropped:ISDEAD {
            SET row TO row + "gone".
            IF NOT gone_said { ab_say("THE DROPPED STAGE IS GONE at t " + ROUND(elapsed, 2)). SET gone_said TO TRUE. }
          } ELSE {
            LOCAL gap IS dropped:POSITION - SHIP:POSITION.
            LOCAL closing IS 0.
            IF gap:MAG > 0 { SET closing TO -VDOT(dropped:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT, gap:NORMALIZED). }
            SET row TO row + ROUND(gap:MAG, 2) + " | " + ROUND(closing, 2) + " | " + ROUND(VDOT(gap, SHIP:FACING:FOREVECTOR), 2)
                + " | " + ROUND(dropped:THRUST, 2) + " | " + ROUND(dropped:MASS, 4).
          }
        } ELSE {
          SET row TO row + "not listed".
        }
        LOG row TO ab_log.
        IF elapsed < 5 { SET next_row TO elapsed. } ELSE { SET next_row TO elapsed + 0.5. }
      }
      WAIT 0.
    }
    ab_say("ascent engine at 60 percent after s " + ROUND(light_t, 2) + " (-1 = never)").
    ab_say("largest attitude error deg " + ROUND(max_error, 2) + "  largest rate deg/s " + ROUND(max_rate, 2)).
    ab_say("ascent stage parts: " + parts_after + " at separation, least " + least_parts + (CHOOSE "  DAMAGED" IF least_parts < parts_after ELSE "  none lost")).
    SET ascent_eng TO ab_engine("LMAE").
    IF ascent_eng:ISTYPE("Engine") { ascent_eng:SHUTDOWN(). }
  }

  SET ab_thr TO 0.
  WAIT 0.5.
  UNLOCK STEERING.
  UNLOCK THROTTLE.
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  ABORT OFF.
  SAS ON.
  ab_say("== done ==").
  PRINT "Log: " + ab_log + ". Quickload (hold F9) before the next run.".
}
