// lm_pad.ks -- the planner's uplink mode: turns a deorbit plan into a PAD, the list of what Mission Control would read up to the
// crew, written as keystrokes: the UPLINK section (what the ground sent: a V71 block each for the landing site RLS and the landing
// time TLAND, and one V71 block for the DOI burn's delta-v and ignition time, the GSOP's "external delta-v update"). A plane-change
// burn is the CSM's and is not loaded in the LM; the PAD only notes it. Why: docs/superpowers/ground-uplinks-research.md.
// Pure logic (no flight data): every input is a parameter, so tests/test_pad.ks checks it against tests/reference_loads.py, whose
// pad_lines must give the same lines.
// Needs lm_cells.ks (the cell table and conversions), core/dsky_store.ks and core/dsky_display.ks (zero_pad).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").
RUNONCEPATH("0:/core/dsky_display.ks").

// pad_chars: a text as a LIST of one-character key names.
FUNCTION pad_chars {
  PARAMETER text.
  LOCAL out IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= text:LENGTH STEP { SET i TO i + 1. } DO { out:ADD(text:SUBSTRING(i, 1)). }
  RETURN out.
}

// pad_join: a LIST of key names as one text.
FUNCTION pad_join {
  PARAMETER keys.
  LOCAL text IS "".
  FOR key_name IN keys { SET text TO text + key_name. }
  RETURN text.
}

// pad_add: add the characters of text to a LIST of keys.
FUNCTION pad_add {
  PARAMETER keys, text.
  FOR key_name IN pad_chars(text) { keys:ADD(key_name). }
}

// pad_v71_keys: the keys of a V71 block update of the words (a LIST of 15-bit integers) at an ECADR, ending in V33 E.
// V71 E, II E (octal, the words + 2), ECADR E (four octal digits), each word as five octal digits and E, V33 E.
FUNCTION pad_v71_keys {
  PARAMETER ecadr_value, words.
  LOCAL keys IS LIST().
  pad_add(keys, "V71E").
  pad_add(keys, octal_text(words:LENGTH + 2, 2) + "E").
  pad_add(keys, octal_text(ecadr_value, 4) + "E").
  FOR word IN words { pad_add(keys, octal_text(word, 5) + "E"). }
  pad_add(keys, "V33E").
  RETURN keys.
}

// pad_signed5: an integer as a sign and five digits (the way a register shows it).
FUNCTION pad_signed5 {
  PARAMETER n.
  RETURN (CHOOSE "-" IF n < 0 ELSE "+") + zero_pad(MIN(99999, ABS(n)), 5).
}

// pad_number_text: a number rounded to the given decimals, without trailing zeros ("0.674", "23.5", "-4").
FUNCTION pad_number_text {
  PARAMETER value, decimals.
  RETURN "" + ROUND(value, decimals).
}

// pad_clock_text: seconds as H:MM:SS.CC (hours, minutes, seconds, hundredths), e.g. 3:34:51.54.
FUNCTION pad_clock_text {
  PARAMETER seconds.
  LOCAL parts IS lm_hms_cs(seconds).
  RETURN parts[0] + ":" + zero_pad(parts[1], 2) + ":" + zero_pad(FLOOR(parts[2] / 100), 2) + "." + zero_pad(MOD(parts[2], 100), 2).
}

// pad_block_line: the keys of one V71 block as one PAD line, spaced so each key group can be read and ticked off: V71 E, the count E,
// the ECADR E, then the words (octal, five digits), each followed by E, and V33 E. The same keys as pad_v71_keys, with spaces.
FUNCTION pad_block_line {
  PARAMETER ecadr_value, words.
  LOCAL text IS "  V71 E " + octal_text(words:LENGTH + 2, 2) + " E " + octal_text(ecadr_value, 4) + " E ".
  FOR word IN words { SET text TO text + " " + octal_text(word, 5) + " E". }
  RETURN text + "  V33 E".
}

// pad_burn_tenths: a delta-v (LIST of three m/s) as the three tenths-of-ft/s integers N81 shows.
FUNCTION pad_burn_tenths {
  PARAMETER lv_dv.
  RETURN LIST(ROUND(lv_dv[0] * FT_PER_M * 10), ROUND(lv_dv[1] * FT_PER_M * 10), ROUND(lv_dv[2] * FT_PER_M * 10)).
}

