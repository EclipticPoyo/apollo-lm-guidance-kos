// test_burnbaby.ks -- pad tests for the burn engine (lm/burn/lm_burnbaby.ks, release 1.4). No flight needed.
//   RUNPATH("0:/tests/test_burnbaby.ks").
// The P63 table must behave exactly like the old P63 sequence (ref_seq_step below, a frozen copy), the safety net for moving P63 onto the
// engine (plan Task 11). Results go to 0:/lm/logs/test_burnbaby.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/descent/lm_ignition.ks").
RUNONCEPATH("0:/lm/descent_j/lm_j_ignition.ks").
RUNONCEPATH("0:/lm/burn/lm_burnbaby.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_burnbaby.log").

// ---- equivalence with the old P63 sequence (frozen reference) -----------------------------------------------------
// ref_seq_*: the P63 sequence exactly as it was in lm/descent/lm_ignition.ks before P63 moved onto the burn engine (plan Task 11).
// seq_new and seq_step are now thin wrappers around bb_*, so this copy is the independent oracle. Do not edit it.
FUNCTION ref_seq_new {
  PARAMETER tig.
  RETURN LEXICON("TIG", tig, "ARMED", FALSE, "IGN_T", -1, "ZOOMED", FALSE, "ENDED", FALSE).
}
FUNCTION ref_seq_phase {
  PARAMETER seq, dt.
  IF seq["IGN_T"] >= 0 {
    IF seq["ZOOMED"] { RETURN "BRAKING". }
    RETURN "BURN".
  }
  IF dt < -35 { RETURN "COAST". }
  IF dt < -30 { RETURN "BLANK". }
  IF dt < -5 { RETURN "COUNT". }
  RETURN "PROMPT".
}
FUNCTION ref_seq_step {
  PARAMETER seq, now, pro_pressed, terminate.
  LOCAL dt IS now - seq["TIG"].
  IF terminate { SET seq["ENDED"] TO TRUE. }
  LOCAL zoom_now IS FALSE.
  IF NOT seq["ENDED"] {
    LOCAL phase IS ref_seq_phase(seq, dt).
    IF phase = "PROMPT" {
      IF pro_pressed { SET seq["ARMED"] TO TRUE. }
      IF seq["ARMED"] AND dt >= 0 { SET seq["IGN_T"] TO now. }
    }
    IF seq["IGN_T"] >= 0 AND NOT seq["ZOOMED"] AND now >= MAX(seq["TIG"] + ZOOMTIME, seq["IGN_T"]) {
      SET seq["ZOOMED"] TO TRUE.
      SET zoom_now TO TRUE.
    }
  }
  LOCAL phase_now IS ref_seq_phase(seq, dt).
  IF seq["ENDED"] { SET phase_now TO "ENDED". }
  LOCAL lit IS seq["IGN_T"] >= 0.
  LOCAL ullage IS FALSE.
  IF NOT seq["ENDED"] {
    IF lit { SET ullage TO now < seq["IGN_T"] + ULLAGE_OFF_AFTER_IGN. }
    ELSE { SET ullage TO dt >= -30 + ULLAGE_START_AFTER_TIG30. }
  }
  LOCAL vn_text IS "".
  IF phase_now = "COUNT" { SET vn_text TO "V06N62". }
  IF phase_now = "PROMPT" { SET vn_text TO "V99N62". }
  IF phase_now = "BURN" OR phase_now = "BRAKING" { SET vn_text TO "V06N63". }
  RETURN LEXICON("STATE", phase_now, "VN", vn_text, "BLANK", phase_now = "BLANK", "ULLAGE", ullage,
                 "PROMPT", phase_now = "PROMPT", "KEY_REL", phase_now = "PROMPT", "ENGINE_ON", lit,
                 "ZOOM", zoom_now, "TTOGO", -dt, "ENDED", seq["ENDED"]).
}

// same_out: compare the keys ref_seq_step returns, one by one; returns the name of the first that differs, or "" when all match.
FUNCTION same_out {
  PARAMETER out_a, out_b.
  FOR key_name IN LIST("STATE", "VN", "BLANK", "ULLAGE", "PROMPT", "KEY_REL", "ENGINE_ON", "ZOOM", "TTOGO") {
    IF out_a[key_name] <> out_b[key_name] { RETURN key_name. }
  }
  RETURN "".
}

