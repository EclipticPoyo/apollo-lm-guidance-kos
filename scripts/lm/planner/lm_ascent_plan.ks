// lm_ascent_plan.ks -- the ascent planner (release 1.5): the lift-off time for the flown rendezvous plan, and the ascent PAD.
//   asc_kepler_polar(r, vh, vr, mu, dt)          two-body motion: radius and angle travelled
//   asc_phase_angle(profile, r_site, r_csm, mu)  how far ahead the CSM must be at insertion
//   asc_phase_coelliptic(profile, r_site, r_csm, mu, csi_to_tpi_s)   the same for a CSI, CDH and TPI flight
//   asc_time_to_apo(r, vh, vr, mu)               seconds to the next apolune (the CSI time)
//   asc_find_liftoff(err_fn, t_from, t_span, steps)   the first time an angle error rises through zero
//   asc_plan_solve(inp)                          lift-off times, rendezvous times, insertion targets, cross-range, warnings
//   asc_pad_lines(res, info)                     the PAD text
//   ascent_plan_run(skip)                        reads the landed ship and the target, solves, saves 0:/lm/ascent.json
//   asc_csm_orbit_warnings(r_site, apo_r, pe_r)  the CSM orbit against the flown ones (also used by the deorbit planner)
//   abt_expected_lead(r_csm, r_pdi), abt_plan_check(...)   the aborts' check of where the CSM is at PDI (deorbit planner)
// Only ascent_plan_run (and asc_csm_at) read the game; everything else takes values and is tested by tests/test_ascent_plan.ks against
// scripts/tests/reference_ascent.py. The planner is a ground computation: nothing here is in Luminary.
//
// The phasing (research docs/superpowers/research-1.5-ascent.md section 10; the flown plans of TN D-7388):
//   A11, coelliptic: CSI 50 minutes after insertion makes the orbit circular; TPI 99 minutes later with the CSM 26.6 degrees above the horizontal.
//   J, short rendezvous: TPI 45 minutes after insertion in the insertion orbit; its phase angle in proportion to the height difference.
//   J's coelliptic fallback (Apollo 15 was read both): its own later lift-off to the same insertion targets, TPI 6712 s after CSI.
// The PAD's rendezvous times: CSI at the apolune of the planned insertion orbit (P32 with a keyed CSI time solves only near it; research
// features/2026-11-26-rendezvous section 17), TPI the flown interval after the 50 minute mark. They are not recomputed from the real insertion.
// All heights are above the landing-site radius.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").
RUNONCEPATH("0:/lm/planner/lm_plan.ks").            // plan_site_at, plan_phase, plan_point_ahead, plan_in_plane, plan_write, lm_profile_for
RUNONCEPATH("0:/lm/planner/lm_pad.ks").             // pad_clock_text, pad_signed5
RUNONCEPATH("0:/lm/ascent/lm_ascent_guid.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").         // ctl_find_ascent_engine

// asc_wrap180: an angle in -180 to 180 degrees.
FUNCTION asc_wrap180 {
  PARAMETER angle_deg.
  RETURN MOD(MOD(angle_deg + 180, 360) + 360, 360) - 180.
}

// asc_mean_deg: the mean anomaly (degrees) at true anomaly nu_deg for eccentricity ecc < 1.
FUNCTION asc_mean_deg {
  PARAMETER nu_deg, ecc.
  LOCAL ecc_deg IS 2 * ARCTAN2(SQRT(1 - ecc) * SIN(nu_deg / 2), SQRT(1 + ecc) * COS(nu_deg / 2)).
  RETURN ecc_deg - ecc * SIN(ecc_deg) * CONSTANT:RADTODEG.
}

