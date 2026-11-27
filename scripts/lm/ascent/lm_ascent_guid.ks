// lm_ascent_guid.ks -- the ascent guidance (release 1.5): Luminary 210 ASCENT_GUIDANCE.agc, with the 099 differences chosen by the pad profile.
// Pure functions only: no ship reads, targets and engine data are passed in, so P12, P70, P71, the planner and the pad tests (test_ascent.ks)
// share one implementation. Reference models: scripts/tests/reference_ascent.py and reference_abort.py.
//
//   asc_new(profile, engine_data)               a fresh guidance state ("A11" or "J"); engine_data from asc_engine_aps (the default) or abt_engine_dps
//   asc_engine_aps(profile)                     the ascent engine as assumed before anything is measured
//   asc_engine(g, dv_ms, span_s)                ATMAG: one measured delta-V into the engine estimate
//   asc_qaxis(r_csm, v_csm)                     QAXIS, the normal of the CSM orbit plane (P12.agc, COMMINIT)
//   asc_state(r_vec, v_vec, qaxis, mu, rco)     the state along the guidance axes
//   asc_target(rco, yco, rdotd, zdotd)          the insertion targets
//   asc_vg(g, st, tgt)                          velocity to be gained
//   asc_guide(g, st, tgt)                       one guidance pass: time to go, steering direction
//   asc_trim(g, st, tgt)                        after cut-off: velocity to be gained, time to go for RCS
//   asc_rise_done(profile, height_m, rdot, yaw_err_deg)   the end of the vertical rise
//   asc_yaw_pitch(cmd, st)                      the N74 angles
//   asc_window_down(dir, st)                    the window reference after the rise
//   asc_insertion_vh(r_ins, r_apo, mu, vr)      horizontal speed for an apolune
//   asc_sim(...)                                the whole ascent simulated (planner)
// The aborts (Luminary P70-P71.agc and the ascent guidance's abort branches):
//   abt_engine_dps(profile, mass_kg)            the descent engine at P70, from the present mass
//   abt_rotation(rot_on, want, axis, ur)        ANG1CHEK: turning over through the vertical
//   abt_cross_range(y)                          the cross-range target, 8.2 nm towards the CSM plane
//   abt_a11_zdotd(engine_key, since_s)          099: the horizontal speed from the time since ignition
//   abt_csm_lead(ur, r_csm, v_csm)              THETCOMP: the CSM's lead angle
//   abt_j_set(theta), abt_j_target(...)         210 ZDOTDCMP: the horizontal speed from the CSM's lead
//   abt_rp(g, st, tgo, trimming)                RPCOMP: the predicted burnout radius
//
// Axes (all unit vectors, from the Moon's centre): UR radial, Z downrange = UR x QAXIS, LAT cross-range = Z x UR. Cross products go through
// lm_cross, so they mean what they mean in the AGC. Luminary names: R -> r_vec / RMAG, V -> v_vec, UNIT/R/ -> UR, ZAXIS1 -> Z, LAXIS -> LAT,
// PCONS PRATE YCONS YRATE -> A B C D.
//
// Documented departures:
//   * The downrange axis is worked out every pass (Luminary 210) for both profiles.
//   * The guidance may be run every programme cycle (faster than Luminary's 2 s); the engine estimate takes the real length of its pass.
//   * VG / Ve is held at 1 in the time-to-go formula: beyond it the formula gives a falling and then negative time, which would cut the engine
//     off. No real target gets there; it only makes a wrongly loaded N76 harmless.
//   * The time to go used in the logarithm is held between 0 and 0.9 TBUP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").          // lm_cross
RUNONCEPATH("0:/lm/burn/lm_r60.ks").           // r60_wrap_deg
RUNONCEPATH("0:/lm/descent_j/lm_j_constants.ks").   // the J abort targets

// asc_engine_aps: the ascent engine before anything has been measured (P12INIT): exhaust velocity VE, thrust acceleration AT0, burn-up time TBUP0,
// one over the delta-V of 2 s INVDV0, and the tail-off taken from TGO.
FUNCTION asc_engine_aps {
  PARAMETER profile.
  LOCAL tailoff IS ASC_TAILOFF_A11.
  IF profile = "J" { SET tailoff TO ASC_TAILOFF_J. }
  RETURN LEXICON("VE", ASC_VE, "AT0", ASC_AT0, "TBUP0", ASC_TBUP0, "INVDV0", ASC_INVDV0, "TAILOFF", tailoff).
}

