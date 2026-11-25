"""reference_ascent.py -- the ascent maths (release 1.5) in Python, numpy-free.

The functions here are the reference for scripts/lm/ascent/lm_ascent_guid.ks, s30_tff (lm/burn/lm_burn_s.ks) and the
phasing part of lm/planner/lm_ascent_plan.ks. The self-checks hold the model against the flown and planned numbers;
the "KOS TEST VALUES" block is what the pad tests assert. Run: python scripts/tests/reference_ascent.py (exit 1 on a
failed check). SI units. Vectors are right-handed tuples (AGC handedness); in kOS the same cross products go through
lm_cross, so the scalar results (speeds along the guidance axes, angles) are the same.
Luminary 210 source: AGC Repo/virtualagc/Luminary210 (ASCENT_GUIDANCE.agc, P12.agc, R30.agc, CONTROLLED_CONSTANTS.agc).
"""
import math
import sys

MU = 4.9028e12                  # m^3/s^2
NM = 1852.0
FT = 0.3048
SITE_R = 1735750.0              # m, the site radius used where a check does not say otherwise
PREFS_ROTATION = 2.6617e-6      # rad/s, the Moon's spin (the surface speed at lift-off)

# Constants as in lm_constants.ks (section "Ascent (1.5)").
ASC_HINJECT_M = 18288.0         # HINJECT, 60 000 ft above the site radius
ASC_VE = 3030.0                 # APSVEX
ASC_AT0 = 3.2883                # (AT)A
ASC_TBUP0 = 919.02              # (TBUP)A
ASC_INVDV0 = 0.152              # (1/DV)A, s/m
ASC_TGO0 = 370.0                # (TGO)A
ASC_ZDOTD_NOM = 1679.299        # VINJNOM, 5509.5 ft/s
ASC_RDOTD_NOM = 5.9436          # RDOTDNOM, 19.5 ft/s
ASC_TIPOVER_RDOT = 14.9352      # 49FPS
ASC_TAILOFF_A11 = 0.10          # ATDECAY -10 cs (099)
ASC_TAILOFF_J = 0.18            # ATDECAY -18 cs (210)
ASC_RISE_RDOT = 12.192          # 40FPS
ASC_RISE_YAW_DEG = 5.0          # 099 yaw test
ASC_RISE_ALT_M = 7620.0         # 25KFT
ASC_T_NOPOS = 10.0              # T3
ASC_T_HOLD = 2.0                # T2A
ASC_T_CUT = 4.0                 # 4SEC
ASC_LOOKAHEAD_S = 1.0           # 100CS at the time scale of D12
ASC_XOVR_S = 10.0
ASC_PRLIMIT = -0.03048          # (B/TBUP) minimum, -0.1 ft/s^3
ASC_MINDV = 3.56                # MINABDV, m/s in 2 s
ASC_AT_RCS = 0.785              # AT/RCS
ASC_SIM_DT = 1.0
ASC_TURN_DEG_S = 10.0           # the commanded attitude turns no faster than this

# Planner (Task 5).
ASC_PHASE_RDOT = 9.81456        # 32.2 ft/s
ASC_APO_BELOW_A11_M = 27780.0   # 15 nm
ASC_APO_BELOW_J_M = 25928.0     # 14 nm
ASC_CSI_S = 3000.0              # insertion to CSI, 50 min
ASC_CSI_TO_TPI_S = 5940.0       # CSI to TPI, 59 + 40 min
ASC_TPI_ELEV_DEG = 26.6
ASC_J_TPI_S = 2700.0            # insertion to TPI, 45 min
ASC_J_TPI_FPS = 73.0
TFF_LIMIT_M = 10668.0           # MINPERM, 35 000 ft


