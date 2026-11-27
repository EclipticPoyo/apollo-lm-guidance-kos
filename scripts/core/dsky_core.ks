// dsky_core.ks -- the DSKY core: the main loop and the programme table. It never names a vehicle or a programme; the
// vehicle (a LEXICON, see below) supplies the navigation, the noun table, the lamps and the programmes.
//
// Vehicle LEXICON (read here, built by the vehicle's own file):
//   "NOUNS", "VERBS", "PROGS"  LISTs of the numbers the keypad accepts (PROGS: what V37 may ask for)
//   "START_VN"     (optional) LIST(verb, noun) shown at start; LIST(-1, -1) = a blank display; default V16 and the first noun
//   "NOUN_REGS"    delegate (noun_no, derived) -> LIST of three register texts (empty LIST = no such noun)
//   "NAV"          delegate (prog) -> LEXICON("OK", bool, "STATE", state, "DERIVED", derived[, "MSG", text]);
//                  prog is the running programme's LEXICON or FALSE; OK FALSE stops the loop (MSG is shown as a warning)
//   "HOOK"         delegate (prog, nav) called once per cycle after the programme's step
//   "TICK"         (optional) delegate () called every 0.02 s while the loop waits, whatever runs: for a display that must move smoothly
//   "LAMPS"        LEXICON: a programme-output key -> the lamp flag it sets ("KEY_REL" -> "KEYREL", ...)
//   "IDLE_LAMPS"   delegate (idle_text) -> LEXICON of lamp flags to set while no programme runs
//   "STICKY_PROGS" LIST of programme numbers whose number stays shown after the programme ends
//   "PROGRAMMES"   LEXICON keyed by the programme number as text ("12"): the programme table
//   "STORE_SAVE"  (optional) a delegate () called once when the DSKY ends, to save the store (the vehicle knows the file)
//   "LOG_FILE"     (optional) path of the terminal's log: every warning and message goes there too; deleted when core_run starts
//   "LOG_CLOCK"    (optional) delegate () -> text: the clock at the front of each log line
//   "STORE", "P27_OK"  (optional, for P27) the erasable store (dsky_store.ks) and a delegate (prog) -> bool: may an update start now
//   "P27_ADDR"  (optional, for P27) LEXICON "BUFF" and "TEMP": the update program's buffer addresses (ECADRs) shown in R3
//   "V37_HOOK"     (optional) delegate (number): called for every accepted V37 (or vehicle) request, after the ENDs it causes and before
//                  its START (for a TAKEOVER entry: after a successful START)
//   "UPLINK_FILE"  (optional, needs "STORE" and "P27_OK") path of the uplink key file the DSKY feeds into its keys (dsky_uplink.ks)
//   "LOADS"        (optional) LEXICON noun-as-text -> LEXICON("NCOMP", n, "DIGITS", LIST(digits of R1, R2, R3)[, "OCTAL", TRUE]): the nouns
//                  V21 to V25 can load (an octal noun: digits 0 to 7, no sign)
//   "LOAD_COMMIT"  (with "LOADS") delegate (noun_no, comps, values) -> text: stores the values keyed (comps: the registers loaded,
//                  1 to 3; values: signed integers as keyed); returns "" or the reason it refused (see dsky_load.ks)
//   "REQUEST_SOURCE"  (optional) delegate (prog, now_ut) -> a programme number the vehicle asks for now (a control of its own, such as a key),
//                  or -1; treated as a V37 request for it (core_vehicle_request)
// Programme table entry: LEXICON(
//   "START"      delegate (prev_prog) -> the new programme's LEXICON; "REFUSED" holds a reason text, "" when it started.
//                prev_prog is FALSE for a V37 start, the old programme's LEXICON for a handover
//   "STEP"       delegate (prog, nav, ks) -> LEXICON: SET_VERB, SET_NOUN, EXTRA, MSG (a message for the terminal, "" none), WARN (optional: a
//                warning, for something wrong, refused or needing the pilot to act), KEY_REL, ALT_LAMP, VEL_LAMP,
//                REQUEST (FALSE, or LEXICON("VERB", v, "NOUN", n): a flashing request for the pilot, see below),
//                ALARM (a code, 0 none: raised in the alarm facility, dsky_alarm.ks, when it differs from the last cycle's), BLANK, FLASH, ENDED, HANDOVER, PROG_NO (and optionally more lamp keys, named in "LAMPS", and
//                "STATUS": a LIST of up to CORE_STATUS_ROWS text lines the core draws in place at the top of the terminal
//                every cycle, for a live readout)
//   "END"        delegate (prog): give the controls back
//   "SAMPLE"     delegate (prog), called every 0.02 s while the loop waits, or FALSE
//   "NEXT"       number of the programme to hand over to, or -1
//   "SELECTABLE" TRUE when V37 may start it
//   "TAKEOVER"   (optional) TRUE: a V37 or vehicle request does not end the running programme first. START gets it (FALSE when idle), as in
//                a handover. Refused: OPR ERR, and the running programme, its display, loads and requests are untouched. Started: the old
//                END is not called, and any load, update, request and extended display are cleared (core_take_over))
//   "BACKGROUND" (optional) TRUE: runs in the second slot, beside whatever programme is selected (see below)
// A pending request: while a step returns REQUEST the core keeps it in ks["PENDING"], flashes VERB and NOUN while the display shows exactly the
// request's verb and noun (and nothing is being typed), and lights KEY REL when the pilot keys over it (dsky_keys.ks has the rules). The step reads
// the pilot's answers in the key state ks: "PRO" (it clears it), and "RECYCLE" (V32), "TERMINATE" (V34) and "ENTER" (any ENTR), which the core
// clears after each step. A step without REQUEST can still use the old FLASH output. The vehicle may add "NO_NOUN_VERBS" (a LIST) and
// "VERB_ACTIONS" (verb as text -> delegate (ks) -> bool, FALSE = OPR ERR), see dsky_keys.ks, and "ALARM_SOURCE" (delegate (prog, now_ut) -> LIST of
// alarm codes to raise this cycle; each is raised and the display restarted, as after a software restart, see core_restart_display).
// Delegates are called with :CALL(...), the documented way to call a delegate held in a lexicon.
//
// The second slot (crun "BACK"): one BACKGROUND programme runs there, with the same START, STEP, END and output keys. V37 of another
// BACKGROUND number replaces it, its own number keeps it (no START), 0 ends it; any other selection leaves it. A verb action ends it by
// setting ks["END_BACK"]. Its STEP runs after the foreground's and the extended display's. Its lamp keys, FLASH, BLANK and HANDOVER are
// ignored; the first line of its STATUS is shown under the foreground's (core_status_texts); its EXTRA is merged under the foreground's and the extended display's; its alarms have their own LAST_BACK_ALARM. PROG shows
// its number when no foreground runs. Its SET_VERB applies only with no foreground, never together with a REQUEST, and reaches the display
// only when no request is pending, no extended display is up and the display is not the pilot's. P27 asks the vehicle about it when no
// foreground runs.
// Its REQUEST is a priority display: it waits while the pilot holds the DSKY (core_prio_hold; KEY REL lights), else it takes the DSKY and
// flashes (ks["PRIO"] keeps the display it covered). While it is up PRO, V32, V34 and ENTR go to the second slot only, which otherwise sees
// them all FALSE; the foreground and the extended display keep running but their display waits. When the request ends, the extended
// display's request, else the foreground's, else the idle request, else PROG_VN, else the covered display comes back (a display the pilot
// keyed over it stays). A foreground that ends leaves the second slot; when the second slot ends with no foreground, END_REQUEST is posted.
// core_run ends both on quit; HOOK and SAMPLE are the foreground's only.
//
// Extended-verb display (as Luminary's extended verbs): a verb action may set ks["EXT"] TO LEXICON("VERB", v, "NOUN", n, "STEP", delegate (nav) ->
// LEXICON merged into derived). While it is up:
//   * it sees the pilot's answers first: PRO (also V33) or V34 ends it, V32 leaves it (STEP runs every cycle, so it is recomputed); PRO, RECYCLE,
//     TERMINATE and ENTER are cleared before the programme's step;
//   * its verb and noun are shown on its first cycle and are the pending (flashing) request. The programme keeps running: its SET_VERB goes only to
//     PROG_VN, its REQUEST is held and its BLANK and FLASH are ignored; alarms, lamps, status lines and handovers work as normal;
//   * when it ends, the programme's request, else the standing idle request, else PROG_VN, else the verb and noun shown before it, come back;
//   * a programme that ends meanwhile leaves it up; V37 clears it. A priority display goes over it and then gives it back.
// Optional keys:
//   "END"      delegate (): called exactly once however the display ends (PRO, V34, ENDED, V37, the DSKY quitting): core_ext_drop.
//   "ANSWERS"  TRUE: an answering display. "STEP" is then a delegate (nav, ans), ans = LEXICON("PRO", "V32", "TERM", "ENTER") (booleans: the
//              pilot's answers this cycle; all FALSE on its first cycle and under a priority display; ENTER only while its display is shown), returning LEXICON("DERIVED", lex,
//              "VERB", n, "NOUN", n, "FLASH", bool, "ENDED", bool, "MSG", text[, "WARN", text]). The core does not end it on PRO or V34, shows a changed VERB
//              and NOUN (not over a display the pilot keyed, unless PRO or V32 asked for it), flashes only while FLASH, and ends it on ENDED
//              (a display the pilot keyed over it then stays).
//
// The terminal has three fixed areas and never scrolls: the live rows (STATUS, rows 0 to 2), the warnings block and the messages block, each under
// its heading, newest at the bottom, a full block dropping its oldest entry. A warning already shown is not added again; warnings stay until
// RSET (ks "RSET") or the next accepted V37 selection, messages until newer ones push them off. A vehicle's code outside a step says things with
// core_say(text) and core_warn(text), never PRINT (core_note(text) for the log only): they queue in CORE_OUTBOX until core_run shows them
// (core_drain). The cursor is left below the blocks, so that is where a kOS error prints.
//
// The run state (core_new) is a LEXICON: "PROG" (the running programme or FALSE), "ENTRY" (its table entry or FALSE), "BACK" and
// "BACK_ENTRY" (the same for the second slot), "BACK_NO", "FG_REQUEST" (the foreground's request of this cycle),
// "IDLE_TEXT" (what PROG shows with nothing running), "WARNS" and "MSGS" (the two blocks' texts), "LOG" (the log's path, "" none), "CLOCK"
// (LOG_CLOCK or FALSE), "SCREEN" (TRUE once core_screen_start has drawn the terminal; until then nothing is drawn).
// Needs dsky_keys.ks, dsky_display.ks (zero_pad, pad_right) and, for core_run, a GUI with gui_poll / gui_update (the vehicle's window file).

