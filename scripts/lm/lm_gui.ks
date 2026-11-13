// lm_gui.ks -- DSKY face as a kOS GUI window with a clickable keypad.
//
// A second presentation of the same data as the terminal display in dsky_display.ks, and it reuses the core's
// logic: key_press / keys_poll (dsky_keys.ks: key entry), fmt_reg and zero_pad (dsky_display.ks: number text). The
// three register texts come in through flags["REGS"] (the vehicle's noun table, lm_nouns.ks). Run dsky_keys.ks and
// dsky_display.ks first (RUNONCEPATH), then this file.

// Layout follows a photograph of a DSKY (supplied by the user, 2026-11-12), top to bottom:
//   [ lamp panel: 2 columns x 7 rows ] [ display panel: PROG / VERB NOUN / R1 R2 R3 ]
//   keypad, 7 columns: VERB,NOUN | + - 0 | 7 4 1 | 8 5 2 | 9 6 3 | CLR PRO KEY REL | ENTR,RSET
// VERB and NOUN, and ENTR and RSET, are tall keys that each cover one and a half rows in the photo.
// A kOS layout cannot span rows, so they are two taller buttons stacked in their own column.
//
// Things the kOS GUI docs do and do not give us, and what this file does about it:
//  - No lamp widget: a lamp is a label whose STYLE:BG is a solid-colour image (scripts/lm/images/lamp_*.png,
//    display_tag.png) and whose TEXTCOLOR is dark when lit, dim when off.
//  - The default skin has a grey window background; I found no documented way to make it black.
//  - Fonts: "digital-7 (mono)" is a seven-segment typeface that appeared in the KSP font list on this
//    install. It is set with STYLE:FONT; if a font is missing it simply will not look like segments.
//  - The window needs the main loop to keep running (gui_poll). Call gui_close when the script ends.
//  - The window object must be created at the top level of the main script, see gui_fill below.
// Simplifications: only PROG, OPR ERR and COMP ACTY ever light (COMP ACTY: whenever a displayed value
// changes), the other lamps are placeholders;
// + - and KEY REL can be pressed but do nothing (key_press ignores them) until something needs them.
// Departure from the real DSKY (deliberate, user choice 2026-11-12): while VERB or NOUN is being keyed, the typed
// digits show in its cells and the whole verb and noun line flashes until ENTR. On the real unit (Luminary 099, PINBALL_GAME_BUTTONS_AND_LIGHTS.agc,
// VERB/NOUN at about line 658) pressing VERB or NOUN blanks the two digits, typed digits appear steady, and
// the VERB/NOUN FLASH output (bit 6 of channel 11) is switched on by a programme that wants input (a data
// load, V37), flashing verb and noun together. We flash the line while keying instead; programme-requested
// flashing does not exist yet.
// Second departure (kept on purpose): on the real unit VERB or NOUN also zeroes that register, so pressing
// VERB, then NOUN, then ENTR without typing a verb alarms. Here a register with nothing typed keeps its old
// value (key_enter in dsky_keys.ks), which is more forgiving.