// run_equiv: step both engines over now = from_ut to to_ut in 0.25 s steps (TIG 1000), PRO pressed once at UT pro_ut
// (pass 0 for none), terminate pressed at UT term_ut (0 for none). Returns "" when every step matched, else a description.
FUNCTION run_equiv {
  PARAMETER from_ut, to_ut, pro_ut, term_ut.
  LOCAL sq_a IS ref_seq_new(1000).
  LOCAL bb_a IS bb_new(bb_table_p63("A11"), 1000).
  LOCAL now_ut IS from_ut.
  UNTIL now_ut > to_ut {
    LOCAL pro_now IS pro_ut <> 0 AND ABS(now_ut - pro_ut) < 0.01.
    LOCAL term_now IS term_ut <> 0 AND ABS(now_ut - term_ut) < 0.01.
    LOCAL out_s IS ref_seq_step(sq_a, now_ut, pro_now, term_now).
    LOCAL out_b IS bb_step(bb_a, now_ut, pro_now, term_now, FALSE).
    LOCAL diff_key IS same_out(out_s, out_b).
    IF diff_key <> "" { RETURN diff_key + " differs at " + now_ut. }
    SET now_ut TO now_ut + 0.25.
  }
  RETURN "".
}
assert_true("P63 table = old sequence: PRO at 997", run_equiv(900, 1060, 997, 0) = "").
assert_true("P63 table = old sequence: no PRO", run_equiv(900, 1060, 0, 0) = "").
assert_true("P63 table = old sequence: PRO before the prompt (980)", run_equiv(900, 1060, 980, 0) = "").
assert_true("P63 table = old sequence: terminate at 1010 after PRO", run_equiv(900, 1060, 997, 1010) = "").
assert_true("P63 table = old sequence: terminate at 960", run_equiv(900, 1060, 0, 960) = "").
// A late call: the jump from 900 to 1040, then on to 1060 (with a late PRO at 1041).
LOCAL late_s IS ref_seq_new(1000).
LOCAL late_b IS bb_new(bb_table_p63("A11"), 1000).
LOCAL late_ok IS TRUE.
FOR late_ut IN LIST(900, 1040, 1041, 1045, 1060) {
  LOCAL late_pro IS late_ut = 1041.
  IF same_out(ref_seq_step(late_s, late_ut, late_pro, FALSE), bb_step(late_b, late_ut, late_pro, FALSE, FALSE)) <> "" { SET late_ok TO FALSE. }
}
assert_true("P63 table = old sequence: late call 900 to 1040", late_ok).
// The J sequence (j_seq_*, plan Task 12) was the same code with J_ZOOMTIME: it must match the same reference, and the J
// table must carry J_ZOOMTIME.
LOCAL jq_ref IS ref_seq_new(1000).
LOCAL jq IS j_seq_new(1000).
LOCAL jq_ok IS TRUE.
LOCAL jq_ut IS 900.
UNTIL jq_ut > 1060 {
  LOCAL jq_pro IS ABS(jq_ut - 997) < 0.01.
  IF same_out(ref_seq_step(jq_ref, jq_ut, jq_pro, FALSE), j_seq_step(jq, jq_ut, jq_pro, FALSE)) <> "" { SET jq_ok TO FALSE. }
  SET jq_ut TO jq_ut + 0.25.
}
assert_true("J sequence = old sequence: PRO at 997, 900 to 1060", jq_ok).
assert_near("the J table's zoom time is J_ZOOMTIME", jq["TABLE"]["ZOOMTIME"], J_ZOOMTIME, 0).
// The table values themselves (what the equivalence rests on).
LOCAL t63 IS bb_table_p63("A11").
assert_near("P63 table BLANK_START", t63["BLANK_START"], -35, 0).
assert_near("P63 table BLANK_END", t63["BLANK_END"], -30, 0).
assert_near("P63 table ULLAGE_ON", t63["ULLAGE_ON"], -30 + ULLAGE_START_AFTER_TIG30, 1e-12).
assert_true("P63 table V99N62 prompt and V06N63 burn", t63["PROMPT_VN"] = "V99N62" AND t63["BURN_VN"] = "V06N63" AND t63["COUNT_VN"] = "V06N62").
assert_true("P63 table ENTR redisplays, zoom from nominal TIG", t63["ENTR_AT_PROMPT"] = "REDISPLAY" AND t63["ZOOM"] = "FROM_NOMINAL_TIG").
// ENTR at the P63 prompt: a redisplay once, never an ignition or a GOPOST.
LOCAL bb63 IS bb_new(t63, 1000).
bb_step(bb63, 990, FALSE, FALSE, FALSE).
LOCAL redis IS bb_step(bb63, 996, FALSE, FALSE, TRUE).
assert_true("P63 ENTR at the prompt: REDISPLAY, no GOPOST, no ignition", redis["REDISPLAY"] AND NOT redis["GOPOST"] AND NOT redis["ENGINE_ON"] AND NOT redis["ENDED"]).

