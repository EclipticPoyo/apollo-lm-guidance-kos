"""Expected values for the pad tests in test_math.ks.

Run: python scripts/tests/reference.py
The numbers printed here are the ones typed into test_math.ks, so the tests
check the KerboScript against an independent calculation.
"""

FT_PER_M = 1 / 0.3048   # international foot, exact by definition
M_PER_NM = 1852.0       # international nautical mile, exact by definition

print("m_to_ft(1)      =", FT_PER_M)
print("ms_to_fps(100)  =", 100 * FT_PER_M)
print("m_to_nm(1852)   =", 1852 / M_PER_NM)
print("m_to_nm(926)    =", 926 / M_PER_NM)

# ---- Task 3: landing-site frame ---------------------------------------------
# Plain-Python mirror of lm_frame.ks (no numpy). FRAME_SIGN = -1 as measured in KSP.
import math

FRAME_SIGN = -1


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def scale(a, k): return tuple(x * k for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def mag(a): return math.sqrt(dot(a, a))
def unit(a): return scale(a, 1 / mag(a))
def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def lm_cross(a, b):
    """Luminary (right-handed) cross product, expressed with kOS's left-handed VCRS."""
    return scale(cross(a, b), FRAME_SIGN)


def guidance_cg(land, r, angterm, lead):
    up = unit(land)
    aim = sub(add(land, scale(angterm, lead)), r)      # CGCALC: LAND + lead*ANGTERM - R
    if mag(lm_cross(aim, up)) <= 1e-9 * mag(aim):       # degenerate (ship directly above the site): lm_frame.ks picks an axis
        aim = (1.0, 0.0, 0.0) if abs(up[0]) < 0.9 else (0.0, 1.0, 0.0)
    row1 = unit(lm_cross(aim, up))
    return [up, row1, lm_cross(up, row1)]


print()
# Test: land_update rotates by atan(w*dt) (Luminary's first-order formula, then renormalised)
w, dt = 0.01, 10
print("land_update angle (deg), w=0.01 dt=10 =", math.degrees(math.atan(w * dt)))

# Test: orientation. LAND straight up the +Y axis, ship 500 m back along -X and 100 m higher.
land = (0.0, 1737000.0, 0.0)
r = (-500.0, 1737100.0, 0.0)
cg = guidance_cg(land, r, (0, 0, 0), 0)
print("rows (FRAME_SIGN=-1):", cg)            # expect (0,1,0) (0,0,-1) (1,0,0)
print("vgu of v=(0,0,0)+(3,0,0):", tuple(dot(row, (3, 0, 0)) for row in cg))   # expect (0,0,3)

# Test: vgu with a spin term. Identity frame, wm=(0,0.001,0), r=(0,0,100), v=(1,2,3).
wm, rr, vv = (0, 0.001, 0), (0, 0, 100), (1, 2, 3)
print("vgu spin term:", sub(vv, lm_cross(wm, rr)))                              # expect (1.1,2,3)

# ---- Task 4: navigation -------------------------------------------------------
# Vertical descent at 10 m/s, 100 m above the site: HDOT=-10, VHORIZ=0, ABVEL=10, HCALC=100,
# RANGEDSP=100, LOOKANGL=asin(unit(R-LAND).XNB)=asin(1)=90 deg. Horizontal 25 m/s: HDOT=0, VHORIZ=25.
r1 = (0.0, 1737100.0, 0.0)
print("nav vertical: HDOT", dot(unit(r1), (0, -10, 0)), "HCALC", mag(r1) - mag(land),
      "LOOKANGL", math.degrees(math.asin(dot(unit(sub(r1, land)), (0, 1, 0)))))
print("nav horizontal over site: HDOT", dot(unit(r1), (25, 0, 0)), "VHORIZ 25, DELTAH = radar - HCALC")


# ---- Milestone 2: deorbit planner ---------------------------------------------
# Mirrors lm_plan.ks. VCRS in kOS uses the standard component formula, so plain `cross` is the
# exact mirror for orbit normals and "ahead" directions. Only the Moon-spin rotation uses lm_cross.
RIGNX, RIGNZ, VIGN = -39782.453328, -436655.657, 1690.256208


def ref_pdi_geometry(site_radius, rignx, rignz, body_radius):
    r_pdi = math.sqrt((site_radius + rignx) ** 2 + rignz ** 2)
    phi = math.degrees(math.atan2(abs(rignz), site_radius + rignx))
    return r_pdi, phi, r_pdi - body_radius


def ref_spin_rotate(vec, wm, dt):
    """Rodrigues rotation about unit(wm) by |wm|*dt radians, physical sense through lm_cross."""
    if mag(wm) == 0 or dt == 0:
        return vec
    k = unit(wm)
    th = mag(wm) * dt
    kxv = lm_cross(k, vec)
    return add(add(scale(vec, math.cos(th)), scale(kxv, math.sin(th))), scale(k, dot(k, vec) * (1 - math.cos(th))))


def ref_target_normal(n_cur, site_dir):
    d = dot(n_cur, site_dir)
    proj = sub(n_cur, scale(site_dir, d))
    return unit(proj), math.degrees(math.asin(d))


def ref_point_ahead(n_unit, u, theta_deg):
    th = math.radians(theta_deg)
    return add(scale(u, math.cos(th)), scale(unit(cross(n_unit, u)), math.sin(th)))


print()
print("---- Task 3: planner geometry ----")
g = ref_pdi_geometry(1737400.0, RIGNX, RIGNZ, 1737100.0)
print("pdi geometry (site radius 1737400, body radius 1737100): R_PDI, PHI deg, ALT_PDI =", g)
print("spin rotate (1737000,0,0) wm (0,1e-5,0) dt 1e5:", ref_spin_rotate((1737000.0, 0, 0), (0, 1e-5, 0), 1e5))
print("spin rotate (1737000,0,0) wm (0,1e-5,0) dt -1e5:", ref_spin_rotate((1737000.0, 0, 0), (0, 1e-5, 0), -1e5))
print("target normal n=(0,1,0), s=(0.6,0.8,0):", ref_target_normal((0, 1, 0), (0.6, 0.8, 0)))
print("target normal n=(0,1,0), s=unit(1,0.01,0):", ref_target_normal((0, 1, 0), unit((1, 0.01, 0))))
print("point ahead 90 / -90 / 0 / 360 from (1,0,0) about (0,1,0):",
      ref_point_ahead((0, 1, 0), (1, 0, 0), 90), ref_point_ahead((0, 1, 0), (1, 0, 0), -90),
      ref_point_ahead((0, 1, 0), (1, 0, 0), 0), ref_point_ahead((0, 1, 0), (1, 0, 0), 360))


# ---- Task 4: burns and node components ---------------------------------------
MU = 4.9028e12


def rodrigues(vec, axis_unit, angle_deg):
    """Standard rotation by angle about a unit axis (the mirror of ANGLEAXIS(angle, axis) * vec)."""
    th = math.radians(angle_deg)
    return add(add(scale(vec, math.cos(th)), scale(cross(axis_unit, vec), math.sin(th))),
               scale(axis_unit, dot(axis_unit, vec) * (1 - math.cos(th))))


def vang(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(a, b) / (mag(a) * mag(b))))))


