// lm_start.ks -- the starter: opens the planner window, and when you CLOSE it, starts the LM computer.
//
//   RUN start.          (from 0:/, through the one-line stub start.ks)
//   RUNPATH("0:/lm/lm_start.ks").
//
// 1. lm_plan_ui.ks opens the planner window and waits there: pick a site, press PLAN, fly the nodes if you like.
//    That script only returns when you press CLOSE, so "done planning" = CLOSE.
// 2. lm_main.ks then starts with no arguments, so it uses the site in the saved plan (0:/lm/plan.json).
//    With no plan it falls back to the point under the next perilune, as when it is started by hand.
// After CLOSE it prints one line on the plan (none, PDI passed, stale, or OK); it only warns.
// Nothing is flown or warped here. Fly the burns, then start the descent with V37 E 63 E in the DSKY.
// If you only want to start the computer (plan already flown), close the planner window straight away.

RUNPATH("0:/lm/lm_plan_ui.ks").
// Check the saved plan and say so on the terminal; this only warns, main starts in every case (you may only want
// the DSKY). The ls_ prefix keeps these names clear of the planner's and main's globals. KerboScript's AND does not
// skip its right side, so the checks are nested.
LOCAL ls_plan IS plan_read(PLAN_PLAN_FILE).
LOCAL ls_ok IS FALSE.
IF ls_plan:ISTYPE("Lexicon") {
  IF ls_plan:HASKEY("T_PDI") AND ls_plan:HASKEY("SITE_LAT") AND ls_plan:HASKEY("SITE_LNG") { SET ls_ok TO TRUE. }
}
IF NOT ls_ok {
  PRINT "START: no saved plan. The DSKY will run, but P63 will refuse until you plan.".
} ELSE IF ls_plan["T_PDI"] < TIME:SECONDS {
  PRINT "START: the saved plan's PDI has passed. P63 will refuse; plan again.".
} ELSE IF plan_is_stale(ls_plan, TIME:SECONDS, PLAN_MAX_AGE_S) {
  PRINT "START: the saved plan is over " + ROUND(PLAN_MAX_AGE_S / 3600, 1) + " h old (the Moon has turned). Plan again.".
} ELSE {
  PRINT "START: plan OK. Site " + ROUND(ls_plan["SITE_LAT"], 2) + ", " + ROUND(ls_plan["SITE_LNG"], 2)
      + ", PDI in " + ROUND(ls_plan["T_PDI"] - TIME:SECONDS) + " s.".
}

RUNPATH("0:/lm/lm_main.ks").
