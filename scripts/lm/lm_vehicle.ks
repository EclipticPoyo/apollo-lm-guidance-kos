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
RUNONCEPATH("0:/core/dsky_core.ks").                // core_say, core_warn: the terminal's messages and warnings
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/shared/lm_nav.ks").
RUNONCEPATH("0:/shared/lm_checks.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
RUNONCEPATH("0:/lm/planner/lm_plan.ks").            // plan_read, for the saved plan
RUNONCEPATH("0:/lm/lm_csm.ks").                      // lm_find_csm, lm_csm_in_orbit: the one CSM finder
RUNONCEPATH("0:/lm/planner/lm_site_pins.ks").       // pins_one: the map-view pin the planner window uses, for the landing-site marker
RUNONCEPATH("0:/lm/descent/lm_p63.ks").             // the P63 programme
RUNONCEPATH("0:/lm/descent/lm_p64.ks").             // the P64 programme
RUNONCEPATH("0:/lm/descent/lm_p65.ks").             // the P65 and P66 programmes
RUNONCEPATH("0:/lm/descent_j/lm_j_p63.ks").         // the J-class (Luminary 210) programmes: P63, P64 and P66 (no P65)
RUNONCEPATH("0:/lm/descent_j/lm_j_p64.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_p66.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_nouns.ks").        // j_noun_registers, lm_forvel (the J profile's nouns 60, 63 and 68)
RUNONCEPATH("0:/lm/descent/lm_p68.ks").               // P68, landing confirmation (both profiles)
RUNONCEPATH("0:/lm/burn/lm_r02.ks").                  // R02, R03 and P51 (release 1.4); it loads lm_r60.ks, the R60 attitude manoeuvre
RUNONCEPATH("0:/lm/burn/lm_p30.ks").                  // P30, external delta-V (release 1.4)
RUNONCEPATH("0:/lm/burn/lm_p40.ks").                  // P40, the DPS burn (release 1.4)
RUNONCEPATH("0:/lm/burn/lm_p41.ks").                  // P41, the RCS burn, and P47, the thrust monitor (release 1.4)
RUNONCEPATH("0:/lm/rndz/lm_p32.ks").                  // P32, CSI targeting (release 1.5)
RUNONCEPATH("0:/lm/rndz/lm_p34.ks").                  // P34, TPI targeting, and P35, midcourse targeting (release 1.5)
RUNONCEPATH("0:/lm/rndz/lm_rverbs.ks").      // V83, V89 and V90
RUNONCEPATH("0:/lm/rndz/lm_p20.ks").         // P20 and P25, the second-slot tracking programmes
RUNONCEPATH("0:/lm/rndz/lm_term.ks").        // the terminal phase: line-of-sight rate and the docking message
RUNONCEPATH("0:/lm/lm_gauge.ks").            // the drift gauge's window (made by dsky.ks)
RUNONCEPATH("0:/lm/ascent/lm_p12.ks").                // P12, the powered ascent (release 1.5)
RUNONCEPATH("0:/lm/ascent/lm_p70.ks").                // P70 and P71, the aborts (release 1.5)

RUNONCEPATH("0:/lm/lm_alarms.ks").                 // the scripted alarms (ALARMS)
RUNONCEPATH("0:/lm/lm_cells.ks").                  // lm_cells_for, the store conversions, lm_hms_cs

GLOBAL LM_CHECK_LOG IS "0:/lm/logs/lm_check.log".        // the cross-check log (LM_LOG only)
GLOBAL LM_VEH IS LEXICON().                         // "SITE" (lm_site_from_store), "STORE" (the erasable store), "SITE_SIG" (signature of the RLS words last seen), "LAND" (site vector), "WM" (the Moon's spin), "PIN" (map pin), "FPIN" (flight-view site vector, P64)


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

// lm_store_from_plan: Skip simulated uplink. Load RLS, TLAND and the DOI burn (TIG and DELVLVC, so N33 and N81 read right) from a saved plan, as if the ground
// had uplinked them before the pilot started, but only the ones not loaded already (an uplink or keyed load is never overwritten). Returns
// LEXICON("RLS", bool, "TLAND", bool, "BURN", bool, "WHY", text): which were filled, and why TLAND or the burn was not when a time does not fit the AGC clock.
FUNCTION lm_store_from_plan {
  PARAMETER vault, plan, radius, clock_zero.
  LOCAL out IS LEXICON("RLS", FALSE, "TLAND", FALSE, "BURN", FALSE, "WHY", "").
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
  // The DOI burn, as the PAD's one V71 block would load it: TIG (N33) and the delta-v in local vertical axes (N81) together, only when neither is loaded.
  IF NOT (store_loaded(vault, "TIG") OR store_loaded(vault, "DELVLVC")) AND plan:HASKEY("T_DOI") AND plan:HASKEY("LV_DOI") {
    LOCAL tig_s IS plan["T_DOI"] - clock_zero.
    IF tig_s < 0 OR tig_s * 100 >= LM_CLOCK_LIMIT_CS {
      IF out["WHY"] = "" { SET out["WHY"] TO "the plan's DOI time does not fit the AGC clock (before its zero or beyond 31 days)". }
    } ELSE {
      LOCAL lv IS plan["LV_DOI"].
      lm_store_put_dv(vault, V(lv[0], lv[1], lv[2])).
      lm_store_put_tig(vault, tig_s).
      SET out["BURN"] TO TRUE.
    }
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
  core_say("V57: landing radar updates permitted (the flag only; it does not change the navigation).").
  RETURN TRUE.
}
FUNCTION lm_verb_58 {
  PARAMETER ks.
  SET LM_VEH["LR_PERMIT"] TO FALSE.
  core_say("V58: landing radar updates inhibited (the flag only; it does not change the navigation).").
  RETURN TRUE.
}
FUNCTION lm_verb_accept {
  PARAMETER ks.
  RETURN TRUE.
}

// ---- V82, the orbit display (release 1.5) ---------------------------------------------------------------------------
// Luminary V82 / R30: flashing V16 N44 for this vehicle: apolune and perilune above the landing-site radius and the time of free fall. It is an
// extended-verb display (dsky_core.ks), so it runs over P00 or any programme; PRO or V34 ends it. Departures: no V04 N06 choice of the other vehicle,
// no N32 (time to perilune); the site radius is |RLS| when it is loaded, else the body's radius.

// lm_v82_values: LIST(apolune altitude m, perilune altitude m, free-fall seconds or -1) for a state from the Moon's centre.
FUNCTION lm_v82_values {
  PARAMETER r_vec, v_vec, mu, site_radius.
  LOCAL orbit_now IS p30_apsides(r_vec, v_vec, V(0, 0, 0), mu, site_radius).
  RETURN LIST(orbit_now["APO_M"], orbit_now["PERI_M"], s30_tff(r_vec, v_vec, mu, site_radius + TFF_LIMIT_M)).
}

// lm_v82_step: the extended display's STEP: the N44 values from this cycle's navigation state.
FUNCTION lm_v82_step {
  PARAMETER nav.
  LOCAL state IS nav["STATE"].
  LOCAL site_radius IS SHIP:BODY:RADIUS.
  IF store_loaded(LM_VEH["STORE"], "RLS") { SET site_radius TO lm_store_get_rls(LM_VEH["STORE"]):MAG. }
  RETURN LEXICON("N44", lm_v82_values(state["R"], state["V"], state["MU"], site_radius)).
}

// lm_verb_82: V82 E. Refused (OPR ERR) while a keyed load or an update waits for data, or a priority display has the DSKY.
FUNCTION lm_verb_82 {
  PARAMETER ks.
  IF load_active(ks) OR p27_active(ks) OR ks["PRIO"]:ISTYPE("Lexicon") { RETURN FALSE. }
  IF NOT ks["EXT"]:ISTYPE("Lexicon") { SET ks["EXT"] TO LEXICON("VERB", 16, "NOUN", 44, "STEP", lm_v82_step@). }
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

// lm_veh_nav: the core's NAV: lm_veh_nav_state, and the values the vehicle keeps itself. Without a site the registers have nothing to show (VALID FALSE). While a programme runs the
// landing-site vector is re-read every cycle (one kOS read): P64 may have moved the site, and P65 and P66 keep it. The
// programme's own SITE_LAT, SITE_LNG and SITE_ALT are used from P64 on, and the vector goes into prog["LAND"].
FUNCTION lm_veh_nav {
  PARAMETER prog.
  LOCAL nav IS lm_veh_nav_state(prog).
  // The vehicle's own words, shown whatever the navigation state.
  SET nav["DERIVED"]["N12"] TO lm_n12().
  SET nav["DERIVED"]["N16"] TO lm_n16().
  SET nav["DERIVED"]["MARKS"] TO lm_trk_flags()["MARKS"].
  RETURN nav.
}

// lm_veh_nav_state: the navigation state and the derived values of this cycle (see lm_veh_nav).
FUNCTION lm_veh_nav_state {
  PARAMETER prog.
  IF NOT prog:ISTYPE("Lexicon") { lm_refresh_site(). }      // no programme: follow RLS in the store (an uplink may have just loaded it)
  LOCAL state IS nav_state().
  // Away from the landing body the descent registers have nothing to show, but the DSKY keeps running (burns and coast
  // happen over other bodies). The descent programmes refuse or go invalid by themselves (BODY_OK in guid_pass).
  IF NOT state["BODY_OK"] {
    RETURN LEXICON("OK", TRUE, "STATE", state, "DERIVED", LEXICON("VALID", FALSE)).
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
  IF LM_VEH:HASKEY("ABT") {          // a programme outside the descent and the aborts (or none) closes the abort window
    LOCAL cur_no IS -1.
    IF prog:ISTYPE("Lexicon") { SET cur_no TO prog["PROG_NO"]. }
    abt_after_step(LM_VEH["ABT"], cur_no).
  }
  lm_term_hook(prog).          // before the no-site return: a rendezvous needs no landing site
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

// lm_term_wanted: does the drift gauge belong on screen? While P20 or P25 runs (TRK_RUN), or P47 is the programme.
FUNCTION lm_term_wanted {
  PARAMETER prog.
  IF LM_VEH:HASKEY("TRK_RUN") { IF LM_VEH["TRK_RUN"] { RETURN TRUE. } }
  IF prog:ISTYPE("Lexicon") { RETURN prog["PROG_NO"] = 47. }
  RETURN FALSE.
}

// lm_term_hook: the drift gauge and its figures (when LM_VEH holds one: dsky.ks makes the window) and the docking message, from the per-cycle hook, read at most
// every GAUGE_PERIOD_S. When no longer wanted the window goes at once. The CSM it found is kept (TERM_CSM) for lm_term_tick.
FUNCTION lm_term_hook {
  PARAMETER prog.
  IF NOT lm_term_wanted(prog) {
    IF LM_VEH:HASKEY("GAUGE") { gauge_update(LM_VEH["GAUGE"], FALSE, FALSE). }
    RETURN.
  }
  IF NOT LM_VEH:HASKEY("DOCK") { SET LM_VEH["DOCK"] TO term_dock_new(). }
  IF NOT LM_VEH:HASKEY("TERM_NEXT") { SET LM_VEH["TERM_NEXT"] TO 0. }
  IF TIME:SECONDS < LM_VEH["TERM_NEXT"] { RETURN. }
  SET LM_VEH["TERM_NEXT"] TO TIME:SECONDS + GAUGE_PERIOD_S.
  LOCAL seen IS lm_rndz_snapshot().
  IF seen:HASKEY("CSM") { SET LM_VEH["TERM_CSM"] TO seen["CSM"]. }
  LOCAL out IS term_step(LM_VEH["DOCK"], TRUE, seen, SHIP:FACING:FOREVECTOR, ctl_window_face_vec()).
  IF out["SAY"] <> "" { core_warn(out["SAY"]). }
  IF out["LOS"]:ISTYPE("Lexicon") {          // ours, a KSP matter: on the screen, where the pilot is looking while warping
    IF NOT LM_VEH:HASKEY("WARP_NEAR") { SET LM_VEH["WARP_NEAR"] TO LEXICON("ON", FALSE). }
    LOCAL warp_text IS term_warp_step(LM_VEH["WARP_NEAR"], KUNIVERSE:TIMEWARP:MODE, KUNIVERSE:TIMEWARP:RATE, out["LOS"]["RANGE"]).
    IF warp_text <> "" { HUDTEXT(warp_text, WARP_NEAR_SHOW_S, 2, 24, YELLOW, FALSE). }          // 2: top centre
  }
  IF LM_VEH:HASKEY("GAUGE") {
    IF out["SHOW"] { gauge_readout(LM_VEH["GAUGE"], term_readout(out["LOS"], LM_VEH["PROFILE"])). }
    gauge_update(LM_VEH["GAUGE"], out["SHOW"], out["LOS"]).
  }
}

// lm_term_tick: the core's TICK hook. While the gauge shows, its needles follow the CSM every tick, from this tick's relative position and velocity
// (the vectors term_step has from the snapshot, without its file read and vessel search). A CSM that has gone away (docked) is not read.
FUNCTION lm_term_tick {
  IF NOT LM_VEH:HASKEY("GAUGE") OR NOT LM_VEH:HASKEY("TERM_CSM") { RETURN. }
  LOCAL gauge_st IS LM_VEH["GAUGE"].
  IF NOT gauge_st["SHOWN"] { RETURN. }
  gauge_buttons(gauge_st).          // here too, so that they answer at once
  IF gauge_st["MINIMISED"] { RETURN. }
  LOCAL csm_ves IS LM_VEH["TERM_CSM"].
  IF csm_ves:ISDEAD { RETURN. }
  gauge_needles(gauge_st, term_los(csm_ves:POSITION, csm_ves:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT, SHIP:FACING:FOREVECTOR, ctl_window_face_vec())).
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
      core_say("N69: landing site correction applied (" + ROUND(dland:MAG) + " m); the correction is cleared.").
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
  IF started["REFUSED"] = "" {
    core_say("P63 started (" + (CHOOSE "J-class pad loads" IF LM_VEH["PROFILE"] = "J" ELSE "Apollo 11 pad loads") + "). Ignition in " + ROUND(started["TIG"] - TIME:SECONDS) + " s.").
    // A new descent: the aborts start afresh (armed at ignition), timed against the CSM found now.
    SET LM_VEH["ABT"] TO abt_new().
    SET LM_VEH["ABT_KEY"] TO FALSE.
    SET LM_VEH["ABT"]["CSM"] TO lm_abort_csm(plan_read(ASC_PLAN_FILE)).
    IF NOT LM_VEH["ABT"]["CSM"]:ISTYPE("Vessel") { core_warn("P63: NO CSM. AN ABORT IS NOT TIMED (target it in KSP before V37 E 63 E)."). }
  }
  RETURN started.
}

// P64 start: P63 has handed over (prev is its programme lexicon, which P64 changes and returns).
FUNCTION lm_p64_start {
  PARAMETER prev.
  LOCAL site IS LM_VEH["SITE"].
  LOCAL started IS LEXICON().
  IF LM_VEH["PROFILE"] = "J" { SET started TO j_p64_start(prev, site["LAT"], site["LNG"], site["ALT"]). }
  ELSE { SET started TO p64_start(prev, site["LAT"], site["LNG"], site["ALT"]). }
  core_say("P64 started. Time to go " + ROUND(started["TGO"]) + " s.").
  RETURN started.
}

// P65 start (Apollo 11 pad loads only): P64 has handed over. P65 turns into P66 inside its own step; one table entry covers both.
FUNCTION lm_p65_start {
  PARAMETER prev.
  LOCAL started IS p65_start(prev).
  core_say("P65 started.").
  RETURN started.
}

// P66 start (J-class only): P64 has handed over; P66 starts at once, holding the descent rate and nulling horizontal speed.
FUNCTION lm_p66_start {
  PARAMETER prev.
  LOCAL started IS j_p66_start(prev).
  core_say("P66 started.").
  RETURN started.
}

// The core hands a step the nav LEXICON; the programmes take its STATE and DERIVED parts.
// lm_att_lamp: add the ATT HOLD lamp to a step's output: lit while the programme's attitude mode is HOLD, which is the SAS button being on
// (att_step). It is what the pilot's SAS click is "recognised" as: the lamp lights when the computer has seen SAS on, and a ROD click can start P66.
FUNCTION lm_att_lamp {
  PARAMETER out, prog.
  SET out["ATT_HOLD"] TO prog:HASKEY("ATT") AND prog["ATT"]["MODE"] = "HOLD".
  RETURN out.
}
FUNCTION lm_p63_step {
  PARAMETER prog, nav, ks.
  LOCAL out IS FALSE.
  IF LM_VEH["PROFILE"] = "J" {
    SET prog["LR_PERMIT"] TO LM_VEH["LR_PERMIT"].          // V57 and V58 (the J display waits for the permit)
    SET out TO j_p63_step(prog, nav["STATE"], nav["DERIVED"], ks).
  } ELSE {
    SET out TO p63_step(prog, nav["STATE"], nav["DERIVED"], ks).
  }
  lm_abort_arm(prog, nav["STATE"]).          // the aborts are armed at ignition (LETABORT)
  RETURN lm_att_lamp(out, prog).
}
FUNCTION lm_p64_step {
  PARAMETER prog, nav, ks.
  IF LM_VEH["PROFILE"] = "J" { RETURN lm_att_lamp(j_p64_step(prog, nav["STATE"], nav["DERIVED"], ks), prog). }
  RETURN lm_att_lamp(p64_step(prog, nav["STATE"], nav["DERIVED"], ks), prog).
}
FUNCTION lm_p65_step { PARAMETER prog, nav, ks. RETURN lm_att_lamp(p65_step(prog, nav["STATE"], nav["DERIVED"], ks), prog). }
FUNCTION lm_p66_step { PARAMETER prog, nav, ks. RETURN lm_att_lamp(j_p66_step(prog, nav["STATE"], nav["DERIVED"], ks), prog). }

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
  lm_abort_poll().
  IF prog:HASKEY("ROD") { ctl_rod_feed(prog["ROD"]). }          // the ROD keys (H and N): a ROD click with SAS on starts P66 early (the A11 set only)
}
FUNCTION lm_p64_sample {
  PARAMETER prog.
  lm_abort_poll().
  IF LM_VEH["PROFILE"] = "J" { j_p64_sample(prog). } ELSE { p64_sample(prog). }
}
// lm_put_ship_site: where the ship stands (latitude, longitude, height above the body's radius) into RLS. P68 at touchdown, and P12 at its start.
FUNCTION lm_put_ship_site {
  PARAMETER lat, lng, height.
  lm_store_put_rls(LM_VEH["STORE"], lm_site_to_rls(lat, lng, height, SHIP:BODY:RADIUS)).
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
  lm_put_ship_site(geo:LAT, geo:LNG, height).
  core_say("P68 started.").
  RETURN prog.
}
FUNCTION lm_p68_step { PARAMETER prog, nav, ks. RETURN p68_step(prog, ks). }
FUNCTION lm_p68_end {
  PARAMETER prog.
  IF prog:HASKEY("ENGINE_LIT") { p63_end(prog). }      // came from the burn: give the controls back (P63's END, as P65's)
}
FUNCTION lm_p68_sample { PARAMETER prog. lm_abort_poll(). }

// P51, the simplified IMU orientation (lm_r02.ks): one flashing request, PRO sets LM_VEH["IMU_OK"].
FUNCTION lm_p51_start {
  PARAMETER prev.
  LOCAL started IS p51_start(prev).
  core_say("P51 started.").
  RETURN started.
}
FUNCTION lm_p51_step { PARAMETER prog, nav, ks. RETURN p51_step(prog, nav, ks). }
FUNCTION lm_p51_end { PARAMETER prog. p51_end(prog). }
FUNCTION lm_p51_sample { PARAMETER prog. }

// P30, external delta-V (lm_p30.ks). The state at TIG comes from the orbit prediction (POSITIONAT, VELOCITYAT, which include manoeuvre nodes still ahead) in the
// raw axes of the moment of the call, with that moment's axes mark; the body's mu and radius go with it for the apsides. START refuses while TIG or the delta-V is not loaded, or TIG has passed. The step is given the
// UT each cycle (for N45's time to go). The result P40, P41 and P42 read is LM_VEH["XDELV"] (FALSE until P30 or P32 to P35 has set a burn).
FUNCTION lm_p30_predict {
  PARAMETER t_ut.
  // Guard: the state is asked for 0.05 s before TIG so that a KSP manoeuvre node at TIG cannot make VELOCITYAT return the velocity after that
  // node's burn (the burn would then be counted twice). 0.05 s is about 0.003 degrees of orbit, so the apsides do not change. Never before now.
  LOCAL t_predict IS MAX(t_ut - 0.05, TIME:SECONDS).
  // WAIT 0 gives the reads a fresh physics tick together: POSITIONAT is measured from the ship's position now, so the body's position is subtracted at once.
  // Nothing is turned: the vectors stay in the axes of this call, and AX says which those are.
  WAIT 0.
  RETURN LEXICON("R", POSITIONAT(SHIP, t_predict) - SHIP:BODY:POSITION, "V", VELOCITYAT(SHIP, t_predict):ORBIT,
                 "MU", SHIP:BODY:MU, "RADIUS", SHIP:BODY:RADIUS, "AX", axes_mark()).
}
FUNCTION lm_p30_start {
  PARAMETER prev.
  LOCAL started IS p30_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, lm_p30_predict@).
  lm_trk_on(started).
  IF started["REFUSED"] = "" { core_say("P30 started."). }
  RETURN started.
}
FUNCTION lm_p30_step {
  PARAMETER prog, nav, ks.
  SET prog["NOW_UT"] TO nav["STATE"]["T"].
  RETURN p30_step(prog, ks).
}
FUNCTION lm_p30_end { PARAMETER prog. p30_end(prog). }
FUNCTION lm_p30_sample { PARAMETER prog. }

// P32, CSI targeting (lm/rndz/lm_p32.ks). lm_rndz_snapshot reads both craft at one instant, from the Moon's centre, in the raw axes of that instant (AX).
// The CSM is the vessel named in the saved ascent plan, else the targeted one. RADIUS (for the perilune alarms) is |RLS| when it is loaded, else the body's
// radius, as the lunar branch of Luminary's SETRAD.
FUNCTION lm_rndz_snapshot {
  LOCAL status_now IS ctl_status().
  IF SHIP:BODY:NAME <> BODY_NAME OR status_now = "LANDED" OR status_now = "SPLASHED" OR status_now = "PRELAUNCH" {
    RETURN LEXICON("OK", FALSE, "WHY", "the LM is not in lunar orbit").
  }
  LOCAL csm_ves IS lm_find_csm(plan_read(ASC_PLAN_FILE), "NAMED_FIRST").
  IF NOT csm_ves:ISTYPE("Vessel") { RETURN LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit: target it, or plan the ascent with it"). }
  LOCAL radius_body IS SHIP:BODY:RADIUS.
  IF store_loaded(LM_VEH["STORE"], "RLS") { SET radius_body TO lm_store_get_rls(LM_VEH["STORE"]):MAG. }
  WAIT 0.          // a fresh physics tick, so that all the reads below belong together
  RETURN LEXICON("OK", TRUE, "WHY", "", "T", TIME:SECONDS, "R", -SHIP:BODY:POSITION, "V", SHIP:VELOCITY:ORBIT,
                 "RT", csm_ves:POSITION - SHIP:BODY:POSITION, "VT", csm_ves:VELOCITY:ORBIT, "AX", axes_mark(),
                 "MU", SHIP:BODY:MU, "RADIUS", radius_body, "CSM", csm_ves).
}
FUNCTION lm_p32_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL started IS p32_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, lm_rndz_snapshot@).
  lm_trk_on(started).
  IF started["REFUSED"] = "" { core_say("P32 started."). }
  RETURN started.
}
FUNCTION lm_p32_step {
  PARAMETER prog, nav, ks.
  SET prog["NOW_UT"] TO nav["STATE"]["T"].
  LOCAL out IS p32_step(prog, ks).
  lm_trk_set("UPDATE", NOT prog["FINAL"]).          // marks freeze from the final computation
  RETURN out.
}
FUNCTION lm_p32_end { PARAMETER prog. p32_end(prog). }
FUNCTION lm_p32_sample { PARAMETER prog. }

// ---- tracking: P20 and P25 (lm_p20.ks) and the flags the other programmes set ------------------------------------

// lm_trk_flags: the tracking flags (trk_flags_new), made on first use.
FUNCTION lm_trk_flags {
  IF NOT LM_VEH:HASKEY("TRACK") { SET LM_VEH["TRACK"] TO trk_flags_new(). }
  RETURN LM_VEH["TRACK"].
}

// lm_trk_set: one tracking flag.
FUNCTION lm_trk_set {
  PARAMETER flag_name, value.
  LOCAL flags_now IS lm_trk_flags().
  SET flags_now[flag_name] TO value.
}

// lm_trk_on: a programme that tracks started (P30, P32 to P35): tracking and updates on.
FUNCTION lm_trk_on {
  PARAMETER started.
  IF started["REFUSED"] <> "" { RETURN. }
  lm_trk_set("TRACK", TRUE).
  lm_trk_set("UPDATE", TRUE).
}

// lm_trk_release: the tracker gives the attitude back, if it holds it. Safe to call at any time.
FUNCTION lm_trk_release {
  IF NOT LM_VEH:HASKEY("TRK_CTL") { RETURN. }
  IF NOT LM_VEH["TRK_CTL"] { RETURN. }
  SET LM_VEH["TRK_CTL"] TO FALSE.
  ctl_track_release().
}

// lm_rails_rate: the rate of a rails warp (KUNIVERSE:TIMEWARP, mode and rate), 1 in physics warp or with none. A craft can be steered in physics
// warp, not on rails.
FUNCTION lm_rails_rate {
  PARAMETER mode_text, rate.
  IF mode_text = "RAILS" { RETURN rate. }
  RETURN 1.
}

// lm_trk_apply: fly what the tracker asks (ctl: "STEER", "DIR", "UP", "HARD"). auto_att FALSE (SAS on) or a rails warp: it lets go. The controls
// are taken at the first command, with the project's coast deadband (db_step; not while turning).
FUNCTION lm_trk_apply {
  PARAMETER ctl, auto_att, warp_rate.
  IF NOT LM_VEH:HASKEY("TRK_CTL") { SET LM_VEH["TRK_CTL"] TO FALSE. }
  IF NOT auto_att OR NOT ctl["STEER"] OR warp_rate > 1 { lm_trk_release(). RETURN. }
  IF NOT LM_VEH["TRK_CTL"] {
    ctl_track_start().
    SET LM_VEH["TRK_CTL"] TO TRUE.
    LOCAL fresh_db IS db_new().
    IF NOT ctl_descent_attached() { SET fresh_db["RATE"] TO ASC_DB_RATE_DEG_S. }
    SET LM_VEH["TRK_DB"] TO fresh_db.
  }
  ctl_set_command(ctl["DIR"], ctl["UP"], 0).          // the throttle command goes nowhere: the tracker locks no throttle
  LOCAL dbs IS LM_VEH["TRK_DB"].
  LOCAL locked_before IS dbs["LOCKED"].
  db_step(dbs, ctl_att_error_deg(), ctl_rate_deg_s(), ctl["HARD"]).
  IF dbs["LOCKED"] <> locked_before {
    IF dbs["LOCKED"] { ctl_steer_lock(). } ELSE { ctl_steer_release(). }
  }
}

// lm_v37_hook: the core's V37_HOOK. Every V37 lets the attitude go (before the new programme takes it) and switches tracking off, except P20 and
// P25, which switch it on (FRESH_START_AND_RESTART.agc 955-1039).
FUNCTION lm_v37_hook {
  PARAMETER number.
  lm_trk_release().
  lm_trk_set("TRACK", number = 20 OR number = 25).
  lm_trk_set("UPDATE", number = 20 OR number = 25).
  SET LM_VEH["TRK_SAS_CHECK"] TO number = 20 OR number = 25.          // read at the tracker's next step (lm_trk_sas_text)
}

// lm_trk_sas_text: once after P20 or P25 is keyed (also while it already runs): what to say if SAS holds its steering off, else "". Ours: on the
// real LM the mode switch was the crew's, and the computer never moves SAS for tracking.
FUNCTION lm_trk_sas_text {
  PARAMETER prog_no, auto_att.
  IF NOT LM_VEH:HASKEY("TRK_SAS_CHECK") { RETURN "". }
  IF NOT LM_VEH["TRK_SAS_CHECK"] { RETURN "". }
  SET LM_VEH["TRK_SAS_CHECK"] TO FALSE.
  IF auto_att { RETURN "". }
  RETURN "P" + prog_no + ": SAS IS ON, TURN IT OFF TO STEER.".
}

// lm_verb_56: V56, terminate tracking: the flags off and the second slot ended.
FUNCTION lm_verb_56 {
  PARAMETER ks.
  lm_trk_set("TRACK", FALSE).
  lm_trk_set("UPDATE", FALSE).
  SET ks["END_BACK"] TO TRUE.
  RETURN TRUE.
}

// lm_verb_93: V93, the next mark restarts the count at 1.
FUNCTION lm_verb_93 {
  PARAMETER ks.
  lm_trk_set("REINIT", TRUE).
  RETURN TRUE.
}

// The tracking log: a line for each change of the tracker's state and each mark, and the results of V83, V89 and V90. Appended to; the pad
// tests point it elsewhere.
GLOBAL P20_LOG_PATH IS "0:/lm/logs/p20.log".
FUNCTION lm_trk_log {
  PARAMETER text.
  LOG "T " + ROUND(TIME:SECONDS) + "  " + text TO P20_LOG_PATH.
}

// lm_trk_where: how far +Z and +X are off the CSM, and the range, as text for the log.
FUNCTION lm_trk_where {
  LOCAL seen IS lm_rndz_snapshot().
  IF NOT seen["OK"] { RETURN seen["WHY"]. }
  LOCAL line IS seen["RT"] - seen["R"].
  RETURN "+Z " + ROUND(VANG(ctl_window_face_vec(), line), 1) + " deg off, +X " + ROUND(VANG(SHIP:FACING:FOREVECTOR, line), 1)
         + " deg off, range " + ROUND(line:MAG / 1000, 2) + " km".
}

// lm_trk_state: the tracker's state in one word or two, for the log. Pure.
FUNCTION lm_trk_state {
  PARAMETER prog, out, auto_att, warp_rate.
  IF out["ENDED"] { RETURN "ending". }
  IF NOT prog["FLAGS"]["TRACK"] { RETURN "off". }
  IF prog["OVER"] { RETURN "over 400 nmi". }
  IF NOT auto_att { RETURN "att hold". }
  IF warp_rate > 1 { RETURN "time warp". }
  IF prog["R60"]:ISTYPE("Lexicon") {
    IF prog["R60"]["STATE"] = "TURNING" { RETURN "turning". }
    RETURN "request V50 N18".
  }
  IF out["CTL"]["STEER"] { RETURN "steering". }
  RETURN "quiet".
}

// lm_trk_line: the terminal's line for the programme running in the background (our own: the DSKY shows only the selected programme). Pure. The
// state words are short enough for the line to fit 48 columns; the log keeps lm_trk_state's own.
FUNCTION lm_trk_line {
  PARAMETER prog_no, state_word, marks.
  LOCAL said IS state_word.
  IF state_word = "quiet" { SET said TO "waiting". }
  IF state_word = "request V50 N18" { SET said TO "V50 N18". }
  IF state_word = "over 400 nmi" { SET said TO "too far". }
  LOCAL line IS "RUNNING IN BACKGROUND: P" + prog_no + " " + said.
  IF prog_no = 20 { SET line TO line + ", " + marks + (CHOOSE " mark" IF marks = 1 ELSE " marks"). }
  RETURN line + ".".
}

// lm_trk_report: give the terminal its line (the output's STATUS) and log what changed this cycle.
FUNCTION lm_trk_report {
  PARAMETER prog, out, auto_att.
  LOCAL state_now IS lm_trk_state(prog, out, auto_att, lm_rails_rate(KUNIVERSE:TIMEWARP:MODE, KUNIVERSE:TIMEWARP:RATE)).
  LOCAL marks IS prog["FLAGS"]["MARKS"].
  IF NOT prog:HASKEY("LOG_STATE") {
    SET prog["LOG_STATE"] TO "".
    SET prog["LOG_MARKS"] TO marks.
  }
  SET out["STATUS"] TO LIST(lm_trk_line(prog["PROG_NO"], state_now, marks)).
  IF state_now <> prog["LOG_STATE"] {
    SET prog["LOG_STATE"] TO state_now.
    lm_trk_log("P" + prog["PROG_NO"] + " " + state_now + " (update " + prog["FLAGS"]["UPDATE"] + "): " + lm_trk_where()).
  }
  IF marks <> prog["LOG_MARKS"] {
    SET prog["LOG_MARKS"] TO marks.
    lm_trk_log("mark " + marks + ": " + lm_trk_where()).
  }
  IF out["ALARM"] > 0 AND out["WARN"] <> "" { lm_trk_log(out["WARN"]). }
}

// lm_p20_new: P20 or P25 from V37.
FUNCTION lm_p20_new {
  PARAMETER prog_no.
  RETURN lm_p20_began(prog_no, p20_start(prog_no, LM_VEH["PROFILE"], lm_trk_flags(), TIME:SECONDS, lm_rndz_snapshot@)).
}
// lm_p20_began: what follows a V37 start of P20 or P25, refused or not: TRK_RUN (the drift gauge's condition), the message and the log.
FUNCTION lm_p20_began {
  PARAMETER prog_no, started.
  SET LM_VEH["TRK_RUN"] TO started["REFUSED"] = "".
  IF started["REFUSED"] = "" {
    core_say("P" + prog_no + " started.").
    lm_trk_log("P" + prog_no + " started, profile " + LM_VEH["PROFILE"]).
  }
  RETURN started.
}
FUNCTION lm_p20_start { PARAMETER prev. RETURN lm_p20_new(20). }
FUNCTION lm_p25_start { PARAMETER prev. RETURN lm_p20_new(25). }
// lm_trk_att: the attitude the tracker and V89 work from (see lm_p20.ks).
FUNCTION lm_trk_att {
  PARAMETER auto_att.
  RETURN LEXICON("AUTO", auto_att, "NOSE", SHIP:FACING:FOREVECTOR, "FACE", ctl_window_face_vec(), "ERR", ctl_att_error_deg(),
                 "RATE", ctl_rate_deg_s(), "REF", LM_VEH["REF_ATT"]).
}
FUNCTION lm_p20_step {
  PARAMETER prog, nav, ks.
  LOCAL auto_att IS NOT ctl_sas_read(FALSE).
  LOCAL out IS p20_step(prog, lm_trk_att(auto_att), nav["STATE"]["T"], ks).
  lm_trk_apply(out["CTL"], auto_att, lm_rails_rate(KUNIVERSE:TIMEWARP:MODE, KUNIVERSE:TIMEWARP:RATE)).
  lm_trk_report(prog, out, auto_att).
  LOCAL sas_text IS lm_trk_sas_text(prog["PROG_NO"], auto_att).
  IF sas_text <> "" { core_warn(sas_text). }
  RETURN out.
}
FUNCTION lm_p20_end {
  PARAMETER prog.
  lm_trk_log("P20/P25 ended").
  SET LM_VEH["TRK_RUN"] TO FALSE.
  lm_trk_release().
  lm_trk_set("TRACK", FALSE).
  lm_trk_set("UPDATE", FALSE).
}

// ---- the rendezvous verbs V83, V89 and V90 (lm_rverbs.ks): answering extended displays ------------------------

// lm_ext_refused: no rendezvous routine starts during a load or an update, a priority display or another extended display.
FUNCTION lm_ext_refused {
  PARAMETER ks.
  RETURN load_active(ks) OR p27_active(ks) OR ks["PRIO"]:ISTYPE("Lexicon") OR ks["EXT"]:ISTYPE("Lexicon").
}

// lm_ext_snapshot_ok: TRUE when there is a CSM to work with; otherwise says why the verb is refused.
FUNCTION lm_ext_snapshot_ok {
  PARAMETER name.
  LOCAL seen IS lm_rndz_snapshot().
  IF NOT seen["OK"] { core_warn(name + " refused: " + seen["WHY"] + "."). }
  RETURN seen["OK"].
}

FUNCTION lm_v83_step {
  PARAMETER nav, ans.
  LOCAL out IS v83_step(lm_rndz_snapshot(), ctl_window_face_vec(), ans).
  IF out["ENDED"] AND out["DERIVED"]:HASKEY("N54") {
    LOCAL shown IS out["DERIVED"]["N54"].
    lm_trk_log("V83: range " + ROUND(shown[0] / 1000, 3) + " km, rate " + ROUND(shown[1], 2) + " m/s, theta " + ROUND(shown[2], 2)).
  }
  RETURN out.
}
FUNCTION lm_verb_83 {
  PARAMETER ks.
  IF lm_ext_refused(ks) { RETURN FALSE. }
  IF NOT lm_ext_snapshot_ok("V83") { RETURN FALSE. }
  SET ks["EXT"] TO LEXICON("VERB", 16, "NOUN", 54, "ANSWERS", TRUE, "STEP", lm_v83_step@).
  RETURN TRUE.
}

// lm_v90_allowed: not during the burn, ascent and descent programmes (R36 refuses with average G on).
FUNCTION lm_v90_allowed {
  PARAMETER prog.
  IF NOT prog:ISTYPE("Lexicon") { RETURN TRUE. }
  LOCAL number IS prog["PROG_NO"].
  RETURN NOT (number = 12 OR (number >= 40 AND number <= 47) OR (number >= 63 AND number <= 71)).
}
FUNCTION lm_v90_step {
  PARAMETER st, nav, ans.
  LOCAL out IS v90_step(st, lm_rndz_snapshot(), lm_clock_zero_ut(), TIME:SECONDS, lm_n16(), ans).
  IF out["LOAD16"] >= 0 { SET LM_VEH["N16"] TO out["LOAD16"]. }
  IF ans["PRO"] AND out["DERIVED"]:HASKEY("N90") {
    LOCAL shown IS out["DERIVED"]["N90"].
    lm_trk_log("V90 at N16 " + ROUND(lm_n16(), 2) + " s (0 = now): Y " + ROUND(shown[0], 1) + " m, Y rate " + ROUND(shown[1], 3) + " m/s, psi " + ROUND(shown[2], 2)).
  }
  RETURN out.
}
FUNCTION lm_verb_90 {
  PARAMETER ks.
  IF lm_ext_refused(ks) OR NOT lm_v90_allowed(ks["PROGRAM"]) { RETURN FALSE. }
  IF NOT lm_ext_snapshot_ok("V90") { RETURN FALSE. }
  LOCAL st IS v90_new(lm_store_get_tig(LM_VEH["STORE"])).
  SET ks["EXT"] TO LEXICON("VERB", 6, "NOUN", 16, "ANSWERS", TRUE, "STEP", lm_v90_step@:BIND(st)).
  RETURN TRUE.
}

// V89 turns the LM itself, through the tracker's controls (lm_trk_apply); its END lets them go.
FUNCTION lm_v89_step {
  PARAMETER st, ks, nav, ans.
  LOCAL auto_att IS NOT ctl_sas_read(FALSE).
  LOCAL att IS lm_trk_att(auto_att).
  SET att["OPTION"] TO lm_n12()[1].
  LOCAL out IS v89_step(st, att, TIME:SECONDS, ans, ks).
  lm_trk_apply(out["CTL"], auto_att, lm_rails_rate(KUNIVERSE:TIMEWARP:MODE, KUNIVERSE:TIMEWARP:RATE)).
  IF out["ENDED"] { lm_trk_log("V89 ended (option " + att["OPTION"] + "): " + lm_trk_where()). }
  RETURN out.
}
FUNCTION lm_verb_89 {
  PARAMETER ks.
  IF lm_ext_refused(ks) OR ks["PROGRAM"]:ISTYPE("Lexicon") { RETURN FALSE. }        // only in P00 with nothing running underneath
  IF NOT lm_ext_snapshot_ok("V89") { RETURN FALSE. }
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL words IS lm_n12().
  SET words[0] TO 3.              // R63: option code 00003, +Z
  SET words[1] TO 1.
  LOCAL st IS v89_new(lm_rndz_snapshot@).
  SET ks["EXT"] TO LEXICON("VERB", 4, "NOUN", 12, "ANSWERS", TRUE, "STEP", lm_v89_step@:BIND(st, ks), "END", lm_trk_release@).
  RETURN TRUE.
}

// P33, CDH targeting (lm_p32.ks), on the same snapshot.
FUNCTION lm_p33_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL started IS p33_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, lm_rndz_snapshot@).
  lm_trk_on(started).
  IF started["REFUSED"] = "" { core_say("P33 started."). }
  RETURN started.
}
FUNCTION lm_p33_step {
  PARAMETER prog, nav, ks.
  SET prog["NOW_UT"] TO nav["STATE"]["T"].
  LOCAL out IS p33_step(prog, ks).
  lm_trk_set("UPDATE", NOT prog["FINAL"]).          // marks freeze from the final computation
  RETURN out.
}
FUNCTION lm_p33_end { PARAMETER prog. p33_end(prog). }
FUNCTION lm_p33_sample { PARAMETER prog. }

