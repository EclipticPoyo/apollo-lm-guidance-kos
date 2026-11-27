// lm_rndz.ks -- rendezvous targeting maths for P32 and P33. Pure: reads nothing from kOS but constants.
//
// Ported from Luminary 210, P32-P35,_P72-P75.agc:
//   CSI/A    (lines 681-1150)   -> rndz_csi (constants: lines 666-679)
//   ROTATE   (lines 1191-1198)  -> rndz_into_plane
//   S32/33.X (lines 1245-1255)  -> rndz_fwd
//   CDHMVR   (lines 1266-1362)  -> rndz_cdh (and rndz_target_at, rndz_apsis_time)
// Positions and velocities are from the Moon's centre in any non-rotating axes; m, m/s, seconds, degrees.
// nrm is the CSM's orbit normal, unit(lm_cross(rt, vt)). Reference model: scripts/tests/reference_rndz.py.

RUNONCEPATH("0:/shared/lm_conics.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").      // lm_cross

GLOBAL RNDZ_FIRST_STEP IS 3.048.        // m/s, first change of the CSI delta-V
GLOBAL RNDZ_STEP_LIMIT IS 60.96.        // m/s, largest Newton step
GLOBAL RNDZ_CONVERGED IS 0.03048.       // m/s, step size that counts as solved
GLOBAL RNDZ_DV_LIMIT IS 304.8.          // m/s, largest CSI delta-V
GLOBAL RNDZ_DV_CLAMP IS 301.4472.       // m/s, where it is put back to the first time it passes the limit
GLOBAL RNDZ_JUMP IS 15.24.              // m/s, search step of the second cycle
GLOBAL RNDZ_MAX_COUNT IS 16.            // iteration limit of one cycle
GLOBAL RNDZ_MIN_PERILUNE IS 10668.      // m above the mean radius, after CSI and after CDH
GLOBAL RNDZ_MIN_GAP IS 600.             // s, CSI to CDH and CDH to TPI
GLOBAL RNDZ_APSIS_RDOT IS 2.1336.       // m/s (7 ft/s): slower than this in the radial direction counts as an apsis
GLOBAL RNDZ_MAX_TRIALS IS 100.          // not Luminary: a guard so that kOS can never loop for ever

FUNCTION rndz_sign {
  PARAMETER value.
  IF value < 0 { RETURN -1. }
  RETURN 1.
}

// rndz_angle: the angle between two vectors, 0 to 180 degrees. ARCTAN2 stays accurate for very small angles.
FUNCTION rndz_angle {
  PARAMETER a_vec, b_vec.
  RETURN ARCTAN2(lm_cross(a_vec, b_vec):MAG, VDOT(a_vec, b_vec)).
}

// rndz_fwd: the forward horizontal direction at pos_vec, in the CSM's orbit plane.
FUNCTION rndz_fwd {
  PARAMETER nrm, pos_vec.
  RETURN lm_cross(nrm, pos_vec):NORMALIZED.
}

// ROTATE: vec turned into the CSM's orbit plane, keeping its length.
FUNCTION rndz_into_plane {
  PARAMETER vec, nrm.
  LOCAL flat IS vec - nrm * VDOT(vec, nrm).
  IF flat:MAG = 0 { RETURN vec. }
  RETURN flat:NORMALIZED * vec:MAG.
}

// rndz_target_at: the target's state where its radius vector lies along dir_unit (a unit vector in its plane),
// read from the shape of its orbit with no time involved. (e cos f, e sin f) is turned by the angle theta from the
// target's present position, then radius = P / (1 + e cos f), radial speed = SQRT(mu/P) e sin f and
// horizontal speed = SQRT(mu/P) (1 + e cos f). Returns LEXICON("OK", "R", "V").
FUNCTION rndz_target_at {
  PARAMETER rt, vt, dir_unit, nrm, mu_val.
  LOCAL el IS conic_elements(rt, vt, mu_val).
  LOCAL theta IS ARCTAN2(VDOT(dir_unit, rndz_fwd(nrm, rt)), VDOT(dir_unit, rt:NORMALIZED)).
  LOCAL ecos IS el["EC"] * COS(theta) - el["ES"] * SIN(theta).
  LOCAL esin IS el["ES"] * COS(theta) + el["EC"] * SIN(theta).
  IF el["P"] <= 0 OR 1 + ecos <= 0 { RETURN LEXICON("OK", FALSE, "R", rt, "V", vt). }
  LOCAL speed_unit IS SQRT(mu_val / el["P"]).
  RETURN LEXICON("OK", TRUE, "R", dir_unit * (el["P"] / (1 + ecos)),
      "V", dir_unit * (speed_unit * esin) + rndz_fwd(nrm, dir_unit) * (speed_unit * (1 + ecos))).
}

