// lm_rverbs.ks -- the rendezvous extended verbs V83, V89 and V90 (release 1.5, stage 3). Pure: the vehicle (lm_vehicle.ks) reads the ship,
// raises each as an answering extended display (core/dsky_core.ks) and applies the attitude.
//   v83_values(seen, face_vec)                              the N54 list: range (m), range rate (m/s), theta (degrees)
//   v83_step(seen, face_vec, ans)                           one cycle of V83
//   v90_new(tig_s) / v90_step(st, seen, clock_zero, now_ut, keyed_s, ans)
//   v89_new(snap)  / v89_step(st, att, now_ut, ans, ks)     as above, with "CTL" (as P20's, lm_p20.ks)
// Each step returns the answering display's lexicon: "DERIVED", "VERB", "NOUN", "FLASH", "ENDED", "MSG".
// seen: P32's snapshot (lm_p32.ks); one that is not usable ends the display with a message.
//
// Source: Luminary 210 R31.agc (V83), P34-P35,_P74-P75.agc lines 1683-1756 (R36, V90), R63.agc (V89). Research:
// docs/superpowers/features/2026-11-26-rendezvous/research.md section 16.
//   V83  V16 N54, recomputed continuously; PRO or V34 ends it.
//   V90  flashing V06 N16 loaded with TIG (V32 reloads it, V25 N16 changes it); PRO, a zero time meaning now, gives the flashing V06 N90 of
//        both craft at that time; there PRO or V34 end it and V32 goes back to N16.
//   V89  flashing V04 N12 (00003, 00001: +Z; V22 N12 E 2 E for +X, any value but 1); PRO takes the line of sight a minute ahead and shows the
//        flashing V06 N18 (V32 again, V34 ends); PRO there is the manoeuvre (R60, lm_r60.ks), after which the routine ends.
//
// Departures: the CSM is read where it is. V90 back from N90 keeps the time keyed. SAS on (ATT HOLD) during V89's manoeuvre brings its request
// back, and PRO does nothing while SAS is on.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/rndz/lm_p20.ks").         // p20_aim's maths (lm_rndz.ks) and r60 (lm_r60.ks)

// rv_out: an answering display's output, flashing.
FUNCTION rv_out {
  PARAMETER verb_no, noun_no.
  RETURN LEXICON("DERIVED", LEXICON(), "VERB", verb_no, "NOUN", noun_no, "FLASH", TRUE, "ENDED", FALSE, "MSG", "", "WARN", "").
}

// rv_lost: the end of a routine whose snapshot is no longer usable.
FUNCTION rv_lost {
  PARAMETER out, name, why.
  SET out["ENDED"] TO TRUE.
  SET out["WARN"] TO name + " ended: " + why + ".".
  RETURN out.
}

// ---- V83, range, range rate and theta ---------------------------------------------------------------------------

// v83_values: face_vec is the +Z axis (the crew window's direction).
FUNCTION v83_values {
  PARAMETER seen, face_vec.
  LOCAL sight IS rndz_range_rate(seen["R"], seen["V"], seen["RT"], seen["VT"]).
  RETURN LIST(sight[0], sight[1], rndz_theta(seen["R"], seen["V"], face_vec)).
}

FUNCTION v83_step {
  PARAMETER seen, face_vec, ans.
  LOCAL out IS rv_out(16, 54).
  IF NOT seen["OK"] { RETURN rv_lost(out, "V83", seen["WHY"]). }
  SET out["DERIVED"]["N54"] TO v83_values(seen, face_vec).
  SET out["ENDED"] TO ans["PRO"] OR ans["TERM"].
  RETURN out.
}

// ---- V90, out-of-plane at a time --------------------------------------------------------------------------------

// v90_new: tig_s the stored time of ignition, mission clock seconds (-1 none: zero is offered, which means now).
FUNCTION v90_new {
  PARAMETER tig_s.
  RETURN LEXICON("PHASE", "TIME", "TIG", MAX(0, tig_s), "LOADED", FALSE, "N90", LIST(0, 0, 0)).
}

// keyed_s: N16 as it stands (mission clock seconds). "LOAD16" in the output is a time the vehicle is to put in N16, -1 none.
FUNCTION v90_step {
  PARAMETER st, seen, clock_zero, now_ut, keyed_s, ans.
  LOCAL out IS rv_out(6, 16).
  SET out["LOAD16"] TO -1.
  IF NOT seen["OK"] { RETURN rv_lost(out, "V90", seen["WHY"]). }
  IF ans["TERM"] OR (ans["PRO"] AND st["PHASE"] = "SHOW") {
    SET out["ENDED"] TO TRUE.
    RETURN out.
  }
  IF st["PHASE"] = "TIME" {
    IF NOT st["LOADED"] OR ans["V32"] {
      SET st["LOADED"] TO TRUE.
      SET out["LOAD16"] TO st["TIG"].
      SET out["DERIVED"]["N16"] TO st["TIG"].
    } ELSE IF ans["PRO"] {
      LOCAL at_ut IS (CHOOSE now_ut IF keyed_s = 0 ELSE clock_zero + keyed_s).
      LOCAL lm_then IS conic_kepler(seen["R"], seen["V"], at_ut - seen["T"], seen["MU"]).
      LOCAL csm_then IS conic_kepler(seen["RT"], seen["VT"], at_ut - seen["T"], seen["MU"]).
      IF NOT lm_then["OK"] OR NOT csm_then["OK"] { RETURN rv_lost(out, "V90", "no orbit to that time"). }
      SET st["N90"] TO rndz_r36(lm_then["R"], lm_then["V"], csm_then["R"], csm_then["V"]).
      SET st["PHASE"] TO "SHOW".
    }
  } ELSE IF ans["V32"] {
    SET st["PHASE"] TO "TIME".
  }
  IF st["PHASE"] = "SHOW" {
    SET out["NOUN"] TO 90.
    SET out["DERIVED"]["N90"] TO st["N90"].
  }
  RETURN out.
}

