// lm_nouns.ks -- the LM's noun table: which nouns, verbs and V37 programmes the LM DSKY accepts, and what each noun
// shows. The register contents follow the noun table in PINBALL_NOUN_TABLES.agc (spec section 7).
// Needs the DSKY core's formatting (dsky_display.ks: fmt_reg, fmt_minsec, NA) and the unit helpers in lm_constants.ks.

RUNONCEPATH("0:/core/dsky_alarm.ks").         // alarm_text (N09)
RUNONCEPATH("0:/lm/lm_cells.ks").          // the store's cells and conversions (N33 and N81 read it)

GLOBAL LM_NOUNS IS LIST(60, 61, 62, 63, 64, 68, 33, 81, 9, 66, 67, 43, 92, 69, 18, 25, 42, 45, 40, 85, 83, 76, 74, 94, 44, 11, 13, 37, 55, 75, 82, 52, 58, 59, 12, 16, 54, 90).   // N60 first: it is the noun shown at start (keys_new uses the first)
GLOBAL LM_VERBS IS LIST(83, 89, 90, 56, 93, 4, 76, 80, 81, 95, 5, 6, 16, 21, 22, 23, 24, 25, 32, 33, 34, 35, 57, 58, 77, 82, 37, 71, 72).   // 04 and 06 display, 16 monitor (all just show the noun here), 76, 80, 81 and 95 are accepted and do nothing (no steerable antenna, one state vector, no W matrix), 56 ends tracking (P20, P25), 93 restarts the mark count, 83, 89 and 90 the rendezvous routines (lm_rverbs.ks), 21 to 25 keyed loads (dsky_load.ks), 33 proceed (verifies a P27 update), 71 and 72 the update programme P27 (dsky_p27.ks; V70 and V73 are not implemented), 34 terminate (as Luminary VBTERM, it answers a request only: it abandons an active load or update, and ends P63 at its V99 enable prompt; anywhere else it does nothing; the DSKY itself ends from the window's X), 37 change programme
// The nouns the keyed loaders can load (V21 to V25): N33 time of ignition (hours, minutes, seconds in hundredths) and N81 delta-v
// in local vertical axes (tenths of ft/s), N69 the landing-site correction and N76 the ascent targets (release 1.5: horizontal and radial speed in
// tenths of ft/s, cross-range in tenths of nm), the times N11 (CSI), N13 (CDH) and N37 (TPI) as N33, and N55 (NN, elevation and central
// angle in hundredths of a degree), N12 (two octal registers: V89's option) and N16 (V90's time, as N33; neither is in the store). All are
// five digits per register. The DSKY core reads this through the vehicle's "LOADS".
GLOBAL LM_LOADS IS LEXICON("33", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "81", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "69", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "76", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)),
    "11", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "13", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "37", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)), "55", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5)),
    "12", LEXICON("NCOMP", 2, "DIGITS", LIST(5, 5), "OCTAL", TRUE), "16", LEXICON("NCOMP", 3, "DIGITS", LIST(5, 5, 5))).
// The nouns that show a time as hours, minutes and seconds in hundredths, and the store cell each one reads and loads.
GLOBAL LM_TIME_NOUNS IS LEXICON("11", "TCSI", "13", "TCDH", "33", "TIG", "37", "TTPI").
GLOBAL LM_PROGS IS LIST(0, 12, 20, 25, 30, 32, 33, 34, 35, 40, 41, 42, 47, 51, 63, 68, 70, 71).    // programmes V37 can select: P00 (none), P12 and P68 (only once down), P63, the aborts P70 and P71 (while armed). P64 is reached only by the handover from P63, P65 by the handover from P64 and P66 from P65 (V37 ENTR 64, 65 or 66 lights OPR ERR)

