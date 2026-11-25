// lm_cells.ks -- the LM's erasable cells: the table of what the DSKY's store holds, with the real Luminary erasable addresses
// and scaling, and the conversions between our units and the AGC's words. One table per software version (spec: the addresses
// differ between 099 and 210). The vehicle-independent store code is core/dsky_store.ks.
//
// A cell line: BANK is the erasable bank (E0 to E7), OFFSET the address inside the bank (octal 1400 to 1777, written here as a
// decimal number so 1422 octal is 786), WORDS the number of 15-bit words (2 = one double-precision number, 6 = a vector),
// SCALE the exponent e such that the cell's full scale is 2^e in its unit (Luminary "B-27 metres" = 27, meaning 2^27 m).
// The ECADR the uplink (V71, V72) names is bank * 256 + (OFFSET - 768), see store_ecadr in core/dsky_store.ks.
// Addresses are from the Virtual AGC listings (ibiblio.org/apollo/listings/Luminary099 and Luminary210, ERASABLE_ASSIGNMENTS);
// scales from ERASABLE_ASSIGNMENTS.agc, R30.agc (RLS B-27 m), PINBALL_NOUN_TABLES.agc (N33 time, N81 VEL3).
// Only the cells the scripts use are here. The ascent loads (release 1.5, N76) are ZDOTD and RDOTD (2^7 m/cs) and XRANGE (2^29 m, P12.agc).
// One cell per line in exactly this form: tests/reference_loads.py reads this file with a regular expression.

RUNONCEPATH("0:/core/dsky_store.ks").       // dp_encode, dp_decode, store_put_all

GLOBAL LM_CELLS_099 IS LEXICON().
LM_CELLS_099:ADD("RLS", LEXICON("BANK", 4, "OFFSET", 786, "WORDS", 6, "SCALE", 27, "LABEL", "landing site vector, Moon-fixed, metres")).
LM_CELLS_099:ADD("TLAND", LEXICON("BANK", 5, "OFFSET", 768, "WORDS", 2, "SCALE", 28, "LABEL", "nominal time of landing, centiseconds")).
LM_CELLS_099:ADD("TIG", LEXICON("BANK", 7, "OFFSET", 801, "WORDS", 2, "SCALE", 28, "LABEL", "time of ignition N33, centiseconds")).
LM_CELLS_099:ADD("DELVLVC", LEXICON("BANK", 7, "OFFSET", 795, "WORDS", 6, "SCALE", 7, "LABEL", "delta-v local vertical N81, metres per centisecond")).
LM_CELLS_099:ADD("ZDOTD", LEXICON("BANK", 4, "OFFSET", 958, "WORDS", 2, "SCALE", 7, "LABEL", "ascent horizontal speed wanted N76, metres per centisecond")).
LM_CELLS_099:ADD("RDOTD", LEXICON("BANK", 4, "OFFSET", 954, "WORDS", 2, "SCALE", 7, "LABEL", "ascent radial speed wanted N76, metres per centisecond")).
LM_CELLS_099:ADD("XRANGE", LEXICON("BANK", 7, "OFFSET", 930, "WORDS", 2, "SCALE", 29, "LABEL", "ascent cross-range N76, metres")).