// rndz_apsis_time: seconds from CSI to CDH, which is the nn-th apsis after CSI. A nearly circular orbit, a CSI at an
// apsis, or force_half, gives nn half periods. Returns -1 when the orbit is not an ellipse.
FUNCTION rndz_apsis_time {
  PARAMETER pos_vec, vel_vec, mu_val, nn, force_half.
  LOCAL el IS conic_elements(pos_vec, vel_vec, mu_val).
  IF el["ALPHA"] <= 0 { RETURN -1. }
  LOCAL sma IS 1 / el["ALPHA"].
  LOCAL half IS CONSTANT:PI * SQRT(sma ^ 3 / mu_val).
  IF force_half OR el["ECC"] < 0.0001 OR ABS(el["RDOT"]) < RNDZ_APSIS_RDOT { RETURN nn * half. }
  // Time from periapsis to the point of the same height on the rising side (0 to half a period).
  LOCAL from_peri IS conic_time_from_peri(el["ECC"], ABS(el["ES"]) / el["ECC"], el["EC"] / el["ECC"], sma, mu_val).
  IF el["RDOT"] >= 0 { RETURN nn * half - from_peri. }
  RETURN nn * half - (half - from_peri).
}

// CDHMVR: the coelliptic burn at the LM state (ra, va). The new orbit is the one "parallel" to the CSM's: the same
// height difference DH below it, semi-major axes DH apart, and the radial speed scaled by (a_csm/a_lm)^1.5.
// Returns LEXICON("OK", "V3" velocity after the burn, "DV" the burn, "DH" height of the CSM above the LM).
FUNCTION rndz_cdh {
  PARAMETER ra, va, rt, vt, nrm, mu_val.
  LOCAL failed IS LEXICON("OK", FALSE, "V3", va, "DV", V(0, 0, 0), "DH", 0).
  IF ra:MAG <= 0 { RETURN failed. }
  LOCAL ra_unit IS ra:NORMALIZED.
  LOCAL tgt IS rndz_target_at(rt, vt, ra_unit, nrm, mu_val).
  IF NOT tgt["OK"] { RETURN failed. }
  LOCAL tgt_r IS tgt["R"]:MAG.
  LOCAL dh IS tgt_r - ra:MAG.
  LOCAL denom IS 2 - tgt_r * tgt["V"]:SQRMAGNITUDE / mu_val.
  IF denom <= 0 { RETURN failed. }
  LOCAL sma_tgt IS tgt_r / denom.
  LOCAL sma_lm IS sma_tgt - dh.
  IF sma_lm <= 0 { RETURN failed. }
  LOCAL radial IS VDOT(tgt["V"], ra_unit) * (sma_tgt / sma_lm) ^ 1.5.
  LOCAL level_sq IS mu_val * (2 / ra:MAG - 1 / sma_lm) - radial * radial.
  IF level_sq < 0 { RETURN failed. }
  LOCAL v3 IS rndz_fwd(nrm, ra) * SQRT(level_sq) + ra_unit * radial.
  RETURN LEXICON("OK", TRUE, "V3", v3, "DV", v3 - va, "DH", dh).
}

