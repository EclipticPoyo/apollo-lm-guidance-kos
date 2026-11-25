// lm_burnbaby.ks -- the burn engine of release 1.4: Luminary's master ignition routine BURNBABY, generalised from seq_*
// (lm/descent/lm_ignition.ks) so that P40, P41 and (in a later task) P63 share one sequence.
//
// Source: Luminary 099, BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc (BBB:), Luminary 210 file of the same name
// ("BURN,_BABY,_BURN_--_MASTER_IGNITION_ROUTINE.agc"). Table entries are the programme tables P40TABLE (BBB:88-103),
// P41TABLE (BBB:104-110) and P63TABLE (BBB:127-140); the 210 tables for these three programmes hold the same values
// (210 file, P40TABLE 2240 cs, P41TABLE -1, P63TABLE 2240 cs), so PROFILE changes no table value here. The differences of
// 210 (ZOOMFLAG, the common ZOOM, 4-jet ullage in S40.13) are not in the timings.
//
// The engine is a pure state machine with no delegates: a programme step calls bb_step each pass and acts on the keys
// it returns (display, ullage, engine, zoom, cutoff). Everything is worked out from the clock each call, so a late call
// (a time warp, a long cycle) still gives the right answer, as seq_step does. Times are dt = now - TIG, seconds.
//
//   dt < BLANK_START     COAST    (BBB:222-233: TIG-35 is scheduled from the TIG-29.9 servicer start, see below)
//   BLANK_START..END     BLANK    DSKY blanked for 5 s (TIG-35, BBB:250-264; P41 blanks through a job, P41BLANK 275-277)
//   BLANK_END..PROMPT_AT COUNT    the countdown display (TIG-30, BBB:292-296; V16 N85 is restored by TIG-30A, 286-288)
//   ULLAGE_ON            ullage on (ULLGTASK, BBB:299-305, 347-350; the table word, 2240 cs, counted from TIG-30)
//   PROMPT_AT            PROMPT   flashing V99: "enable the engine" (TIG-5, BBB:354-387); KEY REL lights
//   engine lit           BURN     from light-up (IGNITION, BBB:414-440)
//   P63 only, TIG+26     BRAKING  the throttle-up counted from the NOMINAL TIG (BBB:394-406)
//   P41 only, TIG        TIGNOW   TIGTASK/TIGNOW (BBB:542-560): the programme shows flashing V16 N85
//
// Departure that matters: the Luminary clock starts at TDEC1 = TIG - 29.9 s (P41SPOT, BBB:188-192), so the real BLANK,
// COUNT and ullage times in P40 are 0.1 s later than the whole-second ones (-34.9, -29.9, -7.5; the research note, section
// 4). The P40 table here uses those; the P63 table keeps today's -35, -30 and -7.6 (what was flown, the equivalence the
// test checks), so P63 does not change when it moves onto this engine.
// What the programme step must do itself (the engine reads nothing from the ship): (1) test ENDED first each pass; after a
// terminate (V34) mid-burn bb_step returns ENDED with ENGINE_ON still TRUE and no ENGINE_OFF (as seq_step), so the step must
// shut the engine down and give the controls back; a lost engine is the step's to detect too. (2) Slip a TIG in the past or under
// about 50 s away with alarm 1703 (p41spot) before the first bb_step; the engine would otherwise go straight to the prompt.
// (3) When s40_8 returns ALARM 1407 keep the previous TGO (it returns -1) and never steer on zero axes from s40_2_3. (4) After
// the cutoff STATE stays BURN: the step owns the post-burn display. bb_retime does not clear ENDED: start a new sequence with bb_new.
// Simplifications as seq_*: polled instead of AGC tasks, no restart protection, a PRO pressed before the prompt is ignored.

RUNONCEPATH("0:/lm/lm_constants.ks").

// bb_table_base: the table values every programme shares; the programme tables below change what differs.
FUNCTION bb_table_base {
  PARAMETER name_text, profile.
  RETURN LEXICON("NAME", name_text, "PROFILE", profile,
                 "CLOCK", TRUE, "CLOCK_BEFORE", -35, "ZOOMTIME", ZOOMTIME,
                 "BLANK_START", -34.9, "BLANK_END", -29.9,
                 "ULLAGE_ON", -7.5, "ULLAGE_OFF_AFTER_IGN", ULLAGE_OFF_AFTER_IGN,
                 "PROMPT", TRUE, "PROMPT_AT", -5,
                 "COUNT_VN", "V06N40", "PROMPT_VN", "V99N40", "BURN_VN", "V06N40",
                 "ENTR_AT_PROMPT", "GOPOST", "ZOOM", "FROM_IGNITION").
}