def ref_plane_change(r, v, n_cur, n_tgt):
    angle = vang(n_cur, n_tgt)
    best = None
    for sgn in (1, -1):
        cand = rodrigues(v, unit(r), sgn * angle)
        err = mag(sub(unit(cross(r, cand)), n_tgt))
        if best is None or err < best[0]:
            best = (err, cand)
    return sub(best[1], v)


def ref_doi(r_doi, v_doi, n, r_pdi, mu):
    ra = mag(r_doi)
    if ra <= r_pdi and ra < r_pdi:
        return None
    a = (ra + r_pdi) / 2
    v_apo = math.sqrt(mu * (2 / ra - 1 / a))
    v_pdi = math.sqrt(mu * (2 / r_pdi - 1 / a))
    t_half = math.pi * math.sqrt(a ** 3 / mu)
    dv = sub(scale(unit(cross(n, r_doi)), v_apo), v_doi)
    return dv, ra, a, v_apo, v_pdi, t_half


def ref_components(dv, r, v, normal_sign=1, radial_sign=1):
    p = unit(v)
    n0 = unit(cross(r, v))
    rad0 = unit(cross(p, n0))
    return dot(dv, rad0) * radial_sign, dot(dv, n0) * normal_sign, dot(dv, p)


print()
print("---- Task 4: burns ----")
r_c = (1847100.0, 0.0, 0.0)
vc = math.sqrt(MU / 1847100.0)
v_c = (0.0, 0.0, vc)
n_c = unit(cross(r_c, v_c))
print("circular vc =", vc, " n =", n_c)
d = ref_doi(r_c, v_c, n_c, 1752500.0, MU)
print("DOI circular: dv =", d[0], "|dv| =", mag(d[0]), "RA,A,V_APO,V_PDI,T_HALF =", d[1:])
v_e = (30.0, 0.0, 1600.0)
n_e = unit(cross(r_c, v_e))
d2 = ref_doi(r_c, v_e, n_e, 1752500.0, MU)
print("DOI elliptic (v=(30,0,1600)): n =", n_e, "dv =", d2[0], "RA,A,V_APO,V_PDI,T_HALF =", d2[1:])
print("DOI at RA = r_pdi:", ref_doi((1752500.0, 0, 0), (0, 0, 1650.0), (0, -1, 0), 1752500.0, MU)[0])
n_t = rodrigues(n_c, (1, 0, 0), 2.0)
print("plane change 2 deg: n_tgt =", n_t, " dv =", ref_plane_change(r_c, v_c, n_c, n_t), "|dv| =", mag(ref_plane_change(r_c, v_c, n_c, n_t)),
      " 2 vc sin(1 deg) =", 2 * vc * math.sin(math.radians(1)))
n_t2 = rodrigues(n_c, (1, 0, 0), -2.0)
print("plane change -2 deg: n_tgt =", n_t2, " dv =", ref_plane_change(r_c, v_c, n_c, n_t2))
print("components dv=(3,-2,5) at r_c, v_e:", ref_components((3.0, -2.0, 5.0), r_c, v_e))
print("components pure prograde 5 along v_e:", ref_components(scale(unit(v_e), 5), r_c, v_e))


# ---- Milestone 3: P63 braking phase and ignition ------------------------------------------------------------
# Plain-Python mirror of lm_guidance.ks / lm_ignition.ks. Each later task adds its functions below and prints the
# numbers typed into test_p63.ks. Constants are the Apollo 11 pad loads (research note) in SI.
M3_RBRFG = (52.375308, 0.0, -3254.836061)
M3_VBRFG = (-32.271005, 0.0, -0.316992)
M3_ABRFG = (0.19022568, 0.0, -2.77502112)
M3_JBRFG_Z = -7.173e-4
M3_RIGNX, M3_RIGNZ, M3_VIGN = -39782.453328, -436655.657, 1690.256208
M3_KIGNX, M3_KIGNY, M3_KIGNV = -0.617631, -2.4770341207e-6, -410.0
M3_ZOOMTIME, M3_LEADTIME, M3_TENDBRAK = 26.0, -2.2, 62.0
M3_TRIMACCL = 3.50132708e-5 * 1e4          # m/cs^2 -> m/s^2
M3_DDUMCRIT = 0.08

