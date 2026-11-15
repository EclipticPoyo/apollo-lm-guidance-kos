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
RUNONCEPATH("0:/lm/descent_j/lm_j_p63.ks").         // the J-class (Luminary 210) programmes: P63, P64 and P66 (no P65)
RUNONCEPATH("0:/lm/descent_j/lm_j_p64.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_p66.ks").

RUNONCEPATH("0:/lm/lm_cells.ks").                  // lm_cells_for, the store conversions, lm_hms_cs

GLOBAL LM_CHECK_LOG IS "0:/lm/logs/lm_check.log".        // the cross-check log (LM_LOG only)
GLOBAL LM_VEH IS LEXICON().                         // "SITE" (lm_site_from_store), "STORE" (the erasable store), "SITE_SIG" (signature of the RLS words last seen), "LAND" (site vector), "WM" (the Moon's spin), "PIN" (map pin), "FPIN" (flight-view site vector, P64)

// lm_profile_for: the software version ("A11" or "J") for a saved plan (or FALSE): the plan's own PROFILE when there is a plan (a plan wins),
// else the PAD_PROFILE setting.
FUNCTION lm_profile_for {
  PARAMETER plan.
  IF plan:ISTYPE("Lexicon") { RETURN plan_profile_of(plan). }
  RETURN PAD_PROFILE.
}

// lm_site_from_store: the landing site out of the store's RLS as LEXICON("OK", bool, "LAT", .., "LNG", .., "ALT", ..). OK is FALSE until
// RLS has been loaded (by uplink, by key, or from the plan with Skip simulated uplink ticked). radius is the body radius (m).
FUNCTION lm_site_from_store {
  PARAMETER vault, radius.
  IF NOT store_loaded(vault, "RLS") { RETURN LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0). }
  LOCAL geo IS lm_rls_to_site(lm_store_get_rls(vault), radius).
  RETURN LEXICON("OK", TRUE, "LAT", geo["LAT"], "LNG", geo["LNG"], "ALT", geo["ALT"]).
}

// lm_plan_from_store: the plan LEXICON that p63_start and j_p63_start take (SITE_LAT, SITE_LNG, SITE_ALT, T_PDI, WINDOW_MODE, PROFILE),
// rebuilt from the store: the site from RLS, the PDI time from TLAND (UT) minus PLAN_PDI_TO_LAND_S. FALSE when RLS or TLAND is not loaded.
// clock_zero is the UT of the AGC clock's zero (lm_clock_zero_ut).
FUNCTION lm_plan_from_store {
  PARAMETER vault, profile, radius, clock_zero.
  IF NOT (store_loaded(vault, "RLS") AND store_loaded(vault, "TLAND")) { RETURN FALSE. }
  LOCAL site IS lm_site_from_store(vault, radius).
  LOCAL tland_ut IS lm_store_get_tland_ut(vault, clock_zero).
  RETURN LEXICON("SITE_LAT", site["LAT"], "SITE_LNG", site["LNG"], "SITE_ALT", site["ALT"], "T_PDI", tland_ut - PLAN_PDI_TO_LAND_S,
                 "T_LAND", tland_ut, "WINDOW_MODE", P63_WINDOW_MODE, "PROFILE", profile).
}

