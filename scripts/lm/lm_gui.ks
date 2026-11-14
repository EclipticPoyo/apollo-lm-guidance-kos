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
//  - Fonts: kOS can only use fonts the operating system has, so the digits are not text: each digit cell is a label
//    whose STYLE:BG is a picture of the digit (scripts/lm/images/digit_<cell width>_<char>.png), rendered from the
//    Zerlina font (SIL OFL, see images/Zerlina-OFL.txt) by tools/make_digit_images.py. GUI_DIGIT_IMAGES = FALSE
//    goes back to text in GUI_DIGIT_FONT (the old "digital-7 (mono)", only if it is installed).
//  - The window needs the main loop to keep running (gui_poll). Call gui_close when the script ends.
//  - The window object must be created at the top level of the main script, see gui_fill below.
// Simplifications: only PROG, OPR ERR and COMP ACTY ever light (COMP ACTY: while a job runs or a displayed value
// changes, see gui_update), the other lamps are placeholders;
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
GLOBAL GUI_DISPLAY_RGB IS RGB(0.227, 0.875, 0.604).   // GUI_DISPLAY_HEX as a colour
GLOBAL GUI_DIGIT_FONT IS "digital-7 (mono)".   // "" = default font; used only for a character that has no digit image
GLOBAL GUI_DIGIT_IMAGES IS TRUE.               // TRUE = digits are pictures (lm/images/digit_<cell width>_<char>.png, made from the Zerlina font by
                                               // tools/make_digit_images.py); FALSE = text in GUI_DIGIT_FONT
GLOBAL GUI_DIGIT_NAMES IS LEXICON("0", "0", "1", "1", "2", "2", "3", "3", "4", "4", "5", "5", "6", "6", "7", "7",
                                  "8", "8", "9", "9", "+", "plus", "-", "minus", ".", "dot", " ", "").   // character -> image name part ("" = blank)
GLOBAL GUI_DIGIT_HEIGHTS IS LEXICON(40, 44, 35, 40).    // cell width -> cell height in pixels; the images exist for these widths only
GLOBAL GUI_PARTS IS LIST().                     // every widget gui_fill creates (see gui_keep)
GLOBAL GUI_RICH IS TRUE.                       // FALSE = plain text, no colour tags
GLOBAL GUI_LAMP_OFF_BG IS "lm/images/lamp_off".        // lamp cell backgrounds: solid-colour images in scripts/lm/images/
GLOBAL GUI_LAMP_WHITE_BG IS "lm/images/lamp_white".    // lit, left column
GLOBAL GUI_LAMP_AMBER_BG IS "lm/images/lamp_amber".    // lit, right column
GLOBAL GUI_TAG_TL_BG IS "lm/images/display_tag_tl".    // the same colour with the top left corner rounded (COMP ACTY), 16 px, radius 8
GLOBAL GUI_TAG_TR_BG IS "lm/images/display_tag_tr".    // top right corner rounded (PROG tag); both follow the display panel's rounded corners
GLOBAL GUI_TAG_BG IS "lm/images/display_tag".           // solid display-colour image, found relative to the archive (Ships/Script) through the lm junction
GLOBAL GUI_DISPLAY_W IS 250.                   // display panel width (the registers); the lamp panel is the same width, gap about 7
GLOBAL GUI_LAMP_W IS 250.                      // lamp panel width: equal to the display panel
GLOBAL GUI_LAMP_COL_W IS 110.                  // width of one lamp cell (two cells, the gap and the panel padding fit GUI_LAMP_W)
GLOBAL GUI_LAMP_INSET IS 8.                    // space between the lamp panel's edge and the lamps, all four sides (the lamps used to overlap the frame)
GLOBAL GUI_LAMP_H IS 40.                       // height of one lamp cell
GLOBAL GUI_LEFT_COL_W IS 116.                  // widths of the two columns of the display panel
GLOBAL GUI_RIGHT_COL_W IS 122.
GLOBAL GUI_RIGHT_SHIFT IS 38.                  // spacer that pushes PROG and NOUN to the right edge
GLOBAL GUI_OFF_TEXT IS RGB(0.04, 0.04, 0.05).  // text of a lamp that is off: black on the light-grey off cell
GLOBAL GUI_REG_PERIOD IS 1.0.                  // seconds between refreshes of R1 to R3: a monitor verb shows its numbers once a second (Luminary PINBALL MONDEL, OCT 144 = 100 centiseconds)
GLOBAL GUI_COMP_HOLD IS 0.1.                   // seconds COMP ACTY stays lit at least, after a job or a display change
GLOBAL GUI_HOUSING_BG IS "lm/images/housing_grey".  // grey housing of the window and the lamp panel (RGB 118,122,128, from a photo of the real unit)
GLOBAL GUI_BEZEL_BG IS "lm/images/bezel_panel".    // frame of the lamp and display panels: darker rim round a near-black centre
GLOBAL GUI_SCREEN_BG IS "lm/images/bezel_screen".  // frame of the display: the same rim, a lighter centre
GLOBAL GUI_BEZEL_W IS 3.                            // rim width of bezel_panel.png in pixels (also the panel padding)
GLOBAL GUI_HOUSING_CORNER IS 12.                    // corner size of housing_grey.png in pixels (it is 32x32 with a radius of 12)
GLOBAL GUI_KEY_BG IS "lm/images/key_black".         // keypad key faces: solid-colour images in scripts/lm/images/
GLOBAL GUI_KEY_HOVER_BG IS "lm/images/key_hover".   // mouse over a key
GLOBAL GUI_KEY_PRESS_BG IS "lm/images/key_press".   // key held down
GLOBAL GUI_KEY_TEXT IS RGB(1, 1, 1).                // key caption colour (white)
GLOBAL GUI_KEY_SIZE IS 64.                    // keypad keys are squares of this size, pixels (7 columns across the 510 window)
GLOBAL GUI_PANEL_H IS 370.                    // height of the lamp panel and the display panel, pixels
GLOBAL GUI_DIGIT_SIZE IS 54.                   // font size of PROG, VERB, NOUN and the registers: sized so a
                                               // six-character register fills the display panel width
