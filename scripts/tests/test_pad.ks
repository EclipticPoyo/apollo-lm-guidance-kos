// test_pad.ks -- pad test for the planner's PAD builder (lm/planner/lm_pad.ks). No ship access. Expected lines come from
// `python scripts/tests/reference_loads.py` (pad_lines).
//   RUNPATH("0:/tests/test_pad.ks").
// Log: 0:/lm/logs/test_pad.log. The last line is "TESTS: N passed, M failed".

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/lm/planner/lm_pad.ks").
RUNONCEPATH("0:/lm/planner/lm_deorbit.ks").      // no arguments: loads the functions only (dp_node_text)

test_begin("0:/lm/logs/test_pad.log").

LOCAL moon_r IS 1737400.
LOCAL zero_ut IS 100000.
// A plan: site 0.674 N 23.473 E at -1930 m, landing at UT 400000, DOI at 399000 (30 m/s retrograde), no plane change.
// The PAD uplinks the DOI burn; a plane change is the CSM's burn and gets only a note.
LOCAL plan_a IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 400000, "T_DOI", 399000, "T_PC", -1,
                        "LV_DOI", LIST(-30, 0, 0), "LV_PC", LIST(0, 0, 0)).

// ---- key helpers ---------------------------------------------------------------------------------------------------------
assert_true("pad_v71_keys for two words at 1501 octal", pad_join(pad_v71_keys(833, LIST(1, 2))) = "V71E04E1501E00001E00002EV33E").

// ---- the whole PAD, Apollo 11 profile, no plane change ---------------------------------------------------------------------
LOCAL pad IS pad_build(plan_a, "A11", moon_r, zero_ut).
assert_true("PAD builds", pad["OK"]).
LOCAL lines IS pad["LINES"].
assert_near("PAD has 19 lines (three blocks with their headings, then a blank and the three-line P30/P40 note; no KEYED part)", lines:LENGTH, 19, 0).
assert_true("the PAD says to fly the DOI with P30 then P40 and gives the MAN reminder (ENG_THR_CONT, checklist 203)",
            lines[16]:CONTAINS("P30 then P40") AND lines[17]:CONTAINS("ENG_THR_CONT = MAN") AND lines[17]:CONTAINS("203")).
assert_true("header", lines[0] = "PAD LUMINARY099     CLOCK ZERO UT 100000").
assert_true("uplink heading", lines[1] = "UPLINK in P00, one block at a time (V34 E abandons a block)").
assert_true("blank line between header and first block", lines[2] = "").
assert_true("RLS heading", lines[3] = "LANDING SITE (RLS)   address 2022").
assert_true("RLS site line", lines[4] = "  lat 0.674  long 23.473  height -1930 m").
assert_true("RLS keys on one line", lines[5] = "  V71 E 10 E 2022 E  00302 E 11604 E 00124 E 14046 E 00002 E 17576 E  V33 E").
assert_true("TLAND heading and time line", lines[7] = "LANDING TIME (TLAND)   address 2400" AND lines[8] = "  30000000 cs = 83:20:00.00 after the clock zero").
assert_true("TLAND keys on one line", lines[9] = "  V71 E 04 E 2400 E  03447 E 01600 E  V33 E").
assert_true("DOI heading", lines[11] = "DOI BURN   address 3433").
assert_true("DOI TIG line shows the N33 values", lines[12] = "  TIG  83:03:20.00   N33 +00083 +00003 +02000").
assert_true("DOI DV line shows the N81 values", lines[13] = "  DV   N81 -00984 +00000 +00000   (tenths ft/s, local vertical X Y Z)").
assert_true("DOI keys on one line (index 12 octal = 8 words + 2)", lines[14] = "  V71 E 12 E 3433 E  77731 E 63145 E 00000 E 00000 E 00000 E 00000 E 03440 E 36340 E  V33 E").
assert_true("blank lines separate the blocks", lines[6] = "" AND lines[10] = "").
assert_true("the uplink keys are the three V71 blocks",
            pad_join(pad["UPLINK_KEYS"]) = "V71E10E2022E00302E11604E00124E14046E00002E17576EV33EV71E04E2400E03447E01600EV33EV71E12E3433E77731E63145E00000E00000E00000E00000E03440E36340EV33E").

// ---- with a plane change: the PC is the CSM's burn, so the LM PAD is the same plus a note -----------------------------------------
LOCAL plan_pc IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 400000, "T_DOI", 399000, "T_PC", 398000,
                         "LV_DOI", LIST(-30, 0, 0), "LV_PC", LIST(0, 2.5, 0)).
