// lm_gauge.ks -- the drift gauge's window (rendezvous stage 4): two needles crossing on a dial, the stand-in for the LM cross-pointer.
//   gauge_fill(win_w, mini_w)    fill the gauge's window and its minimised one, and return the gauge handle (both stay hidden)
//   gauge_update(g, show, los)   show or hide it, read the buttons, set the needles from term_los's result
//   gauge_buttons(g)             read the buttons: minimise, restore, scale
//   gauge_needles(g, los)        move the needles only (called every tick while the dial shows)
//   gauge_readout(g, texts)      the three lines under the dial (term_readout): range, range rate, next gate
//   gauge_close(g)               remove both windows
// The numbers come from lm/rndz/lm_term.ks. The level needle moves up and down with the rate along +X (up: thrust up); the upright needle moves
// left and right with the rate to the crew's right (right: thrust right). A needle on an end mark is at full scale or more. Under the dial: range,
// range rate and the next braking gate, then the two full scales on their keys; the one in use is lit. The line above the keys says when the
// front windows are off the CSM (the needles then stand centred; the figures stay).
//
// The dial is one picture (lm/images/gauge_face.png, drawn by tools/make_gauge_images.py: bezel, marks and axis names). kOS widgets cannot
// overlap, but STYLE:OVERFLOW grows, or with negative values shrinks, the area a widget's background picture is drawn in (kOS docs,
// Style:OVERFLOW; seen to work on this install, tests/probe_needle.ks). Each needle is an empty label 1 pixel high under the dial, with a plain
// picture as its background; its four overflow values put that picture anywhere over the dial, to the pixel.
// Minimised is a second window, as wide and with only the title line, put where the first one stood, so that - and + are at the
// same place. (A second window because a kOS window keeps its size when its widgets are hidden.)
//
// Both windows must be made with GUI() at the top level of the main script, never in a function (see core/dsky.ks), and then passed to gauge_fill.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_gui.ks").                       // gui_skin, gui_border, gui_label, gui_keep, gui_set, bold_text
RUNONCEPATH("0:/lm/rndz/lm_term.ks").                 // term_needle_px

// The first three must match tools/make_gauge_images.py.
GLOBAL GAUGE_DIAL_PX IS 241.                  // the dial's width and height, pixels
GLOBAL GAUGE_EDGE_PX IS 20.                   // the bezel round it, which holds the axis names
GLOBAL GAUGE_TRAVEL_PX IS 116.                // a needle's travel from the centre to full scale
GLOBAL GAUGE_NEEDLE_PX IS 3.                  // a needle's width, pixels
GLOBAL GAUGE_MID_PX IS FLOOR((GAUGE_DIAL_PX - GAUGE_NEEDLE_PX) / 2).      // a centred needle's distance from the dial's edge
GLOBAL GAUGE_BEZEL_PX IS GAUGE_DIAL_PX + 2 * GAUGE_EDGE_PX.               // the whole picture
GLOBAL GAUGE_PAD_PX IS 7.                     // the window's inner edge at the sides
GLOBAL GAUGE_WINDOW_WIDTH IS GAUGE_BEZEL_PX + 2 * GAUGE_PAD_PX.           // the width to pass to GUI() in the main script, for both windows
GLOBAL GAUGE_CORNER_PX IS 16.                 // the corners of gauge_frame.png
GLOBAL GAUGE_KEY_PX IS 35.                    // the height of the key pictures, shadow included
GLOBAL GAUGE_SHADOW_PX IS 3.                  // the shadow under a key
GLOBAL GAUGE_READ_FONT IS 15.                 // the figures under the dial
GLOBAL GAUGE_TEXT_RGB IS RGB(222 / 255, 218 / 255, 204 / 255).           // the dial's cream
GLOBAL GAUGE_GREY_RGB IS RGB(160 / 255, 163 / 255, 170 / 255).
GLOBAL GAUGE_AMBER_RGB IS RGB(1, 184 / 255, 50 / 255).
GLOBAL GAUGE_DARK_RGB IS RGB(24 / 255, 24 / 255, 26 / 255).              // text on a lit key
GLOBAL GAUGE_FACE_BG IS "lm/images/gauge_face".
GLOBAL GAUGE_NEEDLE_BG IS "lm/images/gauge_needle".
GLOBAL GAUGE_FRAME_BG IS "lm/images/gauge_frame".
GLOBAL GAUGE_KEY_BG IS "lm/images/gauge_key".
GLOBAL GAUGE_HOVER_BG IS "lm/images/gauge_key_hover".
GLOBAL GAUGE_PRESS_BG IS "lm/images/gauge_key_press".
GLOBAL GAUGE_LIT_BG IS "lm/images/gauge_key_lit".
GLOBAL GAUGE_SCALE_TEXT IS "FULL SCALE  mrad/s".
GLOBAL GAUGE_OFF_TEXT IS "+Z OFF THE CSM".

