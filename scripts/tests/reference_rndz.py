"""reference_rndz.py -- the rendezvous maths (scripts/shared/lm_conics.ks, lm_axes.ks, scripts/lm/rndz/lm_rndz.ks) in Python.

An independent model: it prints the numbers the pad tests assert, and checks itself against physics.
Exit code 1 when any check fails. Run: python scripts/tests/reference_rndz.py
Standard library only. Vectors are (x, y, z); the scenario orbits lie in the x-z plane.
"""
import math
import sys

MU = 4.9028e12               # m^3/s^2
RADIUS = 1737400.0           # m
M_PER_NM = 1852.0

FAILED = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILED.append(name)


def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def mag(a): return math.sqrt(dot(a, a))
def scale(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def unit(a): return scale(a, 1.0 / mag(a))


def fmt(a, places=3):
    return "(" + ", ".join(f"{x:.{places}f}" for x in a) + ")"


# ---- scenario ---------------------------------------------------------------

R_APO = RADIUS + 45 * M_PER_NM
R_PERI = RADIUS + 9 * M_PER_NM
RA1 = (R_APO, 0.0, 0.0)
VA1 = (0.0, 0.0, math.sqrt(MU * (2 / R_APO - 2 / (R_APO + R_PERI))))


# ---- RK4, the check on the propagator ----------------------------------------

def rk4(pos, vel, dt, steps):
    h = dt / steps

    def acc(p):
        return scale(p, -MU / mag(p) ** 3)

    for _ in range(steps):
        k1r, k1v = vel, acc(pos)
        k2r, k2v = add(vel, scale(k1v, h / 2)), acc(add(pos, scale(k1r, h / 2)))
        k3r, k3v = add(vel, scale(k2v, h / 2)), acc(add(pos, scale(k2r, h / 2)))
        k4r, k4v = add(vel, scale(k3v, h)), acc(add(pos, scale(k3r, h)))
        pos = add(pos, scale(add(add(k1r, scale(k2r, 2)), add(scale(k3r, 2), k4r)), h / 6))
        vel = add(vel, scale(add(add(k1v, scale(k2v, 2)), add(scale(k3v, 2), k4v)), h / 6))
    return pos, vel


# ---- conic propagator ---------------------------------------------------------

def stumpff(z):
    if z > 1e-6:
        root = math.sqrt(z)
        return (1 - math.cos(root)) / z, (root - math.sin(root)) / (root * z)
    if z < -1e-6:
        root = math.sqrt(-z)
        return (math.cosh(root) - 1) / -z, (math.sinh(root) - root) / (root * -z)
    return 0.5 - z / 24, 1 / 6 - z / 120


def kepler(pos0, vel0, dt, mu=MU):
    """Universal-variable propagation. Returns (pos, vel, passes) or None."""
    r0 = mag(pos0)
    if r0 <= 0:
        return None
    if dt == 0:
        return pos0, vel0, 0
    root_mu = math.sqrt(mu)
    rv_term = dot(pos0, vel0) / root_mu
    alpha = 2 / r0 - dot(vel0, vel0) / mu

    def kepler_f(chi):
        z = alpha * chi * chi
        if z < -2500:                       # overflow guard: the function is huge, with the sign of chi
            return math.copysign(1e30, chi), 0.0
        c, s = stumpff(z)
        value = rv_term * chi * chi * c + (1 - alpha * r0) * chi ** 3 * s + r0 * chi - root_mu * dt
        slope = rv_term * chi * (1 - z * s) + (1 - alpha * r0) * chi * chi * c + r0
        return value, slope

    guess = root_mu * abs(alpha * dt) if alpha > 0 else root_mu * abs(dt) / r0
    if guess < 1.0:
        guess = 1.0
    far = math.copysign(guess, dt)
    near = 0.0
    for _ in range(100):
        if kepler_f(far)[0] * dt >= 0:
            break
        near, far = far, far * 2
    else:
        return None
    low, high = min(near, far), max(near, far)
    chi = far
    passes = 0
    done = False
    while not done and passes < 80:
        passes += 1
        value, slope = kepler_f(chi)
        if value > 0:
            high = chi
        else:
            low = chi
        if slope > 0 and abs(value / slope) < 1e-6:
            chi -= value / slope
            done = True
        else:
            trial = chi - value / slope if slope > 0 else low
            if trial <= low or trial >= high:
                trial = (low + high) / 2
            done = abs(trial - chi) < 1e-6
            chi = trial
    if not done:
        return None
    z = alpha * chi * chi
    c, s = stumpff(z)
    pos = add(scale(pos0, 1 - chi * chi / r0 * c), scale(vel0, dt - chi ** 3 * s / root_mu))
    r1 = mag(pos)
    if r1 <= 0:
        return None
    vel = add(scale(pos0, root_mu / (r1 * r0) * chi * (z * s - 1)), scale(vel0, 1 - chi * chi / r1 * c))
    return pos, vel, passes


def elements(pos, vel, mu=MU):
    r = mag(pos)
    h = cross(pos, vel)
    p = dot(h, h) / mu
    ec = p / r - 1
    rdot = dot(pos, vel) / r
    es = rdot * math.sqrt(p / mu)
    return {"P": p, "EC": ec, "ES": es, "ECC": math.hypot(ec, es), "ALPHA": 2 / r - dot(vel, vel) / mu, "RDOT": rdot}


def time_from_periapsis(ecc, f, a, mu=MU):
    """Seconds from periapsis to true anomaly f (rad), negative for negative f."""
    big_e = math.atan2(math.sqrt(max(0.0, 1 - ecc * ecc)) * math.sin(f), ecc + math.cos(f))
    return (big_e - ecc * math.sin(big_e)) * math.sqrt(a ** 3 / mu)


def time_to_apo(pos, vel, mu=MU):
    el = elements(pos, vel, mu)
    if el["ALPHA"] <= 0:
        return -1.0
    a = 1 / el["ALPHA"]
    half = math.pi * math.sqrt(a ** 3 / mu)
    if el["ECC"] < 0.0001:
        return half
    left = half - time_from_periapsis(el["ECC"], math.atan2(el["ES"], el["EC"]), a, mu)
    return left if left > 0 else left + 2 * half


# ---- Task 1 checks ------------------------------------------------------------

def checks_conics():
    fast = scale(VA1, 1.6)
    cases = [("ellipse", VA1, 600), ("ellipse", VA1, 7200), ("ellipse", VA1, -3000),
             ("hyperbola", fast, 900), ("hyperbola", fast, -900)]
    for label, vel, dt in cases:
        out = kepler(RA1, vel, dt)
        ref = rk4(RA1, vel, dt, 4000)
        err = mag(sub(out[0], ref[0])) if out else float("inf")
        check(f"{label} dt {dt}: within 0.1 m of RK4 (error {err:.5f}, passes {out[2] if out else -1})", err < 0.1)

    r_1000, v_1000, _ = kepler(RA1, VA1, 1000)
    check("dt 1000 position is the plan's number",
          mag(sub(r_1000, (1127742.019, 0.0, 1412938.022))) < 0.5)
    check("dt 1000 velocity is the plan's number", mag(sub(v_1000, (-1294.6588, 0.0, 1002.4428))) < 0.001)
    back = kepler(r_1000, v_1000, -1000)[0]
    check("there and back returns RA1 within 0.01 m", mag(sub(back, RA1)) < 0.01)
    period = 2 * math.pi * math.sqrt((1 / elements(RA1, VA1)["ALPHA"]) ** 3 / MU)
    full = kepler(RA1, VA1, period)[0]
    check("a full period returns the start within 0.1 m", mag(sub(full, RA1)) < 0.1)
    check("dt 0 unchanged", kepler(RA1, VA1, 0)[:2] == (RA1, VA1))
    check("zero position fails", kepler((0.0, 0.0, 0.0), VA1, 100) is None)

    for dt, want in ((600, 6180.97), (-600, 600.0)):
        pos, vel, _ = kepler(RA1, VA1, dt)
        got = time_to_apo(pos, vel)
        check(f"time to apolune from {dt:+d} s is {want} (got {got:.3f})", abs(got - want) < 0.1)

    print("--- pad numbers (test_conics.ks)")
    print(f"s = {VA1[2]:.9f}   period = {period:.4f}")
    print(f"dt 1000: R = {fmt(r_1000)}  V = {fmt(v_1000, 4)}")
    r_hyp, v_hyp, _ = kepler(RA1, fast, 900)
    print(f"hyperbola dt 900: R = {fmt(r_hyp)}  V = {fmt(v_hyp, 4)}")


# ---- CSI and CDH (Task 5; Luminary 210 CSI/A and CDHMVR, written from the plan's text) ---------

CSI_FIRST_STEP = 3.048       # m/s
CSI_STEP_LIMIT = 60.96
CSI_CONVERGED = 0.03048
CSI_DV_LIMIT = 304.8
CSI_CLAMP = 301.4472
CSI_JUMP = 15.24
CSI_MAX_COUNT = 16
CSI_MIN_PERILUNE = 10668.0   # m above the mean radius
CSI_MIN_GAP = 600.0          # s
APSIS_RDOT = 2.1336          # m/s (7 ft/s)


def sign(x): return -1.0 if x < 0 else 1.0


def vang(a, b): return math.degrees(math.atan2(mag(cross(a, b)), dot(a, b)))


def fwd(nrm, pos): return unit(cross(nrm, pos))


def into_plane(vec, nrm):
    flat = sub(vec, scale(nrm, dot(vec, nrm)))
    return scale(unit(flat), mag(vec))


def target_at(rt, vt, dir_unit, nrm, mu=MU):
    """The target's state where its radius vector lies along dir_unit."""
    el = elements(rt, vt, mu)
    theta = math.atan2(dot(dir_unit, fwd(nrm, rt)), dot(dir_unit, unit(rt)))
    ec = el["EC"] * math.cos(theta) - el["ES"] * math.sin(theta)
    es = el["ES"] * math.cos(theta) + el["EC"] * math.sin(theta)
    speed = math.sqrt(mu / el["P"])
    pos = scale(dir_unit, el["P"] / (1 + ec))
    vel = add(scale(dir_unit, speed * es), scale(fwd(nrm, dir_unit), speed * (1 + ec)))
    return pos, vel


def apsis_time(pos, vel, nn, force_half=False, mu=MU):
    el = elements(pos, vel, mu)
    a = 1 / el["ALPHA"]
    half = math.pi * math.sqrt(a ** 3 / mu)
    if force_half or el["ECC"] < 0.0001 or abs(el["RDOT"]) < APSIS_RDOT:
        return nn * half
    tp = time_from_periapsis(el["ECC"], math.atan2(abs(el["ES"]), el["EC"]), a, mu)
    return nn * half - (tp if el["RDOT"] >= 0 else half - tp)


def cdh(ra, va, rt, vt, nrm, mu=MU):
    up = unit(ra)
    t_r, t_v = target_at(rt, vt, up, nrm, mu)
    dh = mag(t_r) - mag(ra)
    ap = mag(t_r) / (2 - mag(t_r) * dot(t_v, t_v) / mu)
    aa = ap - dh
    if ap <= 0 or aa <= 0:
        return None
    vr = dot(t_v, up) * (ap / aa) ** 1.5
    vh2 = mu * (2 / mag(ra) - 1 / aa) - vr * vr
    if vh2 < 0:
        return None
    v3 = add(scale(fwd(nrm, ra), math.sqrt(vh2)), scale(up, vr))
    return {"V3": v3, "DV": sub(v3, va), "DH": dh}


class CsiFail(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def perilune(pos, vel, mu):
    el = elements(pos, vel, mu)
    return el["P"] / (1 + el["ECC"])


def csi_trial(inp, base, dv):
    """One trial CSI delta-V: the whole chain CSI -> CDH -> TPI and the error angle g (deg).
    Returns None when the elevation line misses the target's radius (negative discriminant)."""
    mu, nrm = inp["MU"], base["nrm"]
    v4 = add(inp["V1"], scale(base["uh"], dv))
    if elements(inp["R1"], v4, mu)["ALPHA"] <= 0:
        raise CsiFail(606)
    tcdh = inp["TCSI"] + apsis_time(inp["R1"], v4, inp["NN"], inp["FORCE_HALF"], mu)
    if tcdh > inp["TTPI"]:
        raise CsiFail(604)
    lm2 = kepler(inp["R1"], v4, tcdh - inp["TCSI"], mu)
    tg2 = kepler(inp["RT"], inp["VT"], tcdh - inp["TCSI"], mu)
    if lm2 is None or tg2 is None:
        raise CsiFail(605)
    man = cdh(lm2[0], lm2[1], tg2[0], tg2[1], nrm, mu)
    if man is None:
        raise CsiFail(605)
    lm3 = kepler(lm2[0], man["V3"], inp["TTPI"] - tcdh, mu)
    if lm3 is None:
        raise CsiFail(605)
    ra3, rt3, vt3 = lm3[0], base["rt3"], base["vt3"]
    elev = math.radians(inp["ELEV"])
    u = add(scale(fwd(nrm, ra3), math.cos(elev)), scale(unit(ra3), math.sin(elev)))
    t1 = dot(u, ra3)
    disc = t1 * t1 - dot(ra3, ra3) + dot(rt3, rt3)
    if disc < 0:
        return None
    k = min((-t1 + math.sqrt(disc), -t1 - math.sqrt(disc)), key=abs)
    vp = unit(add(ra3, scale(u, k)))
    g = sign(dot(cross(unit(rt3), vp), cross(unit(vt3), unit(rt3)))) * vang(vp, rt3)
    return {"g": g, "v4": v4, "TCDH": tcdh, "R2": lm2[0], "CDH": man, "R3": ra3, "V3T": lm3[1]}


def csi_checks(inp, trial):
    if perilune(inp["R1"], trial["v4"], inp["MU"]) - inp["RADIUS"] < CSI_MIN_PERILUNE:
        raise CsiFail(601)
    if perilune(trial["R2"], trial["CDH"]["V3"], inp["MU"]) - inp["RADIUS"] < CSI_MIN_PERILUNE:
        raise CsiFail(602)
    if trial["TCDH"] - inp["TCSI"] < CSI_MIN_GAP:
        raise CsiFail(603)
    if inp["TTPI"] - trial["TCDH"] < CSI_MIN_GAP:
        raise CsiFail(604)


def csi(inp):
    mu = inp["MU"]
    nrm = unit(cross(inp["RT"], inp["VT"]))
    tg3 = kepler(inp["RT"], inp["VT"], inp["TTPI"] - inp["TCSI"], mu)
    if tg3 is None:
        return {"OK": False, "ALARM": 605, "COUNT": 0}
    base = {"nrm": nrm, "uh": fwd(nrm, inp["R1"]), "rt3": tg3[0], "vt3": tg3[1]}
    r1, rt3 = mag(inp["R1"]), mag(tg3[0])
    hohmann = math.sqrt(2 * mu / (r1 * (1 + r1 / rt3))) - dot(inp["V1"], base["uh"])
    phase, saved = "01", 0
    while True:                                          # one pass of this loop per cycle (two at most)
        dv, inc, count, exceeded, first = hohmann, CSI_FIRST_STEP, 0, False, True
        gprev = dvprev = 0.0
        counted = True
        try:
            while True:
                if counted:
                    count += 1
                    if count >= CSI_MAX_COUNT:
                        raise CsiFail(605)
                counted = True
                if abs(dv) >= CSI_DV_LIMIT:
                    if exceeded or phase == "11":
                        raise CsiFail(606)
                    exceeded = True
                    dv = sign(dv) * CSI_CLAMP
                trial = csi_trial(inp, base, dv)
                if trial is None:
                    if count == 1:
                        return {"OK": False, "ALARM": 600, "COUNT": count}
                    inc /= 2
                    dv = dvprev - inc
                    continue
                g = trial["g"]
                if first:
                    gprev, dvprev, first = g, dv, False
                    dv -= inc
                    continue
                if dv == dvprev:
                    raise CsiFail(605)
                slope = (g - gprev) / (dv - dvprev)
                dvprev = dv
                if phase == "11" and (g - gprev) * gprev < 0:
                    inc = sign(inc) * CSI_FIRST_STEP
                    phase, gprev = "10", g
                    dv -= inc
                    continue
                if phase in ("11", "00"):
                    inc = -CSI_JUMP * sign(slope) * sign(gprev)
                    dv -= inc
                    gprev, phase, counted = g, "11", False
                    continue
                if slope == 0:
                    raise CsiFail(605)
                inc = g / slope
                gprev = g
                if abs(inc) < CSI_CONVERGED:
                    csi_checks(inp, trial)
                    return {"OK": True, "ALARM": 0, "COUNT": count, "DV": dv, "DV1": sub(trial["v4"], inp["V1"]),
                            "TCDH": trial["TCDH"], "DH": trial["CDH"]["DH"], "R2": trial["R2"],
                            "DV2": trial["CDH"]["DV"], "R3": trial["R3"], "V3T": trial["V3T"],
                            "RT3": base["rt3"], "VT3": base["vt3"], "NORMAL": nrm}
                if abs(inc) >= CSI_STEP_LIMIT:
                    inc = sign(inc) * CSI_STEP_LIMIT
                dv -= inc
        except CsiFail as fail:
            if phase == "01":
                saved, phase = fail.code, "00"
                continue
            return {"OK": False, "ALARM": saved, "COUNT": count}


def csm_state(radius, speed, angle_deg=8.4):
    a = math.radians(angle_deg)
    return (radius * math.cos(a), 0.0, radius * math.sin(a)), (-speed * math.sin(a), 0.0, speed * math.cos(a))


def circular_csm(radius=1848520.0, angle_deg=8.4):
    return csm_state(radius, math.sqrt(MU / radius), angle_deg)


def eccentric_csm():
    rp, ra = RADIUS + 58 * M_PER_NM, RADIUS + 64 * M_PER_NM
    return csm_state(rp, math.sqrt(MU * (2 / rp - 2 / (rp + ra))))


def csi_input(csm, **change):
    inp = {"R1": RA1, "V1": VA1, "RT": csm[0], "VT": csm[1], "TCSI": 0.0, "TTPI": 5800.0, "NN": 1, "ELEV": 26.6,
           "FORCE_HALF": False, "MU": MU, "RADIUS": RADIUS}
    inp.update(change)
    return inp


def elevation(ra, va, rt):
    """Angle of the line to the target from the forward horizontal towards up, degrees in [0, 360)."""
    if rt == ra:
        return 0.0                  # no line of sight (kOS: ARCTAN2(0, 0) = 0)
    los, up = unit(sub(rt, ra)), unit(ra)
    ahead = unit(sub(va, scale(up, dot(va, up))))
    return math.degrees(math.atan2(dot(los, up), dot(los, ahead))) % 360


def fly(inp, out):
    """Apply the two burns of a solution: the LM state just after CDH and the CSM state at the same time."""
    lm2 = kepler(inp["R1"], add(inp["V1"], out["DV1"]), out["TCDH"] - inp["TCSI"])
    tg2 = kepler(inp["RT"], inp["VT"], out["TCDH"] - inp["TCSI"])
    return (lm2[0], add(lm2[1], out["DV2"])), (tg2[0], tg2[1])


def checks_csi():
    circ, ecc = circular_csm(), eccentric_csm()
    early_lm, early_tg = kepler(RA1, VA1, -600), kepler(circ[0], circ[1], -600)
    rows = [("circular", csi_input(circ), 15.37881, 3485.806, 27760.41, (0.0044, 0.0, 0.0)),
            ("eccentric", csi_input(ecc), 16.67926, 3494.113, 29325.25, (-1.1705, 0.0, -0.7313)),
            ("circular from -600 s, NN 2",
             csi_input(early_tg[:2], R1=early_lm[0], V1=early_lm[1], TCSI=-600.0, NN=2),
             16.42746, 5088.81, 44291.07, (-8.5441, 0.0, 0.0))]
    for label, inp, want_dv, want_t, want_dh, want_lv in rows:
        out = csi(inp)
        if not out["OK"]:
            check(f"CSI {label}: solved (alarm {out['ALARM']}, count {out['COUNT']})", False)
            continue
        up = unit(out["R2"])
        lv = (dot(out["DV2"], fwd(out["NORMAL"], out["R2"])), -dot(out["DV2"], out["NORMAL"]), -dot(out["DV2"], up))
        print(f"--- CSI {label}: DV {out['DV']:.5f}  TCDH {out['TCDH']:.3f}  DH {out['DH']:.2f}  "
              f"CDH LV {fmt(lv, 4)}  count {out['COUNT']}")
        check(f"CSI {label}: DV", abs(out["DV"] - want_dv) < 0.001)
        check(f"CSI {label}: TCDH", abs(out["TCDH"] - want_t) < 0.05)
        check(f"CSI {label}: DH", abs(out["DH"] - want_dh) < 1.0)
        check(f"CSI {label}: CDH LV", all(abs(a - b) < 0.001 for a, b in zip(lv, want_lv)))
        if label == "circular":
            check("CSI circular: three passes", out["COUNT"] == 3)

        # physics: fly the two burns and look at what comes out
        if inp["TCSI"] == 0:
            lm, tg = fly(inp, out)
            at_tpi = inp["TTPI"] - out["TCDH"]
            lm3, tg3 = kepler(lm[0], lm[1], at_tpi), kepler(tg[0], tg[1], at_tpi)
            got = elevation(lm3[0], lm3[1], tg3[0])
            check(f"CSI {label}: flown elevation at TPI {got:.3f} within 0.5 of 26.6", abs(got - 26.6) < 0.5)
            if label == "circular":
                lm4, tg4 = kepler(lm[0], lm[1], 600), kepler(tg[0], tg[1], 600)
                height = mag(tg4[0]) - mag(lm4[0])
                check(f"CSI circular: height difference 600 s after CDH {height:.1f} within 100 m of DH",
                      abs(height - out["DH"]) < 100)

    for label, inp, want in [("TPI at 1800 s", csi_input(circ, TTPI=1800.0), 604),
                             ("CSM 60 deg ahead", csi_input(circular_csm(angle_deg=60)), 601),
                             ("low CSM, elevation 0", csi_input(circular_csm(RADIUS + 18520.0), ELEV=0), 600)]:
        out = csi(inp)
        check(f"CSI alarm, {label}: {want} (got {out['ALARM']})", out["ALARM"] == want)

    same = csm_state(R_APO, math.sqrt(MU / R_APO))
    odd = [("NN 0", csi_input(circ, NN=0)), ("NN 99", csi_input(circ, NN=99)), ("ELEV 0", csi_input(circ, ELEV=0)),
           ("ELEV 90", csi_input(circ, ELEV=90)), ("ELEV 180", csi_input(circ, ELEV=180)),
           ("ELEV 270", csi_input(circ, ELEV=270)), ("TTPI -100", csi_input(circ, TTPI=-100.0)),
           ("same circular orbit", csi_input(same, V1=(0.0, 0.0, math.sqrt(MU / R_APO))))]
    for label, inp in odd:
        out = csi(inp)
        check(f"CSI odd input, {label}: OK or 600-606 (ok {out['OK']}, alarm {out['ALARM']})",
              out["OK"] or 600 <= out["ALARM"] <= 606)

    print("--- pad numbers (test_rndz.ks)")
    print(f"eccentric CSM: R = {fmt(ecc[0])}  V = {fmt(ecc[1], 6)}")
    for dt in (600, -600):
        pos, vel, _ = kepler(RA1, VA1, dt)
        print(f"apsis time from {dt:+d} s: {apsis_time(pos, vel, 1):.3f}   NN 2: {apsis_time(pos, vel, 2):.3f}")


# ---- TPI time for an elevation angle (Task 6; Luminary 210 S33/34.1, written from the plan's text) ----

def tpi_time(ra, va, rt, vt, elev, mu=MU):
    """The change to the nominal TPI time that gives the elevation angle elev (deg). States are at the nominal time."""
    secmax, nom, prev, del_old = 250.0, 0.0, 0.0, 0.0
    now = (ra, va, rt, vt)
    for n in range(1, 16):
        ra_n, va_n, rt_n, vt_n = now
        ea = elevation(ra_n, va_n, rt_n)
        err = ea - elev                                           # no wrap

        def result(ok, why):
            return {"OK": ok, "WHY": why, "DT": nom, "EA": ea, "PASSES": n,
                    "RA": ra_n, "VA": va_n, "RT": rt_n, "VT": vt_n}

        if abs(err) < 0.1:
            return result(True, "")
        r_a, r_t = mag(ra_n), mag(rt_n)
        higher = sign(r_t - r_a)
        if higher * (180 - elev) < 0:
            return result(False, "geometry")
        cos_x = math.cos(math.radians(elev)) * r_a / r_t
        if abs(cos_x) > 1:
            return result(False, "geometry")
        up_a, up_t = unit(ra_n), unit(rt_n)
        rate = (mag(sub(va_n, scale(up_a, dot(va_n, up_a)))) / r_a
                - mag(sub(vt_n, scale(up_t, dot(vt_n, up_t)))) / r_t)
        if abs(rate) < 1e-9:
            return result(False, "rate")
        alpha = sign(dot(cross(ra_n, rt_n), cross(ra_n, va_n))) * math.radians(vang(ra_n, rt_n))
        theta = math.pi - math.radians(elev) - higher * (math.pi - math.acos(cos_x))
        dt = max(-secmax, min(secmax, (alpha - theta) / rate))
        if n == 1:
            inc = prev = dt
        elif err * del_old < 0:
            secmax /= 3                                           # dt was limited with the old secmax
            inc = prev = -sign(prev) * abs(dt) / 2
        elif abs(del_old) < abs(err):
            inc, prev = -1.5 * prev, -prev / 2
        else:
            inc = prev = abs(dt) * sign(prev)
        del_old = err
        nom += inc
        lm, tg = kepler(ra, va, nom, mu), kepler(rt, vt, nom, mu)
        if lm is None or tg is None:
            return result(False, "conic")
        now = (lm[0], lm[1], tg[0], tg[1])
    return {"OK": False, "WHY": "passes", "DT": nom, "EA": elevation(now[0], now[1], now[2]), "PASSES": 15,
            "RA": now[0], "VA": now[1], "RT": now[2], "VT": now[3]}


def checks_tpi():
    circ = circular_csm()
    out = csi(csi_input(circ))
    at_tpi = (out["R3"], out["V3T"], out["RT3"], out["VT3"])
    print("--- pad numbers (test_rndz.ks, TPI time)")
    for offset, want_dt, want_ea in ((0, 6.381, None), (240, -233.619, 31.082), (-600, 606.381, 18.883)):
        lm = kepler(at_tpi[0], at_tpi[1], offset) if offset else (at_tpi[0], at_tpi[1], 0)
        tg = kepler(at_tpi[2], at_tpi[3], offset) if offset else (at_tpi[2], at_tpi[3], 0)
        ea = elevation(lm[0], lm[1], tg[0])
        found = tpi_time(lm[0], lm[1], tg[0], tg[1], 26.6)
        total = 5800 + offset + found["DT"]
        print(f"offset {offset:+d}: elevation {ea:.3f}  DT {found['DT']:.3f}  TPI {total:.3f}  "
              f"found {found['EA']:.3f}  passes {found['PASSES']}  {found['WHY']}")
        check(f"TPI offset {offset:+d}: solved", found["OK"])
        check(f"TPI offset {offset:+d}: DT {want_dt}", abs(found["DT"] - want_dt) < 0.05)
        check(f"TPI offset {offset:+d}: time 5806.381", abs(total - 5806.381) < 0.05)
        check(f"TPI offset {offset:+d}: elevation within 0.1",
              abs(elevation(found["RA"], found["VA"], found["RT"]) - 26.6) < 0.1)
        if want_ea is not None:
            check(f"TPI offset {offset:+d}: starting elevation {want_ea}", abs(ea - want_ea) < 0.001)

    low = circular_csm(R_APO, 0.0)
    high = circular_csm(R_APO + 20000, 8.4)
    found = tpi_time(low[0], low[1], high[0], high[1], 200)
    check(f"TPI elevation 200, CSM higher: geometry (got {found['WHY']})",
          not found["OK"] and found["WHY"] == "geometry")
    near = circular_csm(R_APO + 100, 8.4)
    found = tpi_time(low[0], low[1], near[0], near[1], 5)
    print(f"CSM 100 m higher, elevation 5: ok {found['OK']}  why {found['WHY']}  passes {found['PASSES']}")
    for label, other in (("same state", low), ("same circle, 8.4 deg apart", circular_csm(R_APO, 8.4))):
        found = tpi_time(low[0], low[1], other[0], other[1], 26.6)
        check(f"TPI identical orbits, {label}: fails ({found['WHY']})", not found["OK"])


# ---- Lambert (Task 2; our own universal-variable solver, one revolution) -------

LAMBERT_MAX_MISS = 100.0     # m; a solution that flies further from the aim point is refused


def lambert(pos1, pos2, tof, mu, vref, cone):
    """The orbit from pos1 to pos2 in tof seconds. vref fixes the direction of travel; within cone degrees of
    180 the target is first turned into the plane of pos1 and vref (INITVEL's E4)."""
    zero = (0.0, 0.0, 0.0)
    out = {"OK": False, "WHY": "", "V1": zero, "V2": zero, "AIM": pos2, "ROTATED": False, "ANGLE": 0.0}

    def fail(why):
        out["WHY"] = why
        return out

    r1 = mag(pos1)
    if r1 <= 0 or mag(pos2) <= 0 or mu <= 0:
        return fail("input")
    if tof <= 0:
        return fail("time")
    u1 = scale(pos1, 1 / r1)
    side_v = sub(vref, scale(u1, dot(vref, u1)))
    if mag(side_v) < 1e-6:
        return fail("direction")                # vref radial or zero: no direction of travel
    ahead = unit(side_v)
    ang = vang(pos1, pos2)
    if abs(180 - ang) < cone:
        nrm = unit(cross(u1, ahead))
        flat = sub(pos2, scale(nrm, dot(pos2, nrm)))
        if mag(flat) < 1e-6:
            return fail("geometry")
        aim = scale(unit(flat), mag(pos2))
        out["AIM"], out["ROTATED"] = aim, True
        theta = math.degrees(math.atan2(dot(aim, ahead), dot(aim, u1))) % 360
        tdir = ahead
    else:
        u2 = unit(pos2)
        side = sub(u2, scale(u1, dot(u2, u1)))
        if mag(side) < 1e-6:
            return fail("geometry")             # in line with the start: no transfer plane
        sgn = 1 if dot(side, ahead) >= 0 else -1
        theta = ang if sgn > 0 else 360 - ang
        tdir = scale(unit(side), sgn)
        aim = pos2
    out["ANGLE"] = theta
    cos_t, sin_t = math.cos(math.radians(theta)), math.sin(math.radians(theta))
    if 1 - cos_t < 1e-8:
        return fail("geometry")
    r2 = mag(aim)
    big_a = sin_t * math.sqrt(r1 * r2 / (1 - cos_t))
    time_term = math.sqrt(mu) * tof

    def curve(z):
        """(F, y, C, S) at z. y < 0 counts as F < 0."""
        c, s = stumpff(z)
        if c <= 0:
            return 1e30, 0.0, c, s
        y = r1 + r2 + big_a * (z * s - 1) / math.sqrt(c)
        if y < 0:
            return -1e30, y, c, s
        return (y / c) ** 1.5 * s + big_a * math.sqrt(y) - time_term, y, c, s

    high = 4 * math.pi ** 2 - 0.0001
    low = -4 * math.pi ** 2
    while curve(low)[0] > 0 and low > -2500:
        low = max(low * 2, -2500)
    if curve(low)[0] > 0 or curve(high)[0] < 0:
        return fail("bracket")                  # the time is outside what one revolution can do
    for _ in range(100):
        mid = (low + high) / 2
        if curve(mid)[0] < 0:
            low = mid
        else:
            high = mid
        if high - low < 1e-11:
            break
    z = (low + high) / 2
    _, y, c, s = curve(z)
    if y <= 0:
        return fail("bracket")
    chi = math.sqrt(y / c)
    alpha = z / chi ** 2
    rv = math.sqrt(mu) * (time_term - (1 - alpha * r1) * chi ** 3 * s - r1 * chi) / (chi ** 2 * c)
    semi = r1 * r2 * (1 - cos_t) / y
    v1 = add(scale(u1, rv / r1), scale(tdir, math.sqrt(mu * semi) / r1))
    flown = kepler(pos1, v1, tof, mu)
    if flown is None:
        return fail("conic")
    if mag(sub(flown[0], aim)) > LAMBERT_MAX_MISS:
        return fail("miss")                     # the numbers ran out (absurdly long or short times)
    out["OK"], out["V1"], out["V2"] = True, v1, flown[1]
    return out


# ---- Lambert (Task 2) ---------------------------------------------------------

def lambert_target(theta_deg, radius=1848520.0):
    a = math.radians(theta_deg)
    return (radius * math.cos(a), 0.0, radius * math.sin(a))


def checks_lambert():
    moved = add(lambert_target(179), (0.0, 20000.0, 0.0))
    rows = [("130 deg", lambert_target(130), 2400, (-87.4407, 0.0, 1669.2219), False),
            ("180 deg", lambert_target(180), 3500, (-9.4378, 0.0, 1647.1607), True),
            ("250 deg", lambert_target(250), 5000, (8.4121, 0.0, 1653.2075), False),
            ("40 deg, hyperbola", lambert_target(40), 400, (-713.7277, 0.0, 3041.6300), False),
            ("179 deg, 20 km out of plane", moved, 3500, (-2.2161, 0.0, 1647.1948), True)]
    print("--- pad numbers (test_conics.ks, Lambert)")
    for label, target, tof, want_v1, want_rot in rows:
        out = lambert(RA1, target, tof, MU, VA1, 15)
        if not out["OK"]:
            check(f"Lambert {label}: solved ({out['WHY']})", False)
            continue
        print(f"{label}: V1 {fmt(out['V1'], 4)}  V2 {fmt(out['V2'], 4)}  angle {out['ANGLE']:.4f}  "
              f"AIM {fmt(out['AIM'])}")
        check(f"Lambert {label}: V1 is the plan's number", mag(sub(out["V1"], want_v1)) < 0.001)
        check(f"Lambert {label}: ROTATED {want_rot}", out["ROTATED"] == want_rot)
        miss = mag(sub(kepler(RA1, out["V1"], tof)[0], out["AIM"]))
        check(f"Lambert {label}: V1 flies to AIM within 0.01 m (miss {miss:.5f})", miss < 0.01)
        if label.startswith("179"):
            check("Lambert out of plane: AIM is in the plane", abs(out["AIM"][1]) < 0.01)
            check("Lambert out of plane: AIM keeps the target radius", abs(mag(out["AIM"]) - mag(target)) < 0.01)
        else:
            want_angle = float(label.split()[0])
            check(f"Lambert {label}: transfer angle", abs(out["ANGLE"] - want_angle) < 1e-6)

    good = lambert_target(130)
    for label, args in [("theta 0", (RA1, lambert_target(0), 2400, MU, VA1, 15)),
                        ("tof 0", (RA1, good, 0, MU, VA1, 15)),
                        ("tof negative", (RA1, good, -100, MU, VA1, 15)),
                        ("radial vref", (RA1, lambert_target(180), 3500, MU, (100.0, 0.0, 0.0), 15)),
                        ("zero start", ((0.0, 0.0, 0.0), good, 2400, MU, VA1, 15)),
                        ("zero target", (RA1, (0.0, 0.0, 0.0), 2400, MU, VA1, 15)),
                        ("180 deg, cone 0", (RA1, (-1848520.0, 0.0, 0.0), 3500, MU, VA1, 0)),
                        ("far too short a time", (RA1, good, 1e-9, MU, VA1, 15))]:
        out = lambert(*args)
        check(f"Lambert {label}: fails with a reason ({out['WHY']})", not out["OK"] and out["WHY"] != "")

    # absurd times lose the numbers: the answer must be good or refused, never wrong and marked OK
    for theta in (1, 130, 250, 350):
        for tof in (1e-3, 1, 30, 1e5, 1e7, 1e9, 1e14):
            out = lambert(RA1, lambert_target(theta), tof, MU, VA1, 15)
            flown = kepler(RA1, out["V1"], tof) if out["OK"] else None
            miss = mag(sub(flown[0], out["AIM"])) if flown else 0.0
            if out["OK"] and not miss <= LAMBERT_MAX_MISS:
                check(f"Lambert extreme, {theta} deg, {tof:g} s: refused or on target (miss {miss:.4g} m)", False)
    out = lambert(RA1, good, 1e7, MU, VA1, 15)
    check(f"Lambert 1e7 s: refused (ok {out['OK']}, {out['WHY']})", not out["OK"] and out["WHY"] == "miss")

    # a sweep: every solved case must fly to its aim point
    worst, unsolved = 0.0, []
    for theta in (1, 10, 90, 165, 179.999, 181, 195, 270, 350):
        for tof in (200, 1000, 3500, 7000, 20000):
            out = lambert(RA1, lambert_target(theta), tof, MU, VA1, 15)
            if not out["OK"]:
                unsolved.append((theta, tof, out["WHY"]))
                continue
            flown = kepler(RA1, out["V1"], tof)
            worst = max(worst, mag(sub(flown[0], out["AIM"])) if flown else float("inf"))
    print(f"sweep unsolved: {unsolved}")
    check(f"Lambert sweep: every solution flies to its aim point (worst miss {worst:.4f} m)", worst < 1.0)


# ---- measured axes (Task 3; shared/lm_axes.ks) --------------------------------
# The truth is independent of the method: turn both fixed directions and a vector by one rotation (Rodrigues);
# carrying the vector from the old pair of directions to the new must land on the turned vector.

def rotate(vec, axis, angle_deg):
    k = unit(axis)
    c, s = math.cos(math.radians(angle_deg)), math.sin(math.radians(angle_deg))
    return add(add(scale(vec, c), scale(cross(k, vec), s)), scale(k, dot(k, vec) * (1 - c)))


def axes_carry(vec, mark_from, mark_to):
    """A mark is (P, N). The vector's components along (P, N x P, N) of one mark, rebuilt along the other's."""
    (p0, n0), (p1, n1) = mark_from, mark_to
    return add(add(scale(p1, dot(vec, p0)), scale(cross(n1, p1), dot(vec, cross(n0, p0)))), scale(n1, dot(vec, n0)))


def checks_axes():
    mark_a = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0))                      # (P, N)
    vec = (1200000.0, -340000.0, 910000.0)
    for axis, angle in (((0, 1, 0), 0.5487), ((1, 2, 2), 30.0), ((-3, 1, 2), 170.0)):
        mark_b = (rotate(mark_a[0], axis, angle), rotate(mark_a[1], axis, angle))
        truth = rotate(vec, axis, angle)
        miss = mag(sub(axes_carry(vec, mark_a, mark_b), truth))
        check(f"axes: {angle} deg about {axis}: the carried vector is the turned vector", miss < 1e-6)
        back = mag(sub(axes_carry(truth, mark_b, mark_a), vec))
        check(f"axes: {angle} deg about {axis}: and back", back < 1e-6)
        if angle == 30.0:
            print(f"axes pad numbers: P {fmt(mark_b[0], 12)}  N {fmt(mark_b[1], 12)}")
            print(f"axes pad numbers: {fmt(vec, 0)} carries to {fmt(truth, 4)}")


