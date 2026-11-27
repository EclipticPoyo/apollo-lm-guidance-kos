// test_p66.ks -- pad tests for release 1.3.1's P65/P66 changes (A11 set): P66 only while SAS is on, an early P66 from a ROD click in P63 or P64,
// and PRO / ENTER dropping the steering target. No flight needed (CTL_DRY).
//   RUNPATH("0:/tests/test_p66.ks").   Log: 0:/lm/logs/test_p66.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/shared/lm_frame.ks").
RUNONCEPATH("0:/shared/lm_nav.ks").
RUNONCEPATH("0:/lm/descent/lm_guidance.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/lm/lm_nouns.ks").
RUNONCEPATH("0:/lm/descent/lm_p63.ks").
RUNONCEPATH("0:/lm/descent/lm_p64.ks").
RUNONCEPATH("0:/lm/descent/lm_p65.ks").

test_begin("0:/lm/logs/test_p66.log").
SET CTL_DRY TO TRUE.

LOCAL land IS V(1737400, 0, 0).
LOCAL wm IS V(0, 0, 0).
LOCAL r_p5 IS V(1737447.1, 0, -20).
LOCAL v_p5 IS V(-0.92, 0, 2.06).

FUNCTION pp_state {
  PARAMETER now_ut, r_vec, v_vec, thrust_now.
  RETURN LEXICON("R", r_vec, "V", v_vec, "T", now_ut, "MASS", 8.095, "THRUST", 43.4547,
                 "THRUST_NOW", thrust_now, "MU", 4.9028e12, "BODY_OK", TRUE, "ALT_RADAR", 47, "XNB", V(1, 0, 0)).
}
// pp_prog: a P64-shaped programme (as P65 takes it over) with the ROD detector, as the real P63 makes it.
FUNCTION pp_prog {
  PARAMETER att_mode.
  LOCAL pr IS LEXICON("REFUSED", "", "PROG_NO", 64, "WINDOW_MODE", "UP", "TURNED", FALSE, "FORE0", V(1, 0, 0), "WIN0", V(0, 1, 0), "WCMD", V(0, 1, 0),
                 "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "ROD", rod_new(), "ROD_START", FALSE, "HIGHGATE", TRUE, "WARP", warp_new(), "ENGINE", 0,
                 "LAND", land, "WM", wm, "TIG", 1000, "BURN_DIR", V(1, 0, 0), "OUTOFPLN", 0,
                 "TGO", 60, "THR", 0.3, "GP", LEXICON(), "ZOOMED", TRUE, "ENGINE_LIT", TRUE, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", 1999.75, "HANDOFF_T", 1999, "LAST_STATE", "", "LAST_ALARM", 0, "ENDED", FALSE).
  SET pr["ATT"]["MODE"] TO att_mode.
  SET pr["GP"]["CG"] TO guidance_cg(land, r_p5, V(0, 0, 0), 0).
  RETURN pr.
}
// pp_p63: a P63 programme in the braking burn (engine lit, zoomed or not), with the new keys. LAST_ALARM is 1406 because the test state does not
// converge the time-to-go; the alarm message would otherwise replace the message under test.
FUNCTION pp_p63 {
  PARAMETER lit, zoomed, att_mode.
  LOCAL seq_lex IS seq_new(1000).
  SET seq_lex["ARMED"] TO TRUE.
  SET seq_lex["IGN_T"] TO (CHOOSE 1000 IF lit ELSE -1).
  SET seq_lex["ZOOMED"] TO zoomed.
  LOCAL pr IS LEXICON("REFUSED", "", "SEQ", seq_lex, "WINDOW_MODE", "UP", "TURNED", FALSE, "FORE0", V(1, 0, 0), "WIN0", V(0, 1, 0), "WCMD", V(0, 1, 0),
                 "ATT", att_new(), "DB", db_new(), "RAD", radar_new(), "ROD", rod_new(), "ROD_START", FALSE, "HIGHGATE", FALSE, "GO", TRUE, "LAST_REQ", FALSE, "N61_SHOWN", TRUE,
                 "WARP", warp_new(), "ENGINE", 0,
                 "LAND", land, "WM", V(0, 2.66e-6, 0), "TIG", 1000, "BURN_DIR", V(0, 0, 1), "OUTOFPLN", 0,
                 "TGO", IGN_TGO_SEED, "THR", 0, "GP", LEXICON(), "ZOOMED", zoomed, "ENGINE_LIT", lit, "ULLAGE_ON", FALSE,
                 "DV", 0, "T_LAST", 1004.75, "HANDOFF_T", -1, "LAST_STATE", "", "LAST_ALARM", 1406, "ENDED", FALSE).
  SET pr["ATT"]["MODE"] TO att_mode.
  RETURN pr.
}
LOCAL ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).

