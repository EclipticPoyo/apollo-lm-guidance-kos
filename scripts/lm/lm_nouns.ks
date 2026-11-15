// lm_nouns.ks -- the LM's noun table: which nouns, verbs and V37 programmes the LM DSKY accepts, and what each noun
// shows. The register contents follow the noun table in PINBALL_NOUN_TABLES.agc (spec section 7).
// Needs the DSKY core's formatting (dsky_display.ks: fmt_reg, fmt_minsec, NA) and the unit helpers in lm_constants.ks.

RUNONCEPATH("0:/lm/lm_cells.ks").          // the store's cells and conversions (N33 and N81 read it)

GLOBAL LM_NOUNS IS LIST(60, 61, 62, 63, 64, 68, 33, 81).   // N60 first: it is the noun shown at start (keys_new uses the first)
GLOBAL LM_VERBS IS LIST(6, 16, 21, 22, 23, 24, 25, 33, 34, 37, 71, 72).   // 06 display, 16 monitor (both just show the noun here), 21 to 25 keyed loads (dsky_load.ks), 33 proceed (verifies a P27 update), 71 and 72 the update programme P27 (dsky_p27.ks; V70 and V73 are not implemented), 34 terminate (as Luminary VBTERM, it answers a request only: it abandons an active load or update, and ends P63 at its V99 enable prompt; anywhere else it does nothing; the DSKY itself ends from the window's X), 37 change programme
// The nouns the keyed loaders can load (V21 to V25): N33 time of ignition (hours, minutes, seconds in hundredths) and N81 delta-v
// in local vertical axes (tenths of ft/s). Both are five digits per register. The DSKY core reads this through the vehicle's "LOADS".
GLOBAL LM_LOADS IS LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "81", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))).
GLOBAL LM_PROGS IS LIST(0, 63).           // programmes V37 can select: P00 (none) and P63. P64 is reached only by the handover from P63, P65 by the handover from P64 and P66 from P65 (V37 ENTR 64, 65 or 66 lights OPR ERR)

// noun_registers_store: N33 (time of ignition: hours, minutes, seconds in hundredths) and N81 (delta-v in local vertical
// axes, tenths of ft/s) from the erasable store (LM_VEH["STORE"]); zeros when the store does not exist or the cell is not loaded.
FUNCTION noun_registers_store {
  PARAMETER noun_no.
  LOCAL vault IS FALSE.
  IF DEFINED LM_VEH { IF LM_VEH:HASKEY("STORE") { SET vault TO LM_VEH["STORE"]. } }
  IF noun_no = 33 {
    LOCAL parts IS LIST(0, 0, 0).
    IF vault:ISTYPE("Lexicon") {
      LOCAL tig_s IS lm_store_get_tig(vault).
      IF tig_s >= 0 { SET parts TO lm_hms_cs(tig_s). }
    }
    RETURN LIST(fmt_reg(parts[0], 0), fmt_reg(parts[1], 0), fmt_reg(parts[2], 0)).
  }
  LOCAL dv IS V(0, 0, 0).
  IF vault:ISTYPE("Lexicon") { SET dv TO lm_store_get_dv(vault). }
  RETURN LIST(fmt_reg(ms_to_fps(dv:X), 1), fmt_reg(ms_to_fps(dv:Y), 1), fmt_reg(ms_to_fps(dv:Z), 1)).
}

