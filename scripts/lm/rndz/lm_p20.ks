// lm_p20.ks -- P20, rendezvous navigation (tracking and marks), and P25, preferred tracking attitude (release 1.5, stage 3). Both run in the
// core's second slot, underneath whatever programme is selected. Pure: the vehicle (lm_vehicle.ks) reads the ship and applies the attitude.
//   trk_flags_new()                                        the tracking flags the vehicle keeps (see below)
//   p20_start(prog_no, profile, flags, now_ut, snap)       prog_no 20 or 25; the programme state, or a LEXICON with "REFUSED" holding why
//   p20_step(prog, att, now_ut, ks)                        one cycle: the core's output keys and "CTL" (what to do with the attitude)
//
// Source: Luminary 210 P20-P25.agc: P20's start and range check (lines 225-315), the tracking attitude R61 and R65 (lines 1245-1376); the
// manoeuvre request R60 (R60,R62.agc; lm_r60.ks); V56 and what V37 does to the flags (EXTENDED_VERBS.agc 1074-1153, FRESH_START_AND_RESTART.agc
// 955-1039). Research: docs/superpowers/features/2026-11-26-rendezvous/research.md sections 6, 9a and 16.
//
// flags: "TRACK" (point at the CSM and ask about it), "UPDATE" (marks may be taken), "MARKS" (the count N45 shows), "REINIT" (V93: the next
// mark reads 1). The vehicle sets TRACK and UPDATE from V37 and the targeting programmes.
// att: "AUTO" (SAS off; SAS on is ATT HOLD), "NOSE" and "FACE" (the thrust axis and the crew window's direction, +Z, now), "ERR" and "RATE"
// (the error to the commanded attitude, degrees, and the turn rate, deg/s: only read during a manoeuvre), "REF" (N18's reference attitude).
// CTL: "STEER" (hold the attitude DIR, UP; FALSE: let go), "DIR" (thrust axis), "UP" (the window's direction), "HARD" (turning: no coast deadband).
// snap: P32's snapshot delegate (lm_p32.ks), and its "RADIUS" for the line-of-sight test.
//
// Every TRK_PASS_S the line of sight TRK_LEAD_S ahead is found. +Z more than TRK_NEAR_DEG off it (AUTO): the flashing V50 N18; PRO turns to the
// line of sight of that moment, then asks again, ENTR leaves it until the next pass, V34 ends tracking (the programme). Within: steered silently.
// ATT HOLD: the angles (N18) only.
//
// Departures:
//   * No rendezvous radar: no designate, search or lock displays, no state correction, N49 or large-update test. A mark is only a count: one per
//     TRK_MARK_S while both flags are set, the CSM within TRK_MARK_DEG of +Z and TRK_RANGE_M, and the Moon not in the way (the rate and the
//     Moon test are ours).
//   * The CSM's position is read where it is.
//   * ENTR at the request waits one pass; the source goes on to the next of its R65 passes.
//   * P25 tracks continuously (the source runs 7 passes at a time, again and again) and has no range check.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/rndz/lm_rndz.ks").        // rndz_range_rate, rndz_los_clear, rndz_aim_axis
RUNONCEPATH("0:/lm/burn/lm_r60.ks").         // r60_new, r60_step, r60_cdu_angles, r60_ref_in

GLOBAL P20_ALARM_RANGE IS 526.      // the CSM is further than TRK_RANGE_M
GLOBAL P20_VERB_ALARM IS 5.         // A11: flashing V05 N09 over range
GLOBAL P20_NOUN_ALARM IS 9.

// trk_flags_new: tracking off, no marks.
FUNCTION trk_flags_new {
  RETURN LEXICON("TRACK", FALSE, "UPDATE", FALSE, "MARKS", 0, "REINIT", FALSE).
}

// p20_start: refused without a usable snapshot (no CSM, or the LM not in lunar orbit). P20 starts the mark count from zero.
FUNCTION p20_start {
  PARAMETER prog_no, profile, flags, now_ut, snap.
  LOCAL seen IS snap:CALL().
  IF NOT seen["OK"] { RETURN LEXICON("REFUSED", seen["WHY"], "PROG_NO", prog_no). }
  IF prog_no = 20 {
    SET flags["MARKS"] TO 0.
    SET flags["REINIT"] TO FALSE.
  }
  // R60: the open manoeuvre request, FALSE none. CMD: the attitude steered to (LEXICON "NOSE", "FACE"), FALSE none. OVER: out of range.
  RETURN LEXICON("REFUSED", "", "PROG_NO", prog_no, "PROFILE", profile, "FLAGS", flags, "SNAP", snap, "NEXT_PASS", now_ut, "R60", FALSE,
                 "CMD", FALSE, "N18", LIST(0, 0, 0), "LAST_MARK", now_ut, "OVER", FALSE, "RANGE_NEXT", now_ut, "RANGE_TOLD", FALSE).
}