def checks_p33():
    """test_p32.ks, P33: from the post-CSI orbit at the CSI time, CDH at 3485.806 s, TPI searched from 5800 s."""
    circ = circular_csm()
    tcdh = 3485.806
    lm = kepler(RA1, add(VA1, (0.0, 0.0, 15.37881)), tcdh)
    tg = kepler(circ[0], circ[1], tcdh)
    nrm = unit(cross(tg[0], tg[1]))
    man = cdh(lm[0], lm[1], tg[0], tg[1], nrm)
    along, down = dot(man["DV"], fwd(nrm, lm[0])), -dot(man["DV"], unit(lm[0]))
    after = kepler(lm[0], man["V3"], 5800 - tcdh)
    target = kepler(circ[0], circ[1], 5800)
    found = tpi_time(after[0], after[1], target[0], target[1], 26.6)
    print(f"--- P33: DH {man['DH']:.2f}  CDH LV along {along:.4f} down {down:.4f}  DT {found['DT']:.3f}")
    check("P33: DH", abs(man["DH"] - 27760.41) < 1.0)
    check("P33: CDH LV", abs(along - 0.0044) < 0.001 and abs(down) < 0.001)
    check("P33: TPI time 6806.381 on the pad clock", found["OK"] and abs(found["DT"] - 6.381) < 0.05)