// bb_table_p40: P40TABLE (BBB:88-103): N40 display, ullage word 2240 cs, a V99 prompt whose ENTR is GOPOST (table word 3),
// the throttle-up counted from the actual ignition (P40IGN, BBB:472-479; skipped when NOTHROTL is set).
FUNCTION bb_table_p40 {
  PARAMETER profile.
  RETURN bb_table_base("P40", profile).
}

// bb_table_p41: P41TABLE (BBB:104-110): no ullage (word 6 is -1), no engine prompt, no zoom. CLOKTASK is not running in P41
// (BBB:268-271), so there is no N40 clock; the display is V16 N85 (TIG-30A, BBB:286-288).
FUNCTION bb_table_p41 {
  PARAMETER profile.
  LOCAL tbl IS bb_table_base("P41", profile).
  SET tbl["CLOCK"] TO FALSE.
  SET tbl["ULLAGE_ON"] TO FALSE.
  SET tbl["PROMPT"] TO FALSE.
  SET tbl["COUNT_VN"] TO "V16N85".
  SET tbl["PROMPT_VN"] TO "".
  SET tbl["BURN_VN"] TO "V16N85".
  SET tbl["ENTR_AT_PROMPT"] TO "NONE".
  SET tbl["ZOOM"] TO "NONE".
  RETURN tbl.
}

// bb_table_p63: P63TABLE (BBB:127-140): V06 N62 countdown, V99 N62 prompt (ENTR redisplays, V99RECYC), V06 N63 burn, the
// throttle-up ZOOMTIME after the NOMINAL TIG (BBB:394-406). Timings are today's seq_* ones (see the departure note above).
FUNCTION bb_table_p63 {
  PARAMETER profile.
  LOCAL tbl IS bb_table_base("P63", profile).
  SET tbl["BLANK_START"] TO -35.
  SET tbl["BLANK_END"] TO -30.
  SET tbl["ULLAGE_ON"] TO -30 + ULLAGE_START_AFTER_TIG30.
  SET tbl["COUNT_VN"] TO "V06N62".
  SET tbl["PROMPT_VN"] TO "V99N62".
  SET tbl["BURN_VN"] TO "V06N63".
  SET tbl["ENTR_AT_PROMPT"] TO "REDISPLAY".
  SET tbl["ZOOM"] TO "FROM_NOMINAL_TIG".
  RETURN tbl.
}

// bb_new: a new sequence for the table and the ignition time tig (UT). The lexicon is the state: ARMED (PRO pressed in the
// prompt), IGN_T (UT of ignition, -1 until lit), ZOOMED, ENDED, NOTHROTL (S40.13's no-throttle-up flag), CUT_UT (the timed
// cutoff, -1 none); TIGGED (P41 TIG reached), GOPOSTED (ENTR skipped the burn), CUT_DONE (the cutoff has fired).
FUNCTION bb_new {
  PARAMETER table, tig.
  RETURN LEXICON("TABLE", table, "TIG", tig, "ARMED", FALSE, "IGN_T", -1, "ZOOMED", FALSE, "ENDED", FALSE,
                 "NOTHROTL", FALSE, "CUT_UT", -1, "TIGGED", FALSE, "GOPOSTED", FALSE, "CUT_DONE", FALSE).
}

// bb_set_nothrotl: S40.13's NOTHROTL flag (burn under 95 s at the 10 percent level: no throttle-up). Only the
// FROM_IGNITION zoom (P40) honours it; P63 never has it set.
FUNCTION bb_set_nothrotl {
  PARAMETER bb, flag.
  SET bb["NOTHROTL"] TO flag.
}

// bb_cutoff_set: the timed engine-off task (ENGOFTSK; the cutoff is a timed task after a TGO computation, P4 S40.8).
// ENGINE_OFF comes on the first bb_step with now >= cut_ut, once.
FUNCTION bb_cutoff_set {
  PARAMETER bb, cut_ut.
  SET bb["CUT_UT"] TO cut_ut.
}