// asc_new: TGO at Luminary's starting value, AT and TBUP from the engine data (FALSE = the ascent engine); EST holds the last four burn-up
// estimates; FLPC TRUE = position control off.
FUNCTION asc_new {
  PARAMETER profile, engine_data IS FALSE.
  LOCAL eng IS engine_data.
  IF NOT eng:ISTYPE("Lexicon") { SET eng TO asc_engine_aps(profile). }
  LOCAL first_est IS eng["VE"] * 2 * eng["INVDV0"].
  RETURN LEXICON("PROFILE", profile, "TGO", ASC_TGO0, "AT", eng["AT0"], "TBUP", eng["TBUP0"],
                 "EST", LIST(first_est, first_est, first_est, first_est), "FLPC", FALSE, "A", 0, "B", 0, "C", 0, "D", 0,
                 "VE", eng["VE"], "TAILOFF", eng["TAILOFF"]).
}

// asc_engine: ATMAG. dv_ms is the delta-V measured over span_s seconds. FALSE (nothing changes) when it is under 1.1 times lunar gravity.
// Each pass estimates TBUP = mass / mass flow as Ve x 2 s / delta-V of 2 s; the new TBUP is half of (the old one carried forward by the pass)
// plus half of (the mean of the last four estimates brought 4 s forward). AT = Ve / TBUP is the thrust acceleration.
FUNCTION asc_engine {
  PARAMETER g, dv_ms, span_s.
  IF span_s <= 0 { RETURN FALSE. }
  LOCAL dv_2s IS dv_ms * 2 / span_s.
  IF dv_2s < ASC_MINDV { RETURN FALSE. }
  g["EST"]:REMOVE(0).
  g["EST"]:ADD(g["VE"] * 2 / dv_2s).
  LOCAL total IS 0.
  FOR one_est IN g["EST"] { SET total TO total + one_est. }
  SET g["TBUP"] TO (g["TBUP"] - span_s + total / 4 - 4) / 2.
  SET g["AT"] TO g["VE"] / g["TBUP"].
  RETURN TRUE.
}

FUNCTION asc_qaxis {
  PARAMETER r_csm, v_csm.
  RETURN lm_cross(v_csm, r_csm):NORMALIZED.
}

// asc_state: RDOT, ZDOT, YDOT are the velocity along the axes; Y is the distance from the CSM plane at the target radius (YCOMP); GEFF is gravity
// plus the centrifugal term of the horizontal speed (negative until orbital speed).
FUNCTION asc_state {
  PARAMETER r_vec, v_vec, qaxis, mu, rco.
  LOCAL rmag IS r_vec:MAG.
  LOCAL ur_vec IS r_vec:NORMALIZED.
  LOCAL z_vec IS lm_cross(ur_vec, qaxis):NORMALIZED.
  LOCAL lat_vec IS lm_cross(z_vec, ur_vec):NORMALIZED.
  LOCAL rdot IS VDOT(v_vec, ur_vec).
  LOCAL horiz IS v_vec - ur_vec * rdot.
  RETURN LEXICON("UR", ur_vec, "Z", z_vec, "LAT", lat_vec, "RMAG", rmag, "RDOT", rdot, "ZDOT", VDOT(v_vec, z_vec),
                 "YDOT", VDOT(v_vec, lat_vec), "Y", rco * VDOT(ur_vec, qaxis),
                 "GEFF", -mu / (rmag * rmag) + horiz:SQRMAGNITUDE / rmag, "QAXIS", qaxis).
}

FUNCTION asc_target {
  PARAMETER rco, yco, rdotd, zdotd.
  RETURN LEXICON("RCO", rco, "YCO", yco, "RDOTD", rdotd, "YDOTD", 0, "ZDOTD", zdotd).
}

// asc_vg: the speed still to be changed along each axis, less what effective gravity does over the time to go of the previous pass.
FUNCTION asc_vg {
  PARAMETER g, st, tgt.
  RETURN st["UR"] * (tgt["RDOTD"] - st["RDOT"]) + st["LAT"] * (tgt["YDOTD"] - st["YDOT"]) + st["Z"] * (tgt["ZDOTD"] - st["ZDOT"])
         - st["UR"] * (g["TGO"] * st["GEFF"]).
}

