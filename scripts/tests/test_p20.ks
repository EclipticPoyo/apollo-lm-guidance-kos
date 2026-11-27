// test_p20.ks -- pad test for P20 and P25 (lm/rndz/lm_p20.ks) and their hooks in the LM vehicle. No ship access: a canned snapshot, and the
// controls in dry-run mode.
//   RUNPATH("0:/tests/test_p20.ks").   Log: 0:/lm/logs/test_p20.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p20.log").

SET CTL_DRY TO TRUE.
SET P20_LOG_PATH TO "0:/lm/logs/test_p20_events.log".     // not the session's log
GLOBAL T20_SNAP IS LEXICON().
GLOBAL T20_AX IS axes_mark().

// t20_world: the LM above +x flying towards +y, the CSM at ahead_m along +y with the same velocity: the line of sight is +y.
FUNCTION t20_world {
  PARAMETER ahead_m IS 10000.
  SET T20_SNAP TO LEXICON("OK", TRUE, "WHY", "", "T", 0, "R", V(1850000, 0, 0), "V", V(0, 1600, 0), "RT", V(1850000, ahead_m, 0),
                          "VT", V(0, 1600, 0), "AX", T20_AX, "MU", 4.9028e12, "RADIUS", 1738000).
}
FUNCTION t20_snap_now { RETURN T20_SNAP. }
// t20_att: the nose up (+x) and the window off_deg away from the line of sight (turned towards +z).
FUNCTION t20_att {
  PARAMETER off_deg, auto_mode IS TRUE, err_deg IS 999, rate_deg IS 999.
  RETURN LEXICON("AUTO", auto_mode, "NOSE", V(1, 0, 0), "FACE", V(0, COS(off_deg), SIN(off_deg)), "ERR", err_deg, "RATE", rate_deg,
                 "REF", LEXICON("DIR", V(1, 0, 0), "UP", V(0, 1, 0), "AX", T20_AX)).
}
FUNCTION t20_keys {
  LOCAL ks IS keys_new(LIST(9, 18), LIST(5, 6, 16, 32, 33, 34, 50), LIST(0)).
  RETURN ks.
}
// t20_answer: the key state with the flashing V50 N18 shown and one answer given ("" none).
FUNCTION t20_answer {
  PARAMETER answer IS "".
  LOCAL ks IS t20_keys().
  SET ks["VERB"] TO 50.
  SET ks["NOUN"] TO 18.
  IF answer <> "" { SET ks[answer] TO TRUE. }
  RETURN ks.
}
// t20_prog: P20 (or 25) started at time 100 with tracking and updates on.
FUNCTION t20_prog {
  PARAMETER prog_no IS 20, profile IS "A11".
  t20_world().
  LOCAL flags IS trk_flags_new().
  SET flags["TRACK"] TO TRUE.
  SET flags["UPDATE"] TO TRUE.
  RETURN p20_start(prog_no, profile, flags, 100, t20_snap_now@).
}
FUNCTION t20_asks {
  PARAMETER out, verb_no, noun_no.
  IF NOT out["REQUEST"]:ISTYPE("Lexicon") { RETURN FALSE. }
  RETURN out["REQUEST"]["VERB"] = verb_no AND out["REQUEST"]["NOUN"] = noun_no.
}

// ---- starting ----
t20_world().
LOCAL t20_flags IS trk_flags_new().
SET t20_flags["MARKS"] TO 4.
SET t20_flags["REINIT"] TO TRUE.
p20_start(25, "A11", t20_flags, 0, t20_snap_now@).
assert_true("P25 leaves the mark count", t20_flags["MARKS"] = 4).
LOCAL p20a IS p20_start(20, "A11", t20_flags, 0, t20_snap_now@).
assert_true("P20 starts the count from zero", p20a["REFUSED"] = "" AND t20_flags["MARKS"] = 0 AND NOT t20_flags["REINIT"]).
SET T20_SNAP TO LEXICON("OK", FALSE, "WHY", "no CSM").
assert_true("P20 refuses without a CSM", p20_start(20, "A11", t20_flags, 0, t20_snap_now@)["REFUSED"] = "no CSM").

