// lm_main.ks -- the LM computer's main loop: navigation + DSKY display, the P63 braking programme (milestone 3) and the
// P64 approach programme (milestone 4) and the P65/P66 final descent (milestone 5).
//
//   RUNPATH("0:/lm/lm_main.ks").                         site = the one in the saved plan (0:/lm/plan.json, made by
//                                                        lm_deorbit.ks); with no plan, the point under the next
//                                                        perilune (placeholder in lm_constants.ks if not bound)
//   RUNPATH("0:/lm/lm_main.ks", 0.67, 23.47).            site latitude, longitude (degrees); height from terrain
//   RUNPATH("0:/lm/lm_main.ks", 0.67, 23.47, 0).         ...and site height above sea level, m
// This script never warps by itself. The only warp is inside P63 (V37 ENTR 63 ENTR): once the ship holds the burn attitude
// it warps to P63_WARP_LEAD_S before ignition (lm_p63.ks, lm_control.ks warp_step). Cross-check rows logged during a
// warp are skewed.
// Exit with V34 ENTR (Apollo "terminate"). Logs the cross-checks to 0:/lm/lm_check.log.
// Without a programme it only displays: it never steers or throttles. V37 ENTR 63 ENTR starts P63 (lm_p63.ks), which
// then steers and throttles the ship; V37 ENTR 00 ENTR ends it. P63 needs the saved plan (lm_deorbit.ks) for the
// same site and logs each cycle to 0:/lm/p63.log. V34 ENTR also ends P63 and hands the controls back to the pilot.
// P63 hands over to P64 by itself when the braking is over (PROG shows 64; it cannot be selected with V37). P64 logs
// to 0:/lm/p64.log; PRO permits redesignation and the pitch and yaw keys then move the aim point (lm_p64.ks).
// P64 hands over to P65 by itself at 12 s to go (lm_p65.ks, log 0:/lm/p65.log). In P65 a Shift or Ctrl tap (the throttle keys)
// is a rate-of-descent click and starts P66, as does switching SAS on; the CONTACT lamp lights at touchdown and the engine cuts off
// about a second later (P68).

// Parameter defaults are sentinels (impossible values): the real defaults live in lm_constants.ks,
// which is not loaded yet when the parameters are read, so they are filled in just below.
PARAMETER site_lat IS -999, site_lng IS -999, site_alt IS -999999.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_nav.ks").
RUNONCEPATH("0:/lm/lm_display.ks").
RUNONCEPATH("0:/lm/lm_gui.ks").
RUNONCEPATH("0:/lm/lm_checks.ks").
RUNONCEPATH("0:/lm/lm_plan.ks").            // plan_read, for the saved plan
RUNONCEPATH("0:/lm/lm_p63.ks").             // the P63 programme
RUNONCEPATH("0:/lm/lm_p64.ks").             // the P64 programme
RUNONCEPATH("0:/lm/lm_p65.ks").             // the P65 and P66 programmes
RUNONCEPATH("0:/lm/lm_site_pins.ks").       // pins_one: the map-view pin the planner window uses, for the landing-site marker

LOCAL log_path IS "0:/lm/lm_check.log".

// end_programme: give the controls back from whichever programme is running (P63, P64, or P65/P66).
FUNCTION end_programme {
  PARAMETER prog_lex.
  IF prog_lex["PROG_NO"] >= 65 { p65_end(prog_lex). } ELSE IF prog_lex["PROG_NO"] = 64 { p64_end(prog_lex). } ELSE { p63_end(prog_lex). }
}

