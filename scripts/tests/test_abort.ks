// test_abort.ks -- pad test for the aborts, P70 and P71 (release 1.5): the abort control layer in dry mode, the rules, the programmes and the
// vehicle's wiring. No flight: CTL_DRY is TRUE and the ship's state is made up. The ship reads and writes themselves (the keys, the staging, the
// steering) can only be checked in flight.
//   RUNPATH("0:/tests/test_abort.ks").   Log: 0:/lm/logs/test_abort.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").
RUNONCEPATH("0:/lm/descent/lm_control.ks").
RUNONCEPATH("0:/lm/ascent/lm_p70.ks").

test_begin("0:/lm/logs/test_abort.log").
SET CTL_DRY TO TRUE.
SET CTL_DRY_STATUS TO "FLYING".          // earlier tests of RUN pad. share these globals
SET CTL_DRY_ATTACHED TO TRUE.
LOCAL tab_keep_facing IS P40_DRY_FACING.

// ---- the control layer, dry ----
SET CTL_THR TO 0.1.
ctl_abort_take(FALSE).
assert_near("take on the descent engine: the throttle command is full", CTL_THR, 1, 0).
SET CTL_THR TO 0.1.
ctl_abort_take(TRUE).
assert_near("take on the ascent stage: the throttle command is full", CTL_THR, 1, 0).
SET CTL_THR TO 0.
SET CTL_DRY_ABORT TO TRUE.
assert_true("the Abort key is read", ctl_abort_key()).
SET CTL_DRY_ABORT TO FALSE.
assert_true("the Abort key is read as off", NOT ctl_abort_key()).
SET CTL_DRY_AG10 TO TRUE.
assert_true("action group 10 (the 0 key) is read", ctl_ag10()).
SET CTL_DRY_AG10 TO FALSE.
assert_true("action group 10 is read as off", NOT ctl_ag10()).
SET CTL_DRY_ATTACHED TO FALSE.
assert_true("the descent stage can read as gone", NOT ctl_descent_attached()).
SET CTL_DRY_ATTACHED TO TRUE.
assert_true("the descent stage reads as attached", ctl_descent_attached()).

// ---- the rules (spec 6) -----------------------------------------------------------------------------------------------------
GLOBAL TAB_MU IS 4.9028e12.
GLOBAL TAB_SITE_R IS 1737400.
GLOBAL TAB_CSM_R IS 1737400 + 60 * 1852.
GLOBAL TAB_RVEC IS V(1747400, 0, 0).
GLOBAL TAB_VVEC IS V(-30, 1000, 0).
GLOBAL TAB_AXIS IS V(1, 0, 0).
GLOBAL TAB_T IS 5000.
GLOBAL TAB_G IS 4.9028e12.                 // the mu in the state (0 in the engine-failure tests: nothing is measured)
GLOBAL TAB_MASS IS 12000.
GLOBAL TAB_MSG IS "".                      // every message since the last tab_set, joined
GLOBAL TAB_AX IS LEXICON("P", V(1, 0, 0), "N", V(0, 0, 1)).    // one axes mark: the raw axes stand still

// tab_armed: abort state armed by an ignition at UT t0, with the CSM's plane (the XY plane) as the saved one.
FUNCTION tab_armed {
  PARAMETER t0.
  LOCAL abt IS abt_new().
  abt_ignition(abt, t0, asc_qaxis(V(TAB_CSM_R, 0, 0), V(0, 1000, 0)), t0, TAB_AX).
  RETURN abt.
}

LOCAL tab_off IS abt_new().
assert_true("new abort state: not armed", NOT tab_off["ARMED"] AND tab_off["T0"] < 0 AND tab_off["PLANE_T"] < 0).
abt_ignition(tab_off, -1, V(0, 0, 1), 90, TAB_AX).
assert_true("no ignition yet: not armed", NOT tab_off["ARMED"]).
abt_ignition(tab_off, 100, V(0, 0, 1), 100, TAB_AX).
assert_true("armed at ignition, with the clock and the plane", tab_off["ARMED"] AND tab_off["T0"] = 100 AND tab_off["PLANE_T"] = 100).
abt_ignition(tab_off, 100, V(0, 1, 0), 105, TAB_AX).
assert_true("the same ignition again keeps the plane", tab_off["PLANE_T"] = 100 AND VANG(tab_off["QAXIS"], V(0, 0, 1)) < 0.001).
abt_disarm(tab_off).
abt_ignition(tab_off, 100, V(0, 0, 1), 110, TAB_AX).
assert_true("disarmed: the old ignition does not arm it again", NOT tab_off["ARMED"]).
abt_ignition(tab_off, 400, V(0, 1, 0), 400, TAB_AX).
assert_true("a new ignition (V97) arms and restarts the abort clock, keeping the first plane",
            tab_off["ARMED"] AND tab_off["T0"] = 400 AND VANG(tab_off["QAXIS"], V(0, 0, 1)) < 0.001).

FOR tab_no IN LIST(63, 64, 65, 66, 68, 70, 71) {
  LOCAL tab_keep IS tab_armed(100).
  abt_after_step(tab_keep, tab_no).
  assert_true("armed stays after a cycle in P" + tab_no, tab_keep["ARMED"]).
}
FOR tab_no IN LIST(-1, 0, 12, 40) {
  LOCAL tab_drop IS tab_armed(100).
  abt_after_step(tab_drop, tab_no).
  assert_true("disarmed with programme " + tab_no, NOT tab_drop["ARMED"]).
}