RUNONCEPATH("0:/core/dsky_keys.ks").
RUNONCEPATH("0:/core/dsky_display.ks").
RUNONCEPATH("0:/core/dsky_uplink.ks").

// The terminal's rows: the live rows, a blank one, the warnings heading and block, a blank one, the messages heading and block.
GLOBAL CORE_STATUS_ROWS IS 3.
GLOBAL CORE_WARN_ROWS IS 6.
GLOBAL CORE_MSG_ROWS IS 8.                        // fewer on a low terminal (core_message_rows)
GLOBAL CORE_MSG_WIDTH IS 48.
GLOBAL CORE_WARN_ROW IS CORE_STATUS_ROWS + 2.     // the first row of each block; its heading is the row above
GLOBAL CORE_MSG_ROW IS CORE_WARN_ROW + CORE_WARN_ROWS + 2.
GLOBAL CORE_WARN_HEADING IS "WARNINGS ---------------------------------------".
GLOBAL CORE_MSG_HEADING IS "MESSAGES ---------------------------------------".
GLOBAL CORE_OUTBOX IS LIST().                     // what core_say, core_warn and core_note queued: LEXICON("WARN", bool, "TEXT", text, "LOG_ONLY", bool)

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

// ---- the terminal: what each area holds (pure), then the drawing ----

// core_status_texts: the live rows: the foreground's lines, then under (the second slot's line, "" none) in the first free row, then "". Pure.
FUNCTION core_status_texts {
  PARAMETER lines, under.
  LOCAL rows IS LIST().
  FOR line_text IN lines { IF rows:LENGTH < CORE_STATUS_ROWS { rows:ADD(line_text). } }
  IF under <> "" AND rows:LENGTH < CORE_STATUS_ROWS { rows:ADD(under). }
  UNTIL rows:LENGTH >= CORE_STATUS_ROWS { rows:ADD(""). }
  RETURN rows.
}

// core_wrapped: every entry of a block, word-wrapped, oldest first. Pure.
FUNCTION core_wrapped {
  PARAMETER entries.
  LOCAL lines IS LIST().
  FOR entry_text_now IN entries {
    FOR line_text IN core_wrap(entry_text_now, CORE_MSG_WIDTH) { lines:ADD(line_text). }
  }
  RETURN lines.
}

// core_block_add: add text to a block of rows lines (once: not when the block holds it already), dropping the oldest entries while they do not fit,
// never the newest. Returns TRUE when it was added. "" is not added. Pure apart from entries.
FUNCTION core_block_add {
  PARAMETER entries, text, rows, once.
  IF text = "" { RETURN FALSE. }
  IF once { IF entries:CONTAINS(text) { RETURN FALSE. } }
  entries:ADD(text).
  UNTIL entries:LENGTH <= 1 OR core_wrapped(entries):LENGTH <= rows { entries:REMOVE(0). }
  RETURN TRUE.
}

// core_block_lines: the lines a block shows, at most rows, newest last. A lone entry too long for the block keeps its first lines (its start says
// what it is); otherwise the oldest lines go. Pure.
FUNCTION core_block_lines {
  PARAMETER entries, rows.
  LOCAL lines IS core_wrapped(entries).
  UNTIL lines:LENGTH <= rows {
    IF entries:LENGTH <= 1 { lines:REMOVE(lines:LENGTH - 1). } ELSE { lines:REMOVE(0). }
  }
  RETURN lines.
}

// core_message_rows: the messages block's rows on a terminal of that height. Pure.
FUNCTION core_message_rows {
  PARAMETER height.
  RETURN MAX(1, MIN(CORE_MSG_ROWS, height - CORE_MSG_ROW - 1)).
}

// core_log_line: one line of the log. Pure.
FUNCTION core_log_line {
  PARAMETER clock_text, text, is_warning.
  IF is_warning { RETURN clock_text + "  WARNING: " + text. }
  RETURN clock_text + "  " + text.
}

// core_log: add a line to the run state's log, if it has one.
FUNCTION core_log {
  PARAMETER crun, text, is_warning.
  IF crun["LOG"] = "" { RETURN. }
  LOCAL clock_text IS "".
  IF NOT crun["CLOCK"]:ISTYPE("Boolean") { SET clock_text TO crun["CLOCK"]:CALL(). }
  LOG core_log_line(clock_text, text, is_warning) TO crun["LOG"].
}

