// lm_p32.ks -- P32, coelliptic sequence initiation (CSI) targeting, and P33, constant delta height (CDH) targeting (release 1.5).
//   p32_start(prev, vault, clock_zero, profile, now_ut, snap)   the programme state, or a LEXICON with "REFUSED" holding the reason
//   p32_step(prog, ks)                                          one cycle; returns the programme output keys the DSKY core reads
//   p32_end(prog)                                               nothing to give back
//   p33_start, p33_step, p33_end                                the same for P33
//
// Source: Luminary 210 P32-P35,_P72-P75.agc: P32 (lines 201-322: the CSI time, NN and elevation, the TPI time, CSI/A, then the displays N75, N81, N82
// and N45), P33 (lines 483-574: the CDH time, the coelliptic burn, the TPI time for the elevation angle with alarm 611, then N75, N81 and N45), ADVANCE
// (lines 1159-1186: both craft carried to the burn time and the LM turned into the CSM's plane), S32/33.1 (lines 1225-1240: the delta-V shown in local
// vertical axes); N45 and its three answers: P34-P35,_P74-P75.agc VN1645 (lines 932-953: R3, the middle gimbal angle, is -00.01 until the final
// computation; P34 and P35 share this). The same in both pad profiles. The maths is lm_rndz.ks.
//
// snap:CALL() returns both craft at one instant: LEXICON("OK", "WHY", "T" UT, "R", "V" the LM, "RT", "VT" the CSM, "AX" the axes mark the vectors are in,
// "MU", "RADIUS"), positions from the Moon's centre. OK FALSE (with WHY) when there is no usable pair.
// The result P41 and P40 read is LM_VEH["XDELV"], as P30 sets it (rndz_xdelv).
//
// Departures:
//   * The first PRO at N11 on a zero time loads the next apolune; the CSM is read where it is, not integrated from an uplinked state.
//   * No tracking marks and no CSM state updates (N45 R1 is always zero).
//   * P33 with no nominal TPI time (TTPI0, set by P32) takes the loaded TPI time (N37) as the nominal one for that run only, and refuses to start
//     with neither. After such a run N37 holds the solved time, so the next one starts from it unless another is keyed.
//   * Every solution of P32 and P33 is logged to 0:/lm/logs/p32.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").               // the store cells
RUNONCEPATH("0:/lm/planner/lm_plan.ks").        // plan_lv_to_dv, plan_lv_components
RUNONCEPATH("0:/lm/burn/lm_burn_s.ks").         // s40_1, p30_mga
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").       // resp_read
RUNONCEPATH("0:/lm/burn/lm_r60.ks").            // lm_entr_on_request
RUNONCEPATH("0:/lm/rndz/lm_rndz.ks").           // rndz_csi, rndz_into_plane, rndz_fwd (and the conics)

GLOBAL P32_LOG_PATH IS "0:/lm/logs/p32.log".    // appended to, one line per solution; the pad test points it elsewhere
GLOBAL P32_ELEV_DEG IS 26.6.                    // the TPI elevation angle when none is loaded
GLOBAL P32_NO_SOLUTION IS 605.
GLOBAL P33_NO_TPI IS 611.                       // P33: no TPI time found for the elevation angle
GLOBAL RNDZ_MGA_NOT_FINAL IS -0.01.             // Luminary +MGA before the final computation (N45 R3 shows -00.01)

// rndz_mga: N45 R3 of P32 to P35: the burn's middle gimbal angle once the final computation has been asked for, -00.01 before.
FUNCTION rndz_mga {
  PARAMETER prog.
  RETURN CHOOSE prog["MGA"] IF prog["FINAL"] ELSE RNDZ_MGA_NOT_FINAL.
}

// rndz_xdelv: the external delta-V lexicon for a burn given in local vertical axes. lv_vec is the N81 value (m/s), pos_burn the LM position at the burn
// turned into the CSM's plane (the local vertical frame is built on it, with the track along rndz_fwd), rtig and vtig the LM state at the burn as it is
// (not turned), tig_ut the burn time, ax the axes mark of all the vectors.
FUNCTION rndz_xdelv {
  PARAMETER lv_vec, pos_burn, nrm, rtig, vtig, tig_ut, ax.
  LOCAL dv_vec IS plan_lv_to_dv(LIST(lv_vec:X, lv_vec:Y, lv_vec:Z), pos_burn, rndz_fwd(nrm, pos_burn)).
  RETURN LEXICON("DELVSIN", dv_vec, "RTIG", rtig, "VTIG", vtig, "UT_TIG", tig_ut, "DELVSAB", dv_vec:MAG, "AX0", ax).
}