// abt_key_request takes (abt, current programme, landed, attached, key); abt_refusal (abt, current programme, landed, attached, wanted).
LOCAL tab_a IS tab_armed(100).
FOR tab_no IN LIST(63, 64, 65, 66, 68) {
  assert_true("P" + tab_no + " attached: Backspace P70", abt_key_request(tab_a, tab_no, FALSE, TRUE, "ABORT") = 70).
  assert_true("P" + tab_no + " attached: 0 P71", abt_key_request(tab_a, tab_no, FALSE, TRUE, "STAGE0") = 71).
  assert_true("P" + tab_no + " attached: a staging P71", abt_key_request(tab_a, tab_no, FALSE, TRUE, "SEPARATED") = 71).
}
assert_true("flying: V37 70 allowed", abt_refusal(tab_a, 63, FALSE, TRUE, 70) = "").
assert_true("flying: V37 71 refused, press 0", abt_refusal(tab_a, 63, FALSE, TRUE, 71):CONTAINS("press 0")).
assert_true("landed: Backspace nothing", abt_key_request(tab_a, 68, TRUE, TRUE, "ABORT") = -1).
assert_true("landed: 0 P71", abt_key_request(tab_a, 68, TRUE, TRUE, "STAGE0") = 71).
assert_true("landed: a staging P71", abt_key_request(tab_a, 68, TRUE, FALSE, "SEPARATED") = 71).
assert_true("landed: V37 70 refused", abt_refusal(tab_a, 68, TRUE, TRUE, 70) <> "").
assert_true("landed attached: V37 71 refused", abt_refusal(tab_a, 68, TRUE, TRUE, 71) <> "").
assert_true("landed, staged: V37 71 allowed", abt_refusal(tab_a, 68, TRUE, FALSE, 71) = "").
assert_true("detached: Backspace nothing", abt_key_request(tab_a, 64, FALSE, FALSE, "ABORT") = -1).
assert_true("detached: 0 P71", abt_key_request(tab_a, 64, FALSE, FALSE, "STAGE0") = 71).
assert_true("detached: a staging P71", abt_key_request(tab_a, 64, FALSE, FALSE, "SEPARATED") = 71).
assert_true("detached: V37 70 refused, the descent stage is gone", abt_refusal(tab_a, 64, FALSE, FALSE, 70):CONTAINS("gone")).
assert_true("detached: V37 71 allowed", abt_refusal(tab_a, 64, FALSE, FALSE, 71) = "").
FOR tab_att IN LIST(TRUE, FALSE) {
  assert_true("in P70 (attached " + tab_att + "): Backspace nothing", abt_key_request(tab_a, 70, FALSE, tab_att, "ABORT") = -1).
  assert_true("in P70 (attached " + tab_att + "): 0 P71", abt_key_request(tab_a, 70, FALSE, tab_att, "STAGE0") = 71).
  assert_true("in P70 (attached " + tab_att + "): a staging P71", abt_key_request(tab_a, 70, FALSE, tab_att, "SEPARATED") = 71).
  assert_true("in P70 (attached " + tab_att + "): V37 70 refused", abt_refusal(tab_a, 70, FALSE, tab_att, 70) <> "").
}
assert_true("in P70 attached: V37 71 refused, press 0", abt_refusal(tab_a, 70, FALSE, TRUE, 71):CONTAINS("press 0")).
assert_true("in P70 detached: V37 71 allowed", abt_refusal(tab_a, 70, FALSE, FALSE, 71) = "").
FOR tab_key IN LIST("ABORT", "STAGE0", "SEPARATED") {
  assert_true("in P71: " + tab_key + " nothing", abt_key_request(tab_a, 71, FALSE, FALSE, tab_key) = -1).
  assert_true("no programme: " + tab_key + " nothing", abt_key_request(tab_a, -1, FALSE, TRUE, tab_key) = -1).
}
assert_true("in P71: V37 70 refused", abt_refusal(tab_a, 71, FALSE, FALSE, 70) <> "").
assert_true("in P71: V37 71 refused", abt_refusal(tab_a, 71, FALSE, FALSE, 71) <> "").
LOCAL tab_d IS abt_new().
assert_true("disarmed: Backspace nothing", abt_key_request(tab_d, 63, FALSE, TRUE, "ABORT") = -1).
assert_true("disarmed: 0 nothing", abt_key_request(tab_d, 63, FALSE, TRUE, "STAGE0") = -1).
assert_true("disarmed: V37 70 refused with a reason", abt_refusal(tab_d, 63, FALSE, TRUE, 70) <> "").
assert_true("disarmed: V37 71 refused with a reason", abt_refusal(tab_d, 63, FALSE, FALSE, 71) <> "").

// the keys: a press is a change of state, latched until taken.
LOCAL tab_kk IS abt_keys_new(FALSE, FALSE, TRUE).
abt_keys_poll(tab_kk, TRUE, TRUE, TRUE).
LOCAL tab_late IS abt_new().
assert_true("keys pressed while not armed: nothing", abt_keys_take(tab_late, tab_kk, 63, FALSE, TRUE) = -1).
abt_ignition(tab_late, 100, V(0, 0, 1), 100, TAB_AX).
abt_keys_poll(tab_kk, TRUE, TRUE, TRUE).
assert_true("armed afterwards: the old presses are gone", abt_keys_take(tab_late, tab_kk, 63, FALSE, TRUE) = -1).
abt_keys_poll(tab_kk, FALSE, TRUE, TRUE).
assert_true("the next change of Backspace is a press", abt_keys_take(tab_late, tab_kk, 63, FALSE, TRUE) = 70).
assert_true("taken once", abt_keys_take(tab_late, tab_kk, 63, FALSE, TRUE) = -1).
abt_keys_poll(tab_kk, TRUE, FALSE, FALSE).
assert_true("0, a staging and Backspace in one poll: P71", abt_keys_take(tab_late, tab_kk, 63, FALSE, FALSE) = 71).
assert_true("and only once", abt_keys_take(tab_late, tab_kk, 63, FALSE, FALSE) = -1).
LOCAL tab_ks2 IS abt_keys_new(FALSE, FALSE, TRUE).
abt_keys_poll(tab_ks2, FALSE, FALSE, TRUE).
abt_keys_poll(tab_ks2, FALSE, FALSE, TRUE).
assert_true("descent stage still attached (a destroyed engine too): no staging seen", abt_keys_take(tab_late, tab_ks2, 66, TRUE, TRUE) = -1).
abt_keys_poll(tab_ks2, FALSE, FALSE, FALSE).
assert_true("the descent stage leaving asks for P71", abt_keys_take(tab_late, tab_ks2, 66, FALSE, FALSE) = 71).
abt_keys_poll(tab_ks2, FALSE, FALSE, FALSE).
assert_true("staying gone asks for nothing more", abt_keys_take(tab_late, tab_ks2, 66, FALSE, FALSE) = -1).

