// probe_needle.ks -- can kOS slide a needle smoothly over a dial? For the drift gauge. Throwaway test; nothing is steered.
//   RUN pneedle.        (the stub; or RUNPATH("0:/tests/probe_needle.ks").)   any craft, anywhere; under a minute.
// Method: widgets cannot overlap, but STYLE:OVERFLOW grows (or, with negative values, shrinks) the area a widget's background is drawn in
// (kOS docs, Style:OVERFLOW). Each needle is an empty label 1 pixel high under the dial, with a plain white background; its four overflow values put
// that background anywhere over the dial. Unknown until seen in game: whether negative values draw properly, whether the needles are on top of the
// dial, and whether changing one widget disturbs another.
// Log: 0:/lm/logs/probe_needle.log.

GLOBAL PND_LOG IS "0:/lm/logs/probe_needle.log".
GLOBAL PND_SIZE IS 150.          // the dial's width and height, pixels
GLOBAL PND_WIDE IS 3.            // needle width, pixels
IF EXISTS(PND_LOG) { DELETEPATH(PND_LOG). }

FUNCTION pnd_say {
  PARAMETER text.
  PRINT text.
  LOG text TO PND_LOG.
}

// pnd_flat: no margin, padding or 9-slice border, so layout positions are exactly the sizes set.
FUNCTION pnd_flat {
  PARAMETER widget_w, wide, high, image.
  FOR side IN LIST(widget_w:STYLE:MARGIN, widget_w:STYLE:PADDING, widget_w:STYLE:BORDER, widget_w:STYLE:OVERFLOW) {
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

// pnd_place: draw the background of needle number slot (0 = first label under the dial) in the rectangle left, top, wide, high, measured in pixels
// from the dial's top left corner. The label itself stays at x 0, y PND_SIZE + slot, PND_SIZE wide and 1 high.
FUNCTION pnd_place {
  PARAMETER needle_w, slot, left, top, wide, high.
  SET needle_w:STYLE:OVERFLOW:LEFT TO -left.
  SET needle_w:STYLE:OVERFLOW:RIGHT TO left + wide - PND_SIZE.
  SET needle_w:STYLE:OVERFLOW:TOP TO PND_SIZE + slot - top.
  SET needle_w:STYLE:OVERFLOW:BOTTOM TO top + high - (PND_SIZE + slot + 1).
}

LOCAL pnd_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.

// The window is made at the top level: windows made inside a function vanished on this install.
LOCAL pnd_win IS GUI(220).
SET pnd_win:X TO 580.
SET pnd_win:Y TO 60.
pnd_win:ADDLABEL("NEEDLE PROBE").
LOCAL pnd_row IS pnd_win:ADDHLAYOUT().
pnd_row:ADDSPACING(25).
LOCAL pnd_box IS pnd_row:ADDVLAYOUT().
LOCAL pnd_dial IS pnd_flat(pnd_box:ADDLABEL(""), PND_SIZE, PND_SIZE, "lm/images/key_black").
// Slots 0 and 1: the dim centre cross (fixed). Slots 2 and 3: the moving needles, drawn after it, so on top of it.
LOCAL pnd_marks IS LIST().
FOR image IN LIST("lm/images/lamp_off", "lm/images/lamp_off", "lm/images/lamp_white", "lm/images/lamp_white") {
  pnd_marks:ADD(pnd_flat(pnd_box:ADDLABEL(""), PND_SIZE, 1, image)).
}
LOCAL pnd_ref IS pnd_win:ADDLABEL("This line and the button should never move or change.").
LOCAL pnd_btn IS pnd_win:ADDBUTTON("A BUTTON").

LOCAL pnd_mid IS FLOOR((PND_SIZE - PND_WIDE) / 2).
pnd_place(pnd_marks[0], 0, 0, pnd_mid + 1, PND_SIZE, 1).
pnd_place(pnd_marks[1], 1, pnd_mid + 1, 0, 1, PND_SIZE).

// pnd_needles: up_at and right_at from -1 to 1. The level needle moves up and down, the upright one left and right.
FUNCTION pnd_needles {
  PARAMETER up_at, right_at.
  pnd_place(pnd_marks[2], 2, 0, pnd_mid - ROUND(up_at * pnd_mid), PND_SIZE, PND_WIDE).
  pnd_place(pnd_marks[3], 3, pnd_mid + ROUND(right_at * pnd_mid), 0, PND_WIDE, PND_SIZE).
}

// pnd_readback: the overflow values read back (left, right, top, bottom).
FUNCTION pnd_readback {
  PARAMETER name, widget_w.
  LOCAL o IS widget_w:STYLE:OVERFLOW.
  LOG "  " + name + " overflow " + o:LEFT + " " + o:RIGHT + " " + o:TOP + " " + o:BOTTOM TO PND_LOG.
}

// pnd_run: for span_s seconds set the needles every period_s from shape: 0 still in the middle, 1 level needle up and down, 2 upright needle left
// and right, 3 both going round. Each sweep takes 8 s.
FUNCTION pnd_run {
  PARAMETER text, shape, span_s, period_s.
  pnd_say(text).
  LOCAL from_ut IS TIME:SECONDS.
  LOCAL updates IS 0.
  UNTIL TIME:SECONDS >= from_ut + span_s {
    LOCAL turned IS (TIME:SECONDS - from_ut) * 45.
    IF shape = 0 { pnd_needles(0, 0). }
    IF shape = 1 { pnd_needles(SIN(turned), 0). }
    IF shape = 2 { pnd_needles(0, SIN(turned)). }
    IF shape = 3 { pnd_needles(SIN(turned), COS(turned)). }
    SET updates TO updates + 1.
    WAIT period_s.
  }
  LOG "  updates " + updates + " in " + span_s + " s" TO PND_LOG.
  pnd_readback("level needle", pnd_marks[2]).
  pnd_readback("upright needle", pnd_marks[3]).
  pnd_readback("dial (all 0)", pnd_dial).
  pnd_readback("text line", pnd_ref).
  pnd_readback("button", pnd_btn).
}

pnd_needles(0, 0).
pnd_win:SHOW().
pnd_run("1. Black square, a dim cross, two white needles crossing in the MIDDLE.", 0, 6, 0.1).
pnd_run("2. LEVEL needle slides up first, then down, edge to edge.", 1, 8, 0.02).
pnd_run("3. UPRIGHT needle slides right first, then left, edge to edge.", 2, 8, 0.02).
pnd_run("4. Both, smoothly.", 3, 8, 0.02).
pnd_run("5. The same, moved only every half second (what the gauge does now).", 3, 8, 0.5).
pnd_say("6. The window goes away for 3 s, then comes back.").
pnd_win:HIDE().
WAIT 3.
pnd_win:SHOW().
pnd_run("7. Back as before, needles in the middle.", 0, 6, 0.1).
pnd_win:HIDE().
pnd_win:DISPOSE().
SET CONFIG:IPU TO pnd_ipu.
pnd_say("Needle probe done. Say what looked wrong, if anything.").