// P34, TPI targeting, and P35, midcourse targeting (lm_p34.ks), on the same snapshot. Their burn is an aim point (LM_VEH["XDELV"] with "AIM").
FUNCTION lm_p34_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL started IS p34_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, lm_rndz_snapshot@).
  lm_trk_on(started).
  IF started["REFUSED"] = "" { core_say("P34 started."). }
  RETURN started.
}
FUNCTION lm_p34_step {
  PARAMETER prog, nav, ks.
  SET prog["NOW_UT"] TO nav["STATE"]["T"].
  LOCAL out IS p34_step(prog, ks).
  lm_trk_set("UPDATE", NOT prog["FINAL"]).          // marks freeze from the final computation
  RETURN out.
}
FUNCTION lm_p34_end { PARAMETER prog. p34_end(prog). }
FUNCTION lm_p34_sample { PARAMETER prog. }
FUNCTION lm_p35_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL started IS p35_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, lm_rndz_snapshot@).
  lm_trk_on(started).
  IF started["REFUSED"] = "" { core_say("P35 started."). }
  RETURN started.
}
FUNCTION lm_p35_step {
  PARAMETER prog, nav, ks.
  SET prog["NOW_UT"] TO nav["STATE"]["T"].
  LOCAL out IS p35_step(prog, ks).
  lm_trk_set("UPDATE", NOT prog["FINAL"]).          // marks freeze from the final computation
  RETURN out.
}
FUNCTION lm_p35_end { PARAMETER prog. p35_end(prog). }
FUNCTION lm_p35_sample { PARAMETER prog. }

