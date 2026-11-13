// lm_deorbit.ks -- landing-site selection and deorbit planner (milestone 2).
//
//   RUNPATH("0:/lm/lm_deorbit.ks", lat, lng).                    plan to the site at lat, lng (degrees)
//   RUNPATH("0:/lm/lm_deorbit.ks", lat, lng, alt_m).             ...with the site height above sea level (m)
//   RUNPATH("0:/lm/lm_deorbit.ks", lat, lng, alt_m, 300).        ...accepting a plane change up to 300 m/s
//   RUNPATH("0:/lm/lm_deorbit.ks", lat, lng, -999999, 200, TRUE). replace existing maneuver nodes
//
// It adds up to two maneuver nodes to the ship (a plane change, then the DOI burn that puts PDI at the
// Apollo 11 pad-loaded ignition geometry before the site) and writes a report. The PILOT flies the
// burns; nothing here steers or throttles. Design: docs/superpowers/specs/2026-11-12-site-selection-deorbit-planner-design.md.
//
// Needs a bound lunar orbit, no time warp, and (career) a Tracking Station that allows maneuver nodes.
// Never deletes the pilot's own nodes unless replace = TRUE; on any failure it removes the nodes it added.
//
// Parameter names are in_lat etc. because kOS names are case-insensitive: SITE_LAT already exists
// in lm_constants.ks.

// in_lat = -999 (no arguments) means "load the functions only": lm_plan_ui.ks does this and then calls
// deorbit_run itself. Latitude -999 is impossible, so it cannot clash with a real site.
PARAMETER in_lat IS -999, in_lng IS 0, in_alt IS -999999, max_pc_dv IS 200, replace IS FALSE.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_site.ks").
RUNONCEPATH("0:/lm/lm_plan.ks").
RUNONCEPATH("0:/lm/lm_checks.ks").

GLOBAL DP_LOG IS "0:/lm/lm_deorbit.log".
GLOBAL dp_nodes IS LIST().        // nodes THIS script added (only these are ever removed)
GLOBAL dp_intended IS LIST().     // the delta-v vector the planner meant for each, same order
GLOBAL DP_QUIET IS FALSE.         // TRUE = print nothing; the full report still goes to DP_LOG (lm_plan_ui.ks sets it)
GLOBAL DP_SUMMARY IS LIST().      // the result in one or two short lines, for a window to show (set by deorbit_run)

// dp_say: print a line (unless DP_QUIET) and append it to the report log.
FUNCTION dp_say {
  PARAMETER text.
  IF NOT DP_QUIET { PRINT text. }
  IF LM_LOG { LOG text TO DP_LOG. }
}

// dp_met: the mission elapsed time (MET) of universal time ut, as "HHH:MM:SS". MISSIONTIME is the ship's MET
// now, so the MET of a future moment is MISSIONTIME plus the time until then. Hours are not capped: past 99 h
// the text just gets longer. A time already past is shown as 0.
FUNCTION dp_met {
  PARAMETER ut.
  LOCAL total IS ROUND(MAX(0, MISSIONTIME + (ut - TIME:SECONDS))).
  LOCAL hours IS FLOOR(total / 3600).
  LOCAL mins IS FLOOR((total - hours * 3600) / 60).
  LOCAL secs IS total - hours * 3600 - mins * 60.
  RETURN dp_pad(hours, 3) + ":" + dp_pad(mins, 2) + ":" + dp_pad(secs, 2).
}

// dp_pad: the whole number n as text, padded with leading zeros to at least width characters.
FUNCTION dp_pad {
  PARAMETER n, width.
  LOCAL text IS "" + n.
  UNTIL text:LENGTH >= width { SET text TO "0" + text. }
  RETURN text.
}

// dp_log_only: append to the report log without printing (diagnostic lines).
FUNCTION dp_log_only {
  PARAMETER text.
  IF LM_LOG { LOG text TO DP_LOG. }
}

// dp_clear: remove the nodes this script added (never anything else).
FUNCTION dp_clear {
  FOR nd IN dp_nodes { REMOVE nd. }
  dp_nodes:CLEAR().
  dp_intended:CLEAR().
}

// dp_fail: report a reason, remove our nodes, end the run unsuccessfully.
FUNCTION dp_fail {
  PARAMETER reason.
  dp_clear().
  SET DP_SUMMARY TO LIST("PLAN FAILED: " + reason, "No maneuver nodes were left by this run.").
  dp_say("PLAN FAILED: " + reason).
  dp_say("No maneuver nodes were left on the ship by this run.").
  RETURN FALSE.
}

