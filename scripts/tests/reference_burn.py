"""reference_burn.py -- the burn maths (scripts/lm/burn/lm_burn_s.ks) in Python, numpy-free.

The numbers it prints are the ones test_burn.ks asserts. Run: python scripts/tests/reference_burn.py
Luminary 099 source: D:/Projects/AGC Repo/Apollo-11/Luminary099 (P40-P47.agc, P34-35_P74-75.agc, CONTROLLED_CONSTANTS.agc).
"""
import math

MU_MOON = 4.9028e12          # m^3/s^2, as the planner tests
R_MOON = 1737400.0           # m
M_PER_NM = 1852.0
FDPS = 43670.0               # N, CC:36 (4.3670 B-7, unit 10 kN)
FRCS2 = 889.6                # N, CC:46 (200 lbf)
FRCS4 = 1779.2               # N, CC:45 (400 lbf)
DPSVEX = 2955.88868          # m/s, CC:97
TDECAY_S = -0.38             # s, CC:38 (DTDECAY -38 cs)
THRUST_10PCT = 4671.0        # N, CC:60 (S40.136, .4671 M.NEWTON)
NOTHROTL_S = 95.0            # s, P4:1043 and 89SECS + 6SEC
IMPULSE_S = 6.0              # s, 6SEC
STEER_STOP_S = 4.0           # s, FOURSECS
PASS_S = 2.0                 # s, one servicer pass (DELVREF is the delta-V of the last pass)
CAP_NM = 9999.9