// rndz_csi_trial: one trial CSI delta-V carried through CSI -> CDH -> TPI. "FAIL" is an alarm code or 0. "MISS" means
// the elevation line from the LM at TPI never reaches the CSM's radius. "G" is the error angle, degrees: from the
// CSM at TPI to the point where that line meets the CSM's radius.
FUNCTION rndz_csi_trial {
  PARAMETER inp, nrm, level_dir, rt3, vt3, dv.
  LOCAL mu_val IS inp["MU"].
  LOCAL v4 IS inp["V1"] + level_dir * dv.
  IF conic_elements(inp["R1"], v4, mu_val)["ALPHA"] <= 0 { RETURN LEXICON("FAIL", 606, "MISS", FALSE). }
  LOCAL tcdh IS inp["TCSI"] + rndz_apsis_time(inp["R1"], v4, mu_val, inp["NN"], inp["FORCE_HALF"]).
  IF tcdh > inp["TTPI"] { RETURN LEXICON("FAIL", 604, "MISS", FALSE). }
  LOCAL lm2 IS conic_kepler(inp["R1"], v4, tcdh - inp["TCSI"], mu_val).
  LOCAL tg2 IS conic_kepler(inp["RT"], inp["VT"], tcdh - inp["TCSI"], mu_val).
  IF NOT lm2["OK"] OR NOT tg2["OK"] { RETURN LEXICON("FAIL", 605, "MISS", FALSE). }
  LOCAL man IS rndz_cdh(lm2["R"], lm2["V"], tg2["R"], tg2["V"], nrm, mu_val).
  IF NOT man["OK"] { RETURN LEXICON("FAIL", 605, "MISS", FALSE). }
  LOCAL lm3 IS conic_kepler(lm2["R"], man["V3"], inp["TTPI"] - tcdh, mu_val).
  IF NOT lm3["OK"] { RETURN LEXICON("FAIL", 605, "MISS", FALSE). }
  LOCAL ra3 IS lm3["R"].
  // The line of sight at the wanted elevation, and where it meets the sphere of the CSM's radius: |ra3 + k u| = |rt3|.
  LOCAL sight IS rndz_fwd(nrm, ra3) * COS(inp["ELEV"]) + ra3:NORMALIZED * SIN(inp["ELEV"]).
  LOCAL along IS VDOT(sight, ra3).
  LOCAL disc IS along * along - ra3:SQRMAGNITUDE + rt3:SQRMAGNITUDE.
  IF disc < 0 { RETURN LEXICON("FAIL", 0, "MISS", TRUE). }
  LOCAL reach IS -along + SQRT(disc).
  IF ABS(-along - SQRT(disc)) < ABS(reach) { SET reach TO -along - SQRT(disc). }
  LOCAL meet IS (ra3 + sight * reach):NORMALIZED.
  LOCAL side IS rndz_sign(VDOT(lm_cross(rt3:NORMALIZED, meet), lm_cross(vt3:NORMALIZED, rt3:NORMALIZED))).
  RETURN LEXICON("FAIL", 0, "MISS", FALSE, "G", side * rndz_angle(meet, rt3), "V4", v4, "TCDH", tcdh,
      "R2", lm2["R"], "CDH", man, "R3", ra3, "V3T", lm3["V"]).
}

// rndz_csi_checks: the tests made on the converged answer. Returns an alarm code, or 0.
FUNCTION rndz_csi_checks {
  PARAMETER inp, trial.
  LOCAL after_csi IS conic_elements(inp["R1"], trial["V4"], inp["MU"]).
  IF after_csi["P"] / (1 + after_csi["ECC"]) - inp["RADIUS"] < RNDZ_MIN_PERILUNE { RETURN 601. }
  LOCAL after_cdh IS conic_elements(trial["R2"], trial["CDH"]["V3"], inp["MU"]).
  IF after_cdh["P"] / (1 + after_cdh["ECC"]) - inp["RADIUS"] < RNDZ_MIN_PERILUNE { RETURN 602. }
  IF trial["TCDH"] - inp["TCSI"] < RNDZ_MIN_GAP { RETURN 603. }
  IF inp["TTPI"] - trial["TCDH"] < RNDZ_MIN_GAP { RETURN 604. }
  RETURN 0.
}