GLOBAL LM_CELLS_210 IS LEXICON().
LM_CELLS_210:ADD("RLS", LEXICON("BANK", 4, "OFFSET", 784, "WORDS", 6, "SCALE", 27, "LABEL", "landing site vector, Moon-fixed, metres")).
LM_CELLS_210:ADD("TLAND", LEXICON("BANK", 4, "OFFSET", 790, "WORDS", 2, "SCALE", 28, "LABEL", "nominal time of landing, centiseconds")).
LM_CELLS_210:ADD("TIG", LEXICON("BANK", 7, "OFFSET", 801, "WORDS", 2, "SCALE", 28, "LABEL", "time of ignition N33, centiseconds")).
LM_CELLS_210:ADD("DELVLVC", LEXICON("BANK", 7, "OFFSET", 795, "WORDS", 6, "SCALE", 7, "LABEL", "delta-v local vertical N81, metres per centisecond")).
LM_CELLS_210:ADD("ZDOTD", LEXICON("BANK", 4, "OFFSET", 951, "WORDS", 2, "SCALE", 7, "LABEL", "ascent horizontal speed wanted N76, metres per centisecond")).
LM_CELLS_210:ADD("RDOTD", LEXICON("BANK", 4, "OFFSET", 947, "WORDS", 2, "SCALE", 7, "LABEL", "ascent radial speed wanted N76, metres per centisecond")).
LM_CELLS_210:ADD("XRANGE", LEXICON("BANK", 7, "OFFSET", 930, "WORDS", 2, "SCALE", 29, "LABEL", "ascent cross-range N76, metres")).
LM_CELLS_210:ADD("DLAND", LEXICON("BANK", 5, "OFFSET", 921, "WORDS", 6, "SCALE", 24, "LABEL", "landing site correction N69, guidance axes, metres (210 only)")).

// The update program's buffer addresses, which P27 shows in R3 while it asks for data (UPDATE_PROGRAM.agc: UPBUFF + the number of items
// received, UPTEMP at the verify step). ECADRs below 1400 octal are the address itself. From the yaYUL listings of
// ERASABLE_ASSIGNMENTS.agc: Luminary 099 UPBUFF 1174 octal (636), UPTEMP 1167 (631); Luminary 210 UPBUFF 1173 (635), UPTEMP 1166 (630).
GLOBAL LM_P27_ADDR_099 IS LEXICON("BUFF", 636, "TEMP", 631).
GLOBAL LM_P27_ADDR_210 IS LEXICON("BUFF", 635, "TEMP", 630).

// lm_p27_addr: LEXICON("BUFF", ..., "TEMP", ...) for a pad profile.
FUNCTION lm_p27_addr {
  PARAMETER profile.
  IF profile = "J" { RETURN LM_P27_ADDR_210. }
  RETURN LM_P27_ADDR_099.
}

// lm_cells_for: the cell table for a pad profile ("J" = Luminary 210, anything else Luminary 099).
FUNCTION lm_cells_for {
  PARAMETER profile.
  IF profile = "J" { RETURN LM_CELLS_210. }
  RETURN LM_CELLS_099.
}

// ---- unit conversions ------------------------------------------------------------------------------------------------
// Each cell holds double-precision numbers at the cell's SCALE. The vehicle works in metres, seconds and m/s; the AGC in
// metres (RLS), centiseconds (TIG, TLAND) and metres per centisecond (DELVLVC).

// The AGC clock counts centiseconds in a 28-bit double-precision word, about 31 days. Its zero here is the mission-time zero of the
// vessel the planner ran on (lm_clock_zero_now), printed on the PAD so the number keyed matches. KSP restarts MISSIONTIME when a
// vessel undocks (measured: the LM read 35 s just after the undock, against 961 s before it), so the planner saves its zero in a file,
// the clock sync the ground would have uplinked, and the DSKY reads it (lm_clock_zero_ut).
GLOBAL LM_CLOCK_LIMIT_CS IS 268435456.
GLOBAL LM_CLOCK_FILE IS "0:/lm/clock.txt".

// The software version ("A11" or "J") the planner's menu chose. The planner saves it with the PAD (the ground knows which version the LM carries) and the
// DSKY reads it when there is no plan file (uplink mode deletes the plan). Skip simulated uplink clears it: the plan carries PROFILE itself.
GLOBAL LM_PROFILE_FILE IS "0:/lm/profile.txt".

