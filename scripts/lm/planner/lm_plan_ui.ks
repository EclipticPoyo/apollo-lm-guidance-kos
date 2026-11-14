// lm_plan_ui.ks -- the deorbit planner window. Run it in lunar orbit with no arguments:
//
//   RUNPATH("0:/lm/planner/lm_plan_ui.ks").
//
// One column, top to bottom:
//   LANDING SITE   site menu (the Apollo sites, or Custom)  |  latitude and longitude
//   PARAMETERS     max plane change  |  replace existing nodes
//                  pad loads menu    |  windows up in P63
//   PLAN | CLOSE
//   one result line: "Plan OK! DOI: 14:03, PDI: 14:55, LDG: 15:03" (the game's UT clock: set the clock to UT), or why it failed.
// Every row is a left part that stretches and a right part of fixed width, so the right column lines up.
//
// It is only a front end. The planning is lm_deorbit.ks (deorbit_run), run quietly: nothing is printed to the
// terminal, and the full report goes to 0:/lm/logs/lm_deorbit.log when LM_LOG is TRUE.
// The planner adds maneuver nodes to the ship and writes 0:/lm/plan.json, which the DSKY (dsky.ks) then reads.
// CLOSE ends this script; it does not remove the nodes.
//
// The pad loads (RIGNX, RIGNZ, VIGN) are one set per profile, the same for every site. A site with rough terrain
// under the descent orbit is refused by the planner's terrain check, not flown into. The height is always the terrain.
//
// The GUI() window is created below at the top level of this script, not in a function (windows made inside a
// function vanished on this install, see lm_gui.ks). Widgets are added by planui_fill.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/planner/lm_deorbit.ks").      // functions only (no arguments); also loads lm_site.ks, lm_plan.ks
RUNONCEPATH("0:/lm/planner/lm_site_pins.ks").    // map-view pins for the sites
SET DP_QUIET TO TRUE.

GLOBAL PLANUI_WIDTH IS 500.
GLOBAL PLANUI_RIGHT_W IS 240.             // width of the right part of every row
GLOBAL PLANUI_LAT_LABEL_W IS 32.          // width of the "LAT" label
GLOBAL PLANUI_LONG_LABEL_W IS 44.         // width of the "LONG" label
GLOBAL PLANUI_LATLNG_FIELD_W IS 64.       // width of the latitude and longitude fields
GLOBAL PLANUI_PAD IS 8.                   // padding between a section's frame and what is inside
GLOBAL PLANUI_GAP IS 6.                   // space between the sections
GLOBAL PLANUI_BLUE IS "#8fc1e8".
GLOBAL PLANUI_GREY IS "#a0a0a0".
GLOBAL PLANUI_GREEN IS "#7fe27f".
GLOBAL PLANUI_RED IS "#ff7070".
GLOBAL PLANUI_AMBER IS "#ffc04d".
GLOBAL PLANUI_NOT_A_NUMBER IS -1e9.       // what TONUMBER returns for text that is not a number (no real input is this)
GLOBAL planui_parts IS LIST().            // keeps a reference to every widget made (same habit as gui_keep in lm_gui.ks)

// planui_flat: a strip with no padding of its own and padding_lr at the left and right, so the widgets in it start
// where the widgets directly in a section start (the default box style adds padding that pushed rows inward).
FUNCTION planui_flat {
  PARAMETER strip, padding_lr.
  SET strip:STYLE:PADDING:LEFT TO padding_lr.
  SET strip:STYLE:PADDING:RIGHT TO padding_lr.
  SET strip:STYLE:PADDING:TOP TO 0.
  SET strip:STYLE:PADDING:BOTTOM TO 0.
  SET strip:STYLE:MARGIN:LEFT TO 0.
  SET strip:STYLE:MARGIN:RIGHT TO 0.
  planui_parts:ADD(strip).
}

// planui_section: a framed box with a blue bold heading; the rows of one group go inside it. Returns the box.
FUNCTION planui_section {
  PARAMETER win, section_title.
  planui_parts:ADD(win:ADDSPACING(PLANUI_GAP)).
  LOCAL section_box IS win:ADDVBOX().
  SET section_box:STYLE:PADDING:LEFT TO PLANUI_PAD.
  SET section_box:STYLE:PADDING:RIGHT TO PLANUI_PAD.
  SET section_box:STYLE:PADDING:TOP TO PLANUI_PAD.
  SET section_box:STYLE:PADDING:BOTTOM TO PLANUI_PAD.
  LOCAL title_w IS section_box:ADDLABEL("<color=" + PLANUI_BLUE + "><b>" + section_title + "</b></color>").
  planui_parts:ADD(section_box).
  planui_parts:ADD(title_w).
  RETURN section_box.
}