# ---- Task 3: time-to-go cubic, quadratic guidance, thrust command ----------------------------------------------
# Downrange (z) components only enter the cubic. Derived from the TTF/8CL comments (LUNAR_LANDING_GUIDANCE_EQUATIONS.agc
# 489-516): with tau = TTF/8 the polynomial is 8 J tau^3 + 6 A tau^2 + (6 VG + 18 VD)/8 tau - 24 (RG - RD)/64 = 0.
# Substituting tau = TTF/64... (TTF is NEGATIVE time-to-go in Luminary) and multiplying by 64 gives, for the plain
# positive time-to-go t = -TTF:   J t^3 - 6 A t^2 + 6 (VG + 3 VD) t + 24 (RG - RD) = 0.
# Check: J = A = 0, VG = VD = v gives t = (RD - RG)/v.

def cubic(t, rg, vg, rd, vd, ad, jd):
    return jd * t**3 - 6 * ad * t**2 + 6 * (vg + 3 * vd) * t + 24 * (rg - rd)


def dcubic(t, rg, vg, rd, vd, ad, jd):
    return 3 * jd * t**2 - 12 * ad * t + 6 * (vg + 3 * vd)


def tgo_cubic(rg, vg, rd, vd, ad, jd, guess):
    """Newton from the guess. Returns (ok, tgo). ok False if no positive converged root."""
    t = guess
    if t <= 0:
        return False, guess
    for _ in range(20):
        f = cubic(t, rg, vg, rd, vd, ad, jd)
        d = dcubic(t, rg, vg, rd, vd, ad, jd)
        if d == 0 or d != d:
            return False, guess
        step = f / d
        t = t - step
        if t <= 0 or t != t:
            return False, guess
        if abs(step) < 1e-3:
            return True, t
    return False, guess


def quad_acg(rg, vg, tgo, rd, vd, ad, leadtime):
    """Quadratic guidance with the AGC's lag lead (QUADGUID, lines 546-600), plain positive time-to-go tgo.
    rho = (tgo + LEADTIME)/tgo (the 'ratio of lag-diminished TTF to TTF'); the AGC's coefficients are
        VG: 2 rho^2 - rho, RD-RG: 3 rho^2 - 2 rho, VD: 4 rho^2 - 3 rho, AD: 6 rho^2 - 6 rho + 1
    and ACG = cA AD - 6 (cVD VD + cV VG)/tgo + 12 cR (RD - RG)/tgo^2.
    rho = 1 (no lead) gives the published ACG = AD - 6 (VD + VG)/tgo + 12 (RD - RG)/tgo^2 (the plus sign in Luminary's
    comment belongs to its NEGATIVE TTF). Verified: equals the quadratic acceleration profile evaluated LEADTIME ahead."""
    if tgo < 1:
        return ad
    rho = (tgo + leadtime) / tgo
    c_v, c_r, c_vd, c_a = 2 * rho**2 - rho, 3 * rho**2 - 2 * rho, 4 * rho**2 - 3 * rho, 6 * rho**2 - 6 * rho + 1
    return tuple(c_a * ad[i] - 6 * (c_vd * vd[i] + c_v * vg[i]) / tgo + 12 * c_r * (rd[i] - rg[i]) / tgo**2
                 for i in range(len(ad)))


def limit_afc(afc, mass, fmax):
    """AMAXHORIZ: keep up and crossrange, shrink the downrange (last) component so |AFC| <= fmax/mass."""
    if mass <= 0 or fmax <= 0:
        return afc
    amax = fmax / mass
    n = mag(afc)
    if n <= amax:
        return afc
    keep = sum(c * c for c in afc[:-1])
    room = amax * amax - keep
    horiz = math.sqrt(room) if room > 0 else 0.0
    last = afc[-1]
    return afc[:-1] + (math.copysign(horiz, last),)


MOON_MU_REF, MOON_R_REF = 4.9028e12, 1737400.0      # real Moon, reference only (kOS reads the Sol Moon)


def sim_braking(mass0=15269.7, fmax=43454.7, isp=311.0, dt=1.0, leadtime=M3_LEADTIME):
    """Point-mass braking from the Apollo 11 ignition conditions (pad-load mass 15269.7 kg, FMAXPOS 43454.7 N), in the
    plane (x up, z downrange) with fixed guidance axes and the mass falling as propellant burns.
    Returns a list of (t, tgo, rg, vg, mass). Stops when tgo < 3 s."""
    rm = MOON_R_REF
    pos = (rm + M3_RIGNX, M3_RIGNZ)                      # inertial plane (X up at the site, Z downrange)
    rmag = math.hypot(*pos)
    tang = (-pos[1] / rmag, pos[0] / rmag)                # unit vector perpendicular to R, pointing toward +Z (zero radial speed)
    vel = (M3_VIGN * tang[0], M3_VIGN * tang[1])
    rd = (M3_RBRFG[0], M3_RBRFG[2]); vd = (M3_VBRFG[0], M3_VBRFG[2]); ad = (M3_ABRFG[0], M3_ABRFG[2])
    t_now, tgo, mass, hist = 0.0, 600.0, mass0, []
    while t_now < 1500:
        rg = (pos[0] - rm, pos[1]); vg = vel
        ok, tgo = tgo_cubic(rg[1], vg[1], rd[1], vd[1], ad[1], M3_JBRFG_Z, tgo)
        if not ok:
            hist.append((t_now, None, rg, vg, mass)); break
        rmag = math.hypot(*pos)
        g = (-MOON_MU_REF * pos[0] / rmag**3, -MOON_MU_REF * pos[1] / rmag**3)
        acg = quad_acg(rg, vg, tgo, rd, vd, ad, leadtime)
        afc = limit_afc((acg[0] - g[0], acg[1] - g[1]), mass, fmax)
        hist.append((t_now, tgo, rg, vg, mass))
        if tgo < 3:
            break
        acc = (afc[0] + g[0], afc[1] + g[1])
        pos = (pos[0] + vel[0] * dt + 0.5 * acc[0] * dt * dt, pos[1] + vel[1] * dt + 0.5 * acc[1] * dt * dt)
        vel = (vel[0] + acc[0] * dt, vel[1] + acc[1] * dt)
        mass -= mag(afc) * mass / (isp * 9.80665) * dt     # thrust = |AFC| * mass, mdot = F / (Isp g0)
        t_now += dt
    return hist


