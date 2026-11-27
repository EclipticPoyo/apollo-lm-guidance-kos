// demo_gauge.ks -- the drift gauge's real window (lm/lm_gauge.ks) driven with made-up rates, to look it over before a flight.
//   RUN gdemo.        (the stub; or RUNPATH("0:/tests/demo_gauge.ks").)   any craft, anywhere; about a minute. Nothing is steered.
// The terminal says what the window should be showing at each step; click the keys under the dial at any time. No CSM is read.
// Log: 0:/lm/logs/demo_gauge.log (each step, with where the two needles stood: pixels from the centre, up and right positive).

RUNONCEPATH("0:/lm/lm_gauge.ks").

GLOBAL DGD_LOG IS "0:/lm/logs/demo_gauge.log".
IF EXISTS(DGD_LOG) { DELETEPATH(DGD_LOG). }

FUNCTION dgd_say {
  PARAMETER text.
  PRINT text.
  LOG text TO DGD_LOG.
}

LOCAL dgd_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.

// The window is made at the top level, as dsky.ks makes it: windows made inside a function vanished on this install.
LOCAL dgd_win IS GUI(GAUGE_WINDOW_WIDTH).
SET dgd_win:X TO 580.
SET dgd_win:Y TO 60.
LOCAL dgd_mini IS GUI(GAUGE_WINDOW_WIDTH).
LOCAL dgd_gauge IS gauge_fill(dgd_win, dgd_mini).

// dgd_los: made-up numbers in the form term_los gives them.
FUNCTION dgd_los {
  PARAMETER up_mrad, right_mrad, on_axis.
  RETURN LEXICON("UP", up_mrad, "RIGHT", right_mrad, "ONAXIS", on_axis).
}

// dgd_hold: show these rates for span_s seconds.
FUNCTION dgd_hold {
  PARAMETER text, los, span_s.
  dgd_say(text).
  LOCAL until_ut IS TIME:SECONDS + span_s.
  UNTIL TIME:SECONDS >= until_ut {
    gauge_update(dgd_gauge, TRUE, los).
    WAIT 0.1.
  }
  LOG "  scale " + dgd_gauge["FULL"] + ", level " + dgd_gauge["UP_PX"] + ", upright " + dgd_gauge["SIDE_PX"] + ", minimised " + dgd_gauge["MINIMISED"] TO DGD_LOG.
}

dgd_say("Gauge demo: the LOS RATE window, right of where the DSKY sits. Scale 20 mrad/s at first.").
dgd_say("Under the dial: RANGE 5980 FT, RATE -28.4 FT/S, BY 3000 FT: -20 FT/S.").
gauge_readout(dgd_gauge, term_readout(LEXICON("RANGE", 5980 / FT_PER_M, "RATE", -28.4 / FT_PER_M), "J")).
dgd_hold("1. Both needles in the MIDDLE.", dgd_los(0, 0, TRUE), 5).
dgd_hold("2. LEVEL needle on the TOP end mark (thrust up). Upright in the middle.", dgd_los(20, 0, TRUE), 6).
dgd_hold("3. LEVEL needle on the BOTTOM end mark.", dgd_los(-20, 0, TRUE), 6).
dgd_hold("4. UPRIGHT needle on the RIGHT end mark (thrust right). Level in the middle.", dgd_los(0, 20, TRUE), 6).
dgd_hold("5. UPRIGHT needle on the LEFT end mark.", dgd_los(0, -20, TRUE), 6).
dgd_hold("6. A small drift, up and left: click the ±2 key and watch the needles move further out on 2 mrad/s (15 s).", dgd_los(1, -1, TRUE), 15).

dgd_say("7. A drift that goes round: both needles moving smoothly.").
LOCAL dgd_from IS TIME:SECONDS.
UNTIL TIME:SECONDS >= dgd_from + 12 {
  LOCAL turned IS (TIME:SECONDS - dgd_from) * 60.
  gauge_update(dgd_gauge, TRUE, dgd_los(dgd_gauge["FULL"] * SIN(turned), dgd_gauge["FULL"] * COS(turned), TRUE)).
  WAIT 0.02.
}

dgd_hold("MINIMISE: drag the window somewhere, click -, then +. It should shrink to its title, with + exactly where - was (20 s).", dgd_los(5, -5, TRUE), 20).
dgd_hold("8. Off the CSM: needles in the middle, the line above the keys reads +Z OFF THE CSM in amber.", dgd_los(0, 0, FALSE), 6).
dgd_say("9. The window goes away for 3 s, then comes back.").
gauge_update(dgd_gauge, FALSE, FALSE).
WAIT 3.
dgd_hold("10. Back in the same place, the line above the keys reading FULL SCALE again.", dgd_los(5, 5, TRUE), 8).

gauge_close(dgd_gauge).
SET CONFIG:IPU TO dgd_ipu.
dgd_say("Gauge demo done. Anything unreadable, wrong way round or odd goes in the checklist notes.").
