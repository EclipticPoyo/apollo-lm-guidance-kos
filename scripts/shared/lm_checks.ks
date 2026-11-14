// lm_checks.ks -- cross-checks of our navigation against what kOS itself reports (plan Task 6).
//
// The Luminary-style quantities in lm_nav.ks are computed from position and velocity. kOS also
// reports several of the same things directly. If the two disagree, our frame or maths is wrong.
// Nothing here changes the display or the guidance: it only measures and logs.

RUNONCEPATH("0:/lm/lm_constants.ks").

// check_update: compare one cycle. Returns a LEXICON of differences (ours minus kOS's), SI units:
//   D_HDOT    HDOT     vs SHIP:VERTICALSPEED            m/s
//   D_VHORIZ  VHORIZ   vs SHIP:GROUNDSPEED              m/s  (equal only near the site: see below)
//   D_HCALC   HCALC    vs SHIP:ALTITUDE - SITE_ALT      m    (height above the landing-site radius)
//   D_RANGE   RANGEDSP vs LATLNG(SITE_LAT,SITE_LNG):DISTANCE   m
// Why VHORIZ only matches near the site: VHORIZ is horizontal with respect to the SITE's up axis,
// GROUNDSPEED with respect to the SHIP's own up axis. Far away these differ a lot (Task 4 smoke test).
// Why HCALC uses SITE_ALT: HCALC is height above the site radius (sea level + SITE_ALT), while
// SHIP:ALTITUDE is height above sea level. Real terrain around the site may differ from SITE_ALT.
// Returns an empty lexicon if the derived state is not valid.
FUNCTION check_update {
  PARAMETER derived, site_lat, site_lng, site_alt.
  IF NOT derived["VALID"] { RETURN LEXICON(). }
  RETURN LEXICON(
    "D_HDOT",   derived["HDOT"] - SHIP:VERTICALSPEED,
    "D_VHORIZ", derived["VHORIZ"] - SHIP:GROUNDSPEED,
    "D_HCALC",  derived["HCALC"] - (SHIP:ALTITUDE - site_alt),
    "D_RANGE",  derived["RANGEDSP"] - LATLNG(site_lat, site_lng):DISTANCE
  ).
}

// check_log_header: start a fresh log file. LOG appends, so the old file is deleted first.
// (LOG text TO path appends a line; verified in the kOS docs, commands/files.)
FUNCTION check_log_header {
  PARAMETER log_file.
  IF NOT LM_LOG { RETURN. }
  IF EXISTS(log_file) { DELETEPATH(log_file). }
  LOG "t_s,alt_m,hcalc_m,hdot,vhoriz,rangedsp,d_hdot,d_vhoriz,d_hcalc,d_range" TO log_file.
}

// check_log: append one comma-separated line. Skipped when the differences are empty (invalid state).
FUNCTION check_log {
  PARAMETER log_file, now_s, derived, diffs.
  IF NOT LM_LOG OR diffs:LENGTH = 0 { RETURN. }
  LOG ROUND(now_s, 2) + "," + ROUND(SHIP:ALTITUDE, 1) + "," + ROUND(derived["HCALC"], 1) + ","
    + ROUND(derived["HDOT"], 3) + "," + ROUND(derived["VHORIZ"], 3) + "," + ROUND(derived["RANGEDSP"], 1) + ","
    + ROUND(diffs["D_HDOT"], 4) + "," + ROUND(diffs["D_VHORIZ"], 4) + ","
    + ROUND(diffs["D_HCALC"], 2) + "," + ROUND(diffs["D_RANGE"], 2) TO log_file.
}

// ---- Deorbit planner checks (milestone 2, spec section 7) -------------------------------
// Both are pure: they take numbers in a LEXICON and return text, so they are tested on the pad.
// TERRAIN_CLEAR_MIN uses the sentinel -999999 for "terrain not measured" (a real clearance can be
// negative: the orbit would then pass below the ground, which is an error, not "not measured").