// asc_kepler_polar: from radius r with horizontal speed vh and radial speed vr, the radius dt seconds later and the angle travelled (degrees, counting
// whole turns). LEXICON("R", m, "ANG", deg). A path that is not a closed orbit returns the start (it does not occur with a real insertion).
FUNCTION asc_kepler_polar {
  PARAMETER r_now, vh, vr, mu, dt.
  LOCAL energy IS (vh * vh + vr * vr) / 2 - mu / r_now.
  LOCAL semi_p IS (r_now * vh) ^ 2 / mu.
  IF energy >= 0 OR semi_p <= 0 { RETURN LEXICON("R", r_now, "ANG", 0). }
  LOCAL semi_a IS -mu / (2 * energy).
  LOCAL mean_rate IS SQRT(mu / semi_a ^ 3) * CONSTANT:RADTODEG.       // degrees per second
  LOCAL e_cos IS semi_p / r_now - 1.
  LOCAL e_sin IS vr * r_now * vh / mu.
  LOCAL ecc IS SQRT(e_cos * e_cos + e_sin * e_sin).
  IF ecc < 1e-8 { RETURN LEXICON("R", r_now, "ANG", mean_rate * dt). }
  LOCAL nu_start IS ARCTAN2(e_sin, e_cos).
  LOCAL mean_end IS asc_mean_deg(nu_start, ecc) + mean_rate * dt.
  LOCAL turns IS FLOOR((mean_end + 180) / 360).
  LOCAL mean_part IS mean_end - turns * 360.
  // Kepler's equation M = E - e sin E, solved for E by Newton's method (degrees).
  LOCAL ecc_deg IS mean_part.
  FROM { LOCAL i IS 0. } UNTIL i >= 12 STEP { SET i TO i + 1. } DO {
    SET ecc_deg TO ecc_deg - (ecc_deg - ecc * SIN(ecc_deg) * CONSTANT:RADTODEG - mean_part) / (1 - ecc * COS(ecc_deg)).
  }
  LOCAL nu_end IS 2 * ARCTAN2(SQRT(1 + ecc) * SIN(ecc_deg / 2), SQRT(1 - ecc) * COS(ecc_deg / 2)).
  RETURN LEXICON("R", semi_a * (1 - ecc * COS(ecc_deg)), "ANG", nu_end - nu_start + turns * 360).
}

// asc_apo_below: how far under the CSM's mean altitude the insertion orbit's apolune is.
FUNCTION asc_apo_below {
  PARAMETER profile.
  IF profile = "J" { RETURN ASC_APO_BELOW_J_M. }
  RETURN ASC_APO_BELOW_A11_M.
}

// asc_time_to_apo: from radius r_now with horizontal speed vh and radial speed vr, the seconds to the next apolune. -1 when the path is not an
// ellipse, or is a circle (no apolune).
FUNCTION asc_time_to_apo {
  PARAMETER r_now, vh, vr, mu.
  LOCAL energy IS (vh * vh + vr * vr) / 2 - mu / r_now.
  LOCAL semi_p IS (r_now * vh) ^ 2 / mu.
  IF energy >= 0 OR semi_p <= 0 { RETURN -1. }
  LOCAL e_cos IS semi_p / r_now - 1.
  LOCAL e_sin IS vr * r_now * vh / mu.
  LOCAL ecc IS SQRT(e_cos * e_cos + e_sin * e_sin).
  IF ecc < 1e-8 { RETURN -1. }
  LOCAL semi_a IS -mu / (2 * energy).
  LOCAL mean_rate IS SQRT(mu / semi_a ^ 3) * CONSTANT:RADTODEG.       // degrees per second
  // The apolune is at a mean anomaly of 180 degrees.
  RETURN MOD(540 - asc_mean_deg(ARCTAN2(e_sin, e_cos), ecc), 360) / mean_rate.
}

// asc_phase_coelliptic: the CSM's lead (degrees) at insertion for a flight with CSI ASC_CSI_S after insertion and TPI csi_to_tpi_s after that,
// the CSM then ASC_TPI_ELEV_DEG above the horizontal. profile picks the insertion apolune.
FUNCTION asc_phase_coelliptic {
  PARAMETER profile, r_site, r_csm, mu, csi_to_tpi_s.
  LOCAL r_ins IS r_site + ASC_HINJECT_M.
  LOCAL vh IS asc_insertion_vh(r_ins, r_csm - asc_apo_below(profile), mu, ASC_PHASE_RDOT).
  LOCAL at_csi IS asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, mu, ASC_CSI_S).
  LOCAL r_lm IS at_csi["R"].
  LOCAL travel IS at_csi["ANG"] + SQRT(mu / r_lm ^ 3) * CONSTANT:RADTODEG * csi_to_tpi_s.
  LOCAL phase_tpi IS ARCCOS(MAX(-1, MIN(1, r_lm * COS(ASC_TPI_ELEV_DEG) / r_csm))) - ASC_TPI_ELEV_DEG.
  RETURN phase_tpi + asc_wrap180(travel - SQRT(mu / r_csm ^ 3) * CONSTANT:RADTODEG * (ASC_CSI_S + csi_to_tpi_s)).
}

