// lm_guidance.ks -- P63 braking-phase guidance: time-to-go, commanded acceleration, thrust command (plan Tasks 3 and 4).
//
// Ported from Luminary 099, LUNAR_LANDING_GUIDANCE_EQUATIONS.agc:
//   TTF/8CL   (489-522)  -> guid_cubic_tgo     how long until the braking target is reached
//   QUADGUID  (546-600)  -> guid_acg           the acceleration the guidance wants now
//   AFCCALC   (600-627)  -> guid_afc           thrust acceleration after gravity, limited to what the engine can give
//   MUNGRAV   (SERVICER.agc 1076-1085) -> guid_gravity
// Everything here is pure maths on numbers and vectors (nothing reads kOS), so it is tested on the pad against
// scripts/tests/reference.py with made-up and simulated numbers.
//
// Guidance-frame vectors are V(up, crossrange, downrange), as in lm_frame.ks.
//
// SIGN CONVENTION. Luminary stores the time-to-go TTF as a NEGATIVE number that grows toward zero as time passes
// (TTFINCR adds the elapsed time). Its published acceleration law "ACG = ADG + 6 (VDG + VG)/TTF + 12 (RDG - RG)/TTF^2"
// is written for that negative TTF. Here the time-to-go "tgo" is the plain positive number of seconds left, so the
// same law reads
//     ACG = ADG - 6 (VDG + VG)/tgo + 12 (RDG - RG)/tgo^2.
// (Checked in reference.py: this is the acceleration at the start of the quadratic acceleration profile that reaches
// RDG, VDG and ADG exactly after tgo seconds.)
//
// Simplifications (spec section 11): no fixed-point scaling, Newton's method instead of the AGC's ROOTPSRS,
// no AGC overflow alarm 1410.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").

// guid_cubic_tgo: the time-to-go, in seconds, for the downrange (z) direction. Newton's method from the last answer.
//
// Why a cubic: the guidance law above reaches the target position, velocity and acceleration for ANY time-to-go, so
// the time-to-go has to be chosen by one more condition. Luminary chooses it so the acceleration is changing at the
// target's jerk rate JDG when the target is reached. Written out, that is the cubic
//     JDG tgo^3 - 6 ADG tgo^2 + 6 (VG + 3 VDG) tgo + 24 (RG - RDG) = 0        (all downrange components)
// (derived from the TTF/8CL comments by putting TTF/8 = -tgo/8 and multiplying by 64; with no jerk or acceleration and
// equal speeds it gives tgo = distance / speed, as it should).
// Returns LEXICON("OK", TRUE or FALSE, "TGO", seconds). OK is FALSE, and TGO is the guess handed in, when the guess is
// not positive, the slope is zero, the iterate goes to zero or below (no positive root: for example the ship is already
// past the target), or 20 passes do not settle to 1 ms. Luminary raises alarm 1406 for that.
FUNCTION guid_cubic_tgo {
  PARAMETER rgz, vgz, rdgz, vdgz, adgz, jdgz, tgo_guess.
  LOCAL bad IS LEXICON("OK", FALSE, "TGO", tgo_guess).
  IF tgo_guess <= 0 { RETURN bad. }
  LOCAL tgo_now IS tgo_guess.
  LOCAL pass_no IS 0.
  UNTIL pass_no >= 20 {
    // ^ is KerboScript's power operator.
    LOCAL resid IS jdgz * tgo_now ^ 3 - 6 * adgz * tgo_now ^ 2 + 6 * (vgz + 3 * vdgz) * tgo_now + 24 * (rgz - rdgz).
    LOCAL slope IS 3 * jdgz * tgo_now ^ 2 - 12 * adgz * tgo_now + 6 * (vgz + 3 * vdgz).
    IF slope = 0 { RETURN bad. }
    LOCAL delta IS resid / slope.
    SET tgo_now TO tgo_now - delta.
    IF tgo_now <= 0 { RETURN bad. }
    IF ABS(delta) < 0.001 { RETURN LEXICON("OK", TRUE, "TGO", tgo_now). }
    SET pass_no TO pass_no + 1.
  }
  RETURN bad.
}