# ---- transfer (stage 2: P34, P35 and the aim point of the burns) ----------------

def time_theta(pos, vel, angle_deg, mu=MU):
    """Seconds to sweep angle_deg (0 to under 360) of true anomaly; -1 when the orbit is not an ellipse."""
    el = elements(pos, vel, mu)
    if el["ALPHA"] <= 0:
        return -1
    a = 1 / el["ALPHA"]
    start = math.atan2(el["ES"], el["EC"])
    gap = (time_from_periapsis(el["ECC"], start + math.radians(angle_deg), a, mu)
           - time_from_periapsis(el["ECC"], start, a, mu))
    period = 2 * math.pi * math.sqrt(a ** 3 / mu)
    if gap < -1e-6:
        gap += period
    return max(0.0, gap)


def central_angle(pos_a, vel_a, pos_aim):
    nrm = unit(cross(pos_a, vel_a))
    return math.degrees(math.atan2(dot(cross(pos_a, pos_aim), nrm), dot(pos_a, pos_aim))) % 360


def los_dv(dv, pos_a, vel_a, pos_p):
    """N59: along the line of sight, right, down."""
    los = unit(sub(pos_p, pos_a))
    down = unit(cross(unit(cross(pos_a, vel_a)), los))
    right = cross(down, los)
    return (dot(dv, los), dot(dv, right), dot(dv, down))