// CSI/A: find the horizontal CSI delta-V that, followed by the coelliptic burn, gives the wanted elevation of the CSM
// at the TPI time. inp: LEXICON of
//   "R1","V1"  LM at CSI, already in the CSM's plane     "RT","VT"  CSM at the CSI time
//   "TCSI","TTPI" s    "NN" apsis number of CDH    "ELEV" deg    "FORCE_HALF"    "MU","RADIUS"
// Returns "OK", "ALARM" (0, or 600-606) and "COUNT"; when OK also "DV" (signed, + = forward), "DV1" (the CSI burn),
// "TCDH", "DH", "R2" (LM at CDH), "DV2" (the CDH burn), "R3","V3T" (LM at TPI), "RT3","VT3" (CSM at TPI), "NORMAL".
//
// Alarms: 600 no solution on the first pass, 601 perilune after CSI too low, 602 after CDH, 603 CSI to CDH too short,
// 604 CDH to TPI too short, 605 iterations or no solution, 606 delta-V over the limit.
//
// The delta-V is driven to zero error angle by Newton's method with a numerical slope, starting from a Hohmann
// guess (phase "01"). If that fails, a second cycle walks in 15.24 m/s steps (phases "00", "11") until the error
// starts to shrink, then uses Newton again (phase "10"). A second failure reports the first cycle's alarm.
FUNCTION rndz_csi {
  PARAMETER inp.
  LOCAL mu_val IS inp["MU"].
  IF inp["R1"]:MAG <= 0 OR lm_cross(inp["RT"], inp["VT"]):MAG <= 0 {
    RETURN LEXICON("OK", FALSE, "ALARM", 605, "COUNT", 0).
  }
  LOCAL nrm IS lm_cross(inp["RT"], inp["VT"]):NORMALIZED.
  LOCAL tg3 IS conic_kepler(inp["RT"], inp["VT"], inp["TTPI"] - inp["TCSI"], mu_val).
  IF NOT tg3["OK"] { RETURN LEXICON("OK", FALSE, "ALARM", 605, "COUNT", 0). }
  LOCAL rt3 IS tg3["R"].
  LOCAL vt3 IS tg3["V"].
  LOCAL level_dir IS rndz_fwd(nrm, inp["R1"]).
  LOCAL r1_mag IS inp["R1"]:MAG.
  LOCAL hohmann IS SQRT(2 * mu_val / (r1_mag * (1 + r1_mag / rt3:MAG))) - VDOT(inp["V1"], level_dir).

  LOCAL phase IS "01".
  LOCAL saved IS 0.
  LOCAL dv IS hohmann.
  LOCAL inc IS RNDZ_FIRST_STEP.
  LOCAL count IS 0.
  LOCAL counted IS TRUE.
  LOCAL exceeded IS FALSE.
  LOCAL first IS TRUE.
  LOCAL g_prev IS 0.
  LOCAL dv_prev IS 0.
  LOCAL trials IS 0.
  UNTIL FALSE {
    LOCAL code IS 0.                      // an alarm raised on this pass
    IF counted {
      SET count TO count + 1.
      IF count >= RNDZ_MAX_COUNT { SET code TO 605. }
    }
    SET counted TO TRUE.
    SET trials TO trials + 1.
    IF trials > RNDZ_MAX_TRIALS { RETURN LEXICON("OK", FALSE, "ALARM", 605, "COUNT", count). }
    IF code = 0 AND ABS(dv) >= RNDZ_DV_LIMIT {
      IF exceeded OR phase = "11" {
        SET code TO 606.
      } ELSE {
        SET exceeded TO TRUE.
        SET dv TO rndz_sign(dv) * RNDZ_DV_CLAMP.
      }
    }
    IF code = 0 {
      LOCAL trial IS rndz_csi_trial(inp, nrm, level_dir, rt3, vt3, dv).
      IF trial["FAIL"] > 0 {
        SET code TO trial["FAIL"].
      } ELSE IF trial["MISS"] {
        IF count = 1 { RETURN LEXICON("OK", FALSE, "ALARM", 600, "COUNT", count). }
        SET inc TO inc / 2.
        SET dv TO dv_prev - inc.
      } ELSE IF first {
        SET g_prev TO trial["G"].
        SET dv_prev TO dv.
        SET dv TO dv - inc.
        SET first TO FALSE.
      } ELSE IF dv = dv_prev {
        SET code TO 605.
      } ELSE {
        LOCAL g_err IS trial["G"].
        LOCAL slope IS (g_err - g_prev) / (dv - dv_prev).
        SET dv_prev TO dv.
        IF phase = "11" AND (g_err - g_prev) * g_prev < 0 {
          SET inc TO rndz_sign(inc) * RNDZ_FIRST_STEP.
          SET phase TO "10".
          SET g_prev TO g_err.
          SET dv TO dv - inc.
        } ELSE IF phase = "11" OR phase = "00" {
          SET inc TO -RNDZ_JUMP * rndz_sign(slope) * rndz_sign(g_prev).
          SET dv TO dv - inc.
          SET g_prev TO g_err.
          SET phase TO "11".
          SET counted TO FALSE.
        } ELSE IF slope = 0 {
          SET code TO 605.
        } ELSE {
          SET inc TO g_err / slope.
          SET g_prev TO g_err.
          IF ABS(inc) < RNDZ_CONVERGED {
            SET code TO rndz_csi_checks(inp, trial).
            IF code = 0 {
              RETURN LEXICON("OK", TRUE, "ALARM", 0, "COUNT", count, "DV", dv, "DV1", trial["V4"] - inp["V1"],
                  "TCDH", trial["TCDH"], "DH", trial["CDH"]["DH"], "R2", trial["R2"], "DV2", trial["CDH"]["DV"],
                  "R3", trial["R3"], "V3T", trial["V3T"], "RT3", rt3, "VT3", vt3, "NORMAL", nrm).
            }
          } ELSE {
            IF ABS(inc) >= RNDZ_STEP_LIMIT { SET inc TO rndz_sign(inc) * RNDZ_STEP_LIMIT. }
            SET dv TO dv - inc.
          }
        }
      }
    }
    IF code > 0 {
      IF phase <> "01" { RETURN LEXICON("OK", FALSE, "ALARM", saved, "COUNT", count). }
      // The second cycle: start again from the Hohmann guess, remembering this alarm.
      SET saved TO code.
      SET phase TO "00".
      SET dv TO hohmann.
      SET inc TO RNDZ_FIRST_STEP.
      SET count TO 0.
      SET counted TO TRUE.
      SET exceeded TO FALSE.
      SET first TO TRUE.
    }
  }
}