// The orbit prediction as the planner needs it: Moon-centred position and velocity at UT t.
// POSITIONAT is measured from the ship's centre NOW, so the body position is read in the same call.
// Both include any maneuver nodes already added (kOS docs, commands/prediction).
FUNCTION dp_pos_at {
  PARAMETER t.
  RETURN POSITIONAT(SHIP, t) - SHIP:BODY:POSITION.
}
FUNCTION dp_vel_at {
  PARAMETER t.
  RETURN VELOCITYAT(SHIP, t):ORBIT.
}

// dp_add_node: add a node for delta-v dv_vec at UT t (position and velocity there from the prediction),
// remember it with its intended vector. The conversion to radial/normal/prograde is plan_node_components.
FUNCTION dp_add_node {
  PARAMETER t, dv_vec, r_vec, v_vec.
  LOCAL comp IS plan_node_components(dv_vec, r_vec, v_vec).
  LOCAL nd IS NODE(t, comp["RADIAL"], comp["NORMAL"], comp["PROGRADE"]).
  ADD nd.
  dp_nodes:ADD(nd).
  dp_intended:ADD(dv_vec).
  // Diagnostic (milestone 2 flight test): log what we meant against what kOS reports, per node, at ADD time.
  LOCAL bv IS nd:BURNVECTOR.
  dp_log_only("  node diag t=" + ROUND(t) + " intended=(" + ROUND(dv_vec:X, 3) + "," + ROUND(dv_vec:Y, 3) + "," + ROUND(dv_vec:Z, 3)
      + ") |" + ROUND(dv_vec:MAG, 3) + "| burnvec=(" + ROUND(bv:X, 3) + "," + ROUND(bv:Y, 3) + "," + ROUND(bv:Z, 3)
      + ") |" + ROUND(bv:MAG, 3) + "| err " + ROUND((bv - dv_vec):MAG, 3) + " angle " + ROUND(VANG(bv, dv_vec), 2)
      + " deg; rad/nrm/pro=" + ROUND(comp["RADIAL"], 3) + "/" + ROUND(comp["NORMAL"], 3) + "/" + ROUND(comp["PROGRADE"], 3)
      + " |r|=" + ROUND(r_vec:MAG) + " |v|=" + ROUND(v_vec:MAG, 2) + " r.v/(|r||v|)=" + ROUND(VDOT(r_vec, v_vec) / (r_vec:MAG * v_vec:MAG), 5)
      + " dv.n=" + ROUND(VDOT(dv_vec, VCRS(r_vec, v_vec):NORMALIZED), 3)).
}

// dp_terrain_min: the smallest height of the descent orbit above the terrain between UT t_a and t_b
// (20 samples), metres. Predicted positions are mapped back into the Moon-fixed axes of now before
// asking the body for the terrain height there.
FUNCTION dp_terrain_min {
  PARAMETER t_a, t_b, wm_vec.
  LOCAL t_now IS TIME:SECONDS.
  LOCAL least IS 1e12.
  FROM { LOCAL i IS 0. } UNTIL i > 20 STEP { SET i TO i + 1. } DO {
    LOCAL t IS t_a + (t_b - t_a) * i / 20.
    LOCAL pos_vec IS dp_pos_at(t).
    LOCAL fixed_vec IS pos_vec.
    IF PREDICT_AXES_INERTIAL { SET fixed_vec TO plan_spin_rotate(pos_vec, wm_vec, -(t - t_now)). }
    LOCAL geo IS SHIP:BODY:GEOPOSITIONOF(fixed_vec + SHIP:BODY:POSITION).
    SET least TO MIN(least, pos_vec:MAG - (SHIP:BODY:RADIUS + geo:TERRAINHEIGHT)).
  }
  RETURN least.
}