// core_put: one row of the terminal, padded to the width; a row below the terminal's last is left out.
FUNCTION core_put {
  PARAMETER row, text.
  IF row < TERMINAL:HEIGHT { PRINT pad_right(text, CORE_MSG_WIDTH) AT (0, row). }
}

// core_park_row: the first row under the messages block, where the cursor is left.
FUNCTION core_park_row {
  RETURN MIN(CORE_MSG_ROW + core_message_rows(TERMINAL:HEIGHT), TERMINAL:HEIGHT - 1).
}

// core_park: leave the cursor under the blocks, so that anything printed by kOS itself (an error) lands there and not over them.
FUNCTION core_park {
  PRINT "" AT (0, core_park_row()).
}

// core_block_draw: draw one block, "WARNS" or "MSGS". Nothing before core_screen_start.
FUNCTION core_block_draw {
  PARAMETER crun, block_key.
  IF NOT crun["SCREEN"] { RETURN. }
  LOCAL first_row IS CORE_WARN_ROW.
  LOCAL rows IS CORE_WARN_ROWS.
  IF block_key = "MSGS" {
    SET first_row TO CORE_MSG_ROW.
    SET rows TO core_message_rows(TERMINAL:HEIGHT).
  }
  LOCAL lines IS core_block_lines(crun[block_key], rows).
  FROM { LOCAL i IS 0. } UNTIL i >= rows STEP { SET i TO i + 1. } DO {
    LOCAL shown IS "".
    IF i < lines:LENGTH { SET shown TO lines[i]. }
    core_put(first_row + i, shown).
  }
  core_park().
}

// core_message: show a message (and log it).
FUNCTION core_message {
  PARAMETER crun, text.
  IF core_block_add(crun["MSGS"], text, core_message_rows(TERMINAL:HEIGHT), FALSE) {
    core_log(crun, text, FALSE).
    core_block_draw(crun, "MSGS").
  }
}

// core_warning: show a warning (and log it), unless it is shown already.
FUNCTION core_warning {
  PARAMETER crun, text.
  IF core_block_add(crun["WARNS"], text, CORE_WARN_ROWS, TRUE) {
    core_log(crun, text, TRUE).
    core_block_draw(crun, "WARNS").
  }
}

// core_warnings_clear: empty the warnings block (RSET, or a new V37 selection).
FUNCTION core_warnings_clear {
  PARAMETER crun.
  crun["WARNS"]:CLEAR().
  core_block_draw(crun, "WARNS").
}

// core_say, core_warn, core_note: for a vehicle's code outside a step: queue a message, a warning, or a line for the log only.
FUNCTION core_say {
  PARAMETER text.
  CORE_OUTBOX:ADD(LEXICON("WARN", FALSE, "TEXT", text, "LOG_ONLY", FALSE)).
}
FUNCTION core_warn {
  PARAMETER text.
  CORE_OUTBOX:ADD(LEXICON("WARN", TRUE, "TEXT", text, "LOG_ONLY", FALSE)).
}
FUNCTION core_note {
  PARAMETER text.
  CORE_OUTBOX:ADD(LEXICON("WARN", FALSE, "TEXT", text, "LOG_ONLY", TRUE)).
}

// core_drain: show what was queued, in order, and empty the queue.
FUNCTION core_drain {
  PARAMETER crun.
  UNTIL CORE_OUTBOX:LENGTH = 0 {
    LOCAL queued IS CORE_OUTBOX[0].
    CORE_OUTBOX:REMOVE(0).
    IF queued["LOG_ONLY"] { core_log(crun, queued["TEXT"], FALSE). }
    ELSE IF queued["WARN"] { core_warning(crun, queued["TEXT"]). }
    ELSE { core_message(crun, queued["TEXT"]). }
  }
}

// core_status_draw: draw the live rows (core_status_texts) over rows 0 to 2. It never clears the screen. Nothing before core_screen_start.
FUNCTION core_status_draw {
  PARAMETER crun, lines, under.
  IF NOT crun["SCREEN"] { RETURN. }
  LOCAL rows IS core_status_texts(lines, under).
  FROM { LOCAL i IS 0. } UNTIL i >= rows:LENGTH STEP { SET i TO i + 1. } DO { core_put(i, rows[i]). }
  core_park().
}

// core_screen_start: the one clearing of the terminal: headings and blocks, the cursor under them.
FUNCTION core_screen_start {
  PARAMETER crun.
  CLEARSCREEN.
  FROM { LOCAL i IS 0. } UNTIL i >= core_park_row() STEP { SET i TO i + 1. } DO { PRINT "". }
  SET crun["SCREEN"] TO TRUE.
  core_put(CORE_WARN_ROW - 1, CORE_WARN_HEADING).
  core_put(CORE_MSG_ROW - 1, CORE_MSG_HEADING).
  core_block_draw(crun, "WARNS").
  core_block_draw(crun, "MSGS").
}