// asc_phase_angle: the angle (degrees) the CSM must be ahead of the LM at insertion. r_csm is the CSM's mean radius, r_site the landing-site radius.
FUNCTION asc_phase_angle {
  PARAMETER profile, r_site, r_csm, mu.
  IF profile <> "J" { RETURN asc_phase_coelliptic(profile, r_site, r_csm, mu, ASC_CSI_TO_TPI_S). }
  LOCAL r_ins IS r_site + ASC_HINJECT_M.
  LOCAL vh IS asc_insertion_vh(r_ins, r_csm - asc_apo_below(profile), mu, ASC_PHASE_RDOT).
  LOCAL at_tpi IS asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, mu, ASC_J_TPI_S).
  LOCAL phase_tpi IS ASC_J_TPI_PHASE_DEG * (r_csm - at_tpi["R"]) / ASC_J_TPI_DH_M.
  RETURN phase_tpi + asc_wrap180(at_tpi["ANG"] - SQRT(mu / r_csm ^ 3) * CONSTANT:RADTODEG * ASC_J_TPI_S).
}

// asc_find_liftoff: the first UT in [t_from, t_from + t_span] at which err_fn:CALL(t) (degrees) goes from at or below zero to above it, with both
// samples within 90 degrees (so the jump from +180 to -180 is not taken); then bisected. -1 when there is none.
FUNCTION asc_find_liftoff {
  PARAMETER err_fn, t_from, t_span, steps.
  LOCAL t_prev IS t_from.
  LOCAL err_prev IS err_fn:CALL(t_prev).
  FROM { LOCAL i IS 1. } UNTIL i > steps STEP { SET i TO i + 1. } DO {
    LOCAL t_now IS t_from + t_span * i / steps.
    LOCAL err_now IS err_fn:CALL(t_now).
    IF err_prev <= 0 AND err_now > 0 AND err_prev > -90 AND err_now < 90 {
      LOCAL lo IS t_prev.
      LOCAL hi IS t_now.
      UNTIL hi - lo < 0.005 {
        LOCAL mid IS (lo + hi) / 2.
        IF err_fn:CALL(mid) <= 0 { SET lo TO mid. } ELSE { SET hi TO mid. }
      }
      RETURN (lo + hi) / 2.
    }
    SET t_prev TO t_now.
    SET err_prev TO err_now.
  }
  RETURN -1.
}

// asc_site_dir: the landing site's direction at UT t_ut, in the orbit plane of the CSM (axes of T0).
FUNCTION asc_site_dir {
  PARAMETER ctx, t_ut.
  LOCAL site_now IS plan_site_at(ctx["SITE"], ctx["WM"], t_ut - ctx["T0"]).
  RETURN plan_in_plane(site_now:NORMALIZED, ctx["N"]).
}

// asc_lift_err: for a lift-off at t_ut, how far (degrees) the CSM at insertion is ahead of where it should be. Rises through zero at the right time.
FUNCTION asc_lift_err {
  PARAMETER ctx, t_ut.
  LOCAL ins_dir IS plan_point_ahead(ctx["N"], asc_site_dir(ctx, t_ut), ctx["ARC"]).
  RETURN asc_wrap180(plan_phase(ctx["CSM_AT"]:CALL(t_ut + ctx["BURN_S"]), ctx["N"], ins_dir) - ctx["PHASE"]).
}

// asc_over_err: the CSM's angle past the site's meridian at t_ut.
FUNCTION asc_over_err {
  PARAMETER ctx, t_ut.
  RETURN plan_phase(ctx["CSM_AT"]:CALL(t_ut), ctx["N"], asc_site_dir(ctx, t_ut)).
}

// asc_plane_y: the site's distance from the CSM plane (Luminary Y, at the target radius) at UT t_ut.
FUNCTION asc_plane_y {
  PARAMETER ctx, t_ut.
  RETURN ctx["RCO"] * VDOT(plan_site_at(ctx["SITE"], ctx["WM"], t_ut - ctx["T0"]):NORMALIZED, ctx["QAXIS"]).
}