# ---- Task 4: throttle logic, handoff, one guidance pass ------------------------------------------------------
M3_THR_LOW, M3_THR_HIGH, M3_THR_MIN = 0.65, 0.942, 0.1


def throttle(fc, fmax, minf, prev, low=M3_THR_LOW, high=M3_THR_HIGH):
    """Throttle fraction. Apollo logic (THROTTLE_CONTROL_ROUTINES.agc 63-99) on the RO dead band (low, high):
    command >= high -> full; command <= low -> the command (not below the minimum throttle);
    in the band -> stay at full if already full (Apollo's hysteresis: leave full only when the command falls to
    low), otherwise the highest available partial thrust, low. No engine (fmax <= 0) -> previous value."""
    if fmax <= 0:
        return prev
    f = fc / fmax
    if f >= high:
        return 1.0
    if f <= low:
        return max(f, minf)
    return 1.0 if prev >= high else low


def guid_pass_ref(r, v, land, wm, mass_t, thrust_kn, mu, tgo_prev, prev_frac):
    """Mirror of guid_pass (lm_guidance.ks) for one state. mass_t in tonnes, thrust_kn in kN (what kOS gives)."""
    angterm = sub(v, lm_cross(wm, r))
    lead = -tgo_prev / 8 * 1.0                     # GAINBRAK = 1
    cg = guidance_cg(land, r, angterm, lead)
    mv = lambda m, x: tuple(dot(row, x) for row in m)
    rg = mv(cg, sub(r, land))
    vg = mv(cg, angterm)
    ok, tgo = tgo_cubic(rg[2], vg[2], M3_RBRFG[2], M3_VBRFG[2], M3_ABRFG[2], M3_JBRFG_Z, tgo_prev)
    acg = quad_acg(rg, vg, tgo, M3_RBRFG, M3_VBRFG, M3_ABRFG, M3_LEADTIME)
    rm = mag(r)
    grav = scale(r, -mu / rm**3)
    g_guid = mv(cg, grav)
    mass_kg, fmax = mass_t * 1000.0, thrust_kn * 1000.0
    afc = limit_afc(sub(acg, g_guid), mass_kg, fmax)
    thr = throttle(mag(afc) * mass_kg, fmax, M3_THR_MIN, prev_frac)
    return dict(ok=ok, tgo=tgo, acg=acg, afc=afc, thr=thr, rgu=rg, vgu=vg, handoff=tgo < M3_TENDBRAK)


# ---- Task 6: IGNALG (ignition algorithm) --------------------------------------------------------------------
def ign_ddum(rg, vg):
    """DDUM, seconds (research note, physical form of DDUMCALC). rg, vg in guidance axes (up, cross, downrange)."""
    num = ((M3_RIGNZ - rg[2]) + M3_KIGNY * rg[1] ** 2 + M3_KIGNX * (rg[0] - M3_RIGNX) + M3_KIGNV * (mag(vg) - M3_VIGN))
    return num / (vg[2] - M3_KIGNX * vg[0])


def ign_trim_dv(afc, cg):
    """Velocity correction for the zoom: unit(AFC) * ZOOMTIME * TRIMACCL, from guidance axes back to raw axes."""
    n = mag(afc)
    if n == 0:
        return (0.0, 0.0, 0.0)
    u = scale(afc, 1 / n)
    k = M3_ZOOMTIME * M3_TRIMACCL
    return tuple(k * (u[0] * cg[0][c] + u[1] * cg[1][c] + u[2] * cg[2][c]) for c in range(3))


def ign_solve_ref(predict, land, wm, mass_kg, fmax_n, mu, t_guess):
    """Mirror of ign_solve (lm_ignition.ks). predict(t) -> (r, v) raw axes. Returns dict."""
    t = t_guess
    for it in range(1, 11):
        r, v = predict(t)
        if 0.5 * mag(v) ** 2 - mu / mag(r) >= 0:
            return dict(ok=False, why="not bound")
        tgo, gp = 550.0, None
        for _ in range(3):                                   # ?GUIDSUB: three guidance passes
            gp = guid_pass_ref(r, v, land, wm, mass_kg / 1000.0, fmax_n / 1000.0, mu, tgo, 1.0)
            if not gp["ok"]:
                return dict(ok=False, why="ttf")
            tgo = gp["tgo"]
        # the guidance axes of the last pass
        angterm = sub(v, lm_cross(wm, r))
        cg = guidance_cg(land, r, angterm, -tgo / 8 * 1.0)
        trim = ign_trim_dv(gp["afc"], cg)
        v2 = add(v, trim)
        mv = lambda m, x: tuple(dot(row, x) for row in m)
        rg = mv(cg, sub(r, land))
        vg = mv(cg, sub(v2, lm_cross(wm, r)))
        dd = ign_ddum(rg, vg)
        if abs(dd) < M3_DDUMCRIT:
            out_of_plane = dot(unit(lm_cross(v, r)), land)
            return dict(ok=True, iters=it, t_conv=t, tig=t - M3_ZOOMTIME, outofpln=out_of_plane, ddum=dd)
        t += dd
        if abs(t - t_guess) > 600:
            return dict(ok=False, why="far")
    return dict(ok=False, why="iterations")


