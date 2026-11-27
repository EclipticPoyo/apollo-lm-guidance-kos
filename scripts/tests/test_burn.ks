// test_burn.ks -- pad tests for the burn maths (lm/burn/lm_burn_s.ks, release 1.4). No flight needed.
//   RUNPATH("0:/tests/test_burn.ks").
// Expected values come from scripts/tests/reference_burn.py. Results go to 0:/lm/logs/test_burn.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/burn/lm_burn_s.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_burn.log").

// The DOI case of reference_burn.py: a circular orbit 60 nmi up (r = 1737400 + 111120 m), position +X, velocity +Z, retrograde 23.1 m/s.
LOCAL mu_b IS 4.9028e12.
LOCAL r_doi IS V(1848520, 0, 0).
LOCAL v_doi IS V(0, 0, 1628.5834302711191).
LOCAL dv_doi IS V(0, 0, -23.1).

// ---- constants ----
assert_near("DPSVEX", DPSVEX, 2955.88868, 1e-6).
assert_near("TDECAY_S", TDECAY_S, -0.38, 1e-9).
assert_near("BURN_THRUST_10PCT_N", BURN_THRUST_10PCT_N, 4671, 1e-9).

// ---- S40.1 ----
LOCAL s1 IS s40_1(dv_doi).
assert_vec("S40.1 UT is the unit vector", s1["UT"], V(0, 0, -1), 1e-12).
assert_near("S40.1 VGMAG", s1["VGMAG"], 23.1, 1e-9).
assert_vec("S40.1 VG is the delta-V", s1["VG"], dv_doi, 1e-12).
assert_near("S40.1 DELVREF starts at zero", s1["DELVREF"]:MAG, 0, 0).

// ---- S40.2,3 ----
// Source gate (re-read in Luminary099 P40-P47.agc 825-860): X = UT, Y = unit(UT x RTIG), Z = X x Y. For the DOI (a retrograde burn
// in a prograde orbit) that gives X = -V-hat, Y = unit(X x R) = the orbit normal (R x V direction) and Z = X x Y = -R-hat, which is
// the window side (+Z) TOWARDS the Moon. The research note says "face up"; that is NOT what the source arithmetic gives, so this test
// asserts the source result and the question is open (see the task report).
LOCAL ax IS s40_2_3(s1["UT"], r_doi, v_doi).
assert_vec("S40.2,3 DOI: X = -V-hat", ax["X"], V(0, 0, -1), 1e-12).
assert_vec("S40.2,3 DOI: Y = unit(X x R)", ax["Y"], V(0, -1, 0), 1e-12).
assert_vec("S40.2,3 DOI: Z = X x Y", ax["Z"], VCRS(ax["X"], ax["Y"]), 1e-12).
assert_vec("S40.2,3 DOI: Z value (-R-hat)", ax["Z"], V(-1, 0, 0), 1e-12).
assert_near("S40.2,3 X.Y = 0", VDOT(ax["X"], ax["Y"]), 0, 1e-12).
assert_near("S40.2,3 Y.Z = 0", VDOT(ax["Y"], ax["Z"]), 0, 1e-12).
assert_near("S40.2,3 X.Z = 0", VDOT(ax["X"], ax["Z"]), 0, 1e-12).
assert_near("S40.2,3 Z is a unit vector", ax["Z"]:MAG, 1, 1e-12).
// RTIG almost parallel to UT: Y falls back to unit(UT x VTIG) = (0, -1, 0); the first formula would give (0, 0, 1).
LOCAL ax_b IS s40_2_3(V(1, 0, 0), V(1e6, 100, 0), v_doi).
assert_vec("S40.2,3 fallback Y = unit(UT x VTIG)", ax_b["Y"], V(0, -1, 0), 1e-12).
assert_true("S40.2,3 fallback Y differs from unit(UT x RTIG)", (ax_b["Y"] - V(0, 0, 1)):MAG > 1).
assert_near("S40.2,3 fallback Y is a unit vector", ax_b["Y"]:MAG, 1, 1e-12).
assert_vec("S40.2,3 fallback Z = X x Y", ax_b["Z"], V(0, 0, -1), 1e-12).
assert_near("S40.2,3 fallback is orthogonal", VDOT(ax_b["Y"], ax_b["Z"]), 0, 1e-12).