// lm_ref_att: N18's reference attitude in the axes of the burn that is set. With no burn set, as stored (P40 and P41 refuse then).
FUNCTION lm_ref_att {
  LOCAL xdelv IS LM_VEH["XDELV"].
  IF NOT xdelv:ISTYPE("Lexicon") { RETURN LM_VEH["REF_ATT"]. }
  RETURN r60_ref_in(LM_VEH["REF_ATT"], xdelv["AX0"]).
}

// P40, the DPS burn (lm_p40.ks). START refuses until a burn is set (LM_VEH["XDELV"]) and while TIG is not loaded; it takes the controls. The engine is the one with the most vacuum
// thrust (ctl_find_engine). The step is given the IMU flags and the staging flag each cycle; in the alarm 1706 phase the engine is looked for again (a re-check with PRO or V32).
FUNCTION lm_p40_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL eng IS ctl_find_engine().
  LOCAL f_max_n IS 0.
  IF eng:ISTYPE("Engine") { SET f_max_n TO eng:POSSIBLETHRUSTAT(0) * 1000. }
  LOCAL ref_att IS lm_ref_att().
  LOCAL started IS p40_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, eng, f_max_n, LM_VEH["XDELV"], ref_att["DIR"], ref_att["UP"]).
  IF started["REFUSED"] = "" { core_say("P40 started."). }
  RETURN started.
}
FUNCTION lm_p40_step {
  PARAMETER prog, nav, ks.
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  IF LM_VEH:HASKEY("STAGED") { SET prog["STAGED"] TO LM_VEH["STAGED"]. }
  IF prog["PHASE"] = "STAGED" {
    LOCAL eng IS ctl_find_engine().
    SET prog["ENGINE"] TO eng.
    SET prog["F_MAX_N"] TO (CHOOSE eng:POSSIBLETHRUSTAT(0) * 1000 IF eng:ISTYPE("Engine") ELSE 0).
  }
  RETURN lm_att_lamp(p40_step(prog, nav["STATE"], nav["DERIVED"], ks), prog).
}
FUNCTION lm_p40_end { PARAMETER prog. p40_end(prog). lm_trk_set("MARKS", 0). }
FUNCTION lm_p40_sample { PARAMETER prog. }