if __name__ == "__main__":
    print("--- Milestone 3 constants ---")
    print("8 * JBRFG_Z       =", 8 * M3_JBRFG_Z, "(research note: -5.7384e-3)")
    print("TRIMACCL (m/s^2)  =", M3_TRIMACCL)
    print("ullage on at TIG - ", 30 - 22.4)
    print("--- Task 3 ---")
    ok, t = tgo_cubic(0.0, 100.0, 5000.0, 100.0, 0.0, 0.0, 30.0)
    print("sanity J=A=0, VG=VD=100, RD-RG=5000: ok", ok, "tgo", t, "(expect 50)")
    hist = sim_braking()
    for h in hist[::60] + [hist[-1]]:
        print("t %6.1f tgo %s rg %s vg %s mass %.0f" % (h[0], None if h[1] is None else round(h[1], 2),
              tuple(round(c, 1) for c in h[2]), tuple(round(c, 2) for c in h[3]), h[4]))
    print("--- Task 4 ---")
    for fc, prev in ((0.99, 1.0), (0.942, 0.3), (0.80, 1.0), (0.80, 0.3), (0.65, 1.0), (0.50, 1.0), (0.05, 0.5), (0.9419, 1.0)):
        print("throttle f=%.4f prev=%.2f -> %s" % (fc, prev, throttle(fc * 43454.7, 43454.7, 0.1, prev)))
    print("throttle fmax=0 prev=0.7 ->", throttle(1000.0, 0.0, 0.1, 0.7))
    # synthetic state: site on the +X axis, ship at the Apollo 11 ignition conditions, no Moon spin lead trouble
    land = (1737400.0, 0.0, 0.0)
    r = (1737400.0 + M3_RIGNX, 0.0, M3_RIGNZ)
    v = (421.056611, 0.0, 1636.972015)
    wm = (0.0, 2.66e-6, 0.0)
    res = guid_pass_ref(r, v, land, wm, 15.2697, 43.4547, 4.9028e12, 553.0, 1.0)
    for k in ("ok", "tgo", "acg", "afc", "thr", "rgu", "vgu", "handoff"):
        print("guid_pass_ref", k, "=", res[k])
    print("--- Task 6 ---")
    print("ddum nominal            =", ign_ddum((M3_RIGNX, 0.0, M3_RIGNZ), (0.0, 0.0, M3_VIGN)))
    print("ddum 1 km short         =", ign_ddum((M3_RIGNX, 0.0, M3_RIGNZ - 1000.0), (0.0, 0.0, M3_VIGN)))
    print("ddum 2 km ahead         =", ign_ddum((M3_RIGNX, 0.0, M3_RIGNZ + 2000.0), (0.0, 0.0, M3_VIGN)))
    print("ddum high+crossrange    =", ign_ddum((M3_RIGNX + 500.0, 800.0, M3_RIGNZ), (30.0, 0.0, M3_VIGN - 15.0)))
    land = (1737400.0, 0.0, 0.0); wm = (0.0, 2.66e-6, 0.0); mu = 4.9028e12
    t0 = 1000.0
    r0 = (1737400.0 + M3_RIGNX, 0.0, M3_RIGNZ - 30000.0)
    vline = (0.0, 0.0, M3_VIGN)
    pred = lambda t: ((r0[0], r0[1], r0[2] + vline[2] * (t - t0)), vline)
    res = ign_solve_ref(pred, land, wm, 15269.7, 43454.7, mu, t0)
    print("ign_solve_ref line      =", res)
    t_true = res["t_conv"]
    print("t_guess = t_conv - 700  =", ign_solve_ref(pred, land, wm, 15269.7, 43454.7, mu, t_true - 700))
    still = lambda t: ((r0[0], r0[1], r0[2] - 20000.0), vline)
    print("stationary ship         =", ign_solve_ref(still, land, wm, 15269.7, 43454.7, mu, t0))
    print("trim dv sample          =", ign_trim_dv((-0.887762, 0.0, -2.703798), [(1,0,0),(0,-1,0),(0,0,1)]))



# ---- Milestone 4: P64 approach (plan Task 1) ----------------------------------------------------------------------
# Apollo 11 approach pad loads (research note). JAPFG* = 5.51e-4 = 8 x JAPFG_z, as for braking.
M4_RAPFG = (33.858708, 0.0, -8.1668112)
M4_VAPFG = (-1.5218664, 0.0, 0.07559040)
M4_AAPFG = (-0.07997952, 0.0, -0.1560576)
M4_JAPFG_Z = 5.51e-4 / 8
M4_TENDAPPR, M4_DELTTFAP, M4_TCGFAPPR = 12.0, -110.0, 30.0