def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def mag(a): return math.sqrt(dot(a, a))
def scale(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def unit(a): return scale(a, 1.0 / mag(a))
def clamp(x, lo, hi): return max(lo, min(hi, x))
def vang(a, b): return math.degrees(math.acos(clamp(dot(unit(a), unit(b)), -1.0, 1.0)))
def wrap180(deg): return (deg + 180.0) % 360.0 - 180.0


def exclude(axis, vec):
    """vec with its part along axis removed (kOS VECTOREXCLUDE)."""
    n = unit(axis)
    return sub(vec, scale(n, dot(vec, n)))


# ---- Guidance (lm_ascent_guid.ks) ---------------------------------------------------------------------------------

def asc_new(profile):
    est = ASC_VE * 2 * ASC_INVDV0
    return {"PROFILE": profile, "TGO": ASC_TGO0, "AT": ASC_AT0, "TBUP": ASC_TBUP0, "EST": [est] * 4,
            "FLPC": False, "A": 0.0, "B": 0.0, "C": 0.0, "D": 0.0}


def asc_engine(g, dv_ms, span_s):
    """ATMAG: the burn-up time filtered from the last four delta-V measurements."""
    dv2 = dv_ms * 2.0 / span_s
    if dv2 < ASC_MINDV:
        return False
    g["EST"] = g["EST"][1:] + [ASC_VE * 2.0 / dv2]
    g["TBUP"] = (g["TBUP"] - span_s + sum(g["EST"]) / 4.0 - 4.0) / 2.0
    g["AT"] = ASC_VE / g["TBUP"]
    return True


def asc_qaxis(r_csm, v_csm):
    return unit(cross(v_csm, r_csm))


def asc_state(r_vec, v_vec, qaxis, mu, rco):
    rmag = mag(r_vec)
    ur = unit(r_vec)
    z_axis = unit(cross(ur, qaxis))
    lat = unit(cross(z_axis, ur))
    rdot = dot(v_vec, ur)
    horiz = sub(v_vec, scale(ur, rdot))
    return {"UR": ur, "Z": z_axis, "LAT": lat, "RMAG": rmag, "RDOT": rdot, "ZDOT": dot(v_vec, z_axis),
            "YDOT": dot(v_vec, lat), "Y": rco * dot(ur, qaxis),
            "GEFF": -mu / rmag ** 2 + dot(horiz, horiz) / rmag, "QAXIS": qaxis}


def asc_target(rco, yco, rdotd, zdotd):
    return {"RCO": rco, "YCO": yco, "RDOTD": rdotd, "YDOTD": 0.0, "ZDOTD": zdotd}


def asc_vg(g, st, tgt):
    """Velocity to be gained, with the gravity term over the previous time to go."""
    vec = scale(st["UR"], tgt["RDOTD"] - st["RDOT"])
    vec = add(vec, scale(st["LAT"], tgt["YDOTD"] - st["YDOT"]))
    vec = add(vec, scale(st["Z"], tgt["ZDOTD"] - st["ZDOT"]))
    return sub(vec, scale(st["UR"], g["TGO"] * st["GEFF"]))


def asc_guide(g, st, tgt):
    vg = asc_vg(g, st, tgt)
    # VG / VE is held at 1 (beyond it the time to go would fall again and go negative, cutting the engine off):
    # never reached by a real target; it only guards a bad load.
    ratio = min(mag(vg) / ASC_VE, 1.0)
    tailoff = ASC_TAILOFF_J if g["PROFILE"] == "J" else ASC_TAILOFF_A11
    tbup = g["TBUP"]
    tgo = tbup * ratio * (1.0 - ratio / 2.0) - tailoff
    g["TGO"] = tgo
    if tgo >= ASC_T_HOLD:
        t = clamp(tgo, 0.0, 0.9 * tbup)
        k = -math.log(1.0 - t / tbup)
        d12 = tbup - t / k
        drdot = tgt["RDOTD"] - st["RDOT"]
        dydot = tgt["YDOTD"] - st["YDOT"]
        if not g["FLPC"] and tgo < ASC_T_NOPOS:
            g["FLPC"] = True
        b_rate = 0.0
        d_rate = 0.0
        if not g["FLPC"]:
            d21 = t - d12
            e = t / 2.0 - d21
            dr = tgt["RCO"] - st["RMAG"] - st["RDOT"] * t
            dy = tgt["YCO"] - st["Y"] - st["YDOT"] * t
            b_rate = (d21 * drdot - dr) / (e * t)
            b_rate = max(min(b_rate, 0.0), ASC_PRLIMIT * tbup)
            d_rate = (d21 * dydot - dy) / (e * t)
        g["B"] = b_rate
        g["D"] = d_rate
        g["A"] = drdot / k - d12 * b_rate
        g["C"] = dydot / k - d12 * d_rate
    at = g["AT"]
    ar = (g["A"] + g["B"] * ASC_LOOKAHEAD_S) / tbup - st["GEFF"]
    ay = (g["C"] + g["D"] * ASC_LOOKAHEAD_S) / tbup
    ah = add(scale(st["LAT"], ay), scale(st["UR"], ar))
    if mag(ah) <= at:
        ap = math.sqrt(max(0.0, at ** 2 - mag(ah) ** 2))
    else:
        ah = scale(ah, at / mag(ah))
        ap = 0.0
    if tgt["ZDOTD"] - st["ZDOT"] < 0:
        ap = -ap
    direction = unit(add(ah, scale(st["Z"], ap)))
    return {"TGO": tgo, "VG": vg, "DIR": direction, "AR": ar, "AY": ay, "AP": ap}


def asc_trim(g, st, tgt):
    vg = asc_vg(g, st, tgt)
    g["TGO"] = mag(vg) / ASC_AT_RCS
    return vg


def asc_rise_done(profile, height_m, rdot, yaw_err_deg):
    if height_m >= ASC_RISE_ALT_M:
        return True
    if rdot < ASC_RISE_RDOT:
        return False
    return profile == "J" or abs(yaw_err_deg) <= ASC_RISE_YAW_DEG


def wrap_deg(angle):
    wrapped = (angle + 360.0) % 360.0
    return 0.0 if wrapped >= 359.995 else wrapped


def asc_yaw_pitch(cmd, st):
    horiz = math.sqrt(cmd["AY"] ** 2 + cmd["AP"] ** 2)
    yaw = 0.0 if horiz == 0 else math.degrees(math.asin(clamp(cmd["AY"] / horiz, -1.0, 1.0)))
    pitch = -vang(cmd["DIR"], st["UR"])
    return (wrap_deg(yaw), wrap_deg(pitch))


def asc_window_down(direction, st):
    ref = st["Z"] if vang(direction, st["UR"]) < 5.0 else scale(st["UR"], -1.0)
    return unit(exclude(direction, ref))


def asc_insertion_vh(r_ins, r_apo, mu, vr):
    return math.sqrt(2.0 * (mu * (1.0 / r_ins - 1.0 / r_apo) - vr ** 2 / 2.0) / (1.0 - (r_ins / r_apo) ** 2))


def turn_toward(cur, want, max_deg):
    """cur turned toward want by at most max_deg."""
    ang = vang(cur, want)
    if ang <= max_deg:
        return unit(want)
    side = unit(exclude(cur, want))
    return add(scale(unit(cur), math.cos(math.radians(max_deg))), scale(side, math.sin(math.radians(max_deg))))


def asc_sim(profile, r0, v0, qaxis, mu, tgt, mass_kg, thrust_n, ve_ms, dt_s):
    """Our ascent flown with the guidance functions: burn time, end state and the pitch shown before lift-off."""
    g = asc_new(profile)
    first = asc_state(r0, add(v0, scale(unit(r0), ASC_TIPOVER_RDOT)), qaxis, mu, tgt["RCO"])
    pitch_rise = asc_yaw_pitch(asc_guide(asc_new(profile), first, tgt), first)[1]
    site_r = mag(r0)
    flow = thrust_n / ve_ms
    r_vec, v_vec, mass, t = r0, v0, mass_kg, 0.0
    direction = unit(r0)
    rising = True
    pass_t, pass_dv = 0.0, 0.0

    def gravity(p):
        return scale(p, -mu / mag(p) ** 3)

    def push(r_vec, v_vec, mass, direction, h):
        m1 = mass - flow * h
        dv = ve_ms * math.log(mass / m1)
        acc = scale(direction, dv / h)
        a0 = add(gravity(r_vec), acc)
        r1 = add(add(r_vec, scale(v_vec, h)), scale(a0, h * h / 2.0))
        a1 = add(gravity(r1), acc)
        return r1, add(v_vec, scale(add(a0, a1), h / 2.0)), m1, dv

    def result(ok):
        return {"OK": ok, "BURN_S": t, "R_END": r_vec, "V_END": v_vec, "MASS_END": mass, "DIR_END": direction,
                "PITCH_RISE": pitch_rise}

    while t < 900.0:
        st = asc_state(r_vec, v_vec, qaxis, mu, tgt["RCO"])
        cmd = asc_guide(g, st, tgt)
        if rising and asc_rise_done(profile, st["RMAG"] - site_r, st["RDOT"], 0.0):
            rising = False
        if rising:
            direction = st["UR"]
        else:
            direction = turn_toward(direction, cmd["DIR"], ASC_TURN_DEG_S * dt_s)
        if not rising and cmd["TGO"] < ASC_T_CUT:
            last = max(0.0, cmd["TGO"])
            if last > 0.001:
                if mass - flow * last <= 0:
                    return result(False)
                r_vec, v_vec, mass, _ = push(r_vec, v_vec, mass, direction, last)
                t += last
            return result(True)
        if mass - flow * dt_s <= 0.05 * mass_kg:
            return result(False)
        r_vec, v_vec, mass, dv = push(r_vec, v_vec, mass, direction, dt_s)
        t += dt_s
        pass_t += dt_s
        pass_dv += dv
        if pass_t >= 2.0 - 1e-6:
            asc_engine(g, pass_dv, pass_t)
            pass_t, pass_dv = 0.0, 0.0
    return result(False)


# ---- V82 (lm_burn_s.ks s30_tff) -----------------------------------------------------------------------------------

def s30_tff(r_vec, v_vec, mu, limit_radius):
    """CALCTFF (R30.agc): seconds to the next descending crossing of limit_radius, or -1."""
    r = mag(r_vec)
    energy = dot(v_vec, v_vec) / 2.0 - mu / r
    if r < limit_radius or energy >= 0:
        return -1.0
    h_vec = cross(r_vec, v_vec)
    p = dot(h_vec, h_vec) / mu
    a = -mu / (2.0 * energy)
    e = math.sqrt(max(0.0, 1.0 - p / a))
    if a * (1.0 - e) >= limit_radius or e < 1e-9:
        return -1.0
    nu_now = math.acos(clamp((p / r - 1.0) / e, -1.0, 1.0))
    if dot(r_vec, v_vec) < 0:
        nu_now = 2 * math.pi - nu_now
    nu_x = 2 * math.pi - math.acos(clamp((p / limit_radius - 1.0) / e, -1.0, 1.0))

    def mean(nu):
        ecc = 2.0 * math.atan2(math.sqrt(1 - e) * math.sin(nu / 2), math.sqrt(1 + e) * math.cos(nu / 2))
        return ecc - e * math.sin(ecc)

    n = math.sqrt(mu / a ** 3)
    return ((mean(nu_x) - mean(nu_now)) % (2 * math.pi)) / n


# ---- Phasing (lm_ascent_plan.ks) ----------------------------------------------------------------------------------

def asc_kepler_polar(r, vh, vr, mu, dt):
    """Two-body motion from radius r with horizontal and radial speed: the radius after dt and the angle travelled."""
    energy = (vh * vh + vr * vr) / 2.0 - mu / r
    p = (r * vh) ** 2 / mu
    if energy >= 0 or p <= 0:
        return {"R": r, "ANG": 0.0}
    a = -mu / (2.0 * energy)
    n = math.sqrt(mu / a ** 3)
    ecos = p / r - 1.0
    esin = vr * r * vh / mu
    e = math.sqrt(ecos ** 2 + esin ** 2)
    if e < 1e-8:
        return {"R": r, "ANG": math.degrees(n * dt)}
    nu0 = math.atan2(esin, ecos)
    ecc0 = 2.0 * math.atan2(math.sqrt(1 - e) * math.sin(nu0 / 2), math.sqrt(1 + e) * math.cos(nu0 / 2))
    m1 = ecc0 - e * math.sin(ecc0) + n * dt
    revs = math.floor((m1 + math.pi) / (2 * math.pi))
    m_part = m1 - revs * 2 * math.pi
    ecc = m_part
    for _ in range(30):
        ecc -= (ecc - e * math.sin(ecc) - m_part) / (1.0 - e * math.cos(ecc))
    nu1 = 2.0 * math.atan2(math.sqrt(1 + e) * math.sin(ecc / 2), math.sqrt(1 - e) * math.cos(ecc / 2))
    return {"R": a * (1.0 - e * math.cos(ecc)), "ANG": math.degrees(nu1 - nu0 + revs * 2 * math.pi)}


def asc_phase_angle(profile, r_site, r_csm, mu, j_phase_deg=None, j_dh_m=None):
    """Degrees the CSM must be ahead of the LM at insertion (research 1.5, section 10)."""
    r_ins = r_site + ASC_HINJECT_M
    r_apo = r_csm - (ASC_APO_BELOW_J_M if profile == "J" else ASC_APO_BELOW_A11_M)
    vh = asc_insertion_vh(r_ins, r_apo, mu, ASC_PHASE_RDOT)
    n_csm = math.sqrt(mu / r_csm ** 3)
    if profile == "J":
        j_phase_deg = J_TPI_PHASE_DEG if j_phase_deg is None else j_phase_deg
        j_dh_m = J_TPI_DH_M if j_dh_m is None else j_dh_m
        at_tpi = asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, mu, ASC_J_TPI_S)
        travel = at_tpi["ANG"]
        total = ASC_J_TPI_S
        phase_tpi = j_phase_deg * (r_csm - at_tpi["R"]) / j_dh_m
    else:
        at_csi = asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, mu, ASC_CSI_S)
        r_lm = at_csi["R"]
        travel = at_csi["ANG"] + math.degrees(math.sqrt(mu / r_lm ** 3) * ASC_CSI_TO_TPI_S)
        total = ASC_CSI_S + ASC_CSI_TO_TPI_S
        elev = math.radians(ASC_TPI_ELEV_DEG)
        phase_tpi = math.degrees(math.acos(clamp(r_lm * math.cos(elev) / r_csm, -1.0, 1.0)) - elev)
    return phase_tpi + wrap180(travel - math.degrees(n_csm * total))


