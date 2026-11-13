// dsky_core.ks -- the DSKY core: the main loop and the programme table. It never names a vehicle or a programme; the
// vehicle (a LEXICON, see below) supplies the navigation, the noun table, the lamps and the programmes.
//
// Vehicle LEXICON (read here, built by the vehicle's own file):
//   "NOUNS", "VERBS", "PROGS"  LISTs of the numbers the keypad accepts (PROGS: what V37 may ask for)
//   "NOUN_REGS"    delegate (noun_no, derived) -> LIST of three register texts (empty LIST = no such noun)
//   "NAV"          delegate (prog) -> LEXICON("OK", bool, "STATE", state, "DERIVED", derived[, "MSG", text]);
//                  prog is the running programme's LEXICON or FALSE; OK FALSE stops the loop (MSG is printed)
//   "HOOK"         delegate (prog, nav) called once per cycle after the programme's step
//   "LAMPS"        LEXICON: a programme-output key -> the lamp flag it sets ("KEY_REL" -> "KEYREL", ...)
//   "IDLE_LAMPS"   delegate (idle_text) -> LEXICON of lamp flags to set while no programme runs
//   "STICKY_PROGS" LIST of programme numbers whose number stays shown after the programme ends
//   "PROGRAMMES"   LEXICON keyed by the programme number as text ("12"): the programme table
// Programme table entry: LEXICON(
//   "START"      delegate (prev_prog) -> the new programme's LEXICON; "REFUSED" holds a reason text, "" when it started.
//                prev_prog is FALSE for a V37 start, the old programme's LEXICON for a handover
//   "STEP"       delegate (prog, nav, ks) -> LEXICON: SET_VERB, SET_NOUN, EXTRA, MSG, KEY_REL, ALT_LAMP, VEL_LAMP,
//                ALARM, BLANK, FLASH, ENDED, HANDOVER, PROG_NO (and optionally more lamp keys, named in "LAMPS", and
//                "STATUS": a LIST of up to CORE_STATUS_ROWS text lines the core draws in place at the top of the terminal
//                every cycle, for a live readout that must not scroll like MSG does)
//   "END"        delegate (prog): give the controls back
//   "SAMPLE"     delegate (prog), called every 0.02 s while the loop waits, or FALSE
//   "NEXT"       number of the programme to hand over to, or -1
//   "SELECTABLE" TRUE when V37 may start it)
// Delegates are called with :CALL(...), the documented way to call a delegate held in a lexicon.
//
// The run state (core_new) is a LEXICON: "PROG" (the running programme or FALSE), "ENTRY" (its table entry or FALSE),
// "IDLE_TEXT" (what PROG shows with nothing running), "STATUS_ROWS" (how many status rows are drawn now), "STATUS_PROG" (the PROG text shown with them).
// Needs dsky_keys.ks, dsky_display.ks (zero_pad) and, for core_run, a GUI with gui_poll / gui_update (the vehicle's window file).

RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").

// The terminal's top CORE_STATUS_ROWS rows are the status area: core_status_draw redraws them every cycle, so messages
// (PRINT, which scroll) can never leave a stale copy there. core_reserve_status moves the print position below them; the
// entry script calls it once after CLEARSCREEN.
GLOBAL CORE_STATUS_ROWS IS 3.

// core_reserve_status: print blank lines so the first message appears below the status area.
FUNCTION core_reserve_status {
  FROM { LOCAL i IS 0. } UNTIL i > CORE_STATUS_ROWS STEP { SET i TO i + 1. } DO { PRINT "". }
}