// p20_out: a quiet output.
FUNCTION p20_out {
  PARAMETER prog_no.
  RETURN LEXICON("SET_VERB", -1, "SET_NOUN", -1, "EXTRA", LEXICON(), "MSG", "", "WARN", "", "KEY_REL", FALSE, "ALT_LAMP", FALSE, "VEL_LAMP", FALSE,
                 "REQUEST", FALSE, "ALARM", 0, "BLANK", FALSE, "FLASH", FALSE, "ENDED", FALSE, "HANDOVER", FALSE, "PROG_NO", prog_no,
                 "CTL", LEXICON("STEER", FALSE, "DIR", V(0, 0, 0), "UP", V(0, 0, 0), "HARD", FALSE)).
}

// p20_idle: nothing asked and nothing steered; the next pass is at once.
FUNCTION p20_idle {
  PARAMETER prog, now_ut.
  SET prog["R60"] TO FALSE.
  SET prog["CMD"] TO FALSE.
  SET prog["NEXT_PASS"] TO now_ut.
}

// p20_aim: the attitude that puts +Z on the line of sight lead_s from now, both craft carried along their velocities: the window face goes on
// the line of sight, and the thrust axis follows it by the smallest turn. LEXICON("NOSE", "FACE").
FUNCTION p20_aim {
  PARAMETER att, seen, lead_s.
  LOCAL line IS (seen["RT"] + seen["VT"] * lead_s) - (seen["R"] + seen["V"] * lead_s).
  LOCAL sight IS line:NORMALIZED.
  RETURN LEXICON("NOSE", rndz_aim_axis(att["FACE"], sight, att["NOSE"]), "FACE", sight).
}

// p20_angles: N18 for an attitude, against the reference attitude carried into the snapshot's axes.
FUNCTION p20_angles {
  PARAMETER att, seen, aim.
  LOCAL ref IS r60_ref_in(att["REF"], seen["AX"]).
  RETURN r60_cdu_angles(ref["DIR"], ref["UP"], aim["NOSE"], aim["FACE"]).
}

// p20_range_ok: P20's range check; FALSE while the CSM is out of range. A11 (Luminary 099) shows 526 with a flashing V05 N09: V34 ends P20, PRO
// or V32 looks again. J (210) gives 526 once and looks again silently every TRK_RECHECK_S.
FUNCTION p20_range_ok {
  PARAMETER prog, range_m, now_ut, ks, out.
  LOCAL far IS range_m > TRK_RANGE_M.
  IF prog["PROFILE"] = "J" {
    IF now_ut >= prog["RANGE_NEXT"] {
      SET prog["OVER"] TO far.
      IF far {
        SET prog["RANGE_NEXT"] TO now_ut + TRK_RECHECK_S.
        IF NOT prog["RANGE_TOLD"] {
          SET prog["RANGE_TOLD"] TO TRUE.
          SET out["ALARM"] TO P20_ALARM_RANGE.
          SET out["WARN"] TO "P20: the CSM is over 400 nmi away (alarm 526). It is checked again by itself.".
        }
      }
    }
    RETURN NOT prog["OVER"].
  }
  IF prog["OVER"] {
    IF ks["TERMINATE"] {
      SET out["ENDED"] TO TRUE.
      RETURN FALSE.
    }
    IF ks["PRO"] OR ks["RECYCLE"] {          // look again: the next cycle raises the alarm afresh if it is still too far
      SET ks["PRO"] TO FALSE.
      SET prog["OVER"] TO FALSE.
      RETURN FALSE.
    }
  } ELSE {
    IF NOT far { RETURN TRUE. }
    SET prog["OVER"] TO TRUE.
    SET out["WARN"] TO "P20: the CSM is over 400 nmi away (alarm 526). PRO checks again, V34 ends P20.".
  }
  SET out["ALARM"] TO P20_ALARM_RANGE.
  SET out["REQUEST"] TO LEXICON("VERB", P20_VERB_ALARM, "NOUN", P20_NOUN_ALARM).
  RETURN FALSE.
}

// p20_marks: count a mark when one is due (P20 only). At most one per cycle, so a time warp does not add a batch.
FUNCTION p20_marks {
  PARAMETER prog, att, seen, range_m, now_ut.
  LOCAL flags IS prog["FLAGS"].
  IF prog["PROG_NO"] <> 20 OR NOT flags["UPDATE"] { RETURN. }
  IF now_ut - prog["LAST_MARK"] < TRK_MARK_S OR range_m > TRK_RANGE_M { RETURN. }
  IF VANG(att["FACE"], seen["RT"] - seen["R"]) > TRK_MARK_DEG { RETURN. }
  IF NOT rndz_los_clear(seen["R"], seen["RT"], seen["RADIUS"]) { RETURN. }
  SET prog["LAST_MARK"] TO now_ut.
  IF flags["REINIT"] {
    SET flags["REINIT"] TO FALSE.
    SET flags["MARKS"] TO 1.
  } ELSE {
    SET flags["MARKS"] TO flags["MARKS"] + 1.
  }
}