// guid_acg: the acceleration the guidance wants right now (QUADGUID).
// leadtime is LEADTIME (negative): the engine takes about 2.2 s to follow a command, so the acceleration asked for is
// the one the guidance profile needs 2.2 s from now. Luminary builds this from the ratio
//     rho = (tgo + LEADTIME)/tgo
// with the coefficients below (read from the code at lines 546-575; with rho = 1 every coefficient is 1 and the
// published law comes out). Under 1 s to go the target acceleration is returned, so no tiny time is ever divided by.
FUNCTION guid_acg {
  PARAMETER rgu_vec, vgu_vec, tgo, rdg_vec, vdg_vec, adg_vec, leadtime.
  IF tgo < 1 { RETURN adg_vec. }
  LOCAL rho IS (tgo + leadtime) / tgo.
  LOCAL c_v  IS 2 * rho ^ 2 - rho.              // on the current velocity
  LOCAL c_r  IS 3 * rho ^ 2 - 2 * rho.          // on the position error
  LOCAL c_vd IS 4 * rho ^ 2 - 3 * rho.          // on the target velocity
  LOCAL c_a  IS 6 * rho ^ 2 - 6 * rho + 1.      // on the target acceleration
  RETURN adg_vec * c_a - (vdg_vec * c_vd + vgu_vec * c_v) * (6 / tgo) + (rdg_vec - rgu_vec) * (12 * c_r / tgo ^ 2).
}

// guid_gravity: gravity acceleration at r_vec (a position from the body's centre, any axes), pointing at the centre.
// mu is the body's gravitational parameter from kOS (SHIP:BODY:MU), never a typed-in number. MUNGRAV.
FUNCTION guid_gravity {
  PARAMETER r_vec, mu.
  IF r_vec:MAG = 0 { RETURN V(0, 0, 0). }
  RETURN r_vec * (-mu / r_vec:MAG ^ 3).
}

// guid_afc: the thrust acceleration the engine must deliver: the commanded acceleration minus gravity (the engine has
// to cancel gravity as well), limited so its size never exceeds what the engine can give, f_max_n / mass.
// If it is too big, up and crossrange are kept and the downrange part is shrunk (AMAXHORIZ, lines 609-627), so the
// lander keeps its height control and gives up speed-up/slow-down first. If even the up and crossrange parts are too
// big, downrange is zero. mass <= 0 or f_max_n <= 0 (engine not available): the command is returned unchanged.
FUNCTION guid_afc {
  PARAMETER acg_vec, g_guid_vec, mass_kg, f_max_n.
  LOCAL afc_vec IS acg_vec - g_guid_vec.
  IF mass_kg <= 0 OR f_max_n <= 0 { RETURN afc_vec. }
  LOCAL amax IS f_max_n / mass_kg.
  IF afc_vec:MAG <= amax { RETURN afc_vec. }
  LOCAL keep_sq IS afc_vec:X ^ 2 + afc_vec:Y ^ 2.
  LOCAL horiz IS 0.
  IF amax ^ 2 > keep_sq { SET horiz TO SQRT(amax ^ 2 - keep_sq). }
  IF afc_vec:Z < 0 { SET horiz TO -horiz. }
  RETURN V(afc_vec:X, afc_vec:Y, horiz).
}

// guid_throttle: the throttle setting (0 to 1) for a commanded thrust fc_n (N), given the engine's full thrust f_max_n
// (N), the least throttle min_frac it can be set to and the setting it has now, prev_frac.
// This is Apollo's logic (THROTTLE_CONTROL_ROUTINES.agc 63-99) on the Realism Overhaul engine's dead band: thrust
// between THR_DEAD_LOW and THR_DEAD_HIGH of full is not available.
//   at or above THR_DEAD_HIGH            -> full throttle (1)
//   at or below THR_DEAD_LOW             -> the command, but not below min_frac
//   inside the band, engine at full      -> stay at full (Apollo leaves full only when the command falls to the
//                                           lower edge, so the throttle does not chatter across the band)
//   inside the band, engine not at full  -> THR_DEAD_LOW, the most the engine can give without jumping to full
// No available thrust (f_max_n <= 0: engine not lit or staged) -> the previous setting, nothing divided by zero.
FUNCTION guid_throttle {
  PARAMETER fc_n, f_max_n, min_frac, prev_frac.
  IF f_max_n <= 0 { RETURN prev_frac. }
  LOCAL frac IS fc_n / f_max_n.
  IF frac >= THR_DEAD_HIGH { RETURN 1. }
  IF frac <= THR_DEAD_LOW { RETURN MAX(frac, min_frac). }
  IF prev_frac >= THR_DEAD_HIGH { RETURN 1. }
  RETURN THR_DEAD_LOW.
}

