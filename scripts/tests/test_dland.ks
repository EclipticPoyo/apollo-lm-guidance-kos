// test_dland.ks -- pad test for N69, the landing-site correction (Luminary 210 only): the DLAND store cell, the V25 N69 load and the N69 registers.
//   RUNPATH("0:/tests/test_dland.ks").   Log: 0:/lm/logs/test_dland.log. No ship access.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").
RUNONCEPATH("0:/core/dsky_core.ks").
RUNONCEPATH("0:/lm/lm_vehicle.ks").

test_begin("0:/lm/logs/test_dland.log").

LOCAL dl_vault IS store_new(lm_cells_for("J")).
SET LM_VEH TO LEXICON("STORE", dl_vault, "PROFILE", "J").
assert_true("the J store has the DLAND cell", lm_store_has_dland(dl_vault)).
assert_true("the 099 store has none", NOT lm_store_has_dland(store_new(lm_cells_for("A11")))).
assert_near("DLAND starts at zero", lm_store_get_dland(dl_vault):MAG, 0, 0).
assert_near("DLAND is ECADR 2631 octal (1433)", store_ecadr(lm_cells_for("J"), "DLAND"), 1433, 0).

// A round trip at the 2^24 m scale.
assert_true("put DLAND", lm_store_put_dland(dl_vault, V(76.2, 152.4, 6096))).
LOCAL dl_back IS lm_store_get_dland(dl_vault).
assert_near("round trip up", dl_back:X, 76.2, 0.04).
assert_near("round trip crossrange", dl_back:Y, 152.4, 0.04).
assert_near("round trip downrange", dl_back:Z, 6096, 0.04).
lm_store_put_dland(dl_vault, V(0, 0, 0)).

// V25 N69 E +20000 E +00500 E +00250 E: R1 downrange 20000 ft, R2 crossrange 500 ft, R3 up 250 ft.
assert_true("lm_load_commit N69", lm_load_commit(69, LIST(1, 2, 3), LIST(20000, 500, 250)) = "").
SET dl_back TO lm_store_get_dland(dl_vault).
assert_near("R1 20000 ft is 6096 m downrange", dl_back:Z, 6096, 0.04).
assert_near("R2 500 ft is 152.4 m crossrange", dl_back:Y, 152.4, 0.04).
assert_near("R3 250 ft is 76.2 m up", dl_back:X, 76.2, 0.04).
LOCAL dl_regs IS noun_registers(69, LEXICON("VALID", FALSE)).
assert_true("N69 shows the whole feet in the order Z, Y, X", dl_regs[0] = "+20000" AND dl_regs[1] = "+00500" AND dl_regs[2] = "+00250").
assert_true("a register not loaded keeps its value", lm_load_commit(69, LIST(2), LIST(-300)) = "" AND lm_store_get_dland(dl_vault):Z > 6095).
assert_near("and the loaded one changed", lm_store_get_dland(dl_vault):Y, -300 / FT_PER_M, 0.01).
assert_true("N69 is a loadable noun", LM_LOADS:HASKEY("69") AND LM_NOUNS:CONTAINS(69)).

// The 099 profile has no N69.
SET LM_VEH TO LEXICON("STORE", store_new(lm_cells_for("A11")), "PROFILE", "A11").
assert_true("A11: N69 load is refused", lm_load_commit(69, LIST(1), LIST(100)) <> "").
SET dl_regs TO noun_registers(69, LEXICON("VALID", FALSE)).
assert_true("A11: N69 shows zeros", dl_regs[0] = "+00000" AND dl_regs[2] = "+00000").

test_end().