// bb_cutoff_clear: cancel a timed cutoff that has not fired (a new TGO that is later, or a terminate).
FUNCTION bb_cutoff_clear {
  PARAMETER bb.
  SET bb["CUT_UT"] TO -1.
}

// bb_retime: a new TIG (after a slip, alarm 1703, or a V97 ENTR retry) restarts the sequence for the same table.
// ENDED is not cleared: a terminated sequence stays terminated.
FUNCTION bb_retime {
  PARAMETER bb, new_tig.
  SET bb["TIG"] TO new_tig.
  SET bb["ARMED"] TO FALSE.
  SET bb["IGN_T"] TO -1.
  SET bb["ZOOMED"] TO FALSE.
  SET bb["CUT_UT"] TO -1.
  SET bb["TIGGED"] TO FALSE.
  SET bb["GOPOSTED"] TO FALSE.
  SET bb["CUT_DONE"] TO FALSE.
}

// bb_has_ullage: the table has an ullage time (a number); P41's is FALSE (word 6 negative, BBB:260-263).
FUNCTION bb_has_ullage {
  PARAMETER table.
  RETURN NOT table["ULLAGE_ON"]:ISTYPE("Boolean").
}

// bb_phase: the state name for the offset dt, the engine lit or not (before the PRO handling). Generalises seq_phase.
FUNCTION bb_phase {
  PARAMETER bb, dt.
  LOCAL tbl IS bb["TABLE"].
  IF bb["IGN_T"] >= 0 {
    IF bb["ZOOMED"] AND tbl["ZOOM"] = "FROM_NOMINAL_TIG" { RETURN "BRAKING". }
    RETURN "BURN".
  }
  IF dt < tbl["BLANK_START"] { RETURN "COAST". }
  IF dt < tbl["BLANK_END"] { RETURN "BLANK". }
  IF tbl["PROMPT"] {
    IF dt < tbl["PROMPT_AT"] { RETURN "COUNT". }
    RETURN "PROMPT".
  }
  IF dt < 0 { RETURN "COUNT". }
  RETURN "TIGNOW".
}