# ---- The J intercept solver (docs/superpowers/research-1.5-phasing.py, heights above the site radius) -------------

def rk4(s, t, h=2.0):
    def f(q):
        x, y, vx, vy = q
        k = -MU / (x * x + y * y) ** 1.5
        return (vx, vy, k * x, k * y)

    while t > 1e-9:
        d = min(h, t)
        a = f(s)
        b = f([s[i] + d / 2 * a[i] for i in range(4)])
        c = f([s[i] + d / 2 * b[i] for i in range(4)])
        e = f([s[i] + d * c[i] for i in range(4)])
        s = [s[i] + d / 6 * (a[i] + 2 * b[i] + 2 * c[i] + e[i]) for i in range(4)]
        t -= d
    return s


def intercept_dv(lm, r_csm, phase_deg, travel=130.0):
    """Delta-v (ft/s) of the impulsive TPI that meets the CSM after it travels `travel` degrees."""
    n = math.sqrt(MU / r_csm ** 3)
    t = math.radians(travel) / n
    end = math.atan2(lm[1], lm[0]) + math.radians(phase_deg + travel)
    tx, ty = r_csm * math.cos(end), r_csm * math.sin(end)
    vel = [lm[2], lm[3]]
    for _ in range(25):
        s = rk4([lm[0], lm[1], vel[0], vel[1]], t)
        ex, ey = s[0] - tx, s[1] - ty
        if math.hypot(ex, ey) < 1:
            break
        jac = []
        for k in range(2):
            w = vel[:]
            w[k] += 0.1
            q = rk4([lm[0], lm[1], w[0], w[1]], t)
            jac.append(((q[0] - s[0]) / 0.1, (q[1] - s[1]) / 0.1))
        det = jac[0][0] * jac[1][1] - jac[1][0] * jac[0][1]
        vel[0] -= (jac[1][1] * ex - jac[1][0] * ey) / det
        vel[1] -= (-jac[0][1] * ex + jac[0][0] * ey) / det
    return math.hypot(vel[0] - lm[2], vel[1] - lm[3]) / FT