// P42, the ascent engine burn (lm_p40.ks). The engine is the ascent engine; alarm 1706 while the descent stage is on, looked at again each cycle
// until the burn begins.
FUNCTION lm_p42_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL eng IS ctl_find_ascent_engine().
  LOCAL f_max_n IS 0.
  IF eng:ISTYPE("Engine") { SET f_max_n TO eng:POSSIBLETHRUSTAT(0) * 1000. }
  LOCAL ref_att IS lm_ref_att().
  LOCAL started IS p42_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, eng, f_max_n, LM_VEH["XDELV"], ref_att["DIR"], ref_att["UP"],
                             ctl_descent_attached()).
  IF started["REFUSED"] = "" { core_say("P42 started."). }
  RETURN started.
}
FUNCTION lm_p42_step {
  PARAMETER prog, nav, ks.
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  IF prog["PHASE"] = "CHECK" OR prog["PHASE"] = "STAGED" {
    LOCAL eng IS ctl_find_ascent_engine().
    SET prog["ENGINE"] TO eng.
    SET prog["F_MAX_N"] TO (CHOOSE eng:POSSIBLETHRUSTAT(0) * 1000 IF eng:ISTYPE("Engine") ELSE 0).
    SET prog["ATTACHED"] TO ctl_descent_attached().
  }
  RETURN lm_att_lamp(p40_step(prog, nav["STATE"], nav["DERIVED"], ks), prog).
}
FUNCTION lm_p42_end { PARAMETER prog. p40_end(prog). lm_trk_set("MARKS", 0). }
FUNCTION lm_p42_sample { PARAMETER prog. }