// lm_profile_save / lm_profile_clear / lm_profile_saved: the file above. lm_profile_saved gives "A11", "J", or "" when there is no good file.
FUNCTION lm_profile_clear {
  IF EXISTS(LM_PROFILE_FILE) { DELETEPATH(LM_PROFILE_FILE). }
}
FUNCTION lm_profile_save {
  PARAMETER profile.
  lm_profile_clear().
  LOG profile TO LM_PROFILE_FILE.
}
FUNCTION lm_profile_saved {
  IF NOT EXISTS(LM_PROFILE_FILE) { RETURN "". }
  LOCAL text IS OPEN(LM_PROFILE_FILE):READALL:STRING:TRIM:TOUPPER.
  IF text = "A11" OR text = "J" { RETURN text. }
  RETURN "".
}

// The erasable store is kept in this file when the DSKY ends (V34), so a restart finds the loads (RLS, TLAND, burn) still there, as the
// computer's erasable memory stayed. The planner deletes it when it makes a new plan. The tag is the profile (the cell tables differ).
GLOBAL LM_STORE_FILE IS "0:/lm/store.txt".

// lm_clock_zero_now: the UT at which this vessel's mission clock read zero.
FUNCTION lm_clock_zero_now {
  RETURN TIME:SECONDS - MISSIONTIME.
}

// lm_clock_zero_save: remember a clock zero (a UT) for the DSKY (the planner calls this when it makes a PAD, with the zero the PAD uses).
FUNCTION lm_clock_zero_save {
  PARAMETER zero_ut.
  lm_clock_zero_clear().
  LOG ROUND(zero_ut, 3) TO LM_CLOCK_FILE.
}

// lm_clock_zero_clear: forget the saved zero (Skip simulated uplink, where plan.json carries UT, so no clock is shared).
FUNCTION lm_clock_zero_clear {
  IF EXISTS(LM_CLOCK_FILE) { DELETEPATH(LM_CLOCK_FILE). }
}

// lm_clock_zero_ut: the UT of the AGC clock's zero. The saved zero when the file holds a believable one (not in the future and less
// than the clock's 31 days old), else this vessel's own mission-time zero.
FUNCTION lm_clock_zero_ut {
  IF EXISTS(LM_CLOCK_FILE) {
    LOCAL saved IS OPEN(LM_CLOCK_FILE):READALL:STRING:TRIM:TONUMBER(-1).
    IF saved > 0 AND saved <= TIME:SECONDS AND (TIME:SECONDS - saved) * 100 < LM_CLOCK_LIMIT_CS { RETURN saved. }
  }
  RETURN lm_clock_zero_now().
}

// lm_hms_cs: a time in seconds as the three integers N33 shows: hours, minutes, and seconds in hundredths (0 to 5999).
FUNCTION lm_hms_cs {
  PARAMETER seconds.
  LOCAL cs IS ROUND(seconds * 100).
  LOCAL hours IS FLOOR(cs / 360000).
  LOCAL rest IS cs - hours * 360000.
  LOCAL minutes IS FLOOR(rest / 6000).
  RETURN LIST(hours, minutes, rest - minutes * 6000).
}

// lm_hms_to_seconds: inverse of lm_hms_cs.
FUNCTION lm_hms_to_seconds {
  PARAMETER hours, minutes, hundredths.
  RETURN hours * 3600 + minutes * 60 + hundredths / 100.
}

// lm_site_to_rls: the Moon-fixed landing-site vector (metres) for a latitude, longitude (degrees) and height above the body
// radius. Our Moon-fixed frame: x through latitude 0, longitude 0; y through latitude 0, longitude 90 E; z north.
FUNCTION lm_site_to_rls {
  PARAMETER lat, lng, height_m, radius.
  LOCAL r_site IS radius + height_m.
  RETURN V(r_site * COS(lat) * COS(lng), r_site * COS(lat) * SIN(lng), r_site * SIN(lat)).
}