// asc_guide: one pass (ASCENT / MAINENG / CMPONENT). Returns LEXICON("TGO", s, "VG", vec, "DIR", unit, "AR", n, "AY", n, "AP", n) and updates g.
// The radial and cross-range accelerations are (A + B t) / (TBUP - t) and (C + D t) / (TBUP - t): A, C set the speed, B, D the position.
FUNCTION asc_guide {
  PARAMETER g, st, tgt.
  LOCAL vg_vec IS asc_vg(g, st, tgt).
  LOCAL ratio IS MIN(vg_vec:MAG / g["VE"], 1).
  LOCAL tbup IS g["TBUP"].
  // Time to go from the rocket equation, to second order in VG / Ve (MAINENG).
  LOCAL tgo IS tbup * ratio * (1 - ratio / 2) - g["TAILOFF"].
  SET g["TGO"] TO tgo.
  IF tgo >= ASC_T_HOLD {
    LOCAL t_go IS MAX(0, MIN(tgo, 0.9 * tbup)).
    LOCAL ln_term IS -LN(1 - t_go / tbup).                    // the integral of 1 / (TBUP - t) over the time to go
    LOCAL d12 IS tbup - t_go / ln_term.
    LOCAL drdot IS tgt["RDOTD"] - st["RDOT"].
    LOCAL dydot IS tgt["YDOTD"] - st["YDOT"].
    IF NOT g["FLPC"] AND tgo < ASC_T_NOPOS { SET g["FLPC"] TO TRUE. }
    LOCAL b_rate IS 0.
    LOCAL d_rate IS 0.
    IF NOT g["FLPC"] {
      LOCAL d21 IS t_go - d12.
      LOCAL e_term IS t_go / 2 - d21.
      LOCAL dr IS tgt["RCO"] - st["RMAG"] - st["RDOT"] * t_go.      // how far the present speeds would miss the wanted position
      LOCAL dy IS tgt["YCO"] - st["Y"] - st["YDOT"] * t_go.
      SET b_rate TO (d21 * drdot - dr) / (e_term * t_go).
      SET b_rate TO MAX(MIN(b_rate, 0), ASC_PRLIMIT * tbup).        // never positive, never below the limit
      SET d_rate TO (d21 * dydot - dy) / (e_term * t_go).
    }
    SET g["B"] TO b_rate.
    SET g["D"] TO d_rate.
    SET g["A"] TO drdot / ln_term - d12 * b_rate.
    SET g["C"] TO dydot / ln_term - d12 * d_rate.
  }
  // The command: radial first (with gravity made up) and cross-range, downrange gets what is left of the thrust acceleration.
  LOCAL at_acc IS g["AT"].
  LOCAL ar_acc IS (g["A"] + g["B"] * ASC_LOOKAHEAD_S) / tbup - st["GEFF"].
  LOCAL ay_acc IS (g["C"] + g["D"] * ASC_LOOKAHEAD_S) / tbup.
  LOCAL ah_vec IS st["LAT"] * ay_acc + st["UR"] * ar_acc.
  LOCAL ap_acc IS 0.
  IF ah_vec:MAG <= at_acc {
    SET ap_acc TO SQRT(MAX(0, at_acc * at_acc - ah_vec:SQRMAGNITUDE)).
  } ELSE {
    SET ah_vec TO ah_vec * (at_acc / ah_vec:MAG).
  }
  IF tgt["ZDOTD"] - st["ZDOT"] < 0 { SET ap_acc TO -ap_acc. }
  LOCAL dir_vec IS (ah_vec + st["Z"] * ap_acc):NORMALIZED.
  RETURN LEXICON("TGO", tgo, "VG", vg_vec, "DIR", dir_vec, "AR", ar_acc, "AY", ay_acc, "AP", ap_acc).
}

// asc_trim: after cut-off (FLRCS): VG is kept up to date and the time to go is that of four RCS jets.
FUNCTION asc_trim {
  PARAMETER g, st, tgt.
  LOCAL vg_vec IS asc_vg(g, st, tgt).
  SET g["TGO"] TO vg_vec:MAG / ASC_AT_RCS.
  RETURN vg_vec.
}

// asc_rise_done: 40 ft/s up (210), and for A11 the yaw within 5 degrees too (099). Above 25 000 ft there is no vertical rise.
FUNCTION asc_rise_done {
  PARAMETER profile, height_m, rdot, yaw_err_deg.
  IF height_m >= ASC_RISE_ALT_M { RETURN TRUE. }
  IF rdot < ASC_RISE_RDOT { RETURN FALSE. }
  RETURN profile = "J" OR ABS(yaw_err_deg) <= ASC_RISE_YAW_DEG.
}

