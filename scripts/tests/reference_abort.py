"""reference_abort.py -- the abort maths (release 1.5, P70 and P71) in Python, numpy-free.

The reference for the abt_ functions of scripts/lm/ascent/lm_ascent_guid.ks, for abt_expected_lead (the planner) and for
the flight logic of scripts/lm/ascent/lm_p70.ks: abt_sim flies whole aborts from descent states. The self-checks hold the
model against the Luminary pad loads (docs/superpowers/research-1.5-aborts.md); the "KOS TEST VALUES" block is what the
pad tests assert. Run: python scripts/tests/reference_abort.py (exit 1 on a failed check). SI units, right-handed
tuples, as reference_ascent.py. Sources: Luminary 099 and 210 P70-P71.agc, ASCENT_GUIDANCE.agc, CONTROLLED_CONSTANTS.agc.
"""
import math
import sys

from reference_ascent import (ASC_HINJECT_M, ASC_RISE_ALT_M, ASC_T_CUT, ASC_TURN_DEG_S, FT, MU, NM, PREFS_ROTATION,
                              SITE_R, TFF_LIMIT_M, add, asc_engine, asc_engine_aps, asc_guide, asc_new, asc_qaxis,
                              asc_rise_done, asc_sim_push, asc_state, asc_target, clamp, cross, dot, guide_case, mag,
                              scale, sub, turn_toward, unit, vang)

# ---- Loads (lm_constants.ks "Aborts (1.5)", lm_j_constants.ks) ---------------------------------------------------------
DPSVEX = 2955.88868             # m/s (CC:97)
ABT_DPS_THRUST_N = 43670.0      # K(1/DV)
ABT_DPS_MDOT = 14.80            # MDOTDPS, kg/s
ABT_DPS_TAILOFF_A11 = 0.38      # 099 DTDECAY
ABT_DPS_TAILOFF_J = 0.24        # 210 100PCTTO
ABT_RDOTD = 5.9436              # ABTRDOT, 19.5 ft/s
ABT_YLIM_M = 15186.4            # YLIM, 8.2 nm
ABT_COSTHET2 = 0.8660254        # COSTHET2
ABT_VMIN_FPS = 5515.0           # VMIN
ABT_POLY = {"DPS": (5641.98, 0.17736, -1.144e-3, 8.122e-7), "APS": (5644.77, 0.13801, -1.062e-3, 7.670e-7)}
J_ABT_J1, J_ABT_K1 = 6045737.6, -605981.9       # ft, ft/rad (Apollo 17)
J_ABT_J2, J_ABT_K2 = 6036605.0, -318029.5
J_ABT_THETCRIT = 6.4323         # deg
J_ABT_RAMIN = 5872844.9         # ft, a radius
J_ABT_SITE_R = 1734484.0        # m, the Apollo 17 landing-site radius

RCO_T = SITE_R + ASC_HINJECT_M
G0 = 9.80665
DPS_THRUST_N, DPS_VE = 46710.0, 305 * G0        # the craft's engines (probe_lander.ks), for the closed loop
APS_THRUST_N, APS_VE = 15570.0, 311 * G0
DRY_KG = {"DPS": 7000.0, "APS": 2600.0}         # the closed loop's mass floor
A11_SITE_R = 1735017.0                          # m, |RLS| of the Apollo 11 pad load (research 5.1)

# ---- Guidance (the abt_ functions of lm_ascent_guid.ks) ---------------------------------------------------------------

def abt_engine_dps(profile, mass_kg):
    """P70INIT: the descent engine as the guidance assumes it, from the present mass."""
    return {"VE": DPSVEX, "AT0": ABT_DPS_THRUST_N / mass_kg, "TBUP0": mass_kg / ABT_DPS_MDOT,
            "INVDV0": mass_kg / (ABT_DPS_THRUST_N * 2.0),
            "TAILOFF": ABT_DPS_TAILOFF_J if profile == "J" else ABT_DPS_TAILOFF_A11}