// rndz_lv: a delta-V vector as the N81 value at the burn position, the inverse of the frame of rndz_xdelv.
FUNCTION rndz_lv {
  PARAMETER dv_vec, pos_burn, nrm.
  LOCAL parts IS plan_lv_components(dv_vec, pos_burn, rndz_fwd(nrm, pos_burn)).
  RETURN V(parts[0], parts[1], parts[2]).
}

// p32_prepare: ADVANCE. Both craft carried from the snapshot to the burn time, and the LM turned into the CSM's plane.
// Returns LEXICON("OK", "NRM", "R1", "V1" the turned LM, "RTIG", "VTIG" the LM as it is, "RT", "VT" the CSM).
FUNCTION p32_prepare {
  PARAMETER seen, burn_ut.
  LOCAL failed IS LEXICON("OK", FALSE).
  LOCAL lm_at IS conic_kepler(seen["R"], seen["V"], burn_ut - seen["T"], seen["MU"]).
  LOCAL csm_at IS conic_kepler(seen["RT"], seen["VT"], burn_ut - seen["T"], seen["MU"]).
  IF NOT lm_at["OK"] OR NOT csm_at["OK"] { RETURN failed. }
  LOCAL nrm_raw IS lm_cross(csm_at["R"], csm_at["V"]).
  IF nrm_raw:MAG <= 0 { RETURN failed. }
  LOCAL nrm IS nrm_raw:NORMALIZED.
  RETURN LEXICON("OK", TRUE, "NRM", nrm, "R1", rndz_into_plane(lm_at["R"], nrm), "V1", rndz_into_plane(lm_at["V"], nrm),
                 "RTIG", lm_at["R"], "VTIG", lm_at["V"], "RT", csm_at["R"], "VT", csm_at["V"]).
}

// p32_restart: the state of a programme just selected (also V32 at the alarm display).
FUNCTION p32_restart {
  PARAMETER prog.
  lm_store_put_time(prog["VAULT"], "TCSI", 0).
  lm_store_put_n55(prog["VAULT"], -1, -1, 0).
  SET prog["STATE"] TO "N11".
  SET prog["SHOWN"] TO FALSE.
  SET prog["FINAL"] TO FALSE.
  SET prog["ALARM_CODE"] TO 0.
}

// rndz_new: the state of a P32 or P33 just selected, at its first display. An unloaded elevation angle gets the default.
FUNCTION rndz_new {
  PARAMETER prog_no, first_state, vault, clock_zero, profile, now_ut, snap.
  IF lm_store_get_n55(vault)["ELEV"] < 0 { lm_store_put_n55(vault, -1, P32_ELEV_DEG, -1). }
  RETURN LEXICON("PROG_NO", prog_no, "MODE", "P" + prog_no, "REFUSED", "", "ENDED", FALSE, "STATE", first_state, "SHOWN", FALSE, "VAULT", vault,
                 "CLOCK_ZERO", clock_zero, "PROFILE", profile, "SNAP", snap, "NOW_UT", now_ut, "SOL", FALSE, "FINAL", FALSE,
                 "ALARM_CODE", 0, "WARN", "", "MGA", 0, "NOMINAL_S", 0).      // NOMINAL_S: P33's nominal TPI time, set at N13
}

// p32_start: prev is FALSE (V37 start). Refused when the snapshot is not usable.
FUNCTION p32_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, snap.
  LOCAL seen IS snap:CALL().
  IF NOT seen["OK"] { RETURN LEXICON("REFUSED", seen["WHY"]). }
  LOCAL prog IS rndz_new(32, "N11", vault, clock_zero, profile, now_ut, snap).
  p32_restart(prog).
  IF lm_store_get_n55(vault)["NN"] < 0 { lm_store_put_n55(vault, 1, -1, -1). }
  RETURN prog.
}

// p32_lost: the snapshot is not usable any more: a message, and the programme ends.
FUNCTION p32_lost {
  PARAMETER prog, why.
  SET prog["WARN"] TO prog["MODE"] + ": " + why + ".".
  SET prog["ENDED"] TO TRUE.
}

