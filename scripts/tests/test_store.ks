// test_store.ks -- pad test for the erasable store (core/dsky_store.ks) and the LM cell conversions (lm/lm_cells.ks).
//   RUNPATH("0:/tests/test_store.ks").
// Log: 0:/lm/logs/test_store.log. The last line is "TESTS: N passed, M failed".
// No ship access: the body radius is passed in. Expected numbers come from `python scripts/tests/reference_loads.py`.

RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_store.ks").
RUNONCEPATH("0:/lm/lm_cells.ks").
RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").          // lm_plan_from_store, lm_store_from_plan, lm_site_from_store, lm_profile_for

test_begin("0:/lm/logs/test_store.log").

LOCAL moon_r IS 1737400.
LOCAL cells_a IS lm_cells_for("A11").
LOCAL cells_j IS lm_cells_for("J").

// ---- ECADR and address lookup -------------------------------------------------------------------------------------
assert_near("099 RLS ECADR is 2022 octal (1042)", store_ecadr(cells_a, "RLS"), 1042, 0).
assert_near("210 RLS ECADR is 2020 octal (1040)", store_ecadr(cells_j, "RLS"), 1040, 0).
assert_near("099 TLAND ECADR is 2400 octal (1280)", store_ecadr(cells_a, "TLAND"), 1280, 0).
assert_near("210 DELVLVC ECADR is 3433 octal (1819), as in the GSOP update address table 2.1.6", store_ecadr(cells_j, "DELVLVC"), 1819, 0).
assert_near("210 UPSVFLAG-style cross check: TLAND follows RLS by six words (2026 octal, 1046)", store_ecadr(cells_j, "TLAND"), 1046, 0).
assert_near("099 ZDOTD ECADR is 2276 octal", store_ecadr(cells_a, "ZDOTD"), 1214, 0).
assert_near("099 RDOTD ECADR is 2272 octal", store_ecadr(cells_a, "RDOTD"), 1210, 0).
assert_near("099 XRANGE ECADR is 3642 octal", store_ecadr(cells_a, "XRANGE"), 1954, 0).
assert_near("210 ZDOTD ECADR is 2267 octal", store_ecadr(cells_j, "ZDOTD"), 1207, 0).
assert_near("210 RDOTD ECADR is 2263 octal", store_ecadr(cells_j, "RDOTD"), 1203, 0).
assert_near("210 XRANGE ECADR is 3642 octal", store_ecadr(cells_j, "XRANGE"), 1954, 0).
assert_true("lm_cells_for J gives the 210 table", cells_j["TLAND"]["BANK"] = 4).
assert_true("lm_cells_for A11 gives the 099 table", cells_a["TLAND"]["BANK"] = 5).

LOCAL st IS store_new(cells_a).
LOCAL dv_first IS store_ecadr(cells_a, "DELVLVC").
LOCAL hit IS store_locate(st, dv_first + 2).
assert_true("locate a word inside DELVLVC: name", hit["NAME"] = "DELVLVC").
assert_near("locate a word inside DELVLVC: index (1-based)", hit["INDEX"], 3, 0).
LOCAL none_hit IS store_locate(st, 0).
assert_true("locate an unmodelled ECADR gives no name", none_hit["NAME"] = "").
LOCAL tig_hit IS store_locate(st, dv_first + 6).
assert_true("locate the ECADR right after DELVLVC is TIG word 1", tig_hit["NAME"] = "TIG" AND tig_hit["INDEX"] = 1).   // TIG follows DELVLVC in the listing

// ---- octal text -----------------------------------------------------------------------------------------------------
assert_true("octal_text 5349 width 5", octal_text(5349, 5) = "12345").
assert_true("octal_text pads with zeros", octal_text(8, 4) = "0010").
assert_near("octal_parse 12345", octal_parse("12345"), 5349, 0).
assert_near("octal_parse rejects an 8", octal_parse("1289"), -1, 0).
assert_near("octal_parse rejects empty", octal_parse(""), -1, 0).