// ---- P66 only while SAS is on; the way back to P65 ----
LOCAL p5 IS p65_start(pp_prog("HOLD")).
SET p5["ROD"]["CLICKS"] TO 1.
LOCAL st IS pp_state(2000, r_p5, v_p5, 13.15).
LOCAL out IS p65_step(p5, st, nav_derived(st, land, wm), ks).
assert_true("a click with SAS on in P65 starts P66", p5["MODE"] = "P66" AND out["PROG_NO"] = 66).
SET p5["ATT"]["MODE"] TO "AUTO".
SET st TO pp_state(2000.25, r_p5, v_p5, 13.15).
SET out TO p65_step(p5, st, nav_derived(st, land, wm), ks).
assert_true("SAS off: back to P65, programme number 65, V06 N60 sent again", p5["MODE"] = "P65" AND out["PROG_NO"] = 65 AND out["SET_VERB"] = 6 AND out["SET_NOUN"] = 60).

// ---- a click while the navigation state is not valid says so and starts nothing ----
LOCAL p5v IS p65_start(pp_prog("HOLD")).
SET p5v["ROD"]["CLICKS"] TO 1.
LOCAL st_bad IS pp_state(2000, r_p5, v_p5, 13.15).
SET st_bad["BODY_OK"] TO FALSE.
LOCAL out_bad IS p65_step(p5v, st_bad, nav_derived(st_bad, land, wm), ks).
assert_true("P65: a click with no valid state stays P65 and says NO VALID STATE", p5v["MODE"] = "P65" AND out_bad["WARN"]:CONTAINS("NO VALID STATE")).
LOCAL p6v IS p65_start(pp_prog("HOLD")).
SET p6v["ROD"]["CLICKS"] TO 1.
LOCAL st_ok IS pp_state(2000, r_p5, v_p5, 13.15).
p65_step(p6v, st_ok, nav_derived(st_ok, land, wm), ks).
LOCAL vdg_before IS p6v["VDG"].
SET p6v["ROD"]["CLICKS"] TO 1.
SET st_bad TO pp_state(2000.25, r_p5, v_p5, 13.15).
SET st_bad["BODY_OK"] TO FALSE.
SET out_bad TO p65_step(p6v, st_bad, nav_derived(st_bad, land, wm), ks).
assert_true("P66: a click with no valid state keeps the commanded rate and says NO VALID STATE", p6v["MODE"] = "P66" AND p6v["VDG"] = vdg_before AND out_bad["WARN"]:CONTAINS("NO VALID STATE")).

// ---- clicks in AUTO or before the engine is lit start nothing (Review Focus 3) ----
LOCAL p3 IS pp_p63(TRUE, TRUE, "AUTO").
SET p3["ROD"]["CLICKS"] TO 1.
LOCAL st3 IS pp_state(1005, V(1739309.437, 0, -6771.996), V(-40.965, 0, 145.871), 43.4547).
LOCAL out3 IS p63_step(p3, st3, nav_derived(st3, land, p3["WM"]), ks).
assert_true("P63: a click in AUTO sets no ROD_START and is not kept", NOT p3["ROD_START"] AND p3["ROD"]["CLICKS"] = 0 AND NOT out3["HANDOVER"]).
assert_true("P63: a click in AUTO says SAS is off (warning and ROD_DROP)", out3["WARN"]:CONTAINS("SAS") AND p3["ROD_DROP"]:CONTAINS("SAS")).
LOCAL p3u IS pp_p63(FALSE, FALSE, "HOLD").
SET p3u["T_LAST"] TO 959.75.
SET p3u["ROD"]["CLICKS"] TO 1.
LOCAL r_far IS V(1737400 + RIGNX, 0, RIGNZ).
LOCAL st3u IS pp_state(960, r_far, V(421.056611, 0, 1636.972015), 0).
LOCAL out3u IS p63_step(p3u, st3u, nav_derived(st3u, land, p3u["WM"]), ks).
assert_true("P63: a click with SAS on before the engine is lit changes nothing", NOT p3u["ROD_START"] AND p3u["ROD"]["CLICKS"] = 0 AND NOT out3u["HANDOVER"]).
assert_true("P63: and says the engine is not lit (not SAS)", p3u["ROD_DROP"]:CONTAINS("ENGINE") AND NOT p3u["ROD_DROP"]:CONTAINS("SAS") AND out3u["WARN"]:CONTAINS("ENGINE")).
LOCAL p_norod IS LEXICON().
assert_true("burn_rod_start: a programme with no ROD is FALSE and untouched", NOT burn_rod_start(p_norod, TRUE) AND p_norod:LENGTH = 0).