// pad_burn_uplink: one burn as the UPLINK section's block: LEXICON("LINES", the PAD lines, "KEYS", the V71 keys). The block is the
// six words of DELVLVC (the delta-v in local vertical axes, metres per centisecond) then the two words of TIG, eight words from the
// DELVLVC ECADR: the GSOP's external delta-v update (the two cells are next to each other in both software versions). The lines
// show what N33 and N81 will read once it is loaded, so the PAD can be checked against the display.
FUNCTION pad_burn_uplink {
  PARAMETER label, tig_ut, lv_dv, clock_zero, cells.
  LOCAL words IS LIST().
  FOR component IN lv_dv {
    LOCAL pair IS dp_encode(component / 100, cells["DELVLVC"]["SCALE"]).
    words:ADD(pair[0]).
    words:ADD(pair[1]).
  }
  LOCAL tig_pair IS dp_encode(ROUND((tig_ut - clock_zero) * 100), cells["TIG"]["SCALE"]).
  words:ADD(tig_pair[0]).
  words:ADD(tig_pair[1]).
  LOCAL burn_ecadr IS store_ecadr(cells, "DELVLVC").
  LOCAL tig_text IS "".
  FOR n IN lm_hms_cs(tig_ut - clock_zero) { SET tig_text TO tig_text + (CHOOSE "" IF tig_text = "" ELSE " ") + pad_signed5(n). }
  LOCAL dv_text IS "".
  FOR n IN pad_burn_tenths(lv_dv) { SET dv_text TO dv_text + (CHOOSE "" IF dv_text = "" ELSE " ") + pad_signed5(n). }
  LOCAL keys IS pad_v71_keys(burn_ecadr, words).
  LOCAL lines IS LIST(label + " BURN   address " + octal_text(burn_ecadr, 4),
                      "  TIG  " + pad_clock_text(tig_ut - clock_zero) + "   N33 " + tig_text,
                      "  DV   N81 " + dv_text + "   (tenths ft/s, local vertical X Y Z)").
  lines:ADD(pad_block_line(burn_ecadr, words)).
  RETURN LEXICON("LINES", lines, "KEYS", keys).
}

