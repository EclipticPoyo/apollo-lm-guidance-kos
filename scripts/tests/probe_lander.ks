// probe_lander.ks -- reads the lander's mass, engine and fuel data from kOS and logs it (read-only).
//   RUNPATH("0:/tests/probe_lander.ks").
// Run it with the lander as the active vessel, anywhere (pad, orbit). Results go to 0:/lm/logs/lander.log.
// Suffix names were checked against the kOS docs (engine, vessel, part pages). The docs read were for
// kOS 1.4; this install is 1.6.0.1, so a suffix that errors here is the thing to report.
// Units: kOS gives mass in tonnes (t), thrust in kN, fuel flow volumetric, Isp in s.

LOCAL log_path IS "0:/lm/logs/lander.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/lander.log".
}

say("== Lander probe, ship '" + SHIP:NAME + "' at " + SHIP:BODY:NAME + " ==").

// ---- Whole ship ----
say("MASS t        now " + ROUND(SHIP:MASS, 3) + "  dry " + ROUND(SHIP:DRYMASS, 3) + "  wet " + ROUND(SHIP:WETMASS, 3)).
say("THRUST kN     available now " + ROUND(SHIP:AVAILABLETHRUST, 2) + "  available in vacuum " + ROUND(SHIP:AVAILABLETHRUSTAT(0), 2)
    + "  max vacuum " + ROUND(SHIP:MAXTHRUSTAT(0), 2)).
IF SHIP:MASS > 0 {
  say("Accel m/s2    full thrust now " + ROUND(SHIP:AVAILABLETHRUSTAT(0) / SHIP:MASS, 3) + " (vacuum thrust / current mass)").
}
say("Stage number  " + SHIP:STAGENUM).

// ---- Engines (every engine on the ship, active or not) ----
LOCAL engines_list IS LIST().
LIST ENGINES IN engines_list.
say("ENGINES       " + engines_list:LENGTH + " found").
LOCAL ship_fwd IS SHIP:FACING:FOREVECTOR.
FOR eng IN engines_list {
  say("-- " + eng:TITLE + " (" + eng:NAME + ") stage " + eng:STAGE + "  tag '" + eng:TAG + "'").
  say("   ignited " + eng:IGNITION + "  flameout " + eng:FLAMEOUT + "  restart " + eng:ALLOWRESTART + "  shutdown " + eng:ALLOWSHUTDOWN).
  say("   thrust kN: vacuum possible " + ROUND(eng:POSSIBLETHRUSTAT(0), 2) + "  available now " + ROUND(eng:AVAILABLETHRUST, 2)
      + "  limit % " + ROUND(eng:THRUSTLIMIT, 1)).
  say("   Isp s: vacuum " + ROUND(eng:VACUUMISP, 1) + "  now " + ROUND(eng:ISP, 1)).
  say("   min throttle " + ROUND(eng:MINTHROTTLE, 3) + " (RealFuels only, else 0)  throttle-locked " + eng:THROTTLELOCK
      + "  gimbal " + eng:HASGIMBAL).
  say("   ignitions left " + eng:IGNITIONS + " (-1 = unlimited or no RealFuels)  needs ullage " + eng:ULLAGE
      + "  pressure fed " + eng:PRESSUREFED + "  fuel stability " + ROUND(eng:FUELSTABILITY, 2)).
  say("   mass flow Mg/s at full throttle " + ROUND(eng:MAXMASSFLOW, 5) + "  modes " + eng:MODES:LENGTH).
  // Thrust direction relative to the ship's forward axis: 1 = same way, -1 = opposite.
  say("   engine axis . ship forward " + ROUND(VDOT(eng:FACING:FOREVECTOR, ship_fwd), 3)).
}

// ---- Mass by stage (parts grouped by the stage they belong to) ----
LOCAL stage_mass IS LEXICON().
FOR prt IN SHIP:PARTS {
  LOCAL key IS "" + prt:STAGE.
  IF NOT stage_mass:HASKEY(key) { SET stage_mass[key] TO 0. }
  SET stage_mass[key] TO stage_mass[key] + prt:MASS.
}
say("MASS BY STAGE (t, current mass incl. fuel; stage 0 drops last)").
FOR key IN stage_mass:KEYS {
  say("   stage " + key + ": " + ROUND(stage_mass[key], 3)).
}

// ---- Fuel ----
say("RESOURCES (whole ship, units)").
FOR res IN SHIP:RESOURCES {
  say("   " + res:NAME + ": " + ROUND(res:AMOUNT, 1) + " of " + ROUND(res:CAPACITY, 1)).
}
say("== done ==").