// noun_registers_store: the times N11, N13, N33 and N37 (hours, minutes, seconds in hundredths), N55 (NN, elevation and central
// angle), N81 and N82 (delta-v in local vertical axes, tenths of ft/s), N69 and N76 from the erasable store (LM_VEH["STORE"]); zeros
// when the store does not exist or the cell is not loaded.
FUNCTION noun_registers_store {
  PARAMETER noun_no.
  LOCAL vault IS FALSE.
  IF DEFINED LM_VEH { IF LM_VEH:HASKEY("STORE") { SET vault TO LM_VEH["STORE"]. } }
  IF LM_TIME_NOUNS:HASKEY("" + noun_no) {
    LOCAL parts IS LIST(0, 0, 0).
    IF vault:ISTYPE("Lexicon") {
      LOCAL time_s IS lm_store_get_time(vault, LM_TIME_NOUNS["" + noun_no]).
      IF time_s >= 0 { SET parts TO lm_hms_cs(time_s). }
    }
    RETURN LIST(fmt_reg(parts[0], 0), fmt_reg(parts[1], 0), fmt_reg(parts[2], 0)).
  }
  // N55: R1 NN (whole number), R2 TPI elevation angle, R3 central angle (degrees, 0.01).
  IF noun_no = 55 {
    LOCAL n55 IS LEXICON("NN", -1, "ELEV", -1, "CENTANG", -1).
    IF vault:ISTYPE("Lexicon") { SET n55 TO lm_store_get_n55(vault). }
    RETURN LIST(fmt_reg(MAX(0, n55["NN"]), 0), fmt_reg(MAX(0, n55["ELEV"]), 2), fmt_reg(MAX(0, n55["CENTANG"]), 2)).
  }
  // N76 (release 1.5): the ascent targets: R1 horizontal speed wanted and R2 radial speed wanted (ft/s, 0.1), R3 cross-range (nm, 0.1).
  IF noun_no = 76 {
    LOCAL asc IS LEXICON("ZDOTD", 0, "RDOTD", 0, "XRANGE", 0).
    IF vault:ISTYPE("Lexicon") { SET asc TO lm_store_get_asc(vault). }
    RETURN LIST(fmt_reg(ms_to_fps(asc["ZDOTD"]), 1), fmt_reg(ms_to_fps(asc["RDOTD"]), 1), fmt_reg(m_to_nm(asc["XRANGE"]), 1)).
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
//   N45 R1 marks (whole number, derived["MARKS"], P20's count; 0 without it), R2 time to go to ignition (MM SS), R3 middle gimbal angle (degrees, 0.01).
//       N45 needs only P30_TTOGO and P30_MGA (P32 and P33 supply them without the orbit values).
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
  }
  IF derived:HASKEY("P30_TTOGO") { SET ttogo_s TO derived["P30_TTOGO"]. }
  IF derived:HASKEY("P30_MGA") { SET mga_deg TO derived["P30_MGA"]. }
  IF noun_no = 42 { RETURN LIST(fmt_reg(m_to_nm(apo_m), 1), fmt_reg(m_to_nm(peri_m), 1), fmt_reg(ms_to_fps(dv_ms), 1)). }
  LOCAL marks IS 0.
  IF derived:HASKEY("MARKS") { SET marks TO derived["MARKS"]. }
  RETURN LIST(fmt_reg(marks, 0), fmt_minsec(ttogo_s), fmt_reg(mga_deg, 2)).
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

// N74 and N44 (release 1.5), from the programme's or V82's extra keys, zeros outside them.
//   N74 R1 time from ignition (MM SS, negative before, as N40), R2 yaw and R3 pitch after the vertical rise (degrees, 0.01, 0 to 359.99)
//   N44 R1 apolune and R2 perilune altitude above the landing-site radius (nm, 0.1), R3 time of free fall (MM SS, shown negative as a time still to
//       run; -59 59 when it cannot be computed). derived["N44"] is LIST(apolune m, perilune m, seconds or -1) (lm_v82_values).
FUNCTION noun_registers_ascent {
  PARAMETER noun_no, derived.
  IF noun_no = 74 {
    LOCAL ttogo_s IS 0.
    LOCAL yaw_deg IS 0.
    LOCAL pitch_deg IS 0.
    IF derived:HASKEY("P12_YAW") {
      SET ttogo_s TO derived["TTOGO"].
      SET yaw_deg TO derived["P12_YAW"].
      SET pitch_deg TO derived["P12_PITCH"].
    }
    RETURN LIST(fmt_minsec(-ttogo_s), fmt_reg(yaw_deg, 2), fmt_reg(pitch_deg, 2)).
  }
  IF NOT derived:HASKEY("N44") { RETURN LIST(fmt_reg(0, 1), fmt_reg(0, 1), fmt_minsec(0)). }
  LOCAL n44_vals IS derived["N44"].
  LOCAL tff_s IS n44_vals[2].
  IF tff_s < 0 { SET tff_s TO 59 * 60 + 59. }
  RETURN LIST(fmt_reg(m_to_nm(n44_vals[0]), 1), fmt_reg(m_to_nm(n44_vals[1]), 1), fmt_minsec(-tff_s)).
}

// N75 (release 1.5, P32 and P33), from the programme's extra keys, zeros without them: R1 height difference at CDH (nm, 0.1,
// + = the CSM is higher), R2 and R3 the times between burns (MM SS): RN_T12 and RN_T23 (seconds).
FUNCTION noun_registers_rndz {
  PARAMETER derived.
  LOCAL dh_m IS 0.
  LOCAL t12_s IS 0.
  LOCAL t23_s IS 0.
  IF derived:HASKEY("RN_DH") { SET dh_m TO derived["RN_DH"]. }
  IF derived:HASKEY("RN_T12") { SET t12_s TO derived["RN_T12"]. }
  IF derived:HASKEY("RN_T23") { SET t23_s TO derived["RN_T23"]. }
  RETURN LIST(fmt_reg(m_to_nm(dh_m), 1), fmt_minsec(t12_s), fmt_minsec(t23_s)).
}

// N52, N58 and N59 (release 1.5, P34 and P35), from the programme's extra keys, zeros without them.
//   N52 R1 the LM's central angle of the transfer (RN_CENT, degrees, 0.01); R2 and R3 blank
//   N58 R1 perilune altitude after TPI (RN_PERI, m; nm 0.1), R2 delta-V at TPI and R3 at the intercept (RN_DVTPI, RN_DVTPF; ft/s 0.1)
//   N59 the delta-V along the line of sight, right of it and down (RN_DVLOS, m/s as V(along, right, down); ft/s 0.1)
FUNCTION noun_registers_tpi {
  PARAMETER noun_no, derived.
  IF noun_no = 52 {
    LOCAL angle IS 0.
    IF derived:HASKEY("RN_CENT") { SET angle TO derived["RN_CENT"]. }
    RETURN LIST(fmt_reg(angle, 2), NA, NA).
  }
  IF noun_no = 58 {
    LOCAL peri_m IS 0.
    LOCAL tpi_ms IS 0.
    LOCAL tpf_ms IS 0.
    IF derived:HASKEY("RN_PERI") { SET peri_m TO derived["RN_PERI"]. }
    IF derived:HASKEY("RN_DVTPI") { SET tpi_ms TO derived["RN_DVTPI"]. }
    IF derived:HASKEY("RN_DVTPF") { SET tpf_ms TO derived["RN_DVTPF"]. }
    RETURN LIST(fmt_reg(m_to_nm(peri_m), 1), fmt_reg(ms_to_fps(tpi_ms), 1), fmt_reg(ms_to_fps(tpf_ms), 1)).
  }
  LOCAL sight IS V(0, 0, 0).
  IF derived:HASKEY("RN_DVLOS") { SET sight TO derived["RN_DVLOS"]. }
  RETURN LIST(fmt_reg(ms_to_fps(sight:X), 1), fmt_reg(ms_to_fps(sight:Y), 1), fmt_reg(ms_to_fps(sight:Z), 1)).
}

// N12, N16, N54 and N90 (release 1.5, the rendezvous routines), from the vehicle's or an extended verb's keys, zeros without them:
//   N12 R1 a code and R2 an option, five octal digits each, the sign cell blank (derived["N12"] = LIST(code, option)); R3 blank
//   N16 a time as N11: hours, minutes, seconds in hundredths (derived["N16"], seconds)
//   N54 R1 range (nm, 0.01), R2 range rate (ft/s, 0.1), R3 theta (degrees, 0.01); derived["N54"] = LIST(m, m/s, degrees)
//   N90 R1 distance out of the CSM's plane (nm, 0.01), R2 its rate (ft/s, 0.1), R3 psi (degrees, 0.01); derived["N90"] as N54
FUNCTION noun_registers_rverbs {
  PARAMETER noun_no, derived.
  IF noun_no = 12 {
    LOCAL codes IS LIST(0, 0).
    IF derived:HASKEY("N12") { SET codes TO derived["N12"]. }
    RETURN LIST(" " + octal_text(codes[0], 5), " " + octal_text(codes[1], 5), NA).
  }
  IF noun_no = 16 {
    LOCAL parts IS LIST(0, 0, 0).
    IF derived:HASKEY("N16") { SET parts TO lm_hms_cs(derived["N16"]). }
    RETURN LIST(fmt_reg(parts[0], 0), fmt_reg(parts[1], 0), fmt_reg(parts[2], 0)).
  }
  LOCAL values IS LIST(0, 0, 0).
  IF derived:HASKEY("N" + noun_no) { SET values TO derived["N" + noun_no]. }
  RETURN LIST(fmt_reg(m_to_nm(values[0]), 2), fmt_reg(ms_to_fps(values[1]), 1), fmt_reg(values[2], 2)).
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
  // The times, N55, N81, N82, N69 and N76 show what the store holds (zeros when nothing is loaded), whatever the navigation state.
  IF LM_TIME_NOUNS:HASKEY("" + noun_no) OR noun_no = 55 OR noun_no = 81 OR noun_no = 82 OR noun_no = 69 OR noun_no = 76 {
    RETURN noun_registers_store(noun_no).
  }
  IF noun_no = 75 { RETURN noun_registers_rndz(derived). }
  IF noun_no = 12 OR noun_no = 16 OR noun_no = 54 OR noun_no = 90 { RETURN noun_registers_rverbs(noun_no, derived). }
  IF noun_no = 52 OR noun_no = 58 OR noun_no = 59 { RETURN noun_registers_tpi(noun_no, derived). }
  IF noun_no = 74 OR noun_no = 44 { RETURN noun_registers_ascent(noun_no, derived). }
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
  // N94 (Luminary 210, release 1.5, the J ascent): R1 the velocity to be gained along body X, R2 altitude rate (ft/s, 0.1), R3 altitude (ft).
  IF noun_no = 94 {
    LOCAL vg_x IS 0.
    IF derived:HASKEY("P40_VGB") { SET vg_x TO derived["P40_VGB"][0]. }
    RETURN LIST(fmt_reg(ms_to_fps(vg_x), 1), hdot, hcalc).
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