// ---- double-precision words -----------------------------------------------------------------------------------------
FUNCTION dp_round_trip_ok {
  PARAMETER value, scale_exp.
  RETURN ABS(dp_decode(dp_encode(value, scale_exp), scale_exp) - value) <= 2 ^ scale_exp / 2 ^ 28.
}
assert_true("dp round trip 0", dp_round_trip_ok(0, 27)).
assert_true("dp round trip -1.5", dp_round_trip_ok(-1.5, 27)).
assert_true("dp round trip 1737400", dp_round_trip_ok(1737400, 27)).
assert_true("dp round trip -1737400.25", dp_round_trip_ok(-1737400.25, 27)).
assert_true("dp round trip centiseconds", dp_round_trip_ok(40000000, 28)).
assert_true("dp round trip -0.0123 at scale 7", dp_round_trip_ok(-0.0123, 7)).
LOCAL pos_words IS dp_encode(1737400, 27).
LOCAL neg_words IS dp_encode(-1737400, 27).
assert_true("positive DP words are below 040000", pos_words[0] < 16384 AND pos_words[1] < 16384).
assert_true("negative DP words are one's complement (040000 and up)", neg_words[0] >= 16384 AND neg_words[1] >= 16384).

// ---- the store -------------------------------------------------------------------------------------------------------
assert_true("nothing loaded at start", NOT store_loaded(st, "RLS")).
assert_true("put to an unknown cell is refused", NOT store_put(st, "NOSUCH", 1, 5)).
assert_true("put to an index past the cell is refused", NOT store_put(st, "TLAND", 3, 5)).
assert_true("put word 1 of TLAND", store_put(st, "TLAND", 1, 100)).
assert_true("TLAND not loaded with one of two words", NOT store_loaded(st, "TLAND")).
assert_true("put word 2 of TLAND", store_put(st, "TLAND", 2, 200)).
assert_true("TLAND loaded with both words", store_loaded(st, "TLAND")).
LOCAL tland_words IS store_words(st, "TLAND").
assert_near("store_words returns what was put", tland_words[1], 200, 0).
store_clear(st, "TLAND").
assert_true("store_clear unloads", NOT store_loaded(st, "TLAND")).

// ---- RLS: site to words and back --------------------------------------------------------------------------------------
LOCAL vec_a IS lm_site_to_rls(0.674, 23.473, -1930, moon_r).
lm_store_put_rls(st, vec_a).
assert_true("RLS loaded after lm_store_put_rls", store_loaded(st, "RLS")).
LOCAL w IS store_words(st, "RLS").
assert_true("RLS first words match the reference (octal 00302 11604)", octal_text(w[0], 5) = "00302" AND octal_text(w[1], 5) = "11604").
assert_true("RLS last words match the reference (00002 17576)", octal_text(w[4], 5) = "00002" AND octal_text(w[5], 5) = "17576").
LOCAL site_a IS lm_rls_to_site(lm_store_get_rls(st), moon_r).
assert_near("site round trip lat", site_a["LAT"], 0.674, 0.001).
assert_near("site round trip lng", site_a["LNG"], 23.473, 0.001).
assert_near("site round trip alt", site_a["ALT"], -1930, 1).
LOCAL vec_b IS lm_site_to_rls(-3, 345, 1500, moon_r).
lm_store_put_rls(st, vec_b).
LOCAL site_b IS lm_rls_to_site(lm_store_get_rls(st), moon_r).
assert_near("southern site lat", site_b["LAT"], -3, 0.001).
assert_near("southern site lng (as -15)", site_b["LNG"], -15, 0.001).
assert_near("southern site alt", site_b["ALT"], 1500, 1).

