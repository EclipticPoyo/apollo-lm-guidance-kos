// test_p12.ks -- pad test for P12, the ascent (lm/ascent/lm_p12.ks, release 1.5), and the ascent control layer (lm_control.ks) in dry mode.
// No flight: CTL_DRY is TRUE, the ship's state is made up. The landed site is on +X, the CSM 60 nmi over it; "downrange" is the CSM's direction of
// motion. On the pad the window face is fixed along +Y (ctl_window_face_vec), so with downrange +Y the yaw is already right and with downrange +Z it
// is 90 degrees off. In the full flight the state is moved by the commanded direction (asc_sim_push); the expected end comes from the same loop run on
// scripts/tests/reference_ascent.py (burn about 434 s; within 10 m and 0.6 m/s of the targets). The ship reads and writes themselves (the decoupler,
// the separation, the steering) can only be checked in flight.
//   RUNPATH("0:/tests/test_p12.ks").   Log: 0:/lm/logs/test_p12.log.
// Written for release 1.5 and not yet run in KSP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").
RUNONCEPATH("0:/lm/ascent/lm_p12.ks").

test_begin("0:/lm/logs/test_p12.log").
SET CTL_DRY TO TRUE.
LOCAL t12_keep_facing IS P40_DRY_FACING.

GLOBAL T12_RAD IS 1737400.                 // the landing-site radius, m
GLOBAL T12_MU IS 4.9028e12.
GLOBAL T12_CLOCK IS 1000.                  // UT of the AGC clock's zero
GLOBAL T12_TIG IS 3000.                    // UT of lift-off unless a test changes it
GLOBAL T12_UR IS V(1, 0, 0).
GLOBAL T12_Y IS V(0, 1, 0).
GLOBAL T12_Z IS V(0, 0, 1).
GLOBAL T12_T IS 2000.
GLOBAL T12_R IS V(1737400, 0, 0).
GLOBAL T12_V IS V(0, 0, 0).
GLOBAL T12_G IS 4.9028e12.                 // the mu in the state (0 in the engine-failure test: no gravity, no ground reaction)
GLOBAL T12_MASS IS 4915.
GLOBAL T12_MSG IS "".                      // every message since the last t12_start, joined

// t12_vault: a store with RLS on +X and TIG at UT tig_ut (no TIG when tig_ut is 0).
FUNCTION t12_vault {
  PARAMETER tig_ut.
  LOCAL vault IS store_new(lm_cells_for("A11")).
  lm_store_put_rls(vault, V(T12_RAD, 0, 0)).
  IF tig_ut > 0 { lm_store_put_tig(vault, tig_ut - T12_CLOCK). }
  RETURN vault.
}
FUNCTION t12_craft {
  PARAMETER downrange, plan.
  RETURN LEXICON("STATUS", "LANDED", "ENGINE", "APS", "CORE_STAYS", TRUE,
                 "CSM", LEXICON("NAME", "CSM", "R", V(1848520, 0, 0), "V", downrange * 1628.58), "PLAN", plan).
}
// t12_start: a fresh programme and a fresh made-up state, landed, at UT 2000.
FUNCTION t12_start {
  PARAMETER profile, downrange, plan, vault.
  SET T12_T TO 2000.
  SET T12_R TO V(T12_RAD, 0, 0).
  SET T12_V TO V(0, 0, 0).
  SET T12_G TO T12_MU.
  SET T12_MASS TO 4915.
  SET T12_MSG TO "".
  RETURN p12_start(FALSE, vault, T12_CLOCK, profile, 2000, t12_craft(downrange, plan), V(0, 0, 0)).
}
FUNCTION t12_keys {
  LOCAL ks IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
  SET ks["VERB"] TO 16.
  SET ks["NOUN"] TO 60.
  RETURN ks.
}
FUNCTION t12_state {
  RETURN LEXICON("R", T12_R, "V", T12_V, "T", T12_T, "MASS", T12_MASS / 1000, "THRUST", 15.57, "THRUST_NOW", 0, "MU", T12_G,
                 "BODY_OK", TRUE, "ALT_RADAR", 0, "XNB", V(1, 0, 0)).
}
// t12_step: one cycle at T12_T; the keys are cleared after, as the core does.
FUNCTION t12_step {
  PARAMETER prog, ks.
  LOCAL out IS p12_step(prog, t12_state(), LEXICON("VALID", FALSE), ks).
  SET ks["PRO"] TO FALSE.
  SET ks["RECYCLE"] TO FALSE.
  SET ks["TERMINATE"] TO FALSE.
  SET ks["ENTER"] TO FALSE.
  IF out["MSG"] <> "" { SET T12_MSG TO T12_MSG + " | " + out["MSG"]. }
  RETURN out.
}
FUNCTION t12_pro {
  PARAMETER prog, ks.
  SET ks["PRO"] TO TRUE.
  RETURN t12_step(prog, ks).
}
FUNCTION t12_enter {
  PARAMETER prog, ks, verb_no, noun_no.
  SET ks["VERB"] TO verb_no.
  SET ks["NOUN"] TO noun_no.
  SET ks["ENTER"] TO TRUE.
  RETURN t12_step(prog, ks).
}
// t12_to_burn: the two loads accepted and into the BURNBABY phase; returns the first output of that phase.
FUNCTION t12_to_burn {
  PARAMETER prog, ks.
  t12_step(prog, ks).                   // CHECK
  t12_step(prog, ks).                   // N33 shown
  t12_pro(prog, ks).                    // N33 accepted
  t12_step(prog, ks).                   // N76 shown
  t12_pro(prog, ks).                    // N76 accepted
  t12_step(prog, ks).                   // the SAS check, TIG check, the sequence made
  RETURN t12_step(prog, ks).            // the countdown display
}
// t12_light: PRO at the prompt, then the cycle at TIG that lights the engine; returns that output.
FUNCTION t12_light {
  PARAMETER prog, ks.
  SET T12_T TO prog["TIG"] - 5.
  t12_step(prog, ks).
  SET T12_T TO prog["TIG"] - 4.
  t12_pro(prog, ks).
  SET T12_T TO prog["TIG"].
  RETURN t12_step(prog, ks).
}
// t12_pass: 2 s on, with a velocity change that makes the servicer measure dv_ms upward.
FUNCTION t12_pass {
  PARAMETER prog, ks, dv_ms.
  SET T12_T TO T12_T + 2.
  SET T12_V TO T12_V + T12_UR * (dv_ms - T12_G / T12_R:MAG ^ 2 * 2).
  RETURN t12_step(prog, ks).
}
// t12_near_insertion: the state put just short of the insertion targets; the servicer starts a new pass so the jump is not measured as thrust.
FUNCTION t12_near_insertion {
  PARAMETER prog, ks, downrange.
  SET T12_R TO T12_UR * (T12_RAD + ASC_HINJECT_M).
  SET T12_V TO downrange * 1671.3 + T12_UR * 5.9.
  SET prog["PASS_T0"] TO -1.
  SET T12_T TO T12_T + 0.5.
  RETURN t12_step(prog, ks).
}
// t12_move: h seconds of flight with the engine along the commanded direction.
FUNCTION t12_move {
  PARAMETER h.
  IF h <= 0 { RETURN. }
  LOCAL ve_ms IS 311 * CONSTANT:G0.
  LOCAL pushed IS asc_sim_push(T12_R, T12_V, T12_MASS, CTL_DIR, h, T12_MU, 15570 / ve_ms, ve_ms).
  SET T12_R TO pushed[0].
  SET T12_V TO pushed[1].
  SET T12_MASS TO pushed[2].
  SET T12_T TO T12_T + h.
}