// guid_targets_brake / guid_targets_approach: the pad-loaded target set of a phase. R, V, A are the target position, velocity
// and acceleration in guidance axes, J_Z the downrange jerk, GAIN the lunar-rotation lead gain, TCGF and TCGI the time-to-go
// window outside which the guidance axes are frozen, TEND the time-to-go below which the phase ends (Luminary's TARGTDEX
// picks the set by phase: LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 100-108).
FUNCTION guid_targets_brake {
  RETURN LEXICON("R", RBRFG, "V", VBRFG, "A", ABRFG, "J_Z", JBRFG_Z, "GAIN", GAINBRAK, "TCGF", TCGFBRAK, "TCGI", TCGIBRAK, "TEND", TENDBRAK).
}

FUNCTION guid_targets_approach {
  RETURN LEXICON("R", RAPFG, "V", VAPFG, "A", AAPFG, "J_Z", JAPFG_Z, "GAIN", GAINAPPR, "TCGF", TCGFAPPR, "TCGI", TCGIAPPR, "TEND", TENDAPPR).
}

// guid_handoff: a phase ends when the time-to-go has fallen below its TEND (TENDBRAK 62 s in braking, TENDAPPR 12 s in the approach).
// (Luminary's test is TEND + TTF/8 <= 0 with its negative TTF; see the sign note at the top.)
FUNCTION guid_handoff {
  PARAMETER tgo, tend.
  RETURN tgo < tend.
}

// guid_pass: one guidance pass. state is nav_state() (or a lexicon with the same keys: BODY_OK, R, V, MASS in tonnes,
// THRUST in kN, MU); land_vec and wm_vec as in lm_frame.ks; tgo_prev is the last time-to-go, already reduced by the time
// since it was computed; prev_frac the throttle setting now; targets one of guid_targets_brake() / guid_targets_approach();
// cg_prev the last pass's guidance axes (a list of 3 vectors) or FALSE when there is none. Returns a LEXICON:
//   VALID (FALSE when the state is not over the right body: nothing else is set), OK (the time-to-go solver settled),
//   ALARM (1406 when it did not, else 0), TGO, ACG, AFC (guidance axes), THR (0 to 1), RGU, VGU, CG, HANDOFF.
// When the solver does not settle, the command is worked out from tgo_prev (the clock-reduced old time-to-go) and
// ALARM says so: the caller can keep flying on it for a few passes.
// The guidance axes are rebuilt every pass from the site and the lead term TTF/8 x GAIN x (velocity over the surface)
// (CGCALC, lines 660-682; TTF is negative there, so the lead here is -tgo/CG_LEAD_DIV x GAIN; CG_LEAD_DIV is 8,
// following the AGC's "TTF/8" variable, with 4 as the alternative reading; see lm_constants.ks and flight test 2).
// Luminary freezes CG when the time-to-go is outside TCGF..TCGI (CGCALC, lines 636-657): here the previous axes cg_prev are
// kept then. In braking (30..900 s) that never happens inside P63; in the approach the axes stop turning 30 s before the end,
// when the direction to the site would otherwise swing fast.
FUNCTION guid_pass {
  PARAMETER state, land_vec, wm_vec, tgo_prev, prev_frac, targets, cg_prev.
  IF NOT state["BODY_OK"] { RETURN LEXICON("VALID", FALSE). }
  LOCAL r_vec IS state["R"].
  LOCAL v_vec IS state["V"].
  LOCAL mass_kg IS state["MASS"] * 1000.
  LOCAL f_max_n IS state["THRUST"] * 1000.
  LOCAL angterm_vec IS v_vec - lm_cross(wm_vec, r_vec).        // velocity over the surface (ANGTERM)
  LOCAL cg IS cg_prev.
  IF NOT (cg_prev:ISTYPE("List") AND (tgo_prev <= targets["TCGF"] OR tgo_prev > targets["TCGI"])) {
    SET cg TO guidance_cg(land_vec, r_vec, angterm_vec, -tgo_prev / CG_LEAD_DIV * targets["GAIN"]).
  }
  LOCAL rgu_vec IS rgu(cg, r_vec, land_vec).
  LOCAL vgu_vec IS vgu(cg, v_vec, r_vec, wm_vec).
  LOCAL solved IS guid_cubic_tgo(rgu_vec:Z, vgu_vec:Z, targets["R"]:Z, targets["V"]:Z, targets["A"]:Z, targets["J_Z"], tgo_prev).
  LOCAL tgo IS solved["TGO"].
  LOCAL acg_vec IS guid_acg(rgu_vec, vgu_vec, tgo, targets["R"], targets["V"], targets["A"], LEADTIME).
  LOCAL g_guid_vec IS cg_apply(cg, guid_gravity(r_vec, state["MU"])).
  LOCAL afc_vec IS guid_afc(acg_vec, g_guid_vec, mass_kg, f_max_n).
  LOCAL thr_frac IS guid_throttle(afc_vec:MAG * mass_kg, f_max_n, THR_MIN_FRAC, prev_frac).
  LOCAL alarm_no IS 0.
  IF NOT solved["OK"] { SET alarm_no TO 1406. }
  RETURN LEXICON("VALID", TRUE, "OK", solved["OK"], "ALARM", alarm_no, "TGO", tgo, "ACG", acg_vec, "AFC", afc_vec,
                 "THR", thr_frac, "RGU", rgu_vec, "VGU", vgu_vec, "CG", cg, "HANDOFF", guid_handoff(tgo, targets["TEND"])).
}

