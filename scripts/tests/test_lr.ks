// test_lr.ks -- pad test for the landing-radar state: V57 and V58, the permit reset, N66 and N67, the radar test timing (no ship access).
//   RUNPATH("0:/tests/test_lr.ks").   Log: 0:/lm/logs/test_lr.log.
// The no-data gate stays at 12 km (RADAR_ALT_MAX_M, decided 2026-11-15); 15,240 m (50,000 ft) is only in a comment.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_lr.log").

assert_near("RADAR_ALT_MAX_M is still 12000", RADAR_ALT_MAX_M, 12000, 0).

// ---- V57 and V58 ----
SET LM_VEH["LR_PERMIT"] TO FALSE.
assert_true("V57 sets the permit", lm_verb_57(FALSE) AND LM_VEH["LR_PERMIT"]).
assert_true("V58 clears it", lm_verb_58(FALSE) AND NOT LM_VEH["LR_PERMIT"]).
assert_true("V77 is accepted and changes nothing", lm_verb_accept(FALSE) AND NOT LM_VEH["LR_PERMIT"]).

// ---- the permit reset (210 only: 50 ft = 15.24 m) ----
assert_true("J: the permit is cleared below 15.24 m", NOT lm_lr_reset(TRUE, 10, 15.24)).
assert_true("J: the permit stays above 15.24 m", lm_lr_reset(TRUE, 100, 15.24)).
assert_true("A11 (cutoff 0): no reset even on the ground", lm_lr_reset(TRUE, 1, 0)).
assert_true("a cleared permit stays cleared", NOT lm_lr_reset(FALSE, 100, 15.24)).

// ---- V59 and V60 by profile ----
assert_true("A11 has V60 and not V59", lm_verbs_for("A11"):CONTAINS(60) AND NOT lm_verbs_for("A11"):CONTAINS(59)).
assert_true("J has V59 and not V60", lm_verbs_for("J"):CONTAINS(59) AND NOT lm_verbs_for("J"):CONTAINS(60)).
assert_true("V57, V58 and V77 are in both", lm_verbs_for("J"):CONTAINS(57) AND lm_verbs_for("A11"):CONTAINS(58) AND lm_verbs_for("A11"):CONTAINS(77)).

// ---- the radar test timing (audit K1): the altitude test runs only from the high gate on ----
LOCAL rd IS radar_new().
radar_step(rd, 1000, 1300, 100, 0, FALSE).
radar_step(rd, 1000, 1300, 100, 0, FALSE).
radar_step(rd, 1000, 1300, 100, 0, FALSE).
assert_true("before the high gate a 300 m error does not light ALT", NOT rd["ALT_LAMP"] AND NOT rd["ALT_TEST"] AND rd["ALT_N"] = 0).
SET rd TO radar_new().
radar_step(rd, 1000, 1300, 100, 0, TRUE).
assert_true("after the gate one bad test does not light ALT", NOT rd["ALT_LAMP"]).
radar_step(rd, 1000, 1300, 100, 0, TRUE).
assert_true("after the gate a second bad test within four lights ALT", rd["ALT_LAMP"]).
SET rd TO radar_new().
radar_step(rd, 20000, 20000, 1000, 0, FALSE).
assert_true("no data above RADAR_ALT_MAX_M lights ALT even before the gate", rd["ALT_LAMP"]).
SET rd TO radar_new().
radar_step(rd, 1000, 1300, 100, 0).
radar_step(rd, 1000, 1300, 100, 0).
assert_true("the default is the test on (the old calls keep their meaning)", rd["ALT_LAMP"]).

// ---- lm_radar_velocity ----
LOCAL xnb IS V(0, 1, 0).
LOCAL znb IS V(0, 0, 1).
LOCAL along IS lm_radar_velocity(V(0, 5, 0), xnb, znb).
assert_true("a vector along xnb gives (|v|, 0, 0)", ABS(along[0] - 5) < 1e-6 AND ABS(along[1]) < 1e-6 AND ABS(along[2]) < 1e-6).
LOCAL fwd IS lm_radar_velocity(V(0, 0, 3), xnb, znb).
assert_true("a vector along znb gives (0, 0, |v|)", ABS(fwd[2] - 3) < 1e-6 AND ABS(fwd[0]) < 1e-6).
LOCAL side IS lm_radar_velocity(V(2, 0, 0), xnb, znb).
assert_true("the third axis is Y = Z x X (right-handed)", ABS(ABS(side[1]) - 2) < 1e-6 AND ABS(side[0]) < 1e-6 AND ABS(side[2]) < 1e-6).

// ---- N66 and N67 ----
LOCAL base IS LEXICON("VALID", TRUE, "VHORIZ", 0, "ABVEL", 0, "HDOT", 0, "HCALC", 0).
LOCAL d66 IS base:COPY.
SET d66["RADAR_ALT_M"] TO 8300 / FT_PER_M.
SET d66["RADAR_ANT"] TO 2.
LOCAL r66 IS noun_registers(66, d66).
assert_true("N66: altitude 8300 ft and antenna 2 show +08300 and +00002", r66[0] = "+08300" AND r66[1] = "+00002").
SET d66["RADAR_ALT_M"] TO 0.
SET d66["RADAR_ANT"] TO 1.
SET r66 TO noun_registers(66, d66).
assert_true("N66 with no radar data shows zero height", r66[0] = "+00000").
LOCAL d67 IS base:COPY.
SET d67["RADAR_VEL"] TO LIST(-3 / FT_PER_M, 1 / FT_PER_M, 0).
LOCAL r67 IS noun_registers(67, d67).
assert_true("N67 shows whole ft/s: -3, +1, 0", r67[0] = "-00003" AND r67[1] = "+00001" AND r67[2] = "+00000").
assert_true("N67 with no data shows zeros", noun_registers(67, base)[0] = "+00000").
assert_true("N66 and N67 are in the LM tables", LM_NOUNS:CONTAINS(66) AND LM_NOUNS:CONTAINS(67)).

test_end().
