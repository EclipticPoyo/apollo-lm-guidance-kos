// demo_gui.ks -- on-screen check of the GUI DSKY (lm_gui.ks). Run anywhere, no flight needed:
//   RUNPATH("0:/lm/tests/demo_gui.ks").           full window
//   RUNPATH("0:/lm/tests/demo_gui.ks", 1).        default font instead of digital-7
//   RUNPATH("0:/lm/tests/demo_gui.ks", 2).        no colour tags (plain text)
//   RUNPATH("0:/lm/tests/demo_gui.ks", 3).        both 1 and 2
//   RUNPATH("0:/lm/tests/demo_gui.ks", 4).        like 3, and the SCRIPT types V16 N60 E, V99 E, R by itself
//   RUNPATH("0:/lm/tests/demo_gui.ks", 5).        like 0 (full window), and the script types the keys by itself
//   RUNPATH("0:/lm/tests/demo_gui.ks", 6).        full window, IDLE: after the first draw the loop does almost nothing
//   RUNPATH("0:/lm/tests/demo_gui.ks", 7).        like 6, but without the first gui_update: the window is never changed after creation
// With 4 or 5 do not touch the keyboard or mouse: it shows whether the window vanishes when the label
// texts change by themselves, with no user input.
// The variants exist to find out what makes the window vanish (bisecting); the variant is logged.
// Feeds FIXED made-up values. Click the keypad (or type in the terminal): V16 N60 E, V99 E, R.
// Runs 120 s, then closes the window. Everything is logged to 0:/lm/demo_gui.log: the IPU setting,
// loop passes per second, and the window's VISIBLE / X / Y once a second, which shows whether the
// window was hidden or merely not drawn if it ever disappears.

PARAMETER variant IS 0.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_display.ks").
RUNONCEPATH("0:/lm/lm_gui.ks").

LOCAL log_path IS "0:/lm/demo_gui.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

// kOS runs only CONFIG:IPU instructions per physics tick (default 150), too few for a live window.
// 2000 is the maximum; it is saved with the game and costs a little electric charge.
SET CONFIG:IPU TO 2000.
LOG "IPU now " + CONFIG:IPU TO log_path.
LOG "variant " + variant TO log_path.
IF variant = 1 OR variant = 3 OR variant = 4 { SET GUI_DIGIT_FONT TO "". }
IF variant = 2 OR variant = 3 OR variant = 4 { SET GUI_RICH TO FALSE. }

// Made-up derived values (SI): 25 m/s horizontal, 3 m/s descent, 120 m high, 5 km from the site.
LOCAL derived IS LEXICON("VALID", TRUE, "HDOT", -3, "VHORIZ", 25, "ABVEL", 25.2, "RANGEDSP", 5000,
                         "LOOKANGL", 42.3, "HCALC", 120, "ALT_RADAR", 118, "DELTAH", -2, "VGU", V(-3, 4, 25)).
LOCAL ks IS keys_new().
// The window object is created here at the top level, not in a function: windows made inside a function
// vanished after a few seconds (see gui_fill in lm_gui.ks). gui_fill then adds the widgets.
CLEARGUIS().
GLOBAL dsky_win IS GUI(GUI_WINDOW_WIDTH).
SET dsky_win:X TO 60.
SET dsky_win:Y TO 60.
GLOBAL ui IS gui_fill(dsky_win).
dsky_win:SHOW().
LOG "gui open" TO log_path.
CLEARSCREEN.
PRINT "GUI demo running for 120 s. Click the keypad, or type here: V16 N60 E, V99 E, R.".

LOCAL t_start IS TIME:SECONDS.
LOCAL t_end IS t_start + 120.
LOCAL next_beat IS t_start.
LOCAL passes IS 0.
LOCAL last IS "".
// Scripted key presses for variants 4 and 5: LIST(seconds after start, key). Same keys as by hand.
LOCAL auto IS variant = 4 OR variant = 5.
LOCAL idle IS variant = 6 OR variant = 7.         // no polling or redrawing: tests whether heavy per-pass work (string churn) matters
LOCAL auto_keys IS LIST(
  LIST(10, "V"), LIST(11, "1"), LIST(12, "6"), LIST(13, "N"), LIST(14, "6"), LIST(15, "0"), LIST(16, "E"),
  LIST(25, "V"), LIST(26, "9"), LIST(27, "9"), LIST(28, "E"), LIST(35, "R")).
LOCAL next_key IS 0.
// One draw of the initial contents, so the idle variant still shows a filled window.
IF variant <> 7 {
  gui_update(ui, derived, "63", ks["VERB"], ks["NOUN"], LEXICON("PROG", FALSE, "OPRERR", FALSE, "ENTRY", "")).
}
UNTIL TIME:SECONDS > t_end {
  SET passes TO passes + 1.
  IF TIME:SECONDS >= next_beat {
    LOG "t=" + ROUND(TIME:SECONDS - t_start, 1) + " passes/s " + passes + " visible=" + ui["WIN"]:VISIBLE
      + " x=" + ROUND(ui["WIN"]:X) + " y=" + ROUND(ui["WIN"]:Y) TO log_path.
    SET passes TO 0.
    SET next_beat TO next_beat + 1.
  }
  IF NOT idle {
  IF auto AND next_key < auto_keys:LENGTH {
    IF TIME:SECONDS - t_start >= auto_keys[next_key][0] {
      key_press(ks, auto_keys[next_key][1]).
      LOG "auto key " + auto_keys[next_key][1] + " at t=" + ROUND(TIME:SECONDS - t_start, 1) TO log_path.
      SET next_key TO next_key + 1.
    }
  }
  gui_poll(ui, ks).
  LOCAL flags IS flags_from_keys(ks, FALSE).
  gui_update(ui, derived, "63", ks["VERB"], ks["NOUN"], flags).
  LOCAL now IS "V" + ks["VERB"] + " N" + ks["NOUN"] + " OPRERR=" + ks["OPRERR"].
  IF now <> last { LOG now TO log_path. SET last TO now. }
  }
  IF idle { WAIT 0.5. } ELSE { WAIT 0.1. }
}
gui_close(ui).
LOG "done" TO log_path.
