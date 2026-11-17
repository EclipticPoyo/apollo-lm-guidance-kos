// dsky_core.ks -- the DSKY core: the main loop and the programme table. It never names a vehicle or a programme; the
// vehicle (a LEXICON, see below) supplies the navigation, the noun table, the lamps and the programmes.
//
// Vehicle LEXICON (read here, built by the vehicle's own file):
//   "NOUNS", "VERBS", "PROGS"  LISTs of the numbers the keypad accepts (PROGS: what V37 may ask for)
//   "START_VN"     (optional) LIST(verb, noun) shown at start; LIST(-1, -1) = a blank display; default V16 and the first noun
//   "NOUN_REGS"    delegate (noun_no, derived) -> LIST of three register texts (empty LIST = no such noun)
//   "NAV"          delegate (prog) -> LEXICON("OK", bool, "STATE", state, "DERIVED", derived[, "MSG", text]);
//                  prog is the running programme's LEXICON or FALSE; OK FALSE stops the loop (MSG is printed)
//   "HOOK"         delegate (prog, nav) called once per cycle after the programme's step
//   "LAMPS"        LEXICON: a programme-output key -> the lamp flag it sets ("KEY_REL" -> "KEYREL", ...)
//   "IDLE_LAMPS"   delegate (idle_text) -> LEXICON of lamp flags to set while no programme runs
//   "STICKY_PROGS" LIST of programme numbers whose number stays shown after the programme ends
//   "PROGRAMMES"   LEXICON keyed by the programme number as text ("12"): the programme table
//   "STORE_SAVE"  (optional) a delegate () called once when the DSKY ends, to save the store (the vehicle knows the file)
//   "STORE", "P27_OK"  (optional, for P27) the erasable store (dsky_store.ks) and a delegate (prog) -> bool: may an update start now
//   "P27_ADDR"  (optional, for P27) LEXICON "BUFF" and "TEMP": the update program's buffer addresses (ECADRs) shown in R3
//   "UPLINK_FILE"  (optional, needs "STORE" and "P27_OK") path of the uplink key file the DSKY feeds into its keys (dsky_uplink.ks)
//   "LOADS"        (optional) LEXICON noun-as-text -> LEXICON("NCOMP", n, "DIGITS", LIST(digits of R1, R2, R3)): the nouns V21 to V25 can load
//   "LOAD_COMMIT"  (with "LOADS") delegate (noun_no, comps, values) -> text: stores the values keyed (comps: the registers loaded,
//                  1 to 3; values: signed integers as keyed); returns "" or the reason it refused (see dsky_load.ks)
// Programme table entry: LEXICON(
//   "START"      delegate (prev_prog) -> the new programme's LEXICON; "REFUSED" holds a reason text, "" when it started.
//                prev_prog is FALSE for a V37 start, the old programme's LEXICON for a handover
//   "STEP"       delegate (prog, nav, ks) -> LEXICON: SET_VERB, SET_NOUN, EXTRA, MSG, KEY_REL, ALT_LAMP, VEL_LAMP,
//                REQUEST (FALSE, or LEXICON("VERB", v, "NOUN", n): a flashing request for the pilot, see below),
//                ALARM (a code, 0 none: raised in the alarm facility, dsky_alarm.ks, when it differs from the last cycle's), BLANK, FLASH, ENDED, HANDOVER, PROG_NO (and optionally more lamp keys, named in "LAMPS", and
//                "STATUS": a LIST of up to CORE_STATUS_ROWS text lines the core draws in place at the top of the terminal
//                every cycle, for a live readout that must not scroll like MSG does)
//   "END"        delegate (prog): give the controls back
//   "SAMPLE"     delegate (prog), called every 0.02 s while the loop waits, or FALSE
//   "NEXT"       number of the programme to hand over to, or -1
//   "SELECTABLE" TRUE when V37 may start it)
// A pending request: while a step returns REQUEST the core keeps it in ks["PENDING"], flashes VERB and NOUN while the display shows exactly the
// request's verb and noun (and nothing is being typed), and lights KEY REL when the pilot keys over it (dsky_keys.ks has the rules). The step reads
// the pilot's answers in the key state ks: "PRO" (it clears it), and "RECYCLE" (V32), "TERMINATE" (V34) and "ENTER" (any ENTR), which the core
// clears after each step. A step without REQUEST can still use the old FLASH output. The vehicle may add "NO_NOUN_VERBS" (a LIST) and
// "VERB_ACTIONS" (verb as text -> delegate (ks) -> bool, FALSE = OPR ERR), see dsky_keys.ks, and "ALARM_SOURCE" (delegate (prog, now_ut) -> LIST of
// alarm codes to raise this cycle; each is raised and the display restarted, as after a software restart, see core_restart_display).
// Delegates are called with :CALL(...), the documented way to call a delegate held in a lexicon.
//
// The run state (core_new) is a LEXICON: "PROG" (the running programme or FALSE), "ENTRY" (its table entry or FALSE),
// "IDLE_TEXT" (what PROG shows with nothing running), "STATUS_ROWS" (how many status rows are drawn now), "STATUS_PROG" (the PROG text shown with them).
// Needs dsky_keys.ks, dsky_display.ks (zero_pad) and, for core_run, a GUI with gui_poll / gui_update (the vehicle's window file).

RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/core/dsky_uplink.ks").

// The terminal's top CORE_STATUS_ROWS rows are the status area: core_status_draw redraws them every cycle, so messages
// (PRINT, which scroll) can never leave a stale copy there. core_reserve_status moves the print position below them; the
// entry script calls it once after CLEARSCREEN.
GLOBAL CORE_STATUS_ROWS IS 3.

// While a status readout is up, messages do not PRINT (a long one wraps and a full screen scrolls, which pushed the live rows out of place and garbled the
// message). core_message draws them in a fixed area of CORE_MSG_ROWS rows under the readout, word-wrapped to CORE_MSG_WIDTH, newest at the bottom.
GLOBAL CORE_MSG_ROWS IS 6.
GLOBAL CORE_MSG_WIDTH IS 48.

// core_reserve_status: print blank lines so the first message appears below the status area.
FUNCTION core_reserve_status {
  FROM { LOCAL i IS 0. } UNTIL i > CORE_STATUS_ROWS STEP { SET i TO i + 1. } DO { PRINT "". }
}

// core_wrap: text as a LIST of lines of at most width characters, broken at spaces (a word longer than a line is cut). Pure.
FUNCTION core_wrap {
  PARAMETER text, width.
  LOCAL out_lines IS LIST().
  LOCAL current IS "".
  FOR first_text IN text:SPLIT(" ") {
    LOCAL word_text IS first_text.
    UNTIL word_text:LENGTH <= width {
      IF current <> "" { out_lines:ADD(current). SET current TO "". }
      out_lines:ADD(word_text:SUBSTRING(0, width)).
      SET word_text TO word_text:SUBSTRING(width, word_text:LENGTH - width).
    }
    IF current = "" { SET current TO word_text. }
    ELSE IF current:LENGTH + 1 + word_text:LENGTH <= width { SET current TO current + " " + word_text. }
    ELSE { out_lines:ADD(current). SET current TO word_text. }
  }
  IF current <> "" { out_lines:ADD(current). }
  RETURN out_lines.
}

// core_message: show a message. With a status readout up it goes into the fixed message area (crun["MSGS"] keeps the latest lines and fits the
// terminal); with none up it is a plain PRINT, as before.
FUNCTION core_message {
  PARAMETER crun, text.
  IF text = "" { RETURN. }
  IF crun["STATUS_ROWS"] = 0 { PRINT text. RETURN. }
  LOCAL area_rows IS MIN(CORE_MSG_ROWS, TERMINAL:HEIGHT - CORE_STATUS_ROWS - 2).
  IF area_rows < 1 { RETURN. }
  FOR line_text IN core_wrap(text, CORE_MSG_WIDTH) { crun["MSGS"]:ADD(line_text). }
  UNTIL crun["MSGS"]:LENGTH <= area_rows { crun["MSGS"]:REMOVE(0). }
  FROM { LOCAL i IS 0. } UNTIL i >= area_rows STEP { SET i TO i + 1. } DO {
    LOCAL shown IS "".
    IF i < crun["MSGS"]:LENGTH { SET shown TO crun["MSGS"][i]. }
    PRINT pad_right(shown, CORE_MSG_WIDTH) AT (0, CORE_STATUS_ROWS + 1 + i).
  }
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
    SET crun["MSGS"] TO LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= CORE_MSG_ROWS STEP { SET i TO i + 1. } DO { PRINT "". }          // plain PRINTs then start below the message area
  }
  IF count > 0 { SET crun["STATUS_PROG"] TO prog_text. }
  FROM { LOCAL i IS 0. } UNTIL i >= count STEP { SET i TO i + 1. } DO { PRINT pad_right(lines[i], 48) AT (0, i). }
  FROM { LOCAL i IS count. } UNTIL i >= crun["STATUS_ROWS"] STEP { SET i TO i + 1. } DO { PRINT pad_right("", 48) AT (0, i). }
  SET crun["STATUS_ROWS"] TO count.
}