// ---- S40.13 (mass 15000 kg; the 099 ullage correction is 4 s of 2 jets = 0.237 m/s) ----
LOCAL b23 IS s40_13(15000, 23, "A11").
assert_near("S40.13 |VG| 23 BURN_S", b23["BURN_S"], 73.09818026118603, 0.05).
assert_true("S40.13 |VG| 23 NOTHROTL", b23["NOTHROTL"]).
assert_true("S40.13 |VG| 23 not an impulse burn", NOT b23["IMPULSE"]).
assert_true("S40.13 |VG| 29 NOTHROTL", s40_13(15000, 29, "A11")["NOTHROTL"]).
assert_near("S40.13 |VG| 29 BURN_S", s40_13(15000, 29, "A11")["BURN_S"], 92.36600299721687, 0.05).
assert_true("S40.13 |VG| 31 throttles up (NOTHROTL clear)", NOT s40_13(15000, 31, "A11")["NOTHROTL"]).
assert_near("S40.13 |VG| 31 BURN_S", s40_13(15000, 31, "A11")["BURN_S"], 98.78861057589381, 0.05).
LOCAL b2 IS s40_13(15000, 2, "A11").
assert_true("S40.13 |VG| 2 IMPULSE", b2["IMPULSE"]).
assert_near("S40.13 |VG| 2 BURN_S", b2["BURN_S"], 5.660800685078142, 0.05).
assert_true("S40.13 099 |VG| 2: NOTHROTL clear (099 leaves it clear under 6 s)", NOT b2["NOTHROTL"]).
LOCAL b0 IS s40_13(15000, 0, "A11").
assert_near("S40.13 |VG| 0 BURN_S, no error", b0["BURN_S"], 0, 0).
assert_true("S40.13 |VG| 0 IMPULSE", b0["IMPULSE"]).
LOCAL bj IS s40_13(15000, 2, "J").
assert_true("S40.13 J |VG| 2: NOTHROTL (210 sets it under 6 s)", bj["NOTHROTL"]).
assert_true("S40.13 J |VG| 2 IMPULSE", bj["IMPULSE"]).
assert_near("S40.13 J |VG| 2 BURN_S (6.5 s of 4 jets)", bj["BURN_S"], 3.9467351744808394, 0.05).
assert_near("S40.13 DOI delta-V burn time", s40_13(15000, 23.1, "A11")["BURN_S"], 73.41931064011989, 0.05).

// ---- S40.8 (one pass measures 0.62 m/s: 15 t at the 10 percent level; VG is along the measured delta-V) ----
LOCAL ref_dir IS V(0, 0, -1).
LOCAL r8 IS s40_8(ref_dir * 5.62, ref_dir * 0.62, TDECAY_S, DPSVEX).
assert_vec("S40.8 VG is VGPREV - DELVREF", r8["VG"], ref_dir * 5, 1e-12).
assert_near("S40.8 TGO for 5 m/s", r8["TGO"], 15.735390817194977, 0.05).
assert_true("S40.8 5 m/s: no alarm, steering on", r8["ALARM"] = 0 AND r8["STEER"] AND NOT r8["IMPULSE"]).
LOCAL r8s IS s40_8(ref_dir * 4.5, ref_dir * 1.5, TDECAY_S, DPSVEX).
assert_near("S40.8 TGO for 3 m/s at 1.5 m/s a pass", r8s["TGO"], 3.6179701535986126, 0.05).
assert_true("S40.8 under 4 s: STEER false", NOT r8s["STEER"]).
assert_true("S40.8 under 4 s: IMPULSE (the cutoff runs on the timer)", r8s["IMPULSE"]).
LOCAL r8a IS s40_8(ref_dir * (-5), ref_dir * 0.62, TDECAY_S, DPSVEX).
assert_true("S40.8 VG opposite the measured delta-V: alarm 1407", r8a["ALARM"] = 1407).
assert_true("S40.8 alarm: TGO not computed (-1), steering goes on, no impulse", r8a["TGO"] < 0 AND r8a["STEER"] AND NOT r8a["IMPULSE"]).
assert_true("S40.8 nothing measured yet: alarm 1407, no divide", s40_8(ref_dir * 5, V(0, 0, 0), TDECAY_S, DPSVEX)["ALARM"] = 1407).