// lm_rls_to_site: LEXICON("LAT", .., "LNG", .., "ALT", ..) from a Moon-fixed vector (longitude in -180 to 180).
FUNCTION lm_rls_to_site {
  PARAMETER vec, radius.
  LOCAL r_site IS vec:MAG.
  RETURN LEXICON("LAT", ARCSIN(vec:Z / r_site), "LNG", ARCTAN2(vec:Y, vec:X), "ALT", r_site - radius).
}

// lm_store_put_dp_list: write several double-precision numbers (a LIST) to a cell, in order, at the cell's scale.
FUNCTION lm_store_put_dp_list {
  PARAMETER vault, name, values.
  LOCAL scale_exp IS vault["CELLS"][name]["SCALE"].
  LOCAL words IS LIST().
  FOR value IN values {
    LOCAL pair IS dp_encode(value, scale_exp).
    words:ADD(pair[0]).
    words:ADD(pair[1]).
  }
  RETURN store_put_all(vault, name, words).
}

// lm_store_get_dp_list: the numbers of a loaded cell as a LIST (each two words), or an empty LIST if the cell is not loaded.
FUNCTION lm_store_get_dp_list {
  PARAMETER vault, name.
  LOCAL out IS LIST().
  IF NOT store_loaded(vault, name) { RETURN out. }
  LOCAL words IS store_words(vault, name).
  LOCAL scale_exp IS vault["CELLS"][name]["SCALE"].
  FROM { LOCAL i IS 0. } UNTIL i >= words:LENGTH STEP { SET i TO i + 2. } DO {
    out:ADD(dp_decode(LIST(words[i], words[i + 1]), scale_exp)).
  }
  RETURN out.
}

FUNCTION lm_store_put_rls {
  PARAMETER vault, vec.
  RETURN lm_store_put_dp_list(vault, "RLS", LIST(vec:X, vec:Y, vec:Z)).
}

// lm_store_get_rls: the loaded RLS as a vector (V(0,0,0) when it is not loaded: check store_loaded first).
FUNCTION lm_store_get_rls {
  PARAMETER vault.
  LOCAL values IS lm_store_get_dp_list(vault, "RLS").
  IF values:LENGTH < 3 { RETURN V(0, 0, 0). }
  RETURN V(values[0], values[1], values[2]).
}

// lm_ut_to_tland_cs: a UT as AGC clock centiseconds from clock_zero (a UT), or -1 when it is before the zero or beyond the
// 28-bit clock.
FUNCTION lm_ut_to_tland_cs {
  PARAMETER ut, clock_zero.
  LOCAL cs IS ROUND((ut - clock_zero) * 100).
  IF cs < 0 OR cs >= LM_CLOCK_LIMIT_CS { RETURN -1. }
  RETURN cs.
}

FUNCTION lm_tland_cs_to_ut {
  PARAMETER cs, clock_zero.
  RETURN clock_zero + cs / 100.
}

// lm_store_put_tland: TLAND from a UT. FALSE (nothing written) when the time is outside the clock.
FUNCTION lm_store_put_tland {
  PARAMETER vault, ut, clock_zero.
  LOCAL cs IS lm_ut_to_tland_cs(ut, clock_zero).
  IF cs < 0 { RETURN FALSE. }
  RETURN lm_store_put_dp_list(vault, "TLAND", LIST(cs)).
}

// lm_store_get_tland_ut: the loaded TLAND as a UT, or -1 when it is not loaded.
FUNCTION lm_store_get_tland_ut {
  PARAMETER vault, clock_zero.
  LOCAL values IS lm_store_get_dp_list(vault, "TLAND").
  IF values:LENGTH < 1 { RETURN -1. }
  RETURN lm_tland_cs_to_ut(values[0], clock_zero).
}

// lm_store_put_tig: the time of ignition (N33) from seconds since the AGC clock zero.
FUNCTION lm_store_put_tig {
  PARAMETER vault, seconds.
  RETURN lm_store_put_dp_list(vault, "TIG", LIST(ROUND(seconds * 100))).
}