// ---- TPI time for an elevation angle ---------------------------------------------------------------------------
// Ported from Luminary 210, P34-P35,_P74-P75.agc: S33/34.1 (lines 471-677), the elevation angle of S34/35.1
// (lines 685-695), constants lines 1047-1049.

GLOBAL RNDZ_TPI_STEP_MAX IS 250.        // s, first limit on one change of the time
GLOBAL RNDZ_TPI_PASSES IS 15.
GLOBAL RNDZ_TPI_CLOSE IS 0.1.           // deg, elevation error that counts as found

// rndz_elevation: the angle of the line to the target, from the LM's forward horizontal towards straight up,
// 0 to 360 degrees.
FUNCTION rndz_elevation {
  PARAMETER ra, va, rt.
  LOCAL ra_unit IS ra:NORMALIZED.
  LOCAL sight IS (rt - ra):NORMALIZED.
  LOCAL ahead IS (va - ra_unit * VDOT(va, ra_unit)):NORMALIZED.
  LOCAL angle IS ARCTAN2(VDOT(sight, ra_unit), VDOT(sight, ahead)).
  IF angle < 0 { SET angle TO angle + 360. }
  RETURN angle.
}

// rndz_tpi_result: the answer of the search. "DT" is added to the nominal TPI time; the states are at that time.
FUNCTION rndz_tpi_result {
  PARAMETER why, dt, passes, ra, va, rt, vt.
  RETURN LEXICON("OK", why = "", "WHY", why, "DT", dt, "EA", rndz_elevation(ra, va, rt), "PASSES", passes,
      "RA", ra, "VA", va, "RT", rt, "VT", vt).
}

