// rndz_setup.ks -- session helper for the rendezvous tests: what P32 will see, and the times to key.
//   RUNPATH("0:/tests/rndz_setup.ks").   (the stub: RUN rdzset.)   Log: 0:/lm/logs/rndz_setup.log, added to by each run.
// It only reads and prints: nothing is stored, loaded, steered or fired. Fly the LM in lunar orbit, with the CSM in lunar orbit (targeted, or named in
// the ascent plan), and run it with the DSKY closed (the terminal runs one program at a time).
// It prints both orbits; the next apolune as the N11 keys; the CSM's phase angle then; a TPI time as the N37 keys, with the CSM's mean anomaly change
// that makes it usable when it is not; and, once p32.log holds a P33 solution whose TPI time is ahead, the height difference now and the elevation
// angle predicted at TPI (assuming no burn before then). Both craft are read as P32 and P33 read them (lm_rndz_snapshot).
// For P34 and P35 (stage 2) it also prints: the next TPI time with the CSM 26.6 degrees up, a TPI time for a short rendezvous (about 70 ft/s), the range
// and closing speed now, and, once the DSKY store (saved when the DSKY is closed) holds an intercept time, how far apart the craft will be then.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").            // lm_rndz_snapshot, and with it P32 (p32_prepare), the cells and the maths
RUNONCEPATH("0:/lm/planner/lm_pad.ks").        // pad_signed5

GLOBAL RDS_LOG IS "0:/lm/logs/rndz_setup.log".
GLOBAL RDS_SPAN_MIN IS 4500.       // s, CSI to TPI: the usable range
GLOBAL RDS_SPAN_MAX IS 9000.
GLOBAL RDS_SPAN_AIM IS 5800.       // s, the span of the pad cases (a CSM about 8.4 degrees ahead from a 9 x 45 nmi orbit under a 111 km one)

FUNCTION rds_say {
  PARAMETER text.
  PRINT text.
  LOG text TO RDS_LOG.
}

// rds_keys: a time in seconds since the AGC clock zero, as the three register entries of N11 or N37.
FUNCTION rds_keys {
  PARAMETER clock_s.
  LOCAL parts IS lm_hms_cs(clock_s).
  RETURN "R1 " + pad_signed5(parts[0]) + " (hours)  R2 " + pad_signed5(parts[1]) + " (minutes)  R3 " + pad_signed5(parts[2]) + " (seconds x 100)".
}

FUNCTION rds_orbit {
  PARAMETER label, pos_vec, vel_vec, mu_val.
  LOCAL el IS conic_elements(pos_vec, vel_vec, mu_val).
  IF el["ECC"] >= 1 { rds_say(label + ": not a closed orbit."). RETURN. }
  LOCAL apo_m IS el["P"] / (1 - el["ECC"]) - SHIP:BODY:RADIUS.
  LOCAL peri_m IS el["P"] / (1 + el["ECC"]) - SHIP:BODY:RADIUS.
  rds_say(label + ": apolune " + ROUND(apo_m / M_PER_NM, 1) + " nmi (" + ROUND(apo_m / 1000, 1) + " km), perilune "
      + ROUND(peri_m / M_PER_NM, 1) + " nmi (" + ROUND(peri_m / 1000, 1) + " km)").
}