// The display colour. Sampled from two of the user's photographs of DSKY displays (digit pixels averaged,
// 2026-11-12): a teal one, RGB 58, 223, 198 (hue 173), judged too blue, and a green one, RGB 52, 163, 86
// (hue 138, darker). This is the middle hue (155) at the brighter photo's brightness: RGB 58, 223, 154.
// Published sources give the original electroluminescent glow as roughly 530 nm ("green", one calls it
// "blueish-green") and no RGB value. Keep it in step with scripts/lm/images/display_tag.png.
GLOBAL GUI_DISPLAY_HEX IS "#3adf9a".
GLOBAL GUI_DIGIT_FONT IS "digital-7 (mono)".   // "" = default font
GLOBAL GUI_PARTS IS LIST().                     // every widget gui_fill creates (see gui_keep)
GLOBAL GUI_RICH IS TRUE.                       // FALSE = plain text, no colour tags
GLOBAL GUI_LAMP_OFF_BG IS "lm/images/lamp_off".        // lamp cell backgrounds: solid-colour images in scripts/lm/images/
GLOBAL GUI_LAMP_WHITE_BG IS "lm/images/lamp_white".    // lit, left column
GLOBAL GUI_LAMP_AMBER_BG IS "lm/images/lamp_amber".    // lit, right column
GLOBAL GUI_TAG_BG IS "lm/images/display_tag".           // solid display-colour image, found relative to the archive (Ships/Script) through the lm junction
GLOBAL GUI_DISPLAY_W IS 250.                   // display panel width: the keypad is about 462 wide, lamp panel 200, gap about 7
GLOBAL GUI_LEFT_COL_W IS 116.                  // widths of the two columns of the display panel
GLOBAL GUI_RIGHT_COL_W IS 116.
GLOBAL GUI_RIGHT_SHIFT IS 32.                  // spacer that pushes PROG and NOUN to the right edge
GLOBAL GUI_OFF_TEXT IS RGB(0.62, 0.68, 0.78).  // text of a lamp that is off
GLOBAL GUI_COMP_HOLD IS 0.25.                  // seconds COMP ACTY stays lit after a display change
GLOBAL GUI_PANEL_H IS 370.                     // height of the lamp panel and the display panel, pixels
GLOBAL GUI_DIGIT_SIZE IS 54.                   // font size of PROG, VERB, NOUN and the registers: sized so a
                                               // six-character register fills the display panel width
GLOBAL GUI_WINDOW_WIDTH IS 460.                // the width to pass to GUI() in the main script

// gui_keep: remember a widget in the global GUI_PARTS list and return it. This is how the windows that
// survived in the probe tests were built. Holding references was one theory for why windows built in a
// function vanished; it did not fix that (the fix is to create the window at the top level, see gui_fill),
// and it is not known whether this list is needed. It is kept because the tested configuration had it.
FUNCTION gui_keep {
  PARAMETER widget_w.
  GUI_PARTS:ADD(widget_w).
  RETURN widget_w.
}

// lit_text: text in the display colour, so register digits look like DSKY numerals.
FUNCTION lit_text {
  PARAMETER text.
  IF NOT GUI_RICH { RETURN text. }
  RETURN "<color=" + GUI_DISPLAY_HEX + ">" + text + "</color>".
}

// gui_lamp_style: a lamp is a cell: a dark cell with dim text when off, a bright cell with dark text when lit
// (the image is the lit colour, white or amber). Like the tags, the background is a solid-colour image.
FUNCTION gui_lamp_style {
  PARAMETER label_w, lit, lit_bg.
  IF lit {
    SET label_w:STYLE:BG TO lit_bg.
    SET label_w:STYLE:TEXTCOLOR TO RGB(0.04, 0.07, 0.1).
  } ELSE {
    SET label_w:STYLE:BG TO GUI_LAMP_OFF_BG.
    SET label_w:STYLE:TEXTCOLOR TO GUI_OFF_TEXT.
  }
}

// gui_lamp_set: light or darken a named lamp, only when its state changes.
FUNCTION gui_lamp_set {
  PARAMETER ui, name, lit.
  IF ui["LAMP_LIT"][name] = lit { RETURN. }
  SET ui["LAMP_LIT"][name] TO lit.
  gui_lamp_style(ui["LAMPS"][name], lit, ui["LAMP_BG"][name]).
}

// gui_set: change a label's text only when it differs, so a 10 Hz update costs almost nothing.
// Returns TRUE when the text changed (gui_update uses this to light COMP ACTY).
FUNCTION gui_set {
  PARAMETER label_w, text.
  IF label_w:TEXT <> text {
    SET label_w:TEXT TO text.
    RETURN TRUE.
  }
  RETURN FALSE.
}

// gui_label: add a label of the given width, font size and alignment ("LEFT", "CENTER" or "RIGHT") to a
// window or layout strip. font may be "" for the default font.
FUNCTION gui_label {
  PARAMETER holder, text, width, size, font, align.
  LOCAL label_w IS gui_keep(holder:ADDLABEL(text)).
  SET label_w:STYLE:WIDTH TO width.
  SET label_w:STYLE:FONTSIZE TO size.
  SET label_w:STYLE:ALIGN TO align.
  IF font <> "" { SET label_w:STYLE:FONT TO font. }
  RETURN label_w.
}