// lm_store_from_plan: Skip simulated uplink. Load RLS and TLAND from a saved plan, as if the ground had uplinked them before the pilot started, but only
// the ones not loaded already (an uplink or keyed load is never overwritten). Returns LEXICON("RLS", bool, "TLAND", bool, "WHY", text):
// which were filled, and why TLAND was not when the plan's time does not fit the AGC clock.
FUNCTION lm_store_from_plan {
  PARAMETER vault, plan, radius, clock_zero.
  LOCAL out IS LEXICON("RLS", FALSE, "TLAND", FALSE, "WHY", "").
  IF NOT plan:ISTYPE("Lexicon") { RETURN out. }
  IF NOT (plan:HASKEY("SITE_LAT") AND plan:HASKEY("SITE_LNG")) { RETURN out. }
  IF NOT store_loaded(vault, "RLS") {
    LOCAL site_alt IS 0.
    IF plan:HASKEY("SITE_ALT") { SET site_alt TO plan["SITE_ALT"]. }
    ELSE { SET site_alt TO LATLNG(plan["SITE_LAT"], plan["SITE_LNG"]):TERRAINHEIGHT. }
    SET out["RLS"] TO lm_store_put_rls(vault, lm_site_to_rls(plan["SITE_LAT"], plan["SITE_LNG"], site_alt, radius)).
  }
  IF NOT store_loaded(vault, "TLAND") AND plan:HASKEY("T_LAND") {
    SET out["TLAND"] TO lm_store_put_tland(vault, plan["T_LAND"], clock_zero).
    IF NOT out["TLAND"] { SET out["WHY"] TO "the plan's landing time does not fit the AGC clock (before its zero or beyond 31 days)". }
  }
  RETURN out.
}

// lm_refresh_site: while no programme runs, follow the store: when RLS has been loaded or changed (an uplink, a keyed load), the site
// (LM_VEH["SITE"]) and its vector (LM_VEH["LAND"]) are recomputed. A signature of the RLS words says whether it changed.
FUNCTION lm_refresh_site {
  LOCAL vault IS LM_VEH["STORE"].
  LOCAL words IS store_words(vault, "RLS").
  LOCAL sig IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= words:LENGTH STEP { SET i TO i + 1. } DO { SET sig TO sig + words[i] * (i + 1). }
  IF sig = LM_VEH["SITE_SIG"] { RETURN. }
  SET LM_VEH["SITE_SIG"] TO sig.
  LOCAL site IS lm_site_from_store(vault, SHIP:BODY:RADIUS).
  SET LM_VEH["SITE"] TO site.
  IF site["OK"] { SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]). }
}

// ---- navigation ------------------------------------------------------------------------------------------------

// lm_veh_nav: the core's NAV. Without a site the registers have nothing to show (VALID FALSE). While a programme runs the
// landing-site vector is re-read every cycle (one kOS read): P64 may have moved the site, and P65 and P66 keep it. The
// programme's own SITE_LAT, SITE_LNG and SITE_ALT are used from P64 on, and the vector goes into prog["LAND"].
FUNCTION lm_veh_nav {
  PARAMETER prog.
  IF NOT prog:ISTYPE("Lexicon") { lm_refresh_site(). }      // no programme: follow RLS in the store (an uplink may have just loaded it)
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

// The programme table has one entry per programme number; which programme set runs (Apollo 11, Luminary 099, or J-class, Luminary 210) is
// decided when P63 starts, from the saved plan's PROFILE (plan_profile_of), and kept in LM_VEH["PROFILE"] ("A11" or "J"). Each
// adapter below calls the 099 or the J function by that. In the J set P64 hands over to P66 (table "64" NEXT is 66) and there is no
// P65 (table "65" is not selectable and never reached).

// P63 start: the landing site and time come from the erasable store (RLS and TLAND, loaded by uplink, by key, or from the plan in auto
// mode). Refuse with a reason if either is missing, else start (it also refuses for its own reasons: another site, PDI passed, no
// engine...). Any time warp is cancelled first, as before.
FUNCTION lm_p63_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL vault IS LM_VEH["STORE"].
  LOCAL how_to IS " (load it from the PAD in P00, or plan with Skip simulated uplink ticked, fly the burns, then RUN dsky.)".
  IF NOT store_loaded(vault, "RLS") { RETURN LEXICON("REFUSED", "RLS (the landing site) is not loaded" + how_to). }
  IF NOT store_loaded(vault, "TLAND") { RETURN LEXICON("REFUSED", "TLAND (the landing time) is not loaded" + how_to). }
  LOCAL plan IS lm_plan_from_store(vault, LM_VEH["PROFILE"], SHIP:BODY:RADIUS, lm_clock_zero_ut()).
  LOCAL site IS lm_site_from_store(vault, SHIP:BODY:RADIUS).
  SET LM_VEH["SITE"] TO site.
  SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
  LOCAL started IS LEXICON().
  IF LM_VEH["PROFILE"] = "J" {
    SET LM_VEH["TABLE"]["64"]["NEXT"] TO 66.
    SET started TO j_p63_start(plan, site["LAT"], site["LNG"], LM_VEH["LAND"], LM_VEH["WM"]).
  } ELSE {
    SET LM_VEH["TABLE"]["64"]["NEXT"] TO 65.
    SET started TO p63_start(plan, site["LAT"], site["LNG"], LM_VEH["LAND"], LM_VEH["WM"]).
  }
  IF started["REFUSED"] = "" { PRINT "P63 started (" + (CHOOSE "J-class pad loads" IF LM_VEH["PROFILE"] = "J" ELSE "Apollo 11 pad loads") + "). Ignition in " + ROUND(started["TIG"] - TIME:SECONDS) + " s.". }
  RETURN started.
}