// ---- the programmes ---------------------------------------------------------------------------------------------------------
// The state is made up: the landing site on +X, "downrange" +Y, the CSM at 60 nmi in the XY plane, 7 degrees behind. P40_DRY_FACING is the
// ship's attitude at the abort (braking: 80 degrees from the vertical, against the motion).
FUNCTION tab_csm {
  LOCAL speed IS SQRT(TAB_MU / TAB_CSM_R).
  RETURN LEXICON("NAME", "CSM", "R", V(COS(7), -SIN(7), 0) * TAB_CSM_R, "V", V(SIN(7), COS(7), 0) * speed).
}
// tab_set: the state at height (m above the site) with horizontal and radial speed (m/s) and mass (kg), at UT 5000.
FUNCTION tab_set {
  PARAMETER height, horizontal, radial, mass_kg.
  SET TAB_T TO 5000.
  SET TAB_G TO TAB_MU.
  SET TAB_RVEC TO V(TAB_SITE_R + height, 0, 0).
  SET TAB_VVEC TO V(radial, horizontal, 0).
  SET TAB_MASS TO mass_kg.
  SET TAB_AXIS TO V(COS(80), -SIN(80), 0).
  SET P40_DRY_FACING TO LOOKDIRUP(TAB_AXIS, V(1, 0, 0)).
  SET TAB_MSG TO "".
}
FUNCTION tab_craft {
  PARAMETER attached, csm.
  RETURN LEXICON("DPS", "DPS", "APS", "APS", "ATTACHED", attached, "CORE_STAYS", TRUE, "LANDED", FALSE, "MASS_KG", TAB_MASS,
                 "SITE_R", TAB_SITE_R, "R", TAB_RVEC, "V", TAB_VVEC, "CSM", csm, "CLOCK_ZERO", 1000, "MU", TAB_MU, "AX", TAB_AX).
}
// tab_prev: what the running descent programme hands over: only its number is read.
FUNCTION tab_prev {
  PARAMETER prog_no.
  RETURN LEXICON("PROG_NO", prog_no).
}
// tab_start: p70_start with a fresh store (also the one the nouns read).
FUNCTION tab_start {
  PARAMETER prog_no, by_key, prev, abt, profile, craft.
  LOCAL vault IS store_new(lm_cells_for(profile)).
  lm_store_put_rls(vault, V(TAB_SITE_R, 0, 0)).
  SET LM_VEH["STORE"] TO vault.
  RETURN p70_start(prog_no, by_key, prev, abt, vault, profile, TAB_T, craft, V(0, 0, 0)).
}
FUNCTION tab_keys {
  LOCAL ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
  SET ks["VERB"] TO 16.
  SET ks["NOUN"] TO 60.
  RETURN ks.
}
FUNCTION tab_state {
  RETURN LEXICON("R", TAB_RVEC, "V", TAB_VVEC, "T", TAB_T, "MASS", TAB_MASS / 1000, "THRUST", 46.7, "THRUST_NOW", 0, "MU", TAB_G,
                 "BODY_OK", TRUE, "ALT_RADAR", 0, "XNB", TAB_AXIS, "AX", TAB_AX).
}
// tab_step: one cycle at TAB_T; the keys are cleared after, as the core does.
FUNCTION tab_step {
  PARAMETER prog, ks.
  LOCAL out IS p70_step(prog, tab_state(), LEXICON("VALID", FALSE), ks).
  SET ks["PRO"] TO FALSE.
  SET ks["RECYCLE"] TO FALSE.
  SET ks["TERMINATE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  IF out["MSG"] <> "" { SET TAB_MSG TO TAB_MSG + " | " + out["MSG"]. }
  IF out["WARN"] <> "" { SET TAB_MSG TO TAB_MSG + " | " + out["WARN"]. }
  RETURN out.
}
FUNCTION tab_pro {
  PARAMETER prog, ks.
  SET ks["PRO"] TO TRUE.
  RETURN tab_step(prog, ks).
}
FUNCTION tab_enter {
  PARAMETER prog, ks, verb_no, noun_no.
  SET ks["VERB"] TO verb_no.
  SET ks["NOUN"] TO noun_no.
  SET ks["ENTER"] TO TRUE.
  RETURN tab_step(prog, ks).
}
// tab_move: h seconds of flight with the engine along the commanded direction (thrust N, exhaust velocity m/s).
FUNCTION tab_move {
  PARAMETER h, thrust_n, ve_ms.
  IF h <= 0 { RETURN. }
  LOCAL pushed IS asc_sim_push(TAB_RVEC, TAB_VVEC, TAB_MASS, CTL_DIR, h, TAB_MU, thrust_n / ve_ms, ve_ms).
  SET TAB_RVEC TO pushed[0].
  SET TAB_VVEC TO pushed[1].
  SET TAB_MASS TO pushed[2].
  SET TAB_AXIS TO CTL_DIR.
  SET TAB_T TO TAB_T + h.
}
// tab_pass: 2 s on, with a velocity change that makes the servicer measure dv_ms upward.
FUNCTION tab_pass {
  PARAMETER prog, ks, dv_ms.
  SET TAB_T TO TAB_T + 2.
  SET TAB_VVEC TO TAB_VVEC + V(1, 0, 0) * (dv_ms - TAB_G / TAB_RVEC:MAG ^ 2 * 2).
  RETURN tab_step(prog, ks).
}
// tab_guided: the first cycle, then one pass with real thrust measured.
FUNCTION tab_guided {
  PARAMETER prog, ks.
  tab_step(prog, ks).
  RETURN tab_pass(prog, ks, 6.4).
}
// tab_starve: 30 s of cycles with nothing measured (TAB_G set to 0 by the caller).
FUNCTION tab_starve {
  PARAMETER prog, ks.
  LOCAL seen IS FALSE.
  FROM { LOCAL i IS 0. } UNTIL i >= 60 STEP { SET i TO i + 1. } DO {
    SET TAB_T TO TAB_T + 0.5.
    LOCAL out IS tab_step(prog, ks).
    IF out["REQUEST"]:ISTYPE("Lexicon") { IF out["REQUEST"]["VERB"] = 97 AND out["REQUEST"]["NOUN"] = 63 { SET seen TO TRUE. } }
  }
  RETURN seen.
}

// ---- P70: the start ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_abt IS tab_armed(TAB_T - 300).
SET CTL_THR TO 0.1.
SET CTL_DRY_FORE TO TRUE.
LOCAL tab_stages IS CTL_DRY_STAGES.
LOCAL tab_p IS tab_start(70, FALSE, tab_prev(63), tab_abt, "A11", tab_craft(TRUE, tab_csm())).
assert_true("P70 from P63: not refused", tab_p["REFUSED"] = "").
assert_near("P70: full throttle at once", CTL_THR, 1, 0).
assert_near("P70 never stages", CTL_DRY_STAGES, tab_stages, 0).
assert_near("P70: first time to go is the time since ignition", tab_p["G"]["TGO"], 300, 1e-6).
assert_true("P70: vertical rise and rotation flags up", tab_p["RISING"] AND tab_p["ROT"]).
assert_near("P70: the ascent no-thrust threshold", tab_p["DVMON"]["MIN"], ASC_DVMON_ACCEL_MS2, 0).
assert_true("P70: the throttle no longer fires the RCS", NOT CTL_DRY_FORE AND tab_p["RCS_HELD"]).
assert_near("P70: the descent engine estimate", tab_p["G"]["VE"], DPSVEX, 0.001).
assert_true("P70: lit, controls taken, staging ruled out, vehicle whole", tab_p["ENGINE_LIT"] AND tab_p["CONTROLS"] AND tab_p["STAGED_DONE"] AND NOT tab_p["VEHICLE_STAGED"]).
assert_true("P70 keeps the abort armed", tab_abt["ARMED"]).
assert_near("A11 targets: horizontal speed at 300 s", tab_p["TGT"]["ZDOTD"], 1711.1952, 0.01).
assert_near("targets: radial speed", tab_p["TGT"]["RDOTD"], 5.9436, 0.0001).
assert_near("targets: insertion radius", tab_p["TGT"]["RCO"], TAB_SITE_R + ASC_HINJECT_M, 0.01).
assert_near("targets: in the CSM plane", tab_p["TGT"]["YCO"], 0, 1).
assert_true("N76 R1 shows the target", noun_registers(76, LEXICON("VALID", FALSE))[0] = fmt_reg(ms_to_fps(tab_p["TGT"]["ZDOTD"]), 1)).
LOCAL tab_k IS tab_keys().
LOCAL tab_o IS tab_step(tab_p, tab_k).
assert_true("P70 first step: V06 N63", tab_o["SET_VERB"] = 6 AND tab_o["SET_NOUN"] = 63 AND tab_o["PROG_NO"] = 70).
assert_true("P70 first step: says it is the abort", TAB_MSG:CONTAINS("P70")).
assert_true("before guidance the present attitude is held", VANG(CTL_DIR, TAB_AXIS) < 0.01).
p12_end(tab_p).
assert_near("p12_end during the abort: engine off", CTL_THR, 0, 0).
assert_true("p12_end during the abort: the RCS setting is put back", CTL_DRY_FORE).

// ---- the plane 12 nmi out ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_tilt IS ARCSIN(12 * M_PER_NM / (TAB_SITE_R + ASC_HINJECT_M)).
SET TAB_RVEC TO V(COS(tab_tilt), 0, SIN(tab_tilt)) * TAB_RVEC:MAG.
LOCAL tab_px IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "A11", tab_craft(TRUE, tab_csm())).
assert_near("12 nmi out of the plane", ABS(tab_px["Y"]) / M_PER_NM, 12, 0.05).
assert_near("cross-range: 8.2 nmi steered out", ABS(tab_px["Y"]) - ABS(tab_px["TGT"]["YCO"]), ABT_YLIM_M, 2).
assert_true("cross-range: towards the plane, same side", tab_px["TGT"]["YCO"] * tab_px["Y"] > 0).
assert_near("N76 R3 is YCO less Y", lm_store_get_asc(tab_px["VAULT"])["XRANGE"], tab_px["TGT"]["YCO"] - tab_px["Y"], 2).
p12_end(tab_px).