// ---- S41.1: VG in body axes (+X = fore) ----
LOCAL face_a IS LOOKDIRUP(V(0, 0, -1), V(1, 0, 0)).
LOCAL body_a IS s41_1(V(0, 0, -7), face_a).
assert_vec("S41.1 a vector along the nose is all +X", body_a, V(7, 0, 0), 1e-4).
// kOS rotations (LOOKDIRUP, inverse) are single precision: errors near 1e-6.
LOCAL body_b IS s41_1(V(3, -4, 5), face_a).
assert_near("S41.1 keeps the length", body_b:MAG, V(3, -4, 5):MAG, 1e-4).
assert_near("S41.1 X is the part along the nose", body_b:X, -5, 1e-4).
// Luminary's other two: +Y the crew's right, +Z out of the windows (WINDOW_AXIS says which face of the ship that is).
LOCAL tb_window IS WINDOW_AXIS.
SET WINDOW_AXIS TO "BOTTOM".
assert_vec("S41.1 window underneath: towards it is +Z, starboard +Y",
    s41_1(face_a:STARVECTOR * 2 - face_a:TOPVECTOR * 3, face_a), V(0, 2, 3), 1e-4).
SET WINDOW_AXIS TO "TOP".
assert_vec("S41.1 window on top: towards it is +Z, port +Y",
    s41_1(face_a:TOPVECTOR * 3 - face_a:STARVECTOR * 2, face_a), V(0, 2, 3), 1e-4).
SET WINDOW_AXIS TO tb_window.

// ---- P41SPOT ----
LOCAL sp_a IS p41spot(1030, 1000).
assert_true("P41SPOT TIG 30 s ahead slips", sp_a["SLIPPED"] AND sp_a["ALARM"] = 1703).
assert_near("P41SPOT slipped TIG = now + 49.9", sp_a["TIG"], 1049.9, 1e-9).
LOCAL sp_b IS p41spot(1080, 1000).
assert_true("P41SPOT TIG 80 s ahead is unchanged", NOT sp_b["SLIPPED"] AND sp_b["ALARM"] = 0 AND sp_b["TIG"] = 1080).
LOCAL sp_c IS p41spot(900, 1000).
assert_true("P41SPOT TIG in the past slips", sp_c["SLIPPED"] AND sp_c["ALARM"] = 1703).
assert_near("P41SPOT past TIG = now + 49.9", sp_c["TIG"], 1049.9, 1e-9).
assert_true("P41SPOT TIG 60 s ahead is not slipped", NOT p41spot(1060, 1000)["SLIPPED"]).

// ---- P30 apsides ----
// Reference value 59.99999 nmi apolune and 5.31220 nmi perilune for the 60 nmi orbit. (The real Apollo 11 DOI gave HA 57.2 and HP 8.5
// from its slightly elliptical 61.5 x 56.6 nmi orbit, so those two numbers are not reproduced from a circular one.)
LOCAL ap IS p30_apsides(r_doi, v_doi, dv_doi, mu_b, 1737400).
assert_near("apsides DOI apolune nmi", ap["APO_M"] / 1852, 59.99999999999711, 0.01).
assert_near("apsides DOI perilune nmi", ap["PERI_M"] / 1852, 5.31220071647529, 0.01).
assert_true("apsides: the DOI burn is at apolune (apolune = the orbit altitude)", ABS(ap["APO_M"] - 111120) < 1).
LOCAL ap_esc IS p30_apsides(r_doi, v_doi, V(0, 0, 2000), mu_b, 1737400).
assert_near("apsides: escape orbit apolune is the 9999.9 nmi cap", ap_esc["APO_M"] / 1852, 9999.9, 1e-6).
assert_true("apsides: perigee is below the cap", ap_esc["PERI_M"] < APSIDE_CAP_NM * 1852).