// gauge_tight: no margin or padding round a widget (kOS's own spacing left the window mostly empty).
FUNCTION gauge_tight {
  PARAMETER widget_w.
  FOR side IN LIST(widget_w:STYLE:MARGIN, widget_w:STYLE:PADDING) {
    SET side:LEFT TO 0.
    SET side:RIGHT TO 0.
    SET side:TOP TO 0.
    SET side:BOTTOM TO 0.
  }
  RETURN widget_w.
}

// gauge_caption: a cream caption in a window or a row.
FUNCTION gauge_caption {
  PARAMETER holder, text, width, size, align.
  LOCAL label_w IS gauge_tight(gui_label(holder, text, width, size, "", align)).
  SET label_w:STYLE:TEXTCOLOR TO GAUGE_TEXT_RGB.
  RETURN label_w.
}

// gauge_frame: the window's one dark, rounded frame and its narrow inner edge.
FUNCTION gauge_frame {
  PARAMETER win_w.
  gui_skin(win_w, GAUGE_FRAME_BG).
  gui_border(win_w, GAUGE_CORNER_PX).
  SET win_w:STYLE:PADDING:LEFT TO GAUGE_PAD_PX.
  SET win_w:STYLE:PADDING:RIGHT TO GAUGE_PAD_PX.
  SET win_w:STYLE:PADDING:TOP TO 8.
  SET win_w:STYLE:PADDING:BOTTOM TO 9.
}

// gauge_light: a key's pictures and text colour in every state (as in gui_style_key). Lit: cream, also under the mouse. Not lit: grey, brighter
// under the mouse, and moved down onto its shadow while held.
FUNCTION gauge_light {
  PARAMETER key_w, lit.
  LOCAL still IS CHOOSE GAUGE_LIT_BG IF lit ELSE GAUGE_KEY_BG.
  LOCAL over IS CHOOSE GAUGE_LIT_BG IF lit ELSE GAUGE_HOVER_BG.
  LOCAL held IS CHOOSE GAUGE_LIT_BG IF lit ELSE GAUGE_PRESS_BG.
  FOR state IN LIST(key_w:STYLE:NORMAL, key_w:STYLE:ON, key_w:STYLE:FOCUSED, key_w:STYLE:FOCUSED_ON) { SET state:BG TO still. }
  FOR state IN LIST(key_w:STYLE:HOVER, key_w:STYLE:HOVER_ON) { SET state:BG TO over. }
  FOR state IN LIST(key_w:STYLE:ACTIVE, key_w:STYLE:ACTIVE_ON) { SET state:BG TO held. }
  FOR state IN LIST(key_w:STYLE:NORMAL, key_w:STYLE:ON, key_w:STYLE:HOVER, key_w:STYLE:HOVER_ON,
                    key_w:STYLE:ACTIVE, key_w:STYLE:ACTIVE_ON, key_w:STYLE:FOCUSED, key_w:STYLE:FOCUSED_ON) {
    SET state:TEXTCOLOR TO CHOOSE GAUGE_DARK_RGB IF lit ELSE GUI_KEY_TEXT.
  }
}

// gauge_key: a raised, clickable key.
FUNCTION gauge_key {
  PARAMETER holder, text, width, size.
  LOCAL key_w IS gauge_tight(gui_keep(holder:ADDBUTTON(bold_text(text)))).
  gui_border(key_w, 8).                                             // the corners and rim are kept, the middle stretches
  SET key_w:STYLE:BORDER:BOTTOM TO 8 + GAUGE_SHADOW_PX.
  SET key_w:STYLE:PADDING:BOTTOM TO GAUGE_SHADOW_PX.                // the text sits on the face, above the shadow
  SET key_w:STYLE:WIDTH TO width.
  SET key_w:STYLE:HEIGHT TO GAUGE_KEY_PX.
  SET key_w:STYLE:FONTSIZE TO size.
  gauge_light(key_w, FALSE).
  RETURN key_w.
}

// gauge_scale: put the gauge on a full scale of full_mrad and light its key.
FUNCTION gauge_scale {
  PARAMETER g, full_mrad.
  SET g["FULL"] TO full_mrad.
  gauge_light(g["HI"], full_mrad = GAUGE_HI_MRAD).
  gauge_light(g["LO"], full_mrad = GAUGE_LO_MRAD).
}

