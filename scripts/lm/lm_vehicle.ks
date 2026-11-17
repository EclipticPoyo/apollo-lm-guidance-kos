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
RUNONCEPATH("0:/lm/descent_j/lm_j_nouns.ks").        // j_noun_registers, lm_forvel (the J profile's nouns 60, 63 and 68)
RUNONCEPATH("0:/lm/descent/lm_p68.ks").               // P68, landing confirmation (both profiles)

RUNONCEPATH("0:/lm/lm_alarms.ks").                 // the scripted alarms (ALARMS)
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

// ---- landing radar state (V57, V58, N66, N67) -------------------------------------------------------------------

// lm_lr_reset: the landing-radar-update permit (V57 sets it, V58 clears it) after a height check. In Luminary 210 the permit is cleared when the radar
// height falls below cutoff_m (HLROFF, 50 ft); 099 has no such reset, so the caller passes a cutoff of 0 or less there and the permit is kept.
FUNCTION lm_lr_reset {
  PARAMETER permit, alt_radar_m, cutoff_m.
  IF permit AND cutoff_m > 0 AND alt_radar_m < cutoff_m { RETURN FALSE. }
  RETURN permit.
}

// lm_radar_velocity: the surface-relative velocity v_surf (m/s, raw axes) as the radar's three components along the LM axes: X along xnb (up),
// Z along znb (forward, the way the window faces) and Y = Z x X (right). A simplification: the real radar measures along its antenna beams.
FUNCTION lm_radar_velocity {
  PARAMETER v_surf, xnb, znb.
  LOCAL x_axis IS xnb:NORMALIZED.
  LOCAL z_axis IS znb:NORMALIZED.
  LOCAL y_axis IS VCRS(z_axis, x_axis).
  RETURN LIST(VDOT(v_surf, x_axis), VDOT(v_surf, y_axis), VDOT(v_surf, z_axis)).
}

// V57 and V58: set and clear the landing-radar-update permit. The simulated radar feeds no navigation here, so the flag only gates the J displays (a
// departure: the real V57 lets the radar update the state vector). Each prints one line. V77 (a landing-radar related enable in 210) and V59/V60 are
// accepted and do nothing.
FUNCTION lm_verb_57 {
  PARAMETER ks.
  SET LM_VEH["LR_PERMIT"] TO TRUE.
  PRINT "V57: landing radar updates permitted (the flag only; it does not change the navigation).".
  RETURN TRUE.
}
FUNCTION lm_verb_58 {
  PARAMETER ks.
  SET LM_VEH["LR_PERMIT"] TO FALSE.
  PRINT "V58: landing radar updates inhibited (the flag only; it does not change the navigation).".
  RETURN TRUE.
}
FUNCTION lm_verb_accept {
  PARAMETER ks.
  RETURN TRUE.
}