// rds_suggest: sections 2 to 4. theta is the angle the CSM leads by when it stands the elevation angle above the LM's horizon, with the LM circular at its
// apolune height (the triangle Moon centre, LM, CSM); close_dps is how fast that lead shrinks. The TPI time is when the lead has come down from the phase at CSI.
FUNCTION rds_suggest {
  PARAMETER seen, clock_zero.
  LOCAL mu_val IS seen["MU"].
  LOCAL ahead_s IS conic_time_to_apo(seen["R"], seen["V"], mu_val).
  IF ahead_s < 0 { rds_say("No apolune: the LM is not in a closed orbit."). RETURN. }
  LOCAL tcsi_ut IS seen["T"] + ahead_s.
  LOCAL tcsi_s IS tcsi_ut - clock_zero.
  rds_say("Next LM apolune in " + FLOOR(ahead_s / 60) + " min " + FLOOR(MOD(ahead_s, 60)) + " s. As N11 (CSI time):").
  rds_say("  " + rds_keys(tcsi_s)).

  LOCAL ready IS p32_prepare(seen, tcsi_ut).
  IF NOT ready["OK"] { rds_say("The orbits cannot be carried to that apolune."). RETURN. }
  LOCAL lm_pos IS ready["R1"].
  LOCAL csm_pos IS ready["RT"].
  LOCAL phase_deg IS ARCTAN2(VDOT(csm_pos, rndz_fwd(ready["NRM"], lm_pos)), VDOT(csm_pos, lm_pos:NORMALIZED)).
  rds_say("Phase angle then: " + ROUND(phase_deg, 2) + " deg (positive: CSM ahead)").

  LOCAL r_lm IS lm_pos:MAG.
  LOCAL r_csm IS csm_pos:MAG.
  IF r_lm >= r_csm { rds_say("No TPI time: the LM's apolune is not below the CSM."). RETURN. }
  LOCAL theta_deg IS ARCCOS(MAX(-1, MIN(1, COS(P32_ELEV_DEG) * r_lm / r_csm))) - P32_ELEV_DEG.
  LOCAL close_dps IS (SQRT(mu_val / r_lm ^ 3) - SQRT(mu_val / r_csm ^ 3)) * CONSTANT:RADTODEG.
  LOCAL span_s IS (phase_deg - theta_deg) / close_dps.
  IF span_s >= RDS_SPAN_MIN AND span_s <= RDS_SPAN_MAX {
    rds_say("USABLE. TPI " + ROUND(span_s / 60, 1) + " min after CSI. As N37 (TPI time):").
    rds_say("  " + rds_keys(tcsi_s + span_s)).
  } ELSE {
    LOCAL change_deg IS theta_deg + close_dps * RDS_SPAN_AIM - phase_deg.
    SET change_deg TO MOD(MOD(change_deg + 180, 360) + 360, 360) - 180.
    rds_say("NOT USABLE. The phase angle at CSI must be " + ROUND(theta_deg + close_dps * RDS_SPAN_MIN, 2) + " to "
        + ROUND(theta_deg + close_dps * RDS_SPAN_MAX, 2) + " deg.").
    rds_say("  Add " + ROUND(change_deg, 2) + " deg (" + ROUND(change_deg * CONSTANT:DEGTORAD, 4)
        + " rad) to the CSM's mean anomaly, same epoch.").
  }
}

// rds_last_p33: the last P33 line of p32.log that is not later than now_ut (a quickload goes back in time), as LEXICON("UT", "TTPI" seconds on the AGC
// clock after the line's TPI change, "ELEV" degrees), or FALSE. The line's layout is p33_log's (lm_p32.ks).
FUNCTION rds_last_p33 {
  PARAMETER now_ut.
  LOCAL found IS FALSE.
  IF NOT EXISTS(P32_LOG_PATH) { RETURN found. }
  LOCAL text_rows IS OPEN(P32_LOG_PATH):READALL:STRING:SPLIT(CHAR(10)).
  FOR text_row IN text_rows {
    IF text_row:STARTSWITH("P33 UT ") {
      LOCAL parts IS text_row:TRIM:SPLIT(", ").
      LOCAL ut_words IS parts[0]:SPLIT(" ").
      LOCAL tpi_words IS parts[2]:SPLIT(" ").
      LOCAL elev_words IS parts[3]:SPLIT(" ").
      LOCAL last_words IS parts[parts:LENGTH - 1]:SPLIT(" ").
      LOCAL line_ut IS ut_words[2]:TONUMBER(-1).
      LOCAL ttpi_s IS tpi_words[1]:TONUMBER(-1).
      IF last_words[0] = "TPI" { SET ttpi_s TO ttpi_s + last_words[2]:TONUMBER(0). }
      IF line_ut >= 0 AND line_ut <= now_ut { SET found TO LEXICON("UT", line_ut, "TTPI", ttpi_s, "ELEV", elev_words[1]:TONUMBER(P32_ELEV_DEG)). }
    }
  }
  RETURN found.
}