// ---- V89, point an axis at the CSM ------------------------------------------------------------------------------

// v89_new: PHASE "OPTION" (V04 N12), "ANGLES" (V06 N18), "MOVE" (R60).
FUNCTION v89_new {
  PARAMETER snap.
  RETURN LEXICON("SNAP", snap, "PHASE", "OPTION", "AIM", FALSE, "N18", LIST(0, 0, 0), "R60", FALSE).
}

// v89_aim: the attitude that puts the chosen axis (option 1: +Z, the window; else +X, the thrust axis) on the line of sight V89_LEAD_S ahead,
// by the smallest turn, and its N18 angles.
FUNCTION v89_aim {
  PARAMETER st, att, seen.
  LOCAL line IS (seen["RT"] + seen["VT"] * V89_LEAD_S) - (seen["R"] + seen["V"] * V89_LEAD_S).
  LOCAL sight IS line:NORMALIZED.
  LOCAL aim IS LEXICON("NOSE", sight, "FACE", rndz_aim_axis(att["NOSE"], sight, att["FACE"])).
  IF att["OPTION"] = 1 { SET aim TO LEXICON("NOSE", rndz_aim_axis(att["FACE"], sight, att["NOSE"]), "FACE", sight). }
  SET st["AIM"] TO aim.
  SET st["N18"] TO p20_angles(att, seen, aim).
}

// v89_step: att as P20's (lm_p20.ks) with "OPTION", N12's R2. ks: only its VERB and NOUN are read, for ENTR at R60's request.
FUNCTION v89_step {
  PARAMETER st, att, now_ut, ans, ks.
  LOCAL out IS rv_out(4, 12).
  SET out["CTL"] TO LEXICON("STEER", FALSE, "DIR", V(0, 0, 0), "UP", V(0, 0, 0), "HARD", FALSE).
  LOCAL seen IS st["SNAP"]:CALL().
  IF NOT seen["OK"] { RETURN rv_lost(out, "V89", seen["WHY"]). }
  IF st["PHASE"] = "MOVE" {
    IF ans["TERM"] {                       // V34 ends it at once, mid-turn too (R60 itself ignores answers while turning)
      SET out["ENDED"] TO TRUE.
      RETURN out.
    }
    LOCAL r60 IS st["R60"].
    LOCAL pro_now IS ans["PRO"] AND att["AUTO"].
    IF r60["STATE"] = "TURNING" AND NOT att["AUTO"] {      // ATT HOLD: the manoeuvre stops and is asked for again
      SET r60["STATE"] TO "ASK".
      SET r60["SHOWN"] TO FALSE.
    }
    LOCAL r60_keys IS LEXICON("PRO", pro_now, "TERMINATE", ans["TERM"], "RECYCLE", ans["V32"], "ENTER", ans["ENTER"], "VERB", ks["VERB"], "NOUN", ks["NOUN"]).
    LOCAL result IS r60_step(r60, r60_keys, att["ERR"], att["RATE"]).
    IF result["STATE"] = "DONE" OR result["STATE"] = "TERM" {
      SET out["ENDED"] TO TRUE.
      RETURN out.
    }
    SET out["VERB"] TO result["VERB"].
    SET out["NOUN"] TO result["NOUN"].
    SET out["FLASH"] TO result["FLASH"].
    // Steering from the first turn on: turning, and holding the attitude while it asks again.
    IF att["AUTO"] AND (result["STATE"] = "TURNING" OR result["STATE"] = "ASK2") {
      LOCAL ctl IS out["CTL"].
      SET ctl["STEER"] TO TRUE.
      SET ctl["DIR"] TO st["AIM"]["NOSE"].
      SET ctl["UP"] TO st["AIM"]["FACE"].
      SET ctl["HARD"] TO result["STATE"] = "TURNING".
    }
  } ELSE {
    IF ans["TERM"] {
      SET out["ENDED"] TO TRUE.
      RETURN out.
    }
    IF st["PHASE"] = "OPTION" {
      IF ans["PRO"] {
        v89_aim(st, att, seen).
        SET st["PHASE"] TO "ANGLES".
      }
    } ELSE IF ans["V32"] {
      v89_aim(st, att, seen).
    } ELSE IF ans["PRO"] {
      SET st["R60"] TO r60_new(st["AIM"]["NOSE"], st["AIM"]["FACE"]).
      SET st["PHASE"] TO "MOVE".
      SET out["VERB"] TO R60_VERB_ASK.
      SET out["NOUN"] TO R60_NOUN_ANGLES.
      SET st["R60"]["SHOWN"] TO TRUE.
    }
    IF st["PHASE"] = "ANGLES" {
      SET out["VERB"] TO 6.
      SET out["NOUN"] TO 18.
    }
  }
  IF st["PHASE"] <> "OPTION" { SET out["DERIVED"]["N18"] TO st["N18"]. }
  RETURN out.
}