// asc_plan_sim: our ascent for a lift-off at t_ut with the cross-plane target yco; puts BURN_S and ARC into ctx. FALSE when it does not reach orbit.
FUNCTION asc_plan_sim {
  PARAMETER ctx, inp, zdotd, t_ut, yco.
  LOCAL r0 IS plan_site_at(inp["SITE"], inp["WM"], t_ut - inp["T0"]).
  LOCAL tgt IS asc_target(ctx["RCO"], yco, ASC_PHASE_RDOT, zdotd).
  LOCAL sim IS asc_sim(inp["PROFILE"], r0, lm_cross(inp["WM"], r0), ctx["QAXIS"], inp["MU"], tgt, inp["MASS_KG"], inp["THRUST_N"], inp["VE"], ASC_SIM_DT).
  IF NOT sim["OK"] { RETURN FALSE. }
  SET ctx["BURN_S"] TO sim["BURN_S"].
  SET ctx["ARC"] TO plan_phase(sim["R_END"], ctx["N"], plan_in_plane(r0:NORMALIZED, ctx["N"])).
  RETURN TRUE.
}

FUNCTION asc_plan_fail {
  PARAMETER why.
  RETURN LEXICON("OK", FALSE, "WHY", why, "T1", -1, "T2", -1, "T_OVER", -1, "ZDOTD", 0, "RDOTD", 0, "XRANGE", 0, "LEFT_M", 0, "BURN_S", 0,
                 "PHASE", 0, "WARN", LIST(), "T_CSI", -1, "T_TPI", -1, "FB", FALSE).
}

// asc_csm_orbit_warnings: the CSM orbit against what was flown: its mean height over the site radius and how eccentric it is. A LIST of texts.
FUNCTION asc_csm_orbit_warnings {
  PARAMETER r_site, apo_r, pe_r.
  LOCAL warns IS LIST().
  LOCAL mean_nm IS ((apo_r + pe_r) / 2 - r_site) / M_PER_NM.
  IF mean_nm < ASC_CSM_MIN_NM - 0.05 OR mean_nm > ASC_CSM_MAX_NM + 0.05 {
    warns:ADD("CSM at " + ROUND(mean_nm, 1) + " nm is outside the " + ASC_CSM_MIN_NM + " to " + ASC_CSM_MAX_NM + " nm that was flown").
  }
  IF (apo_r - pe_r) / M_PER_NM > ASC_CSM_ECC_NM {
    warns:ADD("CSM apolune and perilune more than " + ASC_CSM_ECC_NM + " nm apart: not the flown rendezvous").
  }
  RETURN warns.
}

// abt_expected_lead: the CSM's lead at PDI (degrees, negative: behind) after a DOI flown beside it: both leave one point and the LM flies half of
// its descent orbit (radius r_csm to r_pdi) while the CSM, circular at r_csm, covers less than half of its own. -7 degrees for 60 nm.
FUNCTION abt_expected_lead {
  PARAMETER r_csm, r_pdi.
  RETURN 180 * ((r_csm + r_pdi) / 2 / r_csm) ^ 1.5 - 180.
}

FUNCTION abt_lead_text {
  PARAMETER lead_deg.
  RETURN ROUND(ABS(lead_deg), 1) + " deg " + (CHOOSE "behind" IF lead_deg < 0 ELSE "ahead").
}

// abt_plan_check: lead_deg the CSM's lead at PDI. A LIST of LEXICON("TEXT", line, "WARN", bool): first the lead beside the expected one; a
// warning when they differ by more than the profile's limit (Apollo 11's abort targets are timed for the expected place; J aims at it, and the
// line gives the apolune above the site an abort at PDI would target); then the orbit warnings.
FUNCTION abt_plan_check {
  PARAMETER profile, lead_deg, r_site, apo_r, pe_r, r_pdi, mu.
  LOCAL expected IS abt_expected_lead((apo_r + pe_r) / 2, r_pdi).
  LOCAL checks IS LIST(LEXICON("TEXT", "CSM at PDI: " + abt_lead_text(lead_deg) + " (a DOI flown beside it gives " + abt_lead_text(expected) + ").", "WARN", FALSE)).
  LOCAL off_deg IS ABS(asc_wrap180(lead_deg - expected)).
  IF profile = "J" {
    IF off_deg > ABT_PLAN_TOL_J_DEG {
      LOCAL aim IS abt_j_target(TRUE, lead_deg, abt_j_set(lead_deg), r_site + ASC_HINJECT_M, r_site, mu).
      checks:ADD(LEXICON("TEXT", "CSM " + ROUND(off_deg, 1) + " deg from that place: an abort at PDI would target an apolune of "
                         + ROUND((aim["RA"] - r_site) / M_PER_NM) + " nm.", "WARN", TRUE)).
    }
  } ELSE IF off_deg > ABT_PLAN_TOL_A11_DEG {
    checks:ADD(LEXICON("TEXT", "CSM " + ROUND(off_deg, 1) + " deg from that place: the abort orbit timing will be off.", "WARN", TRUE)).
  }
  FOR warn_text IN asc_csm_orbit_warnings(r_site, apo_r, pe_r) { checks:ADD(LEXICON("TEXT", warn_text + ".", "WARN", TRUE)). }
  RETURN checks.
}