// gauge_flat: a label of exactly this size, with no margin, padding or 9-slice border, so that positions under the dial are the sizes set.
FUNCTION gauge_flat {
  PARAMETER holder, wide, high, image.
  LOCAL widget_w IS gauge_tight(gui_keep(holder:ADDLABEL(""))).
  FOR side IN LIST(widget_w:STYLE:BORDER, widget_w:STYLE:OVERFLOW) {
    SET side:LEFT TO 0.
    SET side:RIGHT TO 0.
    SET side:TOP TO 0.
    SET side:BOTTOM TO 0.
  }
  SET widget_w:STYLE:WIDTH TO wide.
  SET widget_w:STYLE:HEIGHT TO high.
  SET widget_w:STYLE:BG TO image.
  RETURN widget_w.
}

// gauge_place: draw the picture of the label number slot under the dial (0 first) in the rectangle left, top, wide, high, in pixels from the top
// left corner of the dial's picture (bezel included). The label itself stays where the layout put it: at x 0, y GAUGE_BEZEL_PX + slot, the
// picture's width and 1 high. Each overflow value is how far the rectangle reaches past that edge of the label (negative: stops short of it).
FUNCTION gauge_place {
  PARAMETER widget_w, slot, left, top, wide, high.
  SET widget_w:STYLE:OVERFLOW:LEFT TO -left.
  SET widget_w:STYLE:OVERFLOW:RIGHT TO left + wide - GAUGE_BEZEL_PX.
  SET widget_w:STYLE:OVERFLOW:TOP TO GAUGE_BEZEL_PX + slot - top.
  SET widget_w:STYLE:OVERFLOW:BOTTOM TO top + high - (GAUGE_BEZEL_PX + slot + 1).
}

// gauge_level: the level needle, up_px pixels above the centre.
FUNCTION gauge_level {
  PARAMETER widget_w, up_px.
  gauge_place(widget_w, 0, GAUGE_EDGE_PX + 1, GAUGE_EDGE_PX + GAUGE_MID_PX - up_px, GAUGE_DIAL_PX - 2, GAUGE_NEEDLE_PX).   // pixels count downwards
}

// gauge_upright: the upright needle, side_px pixels right of the centre.
FUNCTION gauge_upright {
  PARAMETER widget_w, side_px.
  gauge_place(widget_w, 1, GAUGE_EDGE_PX + GAUGE_MID_PX + side_px, GAUGE_EDGE_PX + 1, GAUGE_NEEDLE_PX, GAUGE_DIAL_PX - 2).
}

// gauge_title: the top line of either window: the name, and a key at its right end.
FUNCTION gauge_title {
  PARAMETER win_w, wide, caption.
  LOCAL title_row IS gauge_tight(gui_keep(win_w:ADDHLAYOUT())).
  SET title_row:STYLE:MARGIN:BOTTOM TO 3.
  LOCAL name_w IS gauge_caption(title_row, bold_text("LOS RATE"), wide - 37, 14, "LEFT").
  SET name_w:STYLE:PADDING:LEFT TO 11.
  SET name_w:STYLE:PADDING:TOP TO 6.
  LOCAL button_w IS gauge_key(title_row, caption, 32, 18).
  SET button_w:STYLE:HEIGHT TO 24 + GAUGE_SHADOW_PX.             // lower than the scale keys
  RETURN button_w.
}

FUNCTION gauge_fill {
  PARAMETER win_w, mini_w.
  gauge_frame(win_w).
  gauge_frame(mini_w).
  LOCAL shrink_w IS gauge_title(win_w, GAUGE_BEZEL_PX, "-").
  LOCAL grow_w IS gauge_title(mini_w, GAUGE_BEZEL_PX, "+").
  LOCAL dial_box IS gauge_tight(gui_keep(win_w:ADDVLAYOUT())).
  gauge_flat(dial_box, GAUGE_BEZEL_PX, GAUGE_BEZEL_PX, GAUGE_FACE_BG).
  // The needles come after the dial, so that they are drawn on top of it.
  LOCAL level_w IS gauge_flat(dial_box, GAUGE_BEZEL_PX, 1, GAUGE_NEEDLE_BG).
  LOCAL upright_w IS gauge_flat(dial_box, GAUGE_BEZEL_PX, 1, GAUGE_NEEDLE_BG).
  gauge_level(level_w, 0).
  gauge_upright(upright_w, 0).
  LOCAL read_list IS LIST().
  FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO {
    read_list:ADD(gauge_caption(win_w, "", GAUGE_BEZEL_PX, GAUGE_READ_FONT, "CENTER")).
  }
  SET read_list[0]:STYLE:MARGIN:TOP TO 4.
  LOCAL caption_w IS gauge_caption(win_w, GAUGE_SCALE_TEXT, GAUGE_BEZEL_PX, 11, "CENTER").
  SET caption_w:STYLE:TEXTCOLOR TO GAUGE_GREY_RGB.
  SET caption_w:STYLE:MARGIN:TOP TO 4.
  LOCAL keys_row IS gauge_tight(gui_keep(win_w:ADDHLAYOUT())).
  SET keys_row:STYLE:MARGIN:TOP TO 5.
  LOCAL key_wide IS FLOOR((GAUGE_BEZEL_PX - 30) / 2).              // 30: 11 outside each key and 8 between them
  LOCAL hi_w IS gauge_key(keys_row, "±" + GAUGE_HI_MRAD, key_wide, 15).
  LOCAL lo_w IS gauge_key(keys_row, "±" + GAUGE_LO_MRAD, key_wide, 15).
  SET hi_w:STYLE:MARGIN:LEFT TO 11.
  SET lo_w:STYLE:MARGIN:LEFT TO 8.
  LOCAL g IS LEXICON("WIN", win_w, "MINI", mini_w, "SHRINK", shrink_w, "GROW", grow_w, "LEVEL", level_w, "UPRIGHT", upright_w,
                     "UP_PX", 0, "SIDE_PX", 0, "HI", hi_w, "LO", lo_w, "CAPTION", caption_w, "FULL", GAUGE_HI_MRAD,
                     "SHOWN", FALSE, "MINIMISED", FALSE, "READ", read_list).
  gauge_scale(g, GAUGE_HI_MRAD).
  RETURN g.
}