// Only run over the body the constants were set up for (the whole frame work assumes it).
IF SHIP:BODY:NAME <> BODY_NAME {
  PRINT "LM computer: this ship is at " + SHIP:BODY:NAME + ", not " + BODY_NAME + ". Nothing to do.".
  PRINT "Run it in the " + BODY_NAME + "'s sphere of influence.".
  // Nothing was created yet, so there is no window to close. Ends the script.
} ELSE {
  // The saved plan from lm_deorbit.ks, if there is a usable one. have_plan stays FALSE otherwise. The checks
  // are nested because KerboScript's AND does not skip the right side when the left is false.
  LOCAL saved_plan IS plan_read(PLAN_PLAN_FILE).
  LOCAL have_plan IS FALSE.
  IF saved_plan:ISTYPE("Lexicon") {
    IF saved_plan:HASKEY("SITE_LAT") AND saved_plan:HASKEY("SITE_LNG") AND saved_plan:HASKEY("T_PDI") { SET have_plan TO TRUE. }
  }
  // No site given but a plan exists: use the plan's site (and its height unless one was given).
  IF have_plan AND site_lat = -999 AND site_lng = -999 {
    SET site_lat TO saved_plan["SITE_LAT"].
    SET site_lng TO saved_plan["SITE_LNG"].
    IF site_alt = -999999 AND saved_plan:HASKEY("SITE_ALT") { SET site_alt TO saved_plan["SITE_ALT"]. }
  }
  // No site given: use the point on the surface under the next perilune (the descent passes over it).
  // POSITIONAT gives the ship's position at a future time; GEOPOSITIONOF turns it into lat/lng. The Moon
  // turns during the coast, so the point can be off by a few tens of km (fine for a test; P64 redesignates).
  // Only valid on a bound orbit (ETA:PERIAPSIS is meaningless otherwise): then fall back to lm_constants.ks.
  IF site_lat = -999 AND site_lng = -999 AND SHIP:ORBIT:ECCENTRICITY < 1 {
    LOCAL peri_geo IS SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, TIME:SECONDS + ETA:PERIAPSIS)).
    SET site_lat TO peri_geo:LAT.
    SET site_lng TO peri_geo:LNG.
  }
  IF site_lat = -999 { SET site_lat TO SITE_LAT. }
  IF site_lng = -999 { SET site_lng TO SITE_LNG. }
  // Default site height: the terrain height at the site (metres above sea level).
  IF site_alt = -999999 { SET site_alt TO LATLNG(site_lat, site_lng):TERRAINHEIGHT. }

  // 2000 is the largest CONFIG:IPU: the default 150 is too slow for a live window.
  SET CONFIG:IPU TO 2000.

  // The site and the Moon's spin vector are constant in the raw axes (AXES_ROTATE = true), so they are
  // computed once. If AXES_ROTATE were false, land_update would have to run every cycle.
  LOCAL land_vec IS land_vector(site_lat, site_lng, site_alt).
  LOCAL wm_vec IS moon_spin().

  LOCAL ks IS keys_new().
  check_log_header(log_path).

  // The GUI() window must be made here, at the top level of the main script, not in a function.
  CLEARGUIS().
  GLOBAL dsky_win IS GUI(GUI_WINDOW_WIDTH).
  SET dsky_win:X TO 60.
  SET dsky_win:Y TO 60.
  GLOBAL ui IS gui_fill(dsky_win).
  dsky_win:SHOW().
  // The landing-site marker: the planner window's map pin (lm_site_pins.ks, an arrow standing above the site and pointing down at it,
  // positions from per-frame delegates, width relative to the camera), shown in map view while a programme runs. It is the "custom" kind
  // of pin, so it follows pins_custom_geo, set each cycle below to the site in use (the redesignated one in P64 and later). Kept in a global.
  GLOBAL site_pin IS pins_one(SITE_MARK_LABEL, LATLNG(site_lat, site_lng), TRUE).
  SET site_pin:COLOR TO PINS_COLOR_SELECTED.
  CLEARSCREEN.
  PRINT "LM computer running. Site " + ROUND(site_lat, 3) + " N, " + ROUND(site_lng, 3) + " E, " + ROUND(site_alt) + " m.".
  PRINT "Use the keypad or type here. V34 ENTR ends the program.".

  LOCAL idle_prog_text IS "00".   // what PROG shows with no programme running: 68 after a landing, until the next V37
  LOCAL prog IS FALSE.            // the running programme's state (a LEXICON from p63_start, then p64_start), FALSE when none
  LOCAL t_start IS TIME:SECONDS.
  LOCAL next_t IS t_start.
  LOCAL running IS TRUE.
  UNTIL NOT running {
    LOCAL state IS nav_state().
    // Left the Moon's SOI mid-run: stop rather than show nonsense.
    IF NOT state["BODY_OK"] {
      PRINT "Left the " + BODY_NAME + "'s sphere of influence. Stopping.".
      SET running TO FALSE.
    } ELSE {
      // While P63 runs the landing-site vector is re-read every cycle (one kOS read). Milestones 1 and 2 computed it once,
      // relying on the raw axes turning with the Moon; whether they still do near the descent orbit's high point was
      // not established (the planner measured them as inertial at 112 km), so P63 does not depend on it.
      IF prog:ISTYPE("Lexicon") {
        IF prog["PROG_NO"] >= 64 {
          // P64 may have moved the site (P65 and P66 keep it): it keeps the redesignated site as latitude, longitude and height.
          SET land_vec TO land_vector(prog["SITE_LAT"], prog["SITE_LNG"], prog["SITE_ALT"]).
        } ELSE {
          SET land_vec TO land_vector(site_lat, site_lng, site_alt).
        }
        SET prog["LAND"] TO land_vec.
      }
      LOCAL derived IS nav_derived(state, land_vec, wm_vec).
      IF prog:ISTYPE("Lexicon") {
        IF prog["PROG_NO"] >= 64 { SET pins_custom_geo TO LATLNG(prog["SITE_LAT"], prog["SITE_LNG"]). }
        ELSE { SET pins_custom_geo TO LATLNG(site_lat, site_lng). }
        SET site_pin:SHOW TO MAPVIEW.
      } ELSE {
        SET site_pin:SHOW TO FALSE.
      }
      gui_poll(ui, ks).
      // V37 ENTR <programme> ENTR: start P63, or end the running programme (00). A running programme is always ended
      // first, so asking for P63 again restarts it.
      IF ks["PROG_REQ"] >= 0 {
        LOCAL req IS ks["PROG_REQ"].
        SET ks["PROG_REQ"] TO -1.
        SET idle_prog_text TO "00".
        IF prog:ISTYPE("Lexicon") { end_programme(prog). SET prog TO FALSE. PRINT "Programme ended.". }
        IF req = 63 {
          IF KUNIVERSE:TIMEWARP:RATE > 1 { KUNIVERSE:TIMEWARP:CANCELWARP(). }
          SET land_vec TO land_vector(site_lat, site_lng, site_alt).
          LOCAL started IS p63_start(plan_read(PLAN_PLAN_FILE), site_lat, site_lng, land_vec, wm_vec).
          IF started["REFUSED"] <> "" {
            PRINT "P63 refused: " + started["REFUSED"] + ".".
            SET ks["OPRERR"] TO TRUE.
          } ELSE {
            SET prog TO started.
            PRINT "P63 started. Ignition in " + ROUND(started["TIG"] - state["T"]) + " s.".
          }
        }
      }
      // The programme's step: it reads and clears PRO, steers, and says what to display. Without a programme PRO
      // is not used and is cleared (as in milestones 1 and 2).
      LOCAL flags IS flags_from_keys(ks, FALSE).
      SET flags["KEYREL"] TO FALSE.
      SET flags["ALT"] TO FALSE.
      SET flags["VEL"] TO FALSE.
      SET flags["BLANK"] TO FALSE.
      SET flags["FLASH"] TO FALSE.
      LOCAL prog_text IS idle_prog_text.
      SET flags["CONTACT"] TO idle_prog_text = "68".         // the CONTACT lamp stays lit after the landing until the next V37
      IF prog:ISTYPE("Lexicon") {
        LOCAL prog_out IS FALSE.
        IF prog["PROG_NO"] >= 65 { SET prog_out TO p65_step(prog, state, derived, ks). }
        ELSE IF prog["PROG_NO"] = 64 { SET prog_out TO p64_step(prog, state, derived, ks). }
        ELSE { SET prog_out TO p63_step(prog, state, derived, ks). }
        IF prog_out["SET_VERB"] >= 0 {
          SET ks["VERB"] TO prog_out["SET_VERB"].
          SET ks["NOUN"] TO prog_out["SET_NOUN"].
        }
        FOR extra_key IN prog_out["EXTRA"]:KEYS { SET derived[extra_key] TO prog_out["EXTRA"][extra_key]. }
        IF prog_out["MSG"] <> "" { PRINT prog_out["MSG"]. }
        SET flags["KEYREL"] TO prog_out["KEY_REL"].
        SET flags["ALT"] TO prog_out["ALT_LAMP"].
        SET flags["VEL"] TO prog_out["VEL_LAMP"].
        IF prog_out:HASKEY("CONTACT") { SET flags["CONTACT"] TO prog_out["CONTACT"]. }
        SET flags["PROG"] TO prog_out["ALARM"] > 0.         // alarm 1406 lights the PROG lamp
        SET flags["BLANK"] TO prog_out["BLANK"].
        SET flags["FLASH"] TO prog_out["FLASH"].
        SET prog_text TO "" + prog_out["PROG_NO"].
        IF prog_out["ENDED"] {
          end_programme(prog).
          SET prog TO FALSE.
          IF prog_out["PROG_NO"] = 68 { SET idle_prog_text TO "68". }
          PRINT "P" + prog_out["PROG_NO"] + " ended. The controls are yours.".
        }
        // Braking is over: P63 hands its state to P64 (the engine, attitude mode and radar carry on; P64 shows V06 N64).
        // The approach is over: P64 hands its state to P65 (V06 N60).
        ELSE IF prog_out["HANDOVER"] {
          IF prog["PROG_NO"] = 64 {
            SET prog TO p65_start(prog).
            PRINT "P65 started: automatic landing. SAS on, or a Shift or Ctrl tap, takes over the rate of descent (P66).".
          } ELSE {
            SET prog TO p64_start(prog, site_lat, site_lng, site_alt).
            PRINT "P64 started. Time to go " + ROUND(prog["TGO"]) + " s. Press PRO to allow redesignation (pitch and yaw keys then move the aim point).".
          }
        }
      } ELSE {
        SET ks["PRO"] TO FALSE.
      }
      gui_update(ui, derived, prog_text, ks["VERB"], ks["NOUN"], flags).
      IF LM_LOG { check_log(log_path, state["T"], derived, check_update(derived, site_lat, site_lng, site_alt)). }
      // V34 ENTR: terminate.
      IF ks["VERB"] = 34 { SET running TO FALSE. }
      // Fixed-rate loop: wait until the next CYCLE_S slot. If the clock ran ahead (time warp), start
      // from now instead of "catching up" with a burst of back-to-back cycles (seen in the first flight log).
      SET next_t TO MAX(next_t + CYCLE_S, TIME:SECONDS).
      // While P64 runs the pitch and yaw keys are read every 0.02 s instead of once a cycle, so a key tap shorter than one
      // cycle is still counted as a redesignation click (lm_p64.ks); in P65 and P66 the throttle lever is read the same way for the
      // ROD clicks (lm_p65.ks). The checks are nested because AND does not skip the right side.
      LOCAL sampling IS 0.
      IF prog:ISTYPE("Lexicon") { IF prog["PROG_NO"] = 64 { SET sampling TO 64. } ELSE IF prog["PROG_NO"] >= 65 { SET sampling TO 65. } }
      IF sampling > 0 {
        UNTIL TIME:SECONDS >= next_t { IF sampling = 64 { p64_sample(prog). } ELSE { p65_sample(prog). } WAIT 0.02. }
      } ELSE {
        WAIT MAX(0.01, next_t - TIME:SECONDS).
      }
    }
  }
  // A programme still running (V34, or the ship left the Moon's sphere of influence): give the controls back.
  IF prog:ISTYPE("Lexicon") { end_programme(prog). }
  SET site_pin:SHOW TO FALSE.
  gui_close(ui).
  PRINT "LM computer ended.".
}
