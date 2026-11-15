// lm_plan_ui.ks -- the deorbit planner window. Run it in lunar orbit with no arguments:
//
//   RUNPATH("0:/lm/planner/lm_plan_ui.ks").
//
// One column, top to bottom:
//   the title, and the close cross (X) in the corner
//   LANDING SITE   site menu (the Apollo sites, or Custom)  |  latitude and longitude
//   PARAMETERS     pad loads menu    |  windows up in P63
//                  max plane change  |  replace existing nodes
//                  Skip simulated uplink box (off: a PAD and SEND; on: the DSKY loads the plan itself)
//   PLAN | SEND (SEND sends the PAD's UPLINK keys to the DSKY; needs a PAD first; hidden when the box is ticked)
//   the PAD (Skip simulated uplink off): the lines Mission Control would read up, as keystrokes
//   one result line: "Plan OK! DOI: 14:03, PDI: 14:55, LDG: 15:03" (the game's UT clock: set the clock to UT), or why it failed.
// Every row is a left part that stretches and a right part of fixed width, so the right column lines up.
//
// It is only a front end. The planning is lm_deorbit.ks (deorbit_run), run quietly: nothing is printed to the
// terminal, and the full report goes to 0:/lm/logs/lm_deorbit.log when LM_LOG is TRUE.
// The planner adds maneuver nodes to the ship. With Skip simulated uplink ticked it writes 0:/lm/plan.json, which the DSKY (dsky.ks) loads into its
// erasable store when it starts. By default (Skip simulated uplink off) it builds a PAD (lm_pad.ks) from the plan instead and, once the plan has worked, deletes
// plan.json (and any old uplink file; a failed plan keeps them), so the DSKY starts empty and the pilot loads it the way the crew did: SEND writes 0:/lm/uplink.txt, which the DSKY
// presses in as an uplink (V71 blocks for the site, the landing time and the DOI burn's delta-v and ignition time). A plane-change burn is the CSM's: the PAD only notes it.
// The DSKY takes its software version (PAD_PROFILE) from lm_config.txt when there is no plan, so set it there to match the menu.
// The cross in the corner (CLOSE) ends this script; it does not remove the nodes.
//
// The pad loads (RIGNX, RIGNZ, VIGN) are one set per profile, the same for every site. A site with rough terrain
// under the descent orbit is refused by the planner's terrain check, not flown into. The height is always the terrain.
//
// The GUI() window is created below at the top level of this script, not in a function (windows made inside a
// function vanished on this install, see lm_gui.ks). Widgets are added by planui_fill.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/planner/lm_deorbit.ks").      // functions only (no arguments); also loads lm_site.ks, lm_plan.ks
RUNONCEPATH("0:/lm/planner/lm_site_pins.ks").    // map-view pins for the sites
RUNONCEPATH("0:/lm/planner/lm_pad.ks").          // pad_build, pad_write, pad_write_uplink (the simulated uplink)
SET DP_QUIET TO TRUE.
GLOBAL planui_cfg_profile IS PAD_PROFILE.         // the version lm_config.txt gave (the menu changes PAD_PROFILE later); the DSKY uses this one with the simulated uplink

