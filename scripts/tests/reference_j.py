"""reference_j.py -- expected numbers for the J-class (Luminary 210) pad tests, and the mass/performance study (release 1.2).

Run with:  python -I scripts/tests/reference_j.py

A plain-Python mirror of lm_j_guidance.ks / lm_j_ignition.ks (the same maths as reference.py, which holds the Apollo 11
versions; the cubic, quadratic guidance and limit functions are repeated here so this file stands alone and does not print
reference.py's output on import). Constants are the Apollo 17 pad load in SI (docs/superpowers/specs/2026-11-13-luminary210-padloads-research.md).
The point-mass simulation is a study tool: it flies the ignition-to-handover path of both profiles with a chosen mass and thrust.
"""
import math

# ---- constants -------------------------------------------------------------------------------------------------------
J = dict(
    RBRFG=(-950.4757622, 0.0, -3578.791217), VBRFG=(-59.88380, 0.0, -50.82844), ABRFG=(-0.2189220, 0.0, -2.530587),
    JBRFG_Z=-4.609691263e-3 / 8,
    RAPFG=(48.31080, 0.0, -8.337926), VAPFG=(-1.077395, 0.0, 0.0076049), AAPFG=(0.02352395, 0.0, -0.1797183),
    JAPFG_Z=1.315931328e-2 / 8,
    RIGNX=-47593.00514, RIGNZ=-469983.8606, VIGN=1689.475188,
    KIGNX=-0.334, KIGNY=-7.240813648e-7, KIGNV=-498.0,
    ZOOMTIME=26.0, LEADTIME=-2.2, TENDBRAK=62.0, TENDAPPR=12.0, DELTTFAP=-70.0,
    TAUHZ=5.0, QHZ=0.4, AHZLIM=1.93898 * 0.3048,
)
A11 = dict(
    RBRFG=(52.375308, 0.0, -3254.836061), VBRFG=(-32.271005, 0.0, -0.316992), ABRFG=(0.19022568, 0.0, -2.77502112),
    JBRFG_Z=-7.173e-4,
    RAPFG=(33.858708, 0.0, -8.1668112), VAPFG=(-1.5218664, 0.0, 0.0755904), AAPFG=(-0.07997952, 0.0, -0.1560576),
    JAPFG_Z=5.51e-4 / 8,
    RIGNX=-39782.453328, RIGNZ=-436655.657, VIGN=1690.256208,
    KIGNX=-0.617631, KIGNY=-2.4770341207e-6, KIGNV=-410.0,
    ZOOMTIME=26.0, LEADTIME=-2.2, TENDBRAK=62.0, TENDAPPR=12.0, DELTTFAP=-110.0,
)
MOON_MU, MOON_R = 4.9028e12, 1737400.0       # the real Moon, for the study only (kOS reads the Sol Moon)


def mag(a): return math.sqrt(sum(x * x for x in a))


# ---- guidance maths (mirror of lm_j_guidance.ks / reference.py) -----------------------------------------------------
def tgo_cubic(rg, vg, rd, vd, ad, jd, guess):
    t = guess
    if t <= 0:
        return False, guess
    for _ in range(20):
        f = jd * t**3 - 6 * ad * t**2 + 6 * (vg + 3 * vd) * t + 24 * (rg - rd)
        d = 3 * jd * t**2 - 12 * ad * t + 6 * (vg + 3 * vd)
        if d == 0:
            return False, guess
        step = f / d
        t -= step
        if t <= 0:
            return False, guess
        if abs(step) < 1e-3:
            return True, t
    return False, guess


def quad_acg(rg, vg, tgo, rd, vd, ad, leadtime):
    if tgo < 1:
        return ad
    rho = (tgo + leadtime) / tgo
    c_v, c_r, c_vd, c_a = 2 * rho**2 - rho, 3 * rho**2 - 2 * rho, 4 * rho**2 - 3 * rho, 6 * rho**2 - 6 * rho + 1
    return tuple(c_a * ad[i] - 6 * (c_vd * vd[i] + c_v * vg[i]) / tgo + 12 * c_r * (rd[i] - rg[i]) / tgo**2 for i in range(len(ad)))


def limit_afc(afc, mass, fmax):
    if mass <= 0 or fmax <= 0:
        return afc
    amax = fmax / mass
    if mag(afc) <= amax:
        return afc
    keep = sum(c * c for c in afc[:-1])
    room = amax * amax - keep
    horiz = math.sqrt(room) if room > 0 else 0.0
    return afc[:-1] + (math.copysign(horiz, afc[-1]),)