// core_new: a fresh run state, nothing running.
FUNCTION core_new {
  PARAMETER vehicle.
  RETURN LEXICON("PROG", FALSE, "ENTRY", FALSE, "IDLE_TEXT", "00", "STATUS_ROWS", 0, "STATUS_PROG", "", "LAST_ALARM", 0, "MSGS", LIST(), "IDLE_REQUEST", FALSE).
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
  SET crun["IDLE_REQUEST"] TO FALSE.          // a V37 selection answers the standing request (see core_step)
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

// core_restart_display: what a software restart does to the display (Luminary's restart reshows the programme's display): drops what is being
// typed, any pending V37 programme number, an active keyed load and an update (nothing is committed), clears KEY REL and puts the pending
// request (else the verb and noun the programme last set) back. The programme's START and END are not called.
FUNCTION core_restart_display {
  PARAMETER ks.
  IF load_active(ks) { load_cancel(ks). }
  IF p27_active(ks) { p27_cancel(ks). }
  key_rel_press(ks).
}

// core_scripted_alarms: the vehicle's ALARM_SOURCE (if it has one) names the alarm codes due now; each is raised, and a software restart then reshows
// the display (core_restart_display). Returns how many codes were raised. The programme's START and END are not called.
FUNCTION core_scripted_alarms {
  PARAMETER ks, vehicle, prog, now_ut.
  IF NOT vehicle:HASKEY("ALARM_SOURCE") { RETURN 0. }
  LOCAL due IS vehicle["ALARM_SOURCE"]:CALL(prog, now_ut).
  FOR code IN due { alarm_raise(ks["ALARM"], code). }
  IF due:LENGTH > 0 { core_restart_display(ks). }
  RETURN due:LENGTH.
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
    IF out["SET_VERB"] >= 0 { SET ks["PROG_VN"] TO LIST(out["SET_VERB"], out["SET_NOUN"]). }
    SET ks["PENDING"] TO FALSE.
    IF out:HASKEY("REQUEST") { IF out["REQUEST"]:ISTYPE("Lexicon") { SET ks["PENDING"] TO out["REQUEST"]. } }
    IF out:HASKEY("STATUS") { SET status_lines TO out["STATUS"]. }
    // A lamp key the programme did not return (a lamp only later programmes drive) leaves the flag as it was.
    FOR lamp_key IN vehicle["LAMPS"]:KEYS {
      IF out:HASKEY(lamp_key) { SET flags[vehicle["LAMPS"][lamp_key]] TO out[lamp_key]. }
    }
    // An alarm code the programme returns is raised once, when it differs from the last cycle's (a steady alarm such as 1406 fills one
    // slot, not all three; the source would repeat it, a documented departure).
    IF out["ALARM"] > 0 AND out["ALARM"] <> crun["LAST_ALARM"] { alarm_raise(ks["ALARM"], out["ALARM"]). }
    SET crun["LAST_ALARM"] TO out["ALARM"].
    SET flags["BLANK"] TO out["BLANK"].
    SET flags["FLASH"] TO out["FLASH"].
    IF ks["PENDING"]:ISTYPE("Lexicon") {
      IF ks["VERB"] = ks["PENDING"]["VERB"] AND ks["NOUN"] = ks["PENDING"]["NOUN"] AND ks["MODE"] = "" AND NOT ks["AWAIT_PROG"] { SET flags["FLASH"] TO TRUE. }
    }
    SET prog_text TO "" + out["PROG_NO"].
    IF out["ENDED"] {
      core_end(crun, vehicle).
      IF vehicle["STICKY_PROGS"]:CONTAINS(out["PROG_NO"]) { SET crun["IDLE_TEXT"] TO "" + out["PROG_NO"]. }
      // Luminary GOTOPOOH (PRO or V34 ended the programme): major mode 00 and a standing flashing request, V37 N99 (GOP00FIX: CAF V37N99, GOFLASH, all
      // three returns post it again) until the pilot keys the next V37. The vehicle names it (END_REQUEST).
      IF vehicle:HASKEY("END_REQUEST") {
        SET crun["IDLE_REQUEST"] TO vehicle["END_REQUEST"].
        SET ks["PENDING"] TO crun["IDLE_REQUEST"].
        key_rel_press(ks).                 // shows it: verb and noun from the request, typed digits dropped
        SET flags["FLASH"] TO TRUE.
      }
      SET msg TO core_join(msg, "P" + out["PROG_NO"] + " ended. The controls are yours.").
    } ELSE IF out["HANDOVER"] {
      SET msg TO core_join(msg, core_handover(crun, vehicle)).
    }
  } ELSE {
    SET ks["PRO"] TO FALSE.            // PRO means nothing with no programme running
    SET ks["PENDING"] TO crun["IDLE_REQUEST"].          // FALSE, or the standing V37 request after a programme ended
    IF ks["PENDING"]:ISTYPE("Lexicon") {
      IF ks["VERB"] = ks["PENDING"]["VERB"] AND ks["NOUN"] = ks["PENDING"]["NOUN"] AND ks["MODE"] = "" AND NOT ks["AWAIT_PROG"] { SET flags["FLASH"] TO TRUE. }
    }
    SET ks["PROG_VN"] TO LIST(-1, -1).
    SET crun["LAST_ALARM"] TO 0.
  }
  // KEY REL: the lamp the pilot's keying over a request lit, with the programme's own KEY_REL (when the vehicle maps it); out with the request.
  IF NOT ks["PENDING"]:ISTYPE("Lexicon") { SET ks["KEYREL"] TO FALSE. }
  IF ks["KEYREL"] { SET flags["KEYREL"] TO TRUE. }
  SET ks["RECYCLE"] TO FALSE.         // V32, V34 and ENTR are seen by the programme for one cycle only
  SET ks["TERMINATE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  SET flags["LAMPTEST"] TO key_lamptest_on(ks, TIME:SECONDS).      // V35: the window lights every lamp and digit
  SET flags["PROG"] TO ks["ALARM"]["LAMP"].       // the PROG lamp is latched by the alarm facility until RSET
  SET derived["ALARM_CODES"] TO ks["ALARM"]["CODES"].      // for N09
  IF load_active(ks) OR p27_active(ks) { SET flags["FLASH"] TO TRUE. }    // VERB and NOUN flash while a keyed load or an update waits for data
  SET flags["UPLINK"] TO p27_active(ks) AND ks["P27"]["ACTY"].               // UPLINK ACTY: the ground is sending (see dsky_p27.ks)
  RETURN LEXICON("FLAGS", flags, "PROG_TEXT", prog_text, "MSG", msg, "STATUS", status_lines).
}

// core_run: the DSKY loop. ui is the window from gui_fill (made at the top level of the entry script). Each cycle:
// read navigation, poll the keys, handle a V37 request, step the programme, update the display, then wait for the next
// fixed-rate slot. Ends when the window's close cross is confirmed (ks["QUIT"]), or when the vehicle's navigation says stop; a running programme is always ended.
FUNCTION core_run {
  PARAMETER ui, vehicle.
  LOCAL start_vn IS LIST().
  IF vehicle:HASKEY("START_VN") { SET start_vn TO vehicle["START_VN"]. }
  LOCAL no_noun IS LIST().
  IF vehicle:HASKEY("NO_NOUN_VERBS") { SET no_noun TO vehicle["NO_NOUN_VERBS"]. }
  LOCAL ks IS keys_new(vehicle["NOUNS"], vehicle["VERBS"], vehicle["PROGS"], start_vn, no_noun).
  SET ks["VEHICLE"] TO vehicle.             // the keyed loaders and P27 read the vehicle's tables through the key state
  LOCAL feed IS FALSE.                       // the uplink feed, when the vehicle names an uplink file
  IF vehicle:HASKEY("UPLINK_FILE") AND vehicle:HASKEY("P27_OK") { SET feed TO uplink_new(vehicle["UPLINK_FILE"]). }
  LOCAL feed_active IS FALSE.
  LOCAL crun IS core_new(vehicle).
  LOCAL next_t IS TIME:SECONDS.
  LOCAL running IS TRUE.
  UNTIL NOT running {
    LOCAL cycle_t0 IS TIME:SECONDS.        // start of this cycle's work, for COMP ACTY
    LOCAL job_ran IS FALSE.                // did the "computer" do a job this cycle (COMP ACTY)?
    LOCAL nav IS vehicle["NAV"]:CALL(crun["PROG"]).
    IF NOT nav["OK"] {
      IF nav:HASKEY("MSG") { PRINT nav["MSG"]. } ELSE { PRINT "Navigation lost. Stopping.". }
      SET running TO FALSE.
    } ELSE {
      SET ks["PROGRAM"] TO crun["PROG"].       // P27 asks the vehicle whether an update is allowed with this
      gui_poll(ui, ks).
      IF feed:ISTYPE("Lexicon") {
        LOCAL fed IS uplink_poll(feed, ks, vehicle, vehicle["P27_OK"]:CALL(crun["PROG"]), TIME:SECONDS).
        SET feed_active TO fed["ACTIVE"].
        core_message(crun, fed["MSG"]).
      }
      core_scripted_alarms(ks, vehicle, crun["PROG"], TIME:SECONDS).
      // V37 ENTR <programme> ENTR: start a programme, or end the running one (00).
      IF ks["PROG_REQ"] >= 0 {
        LOCAL req IS ks["PROG_REQ"].
        SET ks["PROG_REQ"] TO -1.
        SET job_ran TO TRUE.
        LOCAL req_res IS core_request(crun, vehicle, ks, req).
        core_message(crun, req_res["MSG"]).
      }
      LOCAL step_res IS core_step(crun, vehicle, nav, ks).
      core_status_draw(crun, step_res["STATUS"], step_res["PROG_TEXT"]).          // first, so a clear of the screen does not wipe this cycle's message
      core_message(crun, step_res["MSG"]).
      vehicle["HOOK"]:CALL(crun["PROG"], nav).
      LOCAL flags IS step_res["FLAGS"].
      IF feed_active { SET flags["UPLINK"] TO TRUE. }          // UPLINK ACTY stays lit while the uplink file is being pressed in
      SET flags["REGS"] TO vehicle["NOUN_REGS"]:CALL(ks["NOUN"], nav["DERIVED"]).
      // The register being loaded (V21 to V25) shows what the pilot has keyed, blank until something is keyed.
      LOCAL load_view IS load_shown(ks, vehicle).
      IF load_view["REG"] > 0 AND flags["REGS"]:LENGTH = 3 {
        FOR entered IN load_view["DONE"] { SET flags["REGS"][entered[0] - 1] TO entered[1]. }          // registers already entered keep the value keyed
        SET flags["REGS"][load_view["REG"] - 1] TO load_view["TEXT"].
        SET flags["REGS_NOW"] TO TRUE.
      }
      core_message(crun, ks["LOAD"]["MSG"]).
      SET ks["LOAD"]["MSG"] TO "".
      // P27 shows the octal word being keyed in R1 and the buffer address stream in R3 (R2 blank).
      LOCAL p27_view IS p27_shown(ks, vehicle).
      IF p27_view["ACTIVE"] { SET flags["REGS"] TO LIST(p27_view["R1"], NA, p27_view["R3"]). SET flags["REGS_NOW"] TO TRUE. }
      // REGS_NOW: keyed digits (a load, P27) show at once; only a monitored noun's numbers refresh once a second (gui_update).
      core_message(crun, ks["P27"]["MSG"]).
      SET ks["P27"]["MSG"] TO "".
      // COMP ACTY: lit while the Executive runs a job and dark when it idles (Luminary EXECUTIVE.agc: NUCHANG2 and
      // NUDIRECT turn the light on, DUMMYJOB turns it off). Here a job is a programme step or a programme request;
      // BUSY is how long this cycle's work took (the display adds its own minimum so a short job is still visible).
      IF crun["PROG"]:ISTYPE("Lexicon") { SET job_ran TO TRUE. }
      SET flags["JOB"] TO job_ran.
      SET flags["BUSY"] TO TIME:SECONDS - cycle_t0.
      gui_update(ui, nav["DERIVED"], p27_prog_text(ks, step_res["PROG_TEXT"]), ks["VERB"], ks["NOUN"], flags).
      // The window's close cross, confirmed with YES (gui_poll sets QUIT). V34 does not end the DSKY: it is Terminate, as in Luminary.
      IF ks["QUIT"] { SET running TO FALSE. }
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
  // Keep the erasable store for the next DSKY run, when the vehicle names a file for it.
  IF vehicle:HASKEY("STORE") AND vehicle:HASKEY("STORE_SAVE") { vehicle["STORE_SAVE"]:CALL(). }
}
