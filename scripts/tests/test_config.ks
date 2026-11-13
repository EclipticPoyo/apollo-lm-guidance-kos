// test_config.ks -- pad test for the settings file reader (lm_settings.ks). No flight needed.
//   RUNPATH("0:/tests/test_config.ks").
// Log: 0:/lm/logs/test_config.log. It applies lines with cfg_apply_line and restores every setting afterwards, so your real
// lm_config.txt and the constants are left as they were.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_config.log").

LOCAL keep_log IS LM_LOG.
LOCAL keep_mode IS P63_WINDOW_MODE.
LOCAL keep_warp IS P63_WARP_LEAD_S.
LOCAL keep_pitch IS P64_PITCH_SIGN.
LOCAL keep_yaw IS P64_YAW_SIGN.
LOCAL keep_rod IS P66_ROD_SIGN.
LOCAL keep_body IS BODY_NAME.
SET CFG_WARNINGS TO LIST().

// Empty lines and comments change nothing and give no warning.
assert_true("blank line is ignored", cfg_apply_line("") = "" AND cfg_apply_line("   ") = "").
assert_true("comment line is ignored", cfg_apply_line("// LM_LOG = TRUE") = "" AND LM_LOG = keep_log).
assert_true("no warnings so far", CFG_WARNINGS:LENGTH = 0).

// Good lines change the constant.
cfg_apply_line("LM_LOG = TRUE").
assert_true("LM_LOG TRUE", LM_LOG).
cfg_apply_line("lm_log=false   // lower case, no spaces, trailing comment").
assert_true("LM_LOG false, any case, comment after", NOT LM_LOG).
cfg_apply_line("P63_WINDOW_MODE = keep").
assert_true("P63_WINDOW_MODE keep becomes KEEP", P63_WINDOW_MODE = "KEEP").
cfg_apply_line("P63_WARP_LEAD_S = 45.5").
assert_near("P63_WARP_LEAD_S 45.5", P63_WARP_LEAD_S, 45.5, 1e-9).
cfg_apply_line("P64_PITCH_SIGN = -1").
cfg_apply_line("P64_YAW_SIGN = 1").
cfg_apply_line("P66_ROD_SIGN = -1").
assert_true("sign settings", P64_PITCH_SIGN = -1 AND P64_YAW_SIGN = 1 AND P66_ROD_SIGN = -1).
cfg_apply_line("BODY_NAME = Mun").
assert_true("BODY_NAME text", BODY_NAME = "Mun").
assert_true("good lines gave no warnings", CFG_WARNINGS:LENGTH = 0).

// Bad lines are skipped with a reason, and the constant keeps its value.
LOCAL warn_before IS CFG_WARNINGS:LENGTH.
assert_true("unknown name is skipped", cfg_apply_line("NOT_A_SETTING = 1") <> "" AND CFG_WARNINGS:LENGTH = warn_before + 1).
assert_true("a constant that is not on the list cannot be set", cfg_apply_line("CYCLE_S = 5") <> "" AND CYCLE_S = 0.25).
assert_true("no = is skipped", cfg_apply_line("LM_LOG TRUE") <> "").
assert_true("no value is skipped", cfg_apply_line("LM_LOG =") <> "").
SET LM_LOG TO FALSE.
assert_true("bad boolean is skipped", cfg_apply_line("LM_LOG = maybe") <> "" AND NOT LM_LOG).
assert_true("bad window mode is skipped", cfg_apply_line("P63_WINDOW_MODE = SIDEWAYS") <> "" AND P63_WINDOW_MODE = "KEEP").
assert_true("text for a number is skipped", cfg_apply_line("P63_WARP_LEAD_S = soon") <> "" AND P63_WARP_LEAD_S = 45.5).
assert_true("negative warp lead is skipped", cfg_apply_line("P63_WARP_LEAD_S = -5") <> "" AND P63_WARP_LEAD_S = 45.5).
assert_true("sign other than 1 or -1 is skipped", cfg_apply_line("P64_PITCH_SIGN = 2") <> "" AND P64_PITCH_SIGN = -1).
assert_true("warnings name the line", CFG_WARNINGS[CFG_WARNINGS:LENGTH - 1]:CONTAINS("P64_PITCH_SIGN")).

// A missing file is not an error and changes nothing.
SET CFG_WARNINGS TO LIST().
cfg_load("0:/lm/no_such_config_file.txt").
assert_true("missing file: no warning", CFG_WARNINGS:LENGTH = 0).

// The shipped lm_config.txt has every setting commented out, so loading it changes nothing.
IF EXISTS(CFG_PATH) {
  cfg_load(CFG_PATH).
  report("lm_config.txt warnings: " + CFG_WARNINGS:LENGTH).
}

// Restore.
SET LM_LOG TO keep_log.
SET P63_WINDOW_MODE TO keep_mode.
SET P63_WARP_LEAD_S TO keep_warp.
SET P64_PITCH_SIGN TO keep_pitch.
SET P64_YAW_SIGN TO keep_yaw.
SET P66_ROD_SIGN TO keep_rod.
SET BODY_NAME TO keep_body.
test_end().