// ---- P40 table, TIG 1000 -------------------------------------------------------------------------------------------
LOCAL t40 IS bb_table_p40("A11").
assert_true("P40 table keys", t40["NAME"] = "P40" AND t40["CLOCK"] AND t40["PROMPT"] AND t40["ENTR_AT_PROMPT"] = "GOPOST" AND t40["ZOOM"] = "FROM_IGNITION").
assert_near("P40 table BLANK_START", t40["BLANK_START"], -34.9, 0).
assert_near("P40 table BLANK_END", t40["BLANK_END"], -29.9, 0).
assert_near("P40 table ULLAGE_ON", t40["ULLAGE_ON"], -7.5, 0).
assert_near("P40 table ULLAGE_OFF_AFTER_IGN", t40["ULLAGE_OFF_AFTER_IGN"], 0.5, 0).
assert_near("P40 table PROMPT_AT", t40["PROMPT_AT"], -5, 0).
assert_true("P40 table nouns", t40["COUNT_VN"] = "V06N40" AND t40["PROMPT_VN"] = "V99N40" AND t40["BURN_VN"] = "V06N40").
LOCAL bb40 IS bb_new(t40, 1000).
assert_true("P40 new state", bb40["IGN_T"] = -1 AND NOT bb40["ARMED"] AND NOT bb40["ZOOMED"] AND NOT bb40["ENDED"] AND NOT bb40["NOTHROTL"] AND bb40["CUT_UT"] = -1).
assert_true("P40 960 is COAST", bb_step(bb40, 960, FALSE, FALSE, FALSE)["STATE"] = "COAST").
assert_true("P40 965.2 is BLANK", bb_step(bb40, 965.2, FALSE, FALSE, FALSE)["STATE"] = "BLANK").
LOCAL c40 IS bb_step(bb40, 975, FALSE, FALSE, FALSE).
assert_true("P40 975 is COUNT with V06N40", c40["STATE"] = "COUNT" AND c40["VN"] = "V06N40").
assert_near("P40 time to go at 975", c40["TTOGO"], 25, 1e-9).
assert_true("P40 ullage off at 992.4", NOT bb_step(bb40, 992.4, FALSE, FALSE, FALSE)["ULLAGE"]).
assert_true("P40 ullage on at 992.6", bb_step(bb40, 992.6, FALSE, FALSE, FALSE)["ULLAGE"]).
LOCAL p40 IS bb_step(bb40, 996, FALSE, FALSE, FALSE).
assert_true("P40 996 is PROMPT, V99N40, KEY REL", p40["STATE"] = "PROMPT" AND p40["PROMPT"] AND p40["KEY_REL"] AND p40["VN"] = "V99N40").
// PRO at 996 then 1000: ignition at TIG, not before.
LOCAL pro40 IS bb_step(bb40, 996, TRUE, FALSE, FALSE).
assert_true("P40 PRO at 996 does not light before TIG", NOT pro40["ENGINE_ON"]).
assert_true("P40 not lit at 999.75", NOT bb_step(bb40, 999.75, FALSE, FALSE, FALSE)["ENGINE_ON"]).
LOCAL lit40 IS bb_step(bb40, 1000, FALSE, FALSE, FALSE).
assert_true("P40 lit at 1000: ENGINE_ON, BURN, V06N40", lit40["ENGINE_ON"] AND lit40["STATE"] = "BURN" AND lit40["VN"] = "V06N40").
assert_true("P40 ullage still on at 1000.25, off at 1000.5", bb_step(bb40, 1000.25, FALSE, FALSE, FALSE)["ULLAGE"] AND NOT bb_step(bb40, 1000.5, FALSE, FALSE, FALSE)["ULLAGE"]).
// Zoom: IGN_T + ZOOMTIME, once, not before.
assert_true("P40 no zoom at 1025.75", NOT bb_step(bb40, 1025.75, FALSE, FALSE, FALSE)["ZOOM"]).
assert_true("P40 zoom at 1026", bb_step(bb40, 1026, FALSE, FALSE, FALSE)["ZOOM"]).
assert_true("P40 zoom fires once", NOT bb_step(bb40, 1027, FALSE, FALSE, FALSE)["ZOOM"]).
assert_true("P40 state stays BURN after the zoom (BRAKING is P63's)", bb_step(bb40, 1028, FALSE, FALSE, FALSE)["STATE"] = "BURN").
// A late PRO: the zoom counts from the actual ignition for P40 (P63 from the nominal TIG).
LOCAL bb40l IS bb_new(t40, 1000).
bb_step(bb40l, 998, FALSE, FALSE, FALSE).
assert_true("P40 late PRO at 1040 lights", bb_step(bb40l, 1040, TRUE, FALSE, FALSE)["ENGINE_ON"]).
assert_true("P40 no zoom on the lighting call", NOT bb_step(bb40l, 1040.25, FALSE, FALSE, FALSE)["ZOOM"]).
assert_true("P40 zoom 26 s after the actual ignition", bb_step(bb40l, 1066, FALSE, FALSE, FALSE)["ZOOM"]).
// NOTHROTL set: never a zoom.
LOCAL bb40n IS bb_new(t40, 1000).
bb_set_nothrotl(bb40n, TRUE).
assert_true("NOTHROTL is stored", bb40n["NOTHROTL"]).
bb_step(bb40n, 997, TRUE, FALSE, FALSE).
bb_step(bb40n, 1000, FALSE, FALSE, FALSE).
LOCAL nz IS FALSE.
FOR nz_ut IN LIST(1010, 1026, 1030, 1100) { IF bb_step(bb40n, nz_ut, FALSE, FALSE, FALSE)["ZOOM"] { SET nz TO TRUE. } }
assert_true("P40 with NOTHROTL never zooms", NOT nz).
// ENTR at the prompt: GOPOST exactly once, no ignition.
LOCAL bb40g IS bb_new(t40, 1000).
bb_step(bb40g, 990, FALSE, FALSE, FALSE).
LOCAL gp IS bb_step(bb40g, 996, FALSE, FALSE, TRUE).
assert_true("P40 ENTR at the prompt: GOPOST", gp["GOPOST"] AND NOT gp["ENGINE_ON"] AND NOT gp["REDISPLAY"]).
LOCAL gp2 IS bb_step(bb40g, 997, FALSE, FALSE, TRUE).
assert_true("P40 GOPOST only once", NOT gp2["GOPOST"] AND NOT gp2["ENGINE_ON"]).
assert_true("P40 no ignition at TIG after GOPOST", NOT bb_step(bb40g, 1001, FALSE, FALSE, FALSE)["ENGINE_ON"]).
// ENTR outside the prompt does nothing.
LOCAL bb40e IS bb_new(t40, 1000).
assert_true("P40 ENTR in the countdown is no GOPOST", NOT bb_step(bb40e, 980, FALSE, FALSE, TRUE)["GOPOST"]).
// Terminate in the countdown: ended, no ullage.
LOCAL tm IS bb_step(bb_new(t40, 1000), 995, FALSE, TRUE, FALSE).
assert_true("P40 terminate: ENDED, no ullage, no engine", tm["ENDED"] AND NOT tm["ULLAGE"] AND NOT tm["ENGINE_ON"]).