// asc_yaw_pitch: LIST(yaw, pitch) in degrees 0 to 359.99, as Luminary computes N74 (P12RET): yaw from the cross-range share of the horizontal
// command, pitch the (negative) angle of the thrust direction from the vertical.
FUNCTION asc_yaw_pitch {
  PARAMETER cmd, st.
  LOCAL horiz IS SQRT(cmd["AY"] * cmd["AY"] + cmd["AP"] * cmd["AP"]).
  LOCAL yaw_deg IS 0.
  IF horiz > 0 { SET yaw_deg TO ARCSIN(MAX(-1, MIN(1, cmd["AY"] / horiz))). }
  LOCAL pitch_deg IS -VANG(cmd["DIR"], st["UR"]).
  RETURN LIST(r60_wrap_deg(yaw_deg), r60_wrap_deg(pitch_deg)).
}

// asc_window_down: Luminary points the windows at the surface (-UR). Within 5 degrees of vertical that is not defined well, so the downrange
// axis is used there; both are made square to the thrust direction, and they agree for a thrust direction tilted downrange.
FUNCTION asc_window_down {
  PARAMETER dir_vec, st.
  IF VANG(dir_vec, st["UR"]) < 5 { RETURN VECTOREXCLUDE(dir_vec, st["Z"]):NORMALIZED. }
  RETURN VECTOREXCLUDE(dir_vec, -st["UR"]):NORMALIZED.
}

// asc_insertion_vh: the horizontal speed at radius r_ins, with radial speed vr, whose orbit reaches r_apo (energy and angular momentum).
// Returns 0 when no such speed exists (r_apo not above r_ins).
FUNCTION asc_insertion_vh {
  PARAMETER r_ins, r_apo, mu, vr.
  IF r_apo <= r_ins { RETURN 0. }
  LOCAL inside IS 2 * (mu * (1 / r_ins - 1 / r_apo) - vr * vr / 2) / (1 - (r_ins / r_apo) ^ 2).
  IF inside <= 0 { RETURN 0. }
  RETURN SQRT(inside).
}

// asc_turn_toward: dir_cur turned towards dir_want by at most max_deg.
FUNCTION asc_turn_toward {
  PARAMETER dir_cur, dir_want, max_deg.
  IF VANG(dir_cur, dir_want) <= max_deg { RETURN dir_want:NORMALIZED. }
  LOCAL side_vec IS VECTOREXCLUDE(dir_cur, dir_want).
  IF side_vec:MAG < 1e-9 { RETURN dir_want:NORMALIZED. }
  RETURN dir_cur:NORMALIZED * COS(max_deg) + side_vec:NORMALIZED * SIN(max_deg).
}

// asc_sim_push: one velocity-Verlet step of length h with the engine along dir_vec. Returns LIST(r, v, mass, delta-V of the step).
FUNCTION asc_sim_push {
  PARAMETER r_vec, v_vec, mass_kg, dir_vec, h, mu, flow, ve_ms.
  LOCAL m_end IS mass_kg - flow * h.
  LOCAL dv_step IS ve_ms * LN(mass_kg / m_end).
  LOCAL thrust_acc IS dir_vec * (dv_step / h).
  LOCAL acc_a IS thrust_acc - r_vec * (mu / r_vec:MAG ^ 3).
  LOCAL r_end IS r_vec + v_vec * h + acc_a * (h * h / 2).
  LOCAL acc_b IS thrust_acc - r_end * (mu / r_end:MAG ^ 3).
  RETURN LIST(r_end, v_vec + (acc_a + acc_b) * (h / 2), m_end, dv_step).
}