// ---- J: the display noun and the target ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_pj IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "J", tab_craft(TRUE, tab_csm())).
assert_near("J: the CSM 7 degrees behind picks set 1", tab_pj["J_SET"], 1, 0).
assert_near("J: the speed from the CSM's lead", tab_pj["TGT"]["ZDOTD"],
            abt_j_target(TRUE, -7, 1, TAB_SITE_R + ASC_HINJECT_M, TAB_SITE_R, TAB_MU)["ZDOTD"], 0.01).
LOCAL tab_kj IS tab_keys().
SET tab_o TO tab_step(tab_pj, tab_kj).
assert_true("J first step: V06 N94", tab_o["SET_VERB"] = 6 AND tab_o["SET_NOUN"] = 94).
p12_end(tab_pj).

// ---- refusals touch nothing ----
tab_set(10000, 1000, -30, 12000).
SET CTL_THR TO 0.3.
SET tab_stages TO CTL_DRY_STAGES.
LOCAL tab_r1 IS tab_start(70, FALSE, tab_prev(63), abt_new(), "A11", tab_craft(TRUE, FALSE)).
LOCAL tab_r2 IS tab_start(70, FALSE, tab_prev(64), tab_armed(100), "A11", tab_craft(FALSE, FALSE)).
LOCAL tab_cr IS tab_craft(TRUE, FALSE).
SET tab_cr["LANDED"] TO TRUE.
LOCAL tab_r3 IS tab_start(70, TRUE, tab_prev(68), tab_armed(100), "A11", tab_cr).
LOCAL tab_cr4 IS tab_craft(TRUE, FALSE).
SET tab_cr4["DPS"] TO 0.
LOCAL tab_r4 IS tab_start(70, FALSE, tab_prev(63), tab_armed(100), "A11", tab_cr4).
LOCAL tab_r5 IS tab_start(71, FALSE, tab_prev(63), tab_armed(100), "A11", tab_craft(TRUE, FALSE)).
LOCAL tab_cr6 IS tab_craft(TRUE, FALSE).
SET tab_cr6["CORE_STAYS"] TO FALSE.
LOCAL tab_r6 IS tab_start(71, TRUE, tab_prev(63), tab_armed(100), "A11", tab_cr6).
LOCAL tab_r7 IS tab_start(70, TRUE, FALSE, tab_armed(100), "A11", tab_craft(TRUE, FALSE)).
assert_true("refused: disarmed", tab_r1["REFUSED"] <> "").
assert_true("refused: descent stage gone", tab_r2["REFUSED"] <> "").
assert_true("refused: landed", tab_r3["REFUSED"] <> "").
assert_true("refused: no descent engine", tab_r4["REFUSED"]:CONTAINS("engine")).
assert_true("refused: V37 E 71 E while attached", tab_r5["REFUSED"]:CONTAINS("press 0")).
assert_true("refused: the processor would stay on the descent stage", tab_r6["REFUSED"]:CONTAINS("descent stage")).
assert_true("refused: a key with no programme running", tab_r7["REFUSED"] <> "").
assert_near("refusals leave the throttle alone", CTL_THR, 0.3, 0).
assert_near("refusals stage nothing", CTL_DRY_STAGES, tab_stages, 0).
SET CTL_THR TO 0.