// ---- cutoff --------------------------------------------------------------------------------------------------------
LOCAL bbc IS bb_new(t40, 1000).
bb_step(bbc, 997, TRUE, FALSE, FALSE).
bb_step(bbc, 1000, FALSE, FALSE, FALSE).
bb_cutoff_set(bbc, 1030).
assert_true("cutoff: not before 1030", NOT bb_step(bbc, 1029.75, FALSE, FALSE, FALSE)["ENGINE_OFF"]).
LOCAL off1 IS bb_step(bbc, 1030, FALSE, FALSE, FALSE).
assert_true("cutoff: ENGINE_OFF at 1030, engine no longer commanded on", off1["ENGINE_OFF"] AND NOT off1["ENGINE_ON"]).
assert_true("cutoff: once only", NOT bb_step(bbc, 1030.25, FALSE, FALSE, FALSE)["ENGINE_OFF"]).
// A late first call after the cutoff time still gives ENGINE_OFF once.
LOCAL bbc2 IS bb_new(t40, 1000).
bb_step(bbc2, 997, TRUE, FALSE, FALSE).
bb_step(bbc2, 1000, FALSE, FALSE, FALSE).
bb_cutoff_set(bbc2, 1030).
assert_true("cutoff: a late call still cuts off", bb_step(bbc2, 1045, FALSE, FALSE, FALSE)["ENGINE_OFF"]).
// bb_cutoff_clear cancels.
LOCAL bbc3 IS bb_new(t40, 1000).
bb_step(bbc3, 997, TRUE, FALSE, FALSE).
bb_step(bbc3, 1000, FALSE, FALSE, FALSE).
bb_cutoff_set(bbc3, 1030).
bb_cutoff_clear(bbc3).
assert_true("cutoff cleared: no ENGINE_OFF", NOT bb_step(bbc3, 1031, FALSE, FALSE, FALSE)["ENGINE_OFF"] AND bbc3["CUT_UT"] = -1).
// No cutoff on an unlit engine.
LOCAL bbc4 IS bb_new(t40, 1000).
bb_cutoff_set(bbc4, 900).
assert_true("cutoff: nothing happens before ignition", NOT bb_step(bbc4, 960, FALSE, FALSE, FALSE)["ENGINE_OFF"]).