// asc_sim: the ascent from a landed state (r0, v0 from the Moon's centre) flown by the guidance above: vertical rise (yaw taken as met), then the
// guidance direction turned no faster than P63_TURN_RATE_DEG_S, the engine estimate fed every 2 s with the exact delta-V, the cut-off when the
// time to go is under 4 s. mass_kg is the mass that lifts off, ve_ms the engine's exhaust velocity.
// Returns LEXICON("OK", bool, "BURN_S", s, "R_END", vec, "V_END", vec, "MASS_END", kg, "PITCH_RISE", the N74 pitch before ignition).
FUNCTION asc_sim {
  PARAMETER profile, r0, v0, qaxis, mu, tgt, mass_kg, thrust_n, ve_ms, dt_s.
  LOCAL first_st IS asc_state(r0, v0 + r0:NORMALIZED * ASC_TIPOVER_RDOT, qaxis, mu, tgt["RCO"]).
  LOCAL pitch_rise IS asc_yaw_pitch(asc_guide(asc_new(profile), first_st, tgt), first_st)[1].
  LOCAL out IS LEXICON("OK", FALSE, "BURN_S", 0, "R_END", r0, "V_END", v0, "MASS_END", mass_kg, "PITCH_RISE", pitch_rise).
  IF mass_kg <= 0 OR thrust_n <= 0 OR ve_ms <= 0 { RETURN out. }
  LOCAL g IS asc_new(profile).
  LOCAL site_r IS r0:MAG.
  LOCAL flow IS thrust_n / ve_ms.
  LOCAL r_vec IS r0.
  LOCAL v_vec IS v0.
  LOCAL mass_now IS mass_kg.
  LOCAL t_now IS 0.
  LOCAL dir_vec IS r0:NORMALIZED.
  LOCAL rising IS TRUE.
  LOCAL pass_t IS 0.
  LOCAL pass_dv IS 0.
  LOCAL going IS TRUE.
  UNTIL NOT going OR t_now >= ASC_SIM_MAX_S {
    LOCAL st IS asc_state(r_vec, v_vec, qaxis, mu, tgt["RCO"]).
    LOCAL cmd IS asc_guide(g, st, tgt).
    IF rising AND asc_rise_done(profile, st["RMAG"] - site_r, st["RDOT"], 0) { SET rising TO FALSE. }
    IF rising { SET dir_vec TO st["UR"]. } ELSE { SET dir_vec TO asc_turn_toward(dir_vec, cmd["DIR"], P63_TURN_RATE_DEG_S * dt_s). }
    LOCAL last_step IS NOT rising AND cmd["TGO"] < ASC_T_CUT.
    LOCAL h IS dt_s.
    IF last_step { SET h TO MAX(0, cmd["TGO"]). }
    IF mass_now - flow * h <= 0.05 * mass_kg {                 // out of propellant
      SET going TO FALSE.
    } ELSE {
      IF h > 0.001 {
        LOCAL pushed IS asc_sim_push(r_vec, v_vec, mass_now, dir_vec, h, mu, flow, ve_ms).
        SET r_vec TO pushed[0].
        SET v_vec TO pushed[1].
        SET mass_now TO pushed[2].
        SET t_now TO t_now + h.
        SET pass_t TO pass_t + h.
        SET pass_dv TO pass_dv + pushed[3].
      }
      IF last_step {
        SET out["OK"] TO TRUE.
        SET going TO FALSE.
      } ELSE IF pass_t >= 2 - 1e-6 {
        asc_engine(g, pass_dv, pass_t).
        SET pass_t TO 0.
        SET pass_dv TO 0.
      }
    }
  }
  SET out["BURN_S"] TO t_now.
  SET out["R_END"] TO r_vec.
  SET out["V_END"] TO v_vec.
  SET out["MASS_END"] TO mass_now.
  RETURN out.
}

// ---- The aborts, P70 and P71 (release 1.5) --------------------------------------------------------------------------------------

// abt_engine_dps: the descent engine as P70 assumes it (P70INIT): thrust and mass flow as loaded, over the present mass.
FUNCTION abt_engine_dps {
  PARAMETER profile, mass_kg.
  LOCAL tailoff IS ABT_DPS_TAILOFF_A11.
  IF profile = "J" { SET tailoff TO ABT_DPS_TAILOFF_J. }
  RETURN LEXICON("VE", DPSVEX, "AT0", ABT_DPS_THRUST_N / mass_kg, "TBUP0", mass_kg / ABT_DPS_MDOT,
                 "INVDV0", mass_kg / (ABT_DPS_THRUST_N * 2), "TAILOFF", tailoff).
}