// ---- P71 direct, low: vertical rise, windows downrange ----
tab_set(2300, 150, -45, 4900).
LOCAL tab_ab1 IS tab_armed(TAB_T - 500).
SET tab_stages TO CTL_DRY_STAGES.
LOCAL tab_q IS tab_start(71, TRUE, tab_prev(64), tab_ab1, "A11", tab_craft(TRUE, tab_csm())).
assert_true("P71 by the 0 key: not refused", tab_q["REFUSED"] = "").
assert_near("P71 attached: one staging", CTL_DRY_STAGES, tab_stages + 1, 0).
assert_true("P71 disarms the aborts and marks the vehicle staged", NOT tab_ab1["ARMED"] AND tab_q["VEHICLE_STAGED"] AND tab_q["STAGED_DONE"]).
assert_near("direct P71: the ascent engine", tab_q["G"]["VE"], ASC_VE, 0.001).
assert_near("direct P71: first time to go", tab_q["G"]["TGO"], 500, 1e-6).
assert_near("direct P71: its own speed polynomial", tab_q["TGT"]["ZDOTD"], abt_a11_zdotd("APS", 500), 0.001).
assert_near("direct P71: full throttle", CTL_THR, 1, 0).
LOCAL tab_kq IS tab_keys().
tab_guided(tab_q, tab_kq).
assert_true("low abort: rising, thrust straight up", tab_q["GUIDING"] AND tab_q["RISING"] AND VANG(CTL_DIR, V(1, 0, 0)) < 0.01).
assert_true("low abort: the window is commanded downrange", VANG(CTL_UP, V(0, 1, 0)) < 1).
SET TAB_VVEC TO V(15, 150, 0).
SET TAB_T TO TAB_T + 0.5.
tab_step(tab_q, tab_kq).
assert_true("low abort: the rise ends the rotation too", NOT tab_q["RISING"] AND NOT tab_q["ROT"] AND tab_q["RISE_T"] >= 0).
p12_end(tab_q).
tab_set(2300, 150, -45, 4900).
SET tab_stages TO CTL_DRY_STAGES.
LOCAL tab_q2 IS tab_start(71, TRUE, tab_prev(64), tab_armed(TAB_T - 500), "A11", tab_craft(FALSE, tab_csm())).
assert_true("P71 after a staging: not refused", tab_q2["REFUSED"] = "").
assert_near("P71 detached: nothing staged", CTL_DRY_STAGES, tab_stages, 0).
p12_end(tab_q2).

