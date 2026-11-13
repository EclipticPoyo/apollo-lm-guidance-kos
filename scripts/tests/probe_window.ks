// probe_window.ks -- which face of the lander is the crew window on?
//
// kOS cannot see the 3D model, so this does not guess. It draws six labelled arrows out of the lander along the six
// directions the steering code uses, taken from SHIP:FACING (the same frame as WINDOW_AXIS in lm_constants.ks):
//   TOP / BOTTOM  = +/- SHIP:FACING:TOPVECTOR      STAR / PORT = +/- SHIP:FACING:STARVECTOR
//   NOSE / ENGINE = +/- SHIP:FACING:FOREVECTOR
// You orbit the camera (flight view, external camera) until you are looking at the crew window, and read the label of
// the arrow that comes out of the window towards you. The arrows turn with the ship, so they stay on the same faces.
//
// VECDRAW (kOS docs, structures/misc/vecdraw): start and vec given as delegates (small functions kOS calls every frame)
// keep the arrow on the ship as it turns. Width is screen-relative, not metres, so the arrows stay readable at any zoom.
// Setup: the Moon (any body), any orbit or the ground, the RO LM, tanks irrelevant. Nothing is steered or fired.

LOCAL log_path IS "0:/lm/logs/probe_window.log".
IF EXISTS(log_path) { DELETEPATH(log_path). }

FUNCTION say {
  PARAMETER text.
  PRINT text.
  LOG text TO log_path.
}

// face_dir: the direction (raw axes, unit length) a face name points, read from SHIP:FACING every time it is asked.
FUNCTION face_dir {
  PARAMETER face_name.
  IF face_name = "TOP" { RETURN SHIP:FACING:TOPVECTOR. }
  IF face_name = "BOTTOM" { RETURN -SHIP:FACING:TOPVECTOR. }
  IF face_name = "STAR" { RETURN SHIP:FACING:STARVECTOR. }
  IF face_name = "PORT" { RETURN -SHIP:FACING:STARVECTOR. }
  IF face_name = "NOSE" { RETURN SHIP:FACING:FOREVECTOR. }
  RETURN -SHIP:FACING:FOREVECTOR.          // ENGINE
}

// face_arrow: one labelled arrow, starting 2 m out from the ship's centre (so it begins outside a small hull) and 8 m
// long. The parameters are copied per call, so each arrow's delegates keep their own face name.
FUNCTION face_arrow {
  PARAMETER face_name, arrow_colour.
  RETURN VECDRAW(
    { RETURN face_dir(face_name) * 2. },
    { RETURN face_dir(face_name) * 8. },
    arrow_colour, face_name, 1, TRUE, 0.15, TRUE, TRUE).
}

CLEARVECDRAWS().
LOCAL arrows IS LIST().
arrows:ADD(face_arrow("TOP", RGB(1, 1, 0))).          // yellow
arrows:ADD(face_arrow("BOTTOM", RGB(1, 0.15, 0.15))). // red
arrows:ADD(face_arrow("STAR", RGB(0, 1, 1))).         // cyan
arrows:ADD(face_arrow("PORT", RGB(1, 0, 1))).         // magenta
arrows:ADD(face_arrow("NOSE", RGB(1, 1, 1))).         // white
arrows:ADD(face_arrow("ENGINE", RGB(1, 0.55, 0))).    // orange

say("probe_window: " + SHIP:NAME + " at " + SHIP:BODY:NAME + ", control part " + SHIP:CONTROLPART:NAME + " (" + SHIP:CONTROLPART:TITLE + ")").
say("fore " + SHIP:FACING:FOREVECTOR + "  top " + SHIP:FACING:TOPVECTOR + "  star " + SHIP:FACING:STARVECTOR).
say("Arrows are drawn: TOP yellow, BOTTOM red, STAR cyan, PORT magenta, NOSE white, ENGINE orange.").
say("1. Leave map view (M) and use the external camera (C).").
say("2. Orbit the camera until you look straight at the crew window.").
say("3. The arrow that comes out of the window towards you has the answer in its label. Note it.").
say("4. Check against the engine bell: the ENGINE arrow must come out of the engine end and the NOSE arrow out of the other end.").
say("Tell Claude the label. Then click in this terminal and press any key to remove the arrows.").

LOCAL pressed IS TERMINAL:INPUT:GETCHAR().     // waits for a key; the arrows keep following the ship meanwhile
FOR drawn IN arrows { SET drawn:SHOW TO FALSE. }
CLEARVECDRAWS().
say("probe_window done. Log: " + log_path).