// noun_registers: the three register texts for a noun, from the derived lexicon (nav_derived).
// An empty list means "no such noun" and the caller lights OPR ERR.
//   N60 VHORIZ ft/s, HDOT ft/s, HCALC ft
//   N61 TTFDISP (time to go in braking, +mm ss), TTOGO (time to ignition, +mm ss counting down), OUTOFPLN (nautical miles)
//   N62 ABVEL ft/s, TTOGO (as N61), DVTOTAL ft/s (delta-v gained since ignition)
//   TTOGO departs from Luminary's sign on purpose (user's choice): Luminary has TTOGO = TIME2 - TIG, negative until
//   ignition; here it is TIG - now, shown + before ignition and counting down through zero (then -mm ss after TIG).
//   N63 ABVEL ft/s, HDOT ft/s, HCALC ft   (HCALC1 in Luminary is HCALC plus a pad term; plain HCALC here)
//   N64 FUNNYDSP shown as two integers (TREDES seconds, LOOKANGL deg: 2INTOUT), HDOT, HCALC
//   N68 RANGEDSP nautical miles, guidance, DELTAH ft
// The P63 quantities (TTFDISP, TTOGO, OUTOFPLN, DVTOTAL) are extra keys the P63 programme adds to the derived lexicon
// (lm_p63.ks); without them those registers show zeros (the stored value, see noun_registers). TTFDISP, TTOGO and DVTOTAL follow
// PINBALL_NOUN_TABLES.agc lines 717-722 (nouns 61 and 62).
FUNCTION noun_registers {
  PARAMETER noun_no, derived.
  IF NOT LM_NOUNS:CONTAINS(noun_no) { RETURN LIST(). }
  // N33 and N81 show what the store holds (zeros when nothing is loaded), whatever the navigation state.
  IF noun_no = 33 OR noun_no = 81 { RETURN noun_registers_store(noun_no). }
  IF NOT derived["VALID"] { RETURN LIST(NA, NA, NA). }
  LOCAL vhoriz IS fmt_reg(ms_to_fps(derived["VHORIZ"]), 1).
  LOCAL abvel IS fmt_reg(ms_to_fps(derived["ABVEL"]), 1).
  LOCAL hdot IS fmt_reg(ms_to_fps(derived["HDOT"]), 1).
  LOCAL hcalc IS fmt_reg(m_to_ft(derived["HCALC"]), 0).
  // A noun always displays the stored value of its erasable: Luminary has no "no data" case for a register that is driven by a
  // noun, and nothing writes these before the guidance runs, so they show zero until P63 (or P64) supplies them. A blank
  // register (NA) is only for a DSKY with no navigation state at all.
  LOCAL ttfdisp IS fmt_minsec(0).
  LOCAL ttogo IS fmt_minsec(0).
  LOCAL outofpln IS fmt_reg(0, 1).
  LOCAL dvtotal IS fmt_reg(0, 1).
  // TTFDISP is written only by TDISPSET, in the guidance pass of the burn (LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 1384-1387).
  IF derived:HASKEY("TTFDISP") { SET ttfdisp TO fmt_minsec(derived["TTFDISP"]). }
  IF derived:HASKEY("TTOGO") { SET ttogo TO fmt_minsec(derived["TTOGO"]). }
  IF derived:HASKEY("OUTOFPLN") { SET outofpln TO fmt_reg(m_to_nm(derived["OUTOFPLN"]), 1). }
  IF derived:HASKEY("DVTOTAL") { SET dvtotal TO fmt_reg(ms_to_fps(derived["DVTOTAL"]), 1). }
  IF noun_no = 60 { RETURN LIST(vhoriz, hdot, hcalc). }
  IF noun_no = 61 { RETURN LIST(ttfdisp, ttogo, outofpln). }
  IF noun_no = 62 { RETURN LIST(abvel, ttogo, dvtotal). }
  IF noun_no = 63 { RETURN LIST(abvel, hdot, hcalc). }
  IF noun_no = 64 {
    // N64 R1 is FUNNYDSP, shown by 2INTOUT: TREDES (seconds left to redesignate) and LOOKANGL (degrees), two digits each.
    LOCAL funny IS fmt_2int(0, derived["LOOKANGL"]).      // TREDES stored as zero until P64 runs
    IF derived:HASKEY("TREDES") { SET funny TO fmt_2int(derived["TREDES"], derived["LOOKANGL"]). }
    RETURN LIST(funny, hdot, hcalc).
  }
  // noun 68
  RETURN LIST(fmt_reg(m_to_nm(derived["RANGEDSP"]), 1), ttfdisp, fmt_reg(m_to_ft(derived["DELTAH"]), 0)).
}

