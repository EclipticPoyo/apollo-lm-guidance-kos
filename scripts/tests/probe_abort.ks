// probe_abort.ks -- throwaway probes for the 1.5 aborts (spec section 12). QUICKSAVE (F5) FIRST; quickload (hold F9) after each run.
//   RUNPATH("0:/tests/probe_abort.ks", "KEYS").     the 0 key, Backspace and Space as kOS sees them (Space last: it stages)
//   RUNPATH("0:/tests/probe_abort.ks", "BURN").     computer staging with the descent engine burning (press 0 when asked)
//   RUNPATH("0:/tests/probe_abort.ks", "LIGHT").    as BURN, with the descent tanks burnt down first
//   RUNPATH("0:/tests/probe_abort.ks", "OFF").      computer staging with the descent engine off for 30 s; also run landed
//   RUNPATH("0:/tests/probe_abort.ks", "LOW").      from your own hover at 20 to 50 m (SAS on): press 0
//   RUNPATH("0:/tests/probe_abort.ks", "TURN").     the full ship turned 150 degrees through the vertical at full thrust
//   RUNPATH("0:/tests/probe_abort.ks", "RCS").      what pushes the ship forward with every engine dead, and what stops it
// Setup: the lander with the descent stage activated (Space once), no time warp; in lunar orbit unless the mode says otherwise. RCS may also
// be run on the ascent stage alone (after a BURN run, without quickloading). Log: 0:/lm/logs/probe_abort_<mode>_<n>.log, a new number each run.
// The staging runs use the computer's own staging (ctl_stage_ascent) with the throttle full, as P71 will.

PARAMETER probe_mode IS "KEYS".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").       // ctl_stage_ascent, ctl_descent_attached, ctl_start, ctl_set_command, win_min_rotation

SET CONFIG:IPU TO 2000.
GLOBAL pa_log IS "".
LOCAL pa_run IS 1.
UNTIL NOT EXISTS("0:/lm/logs/probe_abort_" + probe_mode + "_" + pa_run + ".log") { SET pa_run TO pa_run + 1. }
SET pa_log TO "0:/lm/logs/probe_abort_" + probe_mode + "_" + pa_run + ".log".
GLOBAL pa_thr IS 0.
GLOBAL pa_hold IS SHIP:FACING.

FUNCTION pa_say {
  PARAMETER text.
  PRINT text.
  LOG text TO pa_log.
}

// pa_engine: the engine whose part name contains name_part, or 0.
FUNCTION pa_engine {
  PARAMETER name_part.
  LOCAL eng_list IS LIST().
  LIST ENGINES IN eng_list.
  FOR eng IN eng_list { IF eng:NAME:CONTAINS(name_part) { RETURN eng. } }
  RETURN 0.
}

FUNCTION pa_rate_deg_s { RETURN SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI. }

// ---- KEYS ----------------------------------------------------------------------------------------------------------------------
FUNCTION pa_keys {
  PRINT "In the next 60 s, outside the terminal: 0 twice, Backspace once. Click the terminal: 0 once, Backspace once.".
  PRINT "Then click outside it and press Space once (H craft: twice, 3 s apart).".
  LOCAL last_ag IS AG10.
  LOCAL last_abort IS ABORT.
  LOCAL last_parts IS SHIP:PARTS:LENGTH.
  LOCAL last_stage IS STAGE:NUMBER.
  LOCAL last_attached IS ctl_descent_attached().
  LOCAL t0 IS TIME:SECONDS.
  UNTIL TIME:SECONDS - t0 > 60 {
    LOCAL at_s IS ROUND(TIME:SECONDS - t0, 2).
    IF AG10 <> last_ag { SET last_ag TO AG10. pa_say(at_s + " s: AG10 is now " + last_ag). }
    IF ABORT <> last_abort { SET last_abort TO ABORT. pa_say(at_s + " s: ABORT is now " + last_abort). }
    IF STAGE:NUMBER <> last_stage { SET last_stage TO STAGE:NUMBER. pa_say(at_s + " s: stage number " + last_stage). }
    IF SHIP:PARTS:LENGTH <> last_parts { SET last_parts TO SHIP:PARTS:LENGTH. pa_say(at_s + " s: parts " + last_parts). }
    LOCAL attached_now IS ctl_descent_attached().
    IF attached_now <> last_attached { SET last_attached TO attached_now. pa_say(at_s + " s: descent stage attached " + attached_now). }
    WAIT 0.
  }
  pa_say("KEYS done: attached " + ctl_descent_attached() + "  parts " + SHIP:PARTS:LENGTH + "  stage " + STAGE:NUMBER).
}