// P41, the RCS burn, and P47, the thrust monitor (lm_p41.ks): the pilot burns by hand. P41 starts like P40 (a burn set by P30 or P32 to P35); P47 needs nothing.
FUNCTION lm_p41_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL ref_att IS lm_ref_att().
  LOCAL started IS p41_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, ctl_find_engine(), LM_VEH["XDELV"], ref_att["DIR"], ref_att["UP"]).
  IF started["REFUSED"] = "" { core_say("P41 started."). }
  RETURN started.
}
FUNCTION lm_p41_step {
  PARAMETER prog, nav, ks.
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  RETURN lm_att_lamp(p41_step(prog, nav["STATE"], nav["DERIVED"], ks), prog).
}
FUNCTION lm_p41_end { PARAMETER prog. p41_end(prog). lm_trk_set("MARKS", 0). }
FUNCTION lm_p41_sample { PARAMETER prog. }
FUNCTION lm_p47_start {
  PARAMETER prev.
  LOCAL started IS p47_start(prev, TIME:SECONDS, axes_mark()).
  core_say("P47 started.").
  IF LM_VEH:HASKEY("TRK_RUN") { IF LM_VEH["TRK_RUN"] { core_say(P47_TRACK_TEXT). } }
  RETURN started.
}
FUNCTION lm_p47_step {
  PARAMETER prog, nav, ks.
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  RETURN p47_step(prog, nav["STATE"], nav["DERIVED"], ks).
}
FUNCTION lm_p47_end { PARAMETER prog. p47_end(prog). }
FUNCTION lm_p47_sample { PARAMETER prog. }