GLOBAL PLANUI_WIDTH IS 570.               // wide enough for the PAD's longest line (a burn block's eight words) at PLANUI_PAD_SIZE
GLOBAL PLANUI_PAD_SIZE IS 12.             // the PAD text size (points)
GLOBAL PLANUI_PAD_LEFT IS 14.             // space left of the PAD text
GLOBAL PLANUI_RIGHT_W IS 240.             // width of the right part of every row
GLOBAL PLANUI_LAT_LABEL_W IS 32.          // width of the "LAT" label
GLOBAL PLANUI_LONG_LABEL_W IS 44.         // width of the "LONG" label
GLOBAL PLANUI_LATLNG_FIELD_W IS 64.       // width of the latitude and longitude fields
GLOBAL PLANUI_CLOSE_SIZE IS 26.           // the close cross in the title row: this wide and high
GLOBAL PLANUI_PAD IS 8.                   // padding between a section's frame and what is inside
GLOBAL PLANUI_GAP IS 6.                   // space between the sections
GLOBAL PLANUI_BLUE IS "#8fc1e8".
GLOBAL PLANUI_GREY IS "#a0a0a0".
GLOBAL PLANUI_PAD_TEXT IS "#f2f2f2".       // the PAD text: near white, grey on the grey window was hard to read
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
  LOCAL title_row IS win:ADDHBOX().                   // the title, and the close cross in the corner
  planui_flat(title_row, 0).
  LOCAL title_w IS title_row:ADDLABEL("<size=16><b>Deorbit planner</b></size>").
  LOCAL close_button IS title_row:ADDBUTTON("X").
  SET close_button:STYLE:WIDTH TO PLANUI_CLOSE_SIZE.
  SET close_button:STYLE:HEIGHT TO PLANUI_CLOSE_SIZE.
  SET close_button:TOOLTIP TO "Close the planner (the maneuver nodes stay).".
  planui_parts:ADD(title_w).
  planui_parts:ADD(close_button).

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

  // ---- Parameters: the descent (pad loads, windows), the planning (largest plane change, replace nodes), then the uplink ----
  LOCAL param_box IS planui_section(win, "PARAMETERS").
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

  // The uplink: by default the plan becomes a PAD and SEND writes the uplink the DSKY presses in. "Skip simulated uplink" ticked: the plan is saved
  // and the DSKY loads it itself (the old Auto mode). SEND, next to PLAN, is for the uplink only and is hidden when the box is ticked.
  LOCAL skip_box IS param_box:ADDCHECKBOX("Skip simulated uplink", FALSE).
  SET skip_box:TOOLTIP TO "Unticked (default): the plan becomes a PAD, the data Mission Control would read up, and SEND writes it as a simulated uplink: the DSKY presses the octal V71 keys in itself when it starts (UPLINK ACTY lit). Ticked: no PAD and no uplink; the plan is saved and the DSKY puts the site, the landing time and the DOI burn straight into its store when it starts (UPLINK ACTY stays dark).".
  planui_parts:ADD(skip_box).

  // ---- PLAN | SEND (SEND is for the simulated uplink), then the PAD and the one-line result ----
  planui_parts:ADD(win:ADDSPACING(PLANUI_GAP)).
  LOCAL button_row IS win:ADDHBOX().                  // padded like a section, so PLAN and SEND line up with the rows above
  planui_flat(button_row, PLANUI_PAD).
  planui_parts:ADD(button_row).
  LOCAL plan_button IS button_row:ADDBUTTON("PLAN").
  LOCAL send_button IS button_row:ADDBUTTON("SEND").
  SET send_button:STYLE:WIDTH TO PLANUI_RIGHT_W.
  SET send_button:TOOLTIP TO "After a good plan with Skip simulated uplink off: write the UPLINK keys to the file the DSKY presses in when it starts (RUN dsky. in P00).".
  planui_parts:ADD(plan_button).
  planui_parts:ADD(send_button).

  LOCAL pad_box IS win:ADDVBOX().                      // the PAD, small text; only widgets this file already uses
  SET pad_box:STYLE:PADDING:LEFT TO PLANUI_PAD_LEFT.
  planui_parts:ADD(pad_box).
  LOCAL pad_text IS pad_box:ADDLABEL("").
  SET pad_text:STYLE:WORDWRAP TO FALSE.
  planui_parts:ADD(pad_text).

  LOCAL result_row IS win:ADDHBOX().                  // padded like a section, so the text starts where the rows above start
  planui_flat(result_row, PLANUI_PAD).
  LOCAL result_w IS result_row:ADDLABEL("").
  SET result_w:STYLE:WORDWRAP TO TRUE.
  planui_parts:ADD(result_w).

  LOCAL ui IS LEXICON("MENU", menu, "LAT", lat_field, "LNG", lng_field, "PC", pc_field,
                      "REPLACE", replace_box, "WINDOW", window_box, "PAD", pad_menu, "PLAN", plan_button, "CLOSE", close_button,
                      "RESULT", result_w, "SKIP", skip_box, "SEND", send_button, "PADTEXT", pad_text, "PAD_KEYS", LIST()).
  planui_result(ui, "Pick a site and press PLAN.", PLANUI_GREY).
  planui_pad_show(ui, LIST()).
  RETURN ui.
}

// planui_result: the one result line, small, in a colour (green good, red failure, grey hint, amber warning).
FUNCTION planui_result {
  PARAMETER ui, message, colour.
  SET ui["RESULT"]:TEXT TO "<size=12><color=" + colour + ">" + message + "</color></size>".
}

// planui_pad_show: show PAD lines in the scroll box (small text); an empty list shows what the box is for.
FUNCTION planui_pad_show {
  PARAMETER ui, lines.
  LOCAL pad_body IS "The PAD appears here after PLAN (with Skip simulated uplink off).".
  IF lines:LENGTH > 0 {
    SET pad_body TO "".
    FOR pad_line IN lines { SET pad_body TO pad_body + (CHOOSE "" IF pad_body = "" ELSE CHAR(10)) + pad_line. }
  }
  SET ui["PADTEXT"]:TEXT TO "<size=" + PLANUI_PAD_SIZE + "><color=" + PLANUI_PAD_TEXT + ">" + pad_body + "</color></size>".
}