// ---- P41 table ----------------------------------------------------------------------------------------------------
LOCAL t41 IS bb_table_p41("A11").
assert_true("P41 table keys", t41["NAME"] = "P41" AND NOT t41["PROMPT"] AND NOT t41["CLOCK"] AND t41["ZOOM"] = "NONE" AND t41["ULLAGE_ON"] = FALSE).
assert_near("P41 table CLOCK_BEFORE", t41["CLOCK_BEFORE"], -35, 0).
LOCAL bb41 IS bb_new(t41, 1000).
LOCAL ull41 IS FALSE.
LOCAL prompt41 IS FALSE.
LOCAL blank_first IS 9999.
LOCAL blank_last IS -9999.
LOCAL tig_count IS 0.
LOCAL zoom41 IS FALSE.
LOCAL eng41 IS FALSE.
LOCAL now41 IS 950.
UNTIL now41 > 1040 {
  LOCAL out41 IS bb_step(bb41, now41, FALSE, FALSE, FALSE).
  IF out41["ULLAGE"] { SET ull41 TO TRUE. }
  IF out41["PROMPT"] OR out41["KEY_REL"] { SET prompt41 TO TRUE. }
  IF out41["BLANK"] {
    SET blank_first TO MIN(blank_first, now41 - 1000).
    SET blank_last TO MAX(blank_last, now41 - 1000).
  }
  IF out41["TIG_REACHED"] { SET tig_count TO tig_count + 1. }
  IF out41["ZOOM"] { SET zoom41 TO TRUE. }
  IF out41["ENGINE_ON"] { SET eng41 TO TRUE. }
  SET now41 TO now41 + 0.25.
}
assert_true("P41 never has ullage", NOT ull41).
assert_true("P41 never has a prompt or KEY REL", NOT prompt41).
assert_near("P41 BLANK starts at -34.9", blank_first, -34.9, 0.25).
assert_near("P41 BLANK ends before -29.9", blank_last, -29.9, 0.25).
assert_true("P41 BLANK ends before -29.9 exactly", blank_last < -29.9).
assert_near("P41 TIG_REACHED once", tig_count, 1, 0).
assert_true("P41 never zooms or lights an engine", NOT zoom41 AND NOT eng41).
LOCAL c41 IS bb_step(bb_new(t41, 1000), 980, FALSE, FALSE, FALSE).
assert_true("P41 countdown shows V16N85", c41["STATE"] = "COUNT" AND c41["VN"] = "V16N85").
LOCAL tn41 IS bb_step(bb_new(t41, 1000), 1001, FALSE, FALSE, FALSE).
assert_true("P41 after TIG is TIGNOW with V16N85", tn41["STATE"] = "TIGNOW" AND tn41["VN"] = "V16N85").
assert_true("P41 PRO does not light an engine", NOT bb_step(bb_new(t41, 1000), 1001, TRUE, FALSE, FALSE)["ENGINE_ON"]).
// TIG_REACHED on exactly the first call with dt >= 0, also after a late first call.
LOCAL bb41b IS bb_new(t41, 1000).
assert_true("P41 not reached at 999.75", NOT bb_step(bb41b, 999.75, FALSE, FALSE, FALSE)["TIG_REACHED"]).
assert_true("P41 reached at 1000", bb_step(bb41b, 1000, FALSE, FALSE, FALSE)["TIG_REACHED"]).
assert_true("P41 reached once", NOT bb_step(bb41b, 1000.25, FALSE, FALSE, FALSE)["TIG_REACHED"]).

