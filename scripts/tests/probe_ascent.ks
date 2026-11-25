// probe_ascent.ks -- throwaway probe for release 1.5 (ascent): reads the parts, decoupler, ascent engine and RCS. READ-ONLY:
// it fires nothing and changes nothing. Run it before probe_ascent_fly.ks.
//   RUNPATH("0:/tests/probe_ascent.ks").
// Setup: the lander landed on the Moon after a descent (any state is fine, nothing moves). Log: 0:/lm/logs/probe_ascent.log
// Suffix names checked against the kOS docs (part, partmodule, rcs, engine pages; the docs read were for kOS 1.4, this
// install is 1.6.0.1, so a suffix that errors here is the thing to report).

LOCAL log_path IS "0:/lm/logs/probe_ascent.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/probe_ascent.log".
}

// ship_axes: a vector in the ship's own axes (x starboard, y top, z fore), rounded, as text.
FUNCTION ship_axes {
  PARAMETER vec.
  LOCAL local_vec IS SHIP:FACING:INVERSE * vec.
  RETURN "x=" + ROUND(local_vec:X, 3) + " y=" + ROUND(local_vec:Y, 3) + " z=" + ROUND(local_vec:Z, 3).
}

say("== Ascent probe, ship '" + SHIP:NAME + "' at " + SHIP:BODY:NAME + ", status " + SHIP:STATUS + " ==").
say("MASS t " + ROUND(SHIP:MASS, 3) + "  stage number " + SHIP:STAGENUM).
say("kOS processor part " + CORE:PART:NAME + "  decoupled in stage " + CORE:PART:DECOUPLEDIN + " (-1: stays with the ascent stage)").

// ---- every part: where it hangs, when it leaves, what it weighs ----
say("-- PARTS (name, parent, decoupledin, mass t, position from the ship's centre of mass in ship axes, m)").
LOCAL keep_mass IS 0.
LOCAL keep_moment IS V(0, 0, 0).
FOR prt IN SHIP:PARTS {
  LOCAL parent_name IS "(root)".
  IF prt:HASPARENT { SET parent_name TO prt:PARENT:NAME. }
  say("   " + prt:NAME + " | " + parent_name + " | " + prt:DECOUPLEDIN + " | " + ROUND(prt:MASS, 4) + " | " + ship_axes(prt:POSITION)).
  IF prt:DECOUPLEDIN < 0 {
    SET keep_mass TO keep_mass + prt:MASS.
    SET keep_moment TO keep_moment + prt:POSITION * prt:MASS.
  }
}
say("ASCENT STAGE (parts never decoupled): mass t " + ROUND(keep_mass, 3) + "  the rest " + ROUND(SHIP:MASS - keep_mass, 3)).
IF keep_mass > 0 { say("ASCENT centre of mass (part origins, approximate): " + ship_axes(keep_moment * (1 / keep_mass))). }

// ---- decouplers: the module and event names the fly probe will use ----
say("-- DECOUPLERS").
FOR prt IN SHIP:PARTS {
  FOR module_name IN prt:MODULES {
    IF module_name:CONTAINS("Decouple") {
      LOCAL mdl IS prt:GETMODULE(module_name).
      say("   " + prt:NAME + "  module " + module_name + "  stage " + prt:STAGE).
      FOR event_name IN mdl:ALLEVENTNAMES { say("      event '" + event_name + "'"). }
    }
  }
}

// ---- engines ----
say("-- ENGINES").
LOCAL engines_list IS LIST().
LIST ENGINES IN engines_list.
FOR eng IN engines_list {
  say("   " + eng:NAME + " stage " + eng:STAGE + " decoupledin " + eng:DECOUPLEDIN + "  ignited " + eng:IGNITION
      + "  vacuum thrust kN " + ROUND(eng:POSSIBLETHRUSTAT(0), 3) + "  isp " + ROUND(eng:VACUUMISP, 1)
      + "  min throttle " + ROUND(eng:MINTHROTTLE, 3)).
  say("      ignitions " + eng:IGNITIONS + "  needs ullage " + eng:ULLAGE + "  fuel stability " + ROUND(eng:FUELSTABILITY, 3)
      + "  mass flow Mg/s " + ROUND(eng:MAXMASSFLOW, 6)).
  say("      position " + ship_axes(eng:POSITION) + "  axis " + ship_axes(eng:FACING:FOREVECTOR)).
}

// ---- RCS ----
say("-- RCS (thruster vectors in ship axes)").
FOR part_rcs IN SHIP:RCS {
  say("   " + part_rcs:NAME + " decoupledin " + part_rcs:DECOUPLEDIN + "  thruster maxthrust kN " + ROUND(part_rcs:MAXTHRUST, 3)
      + "  isp " + ROUND(part_rcs:VACUUMISP, 1) + "  thrusters " + part_rcs:THRUSTVECTORS:LENGTH).
  FOR thr_vec IN part_rcs:THRUSTVECTORS { say("      " + ship_axes(thr_vec)). }
}

// ---- propellant by part (which tanks go up with the ascent stage) ----
say("-- RESOURCES by part (units)").
FOR prt IN SHIP:PARTS {
  FOR res IN prt:RESOURCES {
    IF res:AMOUNT > 0 { say("   " + prt:NAME + " (" + prt:DECOUPLEDIN + "): " + res:NAME + " " + ROUND(res:AMOUNT, 1)). }
  }
}
say("== done ==").