// S33/34.1: find the time near the nominal TPI time at which the CSM is at the elevation elev_deg. The states
// (ra, va) LM and (rt, vt) CSM are at the nominal time.
// Each pass estimates the time change from circular-orbit geometry: theta is the central angle between the craft
// that would give the wanted elevation, alpha the angle there is now, and (alpha - theta) / (difference of the
// angular rates) the time to close the gap. The step is limited, and shortened or turned round when the error
// changes sign or grows.
// "WHY" is "" on success, else "geometry" (this elevation cannot be reached), "rate" (no closing rate),
// "conic" (propagation failed) or "passes" (not found in 15 passes).
FUNCTION rndz_tpi_time {
  PARAMETER ra, va, rt, vt, elev_deg, mu_val.
  LOCAL step_max IS RNDZ_TPI_STEP_MAX.
  LOCAL total IS 0.
  LOCAL prev_inc IS 0.
  LOCAL err_old IS 0.
  LOCAL lm_r IS ra.
  LOCAL lm_v IS va.
  LOCAL tg_r IS rt.
  LOCAL tg_v IS vt.
  LOCAL pass_no IS 0.
  UNTIL pass_no >= RNDZ_TPI_PASSES {
    SET pass_no TO pass_no + 1.
    LOCAL err IS rndz_elevation(lm_r, lm_v, tg_r) - elev_deg.          // no wrap, as in the source
    IF ABS(err) < RNDZ_TPI_CLOSE { RETURN rndz_tpi_result("", total, pass_no, lm_r, lm_v, tg_r, tg_v). }
    LOCAL lm_mag IS lm_r:MAG.
    LOCAL tg_mag IS tg_r:MAG.
    IF lm_mag <= 0 OR tg_mag <= 0 { RETURN rndz_tpi_result("geometry", total, pass_no, lm_r, lm_v, tg_r, tg_v). }
    LOCAL higher IS rndz_sign(tg_mag - lm_mag).
    LOCAL cos_arg IS COS(elev_deg) * lm_mag / tg_mag.
    IF higher * (180 - elev_deg) < 0 OR ABS(cos_arg) > 1 {
      RETURN rndz_tpi_result("geometry", total, pass_no, lm_r, lm_v, tg_r, tg_v).
    }
    LOCAL lm_up IS lm_r:NORMALIZED.
    LOCAL tg_up IS tg_r:NORMALIZED.
    LOCAL rate IS (lm_v - lm_up * VDOT(lm_v, lm_up)):MAG / lm_mag - (tg_v - tg_up * VDOT(tg_v, tg_up)):MAG / tg_mag.
    IF ABS(rate) < 0.000000001 { RETURN rndz_tpi_result("rate", total, pass_no, lm_r, lm_v, tg_r, tg_v). }
    // Angles in radians. alpha is positive when the CSM is ahead.
    LOCAL alpha IS rndz_sign(VDOT(lm_cross(lm_r, tg_r), lm_cross(lm_r, lm_v)))
        * rndz_angle(lm_r, tg_r) * CONSTANT:DEGTORAD.
    LOCAL theta IS CONSTANT:PI - elev_deg * CONSTANT:DEGTORAD
        - higher * (CONSTANT:PI - ARCCOS(MAX(-1, MIN(1, cos_arg))) * CONSTANT:DEGTORAD).
    LOCAL change IS MAX(-step_max, MIN(step_max, (alpha - theta) / rate)).
    LOCAL inc IS change.
    IF pass_no = 1 {
      SET prev_inc TO inc.
    } ELSE IF err * err_old < 0 {
      SET step_max TO step_max / 3.                                   // change was limited with the old step_max
      SET inc TO -rndz_sign(prev_inc) * ABS(change) / 2.
      SET prev_inc TO inc.
    } ELSE IF ABS(err_old) < ABS(err) {
      SET inc TO -1.5 * prev_inc.
      SET prev_inc TO -prev_inc / 2.
    } ELSE {
      SET inc TO ABS(change) * rndz_sign(prev_inc).
      SET prev_inc TO inc.
    }
    SET err_old TO err.
    SET total TO total + inc.
    LOCAL lm_new IS conic_kepler(ra, va, total, mu_val).             // always from the nominal states
    LOCAL tg_new IS conic_kepler(rt, vt, total, mu_val).
    IF NOT lm_new["OK"] OR NOT tg_new["OK"] {
      RETURN rndz_tpi_result("conic", total, pass_no, lm_r, lm_v, tg_r, tg_v).
    }
    SET lm_r TO lm_new["R"].
    SET lm_v TO lm_new["V"].
    SET tg_r TO tg_new["R"].
    SET tg_v TO tg_new["V"].
  }
  RETURN rndz_tpi_result("passes", total, pass_no, lm_r, lm_v, tg_r, tg_v).
}