// rds_after_cdh: section 5. Both craft turned into the CSM's plane as P33 does.
FUNCTION rds_after_cdh {
  PARAMETER seen, clock_zero.
  LOCAL solution IS rds_last_p33(seen["T"]).
  IF NOT solution:ISTYPE("Lexicon") { RETURN. }
  LOCAL tpi_ut IS clock_zero + solution["TTPI"].
  IF tpi_ut <= seen["T"] { RETURN. }
  rds_say("P33 solution of UT " + ROUND(solution["UT"], 1) + ", TPI in " + ROUND((tpi_ut - seen["T"]) / 60, 1) + " min:").
  LOCAL here IS p32_prepare(seen, seen["T"]).
  LOCAL later IS p32_prepare(seen, tpi_ut).
  IF NOT here["OK"] OR NOT later["OK"] { rds_say("  The orbits cannot be carried to the TPI time."). RETURN. }
  LOCAL man IS rndz_cdh(here["R1"], here["V1"], here["RT"], here["VT"], here["NRM"], seen["MU"]).
  IF man["OK"] {
    rds_say("  Height difference now " + ROUND(man["DH"] / M_PER_NM, 2) + " nmi (positive: CSM higher), as N75 R1.").
  }
  rds_say("  Elevation angle predicted at TPI " + ROUND(rndz_elevation(later["R1"], later["V1"], later["RT"]), 2) + " deg (wanted "
      + ROUND(solution["ELEV"], 2) + "), with no further burn.").
}

GLOBAL RDS_SHORT_FPS IS 70.        // ft/s, the TPI size the short-rendezvous suggestion aims for
GLOBAL RDS_MIN_PERI_M IS 25000.    // m, no suggested transfer dips below this

// rds_transfer: what P34 would make of a TPI at ut: LEXICON("OK", "DV" and "TPF" in ft/s, "PERI" m above the mean radius, "ELEV" degrees).
FUNCTION rds_transfer {
  PARAMETER seen, ut.
  LOCAL failed IS LEXICON("OK", FALSE).
  LOCAL at_tpi IS p34_states(seen, ut).
  IF NOT at_tpi["OK"] { RETURN failed. }
  LOCAL span_s IS conic_time_theta(at_tpi["RT"], at_tpi["VT"], P34_CENTANG_DEG, seen["MU"]).
  IF span_s <= 0 { RETURN failed. }
  LOCAL xf IS rndz_transfer(at_tpi["RA"], at_tpi["VA"], at_tpi["RT"], at_tpi["VT"], span_s, seen["MU"]).
  IF NOT xf["OK"] { RETURN failed. }
  RETURN LEXICON("OK", TRUE, "DV", ms_to_fps(xf["DV"]:MAG), "TPF", ms_to_fps(xf["DVTPF"]),
                 "PERI", p30_apsides(at_tpi["RA"], at_tpi["VA"], xf["DV"], seen["MU"], SHIP:BODY:RADIUS)["PERI_M"],
                 "ELEV", rndz_elevation(at_tpi["RA"], at_tpi["VA"], at_tpi["RT"])).
}

FUNCTION rds_tpi_lines {
  PARAMETER seen, clock_zero, ut.
  LOCAL res IS rds_transfer(seen, ut).
  rds_say("  TPI in " + ROUND((ut - seen["T"]) / 60, 1) + " min. As N37 (TPI time):").
  rds_say("  " + rds_keys(ut - clock_zero)).
  IF res["OK"] {
    rds_say("  Elevation " + ROUND(res["ELEV"], 2) + " deg, TPI " + ROUND(res["DV"], 1) + " ft/s, intercept " + ROUND(res["TPF"], 1)
        + " ft/s, perilune after TPI " + ROUND(res["PERI"] / M_PER_NM, 1) + " nmi (as N58).").
  }
}

// rds_coelliptic: the first time from 5 minutes ahead, within 3 hours, when the CSM climbs through 26.6 degrees above the LM's horizon.
FUNCTION rds_coelliptic {
  PARAMETER seen, clock_zero.
  rds_say("-- TPI with the CSM " + P32_ELEV_DEG + " deg up (P34, elevation keyed):").
  LOCAL ut IS seen["T"] + 300.
  LOCAL before IS 999.
  UNTIL ut > seen["T"] + 10800 {
    LOCAL at_ut IS p34_states(seen, ut).
    IF NOT at_ut["OK"] { BREAK. }
    LOCAL angle IS rndz_elevation(at_ut["RA"], at_ut["VA"], at_ut["RT"]).
    IF before < P32_ELEV_DEG AND angle >= P32_ELEV_DEG AND angle < 90 {
      LOCAL found IS rndz_tpi_time(at_ut["RA"], at_ut["VA"], at_ut["RT"], at_ut["VT"], P32_ELEV_DEG, seen["MU"]).
      IF found["OK"] { rds_tpi_lines(seen, clock_zero, ut + found["DT"]). RETURN. }
    }
    SET before TO angle.
    SET ut TO ut + 60.
  }
  rds_say("  Not in the next 3 hours (the CSM is not ahead and above, or is too far).").
}