// gui_cells: a row of n digit cells, each one character wide, spread evenly over the width cell_w * n.
// The real DSKY draws each digit in its own cell; one label per digit is how we spread the narrow
// seven-segment glyphs across the panel. Returns the list of labels, left to right.
FUNCTION gui_cells {
  PARAMETER holder, n, cell_w.
  LOCAL cells IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
    cells:ADD(gui_label(holder, lit_text("-"), cell_w, GUI_DIGIT_SIZE, GUI_DIGIT_FONT, "CENTER")).
  }
  RETURN cells.
}

// gui_set_cells: show text in a row of cells, right-aligned: shorter text is padded with blanks on the
// left, longer text keeps its last characters. Returns TRUE if any cell changed.
FUNCTION gui_set_cells {
  PARAMETER cells, text.
  LOCAL n IS cells:LENGTH.
  LOCAL padded IS "" + text.
  UNTIL padded:LENGTH >= n { SET padded TO " " + padded. }
  IF padded:LENGTH > n { SET padded TO padded:SUBSTRING(padded:LENGTH - n, n). }
  LOCAL changed IS FALSE.
  FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
    IF gui_set(cells[i], lit_text(padded:SUBSTRING(i, 1))) { SET changed TO TRUE. }
  }
  RETURN changed.
}

// gui_tag: a caption on a solid display-colour background with dark text, like the VERB, NOUN and PROG tags on the
// real display. STYLE:BG takes a "9-slice" image file from the archive (kOS docs, StyleState:BG); a plain
// solid image stretches to any size, so display_tag.png is one solid colour.
FUNCTION gui_tag {
  PARAMETER holder, text, width.
  LOCAL tag_w IS gui_label(holder, text, width, 12, "", "CENTER").
  SET tag_w:STYLE:BG TO GUI_TAG_BG.
  SET tag_w:STYLE:TEXTCOLOR TO RGB(0.04, 0.1, 0.05).
  SET tag_w:STYLE:HEIGHT TO 18.
  RETURN tag_w.
}

// gui_comp_style: COMP ACTY is the display colour when lit. Off it has no background at all (transparent, so it shows the
// panel behind it), only dim text, unlike the other lamps whose off state is a dark cell.
// STYLE:BG "" falls back to transparent (kOS docs, StyleState:BG).
FUNCTION gui_comp_style {
  PARAMETER label_w, lit.
  IF lit {
    gui_lamp_style(label_w, TRUE, GUI_TAG_BG).
  } ELSE {
    SET label_w:STYLE:BG TO "".
    SET label_w:STYLE:TEXTCOLOR TO GUI_OFF_TEXT.
  }
}

// gui_comp_show: COMP ACTY, a two-line lamp. Lit: display-colour cell with dark text. Off: dark cell.
// Changes the label only when the state changes.
FUNCTION gui_comp_show {
  PARAMETER ui, lit.
  IF lit = ui["COMP_LIT"] { RETURN. }
  SET ui["COMP_LIT"] TO lit.
  gui_comp_style(ui["COMP"], lit).
}

// gui_rule: a thin horizontal line across a panel, the divider between the DSKY's register rows. It is a
// row of underscores in the lit-segment colour: the GUI docs list no line or filled-bar widget.
// (A solid bar made from an empty label with the tag image was tried and the underscores were preferred.)
FUNCTION gui_rule {
  PARAMETER holder.
  LOCAL rule_w IS gui_label(holder, lit_text("________________________________________"), GUI_DISPLAY_W - 20, 10, "", "CENTER").
  SET rule_w:STYLE:WORDWRAP TO FALSE.
  SET rule_w:STYLE:HEIGHT TO 12.
}

// gui_add_key: add one keypad button of the given size to a column and record it in ui["KEYS"] as
// LIST(button, character sent to key_press).
FUNCTION gui_add_key {
  PARAMETER ui, column_w, caption, key_char, height.
  LOCAL key_w IS gui_keep(column_w:ADDBUTTON(caption)).
  SET key_w:STYLE:WIDTH TO 58.
  SET key_w:STYLE:HEIGHT TO height.
  SET key_w:STYLE:FONTSIZE TO 13.
  ui["KEYS"]:ADD(LIST(key_w, key_char)).
}

