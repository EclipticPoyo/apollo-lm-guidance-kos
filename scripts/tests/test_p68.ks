// test_p68.ks -- pad test for P68, landing confirmation (lm_p68.ks), N43 and the P68 table entry (no ship access except the refusal path).
//   RUNPATH("0:/tests/test_p68.ks").   Log: 0:/lm/logs/test_p68.log.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_p68.log").
SET CTL_DRY TO TRUE.

LOCAL k68 IS keys_new(LM_NOUNS, LM_VERBS, LM_PROGS).
LOCAL pr68 IS p68_enter(LEXICON(), 0.674, 23.473, -1930).
assert_near("p68_enter sets the programme number", pr68["PROG_NO"], 68, 0).

// First cycle: V06 N43 as a flashing request, with the stored position.
LOCAL o68 IS p68_step(pr68, k68).
assert_true("first step shows V06 N43", o68["SET_VERB"] = 6 AND o68["SET_NOUN"] = 43).
assert_true("and requests it", o68["REQUEST"]:ISTYPE("Lexicon") AND o68["REQUEST"]["VERB"] = 6 AND o68["REQUEST"]["NOUN"] = 43).
assert_near("EXTRA carries the latitude", o68["EXTRA"]["P68_LAT"], 0.674, 1e-9).
assert_near("EXTRA carries the longitude", o68["EXTRA"]["P68_LNG"], 23.473, 1e-9).
assert_near("EXTRA carries the altitude", o68["EXTRA"]["P68_ALT"], -1930, 1e-9).
assert_true("the CONTACT lamp stays lit", o68["CONTACT"]).
assert_near("the programme number shown is 68", o68["PROG_NO"], 68, 0).
assert_true("not ended, no handover", NOT o68["ENDED"] AND NOT o68["HANDOVER"]).

// Later cycles: the request stays, no repeated SET_VERB.
SET o68 TO p68_step(pr68, k68).
assert_true("second step: request stays, display not re-set", o68["SET_VERB"] < 0 AND o68["REQUEST"]:ISTYPE("Lexicon")).
// V32 re-posts the display.
SET k68["RECYCLE"] TO TRUE.
SET o68 TO p68_step(pr68, k68).
assert_true("V32 re-posts V06 N43", o68["SET_VERB"] = 6 AND o68["SET_NOUN"] = 43 AND NOT o68["ENDED"]).
SET k68["RECYCLE"] TO FALSE.
// ENTR alone changes nothing (it may come from keying another verb).
SET k68["ENTER"] TO TRUE.
SET o68 TO p68_step(pr68, k68).
assert_true("ENTR alone leaves the display", o68["SET_VERB"] < 0 AND NOT o68["ENDED"]).
SET k68["ENTER"] TO FALSE.
// PRO ends it; so does V34.
SET k68["PRO"] TO TRUE.
SET o68 TO p68_step(pr68, k68).
assert_true("PRO ends P68", o68["ENDED"]).
assert_true("PRO is consumed", NOT k68["PRO"]).
assert_true("and the request is gone", NOT o68["REQUEST"]:ISTYPE("Lexicon")).
LOCAL pr68b IS p68_enter(LEXICON(), 1, 2, 3).
p68_step(pr68b, k68).
SET k68["TERMINATE"] TO TRUE.
SET o68 TO p68_step(pr68b, k68).
assert_true("V34 ends P68", o68["ENDED"]).
SET k68["TERMINATE"] TO FALSE.

// N43: degrees to 0.01, altitude in nautical miles to 0.1 (Luminary PINBALL_NOUN_TABLES, Task 0 reading).
LOCAL dv68 IS LEXICON("VALID", FALSE, "P68_LAT", 0.674, "P68_LNG", -23.47, "P68_ALT", 3704).
LOCAL regs68 IS noun_registers(43, dv68).
assert_true("N43 R1 latitude +00067", regs68[0] = "+00067").
assert_true("N43 R2 longitude -02347", regs68[1] = "-02347").
assert_true("N43 R3 altitude 2.0 nm = +00020", regs68[2] = "+00020").
SET regs68 TO noun_registers(43, LEXICON("VALID", FALSE)).
assert_true("N43 with no P68 shows zeros", regs68[0] = "+00000" AND regs68[1] = "+00000" AND regs68[2] = "+00000").
assert_true("noun 43 is in the table", LM_NOUNS:CONTAINS(43)).

// The table entry and the handovers.
LOCAL tab68 IS lm_programme_table().
assert_true("V37 can select P68", LM_PROGS:CONTAINS(68)).
assert_near("P65 hands over to P68", tab68["65"]["NEXT"], 68, 0).
assert_near("P66 hands over to P68", tab68["66"]["NEXT"], 68, 0).
assert_true("P68 is selectable", tab68["68"]["SELECTABLE"]).
SET CTL_DRY_STATUS TO "FLYING".
assert_true("START refuses with the ship not down", lm_p68_start(FALSE)["REFUSED"] <> "").
// The stored RLS word round trip (what lm_p68_start writes).
LOCAL vault68 IS store_new(lm_cells_for("A11")).
LOCAL moon_r68 IS 1737400.
lm_store_put_rls(vault68, lm_site_to_rls(0.674, 23.473, -1930, moon_r68)).
LOCAL back68 IS lm_rls_to_site(lm_store_get_rls(vault68), moon_r68).
assert_near("RLS round trip latitude", back68["LAT"], 0.674, 1e-4).
assert_near("RLS round trip longitude", back68["LNG"], 23.473, 1e-4).

SET CTL_DRY TO FALSE.
test_end().