// ---- staging and ascent start in the control layer, dry ----
LOCAL t12_stages IS CTL_DRY_STAGES.
assert_true("dry staging: no reason", ctl_stage_ascent(0) = "").
assert_near("dry staging: counted once", CTL_DRY_STAGES, t12_stages + 1, 0).
SET CTL_THR TO 0.3.
SET CTL_THR_LOCKED TO FALSE.
SET CTL_DIR TO V(1, 0, 0).
ctl_ascent_start(TRUE).
assert_near("dry ascent start: throttle command untouched", CTL_THR, 0.3, 0).
assert_true("dry ascent start: nothing locked", NOT CTL_THR_LOCKED).
assert_true("dry ascent start: attitude command untouched", VANG(CTL_DIR, V(1, 0, 0)) < 0.001).
SET CTL_THR TO 0.
SET CTL_DIR TO V(0, 0, 1).

// ---- refusals ----
LOCAL t12_csm IS t12_craft(T12_Y, FALSE)["CSM"].
assert_true("refusals: all good", p12_refusal("LANDED", TRUE, t12_csm, TRUE, TRUE) = "").
assert_true("refusals: not landed", p12_refusal("ORBITING", TRUE, t12_csm, TRUE, TRUE):CONTAINS("not LANDED")).
assert_true("refusals: no landing site", p12_refusal("LANDED", FALSE, t12_csm, TRUE, TRUE):CONTAINS("RLS")).
assert_true("refusals: no CSM", p12_refusal("LANDED", TRUE, FALSE, TRUE, TRUE):CONTAINS("CSM")).
assert_true("refusals: no ascent engine", p12_refusal("LANDED", TRUE, t12_csm, FALSE, TRUE):CONTAINS("ascent engine")).
assert_true("refusals: the processor on the descent stage", p12_refusal("LANDED", TRUE, t12_csm, TRUE, FALSE):CONTAINS("descent stage")).
LOCAL t12_bad IS t12_craft(T12_Y, FALSE).
SET t12_bad["ENGINE"] TO 0.                  // what ctl_find_ascent_engine returns when there is none
assert_true("refusals: p12_start refuses with the reason", p12_start(FALSE, t12_vault(T12_TIG), T12_CLOCK, "A11", 2000, t12_bad, V(0, 0, 0))["REFUSED"]:CONTAINS("ascent engine")).

// ---- the programme table ----
LOCAL t12_entry IS lm_programme_table()["12"].
assert_true("table: V37 can select P12, no handover", t12_entry["SELECTABLE"] AND t12_entry["NEXT"] = -1 AND LM_PROGS:CONTAINS(12)).