// ---- high abort: over the top through the vertical ----
tab_set(10000, 1000, -30, 12000).
SET TAB_AXIS TO V(COS(100), -SIN(100), 0).
SET P40_DRY_FACING TO LOOKDIRUP(TAB_AXIS, V(1, 0, 0)).
LOCAL tab_ph IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "A11", tab_craft(TRUE, tab_csm())).
LOCAL tab_kh IS tab_keys().
tab_guided(tab_ph, tab_kh).
assert_true("high abort: no vertical rise", NOT tab_ph["RISING"] AND tab_ph["RISE_T"] < 0).
assert_true("high abort pointing back and down: straight up", tab_ph["ROT"] AND VANG(CTL_DIR, V(1, 0, 0)) < 0.01).
SET TAB_AXIS TO V(1, 0, 0).
SET TAB_T TO TAB_T + 0.5.
tab_step(tab_ph, tab_kh).
assert_true("near the vertical: guidance steers", NOT tab_ph["ROT"] AND VANG(CTL_DIR, V(1, 0, 0)) > 5).
assert_true("high abort: windows towards the surface", VDOT(CTL_UP, V(1, 0, 0)) < 0).
p12_end(tab_ph).

// ---- P71 after P70 ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_ab2 IS tab_armed(TAB_T - 300).
SET tab_stages TO CTL_DRY_STAGES.
LOCAL tab_p0 IS tab_start(70, FALSE, tab_prev(63), tab_ab2, "A11", tab_craft(TRUE, tab_csm())).
LOCAL tab_k0 IS tab_keys().
tab_guided(tab_p0, tab_k0).
LOCAL tab_tgo0 IS tab_p0["G"]["TGO"].
SET TAB_T TO TAB_T + 100.
LOCAL tab_p1 IS tab_start(71, TRUE, tab_p0, tab_ab2, "A11", tab_craft(TRUE, tab_csm())).
assert_true("P71 after P70: not refused", tab_p1["REFUSED"] = "").
assert_near("P71 after P70: the targets are kept", tab_p1["TGT"]["ZDOTD"], tab_p0["TGT"]["ZDOTD"], 0.0001).
assert_near("P71 after P70: the rise state is kept", tab_p1["RISE_T"], tab_p0["RISE_T"], 0).
assert_true("P71 after P70: rise and rotation flags kept", tab_p1["RISING"] = tab_p0["RISING"] AND tab_p1["ROT"] = tab_p0["ROT"]).
assert_near("P71 after P70: twice the time to go", tab_p1["G"]["TGO"], 2 * tab_tgo0, 0.001).
assert_near("P71 after P70: the steering terms are kept", tab_p1["G"]["B"], tab_p0["G"]["B"], 1e-9).
assert_near("P71 after P70: the ascent engine", tab_p1["G"]["VE"], ASC_VE, 0.001).
assert_near("P71 after P70: one staging", CTL_DRY_STAGES, tab_stages + 1, 0).
assert_true("P71 after P70: still no throttle to the RCS", tab_p1["RCS_HELD"] AND NOT CTL_DRY_FORE).
p12_end(tab_p1).

// ---- no CSM, and a CSM lost in flight (J) ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_pn IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "J", tab_craft(TRUE, FALSE)).
assert_true("no CSM: the abort starts", tab_pn["REFUSED"] = "" AND NOT tab_pn["HAS_CSM"]).
assert_near("no CSM: the 30 nmi floor", tab_pn["TGT"]["ZDOTD"],
            abt_j_target(FALSE, 0, 1, TAB_SITE_R + ASC_HINJECT_M, TAB_SITE_R, TAB_MU)["ZDOTD"], 0.001).
assert_true("no CSM: the plane saved at ignition", VANG(tab_pn["QAXIS0"], asc_qaxis(V(TAB_CSM_R, 0, 0), V(0, 1000, 0))) < 0.001).
LOCAL tab_kn IS tab_keys().
tab_guided(tab_pn, tab_kn).
assert_true("no CSM: guidance runs", tab_pn["GUIDING"]).
p12_end(tab_pn).
// The raw axes have turned 10 degrees about +X since the ignition: the saved plane (its normal along Z) is carried with them.
LOCAL tab_turned IS LEXICON("P", V(1, 0, 0), "N", V(0, SIN(10), COS(10))).
LOCAL tab_abt_t IS tab_armed(TAB_T - 300).
LOCAL tab_qz IS VDOT(tab_abt_t["QAXIS"], V(0, 0, 1)).
tab_set(10000, 1000, -30, 12000).
LOCAL tab_ct IS tab_craft(TRUE, FALSE).
SET tab_ct["AX"] TO tab_turned.
LOCAL tab_pt IS tab_start(70, FALSE, tab_prev(63), tab_abt_t, "J", tab_ct).
assert_vec("no CSM: the saved plane is carried to the axes of the abort", tab_pt["QAXIS0"], tab_turned["N"] * tab_qz, 1e-9).
assert_vec("and the programme keeps that mark", tab_pt["AX0"]["N"], tab_turned["N"], 1e-9).
p12_end(tab_pt).
tab_set(10000, 1000, -30, 12000).
LOCAL tab_pl IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "J", tab_craft(TRUE, tab_csm())).
LOCAL tab_kl IS tab_keys().
tab_guided(tab_pl, tab_kl).
LOCAL tab_plane IS tab_pl["QAXIS0"].
SET tab_pl["CSM_STATE"] TO FALSE.
LOCAL tab_rp0 IS tab_pl["RP"].
tab_pass(tab_pl, tab_kl, 6.4).
assert_near("CSM lost: the floor from this pass on", tab_pl["TGT"]["ZDOTD"], abt_j_target(FALSE, 0, 1, tab_rp0, TAB_SITE_R, TAB_MU)["ZDOTD"], 0.001).
assert_near("CSM lost: N76 follows", lm_store_get_asc(tab_pl["VAULT"])["ZDOTD"], tab_pl["TGT"]["ZDOTD"], 0.02).
assert_true("CSM lost: the plane is unchanged", VANG(tab_pl["QAXIS0"], tab_plane) < 0.001).
p12_end(tab_pl).

