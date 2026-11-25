// lm_nouns.ks -- the LM's noun table: which nouns, verbs and V37 programmes the LM DSKY accepts, and what each noun
// shows. The register contents follow the noun table in PINBALL_NOUN_TABLES.agc (spec section 7).
// Needs the DSKY core's formatting (dsky_display.ks: fmt_reg, fmt_minsec, NA) and the unit helpers in lm_constants.ks.

RUNONCEPATH("0:/core/dsky_alarm.ks").         // alarm_text (N09)
RUNONCEPATH("0:/lm/lm_cells.ks").          // the store's cells and conversions (N33 and N81 read it)

GLOBAL LM_NOUNS IS LIST(60, 61, 62, 63, 64, 68, 33, 81, 9, 66, 67, 43, 92, 69, 18, 25, 42, 45, 40, 85, 83).   // N60 first: it is the noun shown at start (keys_new uses the first)
GLOBAL LM_VERBS IS LIST(5, 6, 16, 21, 22, 23, 24, 25, 32, 33, 34, 35, 57, 58, 77, 37, 71, 72).   // 06 display, 16 monitor (both just show the noun here), 21 to 25 keyed loads (dsky_load.ks), 33 proceed (verifies a P27 update), 71 and 72 the update programme P27 (dsky_p27.ks; V70 and V73 are not implemented), 34 terminate (as Luminary VBTERM, it answers a request only: it abandons an active load or update, and ends P63 at its V99 enable prompt; anywhere else it does nothing; the DSKY itself ends from the window's X), 37 change programme
// The nouns the keyed loaders can load (V21 to V25): N33 time of ignition (hours, minutes, seconds in hundredths) and N81 delta-v
// in local vertical axes (tenths of ft/s). Both are five digits per register. The DSKY core reads this through the vehicle's "LOADS".
GLOBAL LM_LOADS IS LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "81", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "69", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))).
GLOBAL LM_PROGS IS LIST(0, 30, 40, 41, 47, 51, 63, 68).        // programmes V37 can select: P00 (none), P63 and P68 (only once down). P64 is reached only by the handover from P63, P65 by the handover from P64 and P66 from P65 (V37 ENTR 64, 65 or 66 lights OPR ERR)

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
  // N69 (Luminary 210): the landing site correction in whole feet: R1 downrange (DLANDZ), R2 crossrange (DLANDY), R3 up (DLANDX). Zeros in the 099 profile.
  IF noun_no = 69 {
    LOCAL corr IS V(0, 0, 0).
    IF vault:ISTYPE("Lexicon") { SET corr TO lm_store_get_dland(vault). }
    RETURN LIST(fmt_reg(m_to_ft(corr:Z), 0), fmt_reg(m_to_ft(corr:Y), 0), fmt_reg(m_to_ft(corr:X), 0)).
  }
  LOCAL dv IS V(0, 0, 0).
  IF vault:ISTYPE("Lexicon") { SET dv TO lm_store_get_dv(vault). }
  RETURN LIST(fmt_reg(ms_to_fps(dv:X), 1), fmt_reg(ms_to_fps(dv:Y), 1), fmt_reg(ms_to_fps(dv:Z), 1)).
}

// N18 (release 1.4, R60): the roll, pitch and yaw angles of the commanded burn attitude, degrees to 0.01 (derived["N18"], from R60 through the programme's EXTRA;
// zeros outside it). N25 (a checklist code, whole octal number: P51's 00051, P40AUTO's 00203): R1 (derived["N25"], else zero), the sign cell blank as N09's;
// R2 and R3 blank.
FUNCTION noun_registers_r60 {
  PARAMETER noun_no, derived.
  IF noun_no = 25 {
    LOCAL code_no IS 0.
    IF derived:HASKEY("N25") { SET code_no TO derived["N25"]. }
    RETURN LIST(" " + zero_pad(ROUND(code_no), 5), NA, NA).
  }
  LOCAL angles IS LIST(0, 0, 0).
  IF derived:HASKEY("N18") { SET angles TO derived["N18"]. }
  RETURN LIST(fmt_reg(angles[0], 2), fmt_reg(angles[1], 2), fmt_reg(angles[2], 2)).
}

// N42 and N45 (release 1.4, P30; Luminary P30_P37.agc, P34-35_P74-75.agc): from P30's EXTRA keys (derived["P30_APO"] and so on), zeros outside P30.
//   N42 R1 apogee altitude, R2 perigee altitude (nautical miles, 0.1), R3 delta-V magnitude (ft/s, 0.1)
//   N45 R1 marks (whole number: always 0, no marks exist here), R2 time to go to ignition (MM SS), R3 middle gimbal angle (degrees, 0.01)
FUNCTION noun_registers_p30 {
  PARAMETER noun_no, derived.
  LOCAL apo_m IS 0.
  LOCAL peri_m IS 0.
  LOCAL dv_ms IS 0.
  LOCAL ttogo_s IS 0.
  LOCAL mga_deg IS 0.
  IF derived:HASKEY("P30_APO") {
    SET apo_m TO derived["P30_APO"].
    SET peri_m TO derived["P30_PERI"].
    SET dv_ms TO derived["P30_DV"].
    SET ttogo_s TO derived["P30_TTOGO"].
    SET mga_deg TO derived["P30_MGA"].
  }
  IF noun_no = 42 { RETURN LIST(fmt_reg(m_to_nm(apo_m), 1), fmt_reg(m_to_nm(peri_m), 1), fmt_reg(ms_to_fps(dv_ms), 1)). }
  RETURN LIST(fmt_reg(0, 0), fmt_minsec(ttogo_s), fmt_reg(mga_deg, 2)).
}