GLOBAL GUI_WINDOW_WIDTH IS 510.               // the width to pass to GUI() in the main script

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

// bold_text: caption text in rich-text bold (the annunciator lamps). Plain when GUI_RICH is FALSE.
FUNCTION bold_text {
  PARAMETER text.
  IF NOT GUI_RICH { RETURN text. }
  RETURN "<b>" + text + "</b>".
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
  LOCAL use_images IS GUI_DIGIT_IMAGES AND GUI_DIGIT_HEIGHTS:HASKEY(cell_w).
  FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO {
    IF use_images {
      // A picture cell: the label's text holds the character (so gui_set can tell when it changed) but is
      // drawn fully transparent and tiny (font size 8) so the text never makes the cell taller than its height; the picture is the background, stretched to the cell.
      LOCAL cell_w_lbl IS gui_label(holder, "-", cell_w, 8, "", "CENTER").
      SET cell_w_lbl:STYLE:HEIGHT TO GUI_DIGIT_HEIGHTS[cell_w].
      gui_digit_show(cell_w_lbl, "-").
      cells:ADD(cell_w_lbl).
    } ELSE {
      cells:ADD(gui_label(holder, lit_text("-"), cell_w, GUI_DIGIT_SIZE, GUI_DIGIT_FONT, "CENTER")).
    }
  }
  RETURN cells.
}