// P64 start: P63 has handed over (prev is its programme lexicon, which P64 changes and returns).
FUNCTION lm_p64_start {
  PARAMETER prev.
  LOCAL site IS LM_VEH["SITE"].
  LOCAL started IS LEXICON().
  IF LM_VEH["PROFILE"] = "J" { SET started TO j_p64_start(prev, site["LAT"], site["LNG"], site["ALT"]). }
  ELSE { SET started TO p64_start(prev, site["LAT"], site["LNG"], site["ALT"]). }
  PRINT "P64 started. Time to go " + ROUND(started["TGO"]) + " s. Press PRO to allow redesignation (pitch and yaw keys then move the aim point).".
  RETURN started.
}

// P65 start (Apollo 11 pad loads only): P64 has handed over. P65 turns into P66 inside its own step; one table entry covers both.
FUNCTION lm_p65_start {
  PARAMETER prev.
  LOCAL started IS p65_start(prev).
  PRINT "P65 started: automatic landing. SAS on, or a Shift or Ctrl tap, takes over the rate of descent (P66).".
  RETURN started.
}

// P66 start (J-class only): P64 has handed over; P66 starts at once, holding the descent rate and nulling horizontal speed.
FUNCTION lm_p66_start {
  PARAMETER prev.
  LOCAL started IS j_p66_start(prev).
  PRINT "P66 started: rate of descent, horizontal speed nulled automatically. Shift or Ctrl taps change the rate.".
  RETURN started.
}

// The core hands a step the nav LEXICON; the programmes take its STATE and DERIVED parts.
FUNCTION lm_p63_step {
  PARAMETER prog, nav, ks.
  IF LM_VEH["PROFILE"] = "J" { RETURN j_p63_step(prog, nav["STATE"], nav["DERIVED"], ks). }
  RETURN p63_step(prog, nav["STATE"], nav["DERIVED"], ks).
}
FUNCTION lm_p64_step {
  PARAMETER prog, nav, ks.
  IF LM_VEH["PROFILE"] = "J" { RETURN j_p64_step(prog, nav["STATE"], nav["DERIVED"], ks). }
  RETURN p64_step(prog, nav["STATE"], nav["DERIVED"], ks).
}
FUNCTION lm_p65_step { PARAMETER prog, nav, ks. RETURN p65_step(prog, nav["STATE"], nav["DERIVED"], ks). }
FUNCTION lm_p66_step { PARAMETER prog, nav, ks. RETURN j_p66_step(prog, nav["STATE"], nav["DERIVED"], ks). }