// ---- TLAND clock and TIG and DELVLVC -----------------------------------------------------------------------------------
assert_near("negative time gives -1", lm_ut_to_tland_cs(-5, 0), -1, 0).
assert_near("2^28 cs gives -1", lm_ut_to_tland_cs(2 ^ 28 / 100, 0), -1, 0).
assert_near("400000 s from clock zero 100000 is 30000000 cs", lm_ut_to_tland_cs(400000, 100000), 30000000, 0).
assert_true("TLAND store and read back", lm_store_put_tland(st, 400000, 100000)).
assert_near("TLAND reads back to within 0.01 s", lm_store_get_tland_ut(st, 100000), 400000, 0.01).
assert_true("TLAND out of range is refused", NOT lm_store_put_tland(st, 50, 100000)).
lm_store_put_tig(st, 299000).
assert_near("TIG reads back to within 0.01 s", lm_store_get_tig(st), 299000, 0.01).
lm_store_put_dv(st, V(-30, 1.5, -0.25)).
LOCAL dv_back IS lm_store_get_dv(st).
assert_vec("DELVLVC reads back to within 0.001 m/s", dv_back, V(-30, 1.5, -0.25), 0.001).

// ---- the ascent loads (N76) ---------------------------------------------------------------------------------------------
LOCAL asc_empty IS lm_store_get_asc(store_new(cells_a)).
assert_true("ascent loads are zero when nothing is loaded", asc_empty["ZDOTD"] = 0 AND asc_empty["RDOTD"] = 0 AND asc_empty["XRANGE"] = 0).
FOR asc_cells IN LIST(cells_a, cells_j) {
  LOCAL asc_vault IS store_new(asc_cells).
  assert_true("the ascent loads are stored", lm_store_put_asc(asc_vault, 1686.9, 9.81, -3148.4)).
  LOCAL asc_back IS lm_store_get_asc(asc_vault).
  assert_near("ZDOTD reads back", asc_back["ZDOTD"], 1686.9, 0.001).
  assert_near("RDOTD reads back", asc_back["RDOTD"], 9.81, 0.001).
  assert_near("XRANGE reads back", asc_back["XRANGE"], -3148.4, 4).
}

// ---- 210 table selects different addresses ------------------------------------------------------------------------------
LOCAL st_j IS store_new(cells_j).
LOCAL j_hit IS store_locate(st_j, 1042).
assert_near("the 099 RLS ECADR is RLS word 3 in the 210 table (addresses differ), not word 1", j_hit["INDEX"], 3, 0).

// ---- programmes read the store; Skip simulated uplink fills it from the plan (Review Focus 4 and 5) ----------------------------------------------------
LOCAL empty IS store_new(cells_a).
LOCAL site_none IS lm_site_from_store(empty, moon_r).
assert_true("lm_site_from_store is not OK with nothing loaded", NOT site_none["OK"]).
assert_true("lm_plan_from_store is FALSE with nothing loaded", NOT lm_plan_from_store(empty, "A11", moon_r, 100000)).
lm_store_put_rls(empty, lm_site_to_rls(0.674, 23.473, -1930, moon_r)).
assert_true("lm_plan_from_store is FALSE with only RLS", NOT lm_plan_from_store(empty, "A11", moon_r, 100000)).
lm_store_put_tland(empty, 400000, 100000).
LOCAL made IS lm_plan_from_store(empty, "J", moon_r, 100000).
assert_true("lm_plan_from_store gives a plan LEXICON with both loaded", made:ISTYPE("Lexicon")).
assert_near("plan SITE_LAT", made["SITE_LAT"], 0.674, 0.001).
assert_near("plan SITE_LNG", made["SITE_LNG"], 23.473, 0.001).
assert_near("plan SITE_ALT", made["SITE_ALT"], -1930, 1).
assert_near("plan T_PDI is TLAND minus the PDI-to-landing time", made["T_PDI"], 400000 - PLAN_PDI_TO_LAND_S, 0.01).
assert_true("plan carries the profile it was given", made["PROFILE"] = "J" AND made["WINDOW_MODE"] = P63_WINDOW_MODE).