// p32_apolune: PRO on a zero N11. TCSI becomes the next apolune of the LM's orbit.
FUNCTION p32_apolune {
  PARAMETER prog.
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL ahead_s IS conic_time_to_apo(seen["R"], seen["V"], seen["MU"]).
  IF ahead_s < 0 {
    SET prog["WARN"] TO "P32: the orbit has no apolune; load the CSI time (V25 N11 E).".
    RETURN.
  }
  lm_store_put_time(prog["VAULT"], "TCSI", seen["T"] + ahead_s - prog["CLOCK_ZERO"]).
}

// p32_fail: show the alarm display (V05 N09).
FUNCTION p32_fail {
  PARAMETER prog, code.
  SET prog["STATE"] TO "ALARM".
  SET prog["ALARM_CODE"] TO code.
}

// p32_log: one line for a computation (solved is rndz_csi's answer).
FUNCTION p32_log {
  PARAMETER prog, inp, solved.
  LOCAL text IS "P32 UT " + ROUND(prog["NOW_UT"], 1) + ", TCSI " + ROUND(inp["TCSI"], 2) + " s, TTPI " + ROUND(inp["TTPI"], 2) + " s, NN " + inp["NN"]
      + ", elev " + ROUND(inp["ELEV"], 2) + " deg".
  IF solved["OK"] {
    SET text TO text + ", DV " + ROUND(solved["DV"], 4) + " m/s, TCDH " + ROUND(solved["TCDH"], 2) + " s, DH " + ROUND(solved["DH"], 1) + " m".
  } ELSE {
    SET text TO text + ", alarm " + solved["ALARM"].
  }
  LOG text TO P32_LOG_PATH.
}

// p32_compute: read both craft, check the CSI time, run CSI/A. Success stores TCDH and goes to N75.
FUNCTION p32_compute {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL tcsi_s IS lm_store_get_time(vault, "TCSI").
  IF tcsi_s <= 0 OR prog["CLOCK_ZERO"] + tcsi_s < prog["NOW_UT"] {
    SET prog["STATE"] TO "N11".
    SET prog["WARN"] TO "P32: the CSI time has passed; load a later one (V25 N11 E, or zero for the next apolune).".
    RETURN.
  }
  LOCAL ready IS p32_prepare(seen, prog["CLOCK_ZERO"] + tcsi_s).
  IF NOT ready["OK"] { p32_fail(prog, P32_NO_SOLUTION). RETURN. }
  LOCAL loaded IS lm_store_get_n55(vault).
  LOCAL inp IS LEXICON("R1", ready["R1"], "V1", ready["V1"], "RT", ready["RT"], "VT", ready["VT"], "TCSI", tcsi_s,
                       "TTPI", MAX(0, lm_store_get_time(vault, "TTPI")), "NN", loaded["NN"], "ELEV", loaded["ELEV"],
                       "FORCE_HALF", loaded["CENTANG"] > 0, "MU", seen["MU"], "RADIUS", seen["RADIUS"]).
  LOCAL solved IS rndz_csi(inp).
  p32_log(prog, inp, solved).
  IF NOT solved["OK"] { p32_fail(prog, solved["ALARM"]). RETURN. }
  lm_store_put_time(vault, "TCDH", solved["TCDH"]).
  SET prog["SOL"] TO LEXICON("CSI", solved, "AT", ready, "AX", seen["AX"], "TIG_S", tcsi_s, "TTPI", inp["TTPI"], "DH", solved["DH"],
                             "T12", MOD(solved["TCDH"] - tcsi_s, 3600), "T23", MOD(inp["TTPI"] - solved["TCDH"], 3600)).
  SET prog["STATE"] TO "N75".
}

// rndz_set_burn: PRO at N81. The (perhaps keyed) delta-V becomes the burn for P41 and P40, at the solution's burn time.
FUNCTION rndz_set_burn {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL sol IS prog["SOL"].
  LOCAL ready IS sol["AT"].
  LOCAL xd IS rndz_xdelv(lm_store_get_dv(vault), ready["R1"], ready["NRM"], ready["RTIG"], ready["VTIG"], prog["CLOCK_ZERO"] + sol["TIG_S"], sol["AX"]).
  lm_store_put_tig(vault, sol["TIG_S"]).
  IF DEFINED LM_VEH { SET LM_VEH["XDELV"] TO xd. }
  SET prog["MGA"] TO 0.
  IF xd["DELVSAB"] > 0 { SET prog["MGA"] TO p30_mga(s40_1(xd["DELVSIN"])["UT"], VCRS(xd["RTIG"], xd["VTIG"])). }
}