// P12, the ascent (lm/ascent/lm_p12.ks). The CSM is the vessel named in the saved ascent plan (so a later target change does not move it); with no
// plan, the targeted vessel. FALSE when it is missing or not in orbit round the Moon.
FUNCTION lm_p12_csm {
  PARAMETER plan.
  RETURN lm_find_csm(plan, "NAMED_ONLY").
}
FUNCTION lm_p12_start {
  PARAMETER prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  // On the surface the ship itself is the landing site, so RLS is stored from it: no P68 needed, and no old site from another flight. A departure
  // (Luminary P12 only reads RLS), at the user's request.
  IF ctl_status() = "LANDED" {
    LOCAL geo IS SHIP:GEOPOSITION.
    lm_put_ship_site(geo:LAT, geo:LNG, SHIP:ALTITUDE).
    core_say("P12: landing site taken from the ship's position.").
  }
  lm_refresh_site().          // the nouns need the site: no cycle without a programme runs between V37 and P12 to pick up the new RLS
  LOCAL plan IS plan_read(ASC_PLAN_FILE).
  LOCAL csm_ves IS lm_p12_csm(plan).
  LOCAL craft IS LEXICON("STATUS", ctl_status(), "ENGINE", ctl_find_ascent_engine(), "CORE_STAYS", ctl_core_stays(), "CSM", FALSE, "PLAN", plan).
  IF csm_ves:ISTYPE("Vessel") {
    SET craft["CSM"] TO LEXICON("NAME", csm_ves:NAME, "R", csm_ves:POSITION - SHIP:BODY:POSITION, "V", csm_ves:VELOCITY:ORBIT).
  }
  SET craft["AX"] TO axes_mark().          // the axes the CSM state is in
  LOCAL started IS p12_start(prev, LM_VEH["STORE"], lm_clock_zero_ut(), LM_VEH["PROFILE"], TIME:SECONDS, craft, LM_VEH["WM"]).
  IF started["REFUSED"] = "" {
    SET LM_VEH["CSM"] TO csm_ves.          // for the log's CSM angle
    core_say("P12 started, to " + craft["CSM"]["NAME"] + ".").
  }
  RETURN started.
}
// Once the stages have separated the vehicle is marked staged (the descent programmes refuse it) and the landed position is dropped (N43, CONTACT).
FUNCTION lm_p12_step {
  PARAMETER prog, nav, ks.
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  IF LM_VEH:HASKEY("CSM") { SET prog["CSM_NOW"] TO LM_VEH["CSM"]:POSITION - SHIP:BODY:POSITION. }
  LOCAL out IS p12_step(prog, nav["STATE"], nav["DERIVED"], ks).
  IF prog["STAGED_DONE"] {
    SET LM_VEH["STAGED"] TO TRUE.
    IF LM_VEH:HASKEY("LANDED_POS") { LM_VEH:REMOVE("LANDED_POS"). }
  }
  RETURN lm_att_lamp(out, prog).
}
FUNCTION lm_p12_end { PARAMETER prog. p12_end(prog). }
FUNCTION lm_p12_sample { PARAMETER prog. p12_cut_check(prog, TIME:SECONDS). }

// ---- the aborts, P70 and P71 (lm/ascent/lm_p70.ks) -----------------------------------------------------------------------
// LM_VEH["ABT"] is the abort state (armed at P63 ignition), "ABT_KEYS" the controls watched (Backspace, the 0 key, the descent stage leaving)
// and "ABT_KEY" TRUE while the programme asked for comes from one of them.