def transfer(ra, va, rt, vt, tof, mu=MU):
    failed = {"OK": False}
    if tof <= 0:
        return failed
    there = kepler(rt, vt, tof, mu)
    if not there:
        return failed
    lam = lambert(ra, there[0], tof, mu, va, 15.0)
    if not lam["OK"]:
        return failed
    return {"OK": True, "DV": sub(lam["V1"], va), "V1": lam["V1"], "AIM": lam["AIM"], "ROTATED": lam["ROTATED"],
            "DVTPF": mag(sub(there[1], lam["V2"])), "ANGLE": central_angle(ra, va, there[0])}


def aim_vg(pos, vel, aim, tof, rotated, mu=MU):
    lam = lambert(pos, aim, tof, mu, vel, 45.0 if rotated else 10.0)
    if not lam["OK"]:
        return {"OK": False, "VG": (0.0, 0.0, 0.0)}
    return {"OK": True, "VG": sub(lam["V1"], vel)}


def checks_transfer():
    """P34 and P35: the intercept time, the transfer, N58, N59, N81 and the aim point the burns steer on."""
    circ = circular_csm()
    tcdh = 3485.806
    lm = kepler(RA1, add(VA1, (0.0, 0.0, 15.37881)), tcdh)
    tg = kepler(circ[0], circ[1], tcdh)
    nrm = unit(cross(tg[0], tg[1]))
    man = cdh(lm[0], lm[1], tg[0], tg[1], nrm)
    ttpi = 5806.381
    ra, va = kepler(lm[0], man["V3"], ttpi - tcdh)[:2]
    rt, vt = kepler(circ[0], circ[1], ttpi)[:2]
    print("--- TPI states at 5806.381")
    print(f"  RA {fmt(ra, 6)}  VA {fmt(va, 7)}")
    print(f"  RT {fmt(rt, 6)}  VT {fmt(vt, 7)}")
    tof = time_theta(rt, vt, 130.0)
    period = 2 * math.pi * math.sqrt(mag(rt) ** 3 / MU)
    check("time theta: 130 degrees of a circular orbit", abs(tof - period * 130 / 360) < 0.001)
    check("time theta: zero angle", abs(time_theta(rt, vt, 0.0)) < 1e-6)
    check("time theta: hyperbola", time_theta(RA1, scale(VA1, 1.6), 90.0) == -1)
    ecc = eccentric_csm()
    t_ecc = time_theta(ecc[0], ecc[1], 200.0)
    after = kepler(ecc[0], ecc[1], t_ecc)[0]
    nrm_e = unit(cross(ecc[0], ecc[1]))
    swept = math.degrees(math.atan2(dot(cross(ecc[0], after), nrm_e), dot(ecc[0], after))) % 360
    check("time theta: eccentric orbit swept 200 degrees", abs(swept - 200.0) < 1e-6)
    print(f"  tof(130) {tof:.4f}  eccentric tof(200) {t_ecc:.4f}")
    out = transfer(ra, va, rt, vt, tof)
    check("transfer: solved", out["OK"])
    hit = kepler(ra, out["V1"], tof)[0]
    check("transfer: V1 flies to the aim point", mag(sub(hit, out["AIM"])) < 0.01)
    check("transfer: TPI delta-V near Apollo's 25 ft/s", 22.0 < mag(out["DV"]) / 0.3048 < 28.0)
    el = elements(ra, out["V1"], MU)
    peri = el["P"] / (1 + el["ECC"]) - RADIUS
    lv_vec = (dot(out["DV"], fwd(unit(cross(ra, va)), ra)), -dot(out["DV"], unit(cross(ra, va))), -dot(out["DV"], unit(ra)))
    los = los_dv(out["DV"], ra, va, rt)
    check("N59 keeps the length", abs(mag(los) - mag(out["DV"])) < 1e-9)
    print(f"  DV {fmt(out['DV'], 5)} |DV| {mag(out['DV']):.5f}  DVTPF {out['DVTPF']:.5f}  perilune {peri:.2f}")
    print(f"  AIM {fmt(out['AIM'])}  angle {out['ANGLE']:.4f}  LV {fmt(lv_vec, 5)}  N59 {fmt(los, 5)}")
    early_t = [kepler(lm[0], man["V3"], 5800 - tcdh), kepler(circ[0], circ[1], 5800)]
    print(f"  elevation at 5806.381 {elevation(ra, va, rt):.4f}, at 5800 {elevation(early_t[0][0], early_t[0][1], early_t[1][0]):.4f}")
    # the line-of-sight axes
    up = unit(ra)
    ahead = fwd(unit(cross(ra, va)), ra)
    target = add(ra, scale(ahead, 1000.0))
    right = scale(unit(cross(ra, va)), -1.0)
    check("N59: forward, right, down", mag(sub(los_dv(add(add(ahead, scale(right, 2.0)), scale(up, -3.0)), ra, va, target), (1.0, 2.0, 3.0))) < 1e-9)
    check("central angle: along the motion", abs(central_angle(ra, va, kepler(ra, va, 100.0)[0]) - central_angle(ra, va, kepler(ra, va, 50.0)[0]) * 2) < 0.01)
    # the aim point the burns steer on
    burn = aim_vg(ra, va, out["AIM"], tof, out["ROTATED"])
    check("aim: velocity to gain at TIG is the targeted delta-V", mag(sub(burn["VG"], out["DV"])) < 1e-6)
    done = aim_vg(ra, add(va, burn["VG"]), out["AIM"], tof, out["ROTATED"])
    check("aim: nothing left once it is gained", mag(done["VG"]) < 1e-6)
    early = kepler(ra, va, -30.0)
    before = aim_vg(early[0], early[1], out["AIM"], tof + 30.0, out["ROTATED"])
    print(f"  VG 30 s before TIG {fmt(before['VG'], 5)}")
    check("aim: 30 s early the velocity to gain is within 0.5 m/s", mag(sub(before["VG"], out["DV"])) < 0.5)
    mid = kepler(ra, out["V1"], 900.0)
    fix = transfer(mid[0], mid[1], kepler(rt, vt, 900.0)[0], kepler(rt, vt, 900.0)[1], tof - 900.0)
    check("midcourse after a perfect TPI is zero", fix["OK"] and mag(fix["DV"]) < 0.001)
    bad = add(out["V1"], (0.2, 0.3, -0.1))
    mid = kepler(ra, bad, 900.0)
    fix = transfer(mid[0], mid[1], kepler(rt, vt, 900.0)[0], kepler(rt, vt, 900.0)[1], tof - 900.0)
    print(f"  midcourse after a TPI error of (0.2, 0.3, -0.1) at +900 s: DV {fmt(fix['DV'], 5)}")
    hit = kepler(mid[0], add(mid[1], fix["DV"]), tof - 900.0)[0]
    check("midcourse corrects a bad TPI", mag(sub(hit, fix["AIM"])) < 0.01)
    check("transfer: no time of flight", not transfer(ra, va, rt, vt, 0.0)["OK"])
    keyed = add(out["DV"], (0.0, 0.5, 0.0))
    aim_new = kepler(ra, add(va, keyed), tof)[0]
    check("keyed delta-V: the new aim point needs exactly it", mag(sub(aim_vg(ra, va, aim_new, tof, False)["VG"], keyed)) < 1e-5)
    print(f"  keyed +0.5 m/s in y: aim {fmt(aim_new)}")