// core_new: a fresh run state, nothing running.
FUNCTION core_new {
  PARAMETER vehicle.
  LOCAL log_path IS "".
  IF vehicle:HASKEY("LOG_FILE") { SET log_path TO vehicle["LOG_FILE"]. }
  LOCAL log_clock IS FALSE.
  IF vehicle:HASKEY("LOG_CLOCK") { SET log_clock TO vehicle["LOG_CLOCK"]. }
  RETURN LEXICON("PROG", FALSE, "ENTRY", FALSE, "IDLE_TEXT", "00", "LAST_ALARM", 0, "IDLE_REQUEST", FALSE,
                 "BACK", FALSE, "BACK_ENTRY", FALSE, "BACK_NO", -1, "LAST_BACK_ALARM", 0, "FG_REQUEST", FALSE,
                 "WARNS", LIST(), "MSGS", LIST(), "LOG", log_path, "CLOCK", log_clock, "SCREEN", FALSE).
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

// core_end_back: end the second slot's programme (its END), once. Safe to call with nothing in the slot.
FUNCTION core_end_back {
  PARAMETER crun, vehicle.
  IF crun["BACK"]:ISTYPE("Lexicon") {
    LOCAL ended_prog IS crun["BACK"].
    LOCAL ended_entry IS crun["BACK_ENTRY"].
    SET crun["BACK"] TO FALSE.
    SET crun["BACK_ENTRY"] TO FALSE.
    SET crun["BACK_NO"] TO -1.
    SET crun["LAST_BACK_ALARM"] TO 0.
    ended_entry["END"]:CALL(ended_prog).
  }
}

// core_v37_hook: the vehicle's V37_HOOK, if it has one, hears the number of every accepted selection.
FUNCTION core_v37_hook {
  PARAMETER vehicle, number.
  IF vehicle:HASKEY("V37_HOOK") { vehicle["V37_HOOK"]:CALL(number). }
}

// core_flashes: TRUE when the display shows exactly the request's verb and noun with nothing being typed, so it flashes.
FUNCTION core_flashes {
  PARAMETER ks, request.
  IF NOT request:ISTYPE("Lexicon") { RETURN FALSE. }
  RETURN ks["VERB"] = request["VERB"] AND ks["NOUN"] = request["NOUN"] AND ks["MODE"] = "" AND NOT ks["AWAIT_PROG"].
}

// core_pilot_typing: TRUE while something is being keyed in: a verb or noun, a programme number, a load or an update.
FUNCTION core_pilot_typing {
  PARAMETER ks.
  RETURN ks["MODE"] <> "" OR ks["AWAIT_PROG"] OR load_active(ks) OR p27_active(ks).
}

// core_pilot_has: TRUE while the display is the pilot's: typing, a verb and noun of their own up (ks "OWN"), or KEY REL lit.
FUNCTION core_pilot_has {
  PARAMETER ks.
  RETURN core_pilot_typing(ks) OR ks["OWN"] OR ks["KEYREL"].
}

// core_prio_hold: TRUE while the pilot holds the DSKY, so that a priority display must wait (core_pilot_has, or the display over the programme's).
FUNCTION core_prio_hold {
  PARAMETER ks.
  RETURN core_pilot_has(ks) OR key_covers_program(ks).
}

// core_show: a programme or a display puts its own verb and noun up; the display is no longer the pilot's.
FUNCTION core_show {
  PARAMETER ks, verb_no, noun_no.
  SET ks["VERB"] TO verb_no.
  SET ks["NOUN"] TO noun_no.
  SET ks["OWN"] TO FALSE.
}

// core_running: the programme the vehicle is asked about (P27): the foreground, else the second slot's, else FALSE.
FUNCTION core_running {
  PARAMETER crun.
  IF crun["PROG"]:ISTYPE("Lexicon") { RETURN crun["PROG"]. }
  RETURN crun["BACK"].
}

// core_prio_covered: has the pilot keyed over the priority display prio?
FUNCTION core_prio_covered {
  PARAMETER ks, prio.
  IF load_active(ks) OR p27_active(ks) { RETURN TRUE. }
  RETURN NOT core_flashes(ks, prio).
}

// core_waiting_request: what is waiting behind a priority display: the extended display's request, else the foreground's, else the standing one.
FUNCTION core_waiting_request {
  PARAMETER crun, ks.
  IF ks["EXT"]:ISTYPE("Lexicon") { RETURN LEXICON("VERB", ks["EXT"]["VERB"], "NOUN", ks["EXT"]["NOUN"]). }
  IF crun["FG_REQUEST"]:ISTYPE("Lexicon") { RETURN crun["FG_REQUEST"]. }
  RETURN crun["IDLE_REQUEST"].
}

// core_prio_off: the priority display is over. The DSKY goes back to what was waiting (else the foreground's verb and noun, else what was shown
// before), unless the pilot has keyed over the priority display: then theirs stays, and KEY REL brings the waiting display back.
FUNCTION core_prio_off {
  PARAMETER crun, ks.
  IF NOT ks["PRIO"]:ISTYPE("Lexicon") { RETURN. }
  LOCAL prio IS ks["PRIO"].
  LOCAL covered IS core_prio_covered(ks, prio).
  SET ks["PRIO"] TO FALSE.
  SET ks["PENDING"] TO core_waiting_request(crun, ks).
  IF NOT covered {
    SET ks["VERB"] TO prio["BEFORE"][0].
    SET ks["NOUN"] TO prio["BEFORE"][1].
    key_rel_press(ks).
  }
}

// core_prio_clear: drop the priority display for a new selection: the display it covered comes back, and no request is left pending.
FUNCTION core_prio_clear {
  PARAMETER ks.
  IF NOT ks["PRIO"]:ISTYPE("Lexicon") { RETURN. }
  LOCAL prio IS ks["PRIO"].
  IF ks["VERB"] = prio["VERB"] AND ks["NOUN"] = prio["NOUN"] {
    SET ks["VERB"] TO prio["BEFORE"][0].
    SET ks["NOUN"] TO prio["BEFORE"][1].
  }
  SET ks["PRIO"] TO FALSE.
  SET ks["PENDING"] TO FALSE.
  SET ks["KEYREL"] TO FALSE.
}

// core_prio_update: the second slot's request of this cycle (FALSE none). A new one takes the DSKY as a priority display unless the pilot holds it
// (KEY REL lights and it waits); one already up follows the request; none ends it.
FUNCTION core_prio_update {
  PARAMETER crun, ks, request, flags.
  IF NOT request:ISTYPE("Lexicon") {
    IF ks["PRIO"]:ISTYPE("Lexicon") {
      core_prio_off(crun, ks).
      SET flags["FLASH"] TO core_flashes(ks, ks["PENDING"]).
    }
    RETURN.
  }
  IF NOT ks["PRIO"]:ISTYPE("Lexicon") {
    IF core_prio_hold(ks) { SET flags["KEYREL"] TO TRUE. RETURN. }
    SET ks["PRIO"] TO LEXICON("VERB", request["VERB"], "NOUN", request["NOUN"], "BEFORE", LIST(ks["VERB"], ks["NOUN"])).
    core_show(ks, request["VERB"], request["NOUN"]).
    SET ks["PRO"] TO FALSE.             // a PRO the foreground has not read was pressed before this display: it is no answer to it
  } ELSE {
    LOCAL prio IS ks["PRIO"].
    IF NOT core_prio_covered(ks, prio) {
      SET ks["VERB"] TO request["VERB"].
      SET ks["NOUN"] TO request["NOUN"].
    }
    SET prio["VERB"] TO request["VERB"].
    SET prio["NOUN"] TO request["NOUN"].
  }
  SET ks["PENDING"] TO request.
  SET flags["BLANK"] TO FALSE.
  SET flags["FLASH"] TO core_flashes(ks, request).
}

// core_post_end_request: after a programme has ended, the vehicle's standing request (END_REQUEST) is posted. It is shown unless an extended or a
// priority display has the DSKY, or held is TRUE (the pilot is typing: KEY REL then brings it); returns TRUE when shown.
FUNCTION core_post_end_request {
  PARAMETER crun, vehicle, ks, held IS FALSE.
  IF NOT vehicle:HASKEY("END_REQUEST") { RETURN FALSE. }
  SET crun["IDLE_REQUEST"] TO vehicle["END_REQUEST"].
  IF held OR ks["EXT"]:ISTYPE("Lexicon") OR ks["PRIO"]:ISTYPE("Lexicon") { RETURN FALSE. }
  SET ks["PENDING"] TO crun["IDLE_REQUEST"].
  key_rel_press(ks).                 // shows it: verb and noun from the request, typed digits dropped
  RETURN TRUE.
}

// core_back_ended: the second slot is finished (its ENDED, or END_BACK with restart TRUE, which also does a display restart): END once, the
// priority display goes, and with no foreground programme the standing request is posted. Returns TRUE when that request is shown.
FUNCTION core_back_ended {
  PARAMETER crun, vehicle, ks, restart.
  core_end_back(crun, vehicle).
  core_prio_off(crun, ks).
  IF restart { core_restart_display(ks). }
  IF crun["PROG"]:ISTYPE("Lexicon") { RETURN FALSE. }
  RETURN core_post_end_request(crun, vehicle, ks, NOT restart AND core_pilot_typing(ks)).
}

// core_request: one V37 request, number = the programme asked for (0 = none). A number the vehicle has no selectable
// entry for lights OPR ERR and changes nothing (the running programmes carry on). A TAKEOVER entry goes to
// core_take_over. Otherwise the foreground programme is ended first, so asking for the running one again restarts it.
// A BACKGROUND entry goes to the second slot: the same number already there is left alone (no START), another replaces it.
// Any other number leaves the second slot alone; 0 ends both. A BACKGROUND selection made over the standing request blanks that off the display.
// An accepted selection empties the warnings before anything is ended or started (a take-over: once it has started).
// A START that refuses lights OPR ERR and returns the reason
// in WARN. Returns LEXICON("MSG", text, "WARN", text) (a text is "" when there is nothing to say).
FUNCTION core_request {
  PARAMETER crun, vehicle, ks, number.
  LOCAL entry IS FALSE.
  IF number <> 0 {
    SET entry TO core_entry(vehicle, number).
    LOCAL ok IS FALSE.
    IF entry:ISTYPE("Lexicon") { IF entry["SELECTABLE"] { SET ok TO TRUE. } }   // nested: AND would not skip the lookup
    IF NOT ok {
      SET ks["OPRERR"] TO TRUE.
      RETURN LEXICON("MSG", "", "WARN", "").
    }
    IF entry:HASKEY("TAKEOVER") { IF entry["TAKEOVER"] { RETURN core_take_over(crun, vehicle, ks, number, entry). } }
  }
  LOCAL background IS FALSE.
  IF entry:ISTYPE("Lexicon") { IF entry:HASKEY("BACKGROUND") { SET background TO entry["BACKGROUND"]. } }
  LOCAL msg IS "".
  LOCAL warn IS "".
  core_warnings_clear(crun).                  // before any END or START: what they warn of stays
  core_ext_drop(ks).                          // a V37 selection ends an extended-verb display
  core_prio_clear(ks).
  SET ks["OWN"] TO FALSE.
  LOCAL standing IS crun["IDLE_REQUEST"].
  // The standing request on the display (V37 N99) is answered by this selection.
  LOCAL standing_shown IS FALSE.
  IF standing:ISTYPE("Lexicon") { SET standing_shown TO ks["VERB"] = standing["VERB"] AND ks["NOUN"] = standing["NOUN"]. }
  SET crun["IDLE_TEXT"] TO "00".
  SET crun["IDLE_REQUEST"] TO FALSE.          // a V37 selection answers the standing request (see core_step)
  SET crun["FG_REQUEST"] TO FALSE.
  LOCAL front_ended IS crun["PROG"]:ISTYPE("Lexicon").
  IF front_ended {
    core_end(crun, vehicle).
    SET msg TO "Programme ended.".
  }
  LOCAL kept IS FALSE.
  IF crun["BACK"]:ISTYPE("Lexicon") AND (number = 0 OR background) {
    IF crun["BACK_NO"] = number {
      SET kept TO TRUE.
    } ELSE {
      core_end_back(crun, vehicle).
      SET msg TO "Programme ended.".
    }
  }
  IF front_ended AND crun["BACK"]:ISTYPE("Lexicon") { SET ks["PROG_VN"] TO LIST(-1, -1). }    // the ended programme's display is gone
  core_v37_hook(vehicle, number).
  IF number <> 0 AND NOT kept {
    LOCAL started IS entry["START"]:CALL(FALSE).
    IF started["REFUSED"] <> "" {
      SET ks["OPRERR"] TO TRUE.
      SET warn TO "P" + zero_pad(number, 2) + " refused: " + started["REFUSED"] + ".".
      SET standing_shown TO FALSE.
    } ELSE IF background {
      SET crun["BACK"] TO started.
      SET crun["BACK_ENTRY"] TO entry.
      SET crun["BACK_NO"] TO number.
    } ELSE {
      SET crun["PROG"] TO started.
      SET crun["ENTRY"] TO entry.
    }
  }
  // A second-slot programme may have nothing to show for a while: the answered request must not stay up as if nothing had been selected.
  IF background AND standing_shown {
    SET ks["VERB"] TO -1.
    SET ks["NOUN"] TO -1.
  }
  RETURN LEXICON("MSG", msg, "WARN", warn).
}

// core_take_over: a TAKEOVER programme asked for. Its START gets the running programme (FALSE when idle) before anything is changed, so a refusal
// leaves everything as it was. Started, it replaces the running programme without calling its END (the new one has its controls), and what the old
// one had on the DSKY goes: a keyed load, an update, the pending and standing requests, an extended display, typed keys and unread answers.
// Returns LEXICON("MSG", text, "WARN", text).
FUNCTION core_take_over {
  PARAMETER crun, vehicle, ks, number, entry.
  LOCAL started IS entry["START"]:CALL(crun["PROG"]).
  IF started["REFUSED"] <> "" {
    SET ks["OPRERR"] TO TRUE.
    RETURN LEXICON("MSG", "", "WARN", "P" + zero_pad(number, 2) + " refused: " + started["REFUSED"] + ".").
  }
  core_warnings_clear(crun).
  core_ext_drop(ks).
  core_prio_clear(ks).
  SET ks["PENDING"] TO FALSE.
  SET ks["PROG_VN"] TO LIST(-1, -1).          // so the restart below leaves the display as it is
  core_restart_display(ks).
  SET ks["PRO"] TO FALSE.
  SET ks["TERMINATE"] TO FALSE.
  SET ks["RECYCLE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  SET crun["IDLE_TEXT"] TO "00".
  SET crun["IDLE_REQUEST"] TO FALSE.
  SET crun["LAST_ALARM"] TO 0.
  SET crun["FG_REQUEST"] TO FALSE.
  SET crun["PROG"] TO started.
  SET crun["ENTRY"] TO entry.
  core_v37_hook(vehicle, number).
  RETURN LEXICON("MSG", "", "WARN", "").
}

// core_vehicle_request: the vehicle's REQUEST_SOURCE, if it has one, may ask for a programme this cycle. Returns what that request returned
// (both texts "" when it asked for nothing).
FUNCTION core_vehicle_request {
  PARAMETER crun, vehicle, ks, now_ut.
  IF NOT vehicle:HASKEY("REQUEST_SOURCE") { RETURN LEXICON("MSG", "", "WARN", ""). }
  LOCAL asked IS vehicle["REQUEST_SOURCE"]:CALL(crun["PROG"], now_ut).
  IF asked < 0 { RETURN LEXICON("MSG", "", "WARN", ""). }
  RETURN core_request(crun, vehicle, ks, asked).
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
// Returns the warning text ("" when the handover went through).
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

// core_scripted_alarms: the vehicle's ALARM_SOURCE (if it has one) names the alarm codes due now; each is raised and warned of, and a software restart
// then reshows the display (core_restart_display). Returns how many codes were raised. The programme's START and END are not called.
FUNCTION core_scripted_alarms {
  PARAMETER ks, vehicle, prog, now_ut.
  IF NOT vehicle:HASKEY("ALARM_SOURCE") { RETURN 0. }
  LOCAL due IS vehicle["ALARM_SOURCE"]:CALL(prog, now_ut).
  FOR code IN due {
    alarm_raise(ks["ALARM"], code).
    core_warn("ALARM " + zero_pad(code, 5) + ".").
  }
  IF due:LENGTH > 0 { core_restart_display(ks). }
  RETURN due:LENGTH.
}

// core_ext_answers: does this extended display take the pilot's answers itself?
FUNCTION core_ext_answers {
  PARAMETER ext.
  IF NOT ext:HASKEY("ANSWERS") { RETURN FALSE. }
  RETURN ext["ANSWERS"].
}

// core_ext_drop: the extended display is over, however it ended: it is taken away and its END, if it has one, runs. Safe with none up.
FUNCTION core_ext_drop {
  PARAMETER ks.
  IF NOT ks["EXT"]:ISTYPE("Lexicon") { RETURN. }
  LOCAL ext IS ks["EXT"].
  SET ks["EXT"] TO FALSE.                     // cleared first, so a second call cannot call END again
  IF ext:HASKEY("END") { ext["END"]:CALL(). }
}

// core_ext_begin: the extended-verb display's turn before the programme's step (see the header). Shows it on its first cycle (keeping the display it
// covers), takes the pilot's answers and clears them (an answering display's are kept in its "ANS"). Returns TRUE when it ended this cycle
// (ks["EXT"] is then FALSE).
FUNCTION core_ext_begin {
  PARAMETER ks.
  LOCAL ext IS ks["EXT"].
  LOCAL first IS NOT ext:HASKEY("BEFORE").
  IF first {
    IF ks["PRIO"]:ISTYPE("Lexicon") {
      SET ext["BEFORE"] TO ks["PRIO"]["BEFORE"].        // under a priority display: it shows when that one ends
    } ELSE {
      SET ext["BEFORE"] TO LIST(ks["VERB"], ks["NOUN"]).
      core_show(ks, ext["VERB"], ext["NOUN"]).
      SET ks["KEYREL"] TO FALSE.
    }
  }
  LOCAL ending IS FALSE.
  IF core_ext_answers(ext) {
    // The ENTR of the verb that asked for the display is no answer to it.
    // ENTR answers it only while it is the display shown (not the ENTR of a verb the pilot keyed over it).
    LOCAL entered IS ks["ENTER"] AND ks["VERB"] = ext["VERB"] AND ks["NOUN"] = ext["NOUN"].
    SET ext["ANS"] TO LEXICON("PRO", ks["PRO"] AND NOT first, "V32", ks["RECYCLE"] AND NOT first,
                              "TERM", ks["TERMINATE"] AND NOT first, "ENTER", entered AND NOT first).
  } ELSE {
    SET ending TO ks["PRO"] OR ks["TERMINATE"].
  }
  SET ks["PRO"] TO FALSE.
  SET ks["TERMINATE"] TO FALSE.
  SET ks["RECYCLE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  IF ending { core_ext_drop(ks). }
  RETURN ending.
}

// core_ext_restore: the extended display has ended: the request, else the programme's verb and noun, else before (what it covered) comes back
// (key_rel_press). Under a priority display, before becomes what that one gives back.
FUNCTION core_ext_restore {
  PARAMETER ks, before, flags.
  IF ks["PRIO"]:ISTYPE("Lexicon") {
    SET ks["PRIO"]["BEFORE"] TO before.
    RETURN.
  }
  SET ks["VERB"] TO before[0].
  SET ks["NOUN"] TO before[1].
  key_rel_press(ks).
  IF ks["PENDING"]:ISTYPE("Lexicon") { SET flags["FLASH"] TO TRUE. }
}

// core_ext_run: the extended display's turn after the programme's step: its STEP supplies the values, and while up it is the request on the DSKY
// (whatever the programme asked for waits; it asks again every cycle). An answering display also says its verb and noun, whether they flash, and
// when it has ended. Under a priority display it runs but its request waits. The keys of its values are added to taken (the second slot's values
// do not replace them). A changed verb and noun do not replace a display the pilot keyed over it, unless this cycle's PRO or V32 asked for
// the change and nothing is being typed. Returns LEXICON("MSG", its message, "WARN", its warning).
FUNCTION core_ext_run {
  PARAMETER ks, nav, flags, taken.
  LOCAL ext IS ks["EXT"].
  LOCAL values IS LEXICON().
  LOCAL result IS FALSE.
  IF core_ext_answers(ext) {
    SET result TO ext["STEP"]:CALL(nav, ext["ANS"]).
    SET values TO result["DERIVED"].
  } ELSE {
    SET values TO ext["STEP"]:CALL(nav).
  }
  FOR value_key IN values:KEYS {
    SET nav["DERIVED"][value_key] TO values[value_key].
    SET taken[value_key] TO values[value_key].
  }
  LOCAL prio_up IS ks["PRIO"]:ISTYPE("Lexicon").
  LOCAL flashing IS TRUE.
  LOCAL msg IS "".
  LOCAL warn IS "".
  IF result:ISTYPE("Lexicon") {
    SET msg TO result["MSG"].
    IF result:HASKEY("WARN") { SET warn TO result["WARN"]. }
    SET flashing TO result["FLASH"].
    IF result["ENDED"] {
      // A display the pilot keyed over it (or a load under way) stays.
      LOCAL covered IS core_prio_covered(ks, ext).
      core_ext_drop(ks).
      IF prio_up OR NOT covered { core_ext_restore(ks, ext["BEFORE"], flags). }
      RETURN LEXICON("MSG", msg, "WARN", warn).
    }
    IF result["VERB"] <> ext["VERB"] OR result["NOUN"] <> ext["NOUN"] {
      LOCAL answered IS ext["ANS"]["PRO"] OR ext["ANS"]["V32"].
      LOCAL free IS NOT core_prio_covered(ks, ext) OR (answered AND NOT core_pilot_typing(ks)).
      SET ext["VERB"] TO result["VERB"].
      SET ext["NOUN"] TO result["NOUN"].
      IF free AND NOT prio_up { core_show(ks, ext["VERB"], ext["NOUN"]). }
    }
  }
  IF NOT prio_up {
    SET ks["PENDING"] TO LEXICON("VERB", ext["VERB"], "NOUN", ext["NOUN"]).
    SET flags["FLASH"] TO flashing AND core_flashes(ks, ks["PENDING"]).
  }
  RETURN LEXICON("MSG", msg, "WARN", warn).
}

// core_back_step: the second slot's turn, after the foreground's and the extended display's. answers: the pilot's answers set aside for a
// priority display (all FALSE with none up); taken: the foreground's and the extended display's values, which win over this programme's. Its STEP sees exactly those
// answers; ks["PRO"] is put back to what the foreground left. Returns LEXICON("MSG", text, "WARN", text, "PROG_TEXT", text ("" once it has ended),
// "UNDER", its status line).
FUNCTION core_back_step {
  PARAMETER crun, vehicle, nav, ks, answers, taken, flags.
  LOCAL front_pro IS ks["PRO"].
  FOR answer_key IN answers:KEYS { SET ks[answer_key] TO answers[answer_key]. }
  LOCAL out IS crun["BACK_ENTRY"]["STEP"]:CALL(crun["BACK"], nav, ks).
  SET ks["PRO"] TO front_pro.
  FOR extra_key IN out["EXTRA"]:KEYS {
    IF NOT taken:HASKEY(extra_key) { SET nav["DERIVED"][extra_key] TO out["EXTRA"][extra_key]. }
  }
  IF out["ALARM"] > 0 AND out["ALARM"] <> crun["LAST_BACK_ALARM"] { alarm_raise(ks["ALARM"], out["ALARM"]). }
  SET crun["LAST_BACK_ALARM"] TO out["ALARM"].
  LOCAL warn IS "".
  IF out:HASKEY("WARN") { SET warn TO out["WARN"]. }
  IF out["ENDED"] {
    IF core_back_ended(crun, vehicle, ks, FALSE) { SET flags["FLASH"] TO TRUE. }
    ELSE IF ks["PENDING"]:ISTYPE("Lexicon") { SET flags["FLASH"] TO core_flashes(ks, ks["PENDING"]). }
    RETURN LEXICON("MSG", core_join(out["MSG"], "P" + out["PROG_NO"] + " ended."), "WARN", warn, "PROG_TEXT", "", "UNDER", "").
  }
  LOCAL request IS FALSE.
  IF out:HASKEY("REQUEST") { SET request TO out["REQUEST"]. }
  core_prio_update(crun, ks, request, flags).
  // Its own verb and noun: only with no foreground, and not while it asks (the request drives the display then).
  IF out["SET_VERB"] >= 0 AND NOT request:ISTYPE("Lexicon") AND NOT crun["PROG"]:ISTYPE("Lexicon") {
    SET ks["PROG_VN"] TO LIST(out["SET_VERB"], out["SET_NOUN"]).
    // Nor over a request that is up (V37 N99), an extended or priority display, or the pilot's display.
    IF NOT ks["PENDING"]:ISTYPE("Lexicon") AND NOT ks["EXT"]:ISTYPE("Lexicon") AND NOT core_pilot_has(ks) {
      core_show(ks, out["SET_VERB"], out["SET_NOUN"]).
    }
  }
  LOCAL under IS "".
  IF out:HASKEY("STATUS") { IF out["STATUS"]:LENGTH > 0 { SET under TO out["STATUS"][0]. } }
  RETURN LEXICON("MSG", out["MSG"], "WARN", warn, "PROG_TEXT", "" + out["PROG_NO"], "UNDER", under).
}

// core_step: one cycle of the running programmes (or of the idle display). Runs the foreground STEP, applies its display requests
// to the key state ks and the derived values, maps its lamp outputs through the vehicle's LAMPS, and handles its end
// or handover; then the extended display and the second slot. While a priority display is up, PRO, V32, V34 and ENTR are
// its answers, and the foreground's and the extended display's requests wait. Returns LEXICON("FLAGS", the flags lexicon for the display, "PROG_TEXT", PROG text, "MSG", text,
// "WARN", text, "STATUS", LIST of status lines (empty when the programme gave none or none runs), "UNDER", the second slot's status line).
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
  LOCAL warn IS "".
  LOCAL status_lines IS LIST().
  LOCAL ext_before IS LIST().        // the display under an extended-verb display that ended this cycle
  IF ks["END_BACK"] {
    SET ks["END_BACK"] TO FALSE.
    IF crun["BACK"]:ISTYPE("Lexicon") { core_back_ended(crun, vehicle, ks, TRUE). }
  }
  LOCAL prio_up IS ks["PRIO"]:ISTYPE("Lexicon").      // a priority display up at the start of the cycle has the DSKY
  LOCAL answers IS LEXICON("PRO", FALSE, "RECYCLE", FALSE, "TERMINATE", FALSE, "ENTER", FALSE).
  IF prio_up {
    FOR answer_key IN LIST("PRO", "RECYCLE", "TERMINATE", "ENTER") {
      SET answers[answer_key] TO ks[answer_key].
      SET ks[answer_key] TO FALSE.
    }
  }
  LOCAL taken IS LEXICON().          // the values the foreground and the extended display gave: the second slot does not replace them
  LOCAL front_ran IS FALSE.
  IF ks["EXT"]:ISTYPE("Lexicon") {
    LOCAL ext IS ks["EXT"].
    IF core_ext_begin(ks) { SET ext_before TO ext["BEFORE"]. }
  }
  LOCAL ext_up IS ks["EXT"]:ISTYPE("Lexicon").
  LOCAL covered IS ext_up OR prio_up.          // the programme's display is held back
  IF crun["PROG"]:ISTYPE("Lexicon") {
    SET front_ran TO TRUE.
    LOCAL entry IS crun["ENTRY"].
    LOCAL out IS entry["STEP"]:CALL(crun["PROG"], nav, ks).
    IF out["SET_VERB"] >= 0 AND NOT covered { core_show(ks, out["SET_VERB"], out["SET_NOUN"]). }
    FOR extra_key IN out["EXTRA"]:KEYS {
      SET derived[extra_key] TO out["EXTRA"][extra_key].
      SET taken[extra_key] TO out["EXTRA"][extra_key].
    }
    SET msg TO out["MSG"].
    IF out:HASKEY("WARN") { SET warn TO out["WARN"]. }
    IF out["SET_VERB"] >= 0 { SET ks["PROG_VN"] TO LIST(out["SET_VERB"], out["SET_NOUN"]). }
    SET crun["FG_REQUEST"] TO FALSE.
    IF out:HASKEY("REQUEST") { SET crun["FG_REQUEST"] TO out["REQUEST"]. }
    IF NOT prio_up { SET ks["PENDING"] TO crun["FG_REQUEST"]. }
    IF out:HASKEY("STATUS") { SET status_lines TO out["STATUS"]. }
    // A lamp key the programme did not return (a lamp only later programmes drive) leaves the flag as it was.
    FOR lamp_key IN vehicle["LAMPS"]:KEYS {
      IF out:HASKEY(lamp_key) { SET flags[vehicle["LAMPS"][lamp_key]] TO out[lamp_key]. }
    }
    // An alarm code the programme returns is raised once, when it differs from the last cycle's (a steady alarm such as 1406 fills one
    // slot, not all three; the source would repeat it, a documented departure).
    IF out["ALARM"] > 0 AND out["ALARM"] <> crun["LAST_ALARM"] { alarm_raise(ks["ALARM"], out["ALARM"]). }
    SET crun["LAST_ALARM"] TO out["ALARM"].
    IF NOT covered {
      SET flags["BLANK"] TO out["BLANK"].
      SET flags["FLASH"] TO out["FLASH"].
      IF core_flashes(ks, ks["PENDING"]) { SET flags["FLASH"] TO TRUE. }
    }
    SET prog_text TO "" + out["PROG_NO"].
    IF out["ENDED"] {
      core_end(crun, vehicle).
      SET crun["FG_REQUEST"] TO FALSE.
      IF crun["BACK"]:ISTYPE("Lexicon") { SET ks["PROG_VN"] TO LIST(-1, -1). }
      IF vehicle["STICKY_PROGS"]:CONTAINS(out["PROG_NO"]) { SET crun["IDLE_TEXT"] TO "" + out["PROG_NO"]. }
      // Luminary GOTOPOOH (PRO or V34 ended the programme): major mode 00 and a standing flashing request, V37 N99 (GOP00FIX: CAF V37N99, GOFLASH, all
      // three returns post it again) until the pilot keys the next V37. The vehicle names it (END_REQUEST).
      IF core_post_end_request(crun, vehicle, ks) { SET flags["FLASH"] TO TRUE. }
      SET msg TO core_join(msg, "P" + out["PROG_NO"] + " ended. The controls are yours.").
    } ELSE IF out["HANDOVER"] {
      SET warn TO core_join(warn, core_handover(crun, vehicle)).
    }
  } ELSE {
    SET ks["PRO"] TO FALSE.            // PRO means nothing with no foreground programme running
    SET crun["FG_REQUEST"] TO FALSE.
    IF NOT prio_up {
      SET ks["PENDING"] TO crun["IDLE_REQUEST"].          // FALSE, or the standing V37 request after a programme ended
      IF core_flashes(ks, ks["PENDING"]) { SET flags["FLASH"] TO TRUE. }
    }
    IF NOT crun["BACK"]:ISTYPE("Lexicon") { SET ks["PROG_VN"] TO LIST(-1, -1). }
    SET crun["LAST_ALARM"] TO 0.
  }
  IF ext_up {
    LOCAL ext_res IS core_ext_run(ks, nav, flags, taken).
    SET msg TO core_join(msg, ext_res["MSG"]).
    SET warn TO core_join(warn, ext_res["WARN"]).
  } ELSE IF ext_before:LENGTH = 2 {
    core_ext_restore(ks, ext_before, flags).           // it ended this cycle (PRO or V34): give the display back
  }
  LOCAL under_line IS "".           // the second slot's status line
  IF crun["BACK"]:ISTYPE("Lexicon") {
    LOCAL back_res IS core_back_step(crun, vehicle, nav, ks, answers, taken, flags).
    SET msg TO core_join(msg, back_res["MSG"]).
    SET warn TO core_join(warn, back_res["WARN"]).
    IF NOT front_ran AND back_res["PROG_TEXT"] <> "" { SET prog_text TO back_res["PROG_TEXT"]. }
    SET under_line TO back_res["UNDER"].
  }
  // KEY REL: the lamp the pilot's keying over a request lit, with the programme's own KEY_REL (when the vehicle maps it); out with the request.
  IF NOT ks["PENDING"]:ISTYPE("Lexicon") { SET ks["KEYREL"] TO FALSE. }
  IF ks["KEYREL"] { SET flags["KEYREL"] TO TRUE. }
  // Also lit while the pilot's display covers a running programme's steady one: in Luminary the programme's next repaint finds the display held by
  // the keyboard and lights the lamp (PINBALL NVSUB, NVSUBUSY; ASCENT_GUIDANCE repaints V06 N63 every 2 s). Here it lights at once.
  IF crun["PROG"]:ISTYPE("Lexicon") AND key_covers_program(ks) { SET flags["KEYREL"] TO TRUE. }
  SET ks["RECYCLE"] TO FALSE.         // V32, V34 and ENTR are seen by the programme for one cycle only
  SET ks["TERMINATE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  SET flags["LAMPTEST"] TO key_lamptest_on(ks, TIME:SECONDS).      // V35: the window lights every lamp and digit
  SET flags["PROG"] TO ks["ALARM"]["LAMP"].       // the PROG lamp is latched by the alarm facility until RSET
  SET derived["ALARM_CODES"] TO ks["ALARM"]["CODES"].      // for N09
  IF load_active(ks) OR p27_active(ks) { SET flags["FLASH"] TO TRUE. }    // VERB and NOUN flash while a keyed load or an update waits for data
  SET flags["UPLINK"] TO p27_active(ks) AND ks["P27"]["ACTY"].               // UPLINK ACTY: the ground is sending (see dsky_p27.ks)
  RETURN LEXICON("FLAGS", flags, "PROG_TEXT", prog_text, "MSG", msg, "WARN", warn, "STATUS", status_lines, "UNDER", under_line).
}

// core_shutdown: the DSKY is ending: the extended display and both programmes end, so every END has given its controls back.
FUNCTION core_shutdown {
  PARAMETER crun, vehicle, ks.
  core_ext_drop(ks).
  core_end(crun, vehicle).
  core_end_back(crun, vehicle).
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
  IF crun["LOG"] <> "" { IF EXISTS(crun["LOG"]) { DELETEPATH(crun["LOG"]). } }     // a new log for each DSKY run
  core_screen_start(crun).
  core_drain(crun).                            // what the vehicle said while it was being made
  LOCAL next_t IS TIME:SECONDS.
  LOCAL running IS TRUE.
  UNTIL NOT running {
    LOCAL cycle_t0 IS TIME:SECONDS.        // start of this cycle's work, for COMP ACTY
    LOCAL job_ran IS FALSE.                // did the "computer" do a job this cycle (COMP ACTY)?
    LOCAL nav IS vehicle["NAV"]:CALL(crun["PROG"]).
    IF NOT nav["OK"] {
      IF nav:HASKEY("MSG") { core_warning(crun, nav["MSG"]). } ELSE { core_warning(crun, "Navigation lost. Stopping."). }
      SET running TO FALSE.
    } ELSE {
      SET ks["PROGRAM"] TO core_running(crun).       // P27 asks the vehicle whether an update is allowed with this
      gui_poll(ui, ks).
      LOCAL feed_warn IS "".
      IF feed:ISTYPE("Lexicon") {
        LOCAL fed IS uplink_poll(feed, ks, vehicle, vehicle["P27_OK"]:CALL(core_running(crun)), TIME:SECONDS).
        SET feed_active TO fed["ACTIVE"].
        SET feed_warn TO fed["MSG"].
      }
      IF ks["RSET"] {                          // RSET also clears the warnings, before this cycle's are added
        SET ks["RSET"] TO FALSE.
        core_warnings_clear(crun).
      }
      core_warning(crun, feed_warn).
      core_scripted_alarms(ks, vehicle, crun["PROG"], TIME:SECONDS).
      // A programme the vehicle asks for itself, before a keyed V37.
      LOCAL asked IS core_vehicle_request(crun, vehicle, ks, TIME:SECONDS).
      core_drain(crun).
      IF asked["MSG"] <> "" OR asked["WARN"] <> "" {
        SET job_ran TO TRUE.
        core_message(crun, asked["MSG"]).
        core_warning(crun, asked["WARN"]).
      }
      // V37 ENTR <programme> ENTR: start a programme, or end the running one (00).
      IF ks["PROG_REQ"] >= 0 {
        LOCAL req IS ks["PROG_REQ"].
        SET ks["PROG_REQ"] TO -1.
        SET job_ran TO TRUE.
        LOCAL req_res IS core_request(crun, vehicle, ks, req).
        core_drain(crun).                       // what the START said, then what the request returned
        core_message(crun, req_res["MSG"]).
        core_warning(crun, req_res["WARN"]).
      }
      LOCAL step_res IS core_step(crun, vehicle, nav, ks).
      core_status_draw(crun, step_res["STATUS"], step_res["UNDER"]).
      core_message(crun, step_res["MSG"]).
      core_warning(crun, step_res["WARN"]).
      vehicle["HOOK"]:CALL(crun["PROG"], nav).
      core_drain(crun).                 // after the step's own texts: what a handover's START said follows "P.. complete"
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
      core_warning(crun, ks["LOAD"]["MSG"]).          // a refused load
      SET ks["LOAD"]["MSG"] TO "".
      // P27 shows the octal word being keyed in R1 and the buffer address stream in R3 (R2 blank).
      LOCAL p27_view IS p27_shown(ks, vehicle).
      IF p27_view["ACTIVE"] { SET flags["REGS"] TO LIST(p27_view["R1"], NA, p27_view["R3"]). SET flags["REGS_NOW"] TO TRUE. }
      // REGS_NOW: keyed digits (a load, P27) show at once; only a monitored noun's numbers refresh once a second (gui_update).
      core_warning(crun, ks["P27"]["MSG"]).           // a refused update
      SET ks["P27"]["MSG"] TO "".
      // COMP ACTY: lit while the Executive runs a job and dark when it idles (Luminary EXECUTIVE.agc: NUCHANG2 and
      // NUDIRECT turn the light on, DUMMYJOB turns it off). Here a job is a programme step or a programme request;
      // BUSY is how long this cycle's work took (the display adds its own minimum so a short job is still visible).
      IF crun["PROG"]:ISTYPE("Lexicon") OR crun["BACK"]:ISTYPE("Lexicon") { SET job_ran TO TRUE. }
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
      // The vehicle's TICK hook is called at the same rate, with or without a SAMPLE hook.
      LOCAL has_sample IS NOT sample:ISTYPE("Boolean").      // a delegate, not FALSE
      LOCAL has_tick IS vehicle:HASKEY("TICK").
      IF has_sample OR has_tick {
        IF NOT has_sample { WAIT 0.01. }                     // a late cycle still gives up one physics tick
        UNTIL TIME:SECONDS >= next_t {
          IF has_sample { sample:CALL(crun["PROG"]). }
          IF has_tick { vehicle["TICK"]:CALL(). }
          WAIT 0.02.
        }
      } ELSE {
        WAIT MAX(0.01, next_t - TIME:SECONDS).
      }
    }
  }
  // A programme still running (V34, or navigation stopped): give the controls back.
  core_shutdown(crun, vehicle, ks).
  // Keep the erasable store for the next DSKY run, when the vehicle names a file for it.
  IF vehicle:HASKEY("STORE") AND vehicle:HASKEY("STORE_SAVE") { vehicle["STORE_SAVE"]:CALL(). }
  core_drain(crun).
}