def sim_approach(mass0=15269.7, fmax=43454.7, isp=311.0, dt=1.0, delttfap=M4_DELTTFAP, leadtime=M3_LEADTIME):
    """Braking as sim_braking, then at tgo < TENDBRAK switch to the approach targets with the plain positive time-to-go
    changed by -DELTTFAP (Luminary's TTF is negative, so adding DELTTFAP = -110 lengthens the time to go by 110 s), and fly
    on until tgo < 1 s. Same point mass, fixed guidance axes (so the CG freeze at TCGFAPPR does not appear here: with
    fixed axes there is nothing to freeze). Returns (hist, i_switch, i_end) where hist rows are (t, tgo, rg, vg, mass, phase)."""
    rm = MOON_R_REF
    pos = (rm + M3_RIGNX, M3_RIGNZ)
    rmag = math.hypot(*pos)
    tang = (-pos[1] / rmag, pos[0] / rmag)
    vel = (M3_VIGN * tang[0], M3_VIGN * tang[1])
    tgt = {"brake": (M3_RBRFG, M3_VBRFG, M3_ABRFG, M3_JBRFG_Z), "appr": (M4_RAPFG, M4_VAPFG, M4_AAPFG, M4_JAPFG_Z)}
    phase, t_now, tgo, mass, hist, i_switch, i_end = "brake", 0.0, 600.0, mass0, [], None, None
    while t_now < 2500:
        rd3, vd3, ad3, jd = tgt[phase]
        rd = (rd3[0], rd3[2]); vd = (vd3[0], vd3[2]); ad = (ad3[0], ad3[2])
        rg = (pos[0] - rm, pos[1]); vg = vel
        ok, tgo = tgo_cubic(rg[1], vg[1], rd[1], vd[1], ad[1], jd, tgo)
        if not ok:
            hist.append((t_now, None, rg, vg, mass, phase)); break
        if phase == "brake" and tgo < M3_TENDBRAK:
            phase, i_switch = "appr", len(hist)
            tgo = tgo - delttfap                      # the DELTTFAP step
            if tgo <= 0:
                hist.append((t_now, None, rg, vg, mass, phase)); break
            continue                                  # re-solve with the new targets and time-to-go
        rmag = math.hypot(*pos)
        g = (-MOON_MU_REF * pos[0] / rmag**3, -MOON_MU_REF * pos[1] / rmag**3)
        acg = quad_acg(rg, vg, tgo, rd, vd, ad, leadtime)
        afc = limit_afc((acg[0] - g[0], acg[1] - g[1]), mass, fmax)
        hist.append((t_now, tgo, rg, vg, mass, phase))
        if phase == "appr" and i_end is None and tgo < M4_TENDAPPR:
            i_end = len(hist) - 1
        if tgo < 1:
            break
        acc = (afc[0] + g[0], afc[1] + g[1])
        pos = (pos[0] + vel[0] * dt + 0.5 * acc[0] * dt * dt, pos[1] + vel[1] * dt + 0.5 * acc[1] * dt * dt)
        vel = (vel[0] + acc[0] * dt, vel[1] + acc[1] * dt)
        mass -= mag(afc) * mass / (isp * 9.80665) * dt
        t_now += dt
    return hist, i_switch, i_end


print("--- Milestone 4 Task 1 ---")
_hist, _i_sw, _i_end = sim_approach()
assert _i_sw is not None and _i_end is not None, "approach phase never reached TENDAPPR"
_sw, _en, _last = _hist[_i_sw], _hist[_i_end], _hist[-1]
print("P64 start:  t=%.0f tgo=%.1f alt=%.0f m downrange=%.0f m vg=(%.1f, %.1f) m/s" % (_sw[0], _sw[1], _sw[2][0], _sw[2][1], _sw[3][0], _sw[3][1]))
print("tgo = 12:   t=%.0f alt=%.1f m downrange=%.1f m vg=(%.2f, %.2f) m/s mass=%.0f kg" % (_en[0], _en[2][0], _en[2][1], _en[3][0], _en[3][1], _en[4]))
print("end of sim: t=%.0f tgo=%.1f rg=(%.1f, %.1f) vg=(%.2f, %.2f)" % (_last[0], _last[1], _last[2][0], _last[2][1], _last[3][0], _last[3][1]))
_p64_len = _en[0] - _sw[0]
print("P64 length to tgo=12: %.0f s" % _p64_len)
print("miss of the approach target at the end: %.1f m" % math.hypot(_last[2][0] - M4_RAPFG[0], _last[2][1] - M4_RAPFG[2]))
# Gate (plan Task 1 step 3, spec section 9): a wrong DELTTFAP sign or a non-converging switch stops the milestone.
assert 120 <= _p64_len <= 200, "P64 length outside 120-200 s: check the DELTTFAP sign"
assert _en[2][0] < 200 and abs(_en[3][1]) < 5, "at tgo=12 altitude over 200 m or downrange speed over 5 m/s"
assert math.hypot(_last[2][0] - M4_RAPFG[0], _last[2][1] - M4_RAPFG[2]) < 150, "misses the approach target by over 150 m"
_wrong, _, _ = sim_approach(delttfap=+110.0)
assert _wrong[-1][1] is None, "the opposite sign should fail (negative time-to-go)"
print("opposite DELTTFAP sign: fails at the switch, as expected")


# ---- Milestone 4 Task 3: EXNORM window vector --------------------------------------------------------------------
# Mirror of win_exnorm (lm_control.ks). Source: LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 748-815. With u = UNIT(LAND - R),
# PROJ = (u x XNB) . CGrow1 (VXV, DOT XNBPIP, CG+6), the window vector is a*CGrow2 + b*u, a = max(0, PROJMAX - PROJ),
# b = max(0, PROJ - PROJMIN), then normalised. PROJMAX = sin 25 deg = 0.42262, PROJMIN = sin 15 deg = 0.25882.
M4_PROJMAX, M4_PROJMIN = 0.42262, 0.25882


def win_exnorm_ref(land, r, xnb, cg):
    u = unit(sub(land, r))
    proj = dot(lm_cross(u, xnb), cg[1])
    a = max(0.0, M4_PROJMAX - proj)
    b = max(0.0, proj - M4_PROJMIN)
    w = add(scale(cg[2], a), scale(u, b))
    return proj, (unit(w) if mag(w) > 1e-6 else (0.0, 0.0, 0.0))


print("--- Milestone 4 Task 3 ---")
_land = (1737400.0, 0.0, 0.0)
_up = (1.0, 0.0, 0.0)
for _name, _off in (("a nearly overhead (PROJ below PROJMIN)", (3000.0, 0.0, -300.0)),
                    ("b shallow line of sight (PROJ above PROJMAX)", (1000.0, 0.0, -3000.0)),
                    ("c blend (PROJ 0.34)", (2821.5, 0.0, -1020.0)),
                    ("d directly above", (3000.0, 0.0, 0.0))):
    _r = add(_land, _off)
    _cg = guidance_cg(_land, _r, (0.0, 0.0, 0.0), 0.0)
    _proj, _w = win_exnorm_ref(_land, _r, _up, _cg)
    print("exnorm %-45s PROJ=%.6f window=(%.9f, %.9f, %.9f)" % (_name, _proj, _w[0], _w[1], _w[2]))
    print("   row2 =", _cg[2], " u =", unit(sub(_land, _r)))