// ---- the staging runs ----------------------------------------------------------------------------------------------------------

// pa_light_descent: settle with the RCS, then the descent engine at full thrust (the engine must be activated: Space once before the probe).
FUNCTION pa_light_descent {
  LOCAL descent_eng IS pa_engine("LMDE").
  PRINT "Settling the propellant, then the descent engine lights.".
  SET SHIP:CONTROL:FORE TO 1.
  WAIT 8.
  SET pa_thr TO 1.
  LOCAL give_up IS TIME:SECONDS + 10.
  WAIT UNTIL descent_eng:THRUST > 0.5 * descent_eng:POSSIBLETHRUSTAT(0) OR TIME:SECONDS > give_up.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  WAIT 4.
  pa_say("descent engine thrust kN " + ROUND(descent_eng:THRUST, 2) + "  mass t " + ROUND(SHIP:MASS, 3)).
}

// pa_burn_down: burn the descent tanks to a total mass of 8.2 t at 4x physics warp.
FUNCTION pa_burn_down {
  LOCAL descent_eng IS pa_engine("LMDE").
  PRINT "Burning the descent tanks down at 4x physics warp (about 2 minutes). Wait.".
  SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
  SET KUNIVERSE:TIMEWARP:WARP TO 3.
  WAIT UNTIL SHIP:MASS <= 8.2 OR descent_eng:THRUST < 0.5 * descent_eng:POSSIBLETHRUSTAT(0).
  SET KUNIVERSE:TIMEWARP:WARP TO 0.
  WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
  WAIT 3.
  pa_say("burnt down: mass t " + ROUND(SHIP:MASS, 3) + "  descent thrust kN " + ROUND(descent_eng:THRUST, 2)).
}