// N40 and N85 (release 1.4, P40; Luminary P40-P47.agc): from P40's EXTRA keys, zeros outside it.
//   N40 R1 time to go as MM SS, negative before the event (Luminary TIME2 - TIG: counts up to zero at ignition, then to cutoff), R2 |VG| ft/s (0.1), R3 delta-V gained ft/s (0.1)
//   N85 R1 to R3 VG in body axes X, Y, Z, ft/s (0.1): the pilot trims these to zero by hand after the burn
FUNCTION noun_registers_p40 {
  PARAMETER noun_no, derived.
  IF noun_no = 85 OR noun_no = 83 {
    LOCAL vg_axes IS LIST(0, 0, 0).
    IF noun_no = 85 AND derived:HASKEY("P40_VGB") { SET vg_axes TO derived["P40_VGB"]. }
    IF noun_no = 83 AND derived:HASKEY("P47_DVB") { SET vg_axes TO derived["P47_DVB"]. }
    RETURN LIST(fmt_reg(ms_to_fps(vg_axes[0]), 1), fmt_reg(ms_to_fps(vg_axes[1]), 1), fmt_reg(ms_to_fps(vg_axes[2]), 1)).
  }
  LOCAL ttogo_s IS 0.
  LOCAL vg_ms IS 0.
  LOCAL dv_ms IS 0.
  IF derived:HASKEY("VGDISP") {
    SET ttogo_s TO derived["TTOGO"].
    SET vg_ms TO derived["VGDISP"].
    SET dv_ms TO derived["DVTOTAL"].
  }
  RETURN LIST(fmt_minsec(-ttogo_s), fmt_reg(ms_to_fps(vg_ms), 1), fmt_reg(ms_to_fps(dv_ms), 1)).
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
  IF noun_no = 33 OR noun_no = 81 OR noun_no = 69 { RETURN noun_registers_store(noun_no). }
  // N09: the three alarm slots (FAILREG), octal digits, five each, the sign cell blank (as P27's R1). Shows zeros before any alarm.
  IF noun_no = 99 { RETURN LIST(NA, NA, NA). }          // V37 N99: the flashing "select a programme" request after a programme ends, no data
  IF noun_no = 9 {
    LOCAL slots IS LIST(0, 0, 0).
    IF derived:HASKEY("ALARM_CODES") { SET slots TO derived["ALARM_CODES"]. }
    RETURN LIST(" " + alarm_text(slots[0]), " " + alarm_text(slots[1]), " " + alarm_text(slots[2])).
  }
  IF noun_no = 18 OR noun_no = 25 { RETURN noun_registers_r60(noun_no, derived). }
  IF noun_no = 42 OR noun_no = 45 { RETURN noun_registers_p30(noun_no, derived). }
  IF noun_no = 40 OR noun_no = 85 OR noun_no = 83 { RETURN noun_registers_p40(noun_no, derived). }
  // N43: latitude and longitude in degrees (0.01) and altitude in nautical miles (0.1), the landing position P68 stores. Zeros outside P68.
  IF noun_no = 43 {
    IF derived:HASKEY("P68_LAT") { RETURN LIST(fmt_reg(derived["P68_LAT"], 2), fmt_reg(derived["P68_LNG"], 2), fmt_reg(m_to_nm(derived["P68_ALT"]), 1)). }
    RETURN LIST(fmt_reg(0, 2), fmt_reg(0, 2), fmt_reg(0, 1)).
  }
  IF NOT derived["VALID"] { RETURN LIST(NA, NA, NA). }
  // N92 (Luminary 210): R1 the wanted thrust in whole percent of the rated 10,500 lbf (THR_PCT, from the J programmes), R2 HDOT ft/s, R3 HCALC ft.
  IF noun_no = 92 {
    LOCAL pct IS 0.
    IF derived:HASKEY("THR_PCT") { SET pct TO derived["THR_PCT"]. }
    RETURN LIST(fmt_reg(pct, 0), fmt_reg(ms_to_fps(derived["HDOT"]), 1), fmt_reg(m_to_ft(derived["HCALC"]), 0)).
  }
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
  // N66 (landing radar range: R1 altitude in whole feet, R2 the antenna position, no R3) and N67 (the radar's velocity along the LM axes, whole ft/s):
  // zeros until the radar has data (below RADAR_ALT_MAX_M).
  IF noun_no = 66 {
    IF derived:HASKEY("RADAR_ALT_M") { RETURN LIST(fmt_reg(m_to_ft(derived["RADAR_ALT_M"]), 0), fmt_reg(derived["RADAR_ANT"], 0), NA). }
    RETURN LIST(fmt_reg(0, 0), fmt_reg(0, 0), NA).
  }
  IF noun_no = 67 {
    IF derived:HASKEY("RADAR_VEL") {
      LOCAL rv IS derived["RADAR_VEL"].
      RETURN LIST(fmt_reg(ms_to_fps(rv[0]), 0), fmt_reg(ms_to_fps(rv[1]), 0), fmt_reg(ms_to_fps(rv[2]), 0)).
    }
    RETURN LIST(fmt_reg(0, 0), fmt_reg(0, 0), fmt_reg(0, 0)).
  }
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