// planui_manual_after_plan: uplink mode (Skip simulated uplink off), a plan was just made: build the PAD from the saved plan, then take the plan file away so the
// DSKY does not load it by itself. On success the PAD is shown and SEND is enabled. Returns the note to add to the result line.
FUNCTION planui_manual_after_plan {
  PARAMETER ui.
  LOCAL plan IS plan_read(PLAN_PLAN_FILE).
  // The PAD's clock zero is this vessel's (the planner may run docked); the DSKY, which may run after an undock reset MISSIONTIME, reads it
  // from the clock file, saved here only once the PAD is good (below).
  LOCAL zero_ut IS lm_clock_zero_now().
  LOCAL pad IS pad_build(plan, PAD_PROFILE, SHIP:BODY:RADIUS, zero_ut).
  // The uplink mode leaves no plan file and no old uplink once the new plan has worked (a failed plan keeps the old files): the DSKY must
  // start with nothing loaded, so the pilot loads it from the PAD.
  IF EXISTS(PLAN_PLAN_FILE) { DELETEPATH(PLAN_PLAN_FILE). }
  IF EXISTS(LM_UPLINK_FILE) { DELETEPATH(LM_UPLINK_FILE). }
  IF NOT pad["OK"] {
    planui_pad_show(ui, LIST()).
    RETURN "No PAD: " + pad["WHY"] + ".".
  }
  lm_clock_zero_save(zero_ut).
  planui_pad_show(ui, pad["LINES"]).
  SET ui["PAD_KEYS"] TO pad["UPLINK_KEYS"].
  IF LM_LOG { pad_write(pad["LINES"], "0:/lm/logs/pad.log"). }
  LOCAL profile_note IS pad_profile_note(PAD_PROFILE, planui_cfg_profile).
  IF profile_note <> "" { RETURN "PAD ready, but " + profile_note. }
  RETURN "PAD ready. SEND uplinks the site, the landing time and the DOI burn.".
}

// planui_send: write the PAD's UPLINK keys to the uplink file the DSKY feeds from.
FUNCTION planui_send {
  PARAMETER ui.
  IF ui["PAD_KEYS"]:LENGTH = 0 { planui_result(ui, "Nothing to send: make a plan with Skip simulated uplink off first.", PLANUI_AMBER). RETURN. }
  pad_write_uplink(ui["PAD_KEYS"], LM_UPLINK_FILE).
  planui_result(ui, "Sent " + ui["PAD_KEYS"]:LENGTH + " keys to " + LM_UPLINK_FILE + ". Start the DSKY (RUN dsky.) and leave it in P00.", PLANUI_GREEN).
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
  LOCAL manual IS NOT ui["SKIP"]:PRESSED.          // uplink mode (the old Manual): a PAD and SEND; ticked, the DSKY loads the plan itself
  SET ui["PAD_KEYS"] TO LIST().
  planui_pad_show(ui, LIST()).
  SET DP_RESULT TO LEXICON().
  SET DP_REASON TO "".
  planui_result(ui, "Planning...", PLANUI_GREY).
  WAIT 0.2.                                       // let the window redraw before the planner takes over
  deorbit_run(lat, lng, height, max_pc, ui["REPLACE"]:PRESSED).
  IF DP_RESULT:LENGTH > 0 {
    planui_result(ui, "Plan OK! DOI: " + DP_RESULT["DOI"] + ", PDI: " + DP_RESULT["PDI"] + ", LDG: " + DP_RESULT["LDG"], PLANUI_GREEN).
    IF EXISTS(LM_STORE_FILE) { DELETEPATH(LM_STORE_FILE). }      // a new plan: loads kept from an earlier DSKY run are out of date
    IF NOT manual { lm_clock_zero_clear(). }          // Skip simulated uplink: plan.json holds UT, no shared clock
    IF manual {
      LOCAL pad_note IS planui_manual_after_plan(ui).
      LOCAL pad_colour IS PLANUI_GREEN.
      IF pad_note:STARTSWITH("No PAD") OR pad_note:CONTAINS("PAD_PROFILE") { SET pad_colour TO PLANUI_AMBER. }
      SET ui["RESULT"]:TEXT TO ui["RESULT"]:TEXT + CHAR(10) + "<size=12><color=" + pad_colour + ">" + pad_note + "</color></size>".
    }
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
LOCAL planui_skip_last IS planui["SKIP"]:PRESSED.      // the box's state last pass (a checkbox has no CHANGED flag here)
UNTIL NOT planui_running {
  IF planui["CLOSE"]:TAKEPRESS {
    SET planui_running TO FALSE.
  } ELSE {
    pins_update(planui_pins, planui["MENU"]:INDEX, planui_pins_valid(planui),
                planui_number(planui["LAT"]:TEXT), planui_number(planui["LNG"]:TEXT)).
    IF planui["MENU"]:CHANGED { planui_pick(planui, planui["MENU"]:INDEX). }
    IF planui["LAT"]:CHANGED OR planui["LNG"]:CHANGED { planui_sync_menu(planui). }
    IF planui["PLAN"]:TAKEPRESS { planui_run(planui). }
    IF planui["SEND"]:TAKEPRESS { planui_send(planui). }
    IF planui["SKIP"]:PRESSED <> planui_skip_last {          // the box was toggled: the old PAD no longer applies
      SET planui_skip_last TO planui["SKIP"]:PRESSED.
      IF planui_skip_last { planui["SEND"]:HIDE(). } ELSE { planui["SEND"]:SHOW(). }          // SEND only means something with the simulated uplink
      SET planui["PAD_KEYS"] TO LIST().
      planui_pad_show(planui, LIST()).
    }
    WAIT 0.1.
  }
}
pins_clear(planui_pins).
planui_win:HIDE().
planui_win:DISPOSE().