def j_tpi_numbers(r_site=SITE_R):
    """The J plan: 60 nm CSM, 46 nm apolune, TPI 45 min after insertion costing 73 ft/s: its phase and height difference."""
    r_csm = r_site + 60 * NM
    r_ins = r_site + ASC_HINJECT_M
    vh = asc_insertion_vh(r_ins, r_site + 46 * NM, MU, ASC_PHASE_RDOT)
    lm = rk4([r_ins, 0.0, ASC_PHASE_RDOT, vh], ASC_J_TPI_S)
    lo, hi = 1.0, 2.5
    for _ in range(30):
        mid = (lo + hi) / 2
        if intercept_dv(lm, r_csm, mid) < ASC_J_TPI_FPS:
            lo = mid
        else:
            hi = mid
    return lo, r_csm - math.hypot(lm[0], lm[1])


J_TPI_PHASE_DEG, J_TPI_DH_M = j_tpi_numbers()


# ---- Cases shared with the pad tests ------------------------------------------------------------------------------

def surface_case(r_site):
    """Landed on the equator of the CSM plane: position, surface velocity, Q axis."""
    r0 = (r_site, 0.0, 0.0)
    v0 = (0.0, PREFS_ROTATION * r_site, 0.0)
    v_csm = math.sqrt(MU / (r_site + 60 * NM))
    qaxis = asc_qaxis((r_site + 60 * NM, 0.0, 0.0), (0.0, v_csm, 0.0))
    return r0, v0, qaxis