// lm_abort_csm: the CSM an abort is timed against, taken at P63 start and kept: the targeted vessel if it orbits the Moon, else the one named
// in the ascent plan; FALSE with neither.
FUNCTION lm_abort_csm {
  PARAMETER plan.
  RETURN lm_find_csm(plan, "TARGET_FIRST").
}
// lm_abort_csm_state: the CSM now as LEXICON NAME, R, V (from the Moon's centre), or FALSE: none, gone, or no longer in orbit round the Moon.
FUNCTION lm_abort_csm_state {
  PARAMETER csm_ves.
  IF NOT csm_ves:ISTYPE("Vessel") { RETURN FALSE. }
  IF csm_ves:ISDEAD { RETURN FALSE. }
  IF NOT lm_csm_in_orbit(csm_ves) { RETURN FALSE. }
  RETURN LEXICON("NAME", csm_ves:NAME, "R", csm_ves:POSITION - SHIP:BODY:POSITION, "V", csm_ves:VELOCITY:ORBIT).
}
// lm_abort_arm: after each P63 step: an ignition arms the aborts; the ship's own orbit plane is kept for an abort without a CSM.
FUNCTION lm_abort_arm {
  PARAMETER prog, state.
  IF NOT LM_VEH:HASKEY("ABT") { RETURN. }
  abt_ignition(LM_VEH["ABT"], prog["SEQ"]["IGN_T"], asc_qaxis(state["R"], state["V"]), state["T"], state["AX"]).
}
// lm_abort_poll: read the controls (every cycle, and every 0.02 s from the descent and abort programmes' sample hooks).
FUNCTION lm_abort_poll {
  IF NOT LM_VEH:HASKEY("ABT_KEYS") { RETURN. }
  abt_keys_poll(LM_VEH["ABT_KEYS"], ctl_abort_key(), ctl_ag10(), ctl_descent_attached()).
}
// lm_abort_source: the core's REQUEST_SOURCE: 70 or 71 when a control asks for it now, else -1.
FUNCTION lm_abort_source {
  PARAMETER prog, now_ut.
  IF NOT LM_VEH:HASKEY("ABT_KEYS") { RETURN -1. }
  lm_abort_poll().
  LOCAL cur_no IS -1.
  IF prog:ISTYPE("Lexicon") { SET cur_no TO prog["PROG_NO"]. }
  LOCAL status_text IS ctl_status().
  LOCAL asked IS abt_keys_take(LM_VEH["ABT"], LM_VEH["ABT_KEYS"], cur_no, status_text = "LANDED" OR status_text = "SPLASHED", ctl_descent_attached()).
  IF asked >= 0 { SET LM_VEH["ABT_KEY"] TO TRUE. }
  RETURN asked.
}
// lm_abort_start: gathers what p70_start needs about the craft. The site radius is the running programme's landing site, else RLS.
FUNCTION lm_abort_start {
  PARAMETER prog_no, prev.
  IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
  LOCAL by_key IS LM_VEH["ABT_KEY"].
  SET LM_VEH["ABT_KEY"] TO FALSE.
  LOCAL here IS nav_state().
  LOCAL vault IS LM_VEH["STORE"].
  LOCAL site_radius IS SHIP:BODY:RADIUS.
  IF store_loaded(vault, "RLS") { SET site_radius TO lm_store_get_rls(vault):MAG. }
  IF prev:ISTYPE("Lexicon") { IF prev:HASKEY("LAND") { SET site_radius TO prev["LAND"]:MAG. } }
  LOCAL status_text IS ctl_status().
  LOCAL craft IS LEXICON("DPS", ctl_find_descent_engine(), "APS", ctl_find_ascent_engine(), "ATTACHED", ctl_descent_attached(),
      "CORE_STAYS", ctl_core_stays(), "LANDED", status_text = "LANDED" OR status_text = "SPLASHED", "MASS_KG", here["MASS"] * 1000,
      "SITE_R", site_radius, "R", here["R"], "V", here["V"], "CSM", lm_abort_csm_state(LM_VEH["ABT"]["CSM"]),
      "CLOCK_ZERO", lm_clock_zero_ut(), "MU", here["MU"], "AX", here["AX"]).
  LOCAL started IS p70_start(prog_no, by_key, prev, LM_VEH["ABT"], vault, LM_VEH["PROFILE"], here["T"], craft, LM_VEH["WM"]).
  IF started["REFUSED"] = "" { lm_refresh_site(). }          // the nouns need the site
  RETURN started.
}
FUNCTION lm_p70_start { PARAMETER prev. RETURN lm_abort_start(70, prev). }
FUNCTION lm_p71_start { PARAMETER prev. RETURN lm_abort_start(71, prev). }
// As P12: the CSM follows the vessel, and once the stages have separated the vehicle is staged and the landed position dropped (N43, CONTACT).
FUNCTION lm_abort_step {
  PARAMETER prog, nav, ks.
  LOCAL csm_state IS lm_abort_csm_state(LM_VEH["ABT"]["CSM"]).
  SET prog["CSM_STATE"] TO csm_state.
  IF csm_state:ISTYPE("Lexicon") { SET prog["CSM_NOW"] TO csm_state["R"]. } ELSE { SET prog["CSM_NOW"] TO FALSE. }
  SET prog["IMU_ON"] TO LM_VEH["IMU_ON"].
  SET prog["IMU_OK"] TO LM_VEH["IMU_OK"].
  LOCAL out IS p70_step(prog, nav["STATE"], nav["DERIVED"], ks).
  IF prog["VEHICLE_STAGED"] {
    SET LM_VEH["STAGED"] TO TRUE.
    IF LM_VEH:HASKEY("LANDED_POS") { LM_VEH:REMOVE("LANDED_POS"). }
  }
  RETURN lm_att_lamp(out, prog).
}
FUNCTION lm_abort_end { PARAMETER prog. p12_end(prog). }
FUNCTION lm_abort_sample { PARAMETER prog. lm_abort_poll(). p12_cut_check(prog, TIME:SECONDS). }

FUNCTION lm_p65_end { PARAMETER prog. p65_end(prog). }
FUNCTION lm_p65_sample { PARAMETER prog. lm_abort_poll(). p65_sample(prog). }
FUNCTION lm_p66_end { PARAMETER prog. j_p66_end(prog). }
FUNCTION lm_p66_sample { PARAMETER prog. lm_abort_poll(). j_p66_sample(prog). }

// ---- keyed loads -------------------------------------------------------------------------------------------------------

// lm_load_time: a keyed load of a time noun (N11, N13, N33, N37) into its cell: hours, minutes, hundredths of seconds.
FUNCTION lm_load_time {
  PARAMETER vault, noun_no, comps, values.
  LOCAL cell IS LM_TIME_NOUNS["" + noun_no].
  LOCAL keyed IS lm_keyed_time(noun_no, lm_store_get_time(vault, cell), comps, values).
  IF keyed["WHY"] <> "" { RETURN keyed["WHY"]. }
  lm_store_put_time(vault, cell, keyed["S"]).
  RETURN "".
}

// lm_keyed_time: the time a load of hours, minutes and seconds in hundredths gives, starting from old_s (-1 none): LEXICON("WHY", why it is
// refused or "", "S", seconds).
FUNCTION lm_keyed_time {
  PARAMETER noun_no, old_s, comps, values.
  LOCAL parts IS LIST(0, 0, 0).
  IF old_s >= 0 { SET parts TO lm_hms_cs(old_s). }
  FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET parts[comps[i] - 1] TO values[i]. }
  IF parts[0] < 0 OR parts[1] < 0 OR parts[1] > 59 OR parts[2] < 0 OR parts[2] > 5999 {
    RETURN LEXICON("WHY", "N" + noun_no + " takes hours, minutes 0 to 59 and seconds 0 to 59.99, none negative", "S", old_s).
  }
  LOCAL new_s IS lm_hms_to_seconds(parts[0], parts[1], parts[2]).
  IF new_s * 100 >= LM_CLOCK_LIMIT_CS { RETURN LEXICON("WHY", "that time is beyond the AGC clock", "S", old_s). }
  RETURN LEXICON("WHY", "", "S", new_s).
}

// lm_n12 and lm_n16: the words of N12 (V89's code and option) and the time of N16 (V90), kept in the vehicle, not the store; zeros before any.
FUNCTION lm_n12 {
  IF NOT LM_VEH:HASKEY("N12") { SET LM_VEH["N12"] TO LIST(0, 0). }
  RETURN LM_VEH["N12"].
}
FUNCTION lm_n16 {
  IF NOT LM_VEH:HASKEY("N16") { SET LM_VEH["N16"] TO 0. }
  RETURN LM_VEH["N16"].
}