// pad_build: the PAD for a saved plan (LEXICON, see plan_write in lm_plan.ks), the software profile ("A11" or "J"), the body radius
// (m) and the UT of the AGC clock's zero (lm_clock_zero_ut). Returns LEXICON("OK", bool, "WHY", text when not OK,
// "UPLINK_KEYS", LIST of the key names of the whole UPLINK section (what SEND writes to the uplink file), "LINES", the PAD text lines).
// The DOI burn is uplinked (one V71 block, part of UPLINK_KEYS). A plan with a plane change (T_PC at or above zero) gets one more
// PAD line saying it is a CSM burn, not loaded in the LM (the store holds one burn's data at a time, like P30's cells).
FUNCTION pad_build {
  PARAMETER plan, profile, radius, clock_zero.
  LOCAL out IS LEXICON("OK", FALSE, "WHY", "", "UPLINK_KEYS", LIST(), "LINES", LIST()).
  IF NOT plan:ISTYPE("Lexicon") { SET out["WHY"] TO "there is no plan". RETURN out. }
  FOR need IN LIST("SITE_LAT", "SITE_LNG", "SITE_ALT", "T_LAND", "T_DOI", "T_PC", "LV_DOI") {
    IF NOT plan:HASKEY(need) { SET out["WHY"] TO "the plan has no " + need + " (plan again)". RETURN out. }
  }
  LOCAL cells IS lm_cells_for(profile).
  LOCAL tland_cs IS lm_ut_to_tland_cs(plan["T_LAND"], clock_zero).
  IF tland_cs < 0 { SET out["WHY"] TO "the landing time does not fit the AGC clock (before its zero, or beyond 31 days)". RETURN out. }
  IF plan["T_DOI"] < clock_zero { SET out["WHY"] TO "the DOI time is before the AGC clock zero". RETURN out. }

  LOCAL rls_vec IS lm_site_to_rls(plan["SITE_LAT"], plan["SITE_LNG"], plan["SITE_ALT"], radius).
  LOCAL rls_words IS LIST().
  FOR comp IN LIST(rls_vec:X, rls_vec:Y, rls_vec:Z) {
    LOCAL pair IS dp_encode(comp, cells["RLS"]["SCALE"]).
    rls_words:ADD(pair[0]).
    rls_words:ADD(pair[1]).
  }
  LOCAL rls_ecadr IS store_ecadr(cells, "RLS").
  LOCAL tland_words IS dp_encode(tland_cs, cells["TLAND"]["SCALE"]).
  LOCAL tland_ecadr IS store_ecadr(cells, "TLAND").
  LOCAL rls_keys IS pad_v71_keys(rls_ecadr, rls_words).
  LOCAL tland_keys IS pad_v71_keys(tland_ecadr, tland_words).

  LOCAL lines IS LIST().
  lines:ADD("PAD " + (CHOOSE "LUMINARY210" IF profile = "J" ELSE "LUMINARY099") + "     CLOCK ZERO UT " + ROUND(clock_zero)).
  lines:ADD("UPLINK in P00, one block at a time (V34 E abandons a block)").
  lines:ADD("").
  lines:ADD("LANDING SITE (RLS)   address " + octal_text(rls_ecadr, 4)).
  lines:ADD("  lat " + pad_number_text(plan["SITE_LAT"], 3) + "  long " + pad_number_text(plan["SITE_LNG"], 3) + "  height " + ROUND(plan["SITE_ALT"]) + " m").
  lines:ADD(pad_block_line(rls_ecadr, rls_words)).
  lines:ADD("").
  lines:ADD("LANDING TIME (TLAND)   address " + octal_text(tland_ecadr, 4)).
  lines:ADD("  " + tland_cs + " cs = " + pad_clock_text(tland_cs / 100) + " after the clock zero").
  lines:ADD(pad_block_line(tland_ecadr, tland_words)).
  lines:ADD("").
  // The DOI burn is the LM's only burn and the ground uplinked it before separation (one 8-word V71 block). A plane-change burn is the
  // CSM's (Apollo's LM made none before PDI), so it is flown from its node and never loaded into the LM: the PAD only says so.
  LOCAL doi_burn IS pad_burn_uplink("DOI", plan["T_DOI"], plan["LV_DOI"], clock_zero, cells).
  FOR burn_line IN doi_burn["LINES"] { lines:ADD(burn_line). }
  IF plan["T_PC"] >= 0 {
    lines:ADD("").
    lines:ADD("PC: a CSM burn, flown from its node; not loaded in the LM").
  }

  LOCAL all_keys IS LIST().
  FOR key_name IN rls_keys { all_keys:ADD(key_name). }
  FOR key_name IN tland_keys { all_keys:ADD(key_name). }
  FOR key_name IN doi_burn["KEYS"] { all_keys:ADD(key_name). }
  SET out["OK"] TO TRUE.
  SET out["UPLINK_KEYS"] TO all_keys.
  SET out["LINES"] TO lines.
  RETURN out.
}

// pad_profile_note: "" when the planner's software version (menu_profile) is the one the DSKY will use (config_profile, from
// lm_config.txt: with no plan file the DSKY takes its version from there), else a sentence saying what to set. A PAD made for one version
// has that version's cell addresses, so keying it into a DSKY running the other would write the wrong cells.
FUNCTION pad_profile_note {
  PARAMETER menu_profile, config_profile.
  IF menu_profile = config_profile { RETURN "". }
  RETURN "The DSKY takes its version from lm_config.txt (now " + config_profile + "): set PAD_PROFILE = " + menu_profile + " there, or this PAD's addresses will not match.".
}

// pad_write: write the PAD lines to a file (the old file is deleted first, LOG appends).
FUNCTION pad_write {
  PARAMETER lines, file_path.
  IF EXISTS(file_path) { DELETEPATH(file_path). }
  FOR line IN lines { LOG line TO file_path. }
}

// pad_write_uplink: write the key names, one per line, to the uplink file the DSKY feeds from (dsky_uplink.ks).
FUNCTION pad_write_uplink {
  PARAMETER keys, file_path.
  IF EXISTS(file_path) { DELETEPATH(file_path). }
  FOR key_name IN keys { LOG key_name TO file_path. }
}
