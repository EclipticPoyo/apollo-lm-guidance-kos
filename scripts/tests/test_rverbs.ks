// test_rverbs.ks -- pad test for V83, V89 and V90 (lm/rndz/lm_rverbs.ks) and their verbs in the LM vehicle. No ship access: a canned
// snapshot, and the controls in dry-run mode.
//   RUNPATH("0:/tests/test_rverbs.ks").   Log: 0:/lm/logs/test_rverbs.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_rverbs.log").

SET CTL_DRY TO TRUE.
SET P20_LOG_PATH TO "0:/lm/logs/test_p20_events.log".     // not the session's log
GLOBAL TRV_SNAP IS LEXICON().
GLOBAL TRV_AX IS axes_mark().

// "Right" for the right-handed cases: forward (+y) x up (+x) through the project's cross product.
GLOBAL TRV_RIGHT IS lm_cross(V(0, 1, 0), V(1, 0, 0)).

// trv_world: the LM above +x flying towards +y; the CSM at csm_pos with speed csm_vel.
FUNCTION trv_world {
  PARAMETER csm_pos, csm_vel, lm_pos IS V(1800000, 0, 0), lm_vel IS V(0, 1600, 0).
  SET TRV_SNAP TO LEXICON("OK", TRUE, "WHY", "", "T", 1000, "R", lm_pos, "V", lm_vel, "RT", csm_pos, "VT", csm_vel, "AX", TRV_AX,
                          "MU", 4.9028e12, "RADIUS", 1738000).
}
FUNCTION trv_snap_now { RETURN TRV_SNAP. }
FUNCTION trv_ans {
  PARAMETER answer IS "".
  LOCAL ans IS LEXICON("PRO", FALSE, "V32", FALSE, "TERM", FALSE, "ENTER", FALSE).
  IF answer <> "" { SET ans[answer] TO TRUE. }
  RETURN ans.
}
// trv_att: nose up (+x), window forward (+y).
FUNCTION trv_att {
  PARAMETER option, auto_mode IS TRUE, err_deg IS 999, rate_deg IS 999.
  RETURN LEXICON("AUTO", auto_mode, "NOSE", V(1, 0, 0), "FACE", V(0, 1, 0), "ERR", err_deg, "RATE", rate_deg, "OPTION", option,
                 "REF", LEXICON("DIR", V(1, 0, 0), "UP", V(0, 1, 0), "AX", TRV_AX)).
}
FUNCTION trv_keys {
  RETURN keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
}