// deorbit_run: the whole plan. Returns TRUE when a plan was made and passed its checks.
FUNCTION deorbit_run {
  PARAMETER lat_in, lng_in, alt_in, max_pc, replace_nodes.

  IF LM_LOG AND EXISTS(DP_LOG) { DELETEPATH(DP_LOG). }
  dp_say("lm_deorbit " + ROUND(TIME:SECONDS) + " UT, ship " + SHIP:NAME).

  // ---- 1. Preconditions ---------------------------------------------------------------------
  IF SHIP:BODY:NAME <> BODY_NAME { RETURN dp_fail("this ship is at " + SHIP:BODY:NAME + ", not " + BODY_NAME + ".").  }
  IF SHIP:STATUS <> "ORBITING" { RETURN dp_fail("the ship is " + SHIP:STATUS + ", not ORBITING."). }
  IF SHIP:ORBIT:ECCENTRICITY >= 1 { RETURN dp_fail("the orbit is not bound (eccentricity " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + ").").  }
  IF SHIP:ORBIT:PERIAPSIS <= 0 { RETURN dp_fail("the orbit's perilune is below the surface: the ship would hit the Moon."). }
  // The prediction functions follow the orbit across patches. An orbit that leaves the Moon's sphere of
  // influence first would give positions on another body's patch.
  IF SHIP:ORBIT:TRANSITION <> "FINAL" { RETURN dp_fail("the orbit ends with a transition (" + SHIP:ORBIT:TRANSITION + "): it must stay in the " + BODY_NAME + "'s sphere of influence."). }
  // POSITIONAT and VELOCITYAT need the same career upgrade as maneuver nodes (kOS docs, commands/prediction),
  // so this is checked before any prediction call.
  IF NOT CAREER():CANMAKENODES { RETURN dp_fail("maneuver nodes are not available (career: upgrade the Tracking Station)."). }
  IF KUNIVERSE:TIMEWARP:RATE > 1 { RETURN dp_fail("time warp is running (rate " + KUNIVERSE:TIMEWARP:RATE + "): stop warp and run again."). }
  IF NOT POSITIONAT_INCLUDES_NODES {
    RETURN dp_fail("POSITIONAT_INCLUDES_NODES is FALSE in lm_constants.ks (probe result): this planner cannot run, see the plan Task 2.").
  }
  LOCAL site IS site_resolve(lat_in, lng_in, alt_in).
  IF NOT site["VALID"] { RETURN dp_fail("bad site: " + site["WHY"]). }
  IF ALLNODES:LENGTH > 0 {
    dp_say("The ship already has " + ALLNODES:LENGTH + " maneuver node(s):").
    FOR nd IN ALLNODES { dp_say("  in " + ROUND(nd:ETA) + " s, " + ROUND(nd:BURNVECTOR:MAG, 1) + " m/s"). }
    IF NOT replace_nodes { RETURN dp_fail("existing nodes kept. Remove them yourself, or rerun with replace = TRUE."). }
    LOCAL old_nodes IS ALLNODES:COPY.
    FOR nd IN old_nodes { REMOVE nd. }
    dp_say("replace = TRUE: removed the existing nodes.").
  }
  LOCAL nodes_ok IS TRUE.   // the career check above already refused otherwise
  // From here a plan is attempted. Any earlier plan file would no longer match the ship's nodes if this
  // attempt fails, so it is removed now: plan.json always describes the latest successful plan.
  IF EXISTS(PLAN_PLAN_FILE) { DELETEPATH(PLAN_PLAN_FILE). }

  // ---- 2. Inputs ---------------------------------------------------------------------------------
  SET CONFIG:IPU TO 2000.
  LOCAL t_start IS TIME:SECONDS.
  LOCAL land_vec IS site["LAND_VEC"].
  LOCAL site_radius IS land_vec:MAG.
  LOCAL wm_vec IS moon_spin().
  LOCAL mu IS SHIP:BODY:MU.
  LOCAL geo IS plan_pdi_geometry(site_radius, RIGNX, RIGNZ, SHIP:BODY:RADIUS).
  LOCAL n_cur IS VCRS(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT):NORMALIZED.
  LOCAL period IS SHIP:ORBIT:PERIOD.
  LOCAL span IS period * 1.02.          // search window: one orbit plus a margin so a pass at the edge is not missed
  LOCAL pos_d IS dp_pos_at@.
  LOCAL rad_to_deg IS 180 / CONSTANT:PI.
  dp_say("Site " + ROUND(site["LAT"], 4) + " N, " + ROUND(site["LNG"], 4) + " E, height " + ROUND(site["ALT"]) + " m (entered "
         + lat_in + ", " + lng_in + ").").
  dp_say("Orbit before: apolune " + ROUND(SHIP:ORBIT:APOAPSIS) + " m, perilune " + ROUND(SHIP:ORBIT:PERIAPSIS) + " m, inclination "
         + ROUND(SHIP:ORBIT:INCLINATION, 3) + " deg, period " + ROUND(period) + " s.").
  dp_say("PDI geometry from the pad loads: radius " + ROUND(geo["R_PDI"]) + " m, altitude " + ROUND(geo["ALT_PDI"]) + " m, "
         + ROUND(geo["PHI"], 3) + " deg before the site.").

  // ---- 3. Iterate: the Moon turns during the coast, so the site moves while we plan -------------------
  LOCAL t_land_guess IS t_start + PLAN_LEAD_S + period + 3600 + PLAN_PDI_TO_LAND_S.   // only a starting point
  LOCAL converged IS FALSE.
  LOCAL pass_no IS 0.
  LOCAL t_pc IS -1.
  LOCAL dv_pc IS V(0, 0, 0).
  LOCAL t_doi IS 0.
  LOCAL doi IS LEXICON().
  LOCAL t_pdi IS 0.
  LOCAL t_land IS 0.
  LOCAL s_land IS V(1, 0, 0).
  LOCAL tilt_deg IS 0.
  UNTIL converged OR pass_no >= PLAN_ITER_MAX {
    SET pass_no TO pass_no + 1.
    dp_clear().

    // The site direction at the guessed landing time, and the target plane through it.
    LOCAL s_dir IS plan_site_at(land_vec, wm_vec, t_land_guess - t_start):NORMALIZED.
    LOCAL tgt IS plan_target_normal(n_cur, s_dir).
    IF NOT tgt["OK"] { RETURN dp_fail("the site lies on the orbit's pole direction: no single target plane. Plan from a different orbit."). }
    SET tilt_deg TO tgt["TILT"].
    LOCAL xrange IS site_radius * ABS(tilt_deg) / rad_to_deg.

    // Plane change, only when the site is farther out of the plane than PLAN_XRANGE_MAX.
    LOCAL n_use IS n_cur.
    LOCAL s_use IS plan_in_plane(s_dir, n_cur).
    SET t_pc TO -1.
    SET dv_pc TO V(0, 0, 0).
    IF xrange >= PLAN_XRANGE_MAX {
      // The two planes cross along k. The ship passes either +k or -k first: take the earlier pass.
      LOCAL k_vec IS VCRS(n_cur, tgt["N_T"]):NORMALIZED.
      LOCAL t_a IS plan_find_pass(pos_d, n_cur, k_vec, t_start + PLAN_LEAD_S, span).
      LOCAL t_b IS plan_find_pass(pos_d, n_cur, -k_vec, t_start + PLAN_LEAD_S, span).
      IF t_a < 0 AND t_b < 0 { RETURN dp_fail("could not find where the orbit crosses the target plane."). }
      IF t_a < 0 { SET t_pc TO t_b. } ELSE IF t_b < 0 { SET t_pc TO t_a. } ELSE { SET t_pc TO MIN(t_a, t_b). }
      LOCAL r_pc IS dp_pos_at(t_pc).
      LOCAL v_pc IS dp_vel_at(t_pc).
      SET dv_pc TO plan_plane_change(r_pc, v_pc, n_cur, tgt["N_T"]).
      IF dv_pc:MAG > max_pc {
        RETURN dp_fail("plane change needs " + ROUND(dv_pc:MAG, 1) + " m/s, above the accepted " + ROUND(max_pc, 1)
                       + " m/s. Rerun with a larger max_pc_dv to accept it.").
      }
      dp_add_node(t_pc, dv_pc, r_pc, v_pc).
      SET n_use TO tgt["N_T"].
      SET s_use TO s_dir.
    }

    // The DOI point is the descent orbit's apolune: 180 degrees before PDI, and PDI is PHI before the site.
    LOCAL u_doi IS -plan_point_ahead(n_use, s_use, -geo["PHI"]).
    // Leave time to fly the plane change before the DOI burn (PLAN_NODE_GAP_S).
    LOCAL t_from IS MAX(t_start + PLAN_LEAD_S, t_pc + PLAN_NODE_GAP_S).
    SET t_doi TO plan_find_pass(pos_d, n_use, u_doi, t_from, span).
    IF t_doi < 0 { RETURN dp_fail("could not find the DOI point on the orbit."). }
    LOCAL r_doi IS dp_pos_at(t_doi).
    LOCAL v_doi IS dp_vel_at(t_doi).
    SET doi TO plan_doi(r_doi, v_doi, n_use, geo["R_PDI"], mu).
    IF NOT doi["OK"] {
      RETURN dp_fail("the orbit at the DOI point (radius " + ROUND(doi["RA"]) + " m) is lower than the PDI radius "
                     + ROUND(geo["R_PDI"]) + " m: no descent orbit exists. Plan from a higher orbit.").
    }

    // Sanity checks on this pass (terrain is measured once, after the passes converge).
    LOCAL first_t IS t_doi.
    IF t_pc > 0 { SET first_t TO t_pc. }
    LOCAL pre IS check_plan_pre(LEXICON("LEAD_S", first_t - t_start, "DV_DOI", doi["DV"]:MAG, "DV_PC", dv_pc:MAG,
        "MAX_PC_DV", max_pc, "ALT_PDI", geo["ALT_PDI"], "ALT_PDI_NOM", geo["ALT_PDI"], "V_PDI", doi["V_PDI"],
        "WARP_RATE", KUNIVERSE:TIMEWARP:RATE, "NODES_OK", nodes_ok, "TERRAIN_CLEAR_MIN", -999999)).
    IF pre["ERRORS"]:LENGTH > 0 { RETURN dp_fail(pre["ERRORS"][0]). }
    dp_add_node(t_doi, doi["DV"], r_doi, v_doi).

    SET t_pdi TO t_doi + doi["T_HALF"].
    SET t_land TO t_pdi + PLAN_PDI_TO_LAND_S.
    SET s_land TO plan_site_at(land_vec, wm_vec, t_land - t_start):NORMALIZED.
    dp_say("pass " + pass_no + ": landing time " + ROUND(t_land, 1) + " UT (guess was " + ROUND(t_land_guess, 1) + ").").
    IF ABS(t_land - t_land_guess) < PLAN_LAND_TOL_S { SET converged TO TRUE. }
    SET t_land_guess TO t_land.
  }
  IF NOT converged { RETURN dp_fail("the timing did not converge in " + PLAN_ITER_MAX + " passes."). }

  // ---- 4. Does each node's BURNVECTOR equal the vector we meant? --------------------------------------
  LOCAL burn_err IS 0.
  FROM { LOCAL i IS 0. } UNTIL i >= dp_nodes:LENGTH STEP { SET i TO i + 1. } DO {
    // Flight test finding (2026-11-12): for a node that follows another node, kOS's BURNVECTOR was off by
    // 4.7 m/s (13 deg) from its own components, while the predicted orbit matched the plan exactly. So the
    // check uses what the node does to the prediction: velocity just after minus just before, minus one
    // second of the Moon's pull (the 1 s window straddles the node). BURNVECTOR is logged only.
    LOCAL t_n IS dp_nodes[i]:TIME.
    LOCAL g_vec IS -dp_pos_at(t_n):NORMALIZED * (mu / dp_pos_at(t_n):SQRMAGNITUDE).
    LOCAL dv_pred IS dp_vel_at(t_n + 0.5) - dp_vel_at(t_n - 0.5) - g_vec.
    LOCAL err_i IS (dv_pred - dp_intended[i]):MAG.
    SET burn_err TO MAX(burn_err, err_i).
    dp_log_only("  node " + i + " final: predicted dv err " + ROUND(err_i, 4) + " (|pred| " + ROUND(dv_pred:MAG, 3) + " |intended| "
        + ROUND(dp_intended[i]:MAG, 3) + "); BURNVECTOR err " + ROUND((dp_nodes[i]:BURNVECTOR - dp_intended[i]):MAG, 3)
        + " angle " + ROUND(VANG(dp_nodes[i]:BURNVECTOR, dp_intended[i]), 2) + " deg").
  }

  // ---- 5. Terrain under the descent orbit, then the full pre-check list ----------------------------------
  LOCAL terrain_min IS dp_terrain_min(t_doi, t_pdi, wm_vec).
  LOCAL first_burn IS t_doi.
  IF t_pc > 0 { SET first_burn TO t_pc. }
  LOCAL pre_all IS check_plan_pre(LEXICON("LEAD_S", first_burn - t_start, "DV_DOI", doi["DV"]:MAG, "DV_PC", dv_pc:MAG,
      "MAX_PC_DV", max_pc, "ALT_PDI", geo["ALT_PDI"], "ALT_PDI_NOM", geo["ALT_PDI"], "V_PDI", doi["V_PDI"],
      "WARP_RATE", KUNIVERSE:TIMEWARP:RATE, "NODES_OK", nodes_ok, "TERRAIN_CLEAR_MIN", terrain_min)).
  IF pre_all["ERRORS"]:LENGTH > 0 { RETURN dp_fail(pre_all["ERRORS"][0]). }

  // ---- 6. Independent post-check: kOS's own prediction at the planned PDI time ------------------------------
  LOCAL p_pdi IS dp_pos_at(t_pdi).
  LOCAL v_pdi IS dp_vel_at(t_pdi).
  LOCAL post IS check_plan_post(LEXICON(
      "ALT_PDI_PRED", p_pdi:MAG - SHIP:BODY:RADIUS, "ALT_PDI_NOM", geo["ALT_PDI"],
      "RANGE_PRED", site_radius * VANG(p_pdi, s_land) / rad_to_deg, "RANGE_NOM", ABS(RIGNZ),
      "SPEED_PRED", v_pdi:MAG, "SPEED_PLAN", doi["V_PDI"],
      "XRANGE_PRED", site_radius * ARCSIN(MAX(-1, MIN(1, VDOT(VCRS(p_pdi, v_pdi):NORMALIZED, s_land)))) / rad_to_deg,
      "BURN_ERR", burn_err)).

  // ---- 7. Report ------------------------------------------------------------------------------------------------
  dp_say("---- Plan ----").
  IF t_pc > 0 {
    dp_say("Plane change: " + dp_met(t_pc) + " (in " + ROUND(t_pc - t_start) + " s, UT " + ROUND(t_pc) + "), " + ROUND(dv_pc:MAG, 2) + " m/s, site "
           + ROUND(ABS(tilt_deg), 3) + " deg out of plane.").
  } ELSE {
    dp_say("Plane change: none needed (site within " + PLAN_XRANGE_MAX + " m of the orbit plane).").
  }
  dp_say("DOI burn: " + dp_met(t_doi) + " (in " + ROUND(t_doi - t_start) + " s, UT " + ROUND(t_doi) + "), " + ROUND(doi["DV"]:MAG, 2) + " m/s, vector "
         + doi["DV"] + ".").
  dp_say("Descent orbit: apolune " + ROUND(doi["RA"] - SHIP:BODY:RADIUS) + " m, perilune (PDI) " + ROUND(geo["ALT_PDI"]) + " m altitude.").
  dp_say("PDI at " + dp_met(t_pdi) + " (UT " + ROUND(t_pdi) + ", DOI + " + ROUND(doi["T_HALF"]) + " s), landing at UT " + ROUND(t_land) + ".").
  dp_say("Speed at PDI " + ROUND(doi["V_PDI"], 1) + " m/s against VIGN " + ROUND(VIGN, 1) + " m/s.").
  dp_say("Lowest height above terrain on the descent orbit: " + ROUND(terrain_min) + " m.").
  FOR line IN post["LINES"] { dp_say("check: " + line). }
  FOR warn IN pre_all["WARNINGS"] { dp_say("WARNING: " + warn). }
  IF NOT post["PASS"] { RETURN dp_fail("the plan did not pass the prediction check (lines above marked FAIL)."). }

  plan_write(PLAN_PLAN_FILE, LEXICON("SITE_LAT", site["LAT"], "SITE_LNG", site["LNG"], "SITE_ALT", site["ALT"],
      "T_MADE", t_start, "T_DOI", t_doi, "T_PDI", t_pdi, "T_LAND", t_land, "T_PC", t_pc, "WINDOW_MODE", P63_WINDOW_MODE,
      "DV_DOI", doi["DV"]:MAG, "DV_PC", dv_pc:MAG, "V_PDI", doi["V_PDI"], "ALT_PDI", geo["ALT_PDI"])).
  dp_say("PLAN OK. " + dp_nodes:LENGTH + " maneuver node(s) added. Plan saved to " + PLAN_PLAN_FILE + "." + (CHOOSE " Report: " + DP_LOG IF LM_LOG ELSE "")).
  LOCAL pc_text IS "no plane change".
  IF t_pc > 0 { SET pc_text TO "plane change at " + dp_met(t_pc) + ", " + ROUND(dv_pc:MAG, 1) + " m/s". }
  SET DP_SUMMARY TO LIST("PLAN OK: " + dp_nodes:LENGTH + " node(s) added. " + pc_text + ".",
                         "DOI at " + dp_met(t_doi) + ", " + ROUND(doi["DV"]:MAG, 1) + " m/s. PDI at " + dp_met(t_pdi) + ".").
  RETURN TRUE.
}

// With a latitude: plan now (command-line use). Without: stay silent, the caller (lm_plan_ui.ks) runs it.
IF in_lat <> -999 {
  deorbit_run(in_lat, in_lng, in_alt, max_pc_dv, replace).
}
