// lm_p30.ks -- P30, external delta-V (release 1.4).
//   p30_start(prev, vault, clock_zero, profile, now_ut, predict)   the programme state, or a LEXICON with "REFUSED" holding the reason
//   p30_step(prog, ks)                                             one cycle; returns the programme output keys the DSKY core reads
//   p30_end(prog)                                                  nothing to give back
//
// Source: Luminary 099 P30_P37.agc (this file's line numbers are that file's unless stated):
//   P30 (lines 61-86)       sets UPDATFLG and TRACKFLG; flashing V06 N33 (T of ignition, "RETURNS ON PROCEED, POOH ON TERMINATE"); flashing V06 N81
//                           (the delta-V in local vertical axes, "REDISPLAY ON RECYCLE"); S30.1; flashing V06 N42; then XDELVFLG is set (84-85, "FOR
//                           P40'S: EXTERNAL DELTA-V GUIDANCE") and REVN1645 shows N45. VNPOOH (P34-35_P74-75.agc 1022-1031): GOFLASH returns
//                           terminate -> GOTOPOOH, proceed -> on, recycle -> the display again.
//   S30.1 (lines 146-164, 165-198)  propagates the state to TIG (LEMPREC), stores RTIG and VTIG, builds the local vertical frame (Z = -unit(RTIG),
//                           Y = unit(VTIG x RTIG) = minus the orbit normal, X = Y x Z), turns DELVSLV into inertial axes (DELVSIN), its magnitude
//                           (DELVSAB), and the apsides of the orbit with VTIG + DELVSIN (PERIAPO1; each limited to 9999.9 nmi, MAXCHK).
//   VN1645 / GET45 (P34-35_P74-75.agc 930-984): flashing V16 N45, TRKMKCNT (marks), TTOGO, +MGA; the three returns are terminate (KILCLOCK, to P00),
//                           proceed (N45PROC) and recycle (CLUPDATE); GET+MGA (1406-1415) is p30_mga in lm_burn_s.ks.
// Our version, and where it departs:
//   * The state at TIG comes from the vehicle's predict delegate (kOS orbit prediction, which includes maneuver nodes still ahead) in place of LEMPREC.
//     predict:CALL(ut) returns LEXICON("R", vec, "V", vec) plus, for the apsides, "MU" and "RADIUS" of the body (an addition to the brief; the vehicle
//     adds them). The vectors are in the raw axes of the moment of the call, so the delta-V (a vector) is in the same axes.
//   * S30.1 runs when the pilot answers the N81 display with PRO, as in the source (after the loads), so a V25 load keyed over a display (the store changes)
//     is seen; it reads TIG and the delta-V from the store then. P30 refuses to start (V37) while TIG or the delta-V is not loaded, or TIG has passed
//     (the source would take the loads at its own two displays; the brief makes the refusal).
//   * N45: TRKMKCNT is zero (no marks exist), TTOGO is TIG minus now (the COMPTGO task counts it down; it stops at zero) and +MGA is the assumed
//     angle of p30_mga with Y = the orbit normal at TIG (design call 4). The source also loops once through CLUPDATE with FINALFLG (its first PRO at N45
//     sets FINALFLG and recycles for a final computation; the second PRO ends); with no REFSMMAT here the first pass computes nothing more, so PRO ends the
//     programme at once (as the research note says). V32 or ENTR at N45 shows it again.
//   * XDELVFLG: "the flag" is LM_VEH["XDELV"] being a LEXICON (FALSE otherwise) holding DELVSIN, RTIG, VTIG, UT_TIG and DELVSAB, which P40 and P41 read
//     (they do not recompute them, as in Luminary). Luminary 099 sets the flag after N42 is answered, 210 before N42 (research section 14): a V34 at N42
//     leaves it set only in the J profile. A new P30 does not clear it (the source does not); when the flag is already set the stored vectors are overwritten
//     by each new solution, as the erasables are in Luminary.
//   * UPDATFLG and TRACKFLG, the star tracking marks and the CSM tracking are not simulated.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").               // lm_store_get_tig, lm_store_get_dv (and the store)
RUNONCEPATH("0:/lm/planner/lm_plan.ks").        // plan_lv_to_dv
RUNONCEPATH("0:/lm/burn/lm_burn_s.ks").         // s40_1, p30_apsides, p30_mga
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").       // resp_read
RUNONCEPATH("0:/lm/burn/lm_r60.ks").            // lm_entr_on_request

