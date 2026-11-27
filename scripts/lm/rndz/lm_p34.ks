// lm_p34.ks -- P34, transfer phase initiation (TPI) targeting, and P35, midcourse (TPM) targeting (release 1.5, stage 2).
//   p34_start(prev, vault, clock_zero, profile, now_ut, snap)   the programme state, or a LEXICON with "REFUSED" holding the reason
//   p34_step(prog, ks)                                          one cycle; returns the programme output keys the DSKY core reads
//   p34_end(prog)                                               nothing to give back
//   p35_start, p35_step, p35_end                                the same for P35
//
// Source: Luminary 210 P34-P35,_P74-P75.agc: P34 (lines 199-324: the TPI time, NN, elevation and central angle, S33/34.1 with alarm 611, the intercept
// time from the central angle, then N58, N81 and N45), P35 (lines 436-466: TIG = now + ATIGINC, the transfer to the saved intercept time), S34/35.2 to
// S34/35.5 (lines 697-917), VN1645 (932-987). The maths is lm_rndz.ks.
//
// snap is P32's (lm_p32.ks): both craft at one instant. The result P40, P41 and P42 read is LM_VEH["XDELV"] with an aim point in it
// (rndz_aim_xdelv): they steer on the velocity that still reaches that point at the intercept time, not on a fixed delta-V.
//
// The A11 profile (Luminary 099) differs: the TPI elevation angle is kept from last time instead of zeroed, N81 comes only with the final
// computation, and V06 N59 (the delta-V along the line of sight) flashes after it on every pass.
//
// Departures:
//   * The CSM is read where it is; no tracking marks (N45 R1 is always zero) and no precision offset passes (NN is shown and does nothing).
//   * A TPI time already past returns to V06 N37 with a message. A keyed change at the second V06 N37 is used (Luminary would pair it with the
//     states found at the old time).
//   * A transfer with no solution shows alarm 20607 (Luminary's conic abort) and ends the programme; Luminary does not test for it.
//   * P35 uses 180 s from now to TIG in both profiles, and refuses with no intercept time beyond that.
//   * Every solution is logged to 0:/lm/logs/p34.log.

RUNONCEPATH("0:/lm/rndz/lm_p32.ks").            // rndz_lv, p32_lost, P32_ELEV_DEG, and what P32 loads (cells, frames, p30_mga, resp_read, lm_rndz.ks)

GLOBAL P34_LOG_PATH IS "0:/lm/logs/p34.log".    // appended to, one line per solution; the pad test points it elsewhere
GLOBAL P34_CENTANG_DEG IS 130.                  // the CSM's central angle from TPI to the intercept, as P34 loads it
GLOBAL P34_NO_TIME IS 611.                      // no TPI time found for the elevation angle
GLOBAL RNDZ_MID_LEAD_S IS 180.                  // Luminary ATIGINC: from P35's computation to its TIG, s

// rndz_aim_xdelv: the burn as an aim point (Luminary clears XDELVFLG and leaves RTARG and TPASS4). dv_vec is the delta-V at TIG, for the displays
// and the first attitude; pos_burn and vel_burn the LM at TIG; aim_vec the point to reach at tpass_ut; rotated: the targeting turned it into the
// LM's plane. All vectors are in the axes of the mark ax.
FUNCTION rndz_aim_xdelv {
  PARAMETER dv_vec, pos_burn, vel_burn, aim_vec, tpass_ut, rotated, tig_ut, ax.
  RETURN LEXICON("DELVSIN", dv_vec, "RTIG", pos_burn, "VTIG", vel_burn, "UT_TIG", tig_ut, "DELVSAB", dv_vec:MAG, "AX0", ax,
                 "AIM", LEXICON("R", aim_vec, "UT", tpass_ut, "ROTATED", rotated)).
}

// p34_new: the state of a P34 or P35 just selected.
FUNCTION p34_new {
  PARAMETER prog_no, first_state, vault, clock_zero, profile, now_ut, snap.
  RETURN LEXICON("PROG_NO", prog_no, "MODE", "P" + prog_no, "REFUSED", "", "ENDED", FALSE, "STATE", first_state, "SHOWN", FALSE, "VAULT", vault,
                 "CLOCK_ZERO", clock_zero, "PROFILE", profile, "SNAP", snap, "NOW_UT", now_ut, "SOL", FALSE, "FINAL", FALSE,
                 "BY_ELEV", FALSE, "ALARM_CODE", 0, "FAULT", 0, "WARN", "", "MGA", 0).
}