def frame_case(rmag, cross_slope, rdot, zdot, ydot, rco):
    """A flight state given by its parts along the guidance axes (so kOS and Python agree whatever the handedness)."""
    _, _, qaxis = surface_case(SITE_R)
    r_vec = scale(unit(add((1.0, 0.0, 0.0), scale(qaxis, cross_slope))), rmag)
    axes = asc_state(r_vec, (0.0, 0.0, 0.0), qaxis, MU, rco)
    v_vec = add(add(scale(axes["UR"], rdot), scale(axes["Z"], zdot)), scale(axes["LAT"], ydot))
    return asc_state(r_vec, v_vec, qaxis, MU, rco)


RCO_T = SITE_R + ASC_HINJECT_M


def guide_case(rmag=SITE_R + 9000.0, cross_slope=0.001, rdot=40.0, zdot=800.0, ydot=3.0, tgo=250.0, tbup=700.0,
               yco=500.0, zdotd=1686.9, rdotd=ASC_PHASE_RDOT, profile="A11"):
    g = asc_new(profile)
    g["TGO"], g["TBUP"], g["AT"] = tgo, tbup, ASC_VE / tbup
    st = frame_case(rmag, cross_slope, rdot, zdot, ydot, RCO_T)
    tgt = asc_target(RCO_T, yco, rdotd, zdotd)
    return g, st, tgt


