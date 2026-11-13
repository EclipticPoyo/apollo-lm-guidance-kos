// lm_vehicle.ks -- the LM as a vehicle for the DSKY core (core/dsky_core.ks): the navigation, the noun table, the lamps
// and the programme table (P63, P64, P65/P66). lm_vehicle_new() builds the vehicle LEXICON the core reads; its shape is
// described at the top of dsky_core.ks.
//
// What used to be the programme chains and the map pin in lm_main.ks is here: the core calls these through the table.
// The site comes from the saved plan (0:/lm/plan.json, written by the planner) only. With no usable plan the DSKY
// still runs and its registers show NA; P63 refuses and says why.
//
// State that the delegates share is kept in the global LEXICON LM_VEH (delegates made with @ do not capture locals).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/shared/lm_nav.ks").
RUNONCEPATH("0:/shared/lm_checks.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
RUNONCEPATH("0:/lm/planner/lm_plan.ks").            // plan_read, for the saved plan
RUNONCEPATH("0:/lm/planner/lm_site_pins.ks").       // pins_one: the map-view pin the planner window uses, for the landing-site marker
RUNONCEPATH("0:/lm/descent/lm_p63.ks").             // the P63 programme
RUNONCEPATH("0:/lm/descent/lm_p64.ks").             // the P64 programme
RUNONCEPATH("0:/lm/descent/lm_p65.ks").             // the P65 and P66 programmes

GLOBAL LM_CHECK_LOG IS "0:/lm/logs/lm_check.log".        // the cross-check log (LM_LOG only)
GLOBAL LM_VEH IS LEXICON().                         // "SITE" (lm_site_from_plan), "LAND" (site vector), "WM" (the Moon's spin), "PIN" (map pin), "FPIN" (flight-view site vector, P64)

// lm_site_from_plan: the landing site out of a saved plan (or FALSE) as LEXICON("OK", bool, "LAT", .., "LNG", .., "ALT", ..).
// It needs SITE_LAT, SITE_LNG and T_PDI; the height is SITE_ALT when the plan has it, else the terrain height at the site.
FUNCTION lm_site_from_plan {
  PARAMETER plan.
  LOCAL none IS LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0).
  IF NOT plan:ISTYPE("Lexicon") { RETURN none. }
  IF NOT (plan:HASKEY("SITE_LAT") AND plan:HASKEY("SITE_LNG") AND plan:HASKEY("T_PDI")) { RETURN none. }
  LOCAL site_alt IS 0.
  IF plan:HASKEY("SITE_ALT") { SET site_alt TO plan["SITE_ALT"]. }
  ELSE { SET site_alt TO LATLNG(plan["SITE_LAT"], plan["SITE_LNG"]):TERRAINHEIGHT. }
  RETURN LEXICON("OK", TRUE, "LAT", plan["SITE_LAT"], "LNG", plan["SITE_LNG"], "ALT", site_alt).
}

// ---- navigation ------------------------------------------------------------------------------------------------

// lm_veh_nav: the core's NAV. Without a site the registers have nothing to show (VALID FALSE). While a programme runs the
// landing-site vector is re-read every cycle (one kOS read): P64 may have moved the site, and P65 and P66 keep it. The
// programme's own SITE_LAT, SITE_LNG and SITE_ALT are used from P64 on, and the vector goes into prog["LAND"].
FUNCTION lm_veh_nav {
  PARAMETER prog.
  LOCAL state IS nav_state().
  IF NOT state["BODY_OK"] {
    RETURN LEXICON("OK", FALSE, "STATE", state, "DERIVED", LEXICON("VALID", FALSE),
                   "MSG", "Left the " + BODY_NAME + "'s sphere of influence. Stopping.").
  }
  LOCAL site IS LM_VEH["SITE"].
  IF NOT site["OK"] { RETURN LEXICON("OK", TRUE, "STATE", state, "DERIVED", LEXICON("VALID", FALSE)). }
  IF prog:ISTYPE("Lexicon") {
    IF prog["PROG_NO"] >= 64 {
      SET LM_VEH["LAND"] TO land_vector(prog["SITE_LAT"], prog["SITE_LNG"], prog["SITE_ALT"]).
    } ELSE {
      SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
    }
    SET prog["LAND"] TO LM_VEH["LAND"].
  }
  RETURN LEXICON("OK", TRUE, "STATE", state, "DERIVED", nav_derived(state, LM_VEH["LAND"], LM_VEH["WM"])).
}