def abt_rotation(rot_on, want, axis, ur):
    """ANG1CHEK: (direction to command, still rotating). Within 90 degrees steer; else straight up until near vertical."""
    if rot_on and vang(want, axis) >= 90.0 and dot(unit(axis), ur) < ABT_COSTHET2:
        return ur, True
    return want, False


def abt_cross_range(y):
    """More than YLIM out of the CSM plane: the target is YLIM towards it; otherwise the plane itself."""
    if abs(y) <= ABT_YLIM_M:
        return 0.0
    return math.copysign(abs(y) - ABT_YLIM_M, y)


def abt_a11_zdotd(key, since_s):
    """Luminary 099: the horizontal speed wanted, a cubic in the time from ignition with a floor, m/s."""
    a, b, c, d = ABT_POLY[key]
    return max(ABT_VMIN_FPS, a + since_s * (b + since_s * (c + since_s * d))) * FT


def abt_csm_lead(ur, r_csm, v_csm):
    """THETCOMP, signed by the CSM's orbit: positive when the CSM is ahead, degrees."""
    ang = vang(ur, r_csm)
    return -ang if dot(cross(ur, unit(r_csm)), cross(r_csm, v_csm)) < 0 else ang


def abt_j_set(theta_deg):
    return 1 if theta_deg < J_ABT_THETCRIT else 2


def abt_j_target(has_csm, theta_deg, set_no, rp, site_r, mu):
    """ZDOTDCMP (210): the apolune radius from the CSM's lead (semi-major axis J + K theta), floored, and ZDOTD."""
    shift = site_r - J_ABT_SITE_R
    ra = J_ABT_RAMIN * FT + shift
    if has_csm:
        j, k = (J_ABT_J1, J_ABT_K1) if set_no == 1 else (J_ABT_J2, J_ABT_K2)
        semi_major = j * FT + shift + k * FT * math.radians(theta_deg)
        ra = max(ra, 2.0 * semi_major - rp)
    return {"RA": ra, "ZDOTD": math.sqrt(2.0 * mu * ra / (rp * (ra + rp)))}


def abt_rp(g, st, tgo, trimming):
    """RPCOMP: the burnout radius predicted from this pass (the thrust terms only while guiding)."""
    rp = st["RMAG"] + st["RDOT"] * tgo
    if not trimming:
        rp += (g["A"] * tgo ** 2 / 2.0 + g["B"] * tgo ** 3 / 6.0) / g["TBUP"]
    return rp


def abt_expected_lead(r_csm, r_pdi):
    """The CSM's lead at PDI after a DOI flown beside it: both leave one point, the LM flies half its descent orbit."""
    return 180.0 * ((r_csm + r_pdi) / 2.0 / r_csm) ** 1.5 - 180.0


# ---- A whole abort, as lm_p70.ks flies it -----------------------------------------------------------------------------