// p20_manoeuvre: one cycle of the open manoeuvre request (R60). While it asks, the attitude offered follows the line of sight, so PRO turns to
// that of its own moment.
FUNCTION p20_manoeuvre {
  PARAMETER prog, att, seen, now_ut, ks, out.
  LOCAL r60 IS prog["R60"].
  IF r60["STATE"] <> "TURNING" {
    LOCAL aim IS p20_aim(att, seen, TRK_LEAD_S).
    SET r60["BURN_DIR"] TO aim["NOSE"].
    SET r60["BURN_UP"] TO aim["FACE"].
    SET prog["N18"] TO p20_angles(att, seen, aim).
  }
  LOCAL result IS r60_step(r60, ks, att["ERR"], att["RATE"]).
  IF result["STATE"] = "TERM" {
    p20_idle(prog, now_ut).
    SET out["ENDED"] TO TRUE.
    RETURN.
  }
  IF result["STATE"] = "DONE" {
    p20_idle(prog, now_ut).
    SET prog["NEXT_PASS"] TO now_ut + TRK_PASS_S.
    RETURN.
  }
  IF result["FLASH"] {
    SET out["REQUEST"] TO LEXICON("VERB", result["VERB"], "NOUN", result["NOUN"]).
  } ELSE {
    SET prog["CMD"] TO LEXICON("NOSE", result["CMD_DIR"], "FACE", result["CMD_UP"]).
    IF result["CHANGED"] {
      SET out["SET_VERB"] TO result["VERB"].
      SET out["SET_NOUN"] TO result["NOUN"].
    }
  }
}

// p20_step: one cycle. Flags off: nothing at all. A snapshot that is not usable ends the programme.
FUNCTION p20_step {
  PARAMETER prog, att, now_ut, ks.
  LOCAL out IS p20_out(prog["PROG_NO"]).
  LOCAL seen IS prog["SNAP"]:CALL().
  IF NOT seen["OK"] {
    p20_idle(prog, now_ut).
    SET out["WARN"] TO "P" + prog["PROG_NO"] + ": " + seen["WHY"] + ".".
    SET out["ENDED"] TO TRUE.
    RETURN out.
  }
  IF NOT prog["FLAGS"]["TRACK"] {
    p20_idle(prog, now_ut).
    SET prog["OVER"] TO FALSE.
    SET prog["RANGE_NEXT"] TO now_ut.
    RETURN out.
  }
  LOCAL range_m IS rndz_range_rate(seen["R"], seen["V"], seen["RT"], seen["VT"])[0].
  IF prog["PROG_NO"] = 20 {
    IF NOT p20_range_ok(prog, range_m, now_ut, ks, out) {
      p20_idle(prog, now_ut).
      RETURN out.
    }
  }
  p20_marks(prog, att, seen, range_m, now_ut).
  IF NOT att["AUTO"] {
    p20_idle(prog, now_ut).
    SET prog["N18"] TO p20_angles(att, seen, p20_aim(att, seen, TRK_LEAD_S)).
  } ELSE IF prog["R60"]:ISTYPE("Lexicon") {
    p20_manoeuvre(prog, att, seen, now_ut, ks, out).
  } ELSE IF now_ut >= prog["NEXT_PASS"] {
    SET prog["NEXT_PASS"] TO now_ut + TRK_PASS_S.
    LOCAL aim IS p20_aim(att, seen, TRK_LEAD_S).
    SET prog["N18"] TO p20_angles(att, seen, aim).
    IF VANG(att["FACE"], aim["FACE"]) > TRK_NEAR_DEG {
      SET prog["R60"] TO r60_new(aim["NOSE"], aim["FACE"]).
      p20_manoeuvre(prog, att, seen, now_ut, ks, out).
    } ELSE {
      SET prog["CMD"] TO aim.
    }
  }
  SET out["EXTRA"]["N18"] TO prog["N18"].
  IF att["AUTO"] AND prog["CMD"]:ISTYPE("Lexicon") {
    LOCAL ctl IS out["CTL"].
    SET ctl["STEER"] TO TRUE.
    SET ctl["DIR"] TO prog["CMD"]["NOSE"].
    SET ctl["UP"] TO prog["CMD"]["FACE"].
    IF prog["R60"]:ISTYPE("Lexicon") { SET ctl["HARD"] TO prog["R60"]["STATE"] = "TURNING". }
  }
  RETURN out.
}