// gui_fill: add every DSKY widget to an existing window win_w and return the lexicon of the widgets that
// gui_update changes. Does not position or show the window.
//
// THE WINDOW MUST BE CREATED AT THE TOP LEVEL OF THE MAIN SCRIPT, NOT INSIDE A FUNCTION. A window made
// by GUI() inside a function vanished from the screen a few seconds after opening (kOS still reported it
// visible and the script kept running), while the same window made at the top level stayed, even though a
// function added all of its contents (probe tests, 2026-11-12). The cause is not known. So a script does:
//   CLEARGUIS().                       // optional: removes windows left by an earlier run
//   GLOBAL dsky_win IS GUI(GUI_WINDOW_WIDTH).
//   SET dsky_win:X TO 60.
//   SET dsky_win:Y TO 60.
//   GLOBAL dsky_ui IS gui_fill(dsky_win).
//   dsky_win:SHOW().
FUNCTION gui_fill {
  PARAMETER win_w.
  LOCAL ui IS LEXICON().
  SET ui["WIN"] TO win_w.

  LOCAL top_row IS gui_keep(win_w:ADDHLAYOUT()).

  // ---- Lamp panel: two columns of seven, in the order of the photograph. "" is an empty slot. ----
  LOCAL lamp_panel IS gui_keep(top_row:ADDVBOX()).
  SET lamp_panel:STYLE:WIDTH TO 200.
  SET lamp_panel:STYLE:HEIGHT TO GUI_PANEL_H.
  LOCAL lamp_h IS FLOOR((GUI_PANEL_H - 12) / 7) - 9.    // seven rows fill the panel, like the real one (9: the gap between rows)
  LOCAL left_names IS LIST("UPLINK ACTY", "NO ATT", "STBY", "KEY REL", "OPR ERR", "CONTACT", "").   // CONTACT: the P65/P66 touchdown lamp (on the real LM it was on the main panel, not the DSKY)
  LOCAL right_names IS LIST("TEMP", "GIMBAL LOCK", "PROG", "RESTART", "TRACKER", "ALT", "VEL").
  SET ui["LAMPS"] TO LEXICON().
  SET ui["LAMP_LIT"] TO LEXICON().
  SET ui["LAMP_BG"] TO LEXICON().
  FROM { LOCAL i IS 0. } UNTIL i >= 7 STEP { SET i TO i + 1. } DO {
    LOCAL lamp_row IS gui_keep(lamp_panel:ADDHLAYOUT()).
    LOCAL lamp_l IS gui_label(lamp_row, left_names[i], 94, 12, "", "CENTER").
    LOCAL lamp_r IS gui_label(lamp_row, right_names[i], 94, 12, "", "CENTER").
    SET lamp_l:STYLE:HEIGHT TO lamp_h.
    SET lamp_r:STYLE:HEIGHT TO lamp_h.
    SET lamp_l:STYLE:PADDING:TOP TO FLOOR((lamp_h - 14) / 2).    // text starts at the top of a label: pad it to the middle
    SET lamp_r:STYLE:PADDING:TOP TO FLOOR((lamp_h - 14) / 2).
    // Left column lights white, right column amber, as on the real panel. An empty slot is a dark cell.
    gui_lamp_style(lamp_l, FALSE, GUI_LAMP_WHITE_BG).
    gui_lamp_style(lamp_r, FALSE, GUI_LAMP_AMBER_BG).
    IF left_names[i] <> "" {
      SET ui["LAMPS"][left_names[i]] TO lamp_l.
      SET ui["LAMP_LIT"][left_names[i]] TO FALSE.
      SET ui["LAMP_BG"][left_names[i]] TO GUI_LAMP_WHITE_BG.
    }
    SET ui["LAMPS"][right_names[i]] TO lamp_r.
    SET ui["LAMP_LIT"][right_names[i]] TO FALSE.
    SET ui["LAMP_BG"][right_names[i]] TO GUI_LAMP_AMBER_BG.
  }

  // ---- Display panel: COMP ACTY, PROG, VERB and NOUN, three signed registers ----------------------
  LOCAL disp_panel IS gui_keep(top_row:ADDVBOX()).
  SET disp_panel:STYLE:WIDTH TO GUI_DISPLAY_W.
  SET disp_panel:STYLE:HEIGHT TO GUI_PANEL_H.
  SET disp_panel:STYLE:PADDING:LEFT TO 3.       // less left padding: VERB starts nearer the left edge
  SET disp_panel:STYLE:PADDING:RIGHT TO 3.
  // Arrangement from a photograph of a real DSKY display (2026-11-12). Two columns, the right one shared
  // by PROG (top) and NOUN (below), so their digits line up:
  //   COMP ACTY (left)                 PROG tag + 2 digits (right column)
  //   VERB tag + 2 digits (left)       NOUN tag + 2 digits (right column)
  //   ---------------------------------------------------------------
  //   + 5 digits (R1) / rule / R2 / rule / R3 / rule
  // Widths: the panel's usable width is about 206 px (226 less its padding) and kOS adds about 2 px of
  // margin per widget, so six cells of 35 px fit the 250 px panel (31 for the earlier 226 px panel); wider
  // cells overflowed the right edge.
  LOCAL top_cols IS gui_keep(disp_panel:ADDHLAYOUT()).
  LOCAL comp_col IS gui_keep(top_cols:ADDVLAYOUT()).
  SET comp_col:STYLE:WIDTH TO GUI_LEFT_COL_W.
  // Flown DSKYs read COMP ACTY (user, 2026-11-12; the LM panel drawing 300LM5-18 prints CMPTR ACTY).
  // The lit box is large: about as tall as the PROG tag plus its digits, and as wide as the VERB tag (84)
  // so its edges line up with VERB below it.
  SET ui["COMP"] TO gui_label(comp_col, "COMP" + CHAR(10) + "ACTY", 84, 12, "", "CENTER").
  SET ui["COMP"]:STYLE:HEIGHT TO 72.
  SET ui["COMP"]:STYLE:PADDING:TOP TO 22.        // a label draws its text from the top: padding moves it to the middle
  SET ui["COMP_LIT"] TO FALSE.
  gui_comp_style(ui["COMP"], FALSE).
  // The right column (PROG over NOUN) is pushed against the right edge with a spacer ahead of its tag and
  // its digits; the left column (VERB) starts at the left edge.
  LOCAL prog_col IS gui_keep(top_cols:ADDVLAYOUT()).
  SET prog_col:STYLE:WIDTH TO GUI_RIGHT_COL_W.
  LOCAL prog_tag_row IS gui_keep(prog_col:ADDHLAYOUT()).
  gui_label(prog_tag_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  gui_tag(prog_tag_row, "PROG", 84).
  LOCAL prog_dig_row IS gui_keep(prog_col:ADDHLAYOUT()).
  gui_label(prog_dig_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  SET ui["PROG"] TO gui_cells(prog_dig_row, 2, 40).

  gui_keep(disp_panel:ADDSPACING(10)).        // a gap so the PROG digits do not touch the NOUN tag
  LOCAL vn_row IS gui_keep(disp_panel:ADDHLAYOUT()).
  LOCAL verb_col IS gui_keep(vn_row:ADDVLAYOUT()).
  SET verb_col:STYLE:WIDTH TO GUI_LEFT_COL_W.
  gui_tag(verb_col, "VERB", 84).
  SET ui["VERB"] TO gui_cells(gui_keep(verb_col:ADDHLAYOUT()), 2, 40).
  LOCAL noun_col IS gui_keep(vn_row:ADDVLAYOUT()).
  SET noun_col:STYLE:WIDTH TO GUI_RIGHT_COL_W.
  LOCAL noun_tag_row IS gui_keep(noun_col:ADDHLAYOUT()).
  gui_label(noun_tag_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  gui_tag(noun_tag_row, "NOUN", 84).
  LOCAL noun_dig_row IS gui_keep(noun_col:ADDHLAYOUT()).
  gui_label(noun_dig_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  SET ui["NOUN"] TO gui_cells(noun_dig_row, 2, 40).

  // R1 to R3: sign cell plus five digit cells each, six cells across the panel, a rule above each and
  // one below the last, as on the real display.
  SET ui["COMP_UNTIL"] TO 0.     // UT until which COMP ACTY stays lit after a display change
  SET ui["REGS"] TO LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
    gui_rule(disp_panel).
    LOCAL reg_row IS gui_keep(disp_panel:ADDHLAYOUT()).
    ui["REGS"]:ADD(gui_cells(reg_row, 6, 35)).
  }
  gui_rule(disp_panel).

  // ---- Keypad: seven columns, as in the photograph ------------------------------------------------
  // Each column is a vertical strip of buttons. Heights: 34 for a normal key, 52 for the tall keys,
  // which together stand in for the one-and-a-half-row keys of the real unit.
  SET ui["KEYS"] TO LIST().
  LOCAL pad IS gui_keep(win_w:ADDHLAYOUT()).
  LOCAL col_verb IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_verb, "VERB", "V", 52).
  gui_add_key(ui, col_verb, "NOUN", "N", 52).
  LOCAL col_sign IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_sign, "+", "+", 34).
  gui_add_key(ui, col_sign, "-", "-", 34).
  gui_add_key(ui, col_sign, "0", "0", 34).
  LOCAL digit_cols IS LIST(LIST("7", "4", "1"), LIST("8", "5", "2"), LIST("9", "6", "3")).
  FOR digit_col IN digit_cols {
    LOCAL col_w IS gui_keep(pad:ADDVLAYOUT()).
    FOR digit_key IN digit_col { gui_add_key(ui, col_w, digit_key, digit_key, 34). }
  }
  LOCAL col_clr IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_clr, "CLR", "C", 34).
  gui_add_key(ui, col_clr, "PRO", "P", 34).
  gui_add_key(ui, col_clr, "KEY" + CHAR(10) + "REL", "K", 34).
  LOCAL col_entr IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_entr, "ENTR", "E", 52).
  gui_add_key(ui, col_entr, "RSET", "R", 52).

  RETURN ui.
}