// ---- a click with SAS on, engine lit and zoomed, starts P66 early: P63 -> P64 -> P65 in P66 ----
LOCAL p3h IS pp_p63(TRUE, TRUE, "HOLD").
SET p3h["ROD"]["CLICKS"] TO 1.
LOCAL out3h IS p63_step(p3h, st3, nav_derived(st3, land, p3h["WM"]), ks).
assert_true("P63: a click with SAS on, engine lit and zoomed sets ROD_START and hands over", p3h["ROD_START"] AND out3h["HANDOVER"] AND out3h["MSG"]:CONTAINS("ROD")).
assert_true("P63: a used click leaves ROD_DROP empty", p3h["ROD_DROP"] = "").
p64_start(p3h, 0, 23.47, 0).
assert_true("P64 start keeps the flag", p3h["ROD_START"]).
LOCAL r_a4 IS V(1739767.504, 0, -8502.208).
LOCAL v_a4 IS V(-42.2285, 0, 178.0790).
LOCAL st4 IS pp_state(2000, r_a4, v_a4, 43.4547).
LOCAL out4 IS p64_step(p3h, st4, nav_derived(st4, land, p3h["WM"]), ks).
assert_true("P64: the first step hands over to P65 at once (the approach is far from over)", out4["HANDOVER"] AND p3h["TGO"] > 100).
p65_start(p3h).
assert_true("P65 start: the early click is pending and the flag is used up", p3h["PENDING_P66"] AND NOT p3h["ROD_START"] AND p3h["MODE"] = "P65").
SET p3h["T_LAST"] TO 2999.75.
LOCAL st5 IS pp_state(3000, r_p5, v_p5, 13.15).
LOCAL d5 IS nav_derived(st5, land, wm).
LOCAL out5 IS p65_step(p3h, st5, d5, ks).
assert_true("the first valid P65 step starts P66 with VDG = HDOT", p3h["MODE"] = "P66" AND out5["PROG_NO"] = 66 AND ABS(p3h["VDG"] - d5["HDOT"]) < 1e-9).
assert_true("and the early click is not counted as a ROD click", p3h["ROD_TOTAL"] = 0 AND NOT p3h["PENDING_P66"]).

// ---- P64: clicks in AUTO change nothing; with SAS on a click hands over at once ----
LOCAL p4a IS p64_start(pp_prog("AUTO"), 0, 23.47, 0).
SET p4a["ROD"]["CLICKS"] TO 1.
LOCAL out4a IS p64_step(p4a, st4, nav_derived(st4, land, p4a["WM"]), ks).
assert_true("P64: a click in AUTO sets no ROD_START and starts no handover", NOT p4a["ROD_START"] AND NOT out4a["HANDOVER"] AND p4a["ROD"]["CLICKS"] = 0).
assert_true("P64: a click in AUTO says SAS is off", out4a["WARN"]:CONTAINS("SAS")).
LOCAL p4h IS p64_start(pp_prog("HOLD"), 0, 23.47, 0).
SET p4h["ROD"]["CLICKS"] TO 1.
LOCAL out4h IS p64_step(p4h, st4, nav_derived(st4, land, p4h["WM"]), ks).
assert_true("P64: a click with SAS on hands over to P65 in the same cycle", p4h["ROD_START"] AND out4h["HANDOVER"]).

// ---- PRO or ENTER drops the steering target ----
LOCAL p5s IS p65_start(pp_prog("AUTO")).
SET st5 TO pp_state(2000, r_p5, v_p5, 13.15).
p65_step(p5s, st5, nav_derived(st5, land, wm), ks).
assert_true("normally the deadband keeps the lock on in the burn", p5s["DB"]["LOCKED"] AND NOT p5s["STEER_OFF"]).
SET ks["PRO"] TO TRUE.
SET st5 TO pp_state(2000.25, r_p5, v_p5, 13.15).
SET out5 TO p65_step(p5s, st5, nav_derived(st5, land, wm), ks).
assert_true("PRO in P65 drops the steering target and says so", p5s["STEER_OFF"] AND NOT p5s["DB"]["LOCKED"] AND out5["WARN"]:CONTAINS("STEERING") AND NOT ks["PRO"]).
SET st5 TO pp_state(2000.5, r_p5, v_p5, 13.15).
p65_step(p5s, st5, nav_derived(st5, land, wm), ks).
assert_true("burn_shared_step does not take the lock back while it is off", p5s["STEER_OFF"] AND NOT p5s["DB"]["LOCKED"]).
LOCAL p5e IS p65_start(pp_prog("AUTO")).
SET ks["ENTER"] TO TRUE.
SET st5 TO pp_state(2000, r_p5, v_p5, 13.15).
p65_step(p5e, st5, nav_derived(st5, land, wm), ks).
SET ks["ENTER"] TO FALSE.
assert_true("ENTER in P65 does the same", p5e["STEER_OFF"] AND NOT p5e["DB"]["LOCKED"]).
assert_true("burn_steer_off is FALSE for a programme that never set it", NOT burn_steer_off(LEXICON())).
// (changing the attitude mode clears STEER_OFF: att_step reads the real SAS switch, so that is checked in flight, see archive/ksp/ksp-batch-1.3.1.md)

SET CTL_DRY TO FALSE.
test_end().
