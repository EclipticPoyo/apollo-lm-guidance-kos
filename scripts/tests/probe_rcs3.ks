// probe_rcs3.ks -- is the self-damping seen in probe_rcs.ks and probe_rcs2.ks really KSP's SAS? Those probes turned SAS on and
// off (damp) before every measurement and never logged the SAS state while measuring. This one logs SAS every tick.
//   RUNPATH("0:/tests/probe_rcs3.ks").
// Log: 0:/lm/logs/probe_rcs3.log. About 1 minute. Do not time-warp. Nothing to press. Setup as probe_rcs.ks (Moon, coasting
// orbit, LM upright, engine OFF, RCS active, tanks full). SAS must be OFF when you start (press T if the SAS button is lit).
//   A. NO SAS EVER: no damp(), SAS never switched on by the script. A 10-tick pitch pulse, then 400 ticks (8 s) of nothing.
//      Does the rate persist (free rotation) or fall to zero?
//   B. AFTER A SAS TOGGLE: the script turns SAS on, waits for zero rate, turns SAS off (what damp() did), logs SAS, waits 1 s,
//      then the same pulse and recording. If the rate falls to zero here but not in A, the toggle left SAS working.
//   C. AFTER A SECOND TOGGLE: the same as B again, to see whether a second toggle behaves like the first.
// Every run logs SAS each tick (0 or 1) and the total angular speed.

LOCAL log_path IS "0:/lm/logs/probe_rcs3.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

SET CONFIG:IPU TO 500.

FUNCTION zero_controls {
  SET SHIP:CONTROL:PITCH TO 0.
  SET SHIP:CONTROL:YAW TO 0.
  SET SHIP:CONTROL:ROLL TO 0.
  SET SHIP:CONTROL:FORE TO 0.
  SET SHIP:CONTROL:STARBOARD TO 0.
  SET SHIP:CONTROL:TOP TO 0.
}

FUNCTION speed_dps {
  RETURN SHIP:ANGULARVEL:MAG * 180 / CONSTANT:PI.
}

// run_test: a 10-tick pitch pulse at input 1, then 400 ticks recorded. Logs, per 10 ticks, the total angular speed and the SAS
// flag (1 = on); and a line saying whether SAS was ever seen on.
FUNCTION run_test {
  PARAMETER label.
  LOCAL mags IS LIST().
  LOCAL flags IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= 400 STEP { SET i TO i + 1. } DO {
    mags:ADD(speed_dps()).
    IF SAS { flags:ADD(1). } ELSE { flags:ADD(0). }
    IF i < 10 { SET SHIP:CONTROL:PITCH TO 1. } ELSE { SET SHIP:CONTROL:PITCH TO 0. }
    WAIT 0.
  }
  SET SHIP:CONTROL:PITCH TO 0.
  LOCAL pk IS 0.
  LOCAL pk_i IS 0.
  LOCAL sas_ticks IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= 400 STEP { SET i TO i + 1. } DO {
    IF mags[i] > pk { SET pk TO mags[i]. SET pk_i TO i. }
    SET sas_ticks TO sas_ticks + flags[i].
  }
  say(label + ":  peak=" + ROUND(pk, 4) + " at_ms=" + (pk_i * 20) + "  SAS seen on in " + sas_ticks + " of 400 ticks"
      + "  speed at 1s=" + ROUND(mags[50], 4) + " 2s=" + ROUND(mags[100], 4) + " 4s=" + ROUND(mags[200], 4) + " 8s=" + ROUND(mags[399], 4)).
  LOCAL row IS "".
  FROM { LOCAL i IS 0. } UNTIL i >= 400 STEP { SET i TO i + 10. } DO { SET row TO row + ROUND(mags[i], 3) + " ". }
  say("    total speed every 10 ticks: " + row).
}

say("probe_rcs3  ship=" + SHIP:NAME + "  mass_t=" + ROUND(SHIP:MASS, 3)).
UNLOCK STEERING.
zero_controls().
RCS ON.
say("start: SAS=" + SAS + "  RCS=" + RCS + "  SASMODE=" + SASMODE + "  speed=" + ROUND(speed_dps(), 4) + " deg/s").
IF SAS {
  say("SAS is ON at the start: switch it off (T) and run the probe again").
} ELSE {
  WAIT 1.
  // A: SAS was never switched on by this script.
  run_test("A no SAS ever").

  // B: switch SAS on, let it null the rate, switch it off, as damp() did.
  say("B: switching SAS on to null the rate...").
  SAS ON.
  SET SASMODE TO "STABILITYASSIST".
  LOCAL t0 IS TIME:SECONDS.
  UNTIL speed_dps() < 0.01 OR TIME:SECONDS - t0 > 25 { WAIT 0.1. }
  SAS OFF.
  zero_controls().
  say("B: after SAS OFF  SAS=" + SAS + "  SASMODE=" + SASMODE + "  speed=" + ROUND(speed_dps(), 4)).
  WAIT 1.
  run_test("B after a SAS toggle").

  // C: the same again, to see if a second toggle behaves the same.
  SAS ON.
  SET SASMODE TO "STABILITYASSIST".
  SET t0 TO TIME:SECONDS.
  UNTIL speed_dps() < 0.01 OR TIME:SECONDS - t0 > 25 { WAIT 0.1. }
  SAS OFF.
  zero_controls().
  WAIT 1.
  run_test("C after a second SAS toggle").
}
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
SAS OFF.
say("probe_rcs3 done").