// pa_stage_and_watch: wait for the 0 key, stage as P71 will, then 20 s of rows about both stages.
FUNCTION pa_stage_and_watch {
  PARAMETER take_over_hover.
  LOCAL all_targets IS LIST().
  PRINT " ".
  PRINT "CLICK OUTSIDE THE TERMINAL, then press 0 ONCE. (Waits 180 s.)".
  LOCAL ag_was IS AG10.
  LOCAL wait_end IS TIME:SECONDS + 180.
  WAIT UNTIL AG10 <> ag_was OR TIME:SECONDS > wait_end.
  IF AG10 = ag_was { pa_say("0 WAS NOT SEEN: nothing staged"). RETURN. }
  LOCAL t0 IS TIME:SECONDS.
  SET pa_thr TO 1.
  IF take_over_hover {
    SAS OFF.
    RCS ON.
    SET pa_hold TO SHIP:UP.
    LOCK THROTTLE TO pa_thr.
    LOCK STEERING TO pa_hold.
  }
  LOCAL ascent_eng IS pa_engine("LMAE").
  LOCAL descent_eng IS pa_engine("LMDE").
  pa_say("before staging: parts " + SHIP:PARTS:LENGTH + "  stage " + STAGE:NUMBER + "  attached " + ctl_descent_attached() + "  mass t "
      + ROUND(SHIP:MASS, 3) + "  descent thrust kN " + ROUND(descent_eng:THRUST, 2) + "  ascent fuel stability " + ROUND(ascent_eng:FUELSTABILITY, 3)
      + "  ignitions " + ascent_eng:IGNITIONS + "  height m " + ROUND(ALT:RADAR) + "  speed m/s " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 1)).
  LOCAL parts_before IS SHIP:PARTS:LENGTH.
  LOCAL why IS ctl_stage_ascent(ascent_eng).
  WAIT 0.
  pa_say("ctl_stage_ascent: " + (CHOOSE "ok" IF why = "" ELSE why) + "  took s " + ROUND(TIME:SECONDS - t0, 2)).
  pa_say("after staging: parts " + SHIP:PARTS:LENGTH + "  stage " + STAGE:NUMBER + "  attached " + ctl_descent_attached() + "  mass t " + ROUND(SHIP:MASS, 3)).
  LOCAL parts_after IS SHIP:PARTS:LENGTH.

  LOCAL dropped IS 0.
  LOCAL nearest_m IS 500.
  LIST TARGETS IN all_targets.
  FOR one_target IN all_targets {
    IF one_target:POSITION:MAG < nearest_m {
      SET dropped TO one_target.
      SET nearest_m TO one_target:POSITION:MAG.
    }
  }
  IF dropped:ISTYPE("Vessel") { pa_say("dropped stage: " + dropped:NAME + " at " + ROUND(nearest_m, 2) + " m"). }
  ELSE { pa_say("the dropped stage is NOT in LIST TARGETS (parts before " + parts_before + "): watch it and write down what it does"). }

  pa_say("columns: t s | ascent thrust kN | parts | attitude error deg | rate deg/s || dropped: distance m | closing m/s | ahead m | thrust kN").
  LOCAL next_row IS 0.
  LOCAL max_error IS 0.
  LOCAL max_rate IS 0.
  LOCAL light_s IS -1.
  LOCAL least_parts IS parts_after.
  UNTIL TIME:SECONDS - t0 > 20 {
    LOCAL elapsed IS TIME:SECONDS - t0.
    LOCAL eng_now IS pa_engine("LMAE").
    LOCAL thrust_kn IS 0.
    IF eng_now:ISTYPE("Engine") {
      SET thrust_kn TO eng_now:THRUST.
      IF light_s < 0 AND thrust_kn > 0.6 * eng_now:POSSIBLETHRUSTAT(0) { SET light_s TO elapsed. }
    }
    SET least_parts TO MIN(least_parts, SHIP:PARTS:LENGTH).
    LOCAL att_error IS VANG(SHIP:FACING:FOREVECTOR, pa_hold:FOREVECTOR).
    SET max_error TO MAX(max_error, att_error).
    SET max_rate TO MAX(max_rate, pa_rate_deg_s()).
    IF elapsed >= next_row {
      LOCAL row IS ROUND(elapsed, 2) + " | " + ROUND(thrust_kn, 2) + " | " + SHIP:PARTS:LENGTH + " | " + ROUND(att_error, 2) + " | " + ROUND(pa_rate_deg_s(), 2) + " || ".
      IF dropped:ISTYPE("Vessel") {
        IF dropped:ISDEAD { SET row TO row + "gone". }
        ELSE {
          LOCAL gap IS dropped:POSITION - SHIP:POSITION.
          LOCAL closing IS 0.
          IF gap:MAG > 0 { SET closing TO -VDOT(dropped:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT, gap:NORMALIZED). }
          SET row TO row + ROUND(gap:MAG, 2) + " | " + ROUND(closing, 2) + " | " + ROUND(VDOT(gap, SHIP:FACING:FOREVECTOR), 2) + " | " + ROUND(dropped:THRUST, 2).
        }
      } ELSE { SET row TO row + "not listed". }
      LOG row TO pa_log.
      IF elapsed < 5 { SET next_row TO elapsed. } ELSE { SET next_row TO elapsed + 0.5. }
    }
    WAIT 0.
  }
  pa_say("ascent engine at 60 percent after s " + ROUND(light_s, 2) + " (-1 = never)").
  pa_say("largest attitude error deg " + ROUND(max_error, 2) + "  largest rate deg/s " + ROUND(max_rate, 2)).
  pa_say("ascent stage parts " + parts_after + ", least " + least_parts + (CHOOSE "  DAMAGED" IF least_parts < parts_after ELSE "  none lost")).
}