LOCAL pad_pc IS pad_build(plan_pc, "A11", moon_r, zero_ut).
LOCAL lines_pc IS pad_pc["LINES"].
assert_near("PAD with a plane change has 21 lines (the 19, a blank and the PC note)", lines_pc:LENGTH, 21, 0).
assert_true("the DOI block is the same as without a plane change", lines_pc[12] = lines[12] AND lines_pc[14] = lines[14]).
assert_true("a blank line then the PC note says it is a CSM burn", lines_pc[15] = "" AND lines_pc[16] = "PC: a CSM burn, flown from its node; not loaded in the LM").
assert_true("the uplink keys are the same as without a plane change", pad_join(pad_pc["UPLINK_KEYS"]) = pad_join(pad["UPLINK_KEYS"])).
assert_true("nothing is keyed: no V25 and no KEYED heading", NOT pad_join(pad_pc["UPLINK_KEYS"]):CONTAINS("V25") AND NOT lines_pc:CONTAINS("KEYED (P00)")).

// ---- PLAN_NODES: the planner's words about the nodes -------------------------------------------------------------------------
LOCAL words_keep IS dp_node_text(2, TRUE).
assert_true("PLAN_NODES TRUE: the planner says how many nodes it added and to fly the burns with P30 and P40", words_keep:CONTAINS("2 manoeuvre node") AND words_keep:CONTAINS("P30 and P40")).
LOCAL words_none IS dp_node_text(2, FALSE).
assert_true("PLAN_NODES FALSE: the planner says none were left and does not count nodes", words_none:CONTAINS("No manoeuvre nodes left") AND NOT words_none:CONTAINS("2 manoeuvre")).

// ---- J profile uses the 210 addresses ----------------------------------------------------------------------------------------
LOCAL pad_j IS pad_build(plan_a, "J", moon_r, zero_ut).
LOCAL lines_j IS pad_j["LINES"].
assert_true("J header", lines_j[0] = "PAD LUMINARY210     CLOCK ZERO UT 100000").
assert_true("J RLS ECADR is 2020 octal", lines_j[3] = "LANDING SITE (RLS)   address 2020" AND lines_j[5]:STARTSWITH("  V71 E 10 E 2020 E  ")).
assert_true("J TLAND ECADR is 2026 octal (next to RLS)", lines_j[7] = "LANDING TIME (TLAND)   address 2026" AND lines_j[9]:STARTSWITH("  V71 E 04 E 2026 E  ")).
assert_true("J burn block uses the same DELVLVC address", lines_j[11] = "DOI BURN   address 3433" AND lines_j[14]:STARTSWITH("  V71 E 12 E 3433 E  77731 E 63145 E")).

// ---- refusals (Review Focus 4) ----------------------------------------------------------------------------------------------------
LOCAL plan_far IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 100000 + 2 ^ 28 / 100, "T_DOI", 399000, "T_PC", -1,
                          "LV_DOI", LIST(-30, 0, 0), "LV_PC", LIST(0, 0, 0)).
LOCAL pad_far IS pad_build(plan_far, "A11", moon_r, zero_ut).
assert_true("a landing time beyond 2^28 cs is refused with a reason", NOT pad_far["OK"] AND pad_far["WHY"] <> "" AND pad_far["LINES"]:LENGTH = 0).
LOCAL pad_early IS pad_build(plan_a, "A11", moon_r, 500000).
assert_true("a clock zero after the landing is refused", NOT pad_early["OK"]).
LOCAL plan_old IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 400000, "T_DOI", 399000, "T_PC", -1).
LOCAL pad_old IS pad_build(plan_old, "A11", moon_r, zero_ut).
assert_true("a plan without the delta-v vectors asks for a new plan", NOT pad_old["OK"] AND pad_old["WHY"]:CONTAINS("plan again")).
LOCAL pad_none IS pad_build(FALSE, "A11", moon_r, zero_ut).
assert_true("no plan gives no PAD", NOT pad_none["OK"]).

// ---- writing files ------------------------------------------------------------------------------------------------------------
LOCAL pad_path IS "0:/lm/logs/test_pad_out.txt".
pad_write(lines_pc, pad_path).      // the plane-change PAD has the PC note as its last line
LOCAL text_back IS OPEN(pad_path):READALL:STRING.
assert_true("pad_write wrote the lines", text_back:CONTAINS("PC: a CSM burn, flown from its node; not loaded in the LM")).
pad_write_uplink(LIST("V", "7", "1", "E"), pad_path).
LOCAL up_back IS OPEN(pad_path):READALL:STRING:SPLIT(CHAR(10)).
assert_true("pad_write_uplink wrote one key per line", up_back[0]:TRIM() = "V" AND up_back[3]:TRIM() = "E").
DELETEPATH(pad_path).

test_end().
