// lm_site.ks -- landing-site input: validate, wrap and turn latitude/longitude into the site vector.
// The Apollo landing sites, for the planner window (lm_plan_ui.ks). Lunar Module positions, degrees N and E,
// from NASA NSSDC "Apollo Landing Site Coordinates" (https://nssdc.gsfc.nasa.gov/planetary/lunar/lunar_sites.html,
// updated 2017): planetocentric Mean Earth/Polar Axis frame, DE421, from LRO images (Wagner et al., Icarus 283, 2017).
// They are the REAL Moon's positions. Whether the Sol Moon's terrain matches is untested: the site height is read
// from the terrain at the point, so a mismatch shows up there. Apollo 11's descent constants are used for every
// site (spec 2026-11-12-site-selection-deorbit-planner-design.md section 12 and the lm_plan_ui design note).
GLOBAL APOLLO_SITES IS LIST(
  LEXICON("NAME", "Apollo 11", "LAT",  0.67416, "LNG",  23.47314),
  LEXICON("NAME", "Apollo 12", "LAT", -3.0128,  "LNG", -23.4219),
  LEXICON("NAME", "Apollo 14", "LAT", -3.64589, "LNG", -17.47194),
  LEXICON("NAME", "Apollo 15", "LAT", 26.13239, "LNG",   3.63330),
  LEXICON("NAME", "Apollo 16", "LAT", -8.9734,  "LNG",  15.5011),
  LEXICON("NAME", "Apollo 17", "LAT", 20.1911,  "LNG",  30.7723)
).

// site_wrap_lng and site_check are pure. site_resolve reads kOS (terrain height and the body position).

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_frame.ks").

// Longitude wrapped into [-180, 180). The double MOD keeps negative inputs in range
// (kOS's MOD keeps the sign of the dividend, like the C remainder).
FUNCTION site_wrap_lng {
  PARAMETER lng.
  RETURN MOD(MOD(lng + 180, 360) + 360, 360) - 180.
}

// site_check: is this latitude/longitude plausible? Latitude must be within +-90. Longitude may be
// anything up to +-360 (it is wrapped later): beyond that it is almost certainly a typo or a swapped
// argument. Legal but swapped values (23.47, 0.67) cannot be detected here; the report echoes lat/lng.
FUNCTION site_check {
  PARAMETER lat, lng.
  IF lat < -90 OR lat > 90 {
    RETURN LEXICON("VALID", FALSE, "WHY", "latitude " + lat + " is outside -90..90 degrees").
  }
  IF lng < -360 OR lng > 360 {
    RETURN LEXICON("VALID", FALSE, "WHY", "longitude " + lng + " is outside -360..360 degrees").
  }
  RETURN LEXICON("VALID", TRUE, "WHY", "").
}

// site_resolve: the validated, wrapped site and its vector from the Moon's centre.
// alt_m = -999999 means "use the terrain height at the site" (metres above sea level).
FUNCTION site_resolve {
  PARAMETER lat, lng, alt_m.
  LOCAL chk IS site_check(lat, lng).
  IF NOT chk["VALID"] { RETURN LEXICON("VALID", FALSE, "WHY", chk["WHY"]). }
  LOCAL wrapped IS site_wrap_lng(lng).
  LOCAL height IS alt_m.
  IF alt_m = -999999 { SET height TO LATLNG(lat, wrapped):TERRAINHEIGHT. }
  RETURN LEXICON("VALID", TRUE, "WHY", "", "LAT", lat, "LNG", wrapped, "ALT", height,
                 "LAND_VEC", land_vector(lat, wrapped, height)).
}