def ign_ddum(p, rg, vg):
    num = (p["RIGNZ"] - rg[2]) + p["KIGNY"] * rg[1] ** 2 + p["KIGNX"] * (rg[0] - p["RIGNX"]) + p["KIGNV"] * (mag(vg) - p["VIGN"])
    return num / (vg[2] - p["KIGNX"] * vg[0])


def hz_law(vgu, a_prev, g_mag, p=J):
    """j_guid_hz: the P66 horizontal law. Returns (g, a_y, a_z)."""
    lim = p["AHZLIM"]
    ay = max(-lim, min(lim, -p["QHZ"] * a_prev[1] - vgu[1] / p["TAUHZ"]))
    az = max(-lim, min(lim, -p["QHZ"] * a_prev[2] - vgu[2] / p["TAUHZ"]))
    return (g_mag, ay, az)


# ---- point-mass flight: ignition to the P66 handover --------------------------------------------------------------------
def fly(p, mass0, fmax, isp, dt=1.0):
    """Braking then approach, as reference.sim_braking / sim_approach, with the profile's pad loads. Fixed guidance axes,
    plane motion, no throttle dead band or engine lag (a first-order study). Returns a dict of results."""
    pos = (MOON_R + p["RIGNX"], p["RIGNZ"])
    rmag = math.hypot(*pos)
    tang = (-pos[1] / rmag, pos[0] / rmag)
    vel = (p["VIGN"] * tang[0], p["VIGN"] * tang[1])
    tgt = {"brake": (p["RBRFG"], p["VBRFG"], p["ABRFG"], p["JBRFG_Z"]), "appr": (p["RAPFG"], p["VAPFG"], p["AAPFG"], p["JAPFG_Z"])}
    phase, t_now, tgo, mass = "brake", 0.0, 600.0, mass0
    peak, peak_t, peak_phase, t_switch, handover, fail = 0.0, 0.0, "", None, None, None
    over = 0.0                                # seconds the commanded thrust would exceed the engine's maximum
    while t_now < 2500:
        rd3, vd3, ad3, jd = tgt[phase]
        rd, vd, ad = (rd3[0], rd3[2]), (vd3[0], vd3[2]), (ad3[0], ad3[2])
        rg, vg = (pos[0] - MOON_R, pos[1]), vel
        ok, tgo = tgo_cubic(rg[1], vg[1], rd[1], vd[1], ad[1], jd, tgo)
        if not ok:
            fail = "time-to-go did not converge at t=%.0f in %s" % (t_now, phase)
            break
        if phase == "brake" and tgo < p["TENDBRAK"]:
            phase, t_switch = "appr", t_now
            tgo -= p["DELTTFAP"]
            continue
        rm = math.hypot(*pos)
        g = (-MOON_MU * pos[0] / rm**3, -MOON_MU * pos[1] / rm**3)
        acg = quad_acg(rg, vg, tgo, rd, vd, ad, p["LEADTIME"])
        want = (acg[0] - g[0], acg[1] - g[1])
        frac = mag(want) * mass / fmax
        if frac > peak:
            peak, peak_t, peak_phase = frac, t_now, phase
        if frac > 1.0:
            over += dt
        afc = limit_afc(want, mass, fmax)
        if phase == "appr" and tgo < p["TENDAPPR"]:
            handover = dict(t=t_now, alt=rg[0], down=rg[1], vup=vg[0], vdown=vg[1], mass=mass)
            break
        acc = (afc[0] + g[0], afc[1] + g[1])
        pos = (pos[0] + vel[0] * dt + 0.5 * acc[0] * dt * dt, pos[1] + vel[1] * dt + 0.5 * acc[1] * dt * dt)
        vel = (vel[0] + acc[0] * dt, vel[1] + acc[1] * dt)
        mass -= mag(afc) * mass / (isp * 9.80665) * dt
        t_now += dt
    return dict(fail=fail, peak=peak, peak_t=peak_t, peak_phase=peak_phase, over=over, t_switch=t_switch, handover=handover, mass_end=mass)