// p33_restart: back to the first display (also V32 at the alarm display). The final-computation flag is left as it is, as in the source.
FUNCTION p33_restart {
  PARAMETER prog.
  SET prog["STATE"] TO "N13".
  SET prog["SHOWN"] TO FALSE.
  SET prog["ALARM_CODE"] TO 0.
}

// p33_start: refused when the snapshot is not usable, or there is no TPI time (nominal or loaded).
FUNCTION p33_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, snap.
  LOCAL seen IS snap:CALL().
  IF NOT seen["OK"] { RETURN LEXICON("REFUSED", seen["WHY"]). }
  IF lm_store_get_time(vault, "TTPI0") <= 0 AND lm_store_get_time(vault, "TTPI") <= 0 {
    RETURN LEXICON("REFUSED", "no TPI time: run P32 first, or load the TPI time with V25 N37 E").
  }
  RETURN rndz_new(33, "N13", vault, clock_zero, profile, now_ut, snap).
}

// p33_past: the CDH time is not loaded or is behind us: back to (or stay at) N13 with a message.
FUNCTION p33_past {
  PARAMETER prog.
  SET prog["STATE"] TO "N13".
  SET prog["WARN"] TO "P33: the CDH time is not loaded or has passed; load a later one (V25 N13 E).".
}

// p33_log: one line for a computation (man is rndz_cdh's answer, found is rndz_tpi_time's).
FUNCTION p33_log {
  PARAMETER prog, tcdh_s, nominal_s, elev_deg, man, found.
  LOCAL text IS "P33 UT " + ROUND(prog["NOW_UT"], 1) + ", TCDH " + ROUND(tcdh_s, 2) + " s, TTPI " + ROUND(nominal_s, 2) + " s, elev " + ROUND(elev_deg, 2)
      + " deg, DV " + ROUND(man["DV"]:MAG, 4) + " m/s, DH " + ROUND(man["DH"], 1) + " m".
  IF found["OK"] {
    SET text TO text + ", TPI change " + ROUND(found["DT"], 3) + " s".
  } ELSE {
    SET text TO text + ", alarm " + P33_NO_TPI + " (" + found["WHY"] + ")".
  }
  LOG text TO P32_LOG_PATH.
}

// p33_compute: read both craft, check the CDH time, make the coelliptic burn and move the TPI time to where the elevation angle is right. Success goes to
// N75; with no such time the alarm display (611) comes first and the TPI time stays as it was.
FUNCTION p33_compute {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] { p32_lost(prog, seen["WHY"]). RETURN. }
  LOCAL tcdh_s IS lm_store_get_time(vault, "TCDH").
  IF tcdh_s <= 0 OR prog["CLOCK_ZERO"] + tcdh_s < prog["NOW_UT"] { p33_past(prog). RETURN. }
  LOCAL ready IS p32_prepare(seen, prog["CLOCK_ZERO"] + tcdh_s).
  IF NOT ready["OK"] { p32_lost(prog, "the orbits cannot be carried to the CDH time"). RETURN. }
  LOCAL man IS rndz_cdh(ready["R1"], ready["V1"], ready["RT"], ready["VT"], ready["NRM"], seen["MU"]).
  IF NOT man["OK"] { p32_lost(prog, "no coelliptic burn can be made from these orbits"). RETURN. }
  LOCAL elev_deg IS lm_store_get_n55(vault)["ELEV"].
  LOCAL nominal_s IS lm_store_get_time(vault, "TTPI").
  LOCAL found IS LEXICON("OK", FALSE, "WHY", "conic", "DT", 0).
  LOCAL lm_tpi IS conic_kepler(ready["R1"], man["V3"], nominal_s - tcdh_s, seen["MU"]).
  LOCAL csm_tpi IS conic_kepler(ready["RT"], ready["VT"], nominal_s - tcdh_s, seen["MU"]).
  IF lm_tpi["OK"] AND csm_tpi["OK"] {
    SET found TO rndz_tpi_time(lm_tpi["R"], lm_tpi["V"], csm_tpi["R"], csm_tpi["V"], elev_deg, seen["MU"]).
  }
  p33_log(prog, tcdh_s, nominal_s, elev_deg, man, found).
  IF found["OK"] { lm_store_put_time(vault, "TTPI", nominal_s + found["DT"]). }
  LOCAL ttpi_s IS lm_store_get_time(vault, "TTPI").
  LOCAL late_s IS ttpi_s - prog["NOMINAL_S"].
  SET prog["SOL"] TO LEXICON("CDH", man, "AT", ready, "AX", seen["AX"], "TIG_S", tcdh_s, "DH", man["DH"],
                             "T12", MOD(ttpi_s - tcdh_s, 3600), "T23", rndz_sign(late_s) * MOD(ABS(late_s), 3600)).
  IF found["OK"] {
    SET prog["STATE"] TO "N75".
  } ELSE {
    p32_fail(prog, P33_NO_TPI).
  }
}