// ---- the landing site the nouns are worked out from ----
// Seen in flight: V37 E 12 E keyed straight from P68 left N94 blank, because the vehicle only re-read RLS while no programme ran.
SET LM_VEH["STORE"] TO t12_vault(T12_TIG).
SET LM_VEH["SITE"] TO LEXICON("OK", FALSE, "LAT", 0, "LNG", 0, "ALT", 0).
SET LM_VEH["SITE_SIG"] TO -1.
SET LM_VEH["WM"] TO V(0, 0, 0).
SET LM_VEH["PROFILE"] TO "A11".
LOCAL t12_was_dry IS CTL_DRY.
LOCAL t12_was_status IS CTL_DRY_STATUS.
SET CTL_DRY TO TRUE.
SET CTL_DRY_STATUS TO "FLYING".
lm_p12_start(FALSE).                       // whether or not this ship could start P12
assert_true("start: P12 takes the landing site from RLS", LM_VEH["SITE"]["OK"]).
assert_near("start: in flight RLS is left as it was", lm_store_get_rls(LM_VEH["STORE"]):MAG, T12_RAD, 2).
SET CTL_DRY_STATUS TO "LANDED".
SET LM_VEH["STORE"] TO store_new(lm_cells_for("A11")).
lm_p12_start(FALSE).
assert_near("start: landed, RLS is stored from where the ship stands", lm_store_get_rls(LM_VEH["STORE"]):MAG, SHIP:BODY:RADIUS + SHIP:ALTITUDE, 2).
SET CTL_DRY TO t12_was_dry.
SET CTL_DRY_STATUS TO t12_was_status.

// ---- p12spot ----
assert_true("p12spot: 31 s ahead stays", NOT p12spot(1031, 1000)["SLIPPED"] AND p12spot(1031, 1000)["TIG"] = 1031 AND p12spot(1031, 1000)["ALARM"] = 0).
LOCAL t12_spot IS p12spot(1029, 1000).
assert_true("p12spot: 29 s ahead slips with 1703", t12_spot["SLIPPED"] AND t12_spot["ALARM"] = 1703).
assert_near("p12spot: to 29.9 s from now", t12_spot["TIG"], 1029.9, 1e-6).

// ---- display flow: N33, N76, N74 ----
LOCAL t12_va IS t12_vault(T12_TIG).
SET LM_VEH["STORE"] TO t12_va.
LOCAL t12_p IS t12_start("A11", T12_Y, FALSE, t12_va).
LOCAL t12_k IS t12_keys().
assert_true("flow: a good start is not refused", t12_p["REFUSED"] = "").
LOCAL t12_o IS t12_step(t12_p, t12_k).
assert_true("flow: the first cycle checks the IMU only", t12_p["PHASE"] = "N33" AND t12_o["SET_VERB"] < 0 AND t12_o["PROG_NO"] = 12).
SET t12_o TO t12_step(t12_p, t12_k).
assert_true("flow: flashing V06 N33", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 33 AND t12_o["REQUEST"]["VERB"] = 6 AND t12_o["REQUEST"]["NOUN"] = 33).
SET t12_o TO t12_enter(t12_p, t12_k, 16, 33).
assert_true("flow: ENTR on V16 N33 (after a load) shows V06 N33 again", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 33 AND t12_p["PHASE"] = "N33").
t12_pro(t12_p, t12_k).
SET t12_o TO t12_step(t12_p, t12_k).
assert_true("flow: PRO goes on to a flashing V06 N76", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 76 AND t12_o["REQUEST"]["NOUN"] = 76).
LOCAL t12_regs IS noun_registers(76, LEXICON("VALID", FALSE)).
assert_true("flow: N76 horizontal speed 5509.5 ft/s", t12_regs[0] = "+55095").
assert_true("flow: N76 radial speed 19.5 ft/s", t12_regs[1] = "+00195").
assert_near("flow: N76 cross-range is zero for a site in the CSM plane", lm_store_get_asc(t12_va)["XRANGE"], 0, 1).
t12_pro(t12_p, t12_k).
SET t12_o TO t12_step(t12_p, t12_k).
assert_true("flow: SAS off, no V50 N25: into the sequence", t12_p["PHASE"] = "BURN" AND NOT t12_o["REQUEST"]:ISTYPE("Lexicon")).
SET t12_o TO t12_step(t12_p, t12_k).
assert_true("flow: the countdown shows V06 N74", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 74).
LOCAL t12_yaw IS t12_o["EXTRA"]["P12_YAW"].
assert_true("flow: N74 yaw about 0 for a CSM in plane", t12_yaw < 1 OR t12_yaw > 359).
assert_near("flow: N74 pitch about 310", t12_o["EXTRA"]["P12_PITCH"], 310, 6).
assert_near("flow: N74 time counts to TIG", t12_o["EXTRA"]["TTOGO"], T12_TIG - 2000, 1e-6).
assert_near("flow: no controls taken before ignition", CTL_THR, 0, 0).

// ---- TIG not loaded at N33 ----
LOCAL t12_pn IS t12_start("A11", T12_Y, FALSE, t12_vault(0)).
LOCAL t12_kn IS t12_keys().
t12_step(t12_pn, t12_kn).
t12_step(t12_pn, t12_kn).
SET t12_o TO t12_pro(t12_pn, t12_kn).
assert_true("no TIG: PRO lights OPR ERR and N33 stays", t12_kn["OPRERR"] AND t12_pn["PHASE"] = "N33" AND t12_o["REQUEST"]["NOUN"] = 33).