// ---- P30 MGA ----
assert_near("MGA: a burn along Y is 90", p30_mga(V(0, 1, 0), V(0, 1, 0)), 90, 1e-9).
assert_near("MGA: a burn perpendicular to Y is 0", p30_mga(V(0, 0, 1), V(0, 1, 0)), 0, 1e-9).
assert_near("MGA: a negative angle has one revolution added", p30_mga(V(0, -1, 0), V(0, 1, 0)), 270, 1e-9).
assert_near("MGA: rounding noise below zero shows 0, not 360", p30_mga(V(0, -1e-7, 1), V(0, 1, 0)), 0, 1e-9).
assert_near("MGA: 30 degrees", p30_mga(V(0, 0.5, 0.8660254037844386), V(0, 1, 0)), 30, 1e-9).

// ---- S40.13, ascent engine (210 P40-P47.agc:1035-1135): the three regimes ----
LOCAL a3 IS s40_13_aps(4700, 3, "J").
assert_near("S40.13 APS J |VG| 3: the smallest burn", a3["BURN_S"], 0.281418, 0.001).
assert_true("S40.13 APS J |VG| 3: impulse, no throttle-up", a3["IMPULSE"] AND a3["NOTHROTL"]).
LOCAL a12 IS s40_13_aps(4700, 12, "J").
assert_near("S40.13 APS J |VG| 12", a12["BURN_S"], 2.972210, 0.001).
assert_true("S40.13 APS J |VG| 12: impulse", a12["IMPULSE"]).
LOCAL a25 IS s40_13_aps(4700, 25, "J").
assert_near("S40.13 APS J |VG| 25", a25["BURN_S"], 6.804239, 0.001).
assert_true("S40.13 APS J |VG| 25: steered", NOT a25["IMPULSE"]).
assert_near("S40.13 APS A11 |VG| 25 (2-jet ullage, the smaller K1)", s40_13_aps(4700, 25, "A11")["BURN_S"], 7.318492, 0.001).
assert_near("S40.13 APS: a delta-V the ullage covers gives no burn time", s40_13_aps(4700, 1, "J")["BURN_S"], 0, 0).

// ---- S40.8 on a velocity to gain already brought up to date (the aim point) ----
LOCAL r8t IS s40_8_tgo(ref_dir * 5, ref_dir * 0.62, 2, TDECAY_S, DPSVEX).
assert_near("S40.8 TGO from the new VG", r8t["TGO"], 15.735390817194977, 0.05).
assert_vec("S40.8 TGO keeps the VG it is given", r8t["VG"], ref_dir * 5, 1e-12).
assert_true("S40.8 TGO: VG against the delta-V is alarm 1407", s40_8_tgo(ref_dir * (-5), ref_dir * 0.62, 2, TDECAY_S, DPSVEX)["ALARM"] = 1407).

// ---- the aim point (S40.1B, S40.9): the case of reference_rndz.py ----
LOCAL ta IS V(905666.125472, 0, -1579536.104075).
LOCAL tva IS V(1423.5500524, 0, 816.2276615).
LOCAL aim IS V(586581.134, 0, 1752982.819).
LOCAL at_tig IS s40_aim(ta, tva, aim, 2575.3417, mu_b, FALSE).
assert_true("aim: solved (" + at_tig["WHY"] + ")", at_tig["OK"]).
assert_vec("aim: velocity to gain at TIG", at_tig["VG"], V(7.47049, 0, 0.43098), 0.001).
assert_vec("aim: nothing left once it is gained", s40_aim(ta, tva + at_tig["VG"], aim, 2575.3417, mu_b, FALSE)["VG"], V(0, 0, 0), 0.001).
LOCAL early IS conic_kepler(ta, tva, -30, mu_b).
assert_vec("aim: 30 s before TIG", s40_aim(early["R"], early["V"], aim, 2605.3417, mu_b, FALSE)["VG"], V(7.32165, 0, 0.56143), 0.001).
LOCAL late IS s40_aim(ta, tva, aim, -5, mu_b, FALSE).
assert_true("aim: an intercept time gone by fails with no velocity to gain", NOT late["OK"] AND late["VG"]:MAG = 0).

test_end().