def abt_sim(profile, engine_key, r0, v0, axis0, qaxis, mu, site_r, mass_kg, thrust_n, ve_ms, since_s, csm=None,
            kept=None, stop_after=None, dt_s=1.0):
    """One abort from a state. The attitude is held until the first measured pass; then vertical rise, rotation, guidance
    turned no faster than ASC_TURN_DEG_S, the engine estimate every 2 s, J retargeting every pass, cut-off under 4 s.
    since_s: seconds since ignition (the first time to go). csm: t -> (r, v), t from the first abort's start, or None.
    kept: an earlier call's result, for P71 after P70. stop_after: return mid-flight after this many seconds.
    RP_LOW and RP_HIGH are the extremes of the predicted burnout radius."""
    if kept is None:
        engine = abt_engine_dps(profile, mass_kg) if engine_key == "DPS" else asc_engine_aps(profile)
        g = asc_new(profile, engine)
        g["TGO"] = since_s
        rco = site_r + ASC_HINJECT_M
        y = asc_state(r0, v0, qaxis, mu, rco)["Y"]
        tgt = asc_target(rco, abt_cross_range(y), ABT_RDOTD, 0.0)
        lead = abt_csm_lead(unit(r0), *csm(0.0)) if csm else 0.0
        j_set = abt_j_set(lead) if csm else 1
        rp, rising, rot, t = rco, True, True, 0.0
        if profile == "A11":
            tgt["ZDOTD"] = abt_a11_zdotd(engine_key, since_s)
        else:
            tgt["ZDOTD"] = abt_j_target(csm is not None, lead, j_set, rp, site_r, mu)["ZDOTD"]
    else:
        g = asc_new(profile, asc_engine_aps(profile))
        for key in ("A", "B", "C", "D", "FLPC"):
            g[key] = kept["G"][key]
        g["TGO"] = 2.0 * kept["G"]["TGO"]
        tgt, qaxis, rco = dict(kept["TGT"]), kept["QAXIS"], kept["TGT"]["RCO"]
        j_set, rp, rising, rot, t = kept["J_SET"], kept["RP"], kept["RISING"], kept["ROT"], kept["T"]

    flow = thrust_n / ve_ms
    r_vec, v_vec, mass, axis = r0, v0, mass_kg, unit(axis0)
    t_start, pass_t, pass_dv, guiding, min_r = t, 0.0, 0.0, False, mag(r0)
    rp_range = [rp, rp]

    def result(ok):
        return {"OK": ok, "BURN_S": t - t_start, "R_END": r_vec, "V_END": v_vec, "MASS_END": mass, "AXIS": axis,
                "MIN_R": min_r, "TGT": tgt, "QAXIS": qaxis, "G": g, "J_SET": j_set, "RP": rp, "RISING": rising,
                "ROT": rot, "T": t, "RP_LOW": rp_range[0], "RP_HIGH": rp_range[1]}

    while t - t_start < 900.0:
        if guiding:
            st = asc_state(r_vec, v_vec, qaxis, mu, rco)
            if profile == "J":
                lead = abt_csm_lead(st["UR"], *csm(t)) if csm else 0.0
                tgt["ZDOTD"] = abt_j_target(csm is not None, lead, j_set, rp, site_r, mu)["ZDOTD"]
            cmd = asc_guide(g, st, tgt)
            rp = abt_rp(g, st, cmd["TGO"], False)
            rp_range = [min(rp_range[0], rp), max(rp_range[1], rp)]
            want = cmd["DIR"]
            if rising:
                height = st["RMAG"] - site_r
                if asc_rise_done(profile, height, st["RDOT"], 0.0):
                    rising = False
                    if height < ASC_RISE_ALT_M:
                        rot = False
                else:
                    want = st["UR"]
            if not rising and rot:
                want, rot = abt_rotation(rot, cmd["DIR"], axis, st["UR"])
            axis = turn_toward(axis, want, ASC_TURN_DEG_S * dt_s)
            if cmd["TGO"] < ASC_T_CUT:
                last = max(0.0, cmd["TGO"])
                if last > 0.001:
                    r_vec, v_vec, mass, _ = asc_sim_push(r_vec, v_vec, mass, axis, last, mu, flow, ve_ms)
                    t += last
                v_vec = add(v_vec, scale(axis, g["TAILOFF"] * thrust_n / mass))     # the tail-off the guidance allows for
                return result(True)
        if mass - flow * dt_s <= DRY_KG[engine_key]:
            return result(False)
        r_vec, v_vec, mass, dv = asc_sim_push(r_vec, v_vec, mass, axis, dt_s, mu, flow, ve_ms)
        min_r = min(min_r, mag(r_vec))
        t += dt_s
        pass_t += dt_s
        pass_dv += dv
        if pass_t >= 2.0 - 1e-6:
            if asc_engine(g, pass_dv, pass_t):
                guiding = True
            pass_t, pass_dv = 0.0, 0.0
        if stop_after is not None and t - t_start >= stop_after - 1e-6:
            return result(False)
    return result(False)


# ---- Checks -------------------------------------------------------------------------------------------------------