// ---- bb_retime ---------------------------------------------------------------------------------------------------
LOCAL bbr IS bb_new(t40, 1000).
bb_step(bbr, 997, TRUE, FALSE, FALSE).
LOCAL lit_r IS bb_step(bbr, 1000, FALSE, FALSE, FALSE).
bb_cutoff_set(bbr, 1030).
assert_true("retime: lit before", lit_r["ENGINE_ON"]).
bb_retime(bbr, 2000).
LOCAL after_r IS bb_step(bbr, 1005, FALSE, FALSE, FALSE).
assert_true("retime: back to COAST, engine off", after_r["STATE"] = "COAST" AND NOT after_r["ENGINE_ON"]).
assert_true("retime: state cleared", bbr["IGN_T"] = -1 AND NOT bbr["ARMED"] AND NOT bbr["ZOOMED"] AND bbr["CUT_UT"] = -1 AND bbr["TIG"] = 2000).
assert_near("retime: time to go counts to the new TIG", after_r["TTOGO"], 995, 1e-9).
assert_true("retime: ullage off and no ENGINE_OFF", NOT after_r["ULLAGE"] AND NOT after_r["ENGINE_OFF"]).

// ---- P12 table (release 1.5), TIG 1000 ---------------------------------------------------------------------------
LOCAL t12bb IS bb_table_p12("A11").
assert_true("P12 table keys", t12bb["NAME"] = "P12" AND t12bb["PROMPT"] AND t12bb["ENTR_AT_PROMPT"] = "GOPOST" AND t12bb["ZOOM"] = "NONE" AND t12bb["ULLAGE_ON"] = FALSE).
assert_true("P12 table nouns", t12bb["COUNT_VN"] = "V06N74" AND t12bb["PROMPT_VN"] = "V99N74" AND t12bb["BURN_VN"] = "").
assert_true("P12 table timings are the common ones", t12bb["BLANK_START"] = t40["BLANK_START"] AND t12bb["BLANK_END"] = t40["BLANK_END"] AND t12bb["PROMPT_AT"] = -5).
LOCAL bb12 IS bb_new(t12bb, 1000).
LOCAL ull12 IS FALSE.
LOCAL zoom12 IS FALSE.
LOCAL now12 IS 950.
UNTIL now12 > 1040 {
  LOCAL out12 IS bb_step(bb12, now12, now12 = 997, FALSE, FALSE).
  IF out12["ULLAGE"] { SET ull12 TO TRUE. }
  IF out12["ZOOM"] { SET zoom12 TO TRUE. }
  SET now12 TO now12 + 0.25.
}
assert_true("P12 never has ullage or a throttle-up", NOT ull12 AND NOT zoom12).
assert_near("P12 PRO at 997 lights at TIG", bb12["IGN_T"], 1000, 1e-9).
// The P40 and P63 tables are unchanged by the P12 table.
LOCAL t40u IS bb_table_p40("A11").
assert_true("P40 table unchanged", t40u["NAME"] = "P40" AND t40u["ULLAGE_ON"] = -7.5 AND t40u["COUNT_VN"] = "V06N40" AND t40u["PROMPT_VN"] = "V99N40" AND t40u["BURN_VN"] = "V06N40" AND t40u["ZOOM"] = "FROM_IGNITION" AND t40u["ENTR_AT_PROMPT"] = "GOPOST" AND t40u["PROMPT_AT"] = -5 AND t40u["BLANK_START"] = -34.9 AND t40u["BLANK_END"] = -29.9).
LOCAL t63u IS bb_table_p63("A11").
assert_true("P63 table unchanged", t63u["NAME"] = "P63" AND t63u["ULLAGE_ON"] = -30 + ULLAGE_START_AFTER_TIG30 AND t63u["COUNT_VN"] = "V06N62" AND t63u["PROMPT_VN"] = "V99N62" AND t63u["BURN_VN"] = "V06N63" AND t63u["ZOOM"] = "FROM_NOMINAL_TIG" AND t63u["ENTR_AT_PROMPT"] = "REDISPLAY" AND t63u["PROMPT_AT"] = -5 AND t63u["BLANK_START"] = -35 AND t63u["BLANK_END"] = -30).