// asc_plan_solve: inp is LEXICON PROFILE, SITE (vector from the Moon's centre at T0), WM, T0, MU, CSM_AT (delegate UT -> vector in the axes of T0),
// CSM_R, CSM_V (at T0), CSM_APO_R, CSM_PE_R, MASS_KG (what lifts off), THRUST_N, VE, PROP_KG (aboard the ascent stage).
// Returns LEXICON OK, WHY, T1 (the first lift-off at least ASC_LEAD_S ahead), T2 (the next), T_OVER (the CSM's overhead pass nearest T1), ZDOTD,
// RDOTD, XRANGE (to load), LEFT_M (cross-range the load leaves), BURN_S, PHASE, WARN (LIST of texts), T_CSI (UT; -1 on J, whose direct flight
// has no CSI), T_TPI (UT), FB (FALSE, or on J the coelliptic fallback: LEXICON T1, T_CSI, T_TPI, all UT).
FUNCTION asc_plan_solve {
  PARAMETER inp.
  LOCAL mu IS inp["MU"].
  LOCAL r_site IS inp["SITE"]:MAG.
  LOCAL r_csm IS (inp["CSM_APO_R"] + inp["CSM_PE_R"]) / 2.
  LOCAL r_ins IS r_site + ASC_HINJECT_M.
  LOCAL zdotd IS asc_insertion_vh(r_ins, r_csm - asc_apo_below(inp["PROFILE"]), mu, ASC_PHASE_RDOT).
  IF zdotd <= 0 { RETURN asc_plan_fail("the CSM orbit is too low for an ascent to rendezvous below it"). }
  LOCAL ctx IS LEXICON("SITE", inp["SITE"], "WM", inp["WM"], "T0", inp["T0"], "CSM_AT", inp["CSM_AT"], "RCO", r_ins,
                       "N", VCRS(inp["CSM_R"], inp["CSM_V"]):NORMALIZED, "QAXIS", asc_qaxis(inp["CSM_R"], inp["CSM_V"]), "BURN_S", 0, "ARC", 0, "PHASE", 0).
  LOCAL t_first IS inp["T0"] + ASC_LEAD_S.
  IF ABS(asc_plane_y(ctx, t_first)) > r_ins * SIN(ASC_PLANE_MAX_DEG) { RETURN asc_plan_fail("the site is too far from the CSM orbit plane"). }
  SET ctx["PHASE"] TO asc_phase_angle(inp["PROFILE"], r_site, r_csm, mu).
  LOCAL period IS 2 * CONSTANT:PI * SQRT(r_csm ^ 3 / mu).
  LOCAL no_orbit IS "the ascent does not reach orbit (check the thrust and the propellant)".
  // First pass without cross-range, then once more with the cross-plane target P12 will have at that time.
  IF NOT asc_plan_sim(ctx, inp, zdotd, t_first, asc_plane_y(ctx, t_first)) { RETURN asc_plan_fail(no_orbit). }
  LOCAL err_d IS asc_lift_err@:BIND(ctx).
  LOCAL t_one IS asc_find_liftoff(err_d, t_first, 1.5 * period, 72).
  IF t_one < 0 { RETURN asc_plan_fail("no lift-off time was found"). }
  LOCAL y_one IS asc_plane_y(ctx, t_one).
  LOCAL x_range IS MAX(-ASC_XRANGE_PAD_M, MIN(ASC_XRANGE_PAD_M, -y_one)).
  IF NOT asc_plan_sim(ctx, inp, zdotd, t_one, y_one + x_range) { RETURN asc_plan_fail(no_orbit). }
  SET t_one TO asc_find_liftoff(err_d, t_first, 1.5 * period, 72).
  IF t_one < 0 { RETURN asc_plan_fail("no lift-off time was found"). }
  LOCAL t_two IS asc_find_liftoff(err_d, t_one + ASC_LEAD_S, 1.5 * period, 72).
  LOCAL over_d IS asc_over_err@:BIND(ctx).
  LOCAL t_over IS asc_find_liftoff(over_d, t_one - period / 2, period, 48).
  IF t_over < 0 { SET t_over TO asc_find_liftoff(over_d, t_one - period, 2 * period, 96). }
  SET y_one TO asc_plane_y(ctx, t_one).
  SET x_range TO MAX(-ASC_XRANGE_PAD_M, MIN(ASC_XRANGE_PAD_M, -y_one)).
  LOCAL left_m IS y_one + x_range.
  IF ABS(left_m) < 0.5 { SET left_m TO 0. }

  LOCAL warns IS asc_csm_orbit_warnings(r_site, inp["CSM_APO_R"], inp["CSM_PE_R"]).
  IF left_m <> 0 { warns:ADD("cross-range over " + ROUND(ASC_XRANGE_PAD_M / M_PER_NM) + " nm: " + ROUND(ABS(left_m) / M_PER_NM, 1) + " nm left for the rendezvous"). }
  LOCAL need_kg IS inp["THRUST_N"] / inp["VE"] * ctx["BURN_S"] + ASC_RCS_MARGIN_KG.
  IF inp["PROP_KG"] < need_kg { warns:ADD("propellant: about " + ROUND(need_kg) + " kg needed, " + ROUND(inp["PROP_KG"]) + " kg aboard"). }

  // The rendezvous times, from the planned insertion (lift-off plus the burn).
  LOCAL phase_main IS ctx["PHASE"].
  LOCAL ins_s IS ctx["BURN_S"].
  LOCAL apo_s IS asc_time_to_apo(r_ins, zdotd, ASC_PHASE_RDOT, mu).
  IF apo_s < 0 { SET apo_s TO ASC_CSI_S. }
  LOCAL t_csi IS t_one + ins_s + apo_s.
  LOCAL t_tpi IS t_one + ins_s + ASC_CSI_S + ASC_CSI_TO_TPI_S.
  LOCAL fallback IS FALSE.
  IF inp["PROFILE"] = "J" {
    SET t_csi TO -1.
    SET t_tpi TO t_one + ins_s + ASC_J_TPI_S.
    // The coelliptic fallback: the first later lift-off for its own phase angle, to the same insertion targets and cross-range load.
    SET ctx["PHASE"] TO asc_phase_coelliptic("J", r_site, r_csm, mu, ASC_J_FB_CSI_TO_TPI_S).
    LOCAL t_fb IS asc_find_liftoff(err_d, t_one, 1.5 * period, 72).
    IF t_fb < 0 {
      warns:ADD("no coelliptic fallback lift-off was found").
    } ELSE {
      SET fallback TO LEXICON("T1", t_fb, "T_CSI", t_fb + ins_s + apo_s, "T_TPI", t_fb + ins_s + ASC_CSI_S + ASC_J_FB_CSI_TO_TPI_S).
    }
  }

  RETURN LEXICON("OK", TRUE, "WHY", "", "T1", t_one, "T2", t_two, "T_OVER", t_over, "ZDOTD", zdotd, "RDOTD", ASC_PHASE_RDOT, "XRANGE", x_range,
                 "LEFT_M", left_m, "BURN_S", ins_s, "PHASE", phase_main, "WARN", warns, "T_CSI", t_csi, "T_TPI", t_tpi, "FB", fallback).
}