FAILURES = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("  " + detail if detail else ""))
    if not ok:
        FAILURES.append(name)


def apsides(r, vh, vr):
    energy = (vh * vh + vr * vr) / 2 - MU / r
    a = -MU / (2 * energy)
    ecc = math.sqrt(max(0.0, 1 + 2 * energy * (r * vh) ** 2 / MU ** 2))
    return a * (1 + ecc), a * (1 - ecc)


def target_checks():
    for key, wanted in (("DPS", (126, 131, 116, 89, 58, 43, 30.5)), ("APS", (128, 130, 114, 87, 56, 41, 30.5))):
        for t, apo_nm in zip((0, 120, 240, 360, 480, 540, 600), wanted):
            apo = apsides(A11_SITE_R + ASC_HINJECT_M, abt_a11_zdotd(key, t), ABT_RDOTD)[0]
            got = (apo - A11_SITE_R) / NM
            check("A11 %s apolune at %d s" % (key, t), abs(got - apo_nm) <= 1.5, "%.1f nm (research %.1f)" % (got, apo_nm))

    for theta, apo_nm in zip((-20, -10, -7, 0, 5, 7, 10, 20), (176.7, 141.8, 131.4, 107.0, 89.6, 91.2, 85.8, 67.5)):
        set_no = abt_j_set(theta)
        res = abt_j_target(True, theta, set_no, RCO_T, SITE_R, MU)
        got = (res["RA"] - SITE_R) / NM
        check("J apolune at lead %d" % theta, abs(got - apo_nm) <= 0.3 and set_no == (1 if theta < J_ABT_THETCRIT else 2),
              "%.2f nm, set %d" % (got, set_no))
    for label, res in (("lead 60", abt_j_target(True, 60, 2, RCO_T, SITE_R, MU)),
                       ("no CSM", abt_j_target(False, 0, 1, RCO_T, SITE_R, MU))):
        check("J floor, " + label, abs(res["RA"] - 1791309.1) <= 1 and abs(res["ZDOTD"] - 1680.635) <= 0.01,
              "RA %.1f ZDOTD %.4f" % (res["RA"], res["ZDOTD"]))
    j_apo = abt_j_target(True, -7, 1, RCO_T, SITE_R, MU)["RA"] - SITE_R
    a_apo = apsides(RCO_T, abt_a11_zdotd("DPS", 0), ABT_RDOTD)[0] - SITE_R
    check("J at the PDI lead against A11 at ignition", abs(j_apo - a_apo) <= 10 * NM,
          "%.1f against %.1f nm" % (j_apo / NM, a_apo / NM))

    for y, yco in ((20000, 4813.6), (-20000, -4813.6), (10000, 0), (15186.4, 0)):
        check("cross-range %d" % y, abs(abt_cross_range(y) - yco) < 0.001, "%.1f" % abt_cross_range(y))


def rotation_checks():
    ur = (1.0, 0.0, 0.0)

    def tilt(deg, back):
        return (math.cos(math.radians(deg)), 0.0, (-1 if back else 1) * math.sin(math.radians(deg)))

    cases = ((True, 80, 55, "up", True), (True, 20, 55, "want", False), (True, 25, 75, "want", False),
             (False, 80, 55, "want", False))
    for flag, axis_deg, want_deg, expect, still_on in cases:
        want = tilt(want_deg, False)
        direction, on = abt_rotation(flag, want, tilt(axis_deg, True), ur)
        target = ur if expect == "up" else want
        check("rotation %s axis %d want %d" % (flag, axis_deg, want_deg), vang(direction, target) < 1e-6 and on == still_on)