// ---- V83 ----
trv_world(V(1800000, 1000, 0), V(0, 1590, 0)).
LOCAL trv_vals IS v83_values(TRV_SNAP, V(0, 1, 0)).
assert_near("V83 range", trv_vals[0], 1000, 0.001).
assert_near("V83 range rate, closing", trv_vals[1], -10, 0.0001).
assert_true("V83 theta, the window forward, is 0", trv_vals[2] < 0.001 OR trv_vals[2] > 359.999).
assert_near("V83 theta, the window up, is 90", v83_values(TRV_SNAP, V(1, 0, 0))[2], 90, 0.001).
LOCAL out IS v83_step(TRV_SNAP, V(0, 1, 0), trv_ans()).
assert_true("V83 shows flashing V16 N54", out["VERB"] = 16 AND out["NOUN"] = 54 AND out["FLASH"] AND NOT out["ENDED"] AND out["DERIVED"]:HASKEY("N54")).
assert_true("V32 leaves it up", NOT v83_step(TRV_SNAP, V(0, 1, 0), trv_ans("V32"))["ENDED"]).
assert_true("PRO ends V83", v83_step(TRV_SNAP, V(0, 1, 0), trv_ans("PRO"))["ENDED"]).
SET out TO v83_step(LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit"), V(0, 1, 0), trv_ans()).
assert_true("CSM gone ends V83, with a warning", out["ENDED"] AND out["WARN"]:CONTAINS("no CSM")).

// ---- V90: the LM 1000 m to the CSM's right, drifting right at 2 m/s ----
trv_world(V(1800000, 0, 0), V(0, 1600, 0), V(1800000, 0, 0) + TRV_RIGHT * 1000, V(0, 1600, 0) + TRV_RIGHT * 2).
LOCAL st IS v90_new(500).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 0, trv_ans()).
assert_true("V90 shows TIG in a flashing V06 N16", out["VERB"] = 6 AND out["NOUN"] = 16 AND out["FLASH"] AND out["LOAD16"] = 500 AND out["DERIVED"]["N16"] = 500).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 700, trv_ans()).
assert_true("then leaves N16 as keyed", out["LOAD16"] = -1 AND out["NOUN"] = 16).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 700, trv_ans("V32")).
assert_true("V32 reloads TIG", out["LOAD16"] = 500).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 0, trv_ans("PRO")).
assert_true("PRO shows V06 N90", out["NOUN"] = 90 AND out["FLASH"] AND NOT out["ENDED"]).
LOCAL trv_n90 IS out["DERIVED"]["N90"].
assert_near("PRO with 0 uses now: Y", trv_n90[0], 1000, 0.01).
assert_near("N90 Y rate", trv_n90[1], 2, 0.001).
assert_near("N90 psi, the CSM to the left", trv_n90[2], 270, 0.1).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 0, trv_ans("V32")).
assert_true("V32 returns to N16 and keeps the time", out["NOUN"] = 16 AND out["LOAD16"] = -1 AND NOT out["ENDED"]).
SET out TO v90_step(st, TRV_SNAP, 900, 1000, 700, trv_ans("PRO")).
assert_true("a keyed time gives another N90", out["NOUN"] = 90 AND ABS(out["DERIVED"]["N90"][0] - 1000) > 1).
assert_true("PRO at N90 ends it", v90_step(st, TRV_SNAP, 900, 1000, 700, trv_ans("PRO"))["ENDED"]).
assert_true("V34 ends it", v90_step(v90_new(-1), TRV_SNAP, 900, 1000, 0, trv_ans("TERM"))["ENDED"]).
assert_near("no TIG offers zero", v90_new(-1)["TIG"], 0, 0).

// ---- V89: the CSM straight ahead and above ----
trv_world(V(1810000, 10000, 0), V(0, 1600, 0)).
LOCAL trv_sight IS (TRV_SNAP["RT"] - TRV_SNAP["R"]):NORMALIZED.
SET st TO v89_new(trv_snap_now@).
LOCAL ks IS trv_keys().
SET out TO v89_step(st, trv_att(1), 1000, trv_ans(), ks).
assert_true("V89 starts at a flashing V04 N12", out["VERB"] = 4 AND out["NOUN"] = 12 AND out["FLASH"] AND NOT out["CTL"]["STEER"]).
SET out TO v89_step(st, trv_att(1), 1001, trv_ans("PRO"), ks).
assert_true("PRO gives the flashing V06 N18", out["VERB"] = 6 AND out["NOUN"] = 18 AND out["FLASH"] AND out["DERIVED"]:HASKEY("N18")).
assert_vec("option 1 puts the window on the line of sight", st["AIM"]["FACE"], trv_sight, 0.001).
LOCAL trv_n18 IS out["DERIVED"]["N18"].
trv_world(V(1790000, 10000, 0), V(0, 1600, 0)).
SET out TO v89_step(st, trv_att(1), 1002, trv_ans("V32"), ks).
assert_true("recycle recomputes the angles", out["NOUN"] = 18 AND ABS(out["DERIVED"]["N18"][1] - trv_n18[1]) > 1).
SET out TO v89_step(st, trv_att(1), 1003, trv_ans("PRO"), ks).
assert_true("PRO asks for the manoeuvre", out["VERB"] = 50 AND out["NOUN"] = 18 AND out["FLASH"] AND NOT out["CTL"]["STEER"]).
SET ks["VERB"] TO 50.
SET ks["NOUN"] TO 18.
SET out TO v89_step(st, trv_att(1), 1004, trv_ans("PRO"), ks).
assert_true("PRO turns", out["VERB"] = 6 AND NOT out["FLASH"] AND out["CTL"]["STEER"] AND out["CTL"]["HARD"]).
SET out TO v89_step(st, trv_att(1, FALSE, 20, 5), 1005, trv_ans(), ks).
assert_true("ATT HOLD stops the steering and asks again", NOT out["CTL"]["STEER"] AND out["VERB"] = 50).
SET out TO v89_step(st, trv_att(1, FALSE), 1006, trv_ans("PRO"), ks).
assert_true("PRO does nothing in ATT HOLD", NOT out["CTL"]["STEER"] AND out["VERB"] = 50).
v89_step(st, trv_att(1), 1007, trv_ans("PRO"), ks).
SET out TO v89_step(st, trv_att(1, TRUE, 0.5, 0.01), 1020, trv_ans(), ks).
assert_true("after the turn it asks and holds", out["VERB"] = 50 AND out["CTL"]["STEER"] AND NOT out["CTL"]["HARD"]).
SET out TO v89_step(st, trv_att(1), 1021, trv_ans("ENTER"), ks).
assert_true("ENTR ends V89", out["ENDED"] AND NOT out["CTL"]["STEER"]).