// planui_fill: add all the widgets to the window. Returns a lexicon of the ones the loop reads. The explanations
// are tooltips (hover the control).
FUNCTION planui_fill {
  PARAMETER win.
  LOCAL title_w IS win:ADDLABEL("<size=16><b>Deorbit planner</b></size>").
  planui_parts:ADD(title_w).

  // ---- Landing site: the site menu on the left, latitude and longitude in the right column ----
  // The menu has one entry per Apollo site, then "Custom" (typing in the fields). The height is always the terrain.
  LOCAL site_box IS planui_section(win, "LANDING SITE").
  LOCAL site_row IS site_box:ADDHBOX().
  planui_flat(site_row, 0).
  planui_parts:ADD(site_row).
  LOCAL menu IS site_row:ADDPOPUPMENU().
  FOR apollo_site IN APOLLO_SITES { menu:ADDOPTION(apollo_site["NAME"]). }
  menu:ADDOPTION("Custom").
  SET menu:TOOLTIP TO "Pick an Apollo site, or type a latitude and longitude (Custom). The height is the terrain height.".
  planui_parts:ADD(menu).
  LOCAL latlng_cell IS site_row:ADDHBOX().
  planui_flat(latlng_cell, 0).
  SET latlng_cell:STYLE:WIDTH TO PLANUI_RIGHT_W.
  planui_parts:ADD(latlng_cell).
  LOCAL lat_label IS latlng_cell:ADDLABEL("LAT").
  SET lat_label:STYLE:WIDTH TO PLANUI_LAT_LABEL_W.
  LOCAL lat_field IS latlng_cell:ADDTEXTFIELD("").
  SET lat_field:STYLE:WIDTH TO PLANUI_LATLNG_FIELD_W.
  LOCAL lng_label IS latlng_cell:ADDLABEL("LONG").
  SET lng_label:STYLE:WIDTH TO PLANUI_LONG_LABEL_W.
  LOCAL lng_field IS latlng_cell:ADDTEXTFIELD("").
  SET lng_field:STYLE:WIDTH TO PLANUI_LATLNG_FIELD_W.
  SET lat_field:TOOLTIP TO "Latitude, degrees north.".
  SET lng_field:TOOLTIP TO "Longitude, degrees east.".
  planui_parts:ADD(lat_label).
  planui_parts:ADD(lat_field).
  planui_parts:ADD(lng_label).
  planui_parts:ADD(lng_field).

  // ---- Parameters: two rows ----
  LOCAL param_box IS planui_section(win, "PARAMETERS").
  LOCAL pc_row IS param_box:ADDHBOX().
  planui_flat(pc_row, 0).
  planui_parts:ADD(pc_row).
  LOCAL pc_cell IS pc_row:ADDHBOX().                   // the left part: label and field
  planui_flat(pc_cell, 0).
  planui_parts:ADD(pc_cell).
  LOCAL pc_label IS pc_cell:ADDLABEL("Max plane change (m/s)").
  SET pc_label:STYLE:WORDWRAP TO FALSE.                 // one line
  SET pc_label:STYLE:PADDING:TOP TO -2.                 // the row is as tall as the checkbox; this lines the label text up with the field text
  LOCAL pc_field IS pc_cell:ADDTEXTFIELD("200").
  SET pc_field:STYLE:WIDTH TO 50.
  SET pc_field:TOOLTIP TO "The largest plane-change burn the planner may use. A plane change is only planned if the site is more than 2 km out of your orbit plane.".
  LOCAL replace_box IS pc_row:ADDCHECKBOX("Replace nodes", FALSE).
  SET replace_box:STYLE:WIDTH TO PLANUI_RIGHT_W.
  SET replace_box:TOOLTIP TO "Remove the maneuver nodes already on the ship before planning. Off: planning stops if there are any.".
  planui_parts:ADD(pc_label).
  planui_parts:ADD(pc_field).
  planui_parts:ADD(replace_box).

  LOCAL pad_row IS param_box:ADDHBOX().
  planui_flat(pad_row, 0).
  planui_parts:ADD(pad_row).
  LOCAL pad_menu IS pad_row:ADDPOPUPMENU().
  pad_menu:ADDOPTION("Apollo 11 (Luminary 099)").
  pad_menu:ADDOPTION("J-class (Luminary 210)").
  IF PAD_PROFILE = "J" { SET pad_menu:INDEX TO 1. }
  SET pad_menu:TOOLTIP TO "Pad loads and descent guidance (the flight software), same for every site. J-class is Apollo 15 to 17: P66 follows P64, no P65.".
  LOCAL window_box IS pad_row:ADDCHECKBOX("Windows up in P63", P63_WINDOW_MODE <> "KEEP").
  SET window_box:STYLE:WIDTH TO PLANUI_RIGHT_W.
  SET window_box:TOOLTIP TO "On: P63 holds the windows up, away from the Moon (later missions). Off: the roll is kept as Apollo 11 flew it.".
  planui_parts:ADD(pad_menu).
  planui_parts:ADD(window_box).

  // ---- PLAN | CLOSE, then the one-line result ----
  planui_parts:ADD(win:ADDSPACING(PLANUI_GAP)).
  LOCAL button_row IS win:ADDHBOX().                  // padded like a section, so PLAN and CLOSE line up with the rows above
  planui_flat(button_row, PLANUI_PAD).
  planui_parts:ADD(button_row).
  LOCAL plan_button IS button_row:ADDBUTTON("PLAN").
  LOCAL close_button IS button_row:ADDBUTTON("CLOSE").
  SET close_button:STYLE:WIDTH TO PLANUI_RIGHT_W.
  planui_parts:ADD(plan_button).
  planui_parts:ADD(close_button).

  LOCAL result_row IS win:ADDHBOX().                  // padded like a section, so the text starts where the rows above start
  planui_flat(result_row, PLANUI_PAD).
  LOCAL result_w IS result_row:ADDLABEL("").
  SET result_w:STYLE:WORDWRAP TO TRUE.
  planui_parts:ADD(result_w).

  LOCAL ui IS LEXICON("MENU", menu, "LAT", lat_field, "LNG", lng_field, "PC", pc_field,
                      "REPLACE", replace_box, "WINDOW", window_box, "PAD", pad_menu, "PLAN", plan_button, "CLOSE", close_button,
                      "RESULT", result_w).
  planui_result(ui, "Pick a site and press PLAN.", PLANUI_GREY).
  RETURN ui.
}