def lead_checks():
    r_csm = 1846870.0
    lm = (SITE_R, 0.0, 0.0)
    ahead = (r_csm * math.cos(math.radians(10)), r_csm * math.sin(math.radians(10)), 0.0)
    v_with = (-1600 * math.sin(math.radians(10)), 1600 * math.cos(math.radians(10)), 0.0)
    check("CSM lead ahead", abs(abt_csm_lead(unit(lm), ahead, v_with) - 10) < 1e-6)
    check("CSM lead, orbit reversed", abs(abt_csm_lead(unit(lm), ahead, scale(v_with, -1)) + 10) < 1e-6)
    lead = abt_expected_lead(SITE_R + 60 * NM, SITE_R + 50000 * FT)
    check("expected lead at PDI", abs(lead + 6.96) <= 0.05, "%.3f deg" % lead)
    dps = abt_engine_dps("A11", 15000)
    check("descent engine start values", abs(dps["AT0"] - 2.91133) < 1e-4 and abs(dps["TBUP0"] - 1013.51) < 0.01
          and dps["TAILOFF"] == 0.38 and abt_engine_dps("J", 15000)["TAILOFF"] == 0.24)


# ---- Closed loop ----------------------------------------------------------------------------------------------------

def csm_orbit(lead_deg, since_abort_s):
    """A CSM in a 60 nm circle, lead_deg ahead of the +X axis at the abort's start, moving towards +Y."""
    r = SITE_R + 60 * NM
    ang = math.radians(lead_deg) + math.sqrt(MU / r ** 3) * since_abort_s
    speed = math.sqrt(MU / r)
    return (r * math.cos(ang), r * math.sin(ang), 0.0), (-speed * math.sin(ang), speed * math.cos(ang), 0.0)


def state_case(height, horiz, radial, tilt_back_deg):
    """Position, velocity and thrust axis in the CSM plane: horizontal speed towards +Y, thrust tilted backward."""
    r_vec = (SITE_R + height, 0.0, 0.0)
    v_vec = (radial, horiz, 0.0)
    axis = (math.cos(math.radians(tilt_back_deg)), -math.sin(math.radians(tilt_back_deg)), 0.0)
    return r_vec, v_vec, axis


SURFACE = ((SITE_R, 0.0, 0.0), (0.0, PREFS_ROTATION * SITE_R, 0.0), (1.0, 0.0, 0.0))


def fly(profile, engine_key, state, mass_kg, since_s, kept=None, stop_after=None):
    thrust, ve = (DPS_THRUST_N, DPS_VE) if engine_key == "DPS" else (APS_THRUST_N, APS_VE)
    r_vec, v_vec, axis = state
    qaxis = asc_qaxis(*csm_orbit(-7, 0))
    return abt_sim(profile, engine_key, r_vec, v_vec, axis, qaxis, MU, SITE_R, mass_kg, thrust, ve, since_s,
                   csm=lambda t: csm_orbit(-7, t), kept=kept, stop_after=stop_after)


def arrives(name, out, start_r, height="target"):
    """Cut off on the target speeds and never below the site. height: "target" (within 500 m of it); "short", an abort
    too brief to climb to it (early in P63): it inserts no lower than it started; "high", P71 finishing a P70: the climb
    the descent engine started cannot be taken back (Luminary never lets the radial rate term go positive), so it
    inserts at or above the target, by 8 km at most."""
    st = asc_state(out["R_END"], out["V_END"], out["QAXIS"], MU, out["TGT"]["RCO"])
    dz = st["ZDOT"] - out["TGT"]["ZDOTD"]
    dr = st["RDOT"] - ABT_RDOTD
    dh = st["RMAG"] - out["TGT"]["RCO"]
    height_ok = abs(dh) <= 500
    if height == "short":
        height_ok = st["RMAG"] >= start_r - 1 and dh <= 500
    elif height == "high":
        height_ok = -500 <= dh <= 8000
    low = out["MIN_R"] - SITE_R
    check("abort " + name, out["OK"] and abs(dz) <= 2 and abs(dr) <= 2 and height_ok and low >= -1,
          "ok %s burn %.1f s, target %.1f, dZ %.2f dR %.2f m/s, insertion %.0f m (dH %.0f), lowest %.0f m, mass %.0f kg"
          % (out["OK"], out["BURN_S"], out["TGT"]["ZDOTD"], dz, dr, st["RMAG"] - SITE_R, dh, low, out["MASS_END"]))