# ---- Self-checks and the values for the pad tests -----------------------------------------------------------------

FAILURES = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("  " + detail if detail else ""))
    if not ok:
        FAILURES.append(name)


def end_speeds(sim, qaxis, thrust, tailoff):
    """Insertion horizontal and radial speed (m/s) and height, with the engine's tail-off impulse added."""
    v_end = add(sim["V_END"], scale(sim["DIR_END"], tailoff * thrust / sim["MASS_END"]))
    st = asc_state(sim["R_END"], v_end, qaxis, MU, 1.0)
    return st["ZDOT"], st["RDOT"], st["RMAG"]


def apollo11_sim():
    r0, v0, qaxis = surface_case(SITE_R)
    tgt = asc_target(RCO_T, 0.0, 32.2 * FT, 5534.9 * FT)
    return asc_sim("A11", r0, v0, qaxis, MU, tgt, 4915.6, 15569.0, 15569.0 / 5.135, ASC_SIM_DT), qaxis


def self_checks():
    sim, qaxis = apollo11_sim()
    zdot, rdot, rmag = end_speeds(sim, qaxis, 15569.0, ASC_TAILOFF_A11)
    check("Apollo 11 burn time", sim["OK"] and abs(sim["BURN_S"] - 434.9) <= 10, "%.1f s" % sim["BURN_S"])
    check("Apollo 11 insertion speeds", abs(zdot / FT - 5534.9) <= 1 and abs(rdot / FT - 32.2) <= 1,
          "%.2f %.2f ft/s" % (zdot / FT, rdot / FT))
    check("Apollo 11 insertion height", abs(rmag - SITE_R - ASC_HINJECT_M) <= 150, "%.1f m" % (rmag - SITE_R))
    from_vert = 360.0 - sim["PITCH_RISE"]
    check("pitch after rise", abs(from_vert - 50) <= 6, "%.2f deg from vertical" % from_vert)

    r0, v0, q68 = surface_case(SITE_R)
    tgt68 = asc_target(RCO_T, 0.0, 19.5 * FT, 5509.5 * FT)
    s68 = asc_sim("A11", r0, v0, q68, MU, tgt68, 4869.9, 16014.0, 16014.0 / 5.299, ASC_SIM_DT)
    arc = vang(r0, s68["R_END"])
    check("1968 ground arc", s68["OK"] and abs(arc - 9.47) <= 0.5, "%.3f deg, burn %.1f s" % (arc, s68["BURN_S"]))

    g = asc_new("A11")
    mass, flow = 4915.6, 15569.0 / ASC_VE
    worst_at, worst_tb = 0.0, 0.0
    for k in range(1, 101):
        m1 = mass - flow * 2.0
        asc_engine(g, ASC_VE * math.log(mass / m1), 2.0)
        if 2 * k >= 20:
            mean_at = ASC_VE * math.log(mass / m1) / 2.0
            worst_at = max(worst_at, abs(g["AT"] / mean_at - 1))
            worst_tb = max(worst_tb, abs(g["TBUP"] - m1 / flow))
        mass = m1
    check("engine filter acceleration", worst_at <= 0.005, "%.4f %%" % (100 * worst_at))
    check("engine filter burn-up time", worst_tb <= 5.0, "%.2f s" % worst_tb)

    for rs in (1735500.0, 1736000.0):
        vh = asc_insertion_vh(rs + ASC_HINJECT_M, rs + 45 * NM, MU, 32.2 * FT) / FT
        check("insertion speed, site %.0f" % rs, 5533.0 <= vh <= 5534.0, "%.2f ft/s" % vh)
        a11 = asc_phase_angle("A11", rs, rs + 60 * NM, MU)
        jj = asc_phase_angle("J", rs, rs + 60 * NM, MU)
        check("A11 phase, site %.0f" % rs, abs(a11 - 15.87) <= 0.08, "%.3f deg" % a11)
        check("J phase, site %.0f" % rs, abs(jj - 8.58) <= 0.08, "%.3f deg" % jj)

    r_ins = SITE_R + ASC_HINJECT_M
    vh = asc_insertion_vh(r_ins, SITE_R + 45 * NM, MU, ASC_PHASE_RDOT)
    kep = asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, MU, 3000.0)
    s = rk4([r_ins, 0.0, ASC_PHASE_RDOT, vh], 3000.0)
    check("Kepler radius", abs(kep["R"] - math.hypot(s[0], s[1])) <= 20, "%.2f m" % (kep["R"] - math.hypot(s[0], s[1])))
    ang = math.degrees(math.atan2(s[1], s[0]))
    check("Kepler angle", abs(wrap180(kep["ANG"] - ang)) <= 0.001, "%.6f deg" % wrap180(kep["ANG"] - ang))

    # The cases the pad tests rely on: each must really exercise what its name says.
    g, st, tgt = guide_case()
    asc_guide(g, st, tgt)
    check("mid ascent case has an unlimited radial rate", ASC_PRLIMIT * g["TBUP"] < g["B"] < 0, "B %.4f" % g["B"])
    g, st, tgt = guide_case(**LIMIT_LOW)
    asc_guide(g, st, tgt)
    check("radial rate at the limit", abs(g["B"] - ASC_PRLIMIT * g["TBUP"]) < 1e-9, "B %.4f" % g["B"])
    g, st, tgt = guide_case(**LIMIT_HIGH)
    asc_guide(g, st, tgt)
    check("positive radial rate zeroed", g["B"] == 0.0 and not g["FLPC"], "B %.4f TGO %.1f" % (g["B"], g["TGO"]))
    g, st, tgt = guide_case(**NEAR_END)
    c = asc_guide(g, st, tgt)
    check("near-end case is 2 to 10 s", 2.0 < c["TGO"] < 10.0 and g["FLPC"] and g["B"] == 0, "TGO %.2f" % c["TGO"])
    g, st, tgt = guide_case(**HOLD_END)
    c = asc_guide(g, st, tgt)
    check("hold case is under 2 s", c["TGO"] < 2.0, "TGO %.3f" % c["TGO"])
    g, st, tgt = guide_case(**LIMITED)
    c = asc_guide(g, st, tgt)
    check("limited case has no downrange part", c["AP"] == 0 and abs(mag(c["DIR"]) - 1) < 1e-9, "AY %.2f" % c["AY"])
    for kw in BAD_LOADS:
        g, st, tgt = guide_case(**kw)
        c = asc_guide(g, st, tgt)
        check("bad load finite " + str(kw), math.isfinite(c["TGO"]) and c["TGO"] > 0 and abs(mag(c["DIR"]) - 1) < 1e-9,
              "TGO %.1f" % c["TGO"])
    r0, v0, qa = surface_case(SITE_R)
    low = asc_sim("A11", r0, v0, qa, MU, asc_target(RCO_T, 0.0, 32.2 * FT, 5534.9 * FT), 4915.0, 7000.0, ASC_VE, 1.0)
    check("too little thrust never reaches orbit", not low["OK"] and low["BURN_S"] <= 900.0, "%.0f s" % low["BURN_S"])
    tff = s30_tff(*tff_case())
    half = math.pi * math.sqrt(((SITE_R + 111120 + SITE_R - 50000) / 2) ** 3 / MU)
    check("free-fall time descending", 0 < tff < half, "%.2f s of %.0f" % (tff, half))