// planui_result: the one result line, small, in a colour (green good, red failure, grey hint, amber warning).
FUNCTION planui_result {
  PARAMETER ui, message, colour.
  SET ui["RESULT"]:TEXT TO "<size=12><color=" + colour + ">" + message + "</color></size>".
}

// planui_pick: put the chosen Apollo site's latitude and longitude in the fields. The fields' CHANGED flags are
// read and thrown away afterwards, so filling them is not mistaken for the pilot typing.
FUNCTION planui_pick {
  PARAMETER ui, index.
  IF index < 0 OR index >= APOLLO_SITES:LENGTH { RETURN. }
  SET ui["LAT"]:TEXT TO "" + APOLLO_SITES[index]["LAT"].
  SET ui["LNG"]:TEXT TO "" + APOLLO_SITES[index]["LNG"].
  LOCAL ignore IS ui["LAT"]:CHANGED.
  SET ignore TO ui["LNG"]:CHANGED.
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

// planui_run: read the fields, run the planner quietly, show its result on the result line.
FUNCTION planui_run {
  PARAMETER ui.
  LOCAL lat IS planui_number(ui["LAT"]:TEXT).
  LOCAL lng IS planui_number(ui["LNG"]:TEXT).
  IF lat = PLANUI_NOT_A_NUMBER { planui_result(ui, "Latitude is not a number.", PLANUI_RED). RETURN. }
  IF lng = PLANUI_NOT_A_NUMBER { planui_result(ui, "Longitude is not a number.", PLANUI_RED). RETURN. }
  // The height is always the terrain height at the site (-999999 is the planner's "use terrain" value).
  LOCAL height IS -999999.
  LOCAL max_pc IS planui_number(ui["PC"]:TEXT).
  IF max_pc = PLANUI_NOT_A_NUMBER OR max_pc < 0 { planui_result(ui, "Max plane change must be a number, 0 or more.", PLANUI_RED). RETURN. }

  IF ui["WINDOW"]:PRESSED { SET P63_WINDOW_MODE TO "UP". } ELSE { SET P63_WINDOW_MODE TO "KEEP". }   // saved into the plan by deorbit_run
  IF ui["PAD"]:INDEX = 1 { SET PAD_PROFILE TO "J". } ELSE { SET PAD_PROFILE TO "A11". }                    // likewise
  SET DP_RESULT TO LEXICON().
  SET DP_REASON TO "".
  planui_result(ui, "Planning...", PLANUI_GREY).
  WAIT 0.2.                                       // let the window redraw before the planner takes over
  deorbit_run(lat, lng, height, max_pc, ui["REPLACE"]:PRESSED).
  IF DP_RESULT:LENGTH > 0 {
    planui_result(ui, "Plan OK! DOI: " + DP_RESULT["DOI"] + ", PDI: " + DP_RESULT["PDI"] + ", LDG: " + DP_RESULT["LDG"], PLANUI_GREEN).
    IF DP_RESULT["WARN"]:LENGTH > 0 {
      SET ui["RESULT"]:TEXT TO ui["RESULT"]:TEXT + CHAR(10) + "<size=12><color=" + PLANUI_AMBER + ">Warning: " + DP_RESULT["WARN"][0] + "</color></size>".
    }
  } ELSE {
    planui_result(ui, "Plan failed: " + DP_REASON, PLANUI_RED).     // the reason; the full report is in the log
  }
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
