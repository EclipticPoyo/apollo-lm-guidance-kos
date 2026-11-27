// lm_axes.ks -- the measured turn of kOS's raw axes (release 1.5).
//   axes_mark()                            how the raw axes sit now: LEXICON("P", vec, "N", vec)
//   axes_carry(vec, mark_from, mark_to)    a vector held in the axes of one mark, in the axes of the other
// Near a body the raw axes of kOS turn with it; higher up they stand still (measured: research of 1.5 rendezvous, section 13.1; the height where it changes is KSP's, per body).
// A vector kept for later is only right if the turn since it was made is known. Instead of assuming one, a mark records where two fixed directions point in the raw
// axes: N, the body's north pole, and P, SOLARPRIMEVECTOR (fixed among the stars) taken square to N. Store the mark with the vector; later, carry the vector to a new mark.
// A turn is only known once it has happened: for a future time use plan_spin_rotate (lm_plan.ks), which assumes the axes turn with the body.
// Luminary has no counterpart: the AGC's platform does not turn.
// Only axes_mark reads kOS; axes_carry is pure, so it can be tested on the pad with made-up marks.

RUNONCEPATH("0:/shared/lm_frame.ks").        // moon_spin

FUNCTION axes_mark {
  LOCAL pole_vec IS moon_spin():NORMALIZED.
  // VXCL(n, v) is v with its part along n taken out.
  RETURN LEXICON("P", VXCL(pole_vec, SOLARPRIMEVECTOR):NORMALIZED, "N", pole_vec).
}

// axes_carry: each mark gives three unit vectors at right angles (P, N x P, N). The vector's three components along the "from" set are its place among the stars;
// adding them up again along the "to" set writes the same direction in the new axes. VCRS is used on both sides, so its handedness cancels.
FUNCTION axes_carry {
  PARAMETER vec, mark_from, mark_to.
  LOCAL p_from IS mark_from["P"].
  LOCAL n_from IS mark_from["N"].
  LOCAL p_to IS mark_to["P"].
  LOCAL n_to IS mark_to["N"].
  RETURN p_to * VDOT(vec, p_from) + VCRS(n_to, p_to) * VDOT(vec, VCRS(n_from, p_from)) + n_to * VDOT(vec, n_from).
}