# ---- Milestone 4 Task 4: landing-point redesignation (REDESIG) ----------------------------------------------------
# Mirror of redes_los (lm_p64.ks). Source: LUNAR_LANDING_GUIDANCE_EQUATIONS.agc 338-415. In real size (the source keeps the
# vectors at half size and its scale factors cancel):
#   u = UNIT(LAND - R)
#   w = u + ELINCR (u x YNB) - AZINCR YNB      (ELINCR moves the line of sight in the vertical plane, AZINCR sideways)
#   w_up = min(w_up, DEPRCRIT)                 (REDES1: the up component of w may not rise above DEPRCRIT = -0.02)
#   s = (LAND - R)_up / w_up
#   LAND' = |LAND| UNIT(R + s w)
# "up" is the guidance up axis = UNIT(LAND); the cross product is the right-handed one (lm_cross).
M4_DEPRCRIT = -0.02
M4_ELEACH, M4_AZEACH = 0.00873, 0.03491


def redes_ref(land, r, ynb, el, az):
    los = sub(land, r)
    up = unit(land)
    if (el == 0 and az == 0) or mag(los) == 0 or dot(los, up) >= 0:
        return land
    u = unit(los)
    w = sub(add(u, scale(lm_cross(u, ynb), el)), scale(ynb, az))
    w_up = dot(w, up)
    if w_up >= M4_DEPRCRIT:
        w = sub(w, scale(up, w_up - M4_DEPRCRIT))      # replace the up component by DEPRCRIT
    s = dot(los, up) / dot(w, up)
    return scale(unit(add(r, scale(w, s))), mag(land))


print("--- Milestone 4 Task 4 ---")
_land = (1737400.0, 0.0, 0.0)
_r = add(_land, (3000.0, 0.0, -6000.0))
_y = (0.0, 1.0, 0.0)
_los0 = sub(_land, _r)
for _name, _el, _az in (("el click", M4_ELEACH, 0.0), ("az click", 0.0, M4_AZEACH), ("both", M4_ELEACH, M4_AZEACH), ("down click", -M4_ELEACH, 0.0)):
    _n = redes_ref(_land, _r, _y, _el, _az)
    _turn = math.degrees(math.acos(max(-1, min(1, dot(unit(_los0), unit(sub(_n, _r)))))))
    print("redes %-10s new LAND=(%.6f, %.6f, %.6f) |LAND|=%.6f line of sight turned %.4f deg" % (_name, _n[0], _n[1], _n[2], mag(_n), _turn))
_r2 = add(_land, (100.0, 0.0, -6000.0))
_n = redes_ref(_land, _r2, _y, M4_ELEACH, 0.0)
_lu = unit(sub(_n, _r2))
print("clamped: new LAND=(%.6f, %.6f, %.6f) up component of unit(LAND'-R)=%.6f (limit -0.02 on w)" % (_n[0], _n[1], _n[2], dot(_lu, unit(_land))))
_nn = redes_ref(_land, _r2, _y, 0.0, 0.0)
print("no clicks returns LAND:", _nn == _land)


# ---- Milestone 5 Task 1: P65 and P66 (vertical phase) ---------------------------------------------------------------
# Pad loads (research note, "Vertical phase") in SI. Luminary source: LUNAR_LANDING_GUIDANCE_EQUATIONS.agc.
#   P65 (897-913): ACG = (V2FG - VGU) / TAUVERT in guidance axes (up, downrange here), then AFCCALC1: the same limit as P64.
#   P66 (948-1095, once a second): a_up = (VDGVERT - HDOT)/TAUROD; thrust acceleration along the thrust axis
#   AFC = (a_up + |g|)/cos(tilt) (1035-1047); then limited between MINFORCE/mass and MAXFORCE/mass (1076-1090).
#   LAG/TAU term (1048-1075), read together with THROTTLE_CONTROL_ROUTINES.agc 134-179: the present thrust acceleration
#   A_present = measured acceleration + FWEIGHT/MASS (FWEIGHT corrects the PIPA average for the throttle change still to
#   come), then AFC_final = AFC + LAG/TAU * (|g|/cos(tilt) - A_present). With a_net = A_present cos - |g| (the present vertical
#   acceleration) this is AFC - (LAG/TAU) a_net/cos: it predicts HDOT one engine lag ahead, HDOT + L a_net, in the rate law.
#   Kept as in the source except A_present: kOS gives the thrust now (SHIP:THRUST/mass), so FWEIGHT is not needed.
M5_V2FG = (-0.9144, 0.0)                    # (up, downrange); crossrange is zero
M5_TAUVERT, M5_RODSCALE, M5_TAUROD, M5_LAG_TAU = 10.0, 0.3048, 1.5, 0.413333
M5_MINFORCE, M5_MAXFORCE = 4360.0, 28000.0   # N (980 and 6300 lbf)


def p65_acg_ref(vg):
    """P65 commanded acceleration in (up, downrange): (V2FG - VGU)/TAUVERT."""
    return tuple((M5_V2FG[i] - vg[i]) / M5_TAUVERT for i in range(2))


def rod_throttle_ref(vdg, hdot, g_mag, cos_tilt, mass, a_present, fmin=M5_MINFORCE, fmax=M5_MAXFORCE):
    """P66 thrust-acceleration command along the thrust axis, m/s^2, after the lag term and the force limits; a_present is the thrust acceleration now.
    Returns (afc, afc_before_limits)."""
    a_up = (vdg - hdot) / M5_TAUROD
    afc_nom = (a_up + g_mag) / cos_tilt
    afc = afc_nom + M5_LAG_TAU * (g_mag / cos_tilt - a_present)
    return max(fmin / mass, min(fmax / mass, afc)), afc_nom