// p34_start: prev is FALSE (V37 start). Refused when the snapshot is not usable.
FUNCTION p34_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, snap.
  LOCAL seen IS snap:CALL().
  IF NOT seen["OK"] { RETURN LEXICON("REFUSED", seen["WHY"]). }
  RETURN p34_new(34, "N37", vault, clock_zero, profile, now_ut, snap).
}

// p35_start: refused when the snapshot is not usable, or there is no intercept time far enough ahead (P34 stores it).
FUNCTION p35_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, snap.
  LOCAL seen IS snap:CALL().
  IF NOT seen["OK"] { RETURN LEXICON("REFUSED", seen["WHY"]). }
  LOCAL tpass_s IS lm_store_get_time(vault, "TPASS4").
  IF tpass_s <= 0 OR clock_zero + tpass_s <= now_ut + RNDZ_MID_LEAD_S {
    RETURN LEXICON("REFUSED", "no intercept time more than 3 minutes ahead: run P34 first").
  }
  RETURN p34_new(35, "CALC", vault, clock_zero, profile, now_ut, snap).
}

// p34_fault: no solution from the conic maths: alarm 20607, the programme ends.
FUNCTION p34_fault {
  PARAMETER prog, why.
  SET prog["FAULT"] TO RNDZ_CONIC_ABORT.
  SET prog["WARN"] TO prog["MODE"] + " ALARM " + RNDZ_CONIC_ABORT + ": NO TRANSFER ORBIT FOUND (" + why + ").".
  SET prog["ENDED"] TO TRUE.
  LOG prog["MODE"] + " UT " + ROUND(prog["NOW_UT"], 1) + ", alarm " + RNDZ_CONIC_ABORT + " (" + why + ")" TO P34_LOG_PATH.
}

// p34_states: both craft carried from the snapshot to the burn time: LEXICON("OK", "RA", "VA" the LM, "RT", "VT" the CSM).
FUNCTION p34_states {
  PARAMETER seen, burn_ut.
  LOCAL lm_at IS conic_kepler(seen["R"], seen["V"], burn_ut - seen["T"], seen["MU"]).
  LOCAL csm_at IS conic_kepler(seen["RT"], seen["VT"], burn_ut - seen["T"], seen["MU"]).
  RETURN LEXICON("OK", lm_at["OK"] AND csm_at["OK"], "RA", lm_at["R"], "VA", lm_at["V"], "RT", csm_at["R"], "VT", csm_at["V"]).
}

// p34_tpi_time: the loaded TPI time (s on the AGC clock) when it is still ahead; else -1, back to V06 N37 with a message.
FUNCTION p34_tpi_time {
  PARAMETER prog.
  LOCAL ttpi_s IS lm_store_get_time(prog["VAULT"], "TTPI").
  IF ttpi_s <= 0 OR prog["CLOCK_ZERO"] + ttpi_s < prog["NOW_UT"] {
    SET prog["STATE"] TO "N37".
    SET prog["WARN"] TO "P34: the TPI time is not loaded or has passed; load a later one (V25 N37 E).".
    RETURN -1.
  }
  RETURN ttpi_s.
}

// p34_search: S33/34.1. With an elevation angle keyed the TPI time is moved to where the CSM stands at it (alarm 611 when there is none);
// with zero the time stays and the elevation angle is worked out. The result is shown again: N37 or N55.
FUNCTION p34_search {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL ttpi_s IS p34_tpi_time(prog).
  IF ttpi_s < 0 { RETURN. }
  LOCAL at_tpi IS p34_states(seen, prog["CLOCK_ZERO"] + ttpi_s).
  IF NOT at_tpi["OK"] { p34_fault(prog, "conic"). RETURN. }
  IF NOT prog["BY_ELEV"] {
    lm_store_put_n55(vault, -1, rndz_elevation(at_tpi["RA"], at_tpi["VA"], at_tpi["RT"]), -1).
    SET prog["STATE"] TO "N55B".
    RETURN.
  }
  LOCAL elev_deg IS lm_store_get_n55(vault)["ELEV"].
  LOCAL found IS rndz_tpi_time(at_tpi["RA"], at_tpi["VA"], at_tpi["RT"], at_tpi["VT"], elev_deg, seen["MU"]).
  IF NOT found["OK"] {
    SET prog["STATE"] TO "ALARM".
    SET prog["ALARM_CODE"] TO P34_NO_TIME.
    LOG "P34 UT " + ROUND(prog["NOW_UT"], 1) + ", TTPI " + ROUND(ttpi_s, 2) + " s, elev " + ROUND(elev_deg, 2) + " deg, alarm " + P34_NO_TIME + " (" + found["WHY"] + ")" TO P34_LOG_PATH.
    RETURN.
  }
  lm_store_put_time(vault, "TTPI", MAX(0, ttpi_s + found["DT"])).
  SET prog["STATE"] TO "N37B".
}