// END and SAMPLE adapters (P63's END is the same for both sets; the J functions only differ in their names).
FUNCTION lm_p63_end {
  PARAMETER prog.
  IF LM_VEH["PROFILE"] = "J" { j_p63_end(prog). } ELSE { p63_end(prog). }
}
FUNCTION lm_p64_end {
  PARAMETER prog.
  IF LM_VEH["PROFILE"] = "J" { j_p64_end(prog). } ELSE { p64_end(prog). }
}
FUNCTION lm_p64_sample {
  PARAMETER prog.
  IF LM_VEH["PROFILE"] = "J" { j_p64_sample(prog). } ELSE { p64_sample(prog). }
}
FUNCTION lm_p65_end { PARAMETER prog. p65_end(prog). }
FUNCTION lm_p65_sample { PARAMETER prog. p65_sample(prog). }
FUNCTION lm_p66_end { PARAMETER prog. j_p66_end(prog). }
FUNCTION lm_p66_sample { PARAMETER prog. j_p66_sample(prog). }

// ---- keyed loads -------------------------------------------------------------------------------------------------------

// lm_load_commit: the DSKY core's LOAD_COMMIT: the registers a keyed load V21 to V25 gave data to (comps, 1 to 3) and the signed
// integers keyed, as shown on the display. N33: hours, minutes, hundredths of seconds of the ignition time. N81: tenths of ft/s of
// the delta-v in local vertical axes. A register not loaded keeps the stored value. Returns "" or the reason it refused.
FUNCTION lm_load_commit {
  PARAMETER noun_no, comps, values.
  LOCAL vault IS LM_VEH["STORE"].
  IF noun_no = 33 {
    LOCAL parts IS LIST(0, 0, 0).
    LOCAL tig_s IS lm_store_get_tig(vault).
    IF tig_s >= 0 { SET parts TO lm_hms_cs(tig_s). }
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET parts[comps[i] - 1] TO values[i]. }
    IF parts[0] < 0 OR parts[1] < 0 OR parts[1] > 59 OR parts[2] < 0 OR parts[2] > 5999 {
      RETURN "N33 takes hours, minutes 0 to 59 and seconds 0 to 59.99, none negative".
    }
    LOCAL new_s IS lm_hms_to_seconds(parts[0], parts[1], parts[2]).
    IF new_s * 100 >= LM_CLOCK_LIMIT_CS { RETURN "that time is beyond the AGC clock". }
    lm_store_put_tig(vault, new_s).
    RETURN "".
  }
  IF noun_no = 81 {
    LOCAL dv IS lm_store_get_dv(vault).
    LOCAL tenths IS LIST(ROUND(ms_to_fps(dv:X) * 10), ROUND(ms_to_fps(dv:Y) * 10), ROUND(ms_to_fps(dv:Z) * 10)).
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET tenths[comps[i] - 1] TO values[i]. }
    lm_store_put_dv(vault, V(tenths[0] / 10 / FT_PER_M, tenths[1] / 10 / FT_PER_M, tenths[2] / 10 / FT_PER_M)).
    RETURN "".
  }
  RETURN "noun " + noun_no + " has no load".
}

// lm_store_save: the DSKY core's STORE_SAVE: keep the store in its file when the DSKY ends.
FUNCTION lm_store_save {
  store_save(LM_VEH["STORE"], LM_STORE_FILE, LM_VEH["PROFILE"]).
}

// lm_p27_ok: an update (P27) is accepted only in P00, with no programme running (Luminary UPDATE_PROGRAM.agc).
FUNCTION lm_p27_ok {
  PARAMETER prog.
  RETURN NOT prog:ISTYPE("Lexicon").
}

// ---- the vehicle ---------------------------------------------------------------------------------------------------