// ---- IMU and V34 ----
LOCAL t12_pi IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_pi["IMU_OK"] TO FALSE.
SET t12_o TO t12_step(t12_pi, t12_keys()).
assert_true("R02: alarm 220 ends P12", t12_o["ALARM"] = 220 AND t12_o["ENDED"]).
LOCAL t12_pv IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kv IS t12_keys().
t12_step(t12_pv, t12_kv).
t12_step(t12_pv, t12_kv).
SET t12_kv["TERMINATE"] TO TRUE.
SET t12_o TO t12_step(t12_pv, t12_kv).
assert_true("V34 at N33 ends P12", t12_o["ENDED"]).

// ---- SAS on before ignition: the V50 N25 request ----
LOCAL t12_ps IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_ks IS t12_keys().
SET t12_ps["ATT"]["MODE"] TO "HOLD".
t12_step(t12_ps, t12_ks).
t12_step(t12_ps, t12_ks).
t12_pro(t12_ps, t12_ks).
t12_step(t12_ps, t12_ks).
t12_pro(t12_ps, t12_ks).
SET t12_o TO t12_step(t12_ps, t12_ks).
assert_true("SAS on: flashing V50 N25", t12_o["SET_VERB"] = 50 AND t12_o["SET_NOUN"] = 25 AND t12_o["REQUEST"]["NOUN"] = 25).
assert_true("SAS on: N25 shows 00203", noun_registers(25, LEXICON("VALID", FALSE, "N25", t12_o["EXTRA"]["N25"]))[0] = " 00203").
t12_pro(t12_ps, t12_ks).
t12_step(t12_ps, t12_ks).
assert_true("SAS on: PRO checks again and the request stays", t12_ps["PHASE"] = "AUTO").
t12_enter(t12_ps, t12_ks, 50, 25).
assert_true("SAS on: ENTR continues", t12_ps["PHASE"] = "BURN").

// ---- skip plan: TIG and N76 from the ascent plan ----
LOCAL t12_plan IS LEXICON("CSM", "CSM", "T_TIG", 5000, "ZDOTD", 1687, "RDOTD", 9.8, "XRANGE", -1852, "SKIP", TRUE).
LOCAL t12_vk IS t12_vault(T12_TIG).
LOCAL t12_pk IS t12_start("A11", T12_Y, t12_plan, t12_vk).
assert_near("skip plan: TIG loaded from the plan before N33", lm_store_get_tig(t12_vk), 5000 - T12_CLOCK, 0.01).
LOCAL t12_kk IS t12_keys().
t12_step(t12_pk, t12_kk).
t12_step(t12_pk, t12_kk).
t12_pro(t12_pk, t12_kk).
LOCAL t12_asc IS lm_store_get_asc(t12_vk).
assert_near("skip plan: horizontal speed", t12_asc["ZDOTD"], 1687, 0.01).
assert_near("skip plan: radial speed", t12_asc["RDOTD"], 9.8, 0.01).
assert_near("skip plan: cross-range", t12_asc["XRANGE"], -1852, 2).
LOCAL t12_noskip IS t12_plan:COPY.
SET t12_noskip["SKIP"] TO FALSE.
LOCAL t12_vn IS t12_vault(T12_TIG).
t12_start("A11", T12_Y, t12_noskip, t12_vn).
assert_near("no skip: TIG is left as loaded", lm_store_get_tig(t12_vn), T12_TIG - T12_CLOCK, 0.01).

// ---- cross-range over 8 nm ----
LOCAL t12_tilt IS ARCSIN(12 * M_PER_NM / (T12_RAD + ASC_HINJECT_M)).
LOCAL t12_vx IS t12_vault(T12_TIG).
SET LM_VEH["STORE"] TO t12_vx.
LOCAL t12_px IS t12_start("A11", T12_Y, FALSE, t12_vx).
SET T12_R TO V(T12_RAD * COS(t12_tilt), 0, T12_RAD * SIN(t12_tilt)).
LOCAL t12_kx IS t12_keys().
t12_step(t12_px, t12_kx).
t12_step(t12_px, t12_kx).
t12_pro(t12_px, t12_kx).
assert_near("cross-range: the site is 12 nm from the CSM plane", ABS(t12_px["Y"]) / M_PER_NM, 12, 0.05).
assert_true("cross-range: a message", T12_MSG:CONTAINS("CROSS-RANGE")).
assert_near("cross-range: XRANGE is still -Y", lm_store_get_asc(t12_vx)["XRANGE"], -t12_px["Y"], 2).
assert_true("cross-range: N76 R3 shows it in nm", noun_registers(76, LEXICON("VALID", FALSE))[2] = fmt_reg(-t12_px["Y"] / M_PER_NM, 1)).
SET T12_R TO V(T12_RAD * COS(t12_tilt), 0, T12_RAD * SIN(t12_tilt)).
t12_step(t12_px, t12_kx).
t12_pro(t12_px, t12_kx).
assert_near("cross-range: the target position YCO is XRANGE + Y", t12_px["TGT"]["YCO"], 0, 2).

