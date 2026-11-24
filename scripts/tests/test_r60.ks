// test_r60.ks -- pad test for R60 (lm_r60.ks), R02, R03 and P51 (lm_r02.ks), N18 and N25 and the P51 table entry. No ship access.
//   RUNPATH("0:/tests/test_r60.ks").   Log: 0:/lm/logs/test_r60.log.
// Written in release 1.4 and not yet run in KSP.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_r60.log").
SET CTL_DRY TO TRUE.

// angle_gap: the difference between two angles in degrees, around the circle (359.99 and 0 are 0.01 apart).
FUNCTION angle_gap {
  PARAMETER angle_a, angle_b.
  RETURN ABS(MOD(angle_a - angle_b + 540, 360) - 180).
}

// answer_keys: a key state showing the flashing request verb 50 noun 18 (what the core leaves in ks while it is displayed).
FUNCTION answer_keys {
  LOCAL key_state IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
  SET key_state["VERB"] TO 50.
  SET key_state["NOUN"] TO 18.
  RETURN key_state.
}

LOCAL burn_dir IS V(0, 0.6, 0.8).
LOCAL burn_up IS V(1, 0, 0).

// ---- R60: the first request ---------------------------------------------------------------------------------------
LOCAL rr IS r60_new(burn_dir, burn_up).
LOCAL ka IS answer_keys().
LOCAL ro IS r60_step(rr, ka, 999, 999).
assert_true("first step: state ASK", ro["STATE"] = "ASK").
assert_true("first step shows V50 N18 flashing", ro["VERB"] = 50 AND ro["NOUN"] = 18 AND ro["FLASH"] AND ro["CHANGED"]).
assert_true("ASK commands nothing", ro["CMD_DIR"]:MAG = 0 AND ro["CMD_UP"]:MAG = 0).
SET ro TO r60_step(rr, ka, 999, 999).
assert_true("second step: the display is not set again", ro["STATE"] = "ASK" AND NOT ro["CHANGED"]).
SET ka["RECYCLE"] TO TRUE.
SET ro TO r60_step(rr, ka, 999, 999).
assert_true("V32 shows the request again", ro["STATE"] = "ASK" AND ro["CHANGED"]).
SET ka["RECYCLE"] TO FALSE.
// an ENTR for a verb the pilot keyed over the request is not the answer
LOCAL kb IS answer_keys().
SET kb["VERB"] TO 16.
SET kb["NOUN"] TO 60.
SET kb["ENTER"] TO TRUE.
SET ro TO r60_step(rr, kb, 999, 999).
assert_true("ENTR with another verb and noun keyed leaves R60 at the request", ro["STATE"] = "ASK").

// PRO starts the manoeuvre: static V06 N18 and the burn attitude is the command
SET ka["PRO"] TO TRUE.
SET ro TO r60_step(rr, ka, 999, 999).
assert_true("PRO: state TURNING", ro["STATE"] = "TURNING").
assert_true("TURNING shows V06 N18, not flashing", ro["VERB"] = 6 AND ro["NOUN"] = 18 AND NOT ro["FLASH"] AND ro["CHANGED"]).
assert_vec("the command is the burn direction", ro["CMD_DIR"], burn_dir, 1e-9).
assert_vec("and the burn roll reference", ro["CMD_UP"], burn_up, 1e-9).
assert_true("PRO is consumed", NOT ka["PRO"]).

// a PRO during the turn is ignored (and consumed, so it cannot answer the next request)
SET ka["PRO"] TO TRUE.
SET ro TO r60_step(rr, ka, 30, 5).
assert_true("PRO during TURNING changes nothing", ro["STATE"] = "TURNING" AND NOT ro["CHANGED"]).
assert_true("and is consumed", NOT ka["PRO"]).
assert_vec("the command is still given", ro["CMD_DIR"], burn_dir, 1e-9).
// ENTR and V34 during the turn are ignored too
SET ka["ENTER"] TO TRUE.
SET ka["TERMINATE"] TO TRUE.
SET ro TO r60_step(rr, ka, 30, 5).
assert_true("ENTR and V34 during TURNING change nothing", ro["STATE"] = "TURNING").
SET ka["ENTER"] TO FALSE.
SET ka["TERMINATE"] TO FALSE.

// settle: inside the error and inside the rate
SET ro TO r60_step(rr, ka, P63_SETTLE_ERR_DEG + 1, 0).
assert_true("still turning: error too big", ro["STATE"] = "TURNING").
SET ro TO r60_step(rr, ka, 0.5, P63_SETTLE_RATE_DEG_S + 0.2).
assert_true("still turning: rate too fast", ro["STATE"] = "TURNING").
SET ro TO r60_step(rr, ka, 0.5, 0.1).
assert_true("settled: ASK2, flashing V50 N18 again", ro["STATE"] = "ASK2" AND ro["VERB"] = 50 AND ro["NOUN"] = 18 AND ro["FLASH"] AND ro["CHANGED"]).
assert_true("ASK2 commands nothing", ro["CMD_DIR"]:MAG = 0).
// ENTR at the second request finishes
SET ka["ENTER"] TO TRUE.
SET ro TO r60_step(rr, ka, 0.5, 0.1).
assert_true("ASK2 ENTR: DONE, nothing displayed", ro["STATE"] = "DONE" AND ro["VERB"] = -1 AND ro["NOUN"] = -1 AND NOT ro["FLASH"]).
SET ka["ENTER"] TO FALSE.

