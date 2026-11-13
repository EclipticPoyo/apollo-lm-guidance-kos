// demo_display.ks -- on-screen check of the display and key entry (plan Task 5, step 5).
// Run on the pad or anywhere: RUNPATH("0:/lm/tests/demo_display.ks").
// Feeds FIXED made-up values (no flight data). Type V16 N60 E, then V99 E, then R. Runs 90 s.
// Every change of the key state is logged to 0:/lm/demo_display.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_display.ks").

LOCAL log_path IS "0:/lm/demo_display.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

// Made-up derived values (SI): 25 m/s horizontal, 3 m/s descent, 120 m high, 5 km from the site.
LOCAL derived IS LEXICON("VALID", TRUE, "HDOT", -3, "VHORIZ", 25, "ABVEL", 25.2, "RANGEDSP", 5000,
                         "LOOKANGL", 42.3, "HCALC", 120, "ALT_RADAR", 118, "DELTAH", -2, "VGU", V(-3, 4, 25)).
LOCAL ks IS keys_new().
LOCAL last IS "".
// kOS runs only CONFIG:IPU instructions per physics tick (default 150, about 7500 a second), too few for
// this loop. 2000 is the maximum; it is saved with the game, and costs a little electric charge.
SET CONFIG:IPU TO 2000.
LOG "IPU now " + CONFIG:IPU TO log_path.
display_init().
LOCAL passes IS 0.
LOCAL next_beat IS TIME:SECONDS.
LOCAL t_end IS TIME:SECONDS + 90.
UNTIL TIME:SECONDS > t_end {
  SET passes TO passes + 1.
  IF TIME:SECONDS >= next_beat {            // log how many loop passes ran in the last second
    LOG "passes/s " + passes TO log_path.
    SET passes TO 0.
    SET next_beat TO next_beat + 1.
  }
  keys_poll(ks).
  display_update(derived, "63", ks["VERB"], ks["NOUN"],
    LEXICON("PROG", FALSE, "OPRERR", ks["OPRERR"], "ENTRY", entry_text(ks))).
  LOCAL now IS "V" + ks["VERB"] + " N" + ks["NOUN"] + " OPRERR=" + ks["OPRERR"].
  IF now <> last { LOG now TO log_path. SET last TO now. }
  WAIT 0.1.
}
LOG "done" TO log_path.