// p33_proceed: PRO at the present display of P33.
FUNCTION p33_proceed {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL state_now IS prog["STATE"].
  IF state_now = "N13" {
    LOCAL tcdh_s IS lm_store_get_time(vault, "TCDH").
    LOCAL nominal_s IS lm_store_get_time(vault, "TTPI0").
    IF tcdh_s <= 0 OR prog["CLOCK_ZERO"] + tcdh_s < prog["NOW_UT"] {
      p33_past(prog).
    } ELSE IF nominal_s <= 0 AND lm_store_get_time(vault, "TTPI") <= 0 {
      SET prog["WARN"] TO "P33: no TPI time; load it with V25 N37 E.".
    } ELSE {
      // TTPI = TTPI0 (source lines 491-493). With no TTPI0 (no P32) the loaded TPI time is the nominal one, kept in the programme
      // only: stored in TTPI0 it would overwrite every TPI time keyed later.
      IF nominal_s > 0 { lm_store_put_time(vault, "TTPI", nominal_s). }
      SET prog["NOMINAL_S"] TO lm_store_get_time(vault, "TTPI").
      p33_compute(prog).
    }
  } ELSE IF state_now = "ALARM" {
    SET prog["STATE"] TO "N75".          // PRO: go on with the TPI time unchanged
  } ELSE IF state_now = "N75" {
    lm_store_put_dv(vault, rndz_lv(prog["SOL"]["CDH"]["DV"], prog["SOL"]["AT"]["R1"], prog["SOL"]["AT"]["NRM"])).
    SET prog["STATE"] TO "N81".
  } ELSE IF state_now = "N81" {
    rndz_set_burn(prog).
    SET prog["STATE"] TO "N45".
  } ELSE IF state_now = "N45" {
    IF prog["FINAL"] {
      SET prog["ENDED"] TO TRUE.
    } ELSE {
      SET prog["FINAL"] TO TRUE.          // the first PRO at N45 asks for the final computation
      p33_compute(prog).
    }
  }
}

// rndz_state_vn: the verb and noun of a state's flashing display.
FUNCTION rndz_state_vn {
  PARAMETER state_name.
  IF state_name = "N13" { RETURN LIST(6, 13). }
  IF state_name = "N11" { RETURN LIST(6, 11). }
  IF state_name = "N55" { RETURN LIST(6, 55). }
  IF state_name = "N37" { RETURN LIST(6, 37). }
  IF state_name = "ALARM" { RETURN LIST(5, 9). }
  IF state_name = "N75" { RETURN LIST(6, 75). }
  IF state_name = "N81" { RETURN LIST(6, 81). }
  IF state_name = "N82" { RETURN LIST(6, 82). }
  RETURN LIST(16, 45).
}

// p32_proceed: PRO at the present display.
FUNCTION p32_proceed {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL state_now IS prog["STATE"].
  IF state_now = "N11" {
    LOCAL tcsi_s IS lm_store_get_time(vault, "TCSI").
    IF tcsi_s <= 0 {
      p32_apolune(prog).
    } ELSE IF prog["CLOCK_ZERO"] + tcsi_s < prog["NOW_UT"] {
      SET prog["WARN"] TO "P32: the CSI time has passed; load a later one (V25 N11 E, or zero for the next apolune).".
    } ELSE {
      SET prog["STATE"] TO "N55".
    }
  } ELSE IF state_now = "N55" {
    SET prog["STATE"] TO "N37".
  } ELSE IF state_now = "N37" {
    p32_compute(prog).
  } ELSE IF state_now = "N75" {
    lm_store_put_dv(vault, rndz_lv(prog["SOL"]["CSI"]["DV1"], prog["SOL"]["AT"]["R1"], prog["SOL"]["AT"]["NRM"])).
    SET prog["STATE"] TO "N81".
  } ELSE IF state_now = "N81" {
    rndz_set_burn(prog).
    // N81 takes the CDH delta-V for the N82 display.
    lm_store_put_dv(vault, rndz_lv(prog["SOL"]["CSI"]["DV2"], prog["SOL"]["CSI"]["R2"], prog["SOL"]["AT"]["NRM"])).
    SET prog["STATE"] TO "N82".
  } ELSE IF state_now = "N82" {
    lm_store_put_time(vault, "TTPI0", prog["SOL"]["TTPI"]).
    SET prog["STATE"] TO "N45".
  } ELSE IF state_now = "N45" {
    IF prog["FINAL"] {
      SET prog["ENDED"] TO TRUE.
    } ELSE {
      SET prog["FINAL"] TO TRUE.          // the first PRO at N45 asks for the final computation
      p32_compute(prog).
    }
  }
  // "ALARM": PRO shows it again.
}