// core_status_draw: draw the programme's status lines in the top rows, or blank the rows once when it has none any more.
// The terminal is cleared when the readout first appears and whenever the programme number shown (prog_text) changes while
// it is up (P65 to P66, and the landing's P68): the older messages then do not sit beneath the live readout, and a message
// that scrolled the screen cannot leave the readout garbled. Later messages print below it.
FUNCTION core_status_draw {
  PARAMETER crun, lines, prog_text.
  LOCAL count IS MIN(lines:LENGTH, CORE_STATUS_ROWS).
  LOCAL fresh IS crun["STATUS_ROWS"] = 0 AND count > 0.
  LOCAL switched IS crun["STATUS_ROWS"] > 0 AND count > 0 AND crun["STATUS_PROG"] <> prog_text.
  IF fresh OR switched {
    CLEARSCREEN.
    core_reserve_status().
  }
  IF count > 0 { SET crun["STATUS_PROG"] TO prog_text. }
  FROM { LOCAL i IS 0. } UNTIL i >= count STEP { SET i TO i + 1. } DO { PRINT pad_right(lines[i], 48) AT (0, i). }
  FROM { LOCAL i IS count. } UNTIL i >= crun["STATUS_ROWS"] STEP { SET i TO i + 1. } DO { PRINT pad_right("", 48) AT (0, i). }
  SET crun["STATUS_ROWS"] TO count.
}

// core_new: a fresh run state, nothing running.
FUNCTION core_new {
  PARAMETER vehicle.
  RETURN LEXICON("PROG", FALSE, "ENTRY", FALSE, "IDLE_TEXT", "00", "STATUS_ROWS", 0, "STATUS_PROG", "").
}

// core_entry: the table entry for a programme number, or FALSE if the vehicle has none. The table is keyed by the
// number as text, so a number read from the keypad and one written in code find the same entry.
FUNCTION core_entry {
  PARAMETER vehicle, number.
  LOCAL key IS "" + number.
  IF vehicle["PROGRAMMES"]:HASKEY(key) { RETURN vehicle["PROGRAMMES"][key]. }
  RETURN FALSE.
}

// core_end: end the running programme (its END gives the controls back), once. Safe to call with nothing running.
FUNCTION core_end {
  PARAMETER crun, vehicle.
  IF crun["PROG"]:ISTYPE("Lexicon") {
    LOCAL ended_prog IS crun["PROG"].
    LOCAL ended_entry IS crun["ENTRY"].
    SET crun["PROG"] TO FALSE.            // cleared first, so a second call cannot call END again
    SET crun["ENTRY"] TO FALSE.
    ended_entry["END"]:CALL(ended_prog).
  }
}

// core_request: one V37 request, number = the programme asked for (0 = none). A number the vehicle has no selectable
// entry for lights OPR ERR and changes nothing (the running programme carries on). Otherwise the running programme is
// ended first, so asking for the running one again restarts it; 0 only ends. A START that refuses lights OPR ERR and
// returns the reason in MSG. Returns LEXICON("MSG", text) (text "" when there is nothing to say).
FUNCTION core_request {
  PARAMETER crun, vehicle, ks, number.
  LOCAL entry IS FALSE.
  IF number <> 0 {
    SET entry TO core_entry(vehicle, number).
    LOCAL ok IS FALSE.
    IF entry:ISTYPE("Lexicon") { IF entry["SELECTABLE"] { SET ok TO TRUE. } }   // nested: AND would not skip the lookup
    IF NOT ok {
      SET ks["OPRERR"] TO TRUE.
      RETURN LEXICON("MSG", "").
    }
  }
  LOCAL msg IS "".
  SET crun["IDLE_TEXT"] TO "00".
  IF crun["PROG"]:ISTYPE("Lexicon") {
    core_end(crun, vehicle).
    SET msg TO "Programme ended.".
  }
  IF number <> 0 {
    LOCAL started IS entry["START"]:CALL(FALSE).
    IF started["REFUSED"] <> "" {
      SET ks["OPRERR"] TO TRUE.
      SET msg TO "P" + zero_pad(number, 2) + " refused: " + started["REFUSED"] + ".".
    } ELSE {
      SET crun["PROG"] TO started.
      SET crun["ENTRY"] TO entry.
    }
  }
  RETURN LEXICON("MSG", msg).
}