// ---- the whole abort to cut-off, trim and end (A11, from mid P63) ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_ab3 IS tab_armed(TAB_T - 300).
LOCAL tab_pc IS tab_start(70, FALSE, tab_prev(63), tab_ab3, "A11", tab_craft(TRUE, tab_csm())).
LOCAL tab_kc IS tab_keys().
tab_step(tab_pc, tab_kc).
LOCAL tab_ve IS 305 * CONSTANT:G0.
LOCAL tab_t0 IS TAB_T.
UNTIL tab_pc["BB"]["CUT_UT"] >= 0 OR TAB_T > tab_t0 + 500 OR tab_pc["ENDED"] {
  tab_move(2, 46710, tab_ve).
  tab_step(tab_pc, tab_kc).
}
LOCAL tab_cut IS tab_pc["BB"]["CUT_UT"].
assert_true("abort: the cut-off is set", tab_cut >= 0).
tab_move(tab_cut - TAB_T, 46710, tab_ve).
SET TAB_VVEC TO TAB_VVEC + CTL_DIR * (tab_pc["G"]["TAILOFF"] * 46710 / TAB_MASS).          // the tail-off the guidance allows for
p12_cut_check(tab_pc, tab_cut).
assert_true("abort: engine off at the cut time", NOT tab_pc["ENGINE_LIT"] AND CTL_THR = 0).
LOCAL tab_end IS asc_state(TAB_RVEC, TAB_VVEC, tab_pc["QAXIS0"], TAB_MU, TAB_SITE_R + ASC_HINJECT_M).
assert_near("abort insertion: horizontal speed", tab_end["ZDOT"], tab_pc["TGT"]["ZDOTD"], 3).
assert_near("abort insertion: radial speed", tab_end["RDOT"], ABT_RDOTD, 3).
SET TAB_T TO tab_cut + 0.1.
tab_step(tab_pc, tab_kc).
assert_true("cut-off disarms the aborts", NOT tab_ab3["ARMED"]).
SET TAB_T TO tab_cut + 0.35.
SET tab_o TO tab_step(tab_pc, tab_kc).
assert_true("after cut-off: flashing V16 N63", tab_o["SET_VERB"] = 16 AND tab_o["SET_NOUN"] = 63 AND tab_o["REQUEST"]["NOUN"] = 63).
tab_pro(tab_pc, tab_kc).
SET tab_o TO tab_step(tab_pc, tab_kc).
assert_true("PRO: flashing V16 N85", tab_o["SET_VERB"] = 16 AND tab_o["SET_NOUN"] = 85).
SET tab_o TO tab_pro(tab_pc, tab_kc).
assert_true("PRO: the abort programme ends", tab_o["ENDED"]).
p12_end(tab_pc).

// ---- V97 in P70: a relight never stages ----
tab_set(10000, 1000, -30, 12000).
LOCAL tab_ab4 IS tab_armed(TAB_T - 300).
LOCAL tab_pf IS tab_start(70, FALSE, tab_prev(63), tab_ab4, "A11", tab_craft(TRUE, tab_csm())).
LOCAL tab_kf IS tab_keys().
SET tab_stages TO CTL_DRY_STAGES.
SET TAB_G TO 0.
SET tab_kf["TERMINATE"] TO TRUE.
SET tab_o TO tab_step(tab_pf, tab_kf).
assert_true("V34 with no request does nothing", NOT tab_o["ENDED"]).
assert_true("no thrust in P70: V97 N63", tab_starve(tab_pf, tab_kf)).
tab_enter(tab_pf, tab_kf, 97, 63).
assert_true("V97 ENTR: engine off, still in P70", NOT tab_pf["ENGINE_LIT"] AND NOT tab_pf["ENDED"]).
SET TAB_T TO TAB_T + 0.5.
SET tab_o TO tab_step(tab_pf, tab_kf).
assert_true("V97 ENTR: flashing V99 N63", tab_o["REQUEST"]["VERB"] = 99 AND tab_o["REQUEST"]["NOUN"] = 63).
tab_pro(tab_pf, tab_kf).
SET TAB_T TO tab_pf["TIG"].
tab_step(tab_pf, tab_kf).
assert_true("relight: lit again at full throttle", tab_pf["ENGINE_LIT"] AND CTL_THR = 1).
assert_near("relight in P70: nothing staged", CTL_DRY_STAGES, tab_stages, 0).
assert_true("relight: still armed", tab_ab4["ARMED"]).
tab_starve(tab_pf, tab_kf).
tab_enter(tab_pf, tab_kf, 97, 63).
SET TAB_T TO TAB_T + 0.5.
tab_step(tab_pf, tab_kf).
tab_enter(tab_pf, tab_kf, 99, 63).
assert_true("ENTR at the relight prompt: to the cut-off displays", tab_pf["PHASE"] = "POST" AND NOT tab_pf["ENDED"]).
assert_true("ENTR at the relight prompt disarms", NOT tab_ab4["ARMED"]).
p12_end(tab_pf).
tab_set(10000, 1000, -30, 12000).
LOCAL tab_pv IS tab_start(70, FALSE, tab_prev(63), tab_armed(TAB_T - 300), "A11", tab_craft(TRUE, tab_csm())).
LOCAL tab_kv IS tab_keys().
SET TAB_G TO 0.
tab_starve(tab_pv, tab_kv).
SET tab_kv["TERMINATE"] TO TRUE.
SET tab_o TO tab_step(tab_pv, tab_kv).
assert_true("V34 on V97 ends the abort programme", tab_o["ENDED"]).
p12_end(tab_pv).