// rndz_pass_state: the display after the burn has been computed (P34: after N58): N81, except that Luminary 099 keeps it for the final computation
// and shows N59 meanwhile.
FUNCTION rndz_pass_state {
  PARAMETER prog.
  IF prog["PROFILE"] = "J" OR prog["FINAL"] { RETURN "N81". }
  RETURN "N59".
}

// p34_solve: S34/35.2. The transfer from the LM at TIG to the CSM's position at the intercept: stores the intercept time, the delta-V (N81) and TIG,
// and sets the burn. Returns FALSE (with the fault raised) when there is no solution.
FUNCTION p34_solve {
  PARAMETER prog, seen, at_tig, tig_s, tpass_s.
  LOCAL vault IS prog["VAULT"].
  LOCAL ra IS at_tig["RA"].
  LOCAL va IS at_tig["VA"].
  LOCAL xf IS rndz_transfer(ra, va, at_tig["RT"], at_tig["VT"], tpass_s - tig_s, seen["MU"]).
  IF NOT xf["OK"] { p34_fault(prog, xf["WHY"]). RETURN FALSE. }
  LOCAL nrm IS lm_cross(ra, va):NORMALIZED.
  lm_store_put_time(vault, "TPASS4", tpass_s).
  lm_store_put_time(vault, "TIG", tig_s).
  lm_store_put_dv(vault, rndz_lv(xf["DV"], ra, nrm)).
  SET prog["SOL"] TO LEXICON("RA", ra, "VA", va, "RT", at_tig["RT"], "NRM", nrm, "AX", seen["AX"], "TIG_S", tig_s, "TPASS_S", tpass_s,
                             "DV", xf["DV"], "ROTATED", xf["ROTATED"], "LV_SHOWN", lm_store_get_dv(vault), "CENT", xf["ANGLE"],
                             "PERI", p30_apsides(ra, va, xf["DV"], seen["MU"], seen["RADIUS"])["PERI_M"], "DVTPI", xf["DV"]:MAG, "DVTPF", xf["DVTPF"],
                             "LOS", rndz_los_dv(xf["DV"], ra, va, at_tig["RT"]), "MU", seen["MU"]).
  p34_set_burn(prog, xf["AIM"]).
  LOG prog["MODE"] + " UT " + ROUND(prog["NOW_UT"], 1) + ", TIG " + ROUND(tig_s, 2) + " s, intercept " + ROUND(tpass_s, 2) + " s, DV " + ROUND(xf["DV"]:MAG, 4)
      + " m/s, intercept DV " + ROUND(xf["DVTPF"], 4) + " m/s, perilune " + ROUND(prog["SOL"]["PERI"], 1) + " m, angle " + ROUND(xf["ANGLE"], 3)
      + " deg, elevation " + ROUND(rndz_elevation(ra, va, at_tig["RT"]), 3) + " deg" TO P34_LOG_PATH.
  RETURN TRUE.
}

// p34_set_burn: the burn of the present solution, aimed at aim_vec, for P40, P41 and P42.
FUNCTION p34_set_burn {
  PARAMETER prog, aim_vec.
  LOCAL sol IS prog["SOL"].
  LOCAL xd IS rndz_aim_xdelv(sol["DV"], sol["RA"], sol["VA"], aim_vec, prog["CLOCK_ZERO"] + sol["TPASS_S"], sol["ROTATED"],
                             prog["CLOCK_ZERO"] + sol["TIG_S"], sol["AX"]).
  IF DEFINED LM_VEH { SET LM_VEH["XDELV"] TO xd. }
  SET prog["MGA"] TO 0.
  IF xd["DELVSAB"] > 0 { SET prog["MGA"] TO p30_mga(s40_1(xd["DELVSIN"])["UT"], VCRS(xd["RTIG"], xd["VTIG"])). }
}

