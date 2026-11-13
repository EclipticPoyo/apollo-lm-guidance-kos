// lm_plan_ui.ks -- a small window for the deorbit planner: pick an Apollo landing site (or type a latitude and
// longitude), press PLAN. Run it in lunar orbit with no arguments:
//
//   RUNPATH("0:/lm/lm_plan_ui.ks").
//
// It is only a front end. The planning is lm_deorbit.ks (deorbit_run), run quietly: nothing is printed to the
// terminal, the window shows a two-line result, and the full report goes to 0:/lm/lm_deorbit.log.
// The planner adds maneuver nodes to the ship and writes 0:/lm/plan.json, which lm_main.ks then reads (the site; P63 itself warps to before ignition).
// CLOSE ends this script; it does not remove the nodes.
//
// Descent constants (RIGNX, RIGNZ, VIGN) are the Apollo 11 pad load for every site; the window says so.
// Not verified for other sites: a site with rough terrain under the descent orbit is refused by the planner's
// terrain check, not flown into.
//
// The GUI() window is created below at the top level of this script, not in a function (windows made inside a
// function vanished on this install, see lm_gui.ks). Widgets are added by planui_fill.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_deorbit.ks").      // functions only (no arguments); also loads lm_site.ks for APOLLO_SITES
RUNONCEPATH("0:/lm/lm_site_pins.ks").    // map-view pins for the sites
SET DP_QUIET TO TRUE.

GLOBAL PLANUI_WIDTH IS 400.
GLOBAL PLANUI_LABEL_W IS 150.             // width of the label in front of each field
GLOBAL PLANUI_FIELD_W IS 220.
GLOBAL PLANUI_NOT_A_NUMBER IS -1e9.       // what TONUMBER returns for text that is not a number (no real input is this)
GLOBAL planui_parts IS LIST().            // keeps a reference to every widget made (same habit as gui_keep in lm_gui.ks)

// planui_row: a horizontal strip with a fixed-width label and a text field, returns the field.
FUNCTION planui_row {
  PARAMETER holder, caption, start_text.
  LOCAL row_box IS holder:ADDHBOX().
  LOCAL label_w IS row_box:ADDLABEL(caption).
  SET label_w:STYLE:WIDTH TO PLANUI_LABEL_W.
  LOCAL field_w IS row_box:ADDTEXTFIELD(start_text).
  SET field_w:STYLE:WIDTH TO PLANUI_FIELD_W.
  planui_parts:ADD(row_box).
  planui_parts:ADD(label_w).
  planui_parts:ADD(field_w).
  RETURN field_w.
}

// planui_fill: add all the widgets to the window. Returns a lexicon of the ones the loop reads.
FUNCTION planui_fill {
  PARAMETER win.
  LOCAL title_w IS win:ADDLABEL("<b>Deorbit planner</b>").
  planui_parts:ADD(title_w).

  // The site menu: one entry per Apollo site, then "Custom" (typing in the fields below).
  LOCAL menu IS win:ADDPOPUPMENU().
  FOR apollo_site IN APOLLO_SITES { menu:ADDOPTION(apollo_site["NAME"]). }
  menu:ADDOPTION("Custom").
  planui_parts:ADD(menu).

  LOCAL lat_field IS planui_row(win, "Latitude (deg N)", "").
  LOCAL lng_field IS planui_row(win, "Longitude (deg E)", "").
  LOCAL alt_field IS planui_row(win, "Height (m, blank = terrain)", "").
  LOCAL pc_field IS planui_row(win, "Max plane change (m/s)", "200").
  LOCAL replace_box IS win:ADDCHECKBOX("Replace existing maneuver nodes", FALSE).
  planui_parts:ADD(replace_box).

  // The crew window in P63: held up from the Moon (later missions) or the roll kept (Apollo 11). Saved in the plan.
  LOCAL window_label IS win:ADDLABEL("Crew window in P63:").
  planui_parts:ADD(window_label).
  LOCAL window_menu IS win:ADDPOPUPMENU().
  window_menu:ADDOPTION("Windows up (later missions)").
  window_menu:ADDOPTION("Keep the roll (Apollo 11)").
  IF P63_WINDOW_MODE = "KEEP" { SET window_menu:INDEX TO 1. }
  planui_parts:ADD(window_menu).

  LOCAL note_w IS win:ADDLABEL("Descent constants: Apollo 11 pad load (all sites).").
  planui_parts:ADD(note_w).

  LOCAL button_row IS win:ADDHBOX().
  LOCAL plan_button IS button_row:ADDBUTTON("PLAN").
  LOCAL close_button IS button_row:ADDBUTTON("CLOSE").
  planui_parts:ADD(button_row).
  planui_parts:ADD(plan_button).
  planui_parts:ADD(close_button).

  // Two status lines, with word wrap so a long failure reason stays inside the window.
  LOCAL status1 IS win:ADDLABEL("Pick a site and press PLAN.").
  LOCAL status2 IS win:ADDLABEL("").
  SET status1:STYLE:WORDWRAP TO TRUE.
  SET status2:STYLE:WORDWRAP TO TRUE.
  planui_parts:ADD(status1).
  planui_parts:ADD(status2).

  RETURN LEXICON("MENU", menu, "LAT", lat_field, "LNG", lng_field, "ALT", alt_field, "PC", pc_field,
                 "REPLACE", replace_box, "WINDOW", window_menu, "PLAN", plan_button, "CLOSE", close_button,
                 "STATUS1", status1, "STATUS2", status2).
}

// planui_status: show up to two lines of status text.
FUNCTION planui_status {
  PARAMETER ui, line1, line2.
  SET ui["STATUS1"]:TEXT TO line1.
  SET ui["STATUS2"]:TEXT TO line2.
}

