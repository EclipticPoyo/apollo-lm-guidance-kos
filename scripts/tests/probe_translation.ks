// probe_translation.ks -- can kOS read the pilot's translation keys (default H/N fore-aft, J/L left-right, I/K up-down)?
//   Wanted for the ROD clicks: H and N would replace Shift/Ctrl (the throttle lever), which a plugged-in controller can disturb.
//   RUNPATH("0:/tests/probe_translation.ks").   Log: 0:/lm/logs/probe_translation.log.
// Run it on any craft, in flight (a landed or orbiting LM is fine), engine off. It writes nothing to the controls.
// It has two 20 s phases, RCS ON then RCS OFF. In each, tap H, N, J, L, I, K a few times (one at a time, short taps and a held one).
// With a controller plugged in, run it once with the controller idle and say so in your report.
// Reads: SHIP:CONTROL:PILOTFORE, PILOTSTARBOARD, PILOTTOP (names from the kOS docs, pilot.rst; if kOS stops with "no suffix", tell me which).
// Logs every change of a value (rounded to 0.01) and, per phase, the largest value seen on each axis.

LOCAL probe_log IS "0:/lm/logs/probe_translation.log".
IF EXISTS(probe_log) { DELETEPATH(probe_log). }
FUNCTION probe_say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/probe_translation.log".
}

probe_say("== probe_translation  ship=" + SHIP:NAME + "  (RCS is set OFF at the end)").

LOCAL phase_rcs IS LIST(TRUE, FALSE).
LOCAL phase_i IS 0.
UNTIL phase_i >= phase_rcs:LENGTH {
  IF phase_rcs[phase_i] { RCS ON. } ELSE { RCS OFF. }
  probe_say("-- phase " + (phase_i + 1) + ": RCS " + (CHOOSE "ON" IF phase_rcs[phase_i] ELSE "OFF") + " for 20 s. Tap H, N, J, L, I, K now.").
  LOCAL end_ut IS TIME:SECONDS + 20.
  LOCAL last_text IS "".
  LOCAL max_fore IS 0.
  LOCAL max_star IS 0.
  LOCAL max_top IS 0.
  UNTIL TIME:SECONDS >= end_ut {
    LOCAL fore_in IS SHIP:CONTROL:PILOTFORE.
    LOCAL star_in IS SHIP:CONTROL:PILOTSTARBOARD.
    LOCAL top_in IS SHIP:CONTROL:PILOTTOP.
    SET max_fore TO MAX(max_fore, ABS(fore_in)).
    SET max_star TO MAX(max_star, ABS(star_in)).
    SET max_top TO MAX(max_top, ABS(top_in)).
    LOCAL now_text IS "fore " + ROUND(fore_in, 2) + " starboard " + ROUND(star_in, 2) + " top " + ROUND(top_in, 2).
    IF now_text <> last_text {
      probe_say("  " + ROUND(TIME:SECONDS, 2) + "  " + now_text).
      SET last_text TO now_text.
    }
    WAIT 0.02.
  }
  probe_say("   phase " + (phase_i + 1) + " largest: fore " + ROUND(max_fore, 2) + " starboard " + ROUND(max_star, 2) + " top " + ROUND(max_top, 2)).
  SET phase_i TO phase_i + 1.
}
RCS OFF.
probe_say("done. RCS is OFF.").