// asc_pad_key: the keys that load seconds (since the clock zero) into a time noun (N33, N11 or N37).
FUNCTION asc_pad_key {
  PARAMETER noun_no, seconds.
  LOCAL hms IS lm_hms_cs(seconds).
  RETURN "  V25 N" + noun_no + " E " + pad_signed5(hms[0]) + " E " + pad_signed5(hms[1]) + " E " + pad_signed5(hms[2]) + " E".
}

// asc_pad_times: adds a flight's CSI (none when times["T_CSI"] is negative) and TPI times, with their keys, to the PAD lines.
FUNCTION asc_pad_times {
  PARAMETER lines, times, zero_ut.
  IF times["T_CSI"] >= 0 {
    lines:ADD("CSI  " + pad_clock_text(times["T_CSI"] - zero_ut) + "   key at the N11 of P32").
    lines:ADD(asc_pad_key(11, times["T_CSI"] - zero_ut)).
  }
  lines:ADD("TPI  " + pad_clock_text(times["T_TPI"] - zero_ut) + "   key at the N37").
  lines:ADD(asc_pad_key(37, times["T_TPI"] - zero_ut)).
}

// asc_pad_lines: the PAD text. info is LEXICON CSM (name), APO_NM, PERI_NM, PROFILE, CLOCK_ZERO. The loads are keyed, as the crew keyed them.
FUNCTION asc_pad_lines {
  PARAMETER res, info.
  LOCAL zero_ut IS info["CLOCK_ZERO"].
  LOCAL lines IS LIST().
  lines:ADD("ASCENT PAD " + (CHOOSE "LUMINARY210" IF info["PROFILE"] = "J" ELSE "LUMINARY099") + "     CLOCK ZERO UT " + ROUND(zero_ut)).
  lines:ADD("CSM " + info["CSM"] + "   " + info["APO_NM"] + " x " + info["PERI_NM"] + " nm").
  lines:ADD("").
  lines:ADD("LIFT-OFF (TIG)  " + pad_clock_text(res["T1"] - zero_ut) + "   key at the N33 of P12").
  lines:ADD(asc_pad_key(33, res["T1"] - zero_ut)).
  lines:ADD("INSERTION  horizontal ft/s, radial ft/s, cross-range nm   key at the N76").
  lines:ADD("  V25 N76 E " + pad_signed5(ROUND(res["ZDOTD"] * FT_PER_M * 10)) + " E " + pad_signed5(ROUND(res["RDOTD"] * FT_PER_M * 10))
            + " E " + pad_signed5(ROUND(res["XRANGE"] / M_PER_NM * 10)) + " E").
  asc_pad_times(lines, res, zero_ut).
  IF res["FB"]:ISTYPE("Lexicon") {
    LOCAL fb IS res["FB"].
    lines:ADD("").
    lines:ADD("COELLIPTIC FALLBACK (use instead of the above)").
    lines:ADD("LIFT-OFF  " + pad_clock_text(fb["T1"] - zero_ut) + "   key at the N33 of P12").
    lines:ADD(asc_pad_key(33, fb["T1"] - zero_ut)).
    asc_pad_times(lines, fb, zero_ut).
  }
  lines:ADD("").
  lines:ADD("CSM OVERHEAD  " + pad_clock_text(res["T_OVER"] - zero_ut)).
  IF res["LEFT_M"] <> 0 { lines:ADD("CROSS-RANGE LEFT OVER  " + ROUND(ABS(res["LEFT_M"]) / M_PER_NM, 1) + " nm"). }
  IF res["T2"] >= 0 { lines:ADD("NEXT LIFT-OFF  " + pad_clock_text(res["T2"] - zero_ut)). }
  FOR warn_text IN res["WARN"] { lines:ADD("WARNING: " + warn_text). }
  RETURN lines.
}

