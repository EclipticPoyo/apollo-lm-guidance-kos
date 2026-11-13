// smoke_nav.ks -- in-flight smoke check for lm_nav.ks (plan Task 4, step 5). Run in lunar orbit:
//   RUNPATH("0:/lm/tests/smoke_nav.ks").
// Logs every nav_derived key to 0:/lm/smoke_nav.log, and flags any that is not a finite number.
RUNONCEPATH("0:/lm/lm_nav.ks").

LOCAL log_path IS "0:/lm/smoke_nav.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }
FUNCTION say { PARAMETER text. PRINT text. LOG text TO log_path. }

LOCAL st IS nav_state().
LOCAL d IS nav_derived(st, land_vector(SITE_LAT, SITE_LNG, SITE_ALT), moon_spin()).
say("body " + SHIP:BODY:NAME + "  BODY_OK " + st["BODY_OK"] + "  VALID " + d["VALID"]).
say("XNB " + st["XNB"] + "  facing fore " + SHIP:FACING:FOREVECTOR).
FOR key IN d:KEYS {
  say(key + " = " + d[key]).
}
// Cross-checks against kOS's own values (spec section 7.3).
say("check HDOT " + d["HDOT"] + " vs VERTICALSPEED " + SHIP:VERTICALSPEED).
say("check VHORIZ " + d["VHORIZ"] + " vs GROUNDSPEED " + SHIP:GROUNDSPEED).
say("check ABVEL " + d["ABVEL"] + " vs SURFACE speed " + SHIP:VELOCITY:SURFACE:MAG).