def suggest_tpi(r_apo, r_csm, phase_deg, elev=26.6):
    """rndz_setup.ks: seconds from CSI to TPI for the CSM phase_deg ahead at the LM's apolune. theta is the angle the CSM leads
    by when it stands elev degrees above the LM's horizon, with the LM circular at its apolune height."""
    theta = math.degrees(math.acos(math.cos(math.radians(elev)) * r_apo / r_csm)) - elev
    rate = math.degrees(math.sqrt(MU / r_apo ** 3) - math.sqrt(MU / r_csm ** 3))
    return (phase_deg - theta) / rate, theta, rate


def checks_setup():
    """rndz_setup.ks: the suggested TPI time is the pad case's at 8.4 degrees, and CSI solves across the whole usable window."""
    r_apo, r_csm = mag(RA1), 1848520.0
    suggested, theta, rate = suggest_tpi(r_apo, r_csm, 8.4)
    print(f"--- setup: theta {theta:.3f} deg, closing {rate:.7f} deg/s, TPI {suggested:.1f} s after CSI, "
          f"usable phase {theta + rate * 4500:.2f} to {theta + rate * 9000:.2f} deg")
    check("setup: TPI time at 8.4 degrees within 20 s of 5800", abs(suggested - 5800) < 20)
    for span in (4500.0, 5800.0, 9000.0):
        out = csi(csi_input(circular_csm(angle_deg=theta + rate * span), TTPI=span))
        check(f"setup: CSI solves with TPI {span:.0f} s after CSI, DV near 15.4 and DH near 27.7 km",
              bool(out["OK"]) and abs(out["DV"] - 15.38) < 0.1 and abs(out["DH"] - 27750) < 100)
    short = csi(csi_input(circular_csm(), TTPI=1200.0))
    check("setup: a TPI time 20 minutes after CSI gives alarm 604", not short["OK"] and short["ALARM"] == 604)