// gui_digit_show: show one character in a picture cell. A character with no picture (an unexpected one)
// is drawn as lit text instead. The label's text is always the bare character.
FUNCTION gui_digit_show {
  PARAMETER cell_lbl, ch.
  SET cell_lbl:TEXT TO ch.
  IF GUI_DIGIT_NAMES:HASKEY(ch) {
    LOCAL name IS GUI_DIGIT_NAMES[ch].
    SET cell_lbl:STYLE:BG TO (CHOOSE "" IF name = "" ELSE "lm/images/digit_" + ROUND(cell_lbl:STYLE:WIDTH) + "_" + name).
    SET cell_lbl:STYLE:TEXTCOLOR TO RGBA(0, 0, 0, 0).
  } ELSE {
    SET cell_lbl:STYLE:BG TO "".
    SET cell_lbl:STYLE:TEXTCOLOR TO GUI_DISPLAY_RGB.
  }
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
    LOCAL ch IS padded:SUBSTRING(i, 1).
    IF GUI_DIGIT_IMAGES AND GUI_DIGIT_HEIGHTS:HASKEY(ROUND(cells[i]:STYLE:WIDTH)) {
      IF cells[i]:TEXT <> ch { gui_digit_show(cells[i], ch). SET changed TO TRUE. }
    } ELSE IF gui_set(cells[i], lit_text(ch)) { SET changed TO TRUE. }
  }
  RETURN changed.
}

// gui_tag: a caption on a solid display-colour background with dark text, like the VERB, NOUN and PROG tags on the
// real display. STYLE:BG takes a "9-slice" image file from the archive (kOS docs, StyleState:BG); a plain
// solid image stretches to any size, so display_tag.png is one solid colour.
FUNCTION gui_tag {
  PARAMETER holder, text, width.
  LOCAL tag_w IS gui_label(holder, bold_text(text), width, 12, "", "CENTER").
  SET tag_w:STYLE:BG TO GUI_TAG_BG.
  SET tag_w:STYLE:TEXTCOLOR TO RGB(0.04, 0.1, 0.05).
  SET tag_w:STYLE:HEIGHT TO 18.
  RETURN tag_w.
}

// gui_border: set all four 9-slice borders of a widget to px pixels (the corner size of its background image).
FUNCTION gui_border {
  PARAMETER widget_w, px.
  SET widget_w:STYLE:BORDER:LEFT TO px.
  SET widget_w:STYLE:BORDER:RIGHT TO px.
  SET widget_w:STYLE:BORDER:TOP TO px.
  SET widget_w:STYLE:BORDER:BOTTOM TO px.
}