// lm_store_get_tig: seconds since the clock zero, or -1 when TIG is not loaded.
FUNCTION lm_store_get_tig {
  PARAMETER vault.
  LOCAL values IS lm_store_get_dp_list(vault, "TIG").
  IF values:LENGTH < 1 { RETURN -1. }
  RETURN values[0] / 100.
}

// DLAND (Luminary 210 only, N69): the landing-site correction in guidance axes (X up, Y crossrange, Z downrange), metres, six words (ECADR 2631 octal,
// E5 offset 921). Its scale is LAND's (2^24 m; it is added to LANDTEMP, LUNAR_LANDING_GUIDANCE_EQUATIONS 210 line 329): assumed from that, not read from a
// scale table. lm_store_has_dland says whether this store's profile has the cell; lm_store_get_dland gives zero when it is absent or not loaded.
FUNCTION lm_store_has_dland {
  PARAMETER vault.
  RETURN vault["CELLS"]:HASKEY("DLAND").
}
FUNCTION lm_store_put_dland {
  PARAMETER vault, vec.
  IF NOT lm_store_has_dland(vault) { RETURN FALSE. }
  RETURN lm_store_put_dp_list(vault, "DLAND", LIST(vec:X, vec:Y, vec:Z)).
}
FUNCTION lm_store_get_dland {
  PARAMETER vault.
  IF NOT lm_store_has_dland(vault) { RETURN V(0, 0, 0). }
  LOCAL values IS lm_store_get_dp_list(vault, "DLAND").
  IF values:LENGTH < 3 { RETURN V(0, 0, 0). }
  RETURN V(values[0], values[1], values[2]).
}

// lm_store_put_asc: the ascent targets of N76 from horizontal and radial speed (m/s) and cross-range (m).
FUNCTION lm_store_put_asc {
  PARAMETER vault, zdotd_ms, rdotd_ms, xrange_m.
  LOCAL ok_z IS lm_store_put_dp_list(vault, "ZDOTD", LIST(zdotd_ms / 100)).
  LOCAL ok_r IS lm_store_put_dp_list(vault, "RDOTD", LIST(rdotd_ms / 100)).
  LOCAL ok_x IS lm_store_put_dp_list(vault, "XRANGE", LIST(xrange_m)).
  RETURN ok_z AND ok_r AND ok_x.
}

// lm_store_get_asc: LEXICON("ZDOTD", m/s, "RDOTD", m/s, "XRANGE", m); a value that is not loaded is zero.
FUNCTION lm_store_get_asc {
  PARAMETER vault.
  LOCAL z_list IS lm_store_get_dp_list(vault, "ZDOTD").
  LOCAL r_list IS lm_store_get_dp_list(vault, "RDOTD").
  LOCAL x_list IS lm_store_get_dp_list(vault, "XRANGE").
  LOCAL out IS LEXICON("ZDOTD", 0, "RDOTD", 0, "XRANGE", 0).
  IF z_list:LENGTH > 0 { SET out["ZDOTD"] TO z_list[0] * 100. }
  IF r_list:LENGTH > 0 { SET out["RDOTD"] TO r_list[0] * 100. }
  IF x_list:LENGTH > 0 { SET out["XRANGE"] TO x_list[0]. }
  RETURN out.
}

// lm_store_put_dv: the delta-v (N81, local vertical axes) from a vector in metres per second.
FUNCTION lm_store_put_dv {
  PARAMETER vault, vec.
  RETURN lm_store_put_dp_list(vault, "DELVLVC", LIST(vec:X / 100, vec:Y / 100, vec:Z / 100)).
}

// lm_store_get_dv: the loaded delta-v in metres per second (V(0,0,0) when not loaded).
FUNCTION lm_store_get_dv {
  PARAMETER vault.
  LOCAL values IS lm_store_get_dp_list(vault, "DELVLVC").
  IF values:LENGTH < 3 { RETURN V(0, 0, 0). }
  RETURN V(values[0] * 100, values[1] * 100, values[2] * 100).
}