// p34_transfer: PRO at the second N37 or N55 (source label P34/P74E): the intercept time from the central angle, the transfer, then N58.
FUNCTION p34_transfer {
  PARAMETER prog.
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL ttpi_s IS p34_tpi_time(prog).
  IF ttpi_s < 0 { RETURN. }
  LOCAL at_tpi IS p34_states(seen, prog["CLOCK_ZERO"] + ttpi_s).
  IF NOT at_tpi["OK"] { p34_fault(prog, "conic"). RETURN. }
  LOCAL span_s IS conic_time_theta(at_tpi["RT"], at_tpi["VT"], MAX(0, lm_store_get_n55(prog["VAULT"])["CENTANG"]), seen["MU"]).
  IF span_s < 0 { p34_fault(prog, "orbit"). RETURN. }
  IF p34_solve(prog, seen, at_tpi, ttpi_s, ttpi_s + span_s) { SET prog["STATE"] TO "N58". }
}

// p35_compute: a new TIG 180 s from now and the transfer to the saved intercept time.
FUNCTION p35_compute {
  PARAMETER prog.
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL tig_s IS prog["NOW_UT"] - prog["CLOCK_ZERO"] + RNDZ_MID_LEAD_S.
  LOCAL tpass_s IS lm_store_get_time(prog["VAULT"], "TPASS4").
  IF tpass_s <= tig_s { p32_lost(prog, "the intercept is less than 3 minutes away"). RETURN. }
  LOCAL at_tig IS p34_states(seen, prog["CLOCK_ZERO"] + tig_s).
  IF NOT at_tig["OK"] { p34_fault(prog, "conic"). RETURN. }
  IF p34_solve(prog, seen, at_tig, tig_s, tpass_s) { SET prog["STATE"] TO rndz_pass_state(prog). }
}

// p34_again: a recycle or the final computation.
FUNCTION p34_again {
  PARAMETER prog.
  IF prog["PROG_NO"] = 35 { p35_compute(prog). } ELSE { p34_search(prog). }
}

// p34_keyed: PRO at N81. A changed delta-V gives a new aim point, the one it flies to by the intercept time (S34/35.3), and the burn is set again.
FUNCTION p34_keyed {
  PARAMETER prog.
  LOCAL sol IS prog["SOL"].
  LOCAL loaded IS lm_store_get_dv(prog["VAULT"]).
  IF (loaded - sol["LV_SHOWN"]):MAG <= 0.0001 { RETURN. }
  LOCAL dv_vec IS plan_lv_to_dv(LIST(loaded:X, loaded:Y, loaded:Z), sol["RA"], rndz_fwd(sol["NRM"], sol["RA"])).
  LOCAL flown IS conic_kepler(sol["RA"], sol["VA"] + dv_vec, sol["TPASS_S"] - sol["TIG_S"], sol["MU"]).
  IF NOT flown["OK"] { p34_fault(prog, "keyed delta-V"). RETURN. }
  SET sol["DV"] TO dv_vec.
  SET sol["LV_SHOWN"] TO loaded.
  SET sol["LOS"] TO rndz_los_dv(dv_vec, sol["RA"], sol["VA"], sol["RT"]).
  p34_set_burn(prog, flown["R"]).
}

// p34_proceed: PRO at the present display.
FUNCTION p34_proceed {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL state_now IS prog["STATE"].
  IF state_now = "N37" {
    IF p34_tpi_time(prog) >= 0 {
      // NN and the central angle are loaded afresh; Luminary 210 also zeroes the elevation angle, 099 keeps it.
      LOCAL elev_deg IS 0.
      IF prog["PROFILE"] <> "J" { SET elev_deg TO (CHOOSE P32_ELEV_DEG IF lm_store_get_n55(vault)["ELEV"] < 0 ELSE -1). }
      lm_store_put_n55(vault, 0, elev_deg, P34_CENTANG_DEG).
      SET prog["STATE"] TO "N55".
    }
  } ELSE IF state_now = "N55" {
    SET prog["BY_ELEV"] TO lm_store_get_n55(vault)["ELEV"] > 0.
    p34_search(prog).
  } ELSE IF state_now = "N37B" OR state_now = "N55B" {
    p34_transfer(prog).
  } ELSE IF state_now = "ALARM" {
    SET prog["STATE"] TO "N37".          // PRO starts P34 again
    SET prog["ALARM_CODE"] TO 0.
  } ELSE IF state_now = "N58" {
    SET prog["STATE"] TO rndz_pass_state(prog).
  } ELSE IF state_now = "N81" {
    p34_keyed(prog).
    SET prog["STATE"] TO (CHOOSE "N45" IF prog["PROFILE"] = "J" ELSE "N59").
  } ELSE IF state_now = "N59" {
    SET prog["STATE"] TO "N45".
  } ELSE IF state_now = "N45" {
    IF prog["FINAL"] {
      SET prog["ENDED"] TO TRUE.
    } ELSE {
      SET prog["FINAL"] TO TRUE.          // the first PRO at N45 asks for the final computation
      p34_again(prog).
    }
  }
}