def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def mag(a): return math.sqrt(dot(a, a))
def scale(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def unit(a):
    m = mag(a)
    return (a[0] / m, a[1] / m, a[2] / m)


def s40_1(delvsin):
    """Thrust direction and VG at TIG (S40.1, P4:662-740). The finite-burn correction is not modelled."""
    vgmag = mag(delvsin)
    return {"VG": delvsin, "UT": unit(delvsin), "VGMAG": vgmag, "DELVREF": (0.0, 0.0, 0.0)}


def s40_2_3(ut, rtig, vtig):
    """Preferred orientation (S40.2,3, P4:825-860): X = UT, Y = unit(UT x RTIG) (or UT x VTIG), Z = X x Y."""
    cr = cross(ut, rtig)
    if mag(cr) < 1e-3 * mag(ut) * mag(rtig):
        cr = cross(ut, vtig)
    y_axis = unit(cr)
    return {"X": ut, "Y": y_axis, "Z": cross(ut, y_axis)}


def s40_13(mass, vg_mag, profile):
    """Burn time at the 10 percent level and the throttle flags (S40.13, P4:1000-1111)."""
    if profile == "J":
        ull = 6.5 * FRCS4 / mass         # 210: 6.5 s of 4-jet ullage
    else:
        ull = 4.0 * FRCS2 / mass         # 099: 4 s of 2-jet ullage
    vg_corr = vg_mag - ull
    if vg_corr <= 0:
        burn = 0.0
    else:
        burn = mass * vg_corr / THRUST_10PCT
    impulse = burn < IMPULSE_S
    if profile == "J":
        nothrotl = burn < NOTHROTL_S                       # 210 also sets NOTHROTL under 6 s
    else:
        nothrotl = (burn >= IMPULSE_S) and (burn < NOTHROTL_S)   # 099 leaves it clear under 6 s
    return {"BURN_S": burn, "NOTHROTL": nothrotl, "IMPULSE": impulse}


def s40_8(vg_prev, delvref, tdecay, vex):
    """VG update and time to go (S40.8, P4:904-961)."""
    vg = sub(vg_prev, delvref)
    d_mag = mag(delvref)
    if d_mag <= 0 or dot(vg, delvref) <= 0:
        return {"VG": vg, "TGO": -1.0, "ALARM": 1407, "STEER": True, "IMPULSE": False}
    dv = dot(vg, delvref) / d_mag            # VG along the measured direction
    tgo = PASS_S * dv / d_mag * (1.0 - dv / (2.0 * vex)) + tdecay
    steer = tgo >= STEER_STOP_S
    return {"VG": vg, "TGO": tgo, "ALARM": 0, "STEER": steer, "IMPULSE": not steer}


def p41spot(tig, now):
    if tig - 29.9 < now + 20.0:
        return {"TIG": now + 49.9, "SLIPPED": True, "ALARM": 1703}
    return {"TIG": tig, "SLIPPED": False, "ALARM": 0}


def p30_apsides(r_vec, v_vec, dv_vec, mu, radius):
    v_new = add(v_vec, dv_vec)
    r = mag(r_vec)
    h = mag(cross(r_vec, v_new))
    energy = dot(v_new, v_new) / 2.0 - mu / r
    cap = CAP_NM * M_PER_NM
    if energy >= 0:
        return {"APO_M": cap, "PERI_M": min(cap, h * h / mu / (1.0 + math.sqrt(1.0 + 2.0 * energy * h * h / (mu * mu))) - radius)}
    e = math.sqrt(1.0 + 2.0 * energy * h * h / (mu * mu))
    p = h * h / mu
    apo = min(cap, p / (1.0 - e) - radius) if e < 1.0 else cap
    peri = min(cap, p / (1.0 + e) - radius)
    return {"APO_M": apo, "PERI_M": peri}


def p30_mga(ut, ref_y):
    """Middle gimbal angle (GET+MGA, P34-35_P74-75.agc:1406-1415): arcsin(UT . Y), plus one revolution if negative."""
    x = dot(unit(ut), unit(ref_y))
    x = max(-1.0, min(1.0, x))
    ang = math.degrees(math.asin(x))
    return ang + 360.0 if ang < 0 else ang


def plan_lv_components(dv, r_vec, v_vec):
    """Same as lm_plan.ks plan_lv_components with the node normal = unit(r x v) (NODE_NORMAL_SIGN +1)."""
    up = unit(r_vec)
    track = unit(sub(v_vec, scale(up, dot(v_vec, up))))
    nrm = unit(cross(r_vec, v_vec))
    return (dot(dv, track), -dot(dv, nrm), -dot(dv, up))


def plan_lv_to_dv(lv, r_vec, v_vec):
    up = unit(r_vec)
    track = unit(sub(v_vec, scale(up, dot(v_vec, up))))
    nrm = unit(cross(r_vec, v_vec))
    return sub(sub(scale(track, lv[0]), scale(nrm, lv[1])), scale(up, lv[2]))


def s40_13_aps(mass, vg_mag, profile):
    """Burn time of the ascent engine (210 P40-P47.agc 1035-1135, 099 the same but for K1 and the ullage)."""
    thrust, flow = 15569.0, 5.135
    k1 = 14012.0 if profile == "J" else 12455.0
    k2 = 3113.8
    ull = 6.5 * FRCS4 / mass if profile == "J" else 4.0 * FRCS2 / mass
    v = vg_mag - ull
    impulse = True
    if v < k1 / mass:
        burn = (mass * v / 2 + k2) / thrust
    else:
        over = v - k1 / mass
        five = 5 * thrust / (mass - 3.5 * flow)
        if over < five:
            burn = 1 + 5 * over / five
        else:
            burn = mass * v / thrust
            impulse = False
    return {"BURN_S": max(0.0, burn), "NOTHROTL": True, "IMPULSE": impulse}


def checks_aps():
    """S40.13 for the ascent engine (210 P40-P47.agc 1035-1135): the three regimes."""
    ok = True
    for mass, vg, prof in ((4700.0, 3.0, "J"), (4700.0, 12.0, "J"), (4700.0, 25.0, "J"), (4700.0, 25.0, "A11"), (4700.0, 1.0, "J")):
        b = s40_13_aps(mass, vg, prof)
        print("S40.13 APS mass", mass, "|VG|", vg, prof, "->", b)
    ok = ok and s40_13_aps(4700.0, 3.0, "J")["IMPULSE"] and s40_13_aps(4700.0, 12.0, "J")["IMPULSE"]
    ok = ok and not s40_13_aps(4700.0, 25.0, "J")["IMPULSE"] and s40_13_aps(4700.0, 1.0, "J")["BURN_S"] >= 0
    ok = ok and abs(s40_13_aps(4700.0, 25.0, "J")["BURN_S"] - 4700.0 * (25.0 - 6.5 * FRCS4 / 4700.0) / 15569.0) < 1e-9
    if not ok:
        raise SystemExit("FAIL S40.13 APS")
    print("S40.13 APS checks OK")


if __name__ == "__main__":
    # DOI case: a circular orbit 60 nmi up (the brief's "1,837,400 m" is 100 km = 54 nmi and puts perilune below the
    # surface, so the 60 nmi radius is used), retrograde 23.1 m/s (76 ft/s) along track. Position +X, velocity +Z.
    r_doi = R_MOON + 60.0 * M_PER_NM
    v_circ = math.sqrt(MU_MOON / r_doi)
    rtig = (r_doi, 0.0, 0.0)
    vtig = (0.0, 0.0, v_circ)
    dv = (0.0, 0.0, -23.1)
    s1 = s40_1(dv)
    print("DOI r =", r_doi, " v_circ =", v_circ)
    print("S40.1 UT =", s1["UT"], " VGMAG =", s1["VGMAG"])
    s23 = s40_2_3(s1["UT"], rtig, vtig)
    print("S40.2,3 X =", s23["X"], " Y =", s23["Y"], " Z =", s23["Z"])
    # RTIG almost parallel to UT (|UT x RTIG| is 1e-4 of the product of the lengths): Y falls back to unit(UT x VTIG)
    s23b = s40_2_3((1.0, 0.0, 0.0), (1.0e6, 100.0, 0.0), vtig)
    print("S40.2,3 fallback Y =", s23b["Y"], " Z =", s23b["Z"])
    for vgm, prof in ((23.0, "A11"), (29.0, "A11"), (31.0, "A11"), (2.0, "A11"), (0.0, "A11"), (2.0, "J")):
        b = s40_13(15000.0, vgm, prof)
        print("S40.13 mass 15000 |VG|", vgm, prof, "->", b)
    b = s40_13(15000.0, 23.1, "A11")
    print("burn time for the DOI delta-V (15000 kg, 23.1 m/s):", b["BURN_S"])
    # TGO for a 5 m/s residual along the measured direction, one pass measured 0.62 m/s (a = 0.31 m/s^2, 15 t at 10 percent)
    ut = (0.0, 0.0, -1.0)
    dref = scale(ut, 0.62)
    r8 = s40_8(scale(ut, 5.62), dref, TDECAY_S, DPSVEX)
    print("S40.8 VG 5 m/s:", r8)
    r8 = s40_8(scale(ut, 3.0 + 1.5), scale(ut, 1.5), TDECAY_S, DPSVEX)
    print("S40.8 VG 3 m/s, 1.5 m/s per pass (steering stops):", r8)
    r8 = s40_8(scale(ut, -5.0), scale(ut, 0.62), TDECAY_S, DPSVEX)
    print("S40.8 VG opposite the measured delta-V:", r8)
    print("P41SPOT 30 s ahead:", p41spot(1030.0, 1000.0))
    print("P41SPOT 80 s ahead:", p41spot(1080.0, 1000.0))
    print("P41SPOT in the past:", p41spot(900.0, 1000.0))
    ap = p30_apsides(rtig, vtig, dv, MU_MOON, R_MOON)
    print("apsides DOI:", ap, " apo nmi =", ap["APO_M"] / M_PER_NM, " peri nmi =", ap["PERI_M"] / M_PER_NM)
    ap2 = p30_apsides(rtig, vtig, (0.0, 0.0, 2000.0), MU_MOON, R_MOON)
    print("apsides escape (cap):", ap2, ap2["APO_M"] / M_PER_NM)
    print("MGA along Y:", p30_mga((0.0, 1.0, 0.0), (0.0, 1.0, 0.0)), " perpendicular:", p30_mga((0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
          " negative:", p30_mga((0.0, -1.0, 0.0), (0.0, 1.0, 0.0)))
    # plan_lv_to_dv round trips (the same cases test_plan.ks uses)
    rr = (1737400.0 + 15000.0, 0.0, 0.0)
    vv = (100.0, 1600.0, 0.0)
    for d in ((3.0, -2.0, 5.0), (0.0, 0.0, 7.0), (1.0, 2.0, 3.0)):
        back = plan_lv_to_dv(plan_lv_components(d, rr, vv), rr, vv)
        assert mag(sub(back, d)) < 1e-9, (d, back)
    print("plan_lv_to_dv round trips OK")
    checks_aps()
