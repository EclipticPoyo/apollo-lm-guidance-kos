// lm_site_pins.ks -- landing-site pins for the map view: one labelled pin per Apollo site plus a "Custom" pin,
// the selected one in a bright colour, the rest dull. Used by the planner window (lm_plan_ui.ks).
//
// Each pin is a VECDRAW arrow standing above the site and pointing straight down at it. Things learned in the
// map-marker spike (kOS source, VectorRenderer.cs):
//  * VECDRAW positions are ship-raw coordinates, as GEOCOORDINATES:POSITION is, so the start is a delegate
//    (a small function kOS calls every frame) and the pin follows the Moon's spin and the ship's motion.
//  * Width is NOT metres: kOS draws the line Width * 0.05 * (camera distance to it) wide, so it keeps its
//    look on screen at any zoom. The length is in metres, so it is a fraction of the body radius.
//  * Pins are shown only in map view (SHOW is set from MAPVIEW on every update).
//
// The pins are a LIST: index i is APOLLO_SITES[i], the last entry is the Custom pin.

RUNONCEPATH("0:/lm/lm_site.ks").       // APOLLO_SITES

GLOBAL PINS_HEIGHT_FRAC IS 0.06.       // pin height as a fraction of the body radius (the Moon: about 104 km)
GLOBAL PINS_WIDTH IS 0.07.             // screen-relative width of the pin's line (see above)
// The label's size follows the VECDRAW Width, the line's follows Width * Scale (VectorRenderer.cs). So the
// pin is made with the bigger PINS_LABEL_WIDTH and a Scale that brings the line back to PINS_WIDTH, and the
// vector is stretched by 1/Scale so the pin keeps its height. Raise PINS_LABEL_WIDTH for bigger labels.
GLOBAL PINS_LABEL_WIDTH IS 0.14.
GLOBAL PINS_COLOR_SELECTED IS RGB(0.1, 1, 0.3).     // bright green
GLOBAL PINS_COLOR_OTHER IS RGB(0.45, 0.6, 0.8).     // dull blue-grey
GLOBAL pins_custom_geo IS LATLNG(0, 0).   // where the Custom pin points (a GEOCOORDINATES); the pin stays hidden until set

// pins_one: make one pin for a site. The parameters are copied per call, so each pin's delegates keep their own
// geo and height (a loop variable shared by several delegates would not be safe).
FUNCTION pins_one {
  PARAMETER label_text, geo, custom_pin.
  LOCAL pin_len IS PINS_HEIGHT_FRAC * SHIP:BODY:RADIUS.
  // The site's position: the fixed geo, or, for the Custom pin, whatever pins_custom_geo is now.
  LOCAL site_pos IS { IF custom_pin { RETURN pins_custom_geo:POSITION. } RETURN geo:POSITION. }.
  LOCAL site_up IS { RETURN (site_pos() - SHIP:BODY:POSITION):NORMALIZED. }.
  LOCAL pin_scale IS PINS_WIDTH / PINS_LABEL_WIDTH.      // the arrow drawn is Scale * vector long
  RETURN VECDRAW(
    { RETURN site_pos() + pin_len * site_up(). },        // start: above the site (Scale does not affect it)
    { RETURN -(pin_len / pin_scale) * site_up(). },      // vector: straight down, the arrowhead lands on the site
    PINS_COLOR_OTHER, label_text, pin_scale, FALSE, PINS_LABEL_WIDTH, TRUE, TRUE).
}

// pins_make: all the pins, hidden. The Custom pin starts at the 0,0 placeholder and is not shown
// until pins_update gives it real coordinates and Custom is selected.
FUNCTION pins_make {
  LOCAL pins IS LIST().
  FOR apollo_site IN APOLLO_SITES {
    pins:ADD(pins_one(apollo_site["NAME"], LATLNG(apollo_site["LAT"], apollo_site["LNG"]), FALSE)).
  }
  pins:ADD(pins_one("Custom", LATLNG(0, 0), TRUE)).
  RETURN pins.
}

// pins_update: call every loop pass. selected_index is the menu index (0..APOLLO_SITES:LENGTH-1 = an Apollo
// site, APOLLO_SITES:LENGTH = Custom). custom_ok says custom_lat/custom_lng are valid numbers.
// All the Apollo pins show in map view; the Custom pin shows only when Custom is selected and valid.
FUNCTION pins_update {
  PARAMETER pins, selected_index, custom_ok, custom_lat, custom_lng.
  LOCAL custom_index IS APOLLO_SITES:LENGTH.
  LOCAL on_map IS MAPVIEW.
  IF custom_ok AND ABS(custom_lat) <= 90 { SET pins_custom_geo TO LATLNG(custom_lat, custom_lng). }
  LOCAL custom_shown IS custom_ok AND ABS(custom_lat) <= 90 AND selected_index = custom_index.
  FROM { LOCAL i IS 0. } UNTIL i > custom_index STEP { SET i TO i + 1. } DO {
    IF i = selected_index { SET pins[i]:COLOR TO PINS_COLOR_SELECTED. } ELSE { SET pins[i]:COLOR TO PINS_COLOR_OTHER. }
    IF i = custom_index { SET pins[i]:SHOW TO on_map AND custom_shown. } ELSE { SET pins[i]:SHOW TO on_map. }
  }
}

// pins_clear: hide every pin (the window is closing).
FUNCTION pins_clear {
  PARAMETER pins.
  FOR pin IN pins { SET pin:SHOW TO FALSE. }
}