// abt_rotation: ANG1CHEK, aborts only, while the rotation flag is up. Wanted direction within 90 degrees of the present thrust axis: steer to it
// and the rotation is over. Otherwise, while the axis is more than 30 degrees from the vertical, command straight up; inside 30 degrees, over.
// So a ship braking backwards turns over through the vertical, not past the ground. Returns LEXICON("DIR", direction, "ROT", flag).
FUNCTION abt_rotation {
  PARAMETER rot_on, want_dir, axis_vec, ur_vec.
  IF rot_on AND VANG(want_dir, axis_vec) >= 90 AND VDOT(axis_vec:NORMALIZED, ur_vec:NORMALIZED) < ABT_COSTHET2 {
    RETURN LEXICON("DIR", ur_vec:NORMALIZED, "ROT", TRUE).
  }
  RETURN LEXICON("DIR", want_dir, "ROT", FALSE).
}

// abt_cross_range: y_m the distance out of the CSM plane (state "Y"). More than ABT_YLIM_M out: the target is that much towards the plane, else
// the plane itself (YCO).
FUNCTION abt_cross_range {
  PARAMETER y_m.
  IF ABS(y_m) <= ABT_YLIM_M { RETURN 0. }
  IF y_m > 0 { RETURN y_m - ABT_YLIM_M. }
  RETURN y_m + ABT_YLIM_M.
}

// abt_a11_zdotd: Luminary 099 BOTHPOLY: the horizontal speed wanted, a cubic in the seconds since ignition, never below ABT_VMIN_FPS, m/s.
// engine_key "DPS" (P70) or "APS" (a direct P71).
FUNCTION abt_a11_zdotd {
  PARAMETER engine_key, since_s.
  LOCAL poly IS ABT_POLY_APS.
  IF engine_key = "DPS" { SET poly TO ABT_POLY_DPS. }
  LOCAL fps IS poly[0] + since_s * (poly[1] + since_s * (poly[2] + since_s * poly[3])).
  RETURN MAX(ABT_VMIN_FPS, fps) / FT_PER_M.
}

// abt_csm_lead: THETCOMP: the angle between the LM's and the CSM's position, degrees, positive when the CSM is ahead in its direction of orbit
// (Luminary signs it with the Moon's spin; the CSM's orbit is used so "ahead" is right whichever way it goes round).
FUNCTION abt_csm_lead {
  PARAMETER ur_vec, r_csm, v_csm.
  LOCAL angle IS VANG(ur_vec, r_csm).
  IF VDOT(lm_cross(ur_vec, r_csm:NORMALIZED), lm_cross(r_csm, v_csm)) < 0 { RETURN -angle. }
  RETURN angle.
}

// abt_j_set: which parameter set the lead angle picks, once, at the first abort programme.
FUNCTION abt_j_set {
  PARAMETER theta_deg.
  IF theta_deg < J_ABT_THETCRIT { RETURN 1. }
  RETURN 2.
}

// abt_j_target: ZDOTDCMP: the abort orbit's semi-major axis is J + K theta, so its apolune radius is RA = 2 a - RP (RP the predicted burnout
// radius, its perilune), never below RAMIN; ZDOTD is the perigee speed of that orbit. Without a CSM RA is RAMIN. J and RAMIN are moved by our
// landing-site radius less Apollo 17's. Returns LEXICON("RA", m, "ZDOTD", m/s).
FUNCTION abt_j_target {
  PARAMETER has_csm, theta_deg, set_no, rp, site_r, mu.
  LOCAL shift IS site_r - J_ABT_SITE_R.
  LOCAL ra IS J_ABT_RAMIN / FT_PER_M + shift.
  IF has_csm {
    LOCAL j_ft IS J_ABT_J2.
    LOCAL k_ft IS J_ABT_K2.
    IF set_no = 1 { SET j_ft TO J_ABT_J1. SET k_ft TO J_ABT_K1. }
    LOCAL semi_major IS j_ft / FT_PER_M + shift + k_ft / FT_PER_M * theta_deg * CONSTANT:DEGTORAD.
    SET ra TO MAX(ra, 2 * semi_major - rp).
  }
  RETURN LEXICON("RA", ra, "ZDOTD", SQRT(2 * mu * ra / (rp * (ra + rp)))).
}

// abt_rp: RPCOMP2 while guiding: the radius predicted at cut-off from this pass; RPCOMP1 while trimming: without the thrust terms.
FUNCTION abt_rp {
  PARAMETER g, st, tgo, trimming.
  LOCAL rp IS st["RMAG"] + st["RDOT"] * tgo.
  IF NOT trimming { SET rp TO rp + (g["A"] * tgo * tgo / 2 + g["B"] * tgo ^ 3 / 6) / g["TBUP"]. }
  RETURN rp.
}