// gui_comp_style: COMP ACTY is the display colour when lit. Off it has no background at all (transparent, so it shows the
// panel behind it), unlike the other lamps whose off state is a grey cell. The text is black either way.
FUNCTION gui_comp_style {
  PARAMETER label_w, lit.
  IF lit {
    gui_lamp_style(label_w, TRUE, GUI_TAG_TL_BG).
  } ELSE {
    SET label_w:STYLE:BG TO "".     // transparent: "" falls back to no background (kOS docs, StyleState:BG)
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
  LOCAL rule_w IS gui_label(holder, lit_text("___________"), GUI_DISPLAY_W - 6, 32, "", "CENTER").   // label is left-anchored, so extra width moves the centred text right
  SET rule_w:STYLE:WORDWRAP TO FALSE.
  SET rule_w:STYLE:HEIGHT TO 12.   // kept at 12 so the register rows do not move
  // A big underscore sits at the bottom of a tall text line, so it drew below the label. Pull the text up
  // (negative top padding; the docs do not say negative values work, so this is a test).
  SET rule_w:STYLE:PADDING:TOP TO -24.   // was -20: -24 lifts the line 4 px so the gaps above and below it are about equal (digit cells have little ink padding)
}

// gui_skin: give a window or box a background image in every state (they switch between states, a window with
// focus is "on"; STYLE:BG alone sets only NORMAL). Used for the grey housing and the darker panel frames.
FUNCTION gui_skin {
  PARAMETER widget_w, image.
  SET widget_w:STYLE:NORMAL:BG TO image.
  SET widget_w:STYLE:ON:BG TO image.
  SET widget_w:STYLE:HOVER:BG TO image.
  SET widget_w:STYLE:HOVER_ON:BG TO image.
  SET widget_w:STYLE:ACTIVE:BG TO image.
  SET widget_w:STYLE:ACTIVE_ON:BG TO image.
  SET widget_w:STYLE:FOCUSED:BG TO image.
  SET widget_w:STYLE:FOCUSED_ON:BG TO image.
  // The images have rounded, transparent corners. BORDER says how many pixels at each edge are the corners
  // (the "9-slice" edges): they are kept as drawn and only the middle stretches (kOS docs, Style:BORDER).
  SET widget_w:STYLE:BORDER:LEFT TO GUI_HOUSING_CORNER.
  SET widget_w:STYLE:BORDER:RIGHT TO GUI_HOUSING_CORNER.
  SET widget_w:STYLE:BORDER:TOP TO GUI_HOUSING_CORNER.
  SET widget_w:STYLE:BORDER:BOTTOM TO GUI_HOUSING_CORNER.
}

// gui_key_spacer: an empty half-key-high gap at the top of a keypad column.
FUNCTION gui_key_spacer {
  PARAMETER column_w.
  LOCAL gap_w IS gui_label(column_w, "", GUI_KEY_SIZE, 12, "", "CENTER").
  SET gap_w:STYLE:HEIGHT TO FLOOR(GUI_KEY_SIZE / 2).
}

// gui_add_key: add one keypad button of the given size to a column and record it in ui["KEYS"] as
// LIST(button, character sent to key_press).
FUNCTION gui_add_key {
  PARAMETER ui, column_w, caption, key_char.
  LOCAL key_w IS gui_keep(column_w:ADDBUTTON(caption)).
  SET key_w:STYLE:WIDTH TO GUI_KEY_SIZE.
  SET key_w:STYLE:HEIGHT TO GUI_KEY_SIZE.   // every key is the same square
  IF caption:LENGTH = 1 {
    SET key_w:STYLE:FONTSIZE TO 22.   // digits, + and -: larger, like the real keycaps
  } ELSE {
    SET key_w:STYLE:FONTSIZE TO 13.   // word keys (VERB, ENTR, ...)
  }
  // Black keys with white text. STYLE:BG and STYLE:TEXTCOLOR set only the NORMAL state (kOS docs, Style), so
  // the states a click goes through are set one by one: HOVER (mouse over), ACTIVE (held down), FOCUSED.
  // The "on" states matter too: a click sets the button "on" until TAKEPRESS pops it out, and in that
  // moment (and while it has keyboard focus) the default grey skin showed through.
  SET key_w:STYLE:NORMAL:BG TO GUI_KEY_BG.
  SET key_w:STYLE:ON:BG TO GUI_KEY_BG.
  SET key_w:STYLE:HOVER:BG TO GUI_KEY_HOVER_BG.
  SET key_w:STYLE:HOVER_ON:BG TO GUI_KEY_HOVER_BG.
  SET key_w:STYLE:ACTIVE:BG TO GUI_KEY_PRESS_BG.
  SET key_w:STYLE:ACTIVE_ON:BG TO GUI_KEY_PRESS_BG.
  SET key_w:STYLE:FOCUSED:BG TO GUI_KEY_BG.
  SET key_w:STYLE:FOCUSED_ON:BG TO GUI_KEY_BG.
  SET key_w:STYLE:NORMAL:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:ON:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:HOVER:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:HOVER_ON:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:ACTIVE:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:ACTIVE_ON:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:FOCUSED:TEXTCOLOR TO GUI_KEY_TEXT.
  SET key_w:STYLE:FOCUSED_ON:TEXTCOLOR TO GUI_KEY_TEXT.
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
  gui_skin(win_w, GUI_HOUSING_BG).     // grey DSKY housing behind everything

  LOCAL top_row IS gui_keep(win_w:ADDHLAYOUT()).

  // ---- Lamp panel: two columns of seven, in the order of the photograph. "" is an empty slot. ----
  LOCAL lamp_panel IS gui_keep(top_row:ADDVBOX()).
  gui_skin(lamp_panel, GUI_BEZEL_BG).   // darker frame round the annunciators; its dark centre shows between the lamps
  SET lamp_panel:STYLE:WIDTH TO GUI_LAMP_W.
  SET lamp_panel:STYLE:HEIGHT TO GUI_PANEL_H.
  // No padding top and bottom. Every label also has a default margin of about 4 px, which pushed the first lamp
  // down by that much and the last one past the bottom edge (measured 2026-11-13: the padding change alone left
  // the column 5 px low). So the first row has no top margin and the last row no bottom margin (below), which
  // puts the first and last lamp on the top and bottom edges of the display panel next to it.
  SET lamp_panel:STYLE:PADDING:TOP TO GUI_LAMP_INSET.     // keep the lamps clear of the frame's rim
  SET lamp_panel:STYLE:PADDING:BOTTOM TO GUI_LAMP_INSET.
  SET lamp_panel:STYLE:PADDING:LEFT TO GUI_LAMP_INSET.
  SET lamp_panel:STYLE:PADDING:RIGHT TO GUI_LAMP_INSET.
  LOCAL lamp_h IS GUI_LAMP_H.
  // The seven rows still fill the panel from top to bottom: the space the shorter lamps leave is shared out as
  // equal gaps. Each lamp's top margin makes the gap above it, its bottom margin is 0 (set below).
  LOCAL lamp_gap IS FLOOR((GUI_PANEL_H - 2 * GUI_LAMP_INSET - 7 * lamp_h) / 6).
  LOCAL left_names IS LIST("UPLINK ACTY", "NO ATT", "STBY", "KEY REL", "OPR ERR", "CONTACT", "").   // CONTACT: the P65/P66 touchdown lamp (on the real LM it was on the main panel, not the DSKY)
  LOCAL right_names IS LIST("TEMP", "GIMBAL LOCK", "PROG", "RESTART", "TRACKER", "ALT", "VEL").
  SET ui["LAMPS"] TO LEXICON().
  SET ui["LAMP_LIT"] TO LEXICON().
  SET ui["LAMP_BG"] TO LEXICON().
  FROM { LOCAL i IS 0. } UNTIL i >= 7 STEP { SET i TO i + 1. } DO {
    LOCAL lamp_row IS gui_keep(lamp_panel:ADDHLAYOUT()).
    LOCAL lamp_l IS gui_label(lamp_row, bold_text(left_names[i]), GUI_LAMP_COL_W, 12, "", "CENTER").
    LOCAL lamp_r IS gui_label(lamp_row, bold_text(right_names[i]), GUI_LAMP_COL_W, 12, "", "CENTER").
    SET lamp_l:STYLE:HEIGHT TO lamp_h.
    SET lamp_r:STYLE:HEIGHT TO lamp_h.
    LOCAL gap_above IS lamp_gap.
    IF i = 0 { SET gap_above TO 0. }
    SET lamp_l:STYLE:MARGIN:TOP TO gap_above.
    SET lamp_r:STYLE:MARGIN:TOP TO gap_above.
    SET lamp_l:STYLE:MARGIN:BOTTOM TO 0.
    SET lamp_r:STYLE:MARGIN:BOTTOM TO 0.
    SET lamp_l:STYLE:MARGIN:LEFT TO 4.      // centres the two cells in the panel: 4 + 110 + 10 + 110 = 234 of the 234 inside the padding
    SET lamp_r:STYLE:MARGIN:LEFT TO 10.     // 10 = the vertical gap between the two columns
    SET lamp_l:STYLE:PADDING:TOP TO FLOOR((lamp_h - 14) / 2) - 6.    // text starts at the top of a label: pad it to the middle (-6: measured from a screenshot, it sat low)
    SET lamp_r:STYLE:PADDING:TOP TO FLOOR((lamp_h - 14) / 2) - 6.
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
  gui_skin(disp_panel, GUI_SCREEN_BG).    // same frame round the display
  SET disp_panel:STYLE:WIDTH TO GUI_DISPLAY_W.
  SET disp_panel:STYLE:HEIGHT TO GUI_PANEL_H.
  SET disp_panel:STYLE:PADDING:LEFT TO 0.       // was 3: COMP ACTY and VERB 3 px nearer the left edge (the right column got 3 px more spacer to stay put)
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
  SET ui["COMP"] TO gui_label(comp_col, bold_text("COMP" + CHAR(10) + "ACTY"), 84, 12, "", "CENTER").
  SET ui["COMP"]:STYLE:HEIGHT TO 72.
  SET ui["COMP"]:STYLE:PADDING:TOP TO 14.     // a label draws its text from the top: padding moves it to the middle
  SET ui["COMP_LIT"] TO FALSE.
  gui_border(ui["COMP"], 8).             // 9-slice corners of display_tag_tl.png
  gui_comp_style(ui["COMP"], FALSE).
  // The right column (PROG over NOUN) is pushed against the right edge with a spacer ahead of its tag and
  // its digits; the left column (VERB) starts at the left edge.
  LOCAL prog_col IS gui_keep(top_cols:ADDVLAYOUT()).
  SET prog_col:STYLE:WIDTH TO GUI_RIGHT_COL_W.
  LOCAL prog_tag_row IS gui_keep(prog_col:ADDHLAYOUT()).
  gui_label(prog_tag_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  LOCAL prog_tag IS gui_tag(prog_tag_row, "PROG", 84).
  SET prog_tag:STYLE:BG TO GUI_TAG_TR_BG.      // top right corner rounded to follow the panel
  gui_border(prog_tag, 8).
  LOCAL prog_dig_row IS gui_keep(prog_col:ADDHLAYOUT()).
  gui_label(prog_dig_row, "", GUI_RIGHT_SHIFT, 12, "", "LEFT").
  SET ui["PROG"] TO gui_cells(prog_dig_row, 2, 40).

  gui_keep(disp_panel:ADDSPACING(4)).         // a gap so the PROG digits do not touch the NOUN tag
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
  // (three rules in all: below VERB/NOUN, below R1, below R2; none below R3).
  SET ui["REG_NEXT"] TO 0.      // UT of the next refresh of R1 to R3 (a monitor shows its numbers once a second)
  SET ui["REG_NOUN"] TO -1.     // the noun the registers were last refreshed for: a new noun refreshes at once
  SET ui["COMP_UNTIL"] TO 0.     // UT until which COMP ACTY stays lit (after a job or a display change)
  SET ui["REGS"] TO LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
    gui_rule(disp_panel).
    LOCAL reg_row IS gui_keep(disp_panel:ADDHLAYOUT()).
    SET reg_row:STYLE:PADDING:LEFT TO 6.   // centres the register digits between the rims (the panel itself has no left padding now)
    ui["REGS"]:ADD(gui_cells(reg_row, 6, 35)).
  }

  // ---- Keypad: seven columns of identical square keys, as on the real unit ---------------------------
  // VERB/NOUN and ENTR/RSET are two keys each, set half a key lower than the three-key columns
  // (a blank half-key spacer on top).
  SET ui["KEYS"] TO LIST().
  LOCAL pad IS gui_keep(win_w:ADDHLAYOUT()).
  LOCAL col_verb IS gui_keep(pad:ADDVLAYOUT()).
  gui_key_spacer(col_verb).
  gui_add_key(ui, col_verb, "VERB", "V").
  gui_add_key(ui, col_verb, "NOUN", "N").
  LOCAL col_sign IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_sign, "+", "+").
  gui_add_key(ui, col_sign, "-", "-").
  gui_add_key(ui, col_sign, "0", "0").
  LOCAL digit_cols IS LIST(LIST("7", "4", "1"), LIST("8", "5", "2"), LIST("9", "6", "3")).
  FOR digit_col IN digit_cols {
    LOCAL col_w IS gui_keep(pad:ADDVLAYOUT()).
    FOR digit_key IN digit_col { gui_add_key(ui, col_w, digit_key, digit_key). }
  }
  LOCAL col_clr IS gui_keep(pad:ADDVLAYOUT()).
  gui_add_key(ui, col_clr, "CLR", "C").
  gui_add_key(ui, col_clr, "PRO", "P").
  gui_add_key(ui, col_clr, "KEY" + CHAR(10) + "REL", "K").
  LOCAL col_entr IS gui_keep(pad:ADDVLAYOUT()).
  gui_key_spacer(col_entr).
  gui_add_key(ui, col_entr, "ENTR", "E").
  gui_add_key(ui, col_entr, "RSET", "R").

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
    SET ui["REG_NEXT"] TO 0.      // show the numbers again at once when the blanking ends
    RETURN.
  }
  LOCAL flash_all IS flags:HASKEY("FLASH") AND flags["FLASH"].
  // COMP ACTY: lit while the computer is working (Luminary: on when the Executive runs a job, off when it idles,
  // EXECUTIVE.agc). Two things count as work: a job the core reports (flags JOB: a programme step ran or a programme
  // was requested, and BUSY: how long that cycle's work took) and a displayed value (PROG, VERB, NOUN, R1 to R3)
  // changing, which is the display routine running. The light stays lit for the work time, at least GUI_COMP_HOLD
  // seconds so that a short job is still visible. An idle P00 is dark between key presses; a running programme
  // flickers with its cycle.
  LOCAL changed IS FALSE.
  IF gui_set_cells(ui["PROG"], prog) { SET changed TO TRUE. }
  // While VERB or NOUN is being keyed, the whole verb and noun line flashes together (the real VERB/NOUN FLASH
  // output flashes both displays at once) until ENTR. The field being keyed shows what has been typed (blank where
  // nothing was typed yet); the other shows its current value. Flashing alone does not count as a display change
  // for COMP ACTY.
  LOCAL flash_on IS MOD(FLOOR(TIME:SECONDS * 2), 2) = 0.      // 1 Hz: half a second on, half off
  LOCAL keying_v IS gui_entry_active(flags, "V").
  LOCAL keying_n IS gui_entry_active(flags, "N").
  LOCAL verb_text IS vn_digits(verb).      // blank before the first verb and noun are keyed (DSKY_START)
  LOCAL noun_text IS vn_digits(noun).
  // A typed verb stays shown while the noun is being keyed (and the other way round): the digits typed stay on the display
  // until ENTR, as on the real DSKY. Only the field being keyed right now can be blank (just after its key).
  LOCAL vbuf_held IS flags:HASKEY("VBUF") AND flags["VBUF"]:LENGTH > 0.
  LOCAL nbuf_held IS flags:HASKEY("NBUF") AND flags["NBUF"]:LENGTH > 0.
  IF keying_v OR vbuf_held { SET verb_text TO gui_entry_text(flags["VBUF"]). }
  IF keying_n OR nbuf_held { SET noun_text TO gui_entry_text(flags["NBUF"]). }
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
  // R1 to R3 are a monitored noun: the real computer redisplays them once a second (Luminary monitor verbs,
  // "PERIODIC (1 PER SEC) DISPLAY", MONDEL = 1 s), not at our faster cycle. A new noun, or a blanked display, shows at
  // once; otherwise the digits only change when GUI_REG_PERIOD has passed since the last refresh.
  IF noun <> ui["REG_NOUN"] OR TIME:SECONDS >= ui["REG_NEXT"] {
    SET ui["REG_NOUN"] TO noun.
    SET ui["REG_NEXT"] TO TIME:SECONDS + GUI_REG_PERIOD.
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
      IF gui_set_cells(ui["REGS"][i], regs[i]) { SET changed TO TRUE. }
    }
  }
  LOCAL job IS changed OR (flags:HASKEY("JOB") AND flags["JOB"]).
  IF job {
    LOCAL hold_s IS GUI_COMP_HOLD.
    IF flags:HASKEY("BUSY") { SET hold_s TO MAX(hold_s, flags["BUSY"]). }
    SET ui["COMP_UNTIL"] TO TIME:SECONDS + hold_s.
  }
  gui_comp_show(ui, TIME:SECONDS < ui["COMP_UNTIL"]).
}

// gui_close: remove the window. Call it when the script ends, or the window stays on screen.
FUNCTION gui_close {
  PARAMETER ui.
  ui["WIN"]:HIDE().
  ui["WIN"]:DISPOSE().
}