// lm_noun_registers: the core's NOUN_REGS: the J profile (Luminary 210) shows different contents in N60, N63 and N68 (lm_j_nouns.ks); everything else
// is common.
FUNCTION lm_noun_registers {
  PARAMETER noun_no, derived.
  IF LM_VEH["PROFILE"] = "J" { RETURN j_noun_registers(noun_no, derived). }
  RETURN noun_registers(noun_no, derived).
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
    IF prog["PROG_NO"] >= 64 AND prog:HASKEY("SITE_LAT") {      // P68 selected by V37 from P00 has no redesignated site
      SET LM_VEH["LAND"] TO land_vector(prog["SITE_LAT"], prog["SITE_LNG"], prog["SITE_ALT"]).
    } ELSE {
      SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
    }
    SET prog["LAND"] TO LM_VEH["LAND"].
  }
  LOCAL derived IS nav_derived(state, LM_VEH["LAND"], LM_VEH["WM"]).
  // The landing radar's readings for N66 and N67: zeros while it has no data (above RADAR_ALT_MAX_M), antenna position 1 until P64.
  LOCAL cutoff IS (CHOOSE J_HLROFF IF LM_VEH["PROFILE"] = "J" ELSE 0).
  SET LM_VEH["LR_PERMIT"] TO lm_lr_reset(LM_VEH["LR_PERMIT"], state["ALT_RADAR"], cutoff).
  IF derived["VALID"] {
    LOCAL antenna IS 1.
    IF prog:ISTYPE("Lexicon") { IF prog["PROG_NO"] >= 64 { SET antenna TO 2. } }
    LOCAL has_data IS state["ALT_RADAR"] <= RADAR_ALT_MAX_M.
    SET derived["RADAR_ALT_M"] TO (CHOOSE state["ALT_RADAR"] IF has_data ELSE 0).
    SET derived["RADAR_ANT"] TO antenna.
    LOCAL v_surf IS state["V"] - lm_cross(LM_VEH["WM"], state["R"]).
    SET derived["RADAR_VEL"] TO (CHOOSE lm_radar_velocity(v_surf, state["XNB"], ctl_window_face_vec()) IF has_data ELSE LIST(0, 0, 0)).
    IF LM_VEH["PROFILE"] = "J" { SET derived["FORVEL"] TO lm_forvel(v_surf, state["R"], ctl_window_face_vec()). }      // N60 R1 in Luminary 210
  }
  // N43 keeps showing the landing position after P68 has ended (PRO): the position P68 took is kept in LM_VEH["LANDED_POS"] until the next P63.
  IF LM_VEH:HASKEY("LANDED_POS") AND NOT derived:HASKEY("P68_LAT") {
    SET derived["P68_LAT"] TO LM_VEH["LANDED_POS"]["LAT"].
    SET derived["P68_LNG"] TO LM_VEH["LANDED_POS"]["LNG"].
    SET derived["P68_ALT"] TO LM_VEH["LANDED_POS"]["ALT"].
  }
  RETURN LEXICON("OK", TRUE, "STATE", state, "DERIVED", derived).
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
    IF prog["PROG_NO"] >= 64 AND prog:HASKEY("SITE_LAT") { SET pins_custom_geo TO LATLNG(prog["SITE_LAT"], prog["SITE_LNG"]). }
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
  RETURN LEXICON("CONTACT", LM_VEH:HASKEY("LANDED_POS")).          // lit from P68 until the next P63 (idle_text is not used)
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
  IF LM_VEH:HASKEY("LANDED_POS") { LM_VEH:REMOVE("LANDED_POS"). }          // a new descent: N43 goes back to zeros
  LOCAL vault IS LM_VEH["STORE"].
  LOCAL how_to IS " (load it from the PAD in P00, or plan with Skip simulated uplink ticked, fly the burns, then RUN dsky.)".
  IF NOT store_loaded(vault, "RLS") { RETURN LEXICON("REFUSED", "RLS (the landing site) is not loaded" + how_to). }
  IF NOT store_loaded(vault, "TLAND") { RETURN LEXICON("REFUSED", "TLAND (the landing time) is not loaded" + how_to). }
  LOCAL plan IS lm_plan_from_store(vault, LM_VEH["PROFILE"], SHIP:BODY:RADIUS, lm_clock_zero_ut()).
  LOCAL site IS lm_site_from_store(vault, SHIP:BODY:RADIUS).
  SET LM_VEH["SITE"] TO site.
  SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
  // N69 (J only): a landing-site correction the pilot loaded is added to the site once, here, and the cell zeroed (Luminary adds it at the next guidance
  // pass and zeroes it, LUNAR_LANDING_GUIDANCE_EQUATIONS 210 lines 320-346). The correction is in guidance axes (X up, Y crossrange, Z downrange), which
  // are turned back to the raw axes with this moment's CG; the site (latitude, longitude, height) is rebuilt from the moved vector.
  IF LM_VEH["PROFILE"] = "J" {
    LOCAL dland IS lm_store_get_dland(vault).
    IF dland:MAG > 0 {
      LOCAL here IS nav_state().
      LOCAL cg_now IS guidance_cg(LM_VEH["LAND"], here["R"], V(0, 0, 0), 0).
      LOCAL moved IS LM_VEH["LAND"] + cg_unapply(cg_now, dland).
      LOCAL moved_geo IS SHIP:BODY:GEOPOSITIONOF(moved + SHIP:BODY:POSITION).
      SET site TO LEXICON("OK", TRUE, "LAT", moved_geo:LAT, "LNG", moved_geo:LNG, "ALT", moved:MAG - SHIP:BODY:RADIUS).
      SET LM_VEH["SITE"] TO site.
      SET LM_VEH["LAND"] TO land_vector(site["LAT"], site["LNG"], site["ALT"]).
      lm_store_put_dland(vault, V(0, 0, 0)).
      PRINT "N69: landing site correction applied (" + ROUND(dland:MAG) + " m); the correction is cleared.".
    }
  }
  LOCAL started IS LEXICON().
  IF LM_VEH["PROFILE"] = "J" {
    SET LM_VEH["TABLE"]["64"]["NEXT"] TO 66.
    SET started TO j_p63_start(plan, site["LAT"], site["LNG"], LM_VEH["LAND"], LM_VEH["WM"]).
  } ELSE {
    SET LM_VEH["TABLE"]["64"]["NEXT"] TO 65.
    SET started TO p63_start(plan, site["LAT"], site["LNG"], LM_VEH["LAND"], LM_VEH["WM"]).
  }
  IF started["REFUSED"] = "" { PRINT "P63 started (" + (CHOOSE "J-class pad loads" IF LM_VEH["PROFILE"] = "J" ELSE "Apollo 11 pad loads") + "). Ignition in " + ROUND(started["TIG"] - TIME:SECONDS) + " s. Press PRO to continue (V16 N33 E, KEY REL checks the ignition time first).". }
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
  PRINT "P65 started: automatic landing. SAS on plus a Shift or Ctrl tap starts P66; SAS off returns to P65.".
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
  IF LM_VEH["PROFILE"] = "J" {
    SET prog["LR_PERMIT"] TO LM_VEH["LR_PERMIT"].          // V57 and V58 (the J display waits for the permit)
    RETURN j_p63_step(prog, nav["STATE"], nav["DERIVED"], ks).
  }
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
FUNCTION lm_p63_sample {
  PARAMETER prog.
  IF prog:HASKEY("ROD") { ctl_rod_feed(prog["ROD"]). }          // the throttle lever: a ROD click with SAS on starts P66 early (the A11 set only)
}
FUNCTION lm_p64_sample {
  PARAMETER prog.
  IF LM_VEH["PROFILE"] = "J" { j_p64_sample(prog). } ELSE { p64_sample(prog). }
}
// P68 (landing confirmation), both profiles. START: after P65 or J's P66 (prev is their lexicon, which keeps its keys so the END can give the
// controls back) the ship is down; selected by V37 from P00 it refuses unless the ship is LANDED or SPLASHED. The true position comes from the
// ship and is stored as RLS (Luminary stores it too), so the next P63 and the planner-free DSKY start from where the ship really is.
FUNCTION lm_p68_start {
  PARAMETER prev.
  LOCAL prog IS LEXICON().
  IF prev:ISTYPE("Lexicon") { SET prog TO prev. }
  ELSE {
    LOCAL status_text IS ctl_status().
    IF status_text <> "LANDED" AND status_text <> "SPLASHED" { RETURN LEXICON("REFUSED", "the ship is not on the surface"). }
  }
  LOCAL geo IS SHIP:GEOPOSITION.
  LOCAL height IS SHIP:ALTITUDE.         // above the body's radius (the Moon has no sea)
  p68_enter(prog, geo:LAT, geo:LNG, height).
  // Down: stop steering. The lock from the descent stayed on until PRO ended P68, so the RCS kept firing to hold an attitude the legs now hold (the
  // controls are still given back in full by the END).
  IF prev:ISTYPE("Lexicon") { ctl_steer_release(). }
  SET LM_VEH["LANDED_POS"] TO LEXICON("LAT", geo:LAT, "LNG", geo:LNG, "ALT", height).
  lm_store_put_rls(LM_VEH["STORE"], lm_site_to_rls(geo:LAT, geo:LNG, height, SHIP:BODY:RADIUS)).
  PRINT "P68 started: landing confirmed. PRO or V34 ends it (V32 shows N43 again).".
  RETURN prog.
}
FUNCTION lm_p68_step { PARAMETER prog, nav, ks. RETURN p68_step(prog, ks). }
FUNCTION lm_p68_end {
  PARAMETER prog.
  IF prog:HASKEY("ENGINE_LIT") { p63_end(prog). }      // came from the burn: give the controls back (P63's END, as P65's)
}
FUNCTION lm_p68_sample { PARAMETER prog. }

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
  IF noun_no = 69 {
    // N69 (landing site correction, whole feet; R1 downrange, R2 crossrange, R3 up) exists in Luminary 210 only. A register not loaded keeps its value.
    IF NOT lm_store_has_dland(vault) { RETURN "N69 exists only in the J profile (Luminary 210)". }
    LOCAL corr IS lm_store_get_dland(vault).
    LOCAL feet IS LIST(ROUND(m_to_ft(corr:Z)), ROUND(m_to_ft(corr:Y)), ROUND(m_to_ft(corr:X))).
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET feet[comps[i] - 1] TO values[i]. }
    lm_store_put_dland(vault, V(feet[2] / FT_PER_M, feet[1] / FT_PER_M, feet[0] / FT_PER_M)).
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