// rndz_step: one cycle of P32 or P33. V34 ends the programme at any display; PRO goes on; V32, or an ENTR that answers the display, shows it again, except
// that V32 at the alarm display restarts the programme and V32 at N45 computes again. The caller sets prog["NOW_UT"] each cycle (the vehicle adapter does).
// EXTRA carries RN_DH (m), RN_T12 and RN_T23 (s) for N75, P30_TTOGO (s) and P30_MGA (degrees) for N45.
FUNCTION rndz_step {
  PARAMETER prog, ks.
  LOCAL ans IS resp_read(ks).
  LOCAL is_33 IS prog["PROG_NO"] = 33.
  LOCAL vn_now IS rndz_state_vn(prog["STATE"]).
  SET prog["WARN"] TO "".
  IF ans["TERM"] {
    SET prog["ENDED"] TO TRUE.
  } ELSE IF ans["PRO"] {
    IF is_33 { p33_proceed(prog). } ELSE { p32_proceed(prog). }
    SET prog["SHOWN"] TO FALSE.
  } ELSE IF ans["V32"] AND prog["STATE"] = "ALARM" {
    IF is_33 { p33_restart(prog). } ELSE { p32_restart(prog). }
  } ELSE IF ans["V32"] AND prog["STATE"] = "N45" {
    IF is_33 { p33_compute(prog). } ELSE { p32_compute(prog). }
    SET prog["SHOWN"] TO FALSE.
  } ELSE IF ans["V32"] OR lm_entr_on_request(ks, vn_now[0], vn_now[1]) {
    SET prog["SHOWN"] TO FALSE.
  }
  LOCAL vn_out IS rndz_state_vn(prog["STATE"]).
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT prog["ENDED"] AND NOT prog["SHOWN"] {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO vn_out[0].
    SET set_noun TO vn_out[1].
  }
  LOCAL dh_m IS 0.
  LOCAL t12_s IS 0.
  LOCAL t23_s IS 0.
  LOCAL ttogo_s IS 0.
  IF prog["SOL"]:ISTYPE("Lexicon") {
    LOCAL sol IS prog["SOL"].
    SET dh_m TO sol["DH"].
    SET t12_s TO sol["T12"].
    SET t23_s TO sol["T23"].
    SET ttogo_s TO MAX(0, prog["CLOCK_ZERO"] + sol["TIG_S"] - prog["NOW_UT"]).
  }
  LOCAL request IS FALSE.
  IF NOT prog["ENDED"] { SET request TO LEXICON("VERB", vn_out[0], "NOUN", vn_out[1]). }
  LOCAL alarm_now IS 0.
  IF prog["STATE"] = "ALARM" AND NOT prog["ENDED"] { SET alarm_now TO prog["ALARM_CODE"]. }
  LOCAL extra IS LEXICON("RN_DH", dh_m, "RN_T12", t12_s, "RN_T23", t23_s, "P30_TTOGO", ttogo_s, "P30_MGA", rndz_mga(prog)).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", request,
                 "ALARM", alarm_now, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE, "EXTRA", extra, "MSG", "", "WARN", prog["WARN"], "ENDED", prog["ENDED"], "HANDOVER", FALSE,
                 "PROG_NO", prog["PROG_NO"], "CONTACT", FALSE, "STATUS", LIST()).
}

FUNCTION p32_step { PARAMETER prog, ks. RETURN rndz_step(prog, ks). }
FUNCTION p33_step { PARAMETER prog, ks. RETURN rndz_step(prog, ks). }

// p32_end, p33_end: neither takes anything over (they fire nothing and hold no lock), so nothing is given back.
FUNCTION p32_end {
  PARAMETER prog.
}
FUNCTION p33_end {
  PARAMETER prog.
}