// check_plan_pre: sanity checks before the plan's burns are accepted. Input keys:
//   LEAD_S            time from now to the first burn, s
//   DV_DOI, DV_PC     delta-v magnitudes, m/s (DV_PC is 0 when no plane change)
//   MAX_PC_DV         largest plane-change delta-v the pilot accepted, m/s
//   ALT_PDI, ALT_PDI_NOM   planned PDI altitude and the pad-geometry value, m
//   V_PDI             speed at PDI on the planned descent orbit, m/s
//   WARP_RATE         current time-warp rate (1 = none)
//   NODES_OK          the game lets us make maneuver nodes
//   TERRAIN_CLEAR_MIN smallest height above the terrain on the descent orbit, m (-999999 = not measured)
//   VIGN              (optional) the profile's speed at PDI, m/s; the Apollo 11 VIGN when missing
// Returns LEXICON("ERRORS", LIST, "WARNINGS", LIST) of strings. Any error means: do not use this plan.
FUNCTION check_plan_pre {
  PARAMETER p.
  LOCAL errors IS LIST().
  LOCAL warnings IS LIST().
  IF p["LEAD_S"] < PLAN_LEAD_S {
    errors:ADD("first burn is only " + ROUND(p["LEAD_S"]) + " s away (minimum " + PLAN_LEAD_S + " s)").
  }
  IF p["DV_DOI"] > PLAN_DV_MAX {
    errors:ADD("DOI delta-v " + ROUND(p["DV_DOI"], 1) + " m/s is above the limit " + PLAN_DV_MAX + " m/s").
  }
  IF p["DV_PC"] > p["MAX_PC_DV"] {
    errors:ADD("plane change needs " + ROUND(p["DV_PC"], 1) + " m/s, above the accepted " + ROUND(p["MAX_PC_DV"], 1)
      + " m/s (rerun with a larger max_pc_dv to accept it)").
  }
  IF p["WARP_RATE"] > 1 {
    errors:ADD("time warp is running (rate " + p["WARP_RATE"] + "): stop warp and run again").
  }
  IF NOT p["NODES_OK"] {
    errors:ADD("maneuver nodes are not available (career: upgrade the Tracking Station)").
  }
  IF p["TERRAIN_CLEAR_MIN"] > -900000 AND p["TERRAIN_CLEAR_MIN"] < PLAN_TERRAIN_MIN_M {
    errors:ADD("descent orbit comes within " + ROUND(p["TERRAIN_CLEAR_MIN"]) + " m of the terrain (minimum "
      + PLAN_TERRAIN_MIN_M + " m)").
  }
  LOCAL vign_used IS VIGN.                                       // the Apollo 11 value unless the caller names the profile's own
  IF p:HASKEY("VIGN") { SET vign_used TO p["VIGN"]. }
  IF ABS(p["V_PDI"] - vign_used) > PLAN_VIGN_TOL {
    warnings:ADD("PDI speed " + ROUND(p["V_PDI"], 1) + " m/s differs from VIGN " + ROUND(vign_used, 1)
      + " m/s by more than " + PLAN_VIGN_TOL + " m/s (P63 ignition timing will absorb small differences)").
  }
  IF ABS(p["ALT_PDI"] - p["ALT_PDI_NOM"]) > PLAN_CHK_ALT {
    warnings:ADD("planned PDI altitude " + ROUND(p["ALT_PDI"]) + " m is far from the pad geometry "
      + ROUND(p["ALT_PDI_NOM"]) + " m").
  }
  IF p["TERRAIN_CLEAR_MIN"] <= -900000 {
    warnings:ADD("terrain not checked").
  }
  RETURN LEXICON("ERRORS", errors, "WARNINGS", warnings).
}

// check_post_line: one report line, "name predicted=.. planned=.. PASS|FAIL".
FUNCTION check_post_line {
  PARAMETER name, predicted, planned, ok.
  RETURN name + " predicted=" + ROUND(predicted, 2) + " planned=" + ROUND(planned, 2) + " " + (CHOOSE "PASS" IF ok ELSE "FAIL").
}

// check_plan_post: compares kOS's own prediction at the planned PDI time with the pad targets
// (spec section 8, plan pass criteria). Input keys:
//   ALT_PDI_PRED, ALT_PDI_NOM   predicted and pad-geometry PDI altitude, m
//   RANGE_PRED, RANGE_NOM       predicted ground distance from the PDI point to the site, and |RIGNZ|, m
//   SPEED_PRED, SPEED_PLAN      predicted and planned PDI speed, m/s
//   XRANGE_PRED                 predicted crossrange at the site, m
//   BURN_ERR                    largest |node BURNVECTOR - intended delta-v|, m/s
// Returns LEXICON("PASS", bool, "LINES", LIST of report strings).
FUNCTION check_plan_post {
  PARAMETER post_in.
  LOCAL ok_alt IS ABS(post_in["ALT_PDI_PRED"] - post_in["ALT_PDI_NOM"]) <= PLAN_CHK_ALT.
  LOCAL ok_range IS ABS(post_in["RANGE_PRED"] - post_in["RANGE_NOM"]) <= PLAN_CHK_RANGE.
  LOCAL ok_speed IS ABS(post_in["SPEED_PRED"] - post_in["SPEED_PLAN"]) <= PLAN_CHK_SPEED.
  LOCAL ok_xrange IS ABS(post_in["XRANGE_PRED"]) < PLAN_XRANGE_MAX.
  LOCAL ok_burn IS post_in["BURN_ERR"] <= PLAN_CHK_BURN.
  LOCAL lines IS LIST().
  lines:ADD(check_post_line("PDI altitude (m)", post_in["ALT_PDI_PRED"], post_in["ALT_PDI_NOM"], ok_alt)).
  lines:ADD(check_post_line("ground range to site (m)", post_in["RANGE_PRED"], post_in["RANGE_NOM"], ok_range)).
  lines:ADD(check_post_line("PDI speed (m/s)", post_in["SPEED_PRED"], post_in["SPEED_PLAN"], ok_speed)).
  lines:ADD(check_post_line("crossrange at site (m)", post_in["XRANGE_PRED"], 0, ok_xrange)).
  lines:ADD(check_post_line("node burn vector error (m/s)", post_in["BURN_ERR"], 0, ok_burn)).
  RETURN LEXICON("PASS", ok_alt AND ok_range AND ok_speed AND ok_xrange AND ok_burn, "LINES", lines).
}