// rds_short: of the times 8 to 60 minutes ahead, the one whose transfer is nearest RDS_SHORT_FPS (40 to 120 ft/s, a safe perilune).
FUNCTION rds_short {
  PARAMETER seen, clock_zero.
  rds_say("-- Short rendezvous TPI (P34, elevation zero), near " + RDS_SHORT_FPS + " ft/s:").
  LOCAL best_ut IS -1.
  LOCAL best_gap IS 1000.
  LOCAL ut IS seen["T"] + 480.
  UNTIL ut > seen["T"] + 3600 {
    LOCAL res IS rds_transfer(seen, ut).
    IF res["OK"] {
      IF res["DV"] >= 40 AND res["DV"] <= 120 AND res["PERI"] >= RDS_MIN_PERI_M AND ABS(res["DV"] - RDS_SHORT_FPS) < best_gap {
        SET best_gap TO ABS(res["DV"] - RDS_SHORT_FPS).
        SET best_ut TO ut.
      }
    }
    SET ut TO ut + 60.
  }
  IF best_ut < 0 { rds_say("  None in the next hour."). RETURN. }
  rds_tpi_lines(seen, clock_zero, best_ut).
}

// rds_intercept: the range now, and how far apart the craft will be at the stored intercept time with no further burn.
FUNCTION rds_intercept {
  PARAMETER seen, clock_zero, vault.
  LOCAL rel_pos IS seen["RT"] - seen["R"].
  LOCAL rel_vel IS seen["VT"] - seen["V"].
  rds_say("-- Range now " + ROUND(rel_pos:MAG / 1000, 3) + " km (" + ROUND(rel_pos:MAG / M_PER_NM, 2) + " nmi), closing "
      + ROUND(ms_to_fps(-VDOT(rel_pos, rel_vel) / rel_pos:MAG), 1) + " ft/s.").
  LOCAL tpass_s IS lm_store_get_time(vault, "TPASS4").
  IF tpass_s < 0 { rds_say("  No intercept time stored (run P34, then close the DSKY)."). RETURN. }
  LOCAL ahead_s IS clock_zero + tpass_s - seen["T"].
  IF ahead_s <= 0 { rds_say("  The stored intercept time passed " + ROUND(-ahead_s / 60, 1) + " min ago."). RETURN. }
  LOCAL at_end IS p34_states(seen, clock_zero + tpass_s).
  IF NOT at_end["OK"] { rds_say("  The orbits cannot be carried to the intercept."). RETURN. }
  rds_say("  Intercept in " + ROUND(ahead_s / 60, 1) + " min: predicted miss " + ROUND((at_end["RT"] - at_end["RA"]):MAG) + " m with no further burn.").
}

FUNCTION rds_main {
  SET CONFIG:IPU TO 2000.
  // The DSKY store as saved when the DSKY was last closed: the intercept time (and the landing-site radius, for the snapshot).
  LOCAL profile IS lm_profile_for(plan_read(PLAN_PLAN_FILE)).
  SET LM_VEH["STORE"] TO store_new(lm_cells_for(profile)).
  store_restore(LM_VEH["STORE"], LM_STORE_FILE, profile).
  LOCAL seen IS lm_rndz_snapshot().
  IF NOT seen["OK"] { rds_say("== " + seen["WHY"]). RETURN. }
  LOCAL clock_zero IS lm_clock_zero_ut().
  rds_say("== rendezvous setup, UT " + ROUND(seen["T"], 1) + ", AGC clock " + ROUND(seen["T"] - clock_zero, 1) + " s").
  rds_orbit("LM ", seen["R"], seen["V"], seen["MU"]).
  rds_orbit("CSM", seen["RT"], seen["VT"], seen["MU"]).
  rds_suggest(seen, clock_zero).
  rds_after_cdh(seen, clock_zero).
  rds_coelliptic(seen, clock_zero).
  rds_short(seen, clock_zero).
  rds_intercept(seen, clock_zero, LM_VEH["STORE"]).
  rds_say("== done").
}

rds_main().