def session4_state(sma, ecc, mean):
    """ksp.md session 4: an orbit (periapsis on +x) at the mean anomaly the cheat window takes, rad."""
    peri = sma * (1 - ecc)
    speed = math.sqrt(MU * (1 + ecc) / peri)
    return kepler((peri, 0.0, 0.0), (0.0, 0.0, speed), mean / math.sqrt(MU / sma ** 3))[:2]


def session4_tpi(lm, csm, t, moon=1738000.0):
    a = kepler(lm[0], lm[1], t)[:2]
    b = kepler(csm[0], csm[1], t)[:2]
    x = transfer(a[0], a[1], b[0], b[1], time_theta(b[0], b[1], 130.0))
    if not x["OK"]:
        return None
    el = elements(a[0], x["V1"], MU)
    return {"t": t, "dv": mag(x["DV"]) / 0.3048, "peri": el["P"] / (1 + el["ECC"]) - moon,
            "elev": elevation(a[0], a[1], b[0])}


def checks_session4():
    """The two orbit pairs of ksp.md session 4, with the LM set 10 to 60 s after the CSM (the CSM has moved on by then)."""
    csm_sma = 1858500.0
    csm_rate = math.sqrt(MU / csm_sma ** 3)
    for late in (10.0, 30.0, 60.0):
        lm = session4_state(1830700.0, 0.0, 2.000)
        csm = session4_state(csm_sma, 0.0, 2.043 + late * csm_rate)
        found = None
        for t in range(0, 12000, 60):
            a = kepler(lm[0], lm[1], t)[:2]
            b = kepler(csm[0], csm[1], t)[:2]
            if elevation(a[0], a[1], b[0]) >= 26.6:
                step = tpi_time(a[0], a[1], b[0], b[1], 26.6)
                found = session4_tpi(lm, csm, t + step["DT"])
                break
        print(f"--- session 4A, {late:.0f} s: {found}")
        check(f"session 4A ({late:.0f} s): TPI 10 to 70 min ahead, near 24 ft/s",
              bool(found) and 600 < found["t"] < 4200 and 22 < found["dv"] < 27 and found["peri"] > 80000)
    for late in (0.0, 15.0, 30.0):
        lm = session4_state(1799350.0, 0.01742, 1.766)
        csm = session4_state(csm_sma, 0.0, 1.857 + late * csm_rate)
        good = [s for s in (session4_tpi(lm, csm, t) for t in range(480, 3601, 60))
                if s and s["peri"] > 25000 and 40 <= s["dv"] <= 120]
        best = min(good, key=lambda s: abs(s["dv"] - 70)) if good else None
        print(f"--- session 4B, {late:.0f} s: {best}")
        check(f"session 4B ({late:.0f} s): a TPI of 60 to 85 ft/s within the hour",
              bool(best) and 60 < best["dv"] < 85 and best["peri"] > 60000)