def closed_loop_checks():
    for profile in ("A11", "J"):
        early = state_case(14800, 1690, 0, 85)
        arrives("early %s P70" % profile, fly(profile, "DPS", early, 15800, 30), mag(early[0]), "short")
        mid = state_case(10000, 1000, -30, 70)
        arrives("mid P63 %s P70" % profile, fly(profile, "DPS", mid, 12000, 300), mag(mid[0]))
        # Late in the descent the descent tanks run dry before orbit (MSC-01220 3.2): P71 finishes the same abort.
        for name, state, mass, since in (("high gate", state_case(2300, 150, -45, 40), 8700, 500),
                                         ("P66", state_case(50, 1, -1, 5), 8300, 700)):
            dry = fly(profile, "DPS", state, mass, since)
            check("abort %s %s P70 runs dry" % (name, profile), not dry["OK"] and dry["MASS_END"] < DRY_KG["DPS"] + 20
                  and dry["MIN_R"] >= SITE_R - 1, "burn %.1f s, mass %.0f kg" % (dry["BURN_S"], dry["MASS_END"]))
            after = fly(profile, "APS", (dry["R_END"], dry["V_END"], dry["AXIS"]), 4900, since, kept=dry)
            arrives("%s %s P70 dry then P71" % (name, profile), after, mag(dry["R_END"]), "high")
            arrives("%s %s direct P71" % (name, profile), fly(profile, "APS", state, 4900, since), mag(state[0]))
        arrives("surface %s direct P71" % profile, fly(profile, "APS", SURFACE, 4900, 900), SITE_R)
        part = fly(profile, "DPS", mid, 12000, 300, stop_after=100)
        after = fly(profile, "APS", (part["R_END"], part["V_END"], part["AXIS"]), 4900, 300, kept=part)
        arrives("mid P63 %s P70 then P71" % profile, after, mag(part["R_END"]), "high")


# ---- Values for the pad tests ----------------------------------------------------------------------------------------

def kos_values():
    print("\nKOS TEST VALUES")
    for key in ("DPS", "APS"):
        print("a11 zdotd %s: " % key + "  ".join("%d s %.4f" % (t, abt_a11_zdotd(key, t)) for t in (0, 300, 540, 700)))
    for theta in (-7, 0, 6.4, 6.5, 60):
        res = abt_j_target(True, theta, abt_j_set(theta), RCO_T, SITE_R, MU)
        print("j target lead %s set %d: RA %.1f ZDOTD %.4f" % (theta, abt_j_set(theta), res["RA"], res["ZDOTD"]))
    g = asc_new("A11", abt_engine_dps("A11", 15000))
    print("dps start: TBUP %.4f AT %.5f EST %.4f TAILOFF %.2f" % (g["TBUP"], g["AT"], g["EST"][0], g["TAILOFF"]))
    asc_engine(g, 5.9, 2.0)
    print("dps engine 1 pass 5.9 m/s: TBUP %.4f AT %.5f" % (g["TBUP"], g["AT"]))
    _, st, tgt = guide_case()
    g = asc_new("A11", abt_engine_dps("A11", 15000))
    g["TGO"] = 250.0
    cmd = asc_guide(g, st, tgt)
    print("dps guide: TGO %.4f AR %.6f AY %.6f AP %.6f" % (cmd["TGO"], cmd["AR"], cmd["AY"], cmd["AP"]))
    print("dps guide: rp guiding %.2f trimming %.2f" % (abt_rp(g, st, cmd["TGO"], False), abt_rp(g, st, cmd["TGO"], True)))


if __name__ == "__main__":
    target_checks()
    rotation_checks()
    lead_checks()
    closed_loop_checks()
    kos_values()
    if FAILURES:
        print("\n%d CHECK(S) FAILED: %s" % (len(FAILURES), ", ".join(FAILURES)))
        sys.exit(1)
    print("\nALL CHECKS PASSED")