// lm_alarm_source: the core's ALARM_SOURCE: the scripted alarm codes (the ALARMS setting) due this cycle. They run on the time since the engine
// was lit (prog["SEQ"]["IGN_T"]); nothing fires before ignition, and the previous cycle's time is kept in LM_VEH["ALARM_T"].
FUNCTION lm_alarm_source {
  PARAMETER prog, now_ut.
  LOCAL ign_t IS -1.
  IF prog:ISTYPE("Lexicon") { IF prog:HASKEY("SEQ") { SET ign_t TO prog["SEQ"]["IGN_T"]. } }
  IF ign_t < 0 {
    SET LM_VEH["ALARM_T"] TO -1.
    RETURN LIST().
  }
  LOCAL elapsed IS now_ut - ign_t.
  LOCAL due IS alarm_script_due(LM_VEH["ALARM_SCHED"], LM_VEH["ALARM_T"], elapsed).
  SET LM_VEH["ALARM_T"] TO elapsed.
  RETURN due.
}

// ---- the vehicle ---------------------------------------------------------------------------------------------------

// lm_verbs_for: the verbs the profile accepts: the common list and one more, V60 in Luminary 099 (Apollo 11) or V59 in 210 (J), which the other
// software version does not have.
FUNCTION lm_verbs_for {
  PARAMETER profile.
  LOCAL verbs IS LM_VERBS:COPY.
  verbs:ADD(CHOOSE 59 IF profile = "J" ELSE 60).
  RETURN verbs.
}