// p30_refusal: the reason P30 cannot run on this store at this time, or "" when it can. tig_ut is TIG as a UT.
FUNCTION p30_refusal {
  PARAMETER vault, clock_zero, now_ut.
  IF NOT store_loaded(vault, "TIG") { RETURN "TIG is not loaded (V25 N33 E, or the PAD)". }
  IF NOT store_loaded(vault, "DELVLVC") { RETURN "the delta-V is not loaded (V25 N81 E, or the PAD)". }
  IF clock_zero + lm_store_get_tig(vault) < now_ut { RETURN "TIG has passed (load a later time with V25 N33 E)". }
  RETURN "".
}

// p30_start: the programme state. prev is FALSE (V37 start). predict is the vehicle's delegate (see the header).
FUNCTION p30_start {
  PARAMETER prev, vault, clock_zero, profile, now_ut, predict.
  LOCAL why IS p30_refusal(vault, clock_zero, now_ut).
  IF why <> "" { RETURN LEXICON("REFUSED", why). }
  RETURN LEXICON("PROG_NO", 30, "MODE", "P30", "REFUSED", "", "ENDED", FALSE, "STATE", "N33", "SHOWN", FALSE, "VAULT", vault, "CLOCK_ZERO", clock_zero,
                 "PROFILE", profile, "PREDICT", predict, "NOW_UT", now_ut, "SOL", FALSE).
}

// p30_solve: S30.1. Reads TIG and the delta-V from the store, gets the state at TIG from predict and returns
// LEXICON("OK", bool, "WHY", text, "XD", the five-key XDELV lexicon, "APO_M", .., "PERI_M", .., "MGA", degrees).
FUNCTION p30_solve {
  PARAMETER prog.
  LOCAL vault IS prog["VAULT"].
  LOCAL why IS p30_refusal(vault, prog["CLOCK_ZERO"], prog["NOW_UT"]).
  IF why <> "" { RETURN LEXICON("OK", FALSE, "WHY", why). }
  LOCAL tig_ut IS prog["CLOCK_ZERO"] + lm_store_get_tig(vault).
  LOCAL state_tig IS prog["PREDICT"]:CALL(tig_ut).
  LOCAL r_tig IS state_tig["R"].
  LOCAL v_tig IS state_tig["V"].
  LOCAL lv_vec IS lm_store_get_dv(vault).
  LOCAL dv_vec IS plan_lv_to_dv(LIST(lv_vec:X, lv_vec:Y, lv_vec:Z), r_tig, v_tig).
  LOCAL mu_body IS SHIP:BODY:MU.
  LOCAL radius_body IS SHIP:BODY:RADIUS.
  IF state_tig:HASKEY("MU") { SET mu_body TO state_tig["MU"]. }
  IF state_tig:HASKEY("RADIUS") { SET radius_body TO state_tig["RADIUS"]. }
  LOCAL apsides IS p30_apsides(r_tig, v_tig, dv_vec, mu_body, radius_body).
  LOCAL mga_deg IS 0.
  IF dv_vec:MAG > 0 { SET mga_deg TO p30_mga(s40_1(dv_vec)["UT"], VCRS(r_tig, v_tig)). }       // no direction with no delta-V: zero, not NaN
  LOCAL xd IS LEXICON("DELVSIN", dv_vec, "RTIG", r_tig, "VTIG", v_tig, "UT_TIG", tig_ut, "DELVSAB", dv_vec:MAG, "T0", prog["NOW_UT"]).       // T0: the UT these vectors are in the raw axes of (the axes turn with the Moon; P40 turns them to its own time)
  IF DEFINED LM_VEH { IF LM_VEH:HASKEY("XDELV") { IF LM_VEH["XDELV"]:ISTYPE("Lexicon") { SET LM_VEH["XDELV"] TO xd. } } }       // the flag is up already: new erasables
  RETURN LEXICON("OK", TRUE, "WHY", "", "XD", xd, "APO_M", apsides["APO_M"], "PERI_M", apsides["PERI_M"], "MGA", mga_deg).
}

// p30_flag_set: XDELVFLG up, with the P30 results for P40 and P41.
FUNCTION p30_flag_set {
  PARAMETER prog.
  IF DEFINED LM_VEH { SET LM_VEH["XDELV"] TO prog["SOL"]["XD"]. }
}

// p30_state_vn: the verb and noun of a state's flashing display.
FUNCTION p30_state_vn {
  PARAMETER state_name.
  IF state_name = "N33" { RETURN LIST(6, 33). }
  IF state_name = "N81" { RETURN LIST(6, 81). }
  IF state_name = "N42" { RETURN LIST(6, 42). }
  RETURN LIST(16, 45).
}