// core_join: msg and more as one line of text, a space between when both have something.
FUNCTION core_join {
  PARAMETER msg, more.
  IF msg = "" { RETURN more. }
  IF more = "" { RETURN msg. }
  RETURN msg + " " + more.
}

// core_handover: the programme's NEXT takes over, given the old programme's state (the engine, attitude mode and radar
// carry on; END is not called on the old one). A NEXT that is missing, unknown or refuses ends the programme instead.
// Returns the message text ("" when the handover went through).
FUNCTION core_handover {
  PARAMETER crun, vehicle.
  LOCAL next_no IS crun["ENTRY"]["NEXT"].
  LOCAL next_entry IS FALSE.
  IF next_no >= 0 { SET next_entry TO core_entry(vehicle, next_no). }
  IF NOT next_entry:ISTYPE("Lexicon") {
    core_end(crun, vehicle).
    RETURN "Handover failed: no next programme. The controls are yours.".
  }
  LOCAL started IS next_entry["START"]:CALL(crun["PROG"]).
  IF started["REFUSED"] <> "" {
    core_end(crun, vehicle).
    RETURN "Handover refused: " + started["REFUSED"] + ". The controls are yours.".
  }
  SET crun["PROG"] TO started.
  SET crun["ENTRY"] TO next_entry.
  RETURN "".
}

// core_step: one cycle of the running programme (or of the idle display). Runs the STEP, applies its display requests
// to the key state ks and the derived values, maps its lamp outputs through the vehicle's LAMPS, and handles its end
// or handover. Returns LEXICON("FLAGS", the flags lexicon for the display, "PROG_TEXT", PROG text, "MSG", text,
// "STATUS", LIST of status lines (empty when the programme gave none or none runs)).
FUNCTION core_step {
  PARAMETER crun, vehicle, nav, ks.
  LOCAL derived IS nav["DERIVED"].
  LOCAL flags IS flags_from_keys(ks, FALSE).
  SET flags["BLANK"] TO FALSE.
  SET flags["FLASH"] TO FALSE.
  FOR lamp_key IN vehicle["LAMPS"]:KEYS { SET flags[vehicle["LAMPS"][lamp_key]] TO FALSE. }
  LOCAL idle_lamps IS vehicle["IDLE_LAMPS"]:CALL(crun["IDLE_TEXT"]).     // e.g. a lamp that stays lit after a landing
  FOR lamp_flag IN idle_lamps:KEYS { SET flags[lamp_flag] TO idle_lamps[lamp_flag]. }
  LOCAL prog_text IS crun["IDLE_TEXT"].
  LOCAL msg IS "".
  LOCAL status_lines IS LIST().
  IF crun["PROG"]:ISTYPE("Lexicon") {
    LOCAL entry IS crun["ENTRY"].
    LOCAL out IS entry["STEP"]:CALL(crun["PROG"], nav, ks).
    IF out["SET_VERB"] >= 0 {
      SET ks["VERB"] TO out["SET_VERB"].
      SET ks["NOUN"] TO out["SET_NOUN"].
    }
    FOR extra_key IN out["EXTRA"]:KEYS { SET derived[extra_key] TO out["EXTRA"][extra_key]. }
    SET msg TO out["MSG"].
    IF out:HASKEY("STATUS") { SET status_lines TO out["STATUS"]. }
    // A lamp key the programme did not return (a lamp only later programmes drive) leaves the flag as it was.
    FOR lamp_key IN vehicle["LAMPS"]:KEYS {
      IF out:HASKEY(lamp_key) { SET flags[vehicle["LAMPS"][lamp_key]] TO out[lamp_key]. }
    }
    SET flags["PROG"] TO out["ALARM"] > 0.         // alarm 1406 lights the PROG lamp
    SET flags["BLANK"] TO out["BLANK"].
    SET flags["FLASH"] TO out["FLASH"].
    SET prog_text TO "" + out["PROG_NO"].
    IF out["ENDED"] {
      core_end(crun, vehicle).
      IF vehicle["STICKY_PROGS"]:CONTAINS(out["PROG_NO"]) { SET crun["IDLE_TEXT"] TO "" + out["PROG_NO"]. }
      SET msg TO core_join(msg, "P" + out["PROG_NO"] + " ended. The controls are yours.").
    } ELSE IF out["HANDOVER"] {
      SET msg TO core_join(msg, core_handover(crun, vehicle)).
    }
  } ELSE {
    SET ks["PRO"] TO FALSE.            // PRO means nothing with no programme running
  }
  RETURN LEXICON("FLAGS", flags, "PROG_TEXT", prog_text, "MSG", msg, "STATUS", status_lines).
}