// gauge_swap: minimise or restore a gauge that is on screen: the other window takes this one's place.
FUNCTION gauge_swap {
  PARAMETER g, small.
  LOCAL from_w IS CHOOSE g["MINI"] IF g["MINIMISED"] ELSE g["WIN"].
  LOCAL to_w IS CHOOSE g["MINI"] IF small ELSE g["WIN"].
  SET to_w:X TO from_w:X.
  SET to_w:Y TO from_w:Y.
  from_w:HIDE().
  to_w:SHOW().
  SET g["MINIMISED"] TO small.
}

// gauge_buttons: call only while the gauge is on screen. It stays minimised until restored, also if the gauge goes and comes back.
FUNCTION gauge_buttons {
  PARAMETER g.
  IF g["SHRINK"]:TAKEPRESS { gauge_swap(g, TRUE). }
  IF g["GROW"]:TAKEPRESS { gauge_swap(g, FALSE). }
  IF g["HI"]:TAKEPRESS { gauge_scale(g, GAUGE_HI_MRAD). }
  IF g["LO"]:TAKEPRESS { gauge_scale(g, GAUGE_LO_MRAD). }
}

// gauge_needles: los is term_los's result. UP_PX and SIDE_PX are the needles' distances from the centre, up and right positive; only a needle that
// moved is redrawn.
FUNCTION gauge_needles {
  PARAMETER g, los.
  LOCAL up_px IS term_needle_px(los["UP"], g["FULL"], GAUGE_TRAVEL_PX).
  LOCAL side_px IS term_needle_px(los["RIGHT"], g["FULL"], GAUGE_TRAVEL_PX).
  IF up_px <> g["UP_PX"] {
    gauge_level(g["LEVEL"], up_px).
    SET g["UP_PX"] TO up_px.
  }
  IF side_px <> g["SIDE_PX"] {
    gauge_upright(g["UPRIGHT"], side_px).
    SET g["SIDE_PX"] TO side_px.
  }
  IF gui_set(g["CAPTION"], CHOOSE GAUGE_SCALE_TEXT IF los["ONAXIS"] ELSE GAUGE_OFF_TEXT) {
    SET g["CAPTION"]:STYLE:TEXTCOLOR TO CHOOSE GAUGE_GREY_RGB IF los["ONAXIS"] ELSE GAUGE_AMBER_RGB.
  }
}

// gauge_readout: texts is term_readout's result. Only a line that changed is redrawn.
FUNCTION gauge_readout {
  PARAMETER g, texts.
  FROM { LOCAL i IS 0. } UNTIL i >= g["READ"]:LENGTH STEP { SET i TO i + 1. } DO { gui_set(g["READ"][i], bold_text(texts[i])). }
}

// gauge_update: los is term_los's result when show is TRUE (anything when it is FALSE).
FUNCTION gauge_update {
  PARAMETER g, show, los.
  IF NOT show {
    IF g["SHOWN"] {
      g["WIN"]:HIDE().
      g["MINI"]:HIDE().
      SET g["SHOWN"] TO FALSE.
    }
    RETURN.
  }
  IF g["SHOWN"] { gauge_buttons(g). }
  gauge_needles(g, los).
  IF NOT g["SHOWN"] {
    IF g["MINIMISED"] { g["MINI"]:SHOW(). } ELSE { g["WIN"]:SHOW(). }
    SET g["SHOWN"] TO TRUE.
  }
}

// gauge_close: call it when the script ends, or a window stays on screen.
FUNCTION gauge_close {
  PARAMETER g.
  FOR win_w IN LIST(g["WIN"], g["MINI"]) {
    win_w:HIDE().
    win_w:DISPOSE().
  }
}
