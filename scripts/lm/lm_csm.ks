// lm_csm.ks -- the one place the LM looks for the CSM.
//
// There are two candidates: the vessel named in the saved ascent plan (plan["CSM"]) and the vessel targeted in KSP.
// Either counts only while it orbits the landing body. Which comes first depends on who asks:
//   "NAMED_ONLY"    P12: with a name, that vessel or nothing; without one, the target.
//   "TARGET_FIRST"  the aborts: the target, else the named vessel.
//   "NAMED_FIRST"   P32 and P33: the named vessel, else the target.

RUNONCEPATH("0:/lm/lm_constants.ks").

// lm_csm_in_orbit: the vessel orbits the landing body.
FUNCTION lm_csm_in_orbit {
  PARAMETER csm_ves.
  RETURN csm_ves:BODY:NAME = BODY_NAME AND csm_ves:STATUS = "ORBITING".
}

// csm_choice: which candidate to take, "NAMED", "TARGET" or "NONE". Pure.
//   has_name   a name was saved      named_ok   that vessel exists and is in orbit      target_ok   the target is
FUNCTION csm_choice {
  PARAMETER order, has_name, named_ok, target_ok.
  LOCAL use_named IS has_name AND named_ok.
  IF order = "NAMED_ONLY" {
    IF use_named { RETURN "NAMED". }
    IF target_ok AND NOT has_name { RETURN "TARGET". }
  } ELSE IF order = "TARGET_FIRST" {
    IF target_ok { RETURN "TARGET". }
    IF use_named { RETURN "NAMED". }
  } ELSE IF order = "NAMED_FIRST" {
    IF use_named { RETURN "NAMED". }
    IF target_ok { RETURN "TARGET". }
  }
  RETURN "NONE".
}

// lm_find_csm: the CSM as a Vessel, or FALSE. plan is the saved ascent plan (anything but a Lexicon means none).
FUNCTION lm_find_csm {
  PARAMETER plan, order.
  LOCAL wanted IS "".
  IF plan:ISTYPE("Lexicon") { IF plan:HASKEY("CSM") { SET wanted TO plan["CSM"]. } }
  LOCAL named_ves IS FALSE.
  IF wanted <> "" {
    LOCAL all_targets IS LIST().
    LIST TARGETS IN all_targets.
    FOR one_target IN all_targets {
      IF NOT named_ves:ISTYPE("Vessel") AND one_target:NAME = wanted {
        IF lm_csm_in_orbit(one_target) { SET named_ves TO one_target. }
      }
    }
  }
  LOCAL aimed_ves IS FALSE.
  IF HASTARGET {
    IF TARGET:ISTYPE("Vessel") { IF lm_csm_in_orbit(TARGET) { SET aimed_ves TO TARGET. } }
  }
  LOCAL choice IS csm_choice(order, wanted <> "", named_ves:ISTYPE("Vessel"), aimed_ves:ISTYPE("Vessel")).
  IF choice = "NAMED" { RETURN named_ves. }
  IF choice = "TARGET" { RETURN aimed_ves. }
  RETURN FALSE.
}