// ---- R60: the other answers ------------------------------------------------------------------------------------------
LOCAL r2 IS r60_new(burn_dir, burn_up).
LOCAL k2 IS answer_keys().
r60_step(r2, k2, 999, 999).
SET k2["ENTER"] TO TRUE.
SET ro TO r60_step(r2, k2, 999, 999).
assert_true("ASK ENTR: DONE at the present attitude (no command)", ro["STATE"] = "DONE" AND ro["CMD_DIR"]:MAG = 0).

LOCAL r3 IS r60_new(burn_dir, burn_up).
LOCAL k3 IS answer_keys().
r60_step(r3, k3, 999, 999).
SET k3["TERMINATE"] TO TRUE.
SET ro TO r60_step(r3, k3, 999, 999).
assert_true("ASK V34: TERM", ro["STATE"] = "TERM" AND ro["VERB"] = -1).

LOCAL r4 IS r60_new(burn_dir, burn_up).
LOCAL k4 IS answer_keys().
r60_step(r4, k4, 999, 999).
SET k4["PRO"] TO TRUE.
r60_step(r4, k4, 999, 999).
r60_step(r4, k4, 0.5, 0.1).
assert_true("(setup) R60 is at its second request", r4["STATE"] = "ASK2").
SET k4["TERMINATE"] TO TRUE.
SET ro TO r60_step(r4, k4, 0.5, 0.1).
assert_true("ASK2 V34: TERM", ro["STATE"] = "TERM").
LOCAL r5 IS r60_new(burn_dir, burn_up).
LOCAL k5 IS answer_keys().
r60_step(r5, k5, 999, 999).
SET k5["PRO"] TO TRUE.
r60_step(r5, k5, 999, 999).
r60_step(r5, k5, 0.5, 0.1).
SET k5["PRO"] TO TRUE.
SET ro TO r60_step(r5, k5, 0.5, 0.1).
assert_true("ASK2 PRO: another manoeuvre (TURNING, with the command)", ro["STATE"] = "TURNING" AND ro["CMD_DIR"]:MAG > 0).

// ---- N18: the Euler angles against the reference ---------------------------------------------------------------------
LOCAL e_x IS V(1, 0, 0).
LOCAL e_y IS V(0, 1, 0).
LOCAL ang IS r60_cdu_angles(e_x, e_y, e_x, e_y).
assert_true("the reference attitude is 0, 0, 0", angle_gap(ang[0], 0) < 1e-3 AND angle_gap(ang[1], 0) < 1e-3 AND angle_gap(ang[2], 0) < 1e-3).
SET ang TO r60_cdu_angles(e_x, e_y, V(COS(30), SIN(30), 0), V(-SIN(30), COS(30), 0)).
assert_true("pitched up 30 degrees: roll 0, pitch 30, yaw 0", angle_gap(ang[0], 0) < 1e-3 AND angle_gap(ang[1], 30) < 1e-3 AND angle_gap(ang[2], 0) < 1e-3).
SET ang TO r60_cdu_angles(e_x, e_y, V(COS(40), 0, SIN(40)), e_y).
assert_true("yawed 40 degrees: roll 0, pitch 0, yaw 40", angle_gap(ang[0], 0) < 1e-3 AND angle_gap(ang[1], 0) < 1e-3 AND angle_gap(ang[2], 40) < 1e-3).
SET ang TO r60_cdu_angles(e_x, e_y, e_x, V(0, COS(25), SIN(25))).
assert_true("rolled 25 degrees: roll 25, pitch 0, yaw 0", angle_gap(ang[0], 25) < 1e-3 AND angle_gap(ang[1], 0) < 1e-3 AND angle_gap(ang[2], 0) < 1e-3).
SET ang TO r60_cdu_angles(e_x, e_y, e_x, V(0, COS(25), -SIN(25))).
assert_true("rolled the other way: roll 335", angle_gap(ang[0], 335) < 1e-3).
// another reference: thrust axis on +z, roll reference +x; the same pitch of 30 degrees
SET ang TO r60_cdu_angles(V(0, 0, 1), V(1, 0, 0), V(SIN(30), 0, COS(30)), V(COS(30), 0, -SIN(30))).
assert_true("a turned reference: pitch 30, the rest 0", angle_gap(ang[0], 0) < 1e-3 AND angle_gap(ang[1], 30) < 1e-3 AND angle_gap(ang[2], 0) < 1e-3).
assert_near("r60_wrap_deg of a hair under 360 is 0", r60_wrap_deg(-0.000001), 0, 1e-9).