// p30_step: one cycle. The states are the four flashing displays in order: N33, N81, N42, N45. V34 ends the programme (to P00) at any of them, PRO goes
// on (N45's PRO ends it), V32 or an ENTR that answers the displayed request shows the display again. After N81's PRO the programme solves S30.1; if that
// fails (TIG passed meanwhile) it ends with a message. The caller sets prog["NOW_UT"] each cycle (the vehicle adapter does).
// Output keys are those of the other steps; EXTRA carries P30_APO and P30_PERI (m), P30_DV (m/s), P30_TTOGO (s) and P30_MGA (degrees) for N42 and N45.
FUNCTION p30_step {
  PARAMETER prog, ks.
  LOCAL ans IS resp_read(ks).
  LOCAL state_now IS prog["STATE"].
  LOCAL vn_now IS p30_state_vn(state_now).
  LOCAL redisplay IS ans["V32"] OR lm_entr_on_request(ks, vn_now[0], vn_now[1]).
  LOCAL message IS "".
  IF ans["TERM"] {
    SET prog["ENDED"] TO TRUE.
  } ELSE IF ans["PRO"] {
    IF state_now = "N33" {
      SET prog["STATE"] TO "N81".
    } ELSE IF state_now = "N81" {
      LOCAL sol IS p30_solve(prog).
      IF sol["OK"] {
        SET prog["SOL"] TO sol.
        SET prog["STATE"] TO "N42".
        // One line per S30.1 solve for the VELOCITYAT probe (batch 1.4a): the N42 apsides and whether a KSP node was ahead. Always written
        // (like rod.log, one short line, not tied to LM_LOG) so the numbers can be read without a screenshot.
        LOG "UT " + ROUND(prog["NOW_UT"], 1) + ", node ahead " + HASNODE + ", TIG UT " + ROUND(sol["XD"]["UT_TIG"], 2) + ", N42 apo " + ROUND(sol["APO_M"] / 185.2) + " peri "
          + ROUND(sol["PERI_M"] / 185.2) + " (0.1 nm), apo " + ROUND(sol["APO_M"]) + " m, peri " + ROUND(sol["PERI_M"]) + " m, dv " + ROUND(sol["XD"]["DELVSAB"], 3) + " m/s" TO "0:/lm/logs/p30.log".
        IF prog["PROFILE"] = "J" { p30_flag_set(prog). }          // 210: XDELVFLG before N42
      } ELSE {
        SET message TO "P30: " + sol["WHY"] + ".".
        SET prog["ENDED"] TO TRUE.
      }
    } ELSE IF state_now = "N42" {
      IF prog["PROFILE"] <> "J" { p30_flag_set(prog). }           // 099: XDELVFLG after N42
      SET prog["STATE"] TO "N45".
    } ELSE {
      SET prog["ENDED"] TO TRUE.                                  // N45: PRO exits to P00
    }
    SET prog["SHOWN"] TO FALSE.
  } ELSE IF redisplay {
    SET prog["SHOWN"] TO FALSE.
  }
  LOCAL vn_out IS p30_state_vn(prog["STATE"]).
  LOCAL set_verb IS -1.
  LOCAL set_noun IS -1.
  IF NOT prog["ENDED"] AND NOT prog["SHOWN"] {
    SET prog["SHOWN"] TO TRUE.
    SET set_verb TO vn_out[0].
    SET set_noun TO vn_out[1].
  }
  LOCAL apo_m IS 0.
  LOCAL peri_m IS 0.
  LOCAL dv_ms IS 0.
  LOCAL ttogo_s IS 0.
  LOCAL mga_deg IS 0.
  IF prog["SOL"]:ISTYPE("Lexicon") {
    SET apo_m TO prog["SOL"]["APO_M"].
    SET peri_m TO prog["SOL"]["PERI_M"].
    SET dv_ms TO prog["SOL"]["XD"]["DELVSAB"].
    SET ttogo_s TO MAX(0, prog["SOL"]["XD"]["UT_TIG"] - prog["NOW_UT"]).
    SET mga_deg TO prog["SOL"]["MGA"].
  }
  LOCAL request IS FALSE.
  IF NOT prog["ENDED"] { SET request TO LEXICON("VERB", vn_out[0], "NOUN", vn_out[1]). }
  LOCAL extra IS LEXICON("P30_APO", apo_m, "P30_PERI", peri_m, "P30_DV", dv_ms, "P30_TTOGO", ttogo_s, "P30_MGA", mga_deg).
  RETURN LEXICON("SET_VERB", set_verb, "SET_NOUN", set_noun, "KEY_REL", FALSE, "BLANK", FALSE, "FLASH", FALSE, "REQUEST", request,
                 "ALARM", 0, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE, "EXTRA", extra, "MSG", message, "ENDED", prog["ENDED"], "HANDOVER", FALSE,
                 "PROG_NO", 30, "CONTACT", FALSE, "STATUS", LIST()).
}

// p30_end: P30 takes nothing over (it fires nothing and holds no lock), so nothing is given back.
FUNCTION p30_end {
  PARAMETER prog.
}