def sim_vertical(start, mode_p66_at=None, clicks=(), fmax=43454.7, isp=311.0, dt=0.25):
    """Point mass from `start` = (pos, vel, mass) in the plane (X up from the site, Z downrange), fixed guidance axes.
    P65 until mode_p66_at seconds (None = all P65), then P66 with VDGVERT starting at the radial velocity and `clicks` =
    ((time since P66 start, +1 or -1), ...) each adding RODSCALE to VDGVERT; the attitude is held at the last P65 direction
    (cos(tilt) = 1 here, the plane model has no attitude). Runs until the height above the site is 0. Returns the rows
    (t, mode, height, hdot, hspeed, thr_accel, vdg, mass)."""
    pos, vel, mass = start
    rm = MOON_R_REF
    t_now, mode, vdg, a_present, rows = 0.0, "P65", 0.0, 0.0, []
    clicks = sorted(clicks)
    t66 = None
    while t_now < 600:
        rmag = math.hypot(*pos)
        g = (-MOON_MU_REF * pos[0] / rmag**3, -MOON_MU_REF * pos[1] / rmag**3)
        rg = (pos[0] - rm, pos[1])
        if mode == "P65" and mode_p66_at is not None and t_now >= mode_p66_at:
            mode, vdg, t66 = "P66", vel[0], t_now
        if mode == "P65":
            acg = p65_acg_ref(vel)
            afc = limit_afc((acg[0] - g[0], acg[1] - g[1]), mass, fmax)
            acc_thr = afc
        else:
            while clicks and t_now - t66 >= clicks[0][0]:
                vdg += clicks.pop(0)[1] * M5_RODSCALE
            a_cmd, _ = rod_throttle_ref(vdg, vel[0], mag(g), 1.0, mass, a_present)
            acc_thr = (a_cmd, last_afc[1] if rows and rows[-1][1] == "P66" else afc[1])   # horizontal: held attitude, last P65 value
            afc = acc_thr
        if mode == "P65":
            last_afc = afc
        a_present = acc_thr[0]                      # the engine follows at once in this point mass (no response lag)
        rows.append((t_now, mode, rg[0], vel[0], abs(vel[1]), mag(acc_thr), vdg, mass))
        if rg[0] <= 0:
            break
        acc = (acc_thr[0] + g[0], acc_thr[1] + g[1])
        pos = (pos[0] + vel[0] * dt + 0.5 * acc[0] * dt * dt, pos[1] + vel[1] * dt + 0.5 * acc[1] * dt * dt)
        vel = (vel[0] + acc[0] * dt, vel[1] + acc[1] * dt)
        mass -= mag(acc_thr) * mass / (isp * 9.80665) * dt
        t_now += dt
    return rows


print("--- Milestone 5 Task 1 ---")
_h, _isw, _ien = sim_approach()
_e = _h[_ien]
_start = ((MOON_R_REF + _e[2][0], _e[2][1]), _e[3], _e[4])      # state at time-to-go 12 s
print("P65 start (sim):   alt=%.1f m downrange=%.1f m vg=(%.2f, %.2f) m/s mass=%.0f kg" % (_e[2][0], _e[2][1], _e[3][0], _e[3][1], _e[4]))
_flight = ((MOON_R_REF + 66.0, -15.0), (-3.0, 3.3), _e[4])        # milestone 4 flight 1 at tgo 9.2 s (spec section 12)
for _label, _st in (("simulation start", _start), ("flight-1 start", _flight)):
    _rows = sim_vertical(_st)
    _fin = _rows[-1]
    print("P65 only, %-16s: touchdown after %.1f s, hdot=%.2f m/s, horizontal speed=%.2f m/s, thr acc=%.2f m/s^2" % (_label, _fin[0], _fin[3], _fin[4], _fin[5]))
    for _t in (0, 5, 10, 20, 30, 40):
        _r = [x for x in _rows if x[0] >= _t]
        if _r and _r[0][0] <= _fin[0]:
            print("   t=%4.1f h=%6.1f hdot=%6.2f hspeed=%5.2f" % (_r[0][0], _r[0][2], _r[0][3], _r[0][4]))
    # Gate (plan Task 1 step 4): nulls the horizontal speed and reaches the surface slowly.
    assert _fin[4] < 1.0, "P65 leaves a horizontal speed over 1 m/s at touchdown"
    assert -2.0 <= _fin[3] <= 0.0, "P65 touches down faster than 2 m/s or going up"
_clicks = ((2.0, +1), (4.0, +1), (12.0, -1))                       # two slower-descent clicks, then one faster
_rows = sim_vertical(_flight, mode_p66_at=5.0, clicks=_clicks)
_fin = _rows[-1]
print("P66 from t=5 s with clicks +1 at 2 s, +1 at 4 s, -1 at 12 s (VDGVERT starts at hdot):")
for _t in (5, 6, 7, 8, 9, 10, 15, 20, 30):
    _r = [x for x in _rows if x[0] >= _t]
    if _r and _r[0][0] <= _fin[0]:
        print("   t=%5.2f mode=%s h=%6.1f hdot=%6.2f vdg=%6.2f thr_acc=%5.2f m/s^2" % (_r[0][0], _r[0][1], _r[0][2], _r[0][3], _r[0][6], _r[0][5]))
print("   touchdown after %.1f s, hdot=%.2f m/s" % (_fin[0], _fin[3]))
assert abs(_fin[3] - _fin[6]) < 0.6, "P66 does not follow the commanded rate within 0.6 m/s at touchdown"