FUNCTION pa_staging_run {
  IF probe_mode = "LOW" {
    pa_stage_and_watch(TRUE).
    UNLOCK STEERING.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 1.      // the ascent engine keeps burning: quickload now
    UNLOCK THROTTLE.
    SAS ON.
    RETURN.
  }
  SET pa_hold TO SHIP:FACING.
  IF probe_mode = "LIGHT" { SET pa_hold TO SHIP:UP. }      // burn away from the Moon, so the long burn cannot hit it
  SAS OFF.
  RCS ON.
  LOCK THROTTLE TO pa_thr.
  LOCK STEERING TO pa_hold.
  IF SHIP:STATUS <> "LANDED" {
    IF probe_mode = "LIGHT" {
      PRINT "Turning away from the Moon.".
      LOCAL turn_end IS TIME:SECONDS + 60.
      WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, pa_hold:FOREVECTOR) < 3 OR TIME:SECONDS > turn_end.
    }
    pa_light_descent().
    IF probe_mode = "LIGHT" { pa_burn_down(). }
    IF probe_mode = "OFF" {
      SET pa_thr TO 0.
      PRINT "Descent engine off for 30 s.".
      WAIT 30.
      pa_say("descent engine stopped 30 s, thrust kN " + ROUND(pa_engine("LMDE"):THRUST, 2)).
    }
  }
  pa_stage_and_watch(FALSE).
  LOCAL ascent_eng IS pa_engine("LMAE").
  IF ascent_eng:ISTYPE("Engine") AND NOT ctl_descent_attached() { ascent_eng:SHUTDOWN(). }
  SET pa_thr TO 0.
  WAIT 0.5.
  UNLOCK STEERING.
  UNLOCK THROTTLE.
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  SAS ON.
}

// ---- TURN ----------------------------------------------------------------------------------------------------------------------
FUNCTION pa_turn {
  LOCAL up_vec IS (-SHIP:BODY:POSITION):NORMALIZED.
  LOCAL retro_vec IS -VXCL(up_vec, SHIP:VELOCITY:ORBIT):NORMALIZED.
  LOCAL start_dir IS up_vec * COS(80) + retro_vec * SIN(80).
  LOCAL goal_dir IS up_vec * COS(70) - retro_vec * SIN(70).           // 150 deg away, the short way passes the vertical
  ctl_start().
  PRINT "Turning to the braking attitude.".
  LOCAL turn_end IS TIME:SECONDS + 90.
  UNTIL ctl_att_error_deg() < 3 AND VANG(SHIP:FACING:FOREVECTOR, start_dir) < 3 OR TIME:SECONDS > turn_end {
    ctl_set_command(start_dir, ctl_window_face_vec(), 0).
    WAIT 0.05.
  }
  SET SHIP:CONTROL:FORE TO 1.
  LOCAL settle_end IS TIME:SECONDS + 8.
  UNTIL TIME:SECONDS > settle_end { ctl_set_command(start_dir, CTL_GOAL_UP, 0). WAIT 0.05. }
  LOCAL light_end IS TIME:SECONDS + 6.
  UNTIL TIME:SECONDS > light_end { ctl_set_command(start_dir, CTL_GOAL_UP, 1). WAIT 0.05. }
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  LOCAL goal_up IS win_min_rotation(SHIP:FACING:FOREVECTOR, ctl_window_face_vec(), goal_dir).
  pa_say("turn start: mass t " + ROUND(SHIP:MASS, 3) + "  thrust kN " + ROUND(pa_engine("LMDE"):THRUST, 2) + "  angle to turn "
      + ROUND(VANG(SHIP:FACING:FOREVECTOR, goal_dir), 1) + " deg").
  LOCAL t0 IS TIME:SECONDS.
  LOCAL arrived IS -1.
  LOCAL max_lag IS 0.
  LOCAL max_rate IS 0.
  LOCAL next_row IS 0.
  UNTIL TIME:SECONDS - t0 > 40 {
    ctl_set_command(goal_dir, goal_up, 1).
    LOCAL elapsed IS TIME:SECONDS - t0.
    LOCAL lag IS VANG(SHIP:FACING:FOREVECTOR, CTL_DIR).
    LOCAL left IS VANG(SHIP:FACING:FOREVECTOR, goal_dir).
    SET max_lag TO MAX(max_lag, lag).
    SET max_rate TO MAX(max_rate, pa_rate_deg_s()).
    IF arrived < 0 AND left < 5 { SET arrived TO elapsed. }
    IF elapsed >= next_row {
      LOG ROUND(elapsed, 1) + " | to go " + ROUND(left, 1) + " | behind the command " + ROUND(lag, 1) + " | rate " + ROUND(pa_rate_deg_s(), 1) TO pa_log.
      SET next_row TO elapsed + 0.5.
    }
    WAIT 0.05.
  }
  pa_say("within 5 deg of the goal after s " + ROUND(arrived, 1) + " (-1 = never)").
  pa_say("largest lag behind the command deg " + ROUND(max_lag, 1) + "  largest rate deg/s " + ROUND(max_rate, 1)).
  ctl_engine_off(pa_engine("LMDE")).
  ctl_release(TRUE).
}