// bb_step: advance the sequence to UT now. pro_pressed is TRUE on the call PRO was pressed, terminate TRUE when the pilot
// ends the programme (V34), enter_pressed TRUE on the call ENTR (or V32) was pressed. Returns the seq_step keys:
//   STATE, VN (verb/noun to display, "" none), BLANK, ULLAGE, PROMPT, KEY_REL, ENGINE_ON, ZOOM (the one call the
//   throttle-up happens), TTOGO (seconds to TIG, negative after), ENDED
// and the new ones: GOPOST (the one call ENTR at the prompt means the post-burn skip, P40 only; the sequence ends),
// REDISPLAY (the one call ENTR at the prompt means "show it again", P63 only), ENGINE_OFF (the one call now >= CUT_UT,
// once; the engine is then not commanded on), TIG_REACHED (P41: the one call dt >= 0).
FUNCTION bb_step {
  PARAMETER bb, now, pro_pressed, terminate, enter_pressed.
  LOCAL tbl IS bb["TABLE"].
  LOCAL dt IS now - bb["TIG"].
  IF terminate { SET bb["ENDED"] TO TRUE. }
  LOCAL zoom_now IS FALSE.
  LOCAL gopost_now IS FALSE.
  LOCAL redisplay_now IS FALSE.
  LOCAL off_now IS FALSE.
  LOCAL tig_now IS FALSE.
  IF NOT bb["ENDED"] {
    LOCAL phase IS bb_phase(bb, dt).
    // PRO counts only in the prompt (BBB:408-412, ASTNFLAG). Ignition: the prompt is up, the pilot has enabled, TIG has come.
    IF phase = "PROMPT" {
      IF pro_pressed { SET bb["ARMED"] TO TRUE. }
      IF bb["ARMED"] AND dt >= 0 { SET bb["IGN_T"] TO now. }
      // ENTR at the V99 prompt: P40 table word 3 is GOPOST (skip the burn), P63 word 3 is V99RECYC (redisplay).
      IF enter_pressed AND NOT pro_pressed AND NOT bb["ARMED"] {
        IF tbl["ENTR_AT_PROMPT"] = "GOPOST" {
          SET gopost_now TO TRUE.
          SET bb["GOPOSTED"] TO TRUE.
          SET bb["ENDED"] TO TRUE.
        }
        IF tbl["ENTR_AT_PROMPT"] = "REDISPLAY" { SET redisplay_now TO TRUE. }
      }
    }
    // P41: TIG reached (TIGTASK/TIGNOW), once.
    IF NOT tbl["PROMPT"] AND NOT bb["TIGGED"] AND dt >= 0 {
      SET bb["TIGGED"] TO TRUE.
      SET tig_now TO TRUE.
    }
    // Zoom (P40ZOOM / P63ZOOM, BBB:394-406, 472-479): never before the engine is lit.
    IF bb["IGN_T"] >= 0 AND NOT bb["ZOOMED"] {
      IF tbl["ZOOM"] = "FROM_NOMINAL_TIG" AND now >= MAX(bb["TIG"] + tbl["ZOOMTIME"], bb["IGN_T"]) {
        SET bb["ZOOMED"] TO TRUE.
        SET zoom_now TO TRUE.
      }
      IF tbl["ZOOM"] = "FROM_IGNITION" AND NOT bb["NOTHROTL"] AND now >= bb["IGN_T"] + tbl["ZOOMTIME"] {
        SET bb["ZOOMED"] TO TRUE.
        SET zoom_now TO TRUE.
      }
    }
    // The timed cutoff (ENGOFTSK): once, and only on a lit engine.
    IF bb["CUT_UT"] >= 0 AND bb["IGN_T"] >= 0 AND NOT bb["CUT_DONE"] AND now >= bb["CUT_UT"] {
      SET bb["CUT_DONE"] TO TRUE.
      SET off_now TO TRUE.
    }
  }
  LOCAL phase_now IS bb_phase(bb, dt).
  IF bb["ENDED"] { SET phase_now TO "ENDED". }
  LOCAL lit IS bb["IGN_T"] >= 0 AND NOT bb["CUT_DONE"].
  // Ullage: from the table time until ULLAGE_OFF_AFTER_IGN after light-up (ULLAGOFF, BBB:530-533). None for P41, none
  // once ended or after the cutoff.
  LOCAL ullage IS FALSE.
  IF NOT bb["ENDED"] AND NOT bb["CUT_DONE"] AND bb_has_ullage(tbl) {
    IF bb["IGN_T"] >= 0 { SET ullage TO now < bb["IGN_T"] + tbl["ULLAGE_OFF_AFTER_IGN"]. }
    ELSE { SET ullage TO dt >= tbl["ULLAGE_ON"]. }
  }
  LOCAL vn_text IS "".
  IF phase_now = "COUNT" { SET vn_text TO tbl["COUNT_VN"]. }
  IF phase_now = "PROMPT" { SET vn_text TO tbl["PROMPT_VN"]. }
  IF phase_now = "BURN" OR phase_now = "BRAKING" OR phase_now = "TIGNOW" { SET vn_text TO tbl["BURN_VN"]. }
  RETURN LEXICON("STATE", phase_now, "VN", vn_text, "BLANK", phase_now = "BLANK", "ULLAGE", ullage,
                 "PROMPT", phase_now = "PROMPT", "KEY_REL", phase_now = "PROMPT", "ENGINE_ON", lit,
                 "ZOOM", zoom_now, "TTOGO", -dt, "ENDED", bb["ENDED"],
                 "GOPOST", gopost_now, "REDISPLAY", redisplay_now, "ENGINE_OFF", off_now, "TIG_REACHED", tig_now).
}

// resp_read: the three returns of a flashing display in one place (research section 2): TERM (V34), PRO, ENTR (ENTR or V32)
// and V32 alone. PRO is consumed (cleared when read). V32 is RECYCLE only: a redisplay must not fire from an ENTR that
// completed a keyed verb (as in p68_step, lm_p68.ks:34).
FUNCTION resp_read {
  PARAMETER ks.
  LOCAL pro_val IS ks["PRO"].
  SET ks["PRO"] TO FALSE.
  RETURN LEXICON("TERM", ks["TERMINATE"], "PRO", pro_val, "ENTR", ks["ENTER"] OR ks["RECYCLE"], "V32", ks["RECYCLE"]).
}