// planui_pick: put the chosen Apollo site's latitude and longitude in the fields. The fields' CHANGED flags are
// read and thrown away afterwards, so filling them is not mistaken for the pilot typing.
FUNCTION planui_pick {
  PARAMETER ui, index.
  IF index < 0 OR index >= APOLLO_SITES:LENGTH { RETURN. }
  SET ui["LAT"]:TEXT TO "" + APOLLO_SITES[index]["LAT"].
  SET ui["LNG"]:TEXT TO "" + APOLLO_SITES[index]["LNG"].
  SET ui["ALT"]:TEXT TO "".
  LOCAL ignore IS ui["LAT"]:CHANGED.
  SET ignore TO ui["LNG"]:CHANGED.
  SET ignore TO ui["ALT"]:CHANGED.
}

// planui_number: the text as a number, or PLANUI_NOT_A_NUMBER. TONUMBER's argument is the value to return when
// the text is not a number (kOS docs, String:TONUMBER).
FUNCTION planui_number {
  PARAMETER text.
  RETURN text:TRIM:TONUMBER(PLANUI_NOT_A_NUMBER).
}

// planui_pins_valid: are both the latitude and longitude fields numbers? (For the Custom pin.)
FUNCTION planui_pins_valid {
  PARAMETER ui.
  RETURN planui_number(ui["LAT"]:TEXT) <> PLANUI_NOT_A_NUMBER AND planui_number(ui["LNG"]:TEXT) <> PLANUI_NOT_A_NUMBER.
}

// planui_sync_menu: if the pilot has typed a latitude/longitude that is not the selected Apollo site's, switch
// the menu to "Custom" (the last entry). Only called when a lat or lng field was edited.
FUNCTION planui_sync_menu {
  PARAMETER ui.
  LOCAL lat IS planui_number(ui["LAT"]:TEXT).
  LOCAL lng IS planui_number(ui["LNG"]:TEXT).
  LOCAL index IS ui["MENU"]:INDEX.
  IF index >= 0 AND index < APOLLO_SITES:LENGTH {
    IF ABS(lat - APOLLO_SITES[index]["LAT"]) < 0.00001 AND ABS(lng - APOLLO_SITES[index]["LNG"]) < 0.00001 { RETURN. }
  }
  SET ui["MENU"]:INDEX TO APOLLO_SITES:LENGTH.
  LOCAL ignore IS ui["MENU"]:CHANGED.
}

// planui_run: read the fields, run the planner quietly, show its summary.
FUNCTION planui_run {
  PARAMETER ui.
  LOCAL lat IS planui_number(ui["LAT"]:TEXT).
  LOCAL lng IS planui_number(ui["LNG"]:TEXT).
  IF lat = PLANUI_NOT_A_NUMBER { planui_status(ui, "Latitude is not a number.", ""). RETURN. }
  IF lng = PLANUI_NOT_A_NUMBER { planui_status(ui, "Longitude is not a number.", ""). RETURN. }
  // Blank height: let the planner read the terrain height at the site (-999999 is its "use terrain" value).
  LOCAL height IS -999999.
  IF ui["ALT"]:TEXT:TRIM <> "" {
    SET height TO planui_number(ui["ALT"]:TEXT).
    IF height = PLANUI_NOT_A_NUMBER { planui_status(ui, "Height is not a number (or leave it blank).", ""). RETURN. }
  }
  LOCAL max_pc IS planui_number(ui["PC"]:TEXT).
  IF max_pc = PLANUI_NOT_A_NUMBER OR max_pc < 0 { planui_status(ui, "Max plane change must be a number, 0 or more.", ""). RETURN. }

  IF ui["WINDOW"]:INDEX = 1 { SET P63_WINDOW_MODE TO "KEEP". } ELSE { SET P63_WINDOW_MODE TO "UP". }   // saved into the plan by deorbit_run
  planui_status(ui, "Planning...", "").
  WAIT 0.2.                                       // let the window redraw before the planner takes over
  deorbit_run(lat, lng, height, max_pc, ui["REPLACE"]:PRESSED).
  planui_status(ui, DP_SUMMARY[0], DP_SUMMARY[1]).
}

// ---- Main: the window is made here, at the top level ------------------------------------------------------
CLEARGUIS().
GLOBAL planui_win IS GUI(PLANUI_WIDTH).
SET planui_win:X TO 60.
SET planui_win:Y TO 60.
GLOBAL planui IS planui_fill(planui_win).
planui_pick(planui, 0).                           // start on Apollo 11
planui_win:SHOW().

// Map-view pins for the Apollo sites and the Custom point (lm_site_pins.ks). They show only in map view.
GLOBAL planui_pins IS pins_make().

LOCAL planui_running IS TRUE.
UNTIL NOT planui_running {
  IF planui["CLOSE"]:TAKEPRESS {
    SET planui_running TO FALSE.
  } ELSE {
    pins_update(planui_pins, planui["MENU"]:INDEX, planui_pins_valid(planui),
                planui_number(planui["LAT"]:TEXT), planui_number(planui["LNG"]:TEXT)).
    IF planui["MENU"]:CHANGED { planui_pick(planui, planui["MENU"]:INDEX). }
    IF planui["LAT"]:CHANGED OR planui["LNG"]:CHANGED { planui_sync_menu(planui). }
    IF planui["PLAN"]:TAKEPRESS { planui_run(planui). }
    WAIT 0.1.
  }
}
pins_clear(planui_pins).
planui_win:HIDE().
planui_win:DISPOSE().
