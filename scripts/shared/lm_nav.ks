// lm_nav.ks -- navigation: flight data in, Luminary display quantities out (plan Task 4).
//
// nav_state is the ONLY function in the project that reads flight data from kOS.
// nav_derived is pure maths on a state, so it can be tested on the pad with made-up numbers.
//
// Ported from Luminary 099, LUNAR_LANDING_GUIDANCE_EQUATIONS.agc (line ranges per quantity below).
// Names: Luminary's R, V, LAND, WM become r_vec etc. (kOS rejects names like R and V).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").

// nav_state: a snapshot of everything the programmes need from the ship, taken once per cycle.
// A LEXICON is kOS's key -> value dictionary: state["R"] reads the entry with key "R".
FUNCTION nav_state {
  RETURN LEXICON(
    // R: position from the Moon's centre. SHIP:BODY:POSITION points ship -> Moon centre, so negate it.
    "R", -SHIP:BODY:POSITION,
    // V: velocity relative to the Moon's centre in non-rotating axes (what Luminary calls V).
    "V", SHIP:VELOCITY:ORBIT,
    "T", TIME:SECONDS,
    // MASS is in tonnes and THRUST in kN (what kOS gives), so thrust/mass is directly m/s^2.
    "MASS", SHIP:MASS,
    "THRUST", SHIP:AVAILABLETHRUST,
    // THRUST_NOW: the thrust the engines are giving at this moment (kN), for the delta-v gained display (N62).
    "THRUST_NOW", SHIP:THRUST,
    // MU: the body's gravitational parameter, read from kOS (never typed in), for the guidance's gravity term.
    "MU", SHIP:BODY:MU,
    // Only valid when we are actually over the body the constants were set up for.
    "BODY_OK", SHIP:BODY:NAME = BODY_NAME,
    // Radar altitude: height above the terrain directly below, worked out as altitude above sea level minus the terrain
    // height under the ship. Not ALT:RADAR: in flight test 2a ALT:RADAR equalled the altitude above sea level (it differed
    // from HCALC by exactly the site height, 8779 m, for the whole descent), so it is not terrain-relative at these
    // heights. The real radar's behaviour is only approximated (lm_control.ks radar_step).
    "ALT_RADAR", SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT,
    // XNB: the LM's +X axis (up, through the top hatch) as a unit vector in raw axes.
    // Mapping decided here: the lander is built like a rocket, engine at the bottom, so the kOS
    // fore vector (SHIP:FACING:FOREVECTOR) points up through the nose = LM +X. Thrust acts along -X.
    "XNB", SHIP:FACING:FOREVECTOR
  ).
}

// nav_derived: the quantities Luminary shows or uses.
//   state = nav_state() lexicon, land_vec = landing site from Moon centre, wm_vec = Moon spin (rad/s).
// If the state is not valid (wrong body) it returns VALID = false and nothing else.
FUNCTION nav_derived {
  PARAMETER state, land_vec, wm_vec.
  IF NOT state["BODY_OK"] { RETURN LEXICON("VALID", FALSE). }

  LOCAL r_vec IS state["R"].
  LOCAL v_vec IS state["V"].
  // Guidance frame, with no lead (lead = 0 until milestone 2 supplies GAINBRAK).
  LOCAL cg IS guidance_cg(land_vec, r_vec, V(0, 0, 0), 0).
  LOCAL rgu_vec IS rgu(cg, r_vec, land_vec).
  LOCAL vgu_vec IS vgu(cg, v_vec, r_vec, wm_vec).

  // LOOKANGL (line 431): angle between the line to the site and the ship's up axis.
  // The ratio is clamped to [-1, 1] and a zero vector (ship exactly at the site) gives 0,
  // so ARCSIN never sees NaN or a value out of range.
  LOCAL los_vec IS r_vec - land_vec.
  LOCAL look IS 0.
  IF los_vec:MAG > 0 {
    SET look TO ARCSIN(MAX(-1, MIN(1, VDOT(los_vec:NORMALIZED, state["XNB"])))).
  }

  // HCALC (lines 1022-1030): height above the landing-site radius.
  LOCAL hcalc IS r_vec:MAG - land_vec:MAG.

  RETURN LEXICON(
    "VALID", TRUE,
    // HDOT: rate of change of radius = unit(R) . V  (the radial part of the velocity).
    // Guarded for R = 0 (never happens in flight, but never divide by zero).
    "HDOT", CHOOSE VDOT(r_vec:NORMALIZED, v_vec) IF r_vec:MAG > 0 ELSE 0,
    // VHORIZ (lines 427, 452-455): horizontal speed over the surface = magnitude of the two
    // horizontal components of VGU (component 0 is "up", 1 and 2 are horizontal).
    "VHORIZ", SQRT(vgu_vec:Y ^ 2 + vgu_vec:Z ^ 2),
    // ABVEL: speed relative to the surface = |V - WM x R| (Luminary's ABVEL = ABVAL(VGU)).
    "ABVEL", (v_vec - lm_cross(wm_vec, r_vec)):MAG,
    // RANGEDSP (line 286): slant range to the landing site.
    "RANGEDSP", (land_vec - r_vec):MAG,
    "LOOKANGL", look,
    "HCALC", hcalc,
    "ALT_RADAR", state["ALT_RADAR"],
    // DELTAH: radar altitude minus computed altitude (shows terrain height difference).
    "DELTAH", state["ALT_RADAR"] - hcalc,
    "RGU", rgu_vec,
    "VGU", vgu_vec
  ).
}