// ---- TPI and midcourse (release 1.5, stage 2) -------------------------------------------------------------------
// Ported from Luminary 210, P34-P35,_P74-P75.agc: S34/35.1 to S34/35.4 (lines 685-821) and INITVEL's cone (lines
// 1049-1053). The Lambert solution is our own (lm_conics.ks). The precision offset passes (NN above 0) are left
// out: in two-body gravity the conic already reaches the target.

GLOBAL RNDZ_CONE_DEG IS 15.             // deg, targeting treats a transfer this close to 180 degrees in the LM's plane (EPSFOUR)

// rndz_central_angle: the angle the LM travels from pos_a to pos_aim, 0 to 360 along its motion (ACTCENT, N52).
FUNCTION rndz_central_angle {
  PARAMETER pos_a, vel_a, pos_aim.
  LOCAL normal IS lm_cross(pos_a, vel_a):NORMALIZED.
  LOCAL angle IS ARCTAN2(VDOT(lm_cross(pos_a, pos_aim), normal), VDOT(pos_a, pos_aim)).
  IF angle < 0 { SET angle TO angle + 360. }
  RETURN angle.
}

// rndz_los_dv: a delta-V along the line of sight to the target at pos_p, to the right of it and downward (S34/35.4,
// N59): V(along, right, down). "Down" is square to the line of sight in the LM's orbit plane, "right" is down x along.
FUNCTION rndz_los_dv {
  PARAMETER dv_vec, pos_a, vel_a, pos_p.
  LOCAL along IS (pos_p - pos_a):NORMALIZED.
  LOCAL normal IS lm_cross(pos_a, vel_a):NORMALIZED.
  LOCAL down_dir IS lm_cross(normal, along):NORMALIZED.
  LOCAL right_dir IS lm_cross(down_dir, along).
  RETURN V(VDOT(dv_vec, along), VDOT(dv_vec, right_dir), VDOT(dv_vec, down_dir)).
}

// rndz_transfer: the burn that takes the LM (pos_a, vel_a at the burn time) to the CSM's position tof_s seconds later
// (pos_t, vel_t are the CSM at the burn time). S34/35.2.
// Returns LEXICON("OK", "WHY", "DV", "V1" the velocity after the burn, "AIM" the point aimed at, "ROTATED" (the aim
// point was turned into the LM's plane), "DVTPF" the delta-V to match the CSM at the intercept, "ANGLE" the central
// angle to the CSM's position at the intercept).
FUNCTION rndz_transfer {
  PARAMETER pos_a, vel_a, pos_t, vel_t, tof_s, mu_val.
  LOCAL failed IS LEXICON("OK", FALSE, "WHY", "time", "DV", V(0, 0, 0), "V1", vel_a, "AIM", pos_t, "ROTATED", FALSE, "DVTPF", 0, "ANGLE", 0).
  IF tof_s <= 0 { RETURN failed. }
  LOCAL there IS conic_kepler(pos_t, vel_t, tof_s, mu_val).
  IF NOT there["OK"] { SET failed["WHY"] TO "conic". RETURN failed. }
  LOCAL arc IS conic_lambert(pos_a, there["R"], tof_s, mu_val, vel_a, RNDZ_CONE_DEG).
  IF NOT arc["OK"] { SET failed["WHY"] TO arc["WHY"]. RETURN failed. }
  RETURN LEXICON("OK", TRUE, "WHY", "", "DV", arc["V1"] - vel_a, "V1", arc["V1"], "AIM", arc["AIM"], "ROTATED", arc["ROTATED"],
      "DVTPF", (there["V"] - arc["V2"]):MAG, "ANGLE", rndz_central_angle(pos_a, vel_a, there["R"])).
}

