// dsky.ks -- the DSKY: what the pilot starts.
//
//   RUN dsky.                    (from 0:/, through the one-line stub dsky.ks in Ships/Script)
//   RUNPATH("0:/core/dsky.ks").
//
// The landing site comes from the saved plan (0:/lm/plan.json), so run the planner first and fly its burns:
//   RUN plan.     (the stub plan.ks runs 0:/lm/planner/lm_plan_ui.ks; press CLOSE when done)
// then RUN dsky. and V37 ENTR 63 ENTR starts P63; P64, P65 and P66 follow by themselves. With no saved plan the DSKY
// runs, its registers show -----, and P63 refuses (OPR ERR and a message). V34 ENTR ends the DSKY and gives the controls
// back. Start it before the descent and do not restart it mid-descent.
//
// This is the one file that names the LM: it loads the DSKY core and the LM vehicle, makes the window and hands both to the
// core's loop (core_run in dsky_core.ks). It never warps by itself; the only warp is inside P63 (lm_p63.ks).
//
// A GUI() window must be created here at the top level of the main script, not in a function: windows made inside a
// function vanished after a few seconds on this install. gui_fill (lm_gui.ks) fills it.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_gui.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

// Only run over the body the constants were set up for (the whole frame work assumes it).
IF SHIP:BODY:NAME <> BODY_NAME {
  PRINT "DSKY: this ship is at " + SHIP:BODY:NAME + ", not " + BODY_NAME + ". Nothing to do.".
  PRINT "Run it in the " + BODY_NAME + "'s sphere of influence.".
  // Nothing was created yet, so there is no window to close. Ends the script.
} ELSE {
  // 2000 is the largest CONFIG:IPU: the default 150 is too slow for a live window.
  SET CONFIG:IPU TO 2000.
  LOCAL lm IS lm_vehicle_new().
  CLEARGUIS().
  GLOBAL dsky_win IS GUI(GUI_WINDOW_WIDTH).
  SET dsky_win:X TO 60.
  SET dsky_win:Y TO 60.
  GLOBAL ui IS gui_fill(dsky_win).
  dsky_win:SHOW().
  CLEARSCREEN.
  core_reserve_status().                                 // the top rows are the live status readout; messages print below
  FOR cfg_note IN CFG_WARNINGS { PRINT cfg_note. }      // lines of lm_config.txt that were skipped
  IF LM_VEH["SITE"]["OK"] {
    PRINT "DSKY running (" + lm["NAME"] + ", " + lm["VERSION"] + "). Site " + ROUND(LM_VEH["SITE"]["LAT"], 3) + " N, "
        + ROUND(LM_VEH["SITE"]["LNG"], 3) + " E, " + ROUND(LM_VEH["SITE"]["ALT"]) + " m.".
  } ELSE {
    PRINT "DSKY running (" + lm["NAME"] + ", " + lm["VERSION"] + "). No saved plan: P63 will refuse until you run the planner.".
  }
  PRINT "Use the keypad or type here. V37 ENTR 63 ENTR starts P63. V34 ENTR ends the program.".
  core_run(ui, lm).
  LOCAL pin IS LM_VEH["PIN"].
  SET pin:SHOW TO FALSE.
  LOCAL flight_pin IS LM_VEH["FPIN"].
  SET flight_pin:SHOW TO FALSE.
  gui_close(ui).
  PRINT "DSKY ended.".
}