// ---- the vehicle's wiring (lm_vehicle.ks) -----------------------------------------------------------------------------------
// The vehicle loads the store a DSKY run saved; the test points it at a file that is not there.
LOCAL tab_real_store IS LM_STORE_FILE.
SET LM_STORE_FILE TO "0:/lm/logs/test_abort_no_store.txt".
IF EXISTS(LM_STORE_FILE) { DELETEPATH(LM_STORE_FILE). }
SET CTL_DRY_ABORT TO FALSE.
SET CTL_DRY_AG10 TO FALSE.
SET CTL_DRY_ATTACHED TO TRUE.
LOCAL tab_veh IS lm_vehicle_new().
SET LM_STORE_FILE TO tab_real_store.
assert_true("vehicle: not armed at the start", NOT LM_VEH["ABT"]["ARMED"]).
assert_true("vehicle: the DSKY core can ask it for a programme", tab_veh:HASKEY("REQUEST_SOURCE")).
assert_true("vehicle: nothing asked with the keys untouched", lm_abort_source(tab_prev(63), 90) = -1).

// arming from the descent programme's ignition time.
LOCAL tab_nav IS LEXICON("R", V(TAB_SITE_R + 15000, 0, 0), "V", V(0, 1690, 0), "T", 100, "AX", TAB_AX).
lm_abort_arm(LEXICON("SEQ", LEXICON("IGN_T", -1)), tab_nav).
assert_true("vehicle: no ignition, no arming", NOT LM_VEH["ABT"]["ARMED"]).
lm_abort_arm(LEXICON("SEQ", LEXICON("IGN_T", 100)), tab_nav).
assert_true("vehicle: armed at P63 ignition", LM_VEH["ABT"]["ARMED"] AND LM_VEH["ABT"]["T0"] = 100).
assert_true("vehicle: the ship's own plane saved at ignition", VANG(LM_VEH["ABT"]["QAXIS"], asc_qaxis(tab_nav["R"], tab_nav["V"])) < 0.001).
assert_true("vehicle: with the axes it was saved in", (LM_VEH["ABT"]["PLANE_AX"]["N"] - TAB_AX["N"]):MAG < 1e-9).
SET tab_nav["T"] TO 400.
lm_abort_arm(LEXICON("SEQ", LEXICON("IGN_T", 400)), tab_nav).
assert_near("vehicle: a V97 re-ignition restarts the abort clock", LM_VEH["ABT"]["T0"], 400, 0).
assert_near("vehicle: and keeps the plane's time", LM_VEH["ABT"]["PLANE_T"], 100, 0).

SET CTL_DRY_ABORT TO TRUE.
assert_true("vehicle: Backspace in P63 asks for P70", lm_abort_source(tab_prev(63), 401) = 70).
assert_true("vehicle: once", lm_abort_source(tab_prev(63), 401.2) = -1).
assert_true("vehicle: remembered as a control, not V37", LM_VEH["ABT_KEY"]).
SET LM_VEH["ABT_KEY"] TO FALSE.
SET CTL_DRY_AG10 TO TRUE.
SET CTL_DRY_ATTACHED TO FALSE.
assert_true("vehicle: the 0 key and the staging together ask for P71", lm_abort_source(tab_prev(63), 402) = 71).
assert_true("vehicle: only once", lm_abort_source(tab_prev(63), 402.2) = -1).
SET LM_VEH["ABT_KEY"] TO FALSE.
SET CTL_DRY_ATTACHED TO TRUE.
SET CTL_DRY_ABORT TO FALSE.
lm_abort_sample(LEXICON("ENGINE_LIT", FALSE)).          // the sample hook latches a press shorter than a cycle
assert_true("vehicle: the sample hook latched the press", LM_VEH["ABT_KEYS"]["ABORT"]).
assert_true("vehicle: a press seen by the sample hook is not lost", lm_abort_source(tab_prev(63), 403) = 70).
SET LM_VEH["ABT_KEY"] TO FALSE.

// the end of the abort window. The hook is given no site, so it stops after the disarming.
SET LM_VEH["SITE"] TO LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0).
lm_veh_hook(tab_prev(68), LEXICON()).
assert_true("vehicle: P68 keeps the aborts armed", LM_VEH["ABT"]["ARMED"]).
lm_p68_end(LEXICON()).
assert_true("vehicle: P68's END leaves the disarming to the cycle's hook", LM_VEH["ABT"]["ARMED"]).
lm_veh_hook(FALSE, LEXICON()).
assert_true("vehicle: no programme disarms", NOT LM_VEH["ABT"]["ARMED"]).
SET CTL_DRY_ABORT TO TRUE.
assert_true("vehicle: disarmed, Backspace asks for nothing", lm_abort_source(tab_prev(63), 404) = -1).
SET CTL_DRY_ABORT TO FALSE.
assert_true("no CSM: no state", lm_abort_csm_state(FALSE):ISTYPE("Boolean")).

// V37 E 70 E reaches the core, and a refused take-over leaves the running programme.
LOCAL tab_vks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
FOR tab_char IN LIST("V", "3", "7", "E", "7", "0", "E") { key_press(tab_vks, tab_char). }
assert_true("V37 E 70 E asks for programme 70", tab_vks["PROG_REQ"] = 70).
LOCAL tab_run IS core_new(tab_veh).
SET tab_run["PROG"] TO tab_prev(12).
SET tab_run["ENTRY"] TO tab_veh["PROGRAMMES"]["12"].
core_request(tab_run, tab_veh, tab_vks, 70).
assert_true("V37 E 70 E while disarmed: OPR ERR", tab_vks["OPRERR"]).
assert_true("V37 E 70 E while disarmed: the running programme stays", tab_run["PROG"]["PROG_NO"] = 12).

SET P40_DRY_FACING TO tab_keep_facing.
test_end().