// ---- RCS -----------------------------------------------------------------------------------------------------------------------

// pa_accel: the mean acceleration along the ship's nose (and its size) over span_s seconds, gravity removed.
FUNCTION pa_accel {
  PARAMETER label, span_s.
  LOCAL v0 IS SHIP:VELOCITY:ORBIT.
  LOCAL r0 IS -SHIP:BODY:POSITION.
  LOCAL t0 IS TIME:SECONDS.
  LOCAL nose IS SHIP:FACING:FOREVECTOR.
  WAIT span_s.
  LOCAL span_real IS TIME:SECONDS - t0.
  LOCAL r_mid IS (r0 - SHIP:BODY:POSITION) * 0.5.
  LOCAL grav IS -r_mid:NORMALIZED * (SHIP:BODY:MU / r_mid:SQRMAGNITUDE).
  LOCAL acc IS (SHIP:VELOCITY:ORBIT - v0) / span_real - grav.
  pa_say("  " + label + ": accel " + ROUND(acc:MAG, 3) + " m/s2, along the nose " + ROUND(VDOT(acc, nose), 3) + "  (throttle " + ROUND(THROTTLE, 2) + ", RCS " + RCS + ")").
}

FUNCTION pa_rcs {
  LOCAL eng_list IS LIST().
  LIST ENGINES IN eng_list.
  FOR eng IN eng_list { eng:SHUTDOWN(). }
  pa_say("all engines shut down. parts " + SHIP:PARTS:LENGTH + "  attached " + ctl_descent_attached() + "  mass t " + ROUND(SHIP:MASS, 3)).
  LOCAL rcs_list IS LIST().
  LIST RCS IN rcs_list.
  pa_say("LIST RCS: " + rcs_list:LENGTH + " part(s)").
  LOCAL wanted IS LIST("ENABLED", "FOREBYTHROTTLE", "FOREENABLED", "TOPENABLED", "STARBOARDENABLED", "FULLTHRUST", "DEADBAND", "THRUSTLIMIT").
  FOR thruster IN rcs_list {
    LOCAL row IS "  " + thruster:NAME + " decoupledin " + thruster:DECOUPLEDIN.
    FOR suffix_name IN wanted {
      IF thruster:SUFFIXNAMES:CONTAINS(suffix_name) {
        IF suffix_name = "ENABLED" { SET row TO row + " ENABLED=" + thruster:ENABLED. }
        IF suffix_name = "FOREBYTHROTTLE" { SET row TO row + " FOREBYTHROTTLE=" + thruster:FOREBYTHROTTLE. }
        IF suffix_name = "FOREENABLED" { SET row TO row + " FOREENABLED=" + thruster:FOREENABLED. }
        IF suffix_name = "TOPENABLED" { SET row TO row + " TOPENABLED=" + thruster:TOPENABLED. }
        IF suffix_name = "STARBOARDENABLED" { SET row TO row + " STARBOARDENABLED=" + thruster:STARBOARDENABLED. }
        IF suffix_name = "FULLTHRUST" { SET row TO row + " FULLTHRUST=" + thruster:FULLTHRUST. }
        IF suffix_name = "DEADBAND" { SET row TO row + " DEADBAND=" + thruster:DEADBAND. }
        IF suffix_name = "THRUSTLIMIT" { SET row TO row + " THRUSTLIMIT=" + thruster:THRUSTLIMIT. }
      }
    }
    pa_say(row).
  }
  FOR prt IN SHIP:PARTS {
    FOR module_name IN prt:MODULES {
      IF module_name:CONTAINS("RCS") {
        LOCAL mdl IS prt:GETMODULE(module_name).
        pa_say("  module " + prt:NAME + " / " + module_name).
        FOR field_text IN mdl:ALLFIELDS { LOG "    field " + field_text TO pa_log. }
        FOR field_name IN mdl:ALLFIELDNAMES { LOG "    value " + field_name + " = " + mdl:GETFIELD(field_name) TO pa_log. }
        FOR event_name IN mdl:ALLEVENTNAMES { LOG "    event " + event_name TO pa_log. }
        FOR action_name IN mdl:ALLACTIONNAMES { LOG "    action " + action_name TO pa_log. }
      }
    }
  }
  SAS OFF.
  RCS ON.
  GLOBAL pa_dir IS SHIP:FACING.
  LOCK THROTTLE TO pa_thr.
  PRINT "Do not touch the controls. About 90 s.".
  SET pa_thr TO 0.  WAIT 2.  pa_accel("A throttle 0, no steering", 8).
  SET pa_thr TO 1.  WAIT 2.  pa_accel("B throttle 1, no steering", 8).
  LOCK STEERING TO pa_dir.
  WAIT 2.  pa_accel("C throttle 1, steering held", 8).
  RCS OFF.  WAIT 2.  pa_accel("D throttle 1, RCS OFF", 8).
  RCS ON.
  IF rcs_list:LENGTH > 0 AND rcs_list[0]:SUFFIXNAMES:CONTAINS("FOREBYTHROTTLE") {
    LOCAL was IS LIST().
    FOR thruster IN rcs_list { was:ADD(thruster:FOREBYTHROTTLE). SET thruster:FOREBYTHROTTLE TO FALSE. }
    WAIT 2.  pa_accel("E FOREBYTHROTTLE off on every part", 8).
    LOCAL i IS 0.
    FOR thruster IN rcs_list { SET thruster:FOREBYTHROTTLE TO was[i]. SET i TO i + 1. }
  }
  IF rcs_list:LENGTH > 0 AND rcs_list[0]:SUFFIXNAMES:CONTAINS("FOREENABLED") {
    LOCAL was IS LIST().
    FOR thruster IN rcs_list { was:ADD(thruster:FOREENABLED). SET thruster:FOREENABLED TO FALSE. }
    WAIT 2.  pa_accel("F FOREENABLED off on every part", 8).
    LOCAL i IS 0.
    FOR thruster IN rcs_list { SET thruster:FOREENABLED TO was[i]. SET i TO i + 1. }
  }
  SET pa_thr TO 0.
  WAIT 0.5.
  UNLOCK STEERING.
  UNLOCK THROTTLE.
  SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
  SAS ON.
}