// lm_vehicle_new: build the vehicle LEXICON for dsky_core.ks and set up the shared state in LM_VEH.
FUNCTION lm_vehicle_new {
  LOCAL plan IS plan_read(PLAN_PLAN_FILE).
  LOCAL profile IS lm_profile_for(plan).
  SET LM_VEH TO LEXICON("SITE", LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0), "LAND", V(0, 0, 0), "WM", moon_spin(), "PIN", FALSE, "FPIN", FALSE,
      "PROFILE", profile, "TABLE", FALSE, "STORE", store_new(lm_cells_for(profile)), "SITE_SIG", -1, "FILLED", LEXICON()).
  // Loads kept from an earlier DSKY run (saved when it ended; the planner deletes the file on a new plan).
  store_restore(LM_VEH["STORE"], LM_STORE_FILE, profile).
  // Skip simulated uplink: a saved plan fills the store as if it had been uplinked already (never over data that is loaded). With no plan nothing is
  // loaded and P63 refuses until the pilot loads RLS and TLAND (uplink or keys).
  SET LM_VEH["FILLED"] TO lm_store_from_plan(LM_VEH["STORE"], plan, SHIP:BODY:RADIUS, lm_clock_zero_ut()).
  // The site and the Moon's spin vector are constant in the raw axes (AXES_ROTATE = true), so the site vector is computed once
  // here and again only when RLS changes (lm_refresh_site). If AXES_ROTATE were false, land_vector would have to be re-read every cycle.
  lm_refresh_site().
  // The pin is made here and kept in LM_VEH. It stays hidden until lm_veh_hook shows it.
  LOCAL pin IS pins_one(SITE_MARK_LABEL, LATLNG(0, 0), TRUE).
  SET pin:COLOR TO PINS_COLOR_SELECTED.
  SET pin:SHOW TO FALSE.
  SET LM_VEH["PIN"] TO pin.
  LOCAL flight_pin IS pins_flight("").      // no label on the flight-view arrow
  SET flight_pin:SHOW TO FALSE.
  SET LM_VEH["FPIN"] TO flight_pin.
  check_log_header(LM_CHECK_LOG).
  // The programme table. Its entries are shared with LM_VEH["TABLE"] so lm_p63_start can set where P64 hands over (65, or 66 for J).
  LOCAL table IS LEXICON(
    "63", LEXICON("START", lm_p63_start@, "STEP", lm_p63_step@, "END", lm_p63_end@, "SAMPLE", FALSE, "NEXT", 64, "SELECTABLE", TRUE),
    "64", LEXICON("START", lm_p64_start@, "STEP", lm_p64_step@, "END", lm_p64_end@, "SAMPLE", lm_p64_sample@, "NEXT", 65, "SELECTABLE", FALSE),
    "65", LEXICON("START", lm_p65_start@, "STEP", lm_p65_step@, "END", lm_p65_end@, "SAMPLE", lm_p65_sample@, "NEXT", -1, "SELECTABLE", FALSE),
    "66", LEXICON("START", lm_p66_start@, "STEP", lm_p66_step@, "END", lm_p66_end@, "SAMPLE", lm_p66_sample@, "NEXT", -1, "SELECTABLE", FALSE)).
  SET LM_VEH["TABLE"] TO table.
  IF LM_VEH["PROFILE"] = "J" { SET table["64"]["NEXT"] TO 66. }
  RETURN LEXICON(
    "NAME", "LM",
    "VERSION", (CHOOSE "LUMINARY210" IF LM_VEH["PROFILE"] = "J" ELSE "LUMINARY099"),
    "NOUNS", LM_NOUNS, "VERBS", LM_VERBS, "PROGS", LM_PROGS,
    "START_VN", (CHOOSE LIST(16, 60) IF DSKY_START = "N60" ELSE LIST(-1, -1)),
    "NOUN_REGS", noun_registers@,
    "NAV", lm_veh_nav@,
    "HOOK", lm_veh_hook@,
    "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL", "CONTACT", "CONTACT"),
    "IDLE_LAMPS", lm_idle_lamps@,
    "STICKY_PROGS", LIST(68),
    "STORE", LM_VEH["STORE"],
    "STORE_SAVE", lm_store_save@,
    "P27_OK", lm_p27_ok@,
    "UPLINK_FILE", LM_UPLINK_FILE,
    "P27_ADDR", lm_p27_addr(LM_VEH["PROFILE"]),
    "LOADS", LM_LOADS,
    "LOAD_COMMIT", lm_load_commit@,
    "PROGRAMMES", table).
}