// lm_programme_table: the programme table, one entry per number. Its entries are shared with LM_VEH["TABLE"] so lm_p63_start can set where P64
// hands over (65, or 66 for J). P65 and P66 hand over to P68 at contact.
FUNCTION lm_programme_table {
  RETURN LEXICON(
    "63", LEXICON("START", lm_p63_start@, "STEP", lm_p63_step@, "END", lm_p63_end@, "SAMPLE", lm_p63_sample@, "NEXT", 64, "SELECTABLE", TRUE),
    "64", LEXICON("START", lm_p64_start@, "STEP", lm_p64_step@, "END", lm_p64_end@, "SAMPLE", lm_p64_sample@, "NEXT", 65, "SELECTABLE", FALSE),
    "65", LEXICON("START", lm_p65_start@, "STEP", lm_p65_step@, "END", lm_p65_end@, "SAMPLE", lm_p65_sample@, "NEXT", 68, "SELECTABLE", FALSE),
    "66", LEXICON("START", lm_p66_start@, "STEP", lm_p66_step@, "END", lm_p66_end@, "SAMPLE", lm_p66_sample@, "NEXT", 68, "SELECTABLE", FALSE),
    "68", LEXICON("START", lm_p68_start@, "STEP", lm_p68_step@, "END", lm_p68_end@, "SAMPLE", lm_p68_sample@, "NEXT", -1, "SELECTABLE", TRUE)).
}