// N18 and N25 registers
LOCAL regs IS noun_registers(18, LEXICON("VALID", FALSE, "N18", LIST(0, 30, 335.5))).
assert_true("N18 shows roll, pitch, yaw to 0.01 degree", regs[0] = "+00000" AND regs[1] = "+03000" AND regs[2] = "+33550").
SET regs TO noun_registers(18, LEXICON("VALID", FALSE)).
assert_true("N18 with no angles shows zeros", regs[0] = "+00000" AND regs[1] = "+00000" AND regs[2] = "+00000").
SET regs TO noun_registers(25, LEXICON("VALID", FALSE, "N25", 51)).
assert_true("N25 R1 is 00051 with a blank sign", regs[0] = " 00051" AND regs[1] = NA AND regs[2] = NA).
assert_true("N18 and N25 are in the noun table", LM_NOUNS:CONTAINS(18) AND LM_NOUNS:CONTAINS(25)).

// ---- R02 and R03 -----------------------------------------------------------------------------------------------------
LOCAL r02_out IS r02(TRUE, TRUE).
assert_true("r02: IMU on and orientation known is OK, no alarm", r02_out["OK"] AND r02_out["ALARM"] = 0).
SET r02_out TO r02(TRUE, FALSE).
assert_true("r02: orientation not known is alarm 220", NOT r02_out["OK"] AND r02_out["ALARM"] = 220).
SET r02_out TO r02(FALSE, FALSE).
assert_true("r02: IMU off is alarm 210", NOT r02_out["OK"] AND r02_out["ALARM"] = 210).
SET r02_out TO r02(FALSE, TRUE).
assert_true("r02: a known orientation passes (as R02BOTH tests REFSMMAT first)", r02_out["OK"]).
r03().
report("r03 (a stub) returns without error").

// ---- P51 ------------------------------------------------------------------------------------------------------------
IF NOT LM_VEH:HASKEY("IMU_OK") { LM_VEH:ADD("IMU_OK", FALSE). }
SET LM_VEH["IMU_OK"] TO FALSE.
LOCAL p51 IS p51_start(FALSE).
assert_true("p51_start: P51, not refused, not ended", p51["PROG_NO"] = 51 AND p51["REFUSED"] = "" AND NOT p51["ENDED"]).
LOCAL kp IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL po IS p51_step(p51, FALSE, kp).
assert_true("first step shows V50 N25", po["SET_VERB"] = 50 AND po["SET_NOUN"] = 25).
assert_true("and asks for it with a flashing request", po["REQUEST"]:ISTYPE("Lexicon") AND po["REQUEST"]["VERB"] = 50 AND po["REQUEST"]["NOUN"] = 25).
assert_near("R1 of N25 carries 51", po["EXTRA"]["N25"], 51, 0).
assert_true("PROG shows 51", po["PROG_NO"] = 51).
SET po TO p51_step(p51, FALSE, kp).
assert_true("later steps leave the display alone and the flag unset", po["SET_VERB"] < 0 AND NOT po["ENDED"] AND NOT LM_VEH["IMU_OK"]).
SET kp["RECYCLE"] TO TRUE.
SET po TO p51_step(p51, FALSE, kp).
assert_true("V32 shows the request again", po["SET_VERB"] = 50 AND NOT po["ENDED"]).
SET kp["RECYCLE"] TO FALSE.
SET kp["PRO"] TO TRUE.
SET po TO p51_step(p51, FALSE, kp).
assert_true("PRO sets the IMU flag and ends P51", LM_VEH["IMU_OK"] AND po["ENDED"] AND NOT po["REQUEST"]:ISTYPE("Lexicon")).
assert_true("PRO is consumed", NOT kp["PRO"]).

SET LM_VEH["IMU_OK"] TO FALSE.
LOCAL p51b IS p51_start(FALSE).
LOCAL kq IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
p51_step(p51b, FALSE, kq).
SET kq["TERMINATE"] TO TRUE.
SET po TO p51_step(p51b, FALSE, kq).
assert_true("V34 ends P51 without setting the flag", po["ENDED"] AND NOT LM_VEH["IMU_OK"]).

// after P51 the r02 check passes with IMU_ALIGN REQUIRED's flags
SET r02_out TO r02(TRUE, LM_VEH["IMU_OK"]).
assert_true("REQUIRED before P51: 220", r02_out["ALARM"] = 220).
SET LM_VEH["IMU_OK"] TO TRUE.
SET r02_out TO r02(TRUE, LM_VEH["IMU_OK"]).
assert_true("and OK after P51", r02_out["OK"]).

// ---- the table -------------------------------------------------------------------------------------------------------
assert_true("V37 can select P51", LM_PROGS:CONTAINS(51)).
LOCAL table_51 IS lm_programme_table().
assert_true("the programme table has an entry 51, selectable, with no handover", table_51:HASKEY("51") AND table_51["51"]["SELECTABLE"] AND table_51["51"]["NEXT"] = -1).
assert_true("the existing entries are still there", table_51:HASKEY("63") AND table_51:HASKEY("64") AND table_51:HASKEY("65") AND table_51:HASKEY("66") AND table_51:HASKEY("68")).
assert_true("P63 is still selectable and P64 not", table_51["63"]["SELECTABLE"] AND NOT table_51["64"]["SELECTABLE"]).

test_end().
