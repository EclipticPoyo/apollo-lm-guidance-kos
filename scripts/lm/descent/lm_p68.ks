// lm_p68.ks -- P68, landing confirmation (release 1.3.1). Luminary 099 THE_LUNAR_LANDING 277-336, 210 280-345 (Task 0 reading).
//   p68_enter(prog, geo_lat, geo_lng, alt_m)   fills the programme state with the true landing position
//   p68_step(prog, ks)                          one cycle; returns the programme output keys the DSKY core reads
//   p68_end(prog)                               gives the controls back (when the programme took over a burn's state)
//
// What P68 does in Luminary: after the engine is off and the LM is down it computes latitude, longitude and altitude, stores the position
// as RLS, and shows flashing V06 N43 (the position). The pilot answers: PRO (V33) or V34 ends it (to P00; the "please select P57"
// is only a comment in the source), V32 or ENTER shows N43 again.
// Departures: the position comes from the ship (SHIP:GEOPOSITION), not from the navigation state vector; P57 does not exist here.
// No kOS reads in this file (the vehicle, lm_vehicle.ks, reads the ship and calls p68_enter), so the pad test can run it.

// p68_enter: make prog the P68 state. prog is P65's or J's P66 lexicon on a handover (its keys stay: the controls are given back by
// the END), or a new LEXICON when the pilot selects P68 with V37 once down. alt_m is the height above the body's radius.
FUNCTION p68_enter {
  PARAMETER prog, geo_lat, geo_lng, alt_m.
  SET prog["PROG_NO"] TO 68.
  SET prog["MODE"] TO "P68".
  SET prog["REFUSED"] TO "".
  SET prog["ENDED"] TO FALSE.
  SET prog["P68"] TO LEXICON("SHOWN", FALSE, "LAT", geo_lat, "LNG", geo_lng, "ALT", alt_m).
  RETURN prog.
}

// p68_step: stays on the flashing V06 N43 request until the pilot answers. PRO or V34 end the programme; V32 shows N43 again (the source also repeats it on ENTER; not here, see the code).
// The same output keys as the other steps; CONTACT stays lit.
FUNCTION p68_step {
  PARAMETER prog, ks.
  LOCAL state68 IS prog["P68"].
  LOCAL pro_pressed IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  LOCAL ending IS pro_pressed OR ks["TERMINATE"].
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT ending AND (NOT state68["SHOWN"] OR ks["RECYCLE"]) {       // V32 only: an ENTR from keying another verb would wipe the entry (as in P63's N61)
    SET state68["SHOWN"] TO TRUE.
    SET set_verb TO 6.
    SET set_noun TO 43.
  }
  IF ending { SET prog["ENDED"] TO TRUE. }
  LOCAL request IS FALSE.
  IF NOT ending { SET request TO LEXICON("VERB", 6, "NOUN", 43). }
  LOCAL extra IS LEXICON("P68_LAT", state68["LAT"], "P68_LNG", state68["LNG"], "P68_ALT", state68["ALT"]).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", request,
                 "ALARM", 0, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE, "EXTRA", extra, "MSG", "", "WARN", "", "ENDED", prog["ENDED"], "HANDOVER", FALSE,
                 "PROG_NO", 68, "CONTACT", TRUE, "STATUS", LIST()).
}