# ---- pointing and relative motion (stage 3; research.md 16) ----------------------
def level(vec, up):
    """The part of vec square to the unit vector up."""
    return sub(vec, scale(up, dot(vec, up)))


def range_rate(pos_a, vel_a, pos_t, vel_t):
    line = sub(pos_t, pos_a)
    return mag(line), dot(sub(vel_t, vel_a), unit(line))


def theta(pos_a, vel_a, axis):
    """V83 R3: the axis from forward horizontal up through the zenith, 0 to 360 degrees."""
    up = unit(pos_a)
    fwd = unit(level(vel_a, up))
    behind = -1.0 if dot(axis, fwd) < 0 else 1.0
    return math.degrees(math.atan2(dot(axis, up), behind * mag(level(axis, up)))) % 360


def r36(pos_a, vel_a, pos_t, vel_t):
    """V90: out-of-plane distance and rate against the CSM's plane, and the bearing of the line of sight."""
    side = unit(cross(vel_t, pos_t))
    up = unit(pos_a)
    fwd = unit(level(vel_a, up))
    right = cross(fwd, up)
    line = sub(pos_t, pos_a)
    psi = math.degrees(math.atan2(dot(line, right), dot(line, fwd))) % 360
    return dot(pos_a, side), dot(vel_a, side), psi