// core_run: the DSKY loop. ui is the window from gui_fill (made at the top level of the entry script). Each cycle:
// read navigation, poll the keys, handle a V37 request, step the programme, update the display, then wait for the next
// fixed-rate slot. Ends on V34 ENTR, or when the vehicle's navigation says stop; a running programme is always ended.
FUNCTION core_run {
  PARAMETER ui, vehicle.
  LOCAL ks IS keys_new(vehicle["NOUNS"], vehicle["VERBS"], vehicle["PROGS"]).
  LOCAL crun IS core_new(vehicle).
  LOCAL next_t IS TIME:SECONDS.
  LOCAL running IS TRUE.
  UNTIL NOT running {
    LOCAL nav IS vehicle["NAV"]:CALL(crun["PROG"]).
    IF NOT nav["OK"] {
      IF nav:HASKEY("MSG") { PRINT nav["MSG"]. } ELSE { PRINT "Navigation lost. Stopping.". }
      SET running TO FALSE.
    } ELSE {
      gui_poll(ui, ks).
      // V37 ENTR <programme> ENTR: start a programme, or end the running one (00).
      IF ks["PROG_REQ"] >= 0 {
        LOCAL req IS ks["PROG_REQ"].
        SET ks["PROG_REQ"] TO -1.
        LOCAL req_res IS core_request(crun, vehicle, ks, req).
        IF req_res["MSG"] <> "" { PRINT req_res["MSG"]. }
      }
      LOCAL step_res IS core_step(crun, vehicle, nav, ks).
      core_status_draw(crun, step_res["STATUS"], step_res["PROG_TEXT"]).          // first, so a clear of the screen does not wipe this cycle's message
      IF step_res["MSG"] <> "" { PRINT step_res["MSG"]. }
      vehicle["HOOK"]:CALL(crun["PROG"], nav).
      LOCAL flags IS step_res["FLAGS"].
      SET flags["REGS"] TO vehicle["NOUN_REGS"]:CALL(ks["NOUN"], nav["DERIVED"]).
      gui_update(ui, nav["DERIVED"], step_res["PROG_TEXT"], ks["VERB"], ks["NOUN"], flags).
      // V34 ENTR: terminate.
      IF ks["VERB"] = 34 { SET running TO FALSE. }
      // Fixed-rate loop: wait until the next CYCLE_S slot. If the clock ran ahead (time warp), start
      // from now instead of "catching up" with a burst of back-to-back cycles (seen in the first flight log).
      SET next_t TO MAX(next_t + CYCLE_S, TIME:SECONDS).
      // A programme with a SAMPLE hook has it called every 0.02 s while waiting, so a key tap shorter than one cycle is
      // still seen (the redesignation clicks in the approach, the rate-of-descent clicks in the final descent).
      LOCAL sample IS FALSE.
      IF crun["ENTRY"]:ISTYPE("Lexicon") { SET sample TO crun["ENTRY"]["SAMPLE"]. }
      IF NOT sample:ISTYPE("Boolean") {      // a delegate, not FALSE
        UNTIL TIME:SECONDS >= next_t { sample:CALL(crun["PROG"]). WAIT 0.02. }
      } ELSE {
        WAIT MAX(0.01, next_t - TIME:SECONDS).
      }
    }
  }
  // A programme still running (V34, or navigation stopped): give the controls back.
  core_end(crun, vehicle).
}