// ---- resp_read ---------------------------------------------------------------------------------------------------
FUNCTION make_ks {
  PARAMETER pro_f, enter_f, recycle_f, term_f.
  RETURN LEXICON("PRO", pro_f, "ENTER", enter_f, "RECYCLE", recycle_f, "TERMINATE", term_f).
}
LOCAL ks_a IS make_ks(TRUE, FALSE, FALSE, FALSE).
LOCAL rd_a IS resp_read(ks_a).
assert_true("resp_read: PRO read", rd_a["PRO"] AND NOT rd_a["ENTR"] AND NOT rd_a["V32"] AND NOT rd_a["TERM"]).
assert_true("resp_read: PRO consumed once", NOT ks_a["PRO"] AND NOT resp_read(ks_a)["PRO"]).
LOCAL rd_b IS resp_read(make_ks(FALSE, FALSE, TRUE, FALSE)).
assert_true("resp_read: V32 alone gives V32 and ENTR", rd_b["V32"] AND rd_b["ENTR"] AND NOT rd_b["PRO"]).
LOCAL rd_c IS resp_read(make_ks(FALSE, TRUE, FALSE, FALSE)).
assert_true("resp_read: ENTER alone gives ENTR, not V32", rd_c["ENTR"] AND NOT rd_c["V32"]).
LOCAL rd_d IS resp_read(make_ks(FALSE, FALSE, FALSE, TRUE)).
assert_true("resp_read: TERMINATE gives TERM", rd_d["TERM"] AND NOT rd_d["ENTR"] AND NOT rd_d["PRO"]).
LOCAL rd_e IS resp_read(make_ks(FALSE, FALSE, FALSE, FALSE)).
assert_true("resp_read: nothing pressed gives nothing", NOT rd_e["TERM"] AND NOT rd_e["PRO"] AND NOT rd_e["ENTR"] AND NOT rd_e["V32"]).

// ---- J profile: the three tables are the same in Luminary 210 ----------------------------------------------------
LOCAL t40j IS bb_table_p40("J").
assert_true("J P40 table: profile kept, values as 099 (210 P40TABLE 2240)", t40j["PROFILE"] = "J" AND t40j["ULLAGE_ON"] = t40["ULLAGE_ON"] AND t40j["BLANK_START"] = t40["BLANK_START"]).
assert_true("J P41 and P63 tables build", bb_table_p41("J")["NAME"] = "P41" AND bb_table_p63("J")["NAME"] = "P63").

test_end().