// ---- an old TIG slips ----
LOCAL t12_po IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_ko IS t12_keys().
SET T12_T TO T12_TIG + 5000.
t12_step(t12_po, t12_ko).
t12_step(t12_po, t12_ko).
t12_pro(t12_po, t12_ko).
t12_step(t12_po, t12_ko).
t12_pro(t12_po, t12_ko).
SET t12_o TO t12_step(t12_po, t12_ko).
assert_true("old TIG: alarm 1703", t12_o["ALARM"] = 1703).
assert_near("old TIG: slipped to now + 29.9", t12_po["TIG"], T12_T + 29.9, 1e-6).
assert_true("old TIG: the message says the rendezvous timing is lost", t12_o["MSG"]:CONTAINS("rendezvous")).

// ---- the prompt ----
LOCAL t12_pq IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kq IS t12_keys().
t12_to_burn(t12_pq, t12_kq).
SET T12_T TO T12_TIG - 34.
assert_true("prompt: blank at TIG-34", t12_step(t12_pq, t12_kq)["BLANK"]).
SET T12_T TO T12_TIG - 29.
SET t12_o TO t12_step(t12_pq, t12_kq).
assert_true("prompt: V06 N74 back at TIG-29", NOT t12_o["BLANK"] AND t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 74).
SET T12_T TO T12_TIG - 5.
SET t12_o TO t12_step(t12_pq, t12_kq).
assert_true("prompt: flashing V99 N74 at TIG-5", t12_o["SET_VERB"] = 99 AND t12_o["REQUEST"]["VERB"] = 99 AND t12_o["REQUEST"]["NOUN"] = 74).
SET CTL_THR TO 0.3.
SET t12_stages TO CTL_DRY_STAGES.
t12_enter(t12_pq, t12_kq, 99, 74).
assert_true("prompt ENTR: to the post-burn display", t12_pq["PHASE"] = "POST" AND NOT t12_pq["ENDED"]).
SET T12_T TO T12_TIG + 1.
SET t12_o TO t12_step(t12_pq, t12_kq).
assert_true("prompt ENTR: flashing V16 N63", t12_o["SET_VERB"] = 16 AND t12_o["SET_NOUN"] = 63 AND t12_o["REQUEST"]["VERB"] = 16).
assert_near("prompt ENTR: nothing staged", CTL_DRY_STAGES, t12_stages, 0).
p12_end(t12_pq).
assert_near("prompt ENTR: no controls taken, p12_end touches nothing", CTL_THR, 0.3, 0).
SET CTL_THR TO 0.
SET t12_pq TO t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_kq TO t12_keys().
t12_to_burn(t12_pq, t12_kq).
SET T12_T TO T12_TIG - 5.
t12_step(t12_pq, t12_kq).
SET t12_kq["TERMINATE"] TO TRUE.
SET t12_o TO t12_step(t12_pq, t12_kq).
assert_true("prompt V34: ended", t12_o["ENDED"]).
assert_near("prompt V34: nothing staged", CTL_DRY_STAGES, t12_stages, 0).
SET t12_pq TO t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_kq TO t12_keys().
t12_to_burn(t12_pq, t12_kq).
SET T12_T TO T12_TIG - 4.
t12_step(t12_pq, t12_kq).
t12_pro(t12_pq, t12_kq).
SET T12_T TO T12_TIG - 0.5.
t12_step(t12_pq, t12_kq).
assert_true("prompt PRO: not lit before TIG", NOT t12_pq["ENGINE_LIT"] AND CTL_DRY_STAGES = t12_stages).
SET T12_T TO T12_TIG.
SET t12_o TO t12_step(t12_pq, t12_kq).
assert_true("prompt PRO: lit at TIG", t12_pq["ENGINE_LIT"] AND t12_pq["STAGED_DONE"]).
assert_true("A11: V06 N63 from ignition", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 63).
SET T12_T TO T12_TIG + 1.
t12_step(t12_pq, t12_kq).
assert_near("prompt PRO: staged once", CTL_DRY_STAGES, t12_stages + 1, 0).
assert_near("lit: the throttle command is full", CTL_THR, 1, 0).
assert_true("lit: the throttle no longer fires the RCS", NOT CTL_DRY_FORE AND t12_pq["RCS_HELD"]).
// end during the burn: what V37 does.
p12_end(t12_pq).
assert_near("end during the burn: the engine is off (throttle 0)", CTL_THR, 0, 0).
assert_true("end during the burn: the RCS setting is put back", CTL_DRY_FORE AND NOT t12_pq["RCS_HELD"]).
SET t12_pq TO t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_kq TO t12_keys().
t12_to_burn(t12_pq, t12_kq).
SET T12_T TO T12_TIG + 3.
t12_step(t12_pq, t12_kq).
t12_pro(t12_pq, t12_kq).
assert_true("PRO after TIG lights at once", t12_pq["ENGINE_LIT"] AND t12_pq["IGN_T"] = T12_TIG + 3).
p12_end(t12_pq).

// ---- no guidance on a weak pass ----
SET P40_DRY_FACING TO LOOKDIRUP(V(COS(10), 0, SIN(10)), T12_Y).
LOCAL t12_pg IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kg IS t12_keys().
t12_to_burn(t12_pg, t12_kg).
t12_light(t12_pg, t12_kg).
assert_true("ignition: the present attitude is commanded", VANG(CTL_DIR, P40_DRY_FACING:FOREVECTOR) < 0.01).
SET T12_T TO T12_T + 2.
t12_step(t12_pg, t12_kg).
assert_true("weak pass (ground reaction only): no guidance", NOT t12_pg["GUIDING"]).
assert_true("weak pass: the commanded direction stays", VANG(CTL_DIR, P40_DRY_FACING:FOREVECTOR) < 0.01).
t12_pass(t12_pg, t12_kg, 6.4).
assert_true("a 6.4 m/s pass starts guidance", t12_pg["GUIDING"]).
assert_true("rise: thrust straight up", VANG(CTL_DIR, T12_UR) < 0.01).
SET P40_DRY_FACING TO t12_keep_facing.
p12_end(t12_pg).