LOCAL fill_store IS store_new(cells_a).
LOCAL plan_a IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 400000, "PROFILE", "A11").
LOCAL filled IS lm_store_from_plan(fill_store, plan_a, moon_r, 100000).
assert_true("the plan fills RLS and TLAND (Skip simulated uplink)", filled["RLS"] AND filled["TLAND"] AND store_loaded(fill_store, "RLS") AND store_loaded(fill_store, "TLAND")).
LOCAL plan_b IS LEXICON("SITE_LAT", -3.0, "SITE_LNG", 345, "SITE_ALT", 1500, "T_LAND", 500000, "PROFILE", "A11").
LOCAL filled_again IS lm_store_from_plan(fill_store, plan_b, moon_r, 100000).
assert_true("a second plan does not overwrite what is loaded", NOT filled_again["RLS"] AND NOT filled_again["TLAND"]).
LOCAL still IS lm_rls_to_site(lm_store_get_rls(fill_store), moon_r).
assert_near("the loaded site is still the first one", still["LAT"], 0.674, 0.001).
assert_near("the loaded TLAND is still the first one", lm_store_get_tland_ut(fill_store, 100000), 400000, 0.01).
LOCAL late_store IS store_new(cells_a).
LOCAL plan_late IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 50, "PROFILE", "A11").
LOCAL filled_late IS lm_store_from_plan(late_store, plan_late, moon_r, 100000).
assert_true("a landing time before the clock zero is not loaded and says why", filled_late["RLS"] AND NOT filled_late["TLAND"] AND filled_late["WHY"] <> "").
// the DOI burn: TIG and DELVLVC from T_DOI and LV_DOI (clock zero 100000)
LOCAL burn_store IS store_new(cells_a).
LOCAL plan_burn IS LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_LAND", 400000, "T_DOI", 390000, "LV_DOI", LIST(-20.5, 0.3, 1.2), "PROFILE", "A11").
LOCAL filled_burn IS lm_store_from_plan(burn_store, plan_burn, moon_r, 100000).
assert_true("the plan fills the DOI burn (TIG and DELVLVC)", filled_burn["BURN"] AND store_loaded(burn_store, "TIG") AND store_loaded(burn_store, "DELVLVC")).
assert_near("loaded TIG is T_DOI minus the clock zero", lm_store_get_tig(burn_store), 290000, 0.01).
LOCAL burn_dv IS lm_store_get_dv(burn_store).
assert_near("loaded delta-v X", burn_dv:X, -20.5, 0.01).
assert_near("loaded delta-v Y", burn_dv:Y, 0.3, 0.01).
assert_near("loaded delta-v Z", burn_dv:Z, 1.2, 0.01).
LOCAL burn_again IS lm_store_from_plan(burn_store, LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_DOI", 395000, "LV_DOI", LIST(1, 2, 3)), moon_r, 100000).
assert_true("a loaded burn is not overwritten", NOT burn_again["BURN"] AND ABS(lm_store_get_tig(burn_store) - 290000) < 0.01).
LOCAL burn_late IS lm_store_from_plan(store_new(cells_a), LEXICON("SITE_LAT", 0.674, "SITE_LNG", 23.473, "SITE_ALT", -1930, "T_DOI", 50, "LV_DOI", LIST(1, 2, 3)), moon_r, 100000).
assert_true("a DOI time before the clock zero is not loaded and says why", NOT burn_late["BURN"] AND burn_late["WHY"] <> "").
LOCAL filled_none IS lm_store_from_plan(store_new(cells_a), FALSE, moon_r, 100000).
assert_true("no plan loads nothing", NOT filled_none["RLS"]).
assert_true("a plan with PROFILE J selects J", lm_profile_for(LEXICON("PROFILE", "J")) = "J").
// ---- the version the planner saves with its PAD (profile.txt) reaches the DSKY when there is no plan ----------------------------
LOCAL had_profile IS lm_profile_saved().
lm_profile_clear().
assert_true("no plan and no profile file: the PAD_PROFILE default", lm_profile_for(FALSE) = PAD_PROFILE AND lm_profile_saved() = "").
lm_profile_save("J").
assert_true("a saved J reaches the DSKY with no plan", lm_profile_saved() = "J" AND lm_profile_for(FALSE) = "J").
lm_profile_save("A11").
assert_true("a saved A11 reaches the DSKY with no plan", lm_profile_for(FALSE) = "A11").
lm_profile_save("J").
assert_true("a plan's own PROFILE wins over the file", lm_profile_for(LEXICON("PROFILE", "A11")) = "A11").
lm_profile_clear().
LOG "garbage" TO LM_PROFILE_FILE.
assert_true("a bad file is ignored", lm_profile_saved() = "" AND lm_profile_for(FALSE) = PAD_PROFILE).
lm_profile_clear().
assert_true("clearing removes the file", NOT EXISTS(LM_PROFILE_FILE)).
IF had_profile <> "" { lm_profile_save(had_profile). }

// ---- the clock zero: the planner's saved zero survives the undock that restarts MISSIONTIME -----------------------------------
LOCAL had_clock IS EXISTS(LM_CLOCK_FILE).
LOCAL old_clock IS 0.
IF had_clock { SET old_clock TO OPEN(LM_CLOCK_FILE):READALL:STRING:TRIM:TONUMBER(0). }
lm_clock_zero_clear().
assert_near("no clock file: the zero is this vessel's mission-time zero", lm_clock_zero_ut(), lm_clock_zero_now(), 0.5).
LOCAL past_zero IS MAX(1, TIME:SECONDS - 5000).      // a zero before UT 0 is refused, and a new save is younger than 5000 s
lm_clock_zero_save(past_zero).
assert_near("a saved clock zero is used", lm_clock_zero_ut(), past_zero, 0.01).
lm_clock_zero_save(TIME:SECONDS + 100000).
assert_near("a clock zero in the future is ignored", lm_clock_zero_ut(), lm_clock_zero_now(), 0.5).
lm_clock_zero_save(TIME:SECONDS - 4000000).
assert_near("a clock zero older than the 31 day clock is ignored", lm_clock_zero_ut(), lm_clock_zero_now(), 0.5).
lm_clock_zero_clear().
assert_true("clearing removes the file", NOT EXISTS(LM_CLOCK_FILE)).
IF had_clock AND old_clock > 0 { lm_clock_zero_save(old_clock). }

// ---- the store survives the DSKY (saved to a file at V34, restored at the next start) ----
LOCAL keep_path IS "0:/lm/logs/test_store_keep.txt".
LOCAL keep IS store_new(cells_a).
store_put_all(keep, "TLAND", dp_encode(123456, 28)).
store_put(keep, "RLS", 2, 777).
store_save(keep, keep_path, "A11").
LOCAL back IS store_new(cells_a).
assert_near("restore gives back both cells", store_restore(back, keep_path, "A11"), 2, 0).
LOCAL tland_back IS store_words(back, "TLAND").
LOCAL tland_keep IS store_words(keep, "TLAND").
assert_true("TLAND is loaded again, same words", store_loaded(back, "TLAND") AND tland_back[0] = tland_keep[0] AND tland_back[1] = tland_keep[1]).
LOCAL rls_back IS store_words(back, "RLS").
assert_true("a half-written cell stays half written (-1 words kept)", NOT store_loaded(back, "RLS") AND rls_back[1] = 777 AND rls_back[0] = -1).
assert_near("a different tag restores nothing", store_restore(store_new(cells_a), keep_path, "J"), 0, 0).
store_save(store_new(cells_a), keep_path, "A11").
assert_true("an empty store leaves no file", NOT EXISTS(keep_path)).
assert_near("a missing file restores nothing", store_restore(store_new(cells_a), keep_path, "A11"), 0, 0).

test_end().