// ---- Vertical phase (milestone 5): P65 and P66 ---------------------------------------------------------------------

// thr_for_thrust: the throttle command that gives a wanted thrust (a fraction of full thrust), from the engine's measured curve
// THR_CURVE_THRUST / THR_CURVE_THROTTLE (lm_constants.ks), straight lines between the points. Below the engine's least thrust it
// returns the least throttle (the thrust cannot be lower), above full thrust 1.
FUNCTION thr_for_thrust {
  PARAMETER frac.
  IF frac <= THR_CURVE_THRUST[0] { RETURN THR_CURVE_THROTTLE[0]. }
  FROM { LOCAL i IS 1. } UNTIL i >= THR_CURVE_THRUST:LENGTH STEP { SET i TO i + 1. } DO {
    IF frac <= THR_CURVE_THRUST[i] {
      RETURN THR_CURVE_THROTTLE[i - 1] + (THR_CURVE_THROTTLE[i] - THR_CURVE_THROTTLE[i - 1]) * (frac - THR_CURVE_THRUST[i - 1]) / (THR_CURVE_THRUST[i] - THR_CURVE_THRUST[i - 1]).
    }
  }
  RETURN 1.
}

// trim_step: the throttle trim (a thrust fraction added to the wanted thrust) after one more cycle of dt seconds: it moves toward
// the difference between the thrust wanted and the thrust measured (both fractions of full thrust), THR_TRIM_GAIN per second, and
// never beyond +-THR_TRIM_MAX. No change when nothing is wanted (wanted < 0) or no thrust is measured (under 0.05: the engine is
// not lit or is starting up).
FUNCTION trim_step {
  PARAMETER trim, wanted, measured, dt.
  IF wanted < 0 OR measured < 0.05 { RETURN trim. }
  RETURN MAX(-THR_TRIM_MAX, MIN(THR_TRIM_MAX, trim + THR_TRIM_GAIN * dt * (wanted - measured))).
}

// thr_command: guid_throttle's answer (a wanted thrust fraction, or 1 for full throttle) as the throttle to command.
FUNCTION thr_command {
  PARAMETER wanted.
  IF wanted >= 0.99 { RETURN 1. }
  RETURN thr_for_thrust(wanted).
}