// lm_veh_hook: once per cycle after the programme's step. The landing-site marker is the planner window's map pin
// (lm_site_pins.ks), shown in map view while a programme runs. It is the "custom" kind of pin, which follows
// pins_custom_geo, set here to the site in use (the redesignated one from P64 on). Then the cross-check log.
FUNCTION lm_veh_hook {
  PARAMETER prog, nav.
  LOCAL site IS LM_VEH["SITE"].
  LOCAL pin IS LM_VEH["PIN"].
  LOCAL flight_pin IS LM_VEH["FPIN"].
  IF NOT site["OK"] { SET pin:SHOW TO FALSE. SET flight_pin:SHOW TO FALSE. RETURN. }
  // The flight-view vector stands on the site during P64 (the approach, where the aim point can be moved), in the flight view only.
  LOCAL show_flight IS FALSE.
  IF prog:ISTYPE("Lexicon") { IF prog["PROG_NO"] = 64 AND NOT MAPVIEW { SET show_flight TO TRUE. } }
  IF prog:ISTYPE("Lexicon") {
    IF prog["PROG_NO"] >= 64 { SET pins_custom_geo TO LATLNG(prog["SITE_LAT"], prog["SITE_LNG"]). }
    ELSE { SET pins_custom_geo TO LATLNG(site["LAT"], site["LNG"]). }
    SET pin:SHOW TO MAPVIEW.
  } ELSE {
    SET pin:SHOW TO FALSE.
  }
  SET flight_pin:SHOW TO show_flight.
  IF LM_LOG { check_log(LM_CHECK_LOG, nav["STATE"]["T"], nav["DERIVED"], check_update(nav["DERIVED"], site["LAT"], site["LNG"], site["ALT"])). }
}

// lm_idle_lamps: lamps that stay lit with no programme running: CONTACT after a landing (PROG shows 68) until the next V37.
FUNCTION lm_idle_lamps {
  PARAMETER idle_text.
  RETURN LEXICON("CONTACT", idle_text = "68").
}

// ---- programme table adapters --------------------------------------------------------------------------------------

// P63 start: re-read the saved plan, refuse with a reason if there is no usable one, else start (it also refuses for its
// own reasons: another site, PDI passed, no engine...). Any time warp is cancelled first, as before.
FUNCTION lm_p63_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL plan IS plan_read(PLAN_PLAN_FILE).
  LOCAL site IS lm_site_from_plan(plan).
  IF NOT site["OK"] {
    LOCAL why IS "no saved deorbit plan: run the planner first".
    IF plan:ISTYPE("Lexicon") { SET why TO "the saved plan is incomplete: run the planner first". }
    RETURN LEXICON("REFUSED", why + " (V34 ENTR, RUN plan., fly the burns, then RUN dsky.)").
  }
  SET LM_VEH["SITE"] TO site.
  SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
  LOCAL started IS p63_start(plan, site["LAT"], site["LNG"], LM_VEH["LAND"], LM_VEH["WM"]).
  IF started["REFUSED"] = "" { PRINT "P63 started. Ignition in " + ROUND(started["TIG"] - TIME:SECONDS) + " s.". }
  RETURN started.
}