// lm_load_commit: the DSKY core's LOAD_COMMIT: the registers a keyed load V21 to V25 gave data to (comps, 1 to 3) and the signed
// integers keyed, as shown on the display. The times N11, N13, N33 and N37: lm_load_time. N81: tenths of ft/s of the delta-v in
// local vertical axes (N55, N69 and N76 below). A register not loaded keeps the stored value. Returns "" or the reason it refused.
FUNCTION lm_load_commit {
  PARAMETER noun_no, comps, values.
  LOCAL vault IS LM_VEH["STORE"].
  IF LM_TIME_NOUNS:HASKEY("" + noun_no) { RETURN lm_load_time(vault, noun_no, comps, values). }
  IF noun_no = 12 {
    LOCAL words IS lm_n12().
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET words[comps[i] - 1] TO values[i]. }
    RETURN "".
  }
  IF noun_no = 16 {
    LOCAL keyed IS lm_keyed_time(16, lm_n16(), comps, values).
    IF keyed["WHY"] = "" { SET LM_VEH["N16"] TO keyed["S"]. }
    RETURN keyed["WHY"].
  }
  IF noun_no = 55 {
    // N55: R1 NN, R2 elevation angle and R3 central angle in hundredths of a degree. All are checked first, then only the
    // keyed registers are written.
    LOCAL n55_keyed IS LIST(-1, -1, -1).
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO {
      LOCAL top IS 35999.
      IF comps[i] = 1 { SET top TO 99. }
      IF values[i] < 0 OR values[i] > top { RETURN "N55 takes NN 0 to 99 and angles 0 to 359.99, none negative". }
      IF comps[i] = 1 { SET n55_keyed[0] TO values[i]. } ELSE { SET n55_keyed[comps[i] - 1] TO values[i] / 100. }
    }
    lm_store_put_n55(vault, n55_keyed[0], n55_keyed[1], n55_keyed[2]).
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
  IF noun_no = 76 {
    // N76 (ascent targets): R1 horizontal and R2 radial speed in tenths of ft/s, R3 cross-range in tenths of nm. A register not loaded keeps its value.
    LOCAL asc IS lm_store_get_asc(vault).
    LOCAL asc_tenths IS LIST(ROUND(ms_to_fps(asc["ZDOTD"]) * 10), ROUND(ms_to_fps(asc["RDOTD"]) * 10), ROUND(m_to_nm(asc["XRANGE"]) * 10)).
    FROM { LOCAL i IS 0. } UNTIL i >= comps:LENGTH STEP { SET i TO i + 1. } DO { SET asc_tenths[comps[i] - 1] TO values[i]. }
    lm_store_put_asc(vault, asc_tenths[0] / 10 / FT_PER_M, asc_tenths[1] / 10 / FT_PER_M, asc_tenths[2] / 10 * M_PER_NM).
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
    "12", LEXICON("START", lm_p12_start@, "STEP", lm_p12_step@, "END", lm_p12_end@, "SAMPLE", lm_p12_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "70", LEXICON("START", lm_p70_start@, "STEP", lm_abort_step@, "END", lm_abort_end@, "SAMPLE", lm_abort_sample@, "NEXT", -1, "SELECTABLE", TRUE, "TAKEOVER", TRUE),
    "71", LEXICON("START", lm_p71_start@, "STEP", lm_abort_step@, "END", lm_abort_end@, "SAMPLE", lm_abort_sample@, "NEXT", -1, "SELECTABLE", TRUE, "TAKEOVER", TRUE),
    "63", LEXICON("START", lm_p63_start@, "STEP", lm_p63_step@, "END", lm_p63_end@, "SAMPLE", lm_p63_sample@, "NEXT", 64, "SELECTABLE", TRUE),
    "64", LEXICON("START", lm_p64_start@, "STEP", lm_p64_step@, "END", lm_p64_end@, "SAMPLE", lm_p64_sample@, "NEXT", 65, "SELECTABLE", FALSE),
    "65", LEXICON("START", lm_p65_start@, "STEP", lm_p65_step@, "END", lm_p65_end@, "SAMPLE", lm_p65_sample@, "NEXT", 68, "SELECTABLE", FALSE),
    "66", LEXICON("START", lm_p66_start@, "STEP", lm_p66_step@, "END", lm_p66_end@, "SAMPLE", lm_p66_sample@, "NEXT", 68, "SELECTABLE", FALSE),
    "68", LEXICON("START", lm_p68_start@, "STEP", lm_p68_step@, "END", lm_p68_end@, "SAMPLE", lm_p68_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "51", LEXICON("START", lm_p51_start@, "STEP", lm_p51_step@, "END", lm_p51_end@, "SAMPLE", lm_p51_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "20", LEXICON("START", lm_p20_start@, "STEP", lm_p20_step@, "END", lm_p20_end@, "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE, "BACKGROUND", TRUE),
    "25", LEXICON("START", lm_p25_start@, "STEP", lm_p20_step@, "END", lm_p20_end@, "SAMPLE", FALSE, "NEXT", -1, "SELECTABLE", TRUE, "BACKGROUND", TRUE),
    "30", LEXICON("START", lm_p30_start@, "STEP", lm_p30_step@, "END", lm_p30_end@, "SAMPLE", lm_p30_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "32", LEXICON("START", lm_p32_start@, "STEP", lm_p32_step@, "END", lm_p32_end@, "SAMPLE", lm_p32_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "33", LEXICON("START", lm_p33_start@, "STEP", lm_p33_step@, "END", lm_p33_end@, "SAMPLE", lm_p33_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "34", LEXICON("START", lm_p34_start@, "STEP", lm_p34_step@, "END", lm_p34_end@, "SAMPLE", lm_p34_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "35", LEXICON("START", lm_p35_start@, "STEP", lm_p35_step@, "END", lm_p35_end@, "SAMPLE", lm_p35_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "40", LEXICON("START", lm_p40_start@,"STEP", lm_p40_step@, "END", lm_p40_end@, "SAMPLE", lm_p40_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "41", LEXICON("START", lm_p41_start@, "STEP", lm_p41_step@, "END", lm_p41_end@, "SAMPLE", lm_p41_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "42", LEXICON("START", lm_p42_start@,"STEP", lm_p42_step@, "END", lm_p42_end@, "SAMPLE", lm_p42_sample@, "NEXT", -1, "SELECTABLE", TRUE),
    "47", LEXICON("START", lm_p47_start@, "STEP", lm_p47_step@, "END", lm_p47_end@, "SAMPLE", lm_p47_sample@, "NEXT", -1, "SELECTABLE", TRUE)).
}

// lm_vehicle_new: build the vehicle LEXICON for dsky_core.ks and set up the shared state in LM_VEH.
FUNCTION lm_vehicle_new {
  LOCAL plan IS plan_read(PLAN_PLAN_FILE).
  LOCAL profile IS lm_profile_for(plan).
  SET LM_VEH TO LEXICON("SITE", LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0), "LAND", V(0, 0, 0), "WM", moon_spin(), "PIN", FALSE, "FPIN", FALSE,
      "PROFILE", profile, "LR_PERMIT", FALSE, "ALARM_SCHED", LIST(), "ALARM_T", -1, "TABLE", FALSE, "STORE", store_new(lm_cells_for(profile)), "SITE_SIG", -1, "FILLED", LEXICON(), "XDELV", FALSE,
      "IMU_ON", TRUE, "IMU_OK", (IMU_ALIGN = "AUTO"), "REF_ATT", LEXICON("DIR", SHIP:FACING:FOREVECTOR, "UP", SHIP:FACING:TOPVECTOR, "AX", axes_mark()),
      "ABT", abt_new(), "ABT_KEY", FALSE, "ABT_KEYS", abt_keys_new(ctl_abort_key(), ctl_ag10(), ctl_descent_attached()),
      "TRK_RUN", FALSE, "DOCK", term_dock_new(), "TERM_NEXT", 0).
  // XDELV: the burn P40, P41 and P42 read: a LEXICON of DELVSIN, RTIG, VTIG, UT_TIG, DELVSAB and AX0, with "AIM" (R, UT, ROTATED) when P34 or P35 set it
  // (an aim point: XDELVFLG down). FALSE until P30 or P32 to P35 has set it.
  // IMU_ON: our IMU is always on. IMU_OK: its orientation is known (r02): TRUE at start with IMU_ALIGN AUTO, else only after P51. REF_ATT: the IMU reference
  // attitude (an assumed REFSMMAT: the attitude at DSKY start, with the axes mark of that moment) that N18's angles are measured against (r60_cdu_angles).
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
    "REQUEST_SOURCE", lm_abort_source@,
    "NO_NOUN_VERBS", LIST(56, 57, 58, 59, 60, 76, 77, 80, 81, 82, 83, 89, 90, 93, 95),
    "VERB_ACTIONS", LEXICON("57", lm_verb_57@, "58", lm_verb_58@, "77", lm_verb_accept@, "59", lm_verb_accept@, "60", lm_verb_accept@, "82", lm_verb_82@,
        "76", lm_verb_accept@, "80", lm_verb_accept@, "81", lm_verb_accept@, "95", lm_verb_accept@, "56", lm_verb_56@, "93", lm_verb_93@,
        "83", lm_verb_83@, "89", lm_verb_89@, "90", lm_verb_90@),
    "V37_HOOK", lm_v37_hook@,
    "START_VN", (CHOOSE LIST(16, 60) IF DSKY_START = "N60" ELSE LIST(-1, -1)),
    "NOUN_REGS", lm_noun_registers@,
    "NAV", lm_veh_nav@,
    "HOOK", lm_veh_hook@,
    "TICK", lm_term_tick@,
    "LAMPS", LEXICON("KEY_REL", "KEYREL", "ALT_LAMP", "ALT", "VEL_LAMP", "VEL", "CONTACT", "CONTACT", "ATT_HOLD", "ATTHOLD"),
    "IDLE_LAMPS", lm_idle_lamps@,
    "STICKY_PROGS", LIST(),                       // after P68 ends PROG goes to 00 as in Luminary (GOTOPOOH)
    "END_REQUEST", LEXICON("VERB", 37, "NOUN", 99, "QUIET", TRUE),          // the flashing V37 N99 request after a programme ends (Luminary GOP00FIX)
    "STORE", LM_VEH["STORE"],
    "STORE_SAVE", lm_store_save@,
    "LOG_FILE", LM_LOG_FILE,
    "LOG_CLOCK", lm_log_clock@,
    "P27_OK", lm_p27_ok@,
    "UPLINK_FILE", LM_UPLINK_FILE,
    "P27_ADDR", lm_p27_addr(LM_VEH["PROFILE"]),
    "LOADS", LM_LOADS,
    "LOAD_COMMIT", lm_load_commit@,
    "PROGRAMMES", table).
}