# The guidance cases (keyword arguments of guide_case); test_ascent.ks builds the same ones.
LIMIT_LOW = {"rmag": SITE_R + 500.0, "rdot": 0.0, "zdot": 1300.0, "tgo": 100.0}
LIMIT_HIGH = {"rmag": SITE_R + 25000.0, "rdot": 5.0}
NEAR_END = {"rmag": RCO_T, "rdot": ASC_PHASE_RDOT, "zdot": 1655.0, "ydot": 0.0, "tgo": 8.0, "tbup": 480.0}
HOLD_END = {"rmag": RCO_T, "rdot": ASC_PHASE_RDOT, "zdot": 1681.0, "ydot": 0.0, "tgo": 1.5, "tbup": 480.0}
LIMITED = {"yco": 600000.0}
BAD_LOADS = [{"zdotd": 18000.0}, {"zdotd": -500.0}, {"yco": 600000.0}, {"zdotd": 40000.0, "tbup": 200.0}]


def tff_case():
    ra, rp = SITE_R + 111120.0, SITE_R - 50000.0
    va = math.sqrt(MU * (2 / ra - 2 / (ra + rp)))
    return (ra, 0.0, 0.0), (0.0, va, 0.0), MU, SITE_R + TFF_LIMIT_M


def kos_values():
    print("\nKOS TEST VALUES")
    g = asc_new("A11")
    asc_engine(g, 6.4, 2.0)
    print("engine 1 pass  TBUP %.4f  AT %.5f" % (g["TBUP"], g["AT"]))
    for _ in range(4):
        asc_engine(g, 6.4, 2.0)
    print("engine 5 passes TBUP %.4f  AT %.5f" % (g["TBUP"], g["AT"]))
    g, st, tgt = guide_case()
    c = asc_guide(g, st, tgt)
    print("guide mid: Y %.3f GEFF %.6f TGO %.4f AR %.6f AY %.6f AP %.6f" % (st["Y"], st["GEFF"], c["TGO"], c["AR"], c["AY"], c["AP"]))
    print("guide mid: A %.5f B %.6f C %.5f D %.6f" % (g["A"], g["B"], g["C"], g["D"]))
    yp = asc_yaw_pitch(c, st)
    print("guide mid: yaw %.4f pitch %.4f" % yp)
    vg = asc_trim(g, st, tgt)
    print("trim: |VG| %.4f TGO %.4f" % (mag(vg), g["TGO"]))
    sim, qaxis = apollo11_sim()
    zdot, rdot, rmag = (lambda s: (s["ZDOT"], s["RDOT"], s["RMAG"]))(asc_state(sim["R_END"], sim["V_END"], qaxis, MU, 1.0))
    print("sim A11: BURN_S %.3f RMAG %.1f ZDOT %.4f RDOT %.4f MASS %.2f PITCH %.4f" %
          (sim["BURN_S"], rmag, zdot, rdot, sim["MASS_END"], sim["PITCH_RISE"]))
    print("v82 tff %.3f" % s30_tff(*tff_case()))
    print("J_TPI_PHASE_DEG %.6f  J_TPI_DH_M %.1f" % (J_TPI_PHASE_DEG, J_TPI_DH_M))
    r_ins = SITE_R + ASC_HINJECT_M
    vh = asc_insertion_vh(r_ins, SITE_R + 45 * NM, MU, ASC_PHASE_RDOT)
    print("insertion vh 45 nm (site %.0f): %.4f m/s" % (SITE_R, vh))
    kep = asc_kepler_polar(r_ins, vh, ASC_PHASE_RDOT, MU, 3000.0)
    print("kepler 3000 s: R %.2f ANG %.5f" % (kep["R"], kep["ANG"]))
    for csm_nm in (50, 60, 70):
        print("phase CSM %d nm: A11 %.4f  J %.4f" % (csm_nm, asc_phase_angle("A11", SITE_R, SITE_R + csm_nm * NM, MU),
                                                    asc_phase_angle("J", SITE_R, SITE_R + csm_nm * NM, MU)))


if __name__ == "__main__":
    self_checks()
    kos_values()
    if FAILURES:
        print("\n%d CHECK(S) FAILED: %s" % (len(FAILURES), ", ".join(FAILURES)))
        sys.exit(1)
    print("\nALL CHECKS PASSED")