// ---- Pointing and relative motion (release 1.5, stage 3) --------------------------------------------------------
// Luminary 210: V83 (R31.agc), V90 (R36, P34-P35,_P74-P75.agc 1683-1756), the aimed attitude of R61 and R63. Right-handed maths as above.

// rndz_wrap_deg: an angle in 0 to 360 degrees for the display: one that would show as 360.00 is 0.
FUNCTION rndz_wrap_deg {
  PARAMETER angle_deg.
  LOCAL wrapped IS MOD(angle_deg + 360, 360).
  IF wrapped >= 359.995 { RETURN 0. }
  RETURN wrapped.
}

// rndz_range_rate: LIST(range in metres, range rate in m/s along the line of sight; negative closing).
FUNCTION rndz_range_rate {
  PARAMETER pos_a, vel_a, pos_t, vel_t.
  LOCAL line IS pos_t - pos_a.
  RETURN LIST(line:MAG, VDOT(vel_t - vel_a, line:NORMALIZED)).
}

// rndz_theta: where an axis of the LM points in its own vertical sense (V83 R3, N54): 0 forward horizontal, 90 straight up, 180 backward,
// 270 straight down. The angle is the axis's height over its horizontal part, counted as behind when it leans backward.
FUNCTION rndz_theta {
  PARAMETER pos_a, vel_a, axis_vec.
  LOCAL up_dir IS pos_a:NORMALIZED.
  LOCAL fwd_dir IS VECTOREXCLUDE(up_dir, vel_a):NORMALIZED.
  LOCAL flat IS VECTOREXCLUDE(up_dir, axis_vec):MAG.
  IF VDOT(axis_vec, fwd_dir) < 0 { SET flat TO -flat. }
  RETURN rndz_wrap_deg(ARCTAN2(VDOT(axis_vec, up_dir), flat)).
}

// rndz_r36: LIST(Y, YDOT, psi). Y and YDOT: the LM's distance and speed out of the CSM's orbit plane, along unit(V x R) of the CSM. psi: the
// bearing of the line of sight in the LM's horizontal plane, from forward towards the right, 0 to 360.
FUNCTION rndz_r36 {
  PARAMETER pos_a, vel_a, pos_t, vel_t.
  LOCAL side IS lm_cross(vel_t, pos_t):NORMALIZED.
  LOCAL up_dir IS pos_a:NORMALIZED.
  LOCAL fwd_dir IS VECTOREXCLUDE(up_dir, vel_a):NORMALIZED.
  LOCAL right_dir IS lm_cross(fwd_dir, up_dir).
  LOCAL line IS pos_t - pos_a.
  LOCAL psi IS rndz_wrap_deg(ARCTAN2(VDOT(line, right_dir), VDOT(line, fwd_dir))).
  RETURN LIST(VDOT(pos_a, side), VDOT(vel_a, side), psi).
}

// rndz_los_clear: FALSE when the straight line between the two craft passes inside the sphere of radius_m about the body's centre.
FUNCTION rndz_los_clear {
  PARAMETER pos_a, pos_t, radius_m.
  LOCAL line IS pos_t - pos_a.
  LOCAL length2 IS line:SQRMAGNITUDE.
  LOCAL along IS 0.
  IF length2 > 0 { SET along TO MAX(0, MIN(1, -VDOT(pos_a, line) / length2)). }
  RETURN (pos_a + line * along):MAG >= radius_m.
}

// rndz_aim_axis: other_axis (square to from_axis) carried by the smallest rotation that takes from_axis to to_dir, so that an axis can be put on
// a line of sight with no needless roll about it. other_axis comes back unchanged when the turn is (nearly) a half turn.
//   v' = v - ((v . t) / (1 + f . t)) (f + t)        for unit f, t and v square to f
FUNCTION rndz_aim_axis {
  PARAMETER from_axis, to_dir, other_axis.
  LOCAL f_unit IS from_axis:NORMALIZED.
  LOCAL t_unit IS to_dir:NORMALIZED.
  LOCAL cos_turn IS VDOT(f_unit, t_unit).
  IF cos_turn < -0.9999 { RETURN other_axis. }
  RETURN other_axis - (f_unit + t_unit) * (VDOT(other_axis, t_unit) / (1 + cos_turn)).
}