SET st TO v89_new(trv_snap_now@).
SET trv_sight TO ((TRV_SNAP["RT"] - TRV_SNAP["R"]):NORMALIZED).
v89_step(st, trv_att(2), 1000, trv_ans(), ks).
v89_step(st, trv_att(2), 1001, trv_ans("PRO"), ks).
assert_vec("N12 2 points the nose", st["AIM"]["NOSE"], trv_sight, 0.001).
v89_step(st, trv_att(2), 1002, trv_ans("PRO"), ks).
v89_step(st, trv_att(2), 1003, trv_ans("PRO"), ks).
SET out TO v89_step(st, trv_att(2, TRUE, 20, 5), 1004, trv_ans("TERM"), ks).
assert_true("V34 mid-turn ends it and lets go", out["ENDED"] AND NOT out["CTL"]["STEER"]).
SET TRV_SNAP TO LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit").
assert_true("CSM gone ends V89", v89_step(v89_new(trv_snap_now@), trv_att(1), 1000, trv_ans(), ks)["ENDED"]).

// ---- the verbs in the vehicle ----
SET LM_VEH TO LEXICON().
SET ks TO trv_keys().
SET ks["PRIO"] TO LEXICON("VERB", 50, "NOUN", 18, "BEFORE", LIST(16, 60)).
assert_true("V82 is refused under a priority display", NOT lm_verb_82(ks) AND NOT ks["EXT"]:ISTYPE("Lexicon")).
assert_true("so are V83, V89 and V90", NOT lm_verb_83(ks) AND NOT lm_verb_89(ks) AND NOT lm_verb_90(ks)).
SET ks TO trv_keys().
SET ks["PROGRAM"] TO LEXICON("PROG_NO", 41).
assert_true("V90 is refused in P41", NOT lm_verb_90(ks)).
assert_true("V90 is allowed in P20, P32 and P00", lm_v90_allowed(LEXICON("PROG_NO", 20)) AND lm_v90_allowed(LEXICON("PROG_NO", 32)) AND lm_v90_allowed(FALSE)).
assert_true("V90 is refused in P12, P40, P47, P63 and P71", NOT lm_v90_allowed(LEXICON("PROG_NO", 12)) AND NOT lm_v90_allowed(LEXICON("PROG_NO", 40)) AND NOT lm_v90_allowed(LEXICON("PROG_NO", 47)) AND NOT lm_v90_allowed(LEXICON("PROG_NO", 63)) AND NOT lm_v90_allowed(LEXICON("PROG_NO", 71))).
SET ks["PROGRAM"] TO LEXICON("PROG_NO", 20).
assert_true("V89 is refused with P20 running", NOT lm_verb_89(ks)).
SET ks TO trv_keys().
SET LM_VEH["TRK_CTL"] TO TRUE.
SET ks["EXT"] TO LEXICON("VERB", 6, "NOUN", 18, "ANSWERS", TRUE, "END", lm_trk_release@).
LOCAL trv_untracks IS CTL_DRY_UNTRACKS.
core_ext_drop(ks).
lm_v37_hook(41).
assert_near("V37 mid-turn releases once", CTL_DRY_UNTRACKS, trv_untracks + 1, 0).
assert_true("V83, V89 and V90 are accepted", LM_VERBS:CONTAINS(83) AND LM_VERBS:CONTAINS(89) AND LM_VERBS:CONTAINS(90)).

test_end().