// ---- rise, then pitch over ----
LOCAL t12_pa IS t12_start("A11", T12_Z, FALSE, t12_vault(T12_TIG)).
LOCAL t12_ka IS t12_keys().
t12_to_burn(t12_pa, t12_ka).
t12_light(t12_pa, t12_ka).
t12_pass(t12_pa, t12_ka, 6.4).
SET T12_V TO T12_UR * 15.
SET T12_T TO T12_T + 0.5.
t12_step(t12_pa, t12_ka).
assert_true("A11 with the yaw 90 degrees off: still rising at 15 m/s up", t12_pa["RISING"] AND VANG(CTL_DIR, T12_UR) < 0.01).
assert_true("rise: the window is commanded downrange", VANG(CTL_UP, T12_Z) < 1).
p12_end(t12_pa).
LOCAL t12_pj IS t12_start("J", T12_Z, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kj IS t12_keys().
t12_to_burn(t12_pj, t12_kj).
SET t12_o TO t12_light(t12_pj, t12_kj).
assert_true("J: V06 N94 from ignition", t12_o["SET_VERB"] = 6 AND t12_o["SET_NOUN"] = 94).
t12_pass(t12_pj, t12_kj, 6.4).
SET T12_V TO T12_UR * 15.
SET T12_T TO T12_T + 0.5.
SET t12_o TO t12_step(t12_pj, t12_kj).
assert_true("J does not wait for the yaw", NOT t12_pj["RISING"] AND VANG(CTL_DIR, T12_UR) > 5).
LOCAL t12_rise IS t12_pj["RISE_T"].
assert_true("N94 has the body-axis VG", t12_o["EXTRA"]["P40_VGB"]:LENGTH = 3 AND t12_o["EXTRA"]["P40_VGB"][0] <> 0).
SET T12_T TO t12_rise + 5.
t12_step(t12_pj, t12_kj).
assert_true("5 s after the rise the windows face down", VDOT(CTL_UP, T12_UR) < -0.2 AND ABS(VDOT(CTL_UP, T12_Y)) < 0.1).
SET T12_T TO t12_rise + 11.
t12_step(t12_pj, t12_kj).
// The pad's window face stays on +Y: a command that followed the ship would turn to it.
assert_true("11 s after the rise with the stick untouched the roll is held, not taken from the ship", VDOT(CTL_UP, T12_UR) < -0.2 AND ABS(VDOT(CTL_UP, T12_Y)) < 0.1).

// ---- attitude hold (SAS on) mid-ascent ----
SET t12_pj["ATT"]["MODE"] TO "HOLD".
LOCAL t12_held IS CTL_DIR.
t12_near_insertion(t12_pj, t12_kj, T12_Z).
assert_true("attitude hold: no attitude commands", VANG(CTL_DIR, t12_held) < 0.001 AND VANG(CTL_GOAL_DIR, t12_held) < 0.001).
assert_true("attitude hold: the cut-off is still set", t12_pj["BB"]["CUT_UT"] >= 0).
SET t12_pj["ATT"]["MODE"] TO "AUTO".
SET T12_T TO T12_T + 0.1.
t12_step(t12_pj, t12_kj).
assert_true("back in automatic: guidance steers again", VANG(CTL_DIR, t12_held) > 1).
assert_true("back in automatic: the roll the pilot left is taken", VANG(CTL_UP, win_perp(T12_Y, CTL_DIR)) < 1).
p12_end(t12_pj).

// ---- the pilot's yaw: on release a fixed attitude is taken at once, a little ahead of the ship, and held ----
// Seen in flight: with the command following the ship after a release nothing braked it, and it was taken still turning (swinging 4.5 degrees past).
// t12_face: the window face rolled deg about the thrust axis (+X).
FUNCTION t12_face {
  PARAMETER deg.
  RETURN V(0, COS(deg), SIN(deg)).
}
LOCAL t12_roll IS p12_roll_new().
LOCAL t12_up IS p12_roll(t12_roll, t12_face(5), T12_UR, T12_Y, 0, 100).
assert_true("roll: stick untouched, a drifting ship does not move the command", VANG(t12_up, T12_Y) < 0.001).
SET t12_up TO p12_roll(t12_roll, t12_face(5), T12_UR, t12_up, 1, 100.2).
assert_near("roll: with the stick the command leads the ship", VANG(t12_up, t12_face(5)), P63_ROLL_STICK_LEAD_DEG, 0.01).
SET t12_up TO p12_roll(t12_roll, t12_face(7), T12_UR, t12_up, 0, 100.4).          // released at 10 degrees a second
assert_near("roll: on release the target is where the ship will stop, ASC_ROLL_LEAD_S ahead", VANG(t12_up, t12_face(7)), 10 * ASC_ROLL_LEAD_S, 0.2).
assert_true("roll: ahead in the direction of the turn", VANG(t12_up, t12_face(14)) < 1).
LOCAL t12_taken IS t12_up.
SET t12_up TO p12_roll(t12_roll, t12_face(20), T12_UR, t12_up, 0, 100.6).
SET t12_up TO p12_roll(t12_roll, t12_face(24), T12_UR, t12_up, 0, 105).
assert_true("roll: the target stays, whatever the ship does", VANG(t12_up, t12_taken) < 0.001).
// Released with the ship still: its own attitude.
SET t12_up TO p12_roll(t12_roll, t12_face(30), T12_UR, t12_up, 1, 200).
SET t12_up TO p12_roll(t12_roll, t12_face(30), T12_UR, t12_up, 0, 200.2).
assert_true("roll: released without turning, the present attitude", VANG(t12_up, t12_face(30)) < 0.001).
// The held window turns with the thrust axis and stays square to it.
LOCAL t12_tipped IS V(COS(40), 0, SIN(40)).
SET t12_up TO p12_roll(p12_roll_new(), T12_Y, t12_tipped, V(-1, 0, 0), 0, 300).
assert_true("roll: held square to a turned thrust axis", ABS(VDOT(t12_up, t12_tipped)) < 1e-6 AND VDOT(t12_up, V(-1, 0, 0)) > 0.5).

// ---- the warp to the countdown (not Apollo; as P40) ----
LOCAL t12_pw IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kw IS t12_keys().
t12_to_burn(t12_pw, t12_kw).
assert_true("warp: not at once", NOT t12_pw["WARP"]["DONE"]).
SET T12_T TO T12_T + P63_SETTLE_HOLD_S + 0.5.
SET t12_o TO t12_step(t12_pw, t12_kw).
assert_true("warp: a few seconds after the countdown display, with a message", t12_pw["WARP"]["DONE"] AND t12_o["MSG"]:CONTAINS("WARPING")).
SET T12_T TO T12_T + 0.5.
assert_true("warp: once only", NOT t12_step(t12_pw, t12_kw)["MSG"]:CONTAINS("WARPING")).
SET t12_pw TO t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_kw TO t12_keys().
SET T12_T TO T12_TIG - P63_WARP_LEAD_S - 5.
t12_to_burn(t12_pw, t12_kw).
SET T12_T TO T12_T + P63_SETTLE_HOLD_S + 0.5.
t12_step(t12_pw, t12_kw).
assert_true("warp: none when the lift-off is already close", t12_pw["WARP"]["DONE"] AND NOT T12_MSG:CONTAINS("WARPING")).

// ---- engine failure: V97 ----
LOCAL t12_pf IS t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
LOCAL t12_kf IS t12_keys().
t12_to_burn(t12_pf, t12_kf).
SET T12_G TO 0.                          // no gravity and no motion: nothing at all is measured
SET t12_stages TO CTL_DRY_STAGES.
t12_light(t12_pf, t12_kf).
LOCAL t12_v97 IS FALSE.
FROM { LOCAL i IS 0. } UNTIL i >= 60 STEP { SET i TO i + 1. } DO {
  SET T12_T TO T12_T + 0.5.
  SET t12_o TO t12_step(t12_pf, t12_kf).
  IF t12_o["REQUEST"]:ISTYPE("Lexicon") { IF t12_o["REQUEST"]["VERB"] = 97 { SET t12_v97 TO TRUE. } }
}
assert_true("engine failure: V97", t12_v97 AND t12_pf["DVMON"]["FAILED"]).
t12_enter(t12_pf, t12_kf, 97, 74).
assert_true("V97 ENTR: engine off, relight scheduled", NOT t12_pf["ENGINE_LIT"] AND NOT t12_pf["ENDED"]).
assert_near("V97 ENTR: new TIG 5 s ahead", t12_pf["TIG"], T12_T + 5, 1e-6).
SET T12_T TO T12_T + 0.5.
SET t12_o TO t12_step(t12_pf, t12_kf).
assert_true("V97 ENTR: the prompt again", t12_o["REQUEST"]["VERB"] = 99).
t12_pro(t12_pf, t12_kf).
SET T12_T TO t12_pf["TIG"].
t12_step(t12_pf, t12_kf).
assert_true("relight: lit again", t12_pf["ENGINE_LIT"]).
assert_near("relight: never staged twice", CTL_DRY_STAGES, t12_stages + 1, 0).
p12_end(t12_pf).

// ---- the ascent's thrust threshold (Luminary THRESH2): the RCS alone is not thrust ----
// Seen in flight: with the engine out, the RCS (fired by the full throttle) still pushed at 0.67 m/s2 and no V97 came until it ran dry.
SET t12_pf TO t12_start("A11", T12_Y, FALSE, t12_vault(T12_TIG)).
SET t12_kf TO t12_keys().
t12_to_burn(t12_pf, t12_kf).
SET T12_G TO 0.
t12_light(t12_pf, t12_kf).
FROM { LOCAL i IS 0. } UNTIL i >= 60 STEP { SET i TO i + 1. } DO {
  SET T12_T TO T12_T + 0.5.
  SET T12_V TO T12_V + T12_UR * (0.67 * 0.5).
  t12_step(t12_pf, t12_kf).
}
assert_true("engine out with the RCS pushing at 0.67 m/s2: V97", t12_pf["DVMON"]["FAILED"]).
p12_end(t12_pf).
// A failing engine that still gives 2 m/s2 (as one did in flight, at 40 percent) is thrust: no V97.
LOCAL t12_mon IS dvmon_new(ASC_DVMON_ACCEL_MS2).
FROM { LOCAL i IS 0. } UNTIL i >= 20 STEP { SET i TO i + 1. } DO { dvmon_step(t12_mon, 4 * i, 2 * i). }
assert_true("a weak engine at 2 m/s2 raises no V97", NOT t12_mon["FAILED"]).
assert_near("the burns' monitor keeps its own threshold", dvmon_new()["MIN"], DVMON_ACCEL_MS2, 0).

// ---- the whole ascent to cut-off, trim and end; a target changed after the start changes nothing ----
LOCAL t12_vf IS t12_vault(T12_TIG).
LOCAL t12_cr IS t12_craft(T12_Y, FALSE).
SET T12_T TO 2000.
SET T12_R TO V(T12_RAD, 0, 0).
SET T12_V TO V(0, 0, 0).
SET T12_G TO T12_MU.
SET T12_MASS TO 4915.
LOCAL t12_pc IS p12_start(FALSE, t12_vf, T12_CLOCK, "A11", 2000, t12_cr, V(0, 0, 0)).
LOCAL t12_q0 IS t12_pc["QAXIS0"].
SET t12_cr["CSM"]["R"] TO V(0, 1848520, 0).
SET t12_cr["CSM"]["V"] TO V(0, 0, 1628.58).
LOCAL t12_kc IS t12_keys().
SET t12_o TO t12_to_burn(t12_pc, t12_kc).
assert_true("target changed: the plane is the one at the start", VANG(t12_pc["QAXIS0"], t12_q0) < 0.001).
assert_true("target changed: N74 yaw as before", t12_o["EXTRA"]["P12_YAW"] < 1 OR t12_o["EXTRA"]["P12_YAW"] > 359).
t12_light(t12_pc, t12_kc).
// fly: 2 s steps until the timed cut-off is set
UNTIL t12_pc["BB"]["CUT_UT"] >= 0 OR T12_T > T12_TIG + 600 OR t12_pc["ENDED"] {
  t12_move(2).
  t12_step(t12_pc, t12_kc).
}
LOCAL t12_cut IS t12_pc["BB"]["CUT_UT"].
assert_true("cut-off: set", t12_cut >= 0).
assert_near("cut-off: about 434 s after lift-off", t12_cut - T12_TIG, 434, 15).
p12_cut_check(t12_pc, t12_cut - 0.01).
assert_true("cut check before the time does nothing", t12_pc["ENGINE_LIT"] AND CTL_THR = 1).
t12_move(t12_cut - 0.01 - T12_T).
t12_step(t12_pc, t12_kc).
assert_near("cut-off: one cut time", t12_pc["BB"]["CUT_UT"], t12_cut, 0).
t12_move(t12_cut - T12_T).
p12_cut_check(t12_pc, t12_cut).
assert_true("cut check at the time shuts the engine", NOT t12_pc["ENGINE_LIT"] AND CTL_THR = 0).
assert_true("cut-off: the RCS setting is put back for the trim", CTL_DRY_FORE AND NOT t12_pc["RCS_HELD"]).
LOCAL t12_end_st IS asc_state(T12_R, T12_V, t12_q0, T12_MU, T12_RAD + ASC_HINJECT_M).
assert_near("insertion height, m above the site", t12_end_st["RMAG"] - T12_RAD, ASC_HINJECT_M, 300).
assert_near("insertion horizontal speed", t12_end_st["ZDOT"], ASC_ZDOTD_NOM, 3).
assert_near("insertion radial speed", t12_end_st["RDOT"], ASC_RDOTD_NOM, 1.5).
SET T12_T TO t12_cut + 0.1.
t12_step(t12_pc, t12_kc).
SET T12_T TO t12_cut + 0.35.
SET t12_o TO t12_step(t12_pc, t12_kc).
assert_true("after cut-off: flashing V16 N63", t12_o["SET_VERB"] = 16 AND t12_o["SET_NOUN"] = 63 AND t12_o["REQUEST"]["NOUN"] = 63).
assert_near("after cut-off: ABVEL is the inertial speed", t12_o["EXTRA"]["ABVEL"], T12_V:MAG, 0.01).
t12_pro(t12_pc, t12_kc).
SET t12_o TO t12_step(t12_pc, t12_kc).
assert_true("PRO: flashing V16 N85", t12_o["SET_VERB"] = 16 AND t12_o["SET_NOUN"] = 85 AND t12_o["REQUEST"]["NOUN"] = 85).
assert_true("trim: little velocity to be gained", V(t12_o["EXTRA"]["P40_VGB"][0], t12_o["EXTRA"]["P40_VGB"][1], t12_o["EXTRA"]["P40_VGB"][2]):MAG < 5).
SET t12_o TO t12_pro(t12_pc, t12_kc).
assert_true("PRO: P12 ends", t12_o["ENDED"]).
p12_end(t12_pc).
assert_near("after the end the throttle is zero", CTL_THR, 0, 0).

SET P40_DRY_FACING TO t12_keep_facing.
test_end().