// guid_pass_vert: one P65 pass (VERTGUID, source 897-913, then AFCCALC1). The guidance axes cg are the ones P64 left (CGCALC
// is not run in the vertical phase, source 72-74), so the position and velocity come from the frozen axes. There is no
// time-to-go:
//   ACG = (V2FG - VGU) / TAUVERT         the acceleration that closes the velocity error (here the target is a slow descent
//                                        and no horizontal speed) with a time constant of TAUVERT seconds
// Then the same limit and throttle path as the quadratic phases (guid_afc, guid_throttle). Returns a LEXICON: VALID (FALSE when
// the state is not over the right body, nothing else set), ACG, AFC (guidance axes), THR (0 to 1), WANTED (the thrust fraction wanted
// before the engine curve, -1 when there is none), RGU, VGU, CG. With no mass or no thrust available the throttle setting is left
// as it was (prev_frac).
FUNCTION guid_pass_vert {
  PARAMETER state, land_vec, wm_vec, prev_frac, cg.
  IF NOT state["BODY_OK"] { RETURN LEXICON("VALID", FALSE). }
  LOCAL r_vec IS state["R"].
  LOCAL mass_kg IS state["MASS"] * 1000.
  LOCAL f_max_n IS state["THRUST"] * 1000.
  LOCAL rgu_vec IS rgu(cg, r_vec, land_vec).
  LOCAL vgu_vec IS vgu(cg, state["V"], r_vec, wm_vec).
  LOCAL acg_vec IS (V2FG - vgu_vec) / TAUVERT.
  LOCAL g_guid_vec IS cg_apply(cg, guid_gravity(r_vec, state["MU"])).
  LOCAL afc_vec IS guid_afc(acg_vec, g_guid_vec, mass_kg, f_max_n).
  LOCAL thr_frac IS prev_frac.
  LOCAL wanted IS -1.
  IF mass_kg > 0 AND f_max_n > 0 {
    SET wanted TO guid_throttle(afc_vec:MAG * mass_kg, f_max_n, THR_MIN_THRUST_FRAC, prev_frac).
    SET thr_frac TO thr_command(wanted).
  }
  RETURN LEXICON("VALID", TRUE, "ACG", acg_vec, "AFC", afc_vec, "THR", thr_frac, "WANTED", wanted, "RGU", rgu_vec, "VGU", vgu_vec, "CG", cg).
}

// guid_rod_throttle: the P66 throttle (RODCOMP, source 948-1095 with THROTTLE_CONTROL_ROUTINES.agc 134-179).
//   a_up   = (vdg - hdot) / TAUROD                        the vertical acceleration that closes the descent-rate error
//   AFC    = (a_up + |g|) / cos(tilt)                     thrust acceleration along the thrust axis (gravity must be cancelled
//                                                          too; tilt = angle between the thrust axis and the local vertical)
//   AFC   += LAG_TAU * (|g|/cos(tilt) - a_present)        lag compensation: -(LAG/TAU) times the vertical acceleration now,
//                                                          i.e. the rate law sees hdot one engine lag ahead
// then limited between MINFORCE and MAXFORCE (and the engine's own limits: THR_MIN_THRUST_FRAC of its thrust, up to the dead band) divided by the
// mass, and turned into a throttle setting with guid_throttle and the engine's measured curve (thr_command). vdg = commanded descent rate (up positive), hdot = vertical speed
// now, tilt_cos = cos(tilt), mass_kg, f_avail_n = the engine's available thrust, prev_frac = throttle now, a_present = the thrust
// acceleration now (m/s^2; Luminary adds FWEIGHT/MASS to its averaged measurement, kOS gives the thrust now), g_mag = |g|.
// Returns LEXICON("THR", throttle, "A_CMD", the thrust acceleration commanded, "WANTED", the thrust fraction wanted before the curve). No mass, no thrust, or a thrust axis within
// P66_MIN_TILT_COS of horizontal: the throttle is left as it was and A_CMD is 0.
FUNCTION guid_rod_throttle {
  PARAMETER vdg, hdot, tilt_cos, mass_kg, f_avail_n, prev_frac, a_present, g_mag.
  IF mass_kg <= 0 OR f_avail_n <= 0 OR tilt_cos <= P66_MIN_TILT_COS { RETURN LEXICON("THR", prev_frac, "A_CMD", 0, "WANTED", -1). }
  LOCAL a_up IS (vdg - hdot) / TAUROD.
  LOCAL afc IS (a_up + g_mag) / tilt_cos + LAG_TAU * (g_mag / tilt_cos - a_present).
  LOCAL a_low IS MAX(MINFORCE, THR_MIN_THRUST_FRAC * f_avail_n) / mass_kg.
  LOCAL a_high IS MIN(MAXFORCE, THR_DEAD_LOW * f_avail_n) / mass_kg.     // never into the engine dead band (guid_throttle would jump it to full)
  LOCAL a_cmd IS MAX(a_low, MIN(a_high, afc)).
  LOCAL wanted IS guid_throttle(a_cmd * mass_kg, f_avail_n, THR_MIN_THRUST_FRAC, prev_frac).
  RETURN LEXICON("THR", thr_command(wanted), "A_CMD", a_cmd, "WANTED", wanted).
}