// ---- idle ----
LOCAL prog IS t20_prog().
SET prog["FLAGS"]["TRACK"] TO FALSE.
LOCAL out IS p20_step(prog, t20_att(40), 200, t20_keys()).
assert_true("flags off: idle", NOT out["REQUEST"]:ISTYPE("Lexicon") AND NOT out["CTL"]["STEER"] AND prog["FLAGS"]["MARKS"] = 0 AND NOT out["ENDED"]).

// ---- the manoeuvre request ----
SET prog TO t20_prog().
SET out TO p20_step(prog, t20_att(40), 100, t20_keys()).
assert_true("40 deg off asks V50 N18", t20_asks(out, 50, 18) AND NOT out["CTL"]["STEER"]).
SET out TO p20_step(prog, t20_att(40), 101, t20_answer("PRO")).
assert_true("PRO turns, static V06 N18", out["CTL"]["STEER"] AND out["CTL"]["HARD"] AND out["SET_VERB"] = 6 AND out["SET_NOUN"] = 18 AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
assert_vec("the commanded window face is on the line of sight", out["CTL"]["UP"], V(0, 1, 0), 0.001).
assert_vec("the nose stays square to it", out["CTL"]["DIR"], V(1, 0, 0), 0.001).
SET out TO p20_step(prog, t20_att(20, TRUE, 20, 5), 105, t20_keys()).
assert_true("still turning", out["CTL"]["STEER"] AND out["CTL"]["HARD"] AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET out TO p20_step(prog, t20_att(0, TRUE, 0.5, 0.01), 110, t20_keys()).
assert_true("after the turn it asks again and holds", t20_asks(out, 50, 18) AND out["CTL"]["STEER"] AND NOT out["CTL"]["HARD"]).
SET out TO p20_step(prog, t20_att(0), 111, t20_answer("ENTER")).
assert_true("ENTR leaves the manoeuvre", NOT out["REQUEST"]:ISTYPE("Lexicon") AND NOT out["ENDED"]).

SET prog TO t20_prog().
p20_step(prog, t20_att(40), 100, t20_keys()).
SET out TO p20_step(prog, t20_att(40), 101, t20_answer("ENTER")).
assert_true("ENTR then quiet", NOT out["REQUEST"]:ISTYPE("Lexicon") AND NOT out["CTL"]["STEER"]).
SET out TO p20_step(prog, t20_att(40), 104, t20_keys()).
assert_true("quiet before the next pass", NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET out TO p20_step(prog, t20_att(40), 107.1, t20_keys()).
assert_true("asks again after 6 s", t20_asks(out, 50, 18)).
SET out TO p20_step(prog, t20_att(40), 108, t20_answer("TERMINATE")).
assert_true("V34 ends", out["ENDED"] AND NOT out["CTL"]["STEER"]).

SET prog TO t20_prog().
SET out TO p20_step(prog, t20_att(10), 100, t20_keys()).
assert_true("10 deg off steers, no request", out["CTL"]["STEER"] AND NOT out["CTL"]["HARD"] AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
assert_vec("silently onto the line of sight", out["CTL"]["UP"], V(0, 1, 0), 0.001).
assert_true("N18 is given", out["EXTRA"]:HASKEY("N18")).

// ---- ATT HOLD ----
SET prog TO t20_prog().
SET out TO p20_step(prog, t20_att(40, FALSE), 100, t20_keys()).
assert_true("ATT HOLD: no request, no steering, N18 given", NOT out["REQUEST"]:ISTYPE("Lexicon") AND NOT out["CTL"]["STEER"] AND out["EXTRA"]:HASKEY("N18")).
SET prog TO t20_prog().
p20_step(prog, t20_att(40), 100, t20_keys()).
SET out TO p20_step(prog, t20_att(40, FALSE), 101, t20_keys()).
assert_true("ATT HOLD during the request drops it", NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET prog TO t20_prog().
p20_step(prog, t20_att(40), 100, t20_keys()).
p20_step(prog, t20_att(40), 101, t20_answer("PRO")).
SET out TO p20_step(prog, t20_att(20, FALSE, 20, 5), 102, t20_keys()).
assert_true("SAS in a turn stops steering", NOT out["CTL"]["STEER"] AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET out TO p20_step(prog, t20_att(40), 103, t20_keys()).
assert_true("back in AUTO it asks at once", t20_asks(out, 50, 18)).

// ---- over 400 nmi ----
SET prog TO t20_prog(20, "A11").
t20_world(800000).
SET out TO p20_step(prog, t20_att(0), 100, t20_keys()).
assert_true("A11: 526 and a flashing V05 N09", out["ALARM"] = 526 AND t20_asks(out, 5, 9) AND NOT out["CTL"]["STEER"]).
LOCAL t20_pro IS t20_keys().
SET t20_pro["PRO"] TO TRUE.
SET out TO p20_step(prog, t20_att(0), 101, t20_pro).
assert_true("A11: PRO looks again", out["ALARM"] = 0 AND NOT out["REQUEST"]:ISTYPE("Lexicon")).
SET out TO p20_step(prog, t20_att(0), 102, t20_keys()).
assert_true("A11: still too far, 526 shows again", out["ALARM"] = 526 AND t20_asks(out, 5, 9)).
LOCAL t20_term IS t20_keys().
SET t20_term["TERMINATE"] TO TRUE.
SET out TO p20_step(prog, t20_att(0), 103, t20_term).
assert_true("A11: V34 ends P20", out["ENDED"]).
SET prog TO t20_prog(20, "J").
t20_world(800000).
SET out TO p20_step(prog, t20_att(0), 100, t20_keys()).
assert_true("J: 526 once, no request", out["ALARM"] = 526 AND NOT out["REQUEST"]:ISTYPE("Lexicon") AND NOT out["CTL"]["STEER"]).
SET out TO p20_step(prog, t20_att(0), 106, t20_keys()).
assert_true("J: not again", out["ALARM"] = 0 AND NOT out["CTL"]["STEER"]).
t20_world().
SET out TO p20_step(prog, t20_att(0), 112, t20_keys()).
assert_true("J: tracks when back in range", out["CTL"]["STEER"]).
SET prog TO t20_prog(25, "A11").
t20_world(800000).
SET out TO p20_step(prog, t20_att(0), 100, t20_keys()).
assert_true("P25 has no range check", out["ALARM"] = 0 AND out["CTL"]["STEER"]).

// ---- marks ----
SET prog TO t20_prog().
p20_step(prog, t20_att(0), 100, t20_keys()).
p20_step(prog, t20_att(0), 129, t20_keys()).
assert_near("no mark yet", prog["FLAGS"]["MARKS"], 0, 0).
p20_step(prog, t20_att(0), 130, t20_keys()).
assert_near("one mark at 30 s", prog["FLAGS"]["MARKS"], 1, 0).
p20_step(prog, t20_att(0), 160, t20_keys()).
assert_near("two at 60 s", prog["FLAGS"]["MARKS"], 2, 0).
p20_step(prog, t20_att(0), 760, t20_keys()).
assert_near("one only after a 600 s jump", prog["FLAGS"]["MARKS"], 3, 0).
SET prog["FLAGS"]["REINIT"] TO TRUE.
p20_step(prog, t20_att(0), 761, t20_keys()).
assert_near("V93 keeps the count", prog["FLAGS"]["MARKS"], 3, 0).
p20_step(prog, t20_att(0), 791, t20_keys()).
assert_true("and the next mark reads 1", prog["FLAGS"]["MARKS"] = 1 AND NOT prog["FLAGS"]["REINIT"]).
SET prog["FLAGS"]["UPDATE"] TO FALSE.
p20_step(prog, t20_att(0), 900, t20_keys()).
assert_near("no mark with the update flag off", prog["FLAGS"]["MARKS"], 1, 0).
SET prog["FLAGS"]["UPDATE"] TO TRUE.
p20_step(prog, t20_att(31), 901, t20_keys()).
assert_near("no mark 31 deg off", prog["FLAGS"]["MARKS"], 1, 0).
SET T20_SNAP["RADIUS"] TO 1900000.
p20_step(prog, t20_att(0), 902, t20_keys()).
assert_near("no mark with the Moon between", prog["FLAGS"]["MARKS"], 1, 0).
SET prog TO t20_prog(25).
p20_step(prog, t20_att(0), 200, t20_keys()).
assert_near("no marks in P25", prog["FLAGS"]["MARKS"], 0, 0).

// ---- the CSM gone ----
SET prog TO t20_prog().
p20_step(prog, t20_att(10), 100, t20_keys()).
SET T20_SNAP TO LEXICON("OK", FALSE, "WHY", "no CSM in lunar orbit").
SET out TO p20_step(prog, t20_att(10), 101, t20_keys()).
assert_true("CSM gone ends it, with a warning", out["ENDED"] AND NOT out["CTL"]["STEER"] AND out["WARN"]:CONTAINS("no CSM")).

// ---- the tracking log's state word ----
SET prog TO t20_prog().
SET out TO p20_step(prog, t20_att(40), 100, t20_keys()).
assert_true("the log calls an open request by name", lm_trk_state(prog, out, TRUE, 1) = "request V50 N18").
assert_true("and ATT HOLD and a warp", lm_trk_state(prog, out, FALSE, 1) = "att hold" AND lm_trk_state(prog, out, TRUE, 10) = "time warp").
assert_true("only a rails warp stops the steering", lm_rails_rate("RAILS", 10) = 10 AND lm_rails_rate("PHYSICS", 4) = 1 AND lm_rails_rate("RAILS", 1) = 1).

// ---- the terminal's line for what runs underneath ----
assert_true("the line names the programme, its state and the marks", lm_trk_line(20, "steering", 4) = "RUNNING IN BACKGROUND: P20 steering, 4 marks.").
assert_true("one mark, and tracking off", lm_trk_line(20, "off", 1) = "RUNNING IN BACKGROUND: P20 off, 1 mark.").
assert_true("P25 has no marks, and quiet reads as waiting", lm_trk_line(25, "quiet", 3) = "RUNNING IN BACKGROUND: P25 waiting.").
assert_true("an open request and a CSM out of range are said shortly", lm_trk_line(20, "request V50 N18", 2) = "RUNNING IN BACKGROUND: P20 V50 N18, 2 marks." AND lm_trk_line(20, "over 400 nmi", 2) = "RUNNING IN BACKGROUND: P20 too far, 2 marks.").
LOCAL t20_widest IS 0.
FOR t20_word IN LIST("ending", "off", "over 400 nmi", "att hold", "time warp", "turning", "request V50 N18", "steering", "quiet") {
  SET t20_widest TO MAX(t20_widest, lm_trk_line(20, t20_word, 999):LENGTH).
}
assert_true("every state fits the terminal's 48 columns, with 999 marks", t20_widest <= 48).

// ---- the vehicle: flags, controls and verbs ----
SET LM_VEH TO LEXICON().
lm_v37_hook(20).
assert_true("V37 20 sets both flags", lm_trk_flags()["TRACK"] AND lm_trk_flags()["UPDATE"]).
LOCAL t20_ctl IS LEXICON("STEER", TRUE, "DIR", V(1, 0, 0), "UP", V(0, 1, 0), "HARD", FALSE).
LOCAL t20_tracks IS CTL_DRY_TRACKS.
LOCAL t20_untracks IS CTL_DRY_UNTRACKS.
lm_trk_apply(t20_ctl, TRUE, 1).
lm_trk_apply(t20_ctl, TRUE, 1).
assert_true("steering takes the controls once", CTL_DRY_TRACKS = t20_tracks + 1 AND LM_VEH["TRK_CTL"]).
lm_trk_apply(t20_ctl, FALSE, 1).
assert_true("SAS on lets go", CTL_DRY_UNTRACKS = t20_untracks + 1 AND NOT LM_VEH["TRK_CTL"]).
lm_trk_apply(t20_ctl, TRUE, 10).
assert_true("no steering in a time warp", CTL_DRY_TRACKS = t20_tracks + 1 AND NOT LM_VEH["TRK_CTL"]).
lm_trk_apply(t20_ctl, TRUE, 1).
lm_v37_hook(41).
assert_true("V37 41 clears the flags and lets go", NOT lm_trk_flags()["TRACK"] AND NOT lm_trk_flags()["UPDATE"] AND CTL_DRY_UNTRACKS = t20_untracks + 2).
lm_v37_hook(41).
assert_near("letting go happens once", CTL_DRY_UNTRACKS, t20_untracks + 2, 0).
lm_trk_set("MARKS", 5).
lm_p41_end(LEXICON()).
assert_near("a burn's end clears the marks", lm_trk_flags()["MARKS"], 0, 0).
lm_v37_hook(25).
lm_trk_apply(t20_ctl, TRUE, 1).
lm_p20_end(LEXICON()).
assert_true("P20's END lets go and clears the flags", NOT LM_VEH["TRK_CTL"] AND NOT lm_trk_flags()["TRACK"]).
// TRK_RUN: P20 or P25 is running (the drift gauge's condition).
SET LM_VEH["PROFILE"] TO "A11".
LOCAL t20_refused IS lm_p20_began(20, LEXICON("REFUSED", "no CSM")).
assert_true("a refused start leaves TRK_RUN off", NOT LM_VEH["TRK_RUN"] AND t20_refused["REFUSED"] = "no CSM").
lm_p20_began(20, LEXICON("REFUSED", "")).
assert_true("a start sets TRK_RUN", LM_VEH["TRK_RUN"]).
lm_p20_end(LEXICON()).
assert_true("P20's END clears TRK_RUN", NOT LM_VEH["TRK_RUN"]).
LM_VEH:REMOVE("TRK_RUN").
LM_VEH:REMOVE("PROFILE").
lm_v37_hook(20).
LOCAL t20_vks IS t20_keys().
lm_verb_56(t20_vks).
assert_true("V56 clears the flags and ends the second slot", NOT lm_trk_flags()["TRACK"] AND NOT lm_trk_flags()["UPDATE"] AND t20_vks["END_BACK"]).
lm_verb_93(t20_vks).
assert_true("V93 restarts the marks at the next one", lm_trk_flags()["REINIT"]).
LOCAL t20_table IS lm_programme_table().
assert_true("P20 and P25 are second-slot programmes", t20_table["20"]["BACKGROUND"] AND t20_table["25"]["BACKGROUND"] AND LM_PROGS:CONTAINS(20) AND LM_PROGS:CONTAINS(25)).
assert_true("V56 and V93 are accepted", LM_VERBS:CONTAINS(56) AND LM_VERBS:CONTAINS(93)).
// The SAS warning: once after P20 or P25 is keyed.
lm_v37_hook(20).
assert_true("P20 keyed with SAS on: told", lm_trk_sas_text(20, FALSE) = "P20: SAS IS ON, TURN IT OFF TO STEER.").
assert_true("told once", lm_trk_sas_text(20, FALSE) = "").
lm_v37_hook(25).
assert_true("SAS off: nothing, and nothing if SAS goes on later", lm_trk_sas_text(25, TRUE) = "" AND lm_trk_sas_text(25, FALSE) = "").
lm_v37_hook(41).
assert_true("another programme keyed: nothing", lm_trk_sas_text(20, FALSE) = "").

test_end().