// gui_poll: handle typed keys and clicked buttons. Both go through key_press, so a click and a typed
// key behave identically. TAKEPRESS is true once per click, then the button pops out again.
FUNCTION gui_poll {
  PARAMETER ui, ks.
  keys_poll(ks).
  FOR key_entry IN ui["KEYS"] {
    IF key_entry[0]:TAKEPRESS { key_press(ks, key_entry[1]). }
  }
  RETURN ks.
}

// gui_entry_active: is this key (mode "V" or "N") being keyed now? flags carries "MODE" from flags_from_keys;
// an older caller without it simply never shows an entry.
FUNCTION gui_entry_active {
  PARAMETER flags, mode_key.
  IF NOT flags:HASKEY("MODE") { RETURN FALSE. }
  RETURN flags["MODE"] = mode_key.
}

// gui_entry_text: the typed digits as exactly two characters, left-aligned, blank-padded ("1 " after one digit).
FUNCTION gui_entry_text {
  PARAMETER typed.
  RETURN (typed + "  "):SUBSTRING(0, 2).
}

// gui_update: same inputs as display_update in dsky_display.ks. flags: "PROG" and "OPRERR" (lamps), "MODE"
// ("", "V" or "N"), "VBUF" and "NBUF" (digits typed so far); flags_from_keys in dsky_keys.ks builds it, and the core adds "REGS" (three register texts).
// Optional flags, added by the P63 programme (each is ignored when absent): "KEYREL", "ALT", "VEL", "CONTACT" (lamps),
// "BLANK" (blank every display for the countdown) and "FLASH" (the
// verb and noun flash together, the V99 "please enable engine" prompt).
FUNCTION gui_update {
  PARAMETER ui, derived, prog, verb, noun, flags.
  gui_lamp_set(ui, "PROG", flags["PROG"]).
  gui_lamp_set(ui, "OPR ERR", flags["OPRERR"]).
  IF flags:HASKEY("KEYREL") { gui_lamp_set(ui, "KEY REL", flags["KEYREL"]). }
  IF flags:HASKEY("ALT") { gui_lamp_set(ui, "ALT", flags["ALT"]). }
  IF flags:HASKEY("VEL") { gui_lamp_set(ui, "VEL", flags["VEL"]). }
  IF flags:HASKEY("CONTACT") { gui_lamp_set(ui, "CONTACT", flags["CONTACT"]). }
  // BLANK (TIG-35 to TIG-30): every display goes dark; COMP ACTY is left as it is.
  IF flags:HASKEY("BLANK") AND flags["BLANK"] {
    gui_set_cells(ui["PROG"], "").
    gui_set_cells(ui["VERB"], "").
    gui_set_cells(ui["NOUN"], "").
    FOR reg_cells IN ui["REGS"] { gui_set_cells(reg_cells, ""). }
    RETURN.
  }
  LOCAL flash_all IS flags:HASKEY("FLASH") AND flags["FLASH"].
  // COMP ACTY lights whenever a displayed value (PROG, VERB, NOUN, R1 to R3) changes, and stays lit for
  // GUI_COMP_HOLD seconds so a single change is visible.
  LOCAL changed IS FALSE.
  IF gui_set_cells(ui["PROG"], prog) { SET changed TO TRUE. }
  // While VERB or NOUN is being keyed, the whole verb and noun line flashes together (the real VERB/NOUN FLASH
  // output flashes both displays at once) until ENTR. The field being keyed shows what has been typed (blank where
  // nothing was typed yet); the other shows its current value. Flashing alone does not count as a display change
  // for COMP ACTY.
  LOCAL flash_on IS MOD(FLOOR(TIME:SECONDS * 2), 2) = 0.      // 1 Hz: half a second on, half off
  LOCAL keying_v IS gui_entry_active(flags, "V").
  LOCAL keying_n IS gui_entry_active(flags, "N").
  LOCAL verb_text IS zero_pad(verb, 2).
  LOCAL noun_text IS zero_pad(noun, 2).
  IF keying_v { SET verb_text TO gui_entry_text(flags["VBUF"]). }
  IF keying_n { SET noun_text TO gui_entry_text(flags["NBUF"]). }
  // After V37 ENTR the programme number is keyed in the NOUN cells (blank until typed), the verb stays 37, and the line
  // flashes like any other entry until ENTR (Luminary MMCHANG: "uses noun display until enter").
  LOCAL keying_prog IS flags:HASKEY("PROGKEY") AND flags["PROGKEY"].
  IF keying_prog { SET noun_text TO gui_entry_text(flags["PBUF"]). }
  IF keying_v OR keying_n OR keying_prog OR flash_all {
    gui_set_cells(ui["VERB"], (CHOOSE verb_text IF flash_on ELSE "  ")).
    gui_set_cells(ui["NOUN"], (CHOOSE noun_text IF flash_on ELSE "  ")).
  } ELSE {
    IF gui_set_cells(ui["VERB"], verb_text) { SET changed TO TRUE. }
    IF gui_set_cells(ui["NOUN"], noun_text) { SET changed TO TRUE. }
  }
  LOCAL regs IS LIST(NA, NA, NA).      // the three register texts come in through flags["REGS"] (the vehicle's noun table)
  IF flags:HASKEY("REGS") { IF flags["REGS"]:LENGTH = 3 { SET regs TO flags["REGS"]. } }
  FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
    IF gui_set_cells(ui["REGS"][i], regs[i]) { SET changed TO TRUE. }
  }
  IF changed { SET ui["COMP_UNTIL"] TO TIME:SECONDS + GUI_COMP_HOLD. }
  gui_comp_show(ui, TIME:SECONDS < ui["COMP_UNTIL"]).
}

// gui_close: remove the window. Call it when the script ends, or the window stays on screen.
FUNCTION gui_close {
  PARAMETER ui.
  ui["WIN"]:HIDE().
  ui["WIN"]:DISPOSE().
}