// P64 start: P63 has handed over (prev is its programme lexicon, which P64 changes and returns).
FUNCTION lm_p64_start {
  PARAMETER prev.
  LOCAL site IS LM_VEH["SITE"].
  LOCAL started IS p64_start(prev, site["LAT"], site["LNG"], site["ALT"]).
  PRINT "P64 started. Time to go " + ROUND(started["TGO"]) + " s. Press PRO to allow redesignation (pitch and yaw keys then move the aim point).".
  RETURN started.
}

// P65 start: P64 has handed over. P65 turns into P66 inside its own step; one table entry covers both.
FUNCTION lm_p65_start {
  PARAMETER prev.
  LOCAL started IS p65_start(prev).
  PRINT "P65 started: automatic landing. SAS on, or a Shift or Ctrl tap, takes over the rate of descent (P66).".
  RETURN started.
}

// The core hands a step the nav LEXICON; the programmes take its STATE and DERIVED parts.
FUNCTION lm_p63_step { PARAMETER prog, nav, ks. RETURN p63_step(prog, nav["STATE"], nav["DERIVED"], ks). }
FUNCTION lm_p64_step { PARAMETER prog, nav, ks. RETURN p64_step(prog, nav["STATE"], nav["DERIVED"], ks). }
FUNCTION lm_p65_step { PARAMETER prog, nav, ks. RETURN p65_step(prog, nav["STATE"], nav["DERIVED"], ks). }

// ---- the vehicle ---------------------------------------------------------------------------------------------------

// lm_vehicle_new: build the vehicle LEXICON for dsky_core.ks and set up the shared state in LM_VEH.
FUNCTION lm_vehicle_new {
  SET LM_VEH TO LEXICON("SITE", lm_site_from_plan(plan_read(PLAN_PLAN_FILE)), "LAND", V(0, 0, 0), "WM", moon_spin(), "PIN", FALSE, "FPIN", FALSE).
  // The site and the Moon's spin vector are constant in the raw axes (AXES_ROTATE = true), so they are computed once
  // while no programme runs. If AXES_ROTATE were false, land_vector would have to be re-read every cycle.
  IF LM_VEH["SITE"]["OK"] {
    LOCAL site IS LM_VEH["SITE"].
    SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
  }
  // The pin is made here and kept in LM_VEH. It stays hidden until lm_veh_hook shows it.
  LOCAL pin IS pins_one(SITE_MARK_LABEL, LATLNG(0, 0), TRUE).
  SET pin:COLOR TO PINS_COLOR_SELECTED.
  SET pin:SHOW TO FALSE.
  SET LM_VEH["PIN"] TO pin.
  LOCAL flight_pin IS pins_flight("").      // no label on the flight-view arrow
  SET flight_pin:SHOW TO FALSE.
  SET LM_VEH["FPIN"] TO flight_pin.
  check_log_header(LM_CHECK_LOG).
  RETURN LEXICON(
    "NAME", "LM",
    "VERSION", "LUMINARY099",
    "NOUNS", LM_NOUNS, "VERBS", LM_VERBS, "PROGS", LM_PROGS,
    "NOUN_REGS", noun_registers@,
    "NAV", lm_veh_nav@,
    "HOOK", lm_veh_hook@,
    "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL", "CONTACT", "CONTACT"),
    "IDLE_LAMPS", lm_idle_lamps@,
    "STICKY_PROGS", LIST(68),
    "PROGRAMMES", LEXICON(
      "63", LEXICON("START", lm_p63_start@, "STEP", lm_p63_step@, "END", p63_end@, "SAMPLE", FALSE, "NEXT", 64, "SELECTABLE", TRUE),
      "64", LEXICON("START", lm_p64_start@, "STEP", lm_p64_step@, "END", p64_end@, "SAMPLE", p64_sample@, "NEXT", 65, "SELECTABLE", FALSE),
      "65", LEXICON("START", lm_p65_start@, "STEP", lm_p65_step@, "END", p65_end@, "SAMPLE", p65_sample@, "NEXT", -1, "SELECTABLE", FALSE))).
}