def los_clear(pos_a, pos_t, radius):
    """False when the segment between the two passes inside the sphere."""
    line = sub(pos_t, pos_a)
    length2 = dot(line, line)
    along = 0.0 if length2 == 0 else min(1.0, max(0.0, -dot(pos_a, line) / length2))
    return mag(add(pos_a, scale(line, along))) >= radius


def aim_axis(from_axis, to_dir, other):
    """other (square to from_axis) carried by the smallest rotation taking from_axis to to_dir."""
    f, t = unit(from_axis), unit(to_dir)
    cos_turn = dot(f, t)
    if cos_turn < -0.9999:
        return other
    return sub(other, scale(add(f, t), dot(other, t) / (1 + cos_turn)))


def near(name, got, want, tol):
    check(f"{name}: {got:.3f} (expected {want})", abs(got - want) <= tol)


def checks_pointing():
    """Stage 3 pointing and relative motion. The LM flies +y above the +x axis, so up = +x, forward = +y, right = -z."""
    print("--- stage 3: pointing and relative motion")
    pos_a, vel_a = (1.8e6, 0.0, 0.0), (0.0, 1600.0, 0.0)
    up, fwd, right = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)
    back, down = scale(fwd, -1), scale(up, -1)
    for name, axis, want in (("theta fwd", fwd, 0), ("theta up", up, 90), ("theta back", back, 180), ("theta down", down, 270),
                             ("theta fwd+up", add(fwd, up), 45), ("theta back-down", add(back, down), 225),
                             ("theta up 30, right", add(scale(up, 0.5), scale(right, math.sqrt(0.75))), 30)):
        near(name, theta(pos_a, vel_a, unit(axis)), want, 1e-9)
    y_m, ydot, psi = r36((1.8e6, 0.0, -1000.0), (0.0, 1600.0, -2.0), pos_a, vel_a)
    near("r36 Y", y_m, 1000, 1e-6)
    near("r36 YDOT", ydot, 2, 1e-9)
    near("r36 psi, target to the left", psi, 270, 0.1)
    near("r36 psi ahead", r36(pos_a, vel_a, (1.8e6, 1000.0, 0.0), vel_a)[2] % 360, 0, 0.05)
    near("r36 psi right", r36(pos_a, vel_a, (1.8e6, 0.0, -1000.0), vel_a)[2], 90, 0.05)
    distance, rate = range_rate(pos_a, vel_a, (1.8e6, 1000.0, 0.0), (0.0, 1590.0, 0.0))
    near("range", distance, 1000, 1e-9)
    near("range rate, closing", rate, -10, 1e-9)
    check("line of sight: the Moon between", not los_clear(pos_a, (-1.8e6, 0.0, 0.0), 1.738e6))
    check("line of sight: clear", los_clear(pos_a, (1.8e6, 1000.0, 0.0), 1.738e6))
    for name, other, want in (("aim axis +z", (0.0, 0.0, 1.0), (0.0, 0.0, 1.0)), ("aim axis +y", (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0))):
        got = aim_axis((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), other)
        check(f"{name}: {fmt(got)}", mag(sub(got, want)) < 1e-12)
    check("aim axis, turned right round: unchanged", aim_axis((1.0, 0.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)) == (0.0, 1.0, 0.0))


# The CC17 cue card, page 8: the nominal curve of the inertial line-of-sight rate after a coelliptic TPI (research section 11).
LOS_CARD = ((5, 0.55), (10, 0.47), (15, 0.37), (20, 0.25), (25, 0.10), (28, 0.0), (35, -0.10), (40, -0.07))


def los_rate(rel_pos, rel_vel, nrm):
    """The signed inertial line-of-sight rate about nrm, mrad/s, from the target's position and velocity less the chaser's."""
    return dot(cross(rel_pos, rel_vel), nrm) / dot(rel_pos, rel_pos) * 1000.0


def checks_los():
    """Our maths against that curve: circular CSM at 60 nm, LM circular 15 nm lower, TPI at 26.6 deg, 130 deg of CSM travel."""
    r_csm = RADIUS + 60 * M_PER_NM
    r_lm = r_csm - 15 * M_PER_NM
    elev = math.radians(26.6)
    phase = math.degrees(math.acos(r_lm * math.cos(elev) / r_csm) - elev)
    csm = csm_state(r_csm, math.sqrt(MU / r_csm), phase)
    lm_pos, lm_vel = (r_lm, 0.0, 0.0), (0.0, 0.0, math.sqrt(MU / r_lm))
    tof = math.radians(130) / math.sqrt(MU / r_csm ** 3)
    lam = lambert(lm_pos, kepler(csm[0], csm[1], tof)[0], tof, MU, lm_vel, 15)
    check("line-of-sight rate: the transfer solves", lam["OK"])
    if not lam["OK"]:
        return
    nrm = unit(cross(lm_pos, lm_vel))
    print(f"--- line-of-sight rate after TPI ({mag(sub(lam['V1'], lm_vel)) / 0.3048:.1f} ft/s, {tof / 60:.1f} min)")
    for minutes, card in LOS_CARD:
        lm = kepler(lm_pos, lam["V1"], minutes * 60)
        tg = kepler(csm[0], csm[1], minutes * 60)
        rate = los_rate(sub(tg[0], lm[0]), sub(tg[1], lm[1]), nrm)
        near(f"line-of-sight rate at {minutes} min", rate, card, 0.03)


def main():
    checks_pointing()
    checks_axes()
    checks_conics()
    checks_lambert()
    checks_csi()
    checks_tpi()
    checks_p33()
    checks_setup()
    checks_transfer()
    checks_session4()
    checks_los()
    print("ALL REFERENCE CHECKS PASSED" if not FAILED else f"FAILED: {len(FAILED)}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