// lm_vehicle_new: build the vehicle LEXICON for dsky_core.ks and set up the shared state in LM_VEH.
FUNCTION lm_vehicle_new {
  LOCAL plan IS plan_read(PLAN_PLAN_FILE).
  LOCAL profile IS lm_profile_for(plan).
  SET LM_VEH TO LEXICON("SITE", LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0), "LAND", V(0, 0, 0), "WM", moon_spin(), "PIN", FALSE, "FPIN", FALSE,
      "PROFILE", profile, "LR_PERMIT", FALSE, "ALARM_SCHED", LIST(), "ALARM_T", -1, "TABLE", FALSE, "STORE", store_new(lm_cells_for(profile)), "SITE_SIG", -1, "FILLED", LEXICON()).
  // Loads kept from an earlier DSKY run (saved when it ended; the planner deletes the file on a new plan).
  store_restore(LM_VEH["STORE"], LM_STORE_FILE, profile).
  // Skip simulated uplink: a saved plan fills the store as if it had been uplinked already (never over data that is loaded). With no plan nothing is
  // loaded and P63 refuses until the pilot loads RLS and TLAND (uplink or keys).
  SET LM_VEH["FILLED"] TO lm_store_from_plan(LM_VEH["STORE"], plan, SHIP:BODY:RADIUS, lm_clock_zero_ut()).
  // The site and the Moon's spin vector are constant in the raw axes (AXES_ROTATE = true), so the site vector is computed once
  // here and again only when RLS changes (lm_refresh_site). If AXES_ROTATE were false, land_vector would have to be re-read every cycle.
  lm_refresh_site().
  LOCAL sched IS alarm_script_parse(ALARMS, profile).
  IF NOT sched:ISTYPE("Boolean") { SET LM_VEH["ALARM_SCHED"] TO sched. }
  // The pin is made here and kept in LM_VEH. It stays hidden until lm_veh_hook shows it.
  LOCAL pin IS pins_one(SITE_MARK_LABEL, LATLNG(0, 0), TRUE).
  SET pin:COLOR TO PINS_COLOR_SELECTED.
  SET pin:SHOW TO FALSE.
  SET LM_VEH["PIN"] TO pin.
  LOCAL flight_pin IS pins_flight("").      // no label on the flight-view arrow
  SET flight_pin:SHOW TO FALSE.
  SET LM_VEH["FPIN"] TO flight_pin.
  check_log_header(LM_CHECK_LOG).
  LOCAL table IS lm_programme_table().
  SET LM_VEH["TABLE"] TO table.
  IF LM_VEH["PROFILE"] = "J" { SET table["64"]["NEXT"] TO 66. }
  RETURN LEXICON(
    "NAME", "LM",
    "VERSION", (CHOOSE "LUMINARY210" IF LM_VEH["PROFILE"] = "J" ELSE "LUMINARY099"),
    "NOUNS", LM_NOUNS, "VERBS", lm_verbs_for(LM_VEH["PROFILE"]), "PROGS", LM_PROGS,
    "ALARM_SOURCE", lm_alarm_source@,
    "NO_NOUN_VERBS", LIST(57, 58, 59, 60, 77),
    "VERB_ACTIONS", LEXICON("57", lm_verb_57@, "58", lm_verb_58@, "77", lm_verb_accept@, "59", lm_verb_accept@, "60", lm_verb_accept@),
    "START_VN", (CHOOSE LIST(16, 60) IF DSKY_START = "N60" ELSE LIST(-1, -1)),
    "NOUN_REGS", lm_noun_registers@,
    "NAV", lm_veh_nav@,
    "HOOK", lm_veh_hook@,
    "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL", "CONTACT", "CONTACT"),
    "IDLE_LAMPS", lm_idle_lamps@,
    "STICKY_PROGS", LIST(),                       // after P68 ends PROG goes to 00 as in Luminary (GOTOPOOH)
    "END_REQUEST", LEXICON("VERB", 37, "NOUN", 99),          // the flashing V37 N99 request after a programme ends (Luminary GOP00FIX)
    "STORE", LM_VEH["STORE"],
    "STORE_SAVE", lm_store_save@,
    "P27_OK", lm_p27_ok@,
    "UPLINK_FILE", LM_UPLINK_FILE,
    "P27_ADDR", lm_p27_addr(LM_VEH["PROFILE"]),
    "LOADS", LM_LOADS,
    "LOAD_COMMIT", lm_load_commit@,
    "PROGRAMMES", table).
}
