// lm_j_nouns.ks -- the descent nouns whose contents Luminary 210 (the J profile) changed from 099 (spec J2; PINBALL_NOUN_TABLES 210 lines 733-755):
//   N60 R1 is FORVEL (the forward horizontal velocity along the LM's forward axis, LANDING_ANALOG_DISPLAYS CROSCOMP), not VHORIZ; R2, R3 as 099.
//   N63 R1 is DELTAH (radar altitude minus computed altitude, whole feet), R2 HDOT, R3 HCALC1 (here plain HCALC, as 099).
//   N68 R1 is the Z (downrange) component of the position relative to the site, in nautical miles (RANGEDSP, "SM Z-AXIS RANGE", LUNAR_LANDING_
//        GUIDANCE_EQUATIONS 210 line 490), R2 TTFDISP, R3 ABVEL.
// The other nouns are the same in both, so they come from noun_registers (lm_nouns.ks). derived["FORVEL"] is set in lm_veh_nav for J.

RUNONCEPATH("0:/lm/lm_nouns.ks").

// j_noun_registers: the three register texts for a noun in the J profile (an empty LIST for no such noun, as noun_registers).
FUNCTION j_noun_registers {
  PARAMETER noun_no, derived.
  LOCAL regs IS noun_registers(noun_no, derived).
  IF regs:LENGTH = 0 OR NOT derived["VALID"] { RETURN regs. }
  IF noun_no = 60 {
    LOCAL forvel IS 0.
    IF derived:HASKEY("FORVEL") { SET forvel TO derived["FORVEL"]. }
    SET regs[0] TO fmt_reg(ms_to_fps(forvel), 1).
  }
  IF noun_no = 63 { SET regs[0] TO fmt_reg(m_to_ft(derived["DELTAH"]), 0). }
  IF noun_no = 68 {
    LOCAL range_z IS derived["RGU"]:Z.
    SET regs[0] TO fmt_reg(m_to_nm(range_z), 1).
    SET regs[2] TO fmt_reg(ms_to_fps(derived["ABVEL"]), 1).
  }
  RETURN regs.
}

// lm_forvel: the horizontal surface velocity along the LM's forward axis (m/s): v_surf (the surface-relative velocity) with its vertical part
// (along r_vec) removed, projected on the forward axis fwd_vec with its own vertical part removed. Zero when the forward axis is vertical.
FUNCTION lm_forvel {
  PARAMETER v_surf, r_vec, fwd_vec.
  LOCAL up_vec IS r_vec:NORMALIZED.
  LOCAL v_horiz IS v_surf - up_vec * VDOT(v_surf, up_vec).
  LOCAL fwd_horiz IS fwd_vec - up_vec * VDOT(fwd_vec, up_vec).
  IF fwd_horiz:MAG < 1e-9 { RETURN 0. }
  RETURN VDOT(v_horiz, fwd_horiz:NORMALIZED).
}