// asc_csm_at: the target's predicted position from the Moon's centre at UT t_ut, turned back into the axes of t0 (the raw axes turn with the Moon).
FUNCTION asc_csm_at {
  PARAMETER csm_vessel, wm_vec, t0, t_ut.
  RETURN plan_spin_rotate(POSITIONAT(csm_vessel, t_ut) - SHIP:BODY:POSITION, wm_vec, TIME:SECONDS - t0).
}

// asc_plan_refusal: why the ascent cannot be planned, or "". status is the ship's status, has_target whether a vessel is targeted, target_body the
// name of the body it is at, engine_found whether there is an ascent engine.
FUNCTION asc_plan_refusal {
  PARAMETER status_text, has_target, target_body, engine_found.
  IF status_text <> "LANDED" { RETURN "the ship is " + status_text + ", not LANDED". }
  IF NOT has_target { RETURN "target the CSM first (no vessel is targeted)". }
  IF target_body <> BODY_NAME { RETURN "the target is not at the " + BODY_NAME. }
  IF NOT engine_found { RETURN "no ascent engine found (an engine that is never decoupled)". }
  RETURN "".
}

// ascent_plan_run: plan the ascent of this landed ship to the targeted CSM. skip: "Skip simulated uplink" was ticked (P12 then loads TIG, N76 and
// the rendezvous times N11 and N37 from the plan). Returns LEXICON OK, WHY, LINES (the PAD), WARN. The plan file is written only on success. The erasable store is not touched.
FUNCTION ascent_plan_run {
  PARAMETER skip.
  LOCAL out IS LEXICON("OK", FALSE, "WHY", "", "LINES", LIST(), "WARN", LIST()).
  IF SHIP:BODY:NAME <> BODY_NAME { SET out["WHY"] TO "this ship is not at the " + BODY_NAME. RETURN out. }
  LOCAL csm_vessel IS FALSE.
  IF HASTARGET { IF TARGET:ISTYPE("Vessel") { SET csm_vessel TO TARGET. } }
  LOCAL has_csm IS csm_vessel:ISTYPE("Vessel").
  LOCAL csm_body IS "".
  IF has_csm { SET csm_body TO csm_vessel:BODY:NAME. }
  LOCAL eng IS ctl_find_ascent_engine().
  LOCAL why IS asc_plan_refusal(SHIP:STATUS, has_csm, csm_body, eng:ISTYPE("Engine")).
  IF why <> "" { SET out["WHY"] TO why. RETURN out. }
  IF csm_vessel:STATUS <> "ORBITING" { SET out["WHY"] TO csm_vessel:NAME + " is not in orbit". RETURN out. }
  IF NOT CAREER():CANMAKENODES { SET out["WHY"] TO "orbit prediction is not available (career: upgrade the Tracking Station)". RETURN out. }
  IF KUNIVERSE:TIMEWARP:RATE > 1 { SET out["WHY"] TO "time warp is running: stop it and plan again". RETURN out. }

  LOCAL old_ipu IS CONFIG:IPU.
  SET CONFIG:IPU TO 2000.
  // The stage that lifts off: the parts that are never decoupled. Its propellant is shared by the engine and the RCS.
  LOCAL mass_kg IS 0.
  LOCAL prop_kg IS 0.
  FOR ship_part IN SHIP:PARTS {
    IF ship_part:DECOUPLEDIN < 0 {
      SET mass_kg TO mass_kg + ship_part:MASS * 1000.
      FOR res_item IN ship_part:RESOURCES {
        IF res_item:NAME = "Aerozine50" OR res_item:NAME = "MON1" { SET prop_kg TO prop_kg + res_item:AMOUNT * res_item:DENSITY * 1000. }
      }
    }
  }
  LOCAL profile IS lm_profile_for(plan_read(PLAN_PLAN_FILE)).
  LOCAL t0 IS TIME:SECONDS.
  LOCAL wm_vec IS moon_spin().
  LOCAL body_r IS SHIP:BODY:RADIUS.
  LOCAL inp IS LEXICON("PROFILE", profile, "SITE", -SHIP:BODY:POSITION, "WM", wm_vec, "T0", t0, "MU", SHIP:BODY:MU,
                       "CSM_AT", asc_csm_at@:BIND(csm_vessel, wm_vec, t0), "CSM_R", csm_vessel:POSITION - SHIP:BODY:POSITION,
                       "CSM_V", csm_vessel:VELOCITY:ORBIT, "CSM_APO_R", csm_vessel:ORBIT:APOAPSIS + body_r,
                       "CSM_PE_R", csm_vessel:ORBIT:PERIAPSIS + body_r, "MASS_KG", mass_kg, "THRUST_N", eng:POSSIBLETHRUSTAT(0) * 1000,
                       "VE", eng:VACUUMISP * CONSTANT:G0, "PROP_KG", prop_kg).
  LOCAL res IS asc_plan_solve(inp).
  SET CONFIG:IPU TO old_ipu.
  IF NOT res["OK"] { SET out["WHY"] TO res["WHY"]. RETURN out. }

  // The AGC clock: keep a saved zero (the DSKY and the descent PAD use it), else save this vessel's own, before the separation restarts it.
  IF NOT EXISTS(LM_CLOCK_FILE) { lm_clock_zero_save(lm_clock_zero_now()). }
  LOCAL zero_ut IS lm_clock_zero_ut().
  LOCAL r_site IS inp["SITE"]:MAG.
  LOCAL info IS LEXICON("CSM", csm_vessel:NAME, "APO_NM", ROUND((inp["CSM_APO_R"] - r_site) / M_PER_NM, 1),
                        "PERI_NM", ROUND((inp["CSM_PE_R"] - r_site) / M_PER_NM, 1), "PROFILE", profile, "CLOCK_ZERO", zero_ut).
  plan_write(ASC_PLAN_FILE, LEXICON("CSM", csm_vessel:NAME, "T_TIG", res["T1"], "ZDOTD", res["ZDOTD"], "RDOTD", res["RDOTD"],
                                    "XRANGE", res["XRANGE"], "SKIP", skip, "T_MADE", t0, "PHASE", res["PHASE"],
                                    "T_CSI", res["T_CSI"], "T_TPI", res["T_TPI"])).
  SET out["OK"] TO TRUE.
  SET out["LINES"] TO asc_pad_lines(res, info).
  SET out["WARN"] TO res["WARN"].
  RETURN out.
}