// ---- main -----------------------------------------------------------------------------------------------------------------------
LOCAL pa_modes IS LIST("KEYS", "BURN", "LIGHT", "OFF", "LOW", "TURN", "RCS").
LOCAL pa_problem IS "".
IF NOT pa_modes:CONTAINS(probe_mode) { SET pa_problem TO "unknown mode " + probe_mode. }
ELSE IF probe_mode <> "RCS" {
  IF pa_engine("LMDE"):ISTYPE("Scalar") { SET pa_problem TO "no descent engine (LMDE) found". }
  ELSE IF NOT pa_engine("LMDE"):IGNITION AND SHIP:STATUS <> "LANDED" { SET pa_problem TO "the descent stage is not activated: press Space once, then run the probe again". }
  IF pa_engine("LMAE"):ISTYPE("Scalar") { SET pa_problem TO "no ascent engine (LMAE) found". }
  IF CORE:PART:DECOUPLEDIN >= 0 { SET pa_problem TO "this kOS processor would be left on the descent stage". }
  IF SHIP:STATUS = "LANDED" AND probe_mode <> "OFF" AND probe_mode <> "KEYS" { SET pa_problem TO "landed: only OFF and KEYS run on the surface". }
}
IF pa_problem <> "" {
  pa_say("STOPPED, nothing was done: " + pa_problem).
} ELSE {
  pa_say("== Abort probe " + probe_mode + ", " + SHIP:NAME + ", " + SHIP:STATUS + ", mass t " + ROUND(SHIP:MASS, 3) + ", parts " + SHIP:PARTS:LENGTH
      + ", stage " + STAGE:NUMBER + ", attached " + ctl_descent_attached() + " ==").
  IF probe_mode = "KEYS" { pa_keys(). }
  ELSE IF probe_mode = "TURN" { pa_turn(). }
  ELSE IF probe_mode = "RCS" { pa_rcs(). }
  ELSE { pa_staging_run(). }
  pa_say("== done ==").
  PRINT "Log: " + pa_log + ". Quickload (hold F9) before the next run.".
}