// p34_state_vn: the verb and noun of a state's flashing display.
FUNCTION p34_state_vn {
  PARAMETER state_name.
  IF state_name = "N37" OR state_name = "N37B" { RETURN LIST(6, 37). }
  IF state_name = "N55" OR state_name = "N55B" { RETURN LIST(6, 55). }
  IF state_name = "ALARM" { RETURN LIST(5, 9). }
  IF state_name = "N58" { RETURN LIST(6, 58). }
  IF state_name = "N81" { RETURN LIST(6, 81). }
  IF state_name = "N59" { RETURN LIST(6, 59). }
  RETURN LIST(16, 45).
}

// rndz34_step: one cycle of P34 or P35. V34 ends the programme at any display; PRO goes on; V32, or an ENTR that answers the display, shows it again,
// except that V32 at N45 computes again. The caller sets prog["NOW_UT"] each cycle. P35 computes on its first cycle.
// EXTRA carries RN_CENT (N52), RN_PERI, RN_DVTPI, RN_DVTPF (N58), RN_DVLOS (N59), P30_TTOGO and P30_MGA (N45).
FUNCTION rndz34_step {
  PARAMETER prog, ks.
  LOCAL ans IS resp_read(ks).
  SET prog["WARN"] TO "".
  IF prog["STATE"] = "CALC" {
    p35_compute(prog).
  } ELSE {
    LOCAL vn_now IS p34_state_vn(prog["STATE"]).
    IF ans["TERM"] {
      SET prog["ENDED"] TO TRUE.
    } ELSE IF ans["PRO"] {
      p34_proceed(prog).
      SET prog["SHOWN"] TO FALSE.
    } ELSE IF ans["V32"] AND prog["STATE"] = "N45" {
      p34_again(prog).
      SET prog["SHOWN"] TO FALSE.
    } ELSE IF ans["V32"] OR lm_entr_on_request(ks, vn_now[0], vn_now[1]) {
      SET prog["SHOWN"] TO FALSE.
    }
  }
  LOCAL vn_out IS p34_state_vn(prog["STATE"]).
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT prog["ENDED"] AND NOT prog["SHOWN"] {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO vn_out[0].
    SET set_noun TO vn_out[1].
  }
  LOCAL extra IS LEXICON("RN_CENT", 0, "RN_PERI", 0, "RN_DVTPI", 0, "RN_DVTPF", 0, "RN_DVLOS", V(0, 0, 0), "P30_TTOGO", 0, "P30_MGA", rndz_mga(prog)).
  IF prog["SOL"]:ISTYPE("Lexicon") {
    LOCAL sol IS prog["SOL"].
    SET extra["RN_CENT"] TO sol["CENT"].
    SET extra["RN_PERI"] TO sol["PERI"].
    SET extra["RN_DVTPI"] TO sol["DVTPI"].
    SET extra["RN_DVTPF"] TO sol["DVTPF"].
    SET extra["RN_DVLOS"] TO sol["LOS"].
    SET extra["P30_TTOGO"] TO MAX(0, prog["CLOCK_ZERO"] + sol["TIG_S"] - prog["NOW_UT"]).
  }
  LOCAL request IS FALSE.
  IF NOT prog["ENDED"] { SET request TO LEXICON("VERB", vn_out[0], "NOUN", vn_out[1]). }
  LOCAL alarm_now IS prog["FAULT"].
  IF prog["STATE"] = "ALARM" AND NOT prog["ENDED"] { SET alarm_now TO prog["ALARM_CODE"]. }
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", request,
                 "ALARM", alarm_now, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE, "EXTRA", extra, "MSG", "", "WARN", prog["WARN"], "ENDED", prog["ENDED"], "HANDOVER", FALSE,
                 "PROG_NO", prog["PROG_NO"], "CONTACT", FALSE, "STATUS", LIST()).
}

FUNCTION p34_step { PARAMETER prog, ks. RETURN rndz34_step(prog, ks). }
FUNCTION p35_step { PARAMETER prog, ks. RETURN rndz34_step(prog, ks). }

// p34_end, p35_end: neither takes anything over (they fire nothing and hold no lock), so nothing is given back.
FUNCTION p34_end {
  PARAMETER prog.
}
FUNCTION p35_end {
  PARAMETER prog.
}