if __name__ == "__main__":
    print("=== numbers typed into test_j.ks ===")
    print("cubic tgo, J braking, ship 3 km before the nominal ignition point speed VIGN:")
    rg = (J["RIGNX"], 0.0, J["RIGNZ"] - 3000.0)
    vg = (0.0, 0.0, J["VIGN"])
    print("  ddum at nominal state         :", ign_ddum(J, (J["RIGNX"], 0.0, J["RIGNZ"]), (0.0, 0.0, J["VIGN"])))
    print("  ddum 1 km short               :", ign_ddum(J, (J["RIGNX"], 0.0, J["RIGNZ"] - 1000), (0.0, 0.0, J["VIGN"])))
    print("  ddum 2 km ahead               :", ign_ddum(J, (J["RIGNX"], 0.0, J["RIGNZ"] + 2000), (0.0, 0.0, J["VIGN"])))
    print("  ddum high, crossrange, slow   :", ign_ddum(J, (J["RIGNX"] + 500, 800.0, J["RIGNZ"]), (30.0, 0.0, J["VIGN"] - 15)))
    ok, t = tgo_cubic(-900.0, -50.0, J["RBRFG"][2] * 0 + (-3578.791217), -50.82844, -2.530587, J["JBRFG_Z"], 400.0)
    # downrange components only: rg_z = -80000, vg_z = 1500, guess 500
    ok, t = tgo_cubic(-80000.0, 1500.0, J["RBRFG"][2], J["VBRFG"][2], J["ABRFG"][2], J["JBRFG_Z"], 500.0)
    print("  cubic (rg_z -80000, vg_z 1500, guess 500): ok=%s tgo=%.6f" % (ok, t))
    acg = quad_acg((-900.0, 0.0, -80000.0), (-40.0, 0.0, 1500.0), t, J["RBRFG"], J["VBRFG"], J["ABRFG"], J["LEADTIME"])
    print("  quad_acg at that tgo, rg=(-900,0,-80000) vg=(-40,0,1500):", tuple("%.9f" % c for c in acg))
    print("hz law:")
    for vgu, prev in [((0, 0, 0), (1.6, 0, 0)), ((0, 2.0, -3.0), (1.6, 0, 0)), ((0, 2.0, -3.0), (1.6, -0.3, 0.5)), ((0, 10.0, -10.0), (1.6, 0, 0)), ((0, -10.0, 10.0), (1.6, 0.3, -0.3))]:
        print("  vgu=%s prev=%s ->" % (vgu, prev), tuple("%.9f" % c for c in hz_law(vgu, prev, 1.62)))
    print("AHZLIM = %.6f m/s^2" % J["AHZLIM"])
    print("steady state of the law: a = -v/(TAUHZ (1+QHZ)) -> 7 s time constant; v=2: %.6f" % (-2.0 / (J["TAUHZ"] * (1 + J["QHZ"]))))

    print()
    print("=== study: ignition to P66 handover, point mass (task 8) ===")
    cases = [
        ("Apollo 11 LM (pad load 15269.7 kg, 43.45 kN, 311 s)", A11, 15269.7, 43454.7, 311.0),
        ("J pad loads, same craft as Apollo 11", J, 15269.7, 43454.7, 311.0),
        ("Apollo 17 LM at PDI (about 16.4 t, 45.04 kN max, 311 s)", J, 16400.0, 45040.0, 311.0),
        ("user's lander (16183 kg, 46.71 kN, 305 s), A11 pad loads", A11, 16183.0, 46710.0, 305.0),
        ("user's lander (16183 kg, 46.71 kN, 305 s), J pad loads", J, 16183.0, 46710.0, 305.0),
        ("user's lander, J pad loads, 12 t (light)", J, 12000.0, 46710.0, 305.0),
        ("user's lander, J pad loads, 20 t (heavy)", J, 20000.0, 46710.0, 305.0),
    ]
    for name, p, m0, fmax, isp in cases:
        r = fly(p, m0, fmax, isp)
        print(name)
        if r["fail"]:
            print("   FAILED:", r["fail"])
            continue
        h = r["handover"]
        print("   thrust wanted peaks at %.2f of full thrust (t=%.0f s, %s); over 1.0 for %.0f s" % (r["peak"], r["peak_t"], r["peak_phase"], r["over"]))
        if h:
            print("   P64 starts t=%.0f s; handover to P66 at t=%.0f s: alt %.1f m, downrange %.1f m, vup %.2f, vdown %.2f m/s, mass %.0f kg (%.0f kg burned)"
                  % (r["t_switch"], h["t"], h["alt"], h["down"], h["vup"], h["vdown"], h["mass"], m0 - h["mass"]))
        else:
            print("   no handover reached")

    print()
    print("=== study: heaviest craft that still reaches the P66 handover (alt < 200 m, downrange speed < 5 m/s) with the user's engine ===")

    def reaches(p, m0, fmax, isp):
        r = fly(p, m0, fmax, isp)
        h = r["handover"]
        return h is not None and h["alt"] < 200 and abs(h["vdown"]) < 5

    for name, p in (("Apollo 11 pad loads", A11), ("J pad loads", J)):
        lo, hi = 10000.0, 25000.0
        for _ in range(30):
            mid = (lo + hi) / 2
            if reaches(p, mid, 46710.0, 305.0):
                lo = mid
            else:
                hi = mid
        print("%-20s heaviest mass at ignition: %.0f kg (thrust/weight on the Moon at ignition %.2f)" % (name, lo, 46710.0 / lo / 1.62))
