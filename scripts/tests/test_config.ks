// test_config.ks -- pad test for the settings file reader (lm_settings.ks). No flight needed.
//   RUNPATH("0:/tests/test_config.ks").
// Log: 0:/lm/logs/test_config.log. It applies lines with cfg_apply_line and restores every setting afterwards, so your real
// lm_config.txt and the constants are left as they were.

RUNONCEPATH("0:/lm/lm_constants.ks").
RUNONCEPATH("0:/tests/test_lib.ks").

test_begin("0:/lm/logs/test_config.log").

LOCAL keep_log IS LM_LOG.
LOCAL keep_start IS DSKY_START.
LOCAL keep_mode IS P63_WINDOW_MODE.
LOCAL keep_warp IS P63_WARP_LEAD_S.
LOCAL keep_pitch IS P64_PITCH_SIGN.
LOCAL keep_yaw IS P64_YAW_SIGN.
LOCAL keep_rod IS P66_ROD_SIGN.
LOCAL keep_body IS BODY_NAME.
LOCAL keep_profile IS PAD_PROFILE.
LOCAL keep_rodkeys IS ROD_KEYS.
LOCAL keep_imu IS IMU_ALIGN.
LOCAL keep_thr IS ENG_THR_CONT.
LOCAL keep_nodes IS PLAN_NODES.
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
cfg_apply_line("dsky_start = n60").
assert_true("DSKY_START n60 becomes N60", DSKY_START = "N60").
assert_true("DSKY_START other than BLANK or N60 is skipped", cfg_apply_line("DSKY_START = X") <> "" AND DSKY_START = "N60").
CFG_WARNINGS:CLEAR().
cfg_apply_line("P63_WARP_LEAD_S = 45.5").
assert_near("P63_WARP_LEAD_S 45.5", P63_WARP_LEAD_S, 45.5, 1e-9).
cfg_apply_line("P64_PITCH_SIGN = 1").
cfg_apply_line("P64_YAW_SIGN = 1").
cfg_apply_line("P66_ROD_SIGN = -1").
assert_true("sign settings", P64_PITCH_SIGN = 1 AND P64_YAW_SIGN = 1 AND P66_ROD_SIGN = -1).
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
assert_true("PAD_PROFILE is no longer a setting (the planner menu sets it): skipped", cfg_apply_line("PAD_PROFILE = J") <> "" AND PAD_PROFILE = keep_profile).
cfg_apply_line("ROD_KEYS = hn").
assert_true("ROD_KEYS hn becomes HN", ROD_KEYS = "HN").
cfg_apply_line("ROD_KEYS = SHIFTCTRL").
assert_true("ROD_KEYS SHIFTCTRL", ROD_KEYS = "SHIFTCTRL").
assert_true("a ROD_KEYS other than BOTH, HN or SHIFTCTRL is skipped", cfg_apply_line("ROD_KEYS = X") <> "" AND ROD_KEYS = "SHIFTCTRL").
assert_true("IMU_ALIGN is AUTO or REQUIRED to start with", keep_imu = "AUTO" OR keep_imu = "REQUIRED").
cfg_apply_line("IMU_ALIGN = required").
assert_true("IMU_ALIGN required becomes REQUIRED", IMU_ALIGN = "REQUIRED").
assert_true("an IMU_ALIGN other than AUTO or REQUIRED is skipped", cfg_apply_line("IMU_ALIGN = x") <> "" AND IMU_ALIGN = "REQUIRED").
assert_true("ENG_THR_CONT is AUTO or MAN to start with", keep_thr = "AUTO" OR keep_thr = "MAN").
cfg_apply_line("ENG_THR_CONT = man").
assert_true("ENG_THR_CONT man becomes MAN", ENG_THR_CONT = "MAN").
assert_true("an ENG_THR_CONT other than AUTO or MAN is skipped", cfg_apply_line("ENG_THR_CONT = x") <> "" AND ENG_THR_CONT = "MAN").
cfg_apply_line("PLAN_NODES = false").
assert_true("PLAN_NODES false becomes FALSE", NOT PLAN_NODES).
cfg_apply_line("PLAN_NODES = true").
assert_true("PLAN_NODES true becomes TRUE", PLAN_NODES).
assert_true("a PLAN_NODES other than TRUE or FALSE is skipped", cfg_apply_line("PLAN_NODES = x") <> "" AND PLAN_NODES).
assert_true("negative warp lead is skipped", cfg_apply_line("P63_WARP_LEAD_S = -5") <> "" AND P63_WARP_LEAD_S = 45.5).
assert_true("sign other than 1 or -1 is skipped", cfg_apply_line("P64_PITCH_SIGN = 2") <> "" AND P64_PITCH_SIGN = 1).
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

// ---- 1.4: sections, the generic parser and the two files -------------------------------------------------------------
assert_true("CFG_NAMES has 14 entries (LM and common names)", CFG_NAMES:LENGTH = 14).
FOR old_name IN LIST("PLAN_NODES", "LM_LOG", "DSKY_START", "P63_WINDOW_MODE", "P63_WARP_LEAD_S", "P64_PITCH_SIGN", "P64_YAW_SIGN", "P66_ROD_SIGN", "BODY_NAME", "ALARMS", "ROD_KEYS", "IMU_ALIGN", "ENG_THR_CONT", "LOG") {
  assert_true("CFG_NAMES has " + old_name, CFG_NAMES:CONTAINS(old_name)).
}
SET LM_LOG TO FALSE.
SET CFG_WARNINGS TO LIST().
LOCAL sect_tables IS LEXICON("LM", LM_SETTINGS, "CSM", LIST()).
LOCAL sect_result IS cfg_parse(LIST("[LM]", "LM_LOG = TRUE"), sect_tables, lm_cfg_custom@, "t").
assert_true("[LM] header then LM_LOG = TRUE gives TRUE", sect_result["VALUES"]["LM"]["LM_LOG"] AND sect_result["WARNINGS"]:LENGTH = 0).
SET sect_result TO cfg_parse(LIST("LM_LOG = TRUE"), sect_tables, lm_cfg_custom@, "t").
assert_true("a flat line counts as [LM]", sect_result["VALUES"]["LM"]:HASKEY("LM_LOG") AND sect_result["WARNINGS"]:LENGTH = 0).
SET sect_result TO cfg_parse(LIST("[CSM]", "LM_LOG = TRUE"), sect_tables, lm_cfg_custom@, "t").
assert_true("a [CSM] setting is skipped with a warning naming CSM", sect_result["WARNINGS"]:LENGTH = 1 AND sect_result["WARNINGS"][0]:CONTAINS("CSM") AND NOT sect_result["VALUES"]["LM"]:HASKEY("LM_LOG")).
SET sect_result TO cfg_parse(LIST("[BOGUS]", "LM_LOG = TRUE", "P63_WARP_LEAD_S = 5"), sect_tables, lm_cfg_custom@, "t").
assert_true("[BOGUS] warns once and skips its lines", sect_result["WARNINGS"]:LENGTH = 1 AND sect_result["WARNINGS"][0]:CONTAINS("BOGUS") AND NOT sect_result["VALUES"]["LM"]:HASKEY("LM_LOG")).
SET sect_result TO cfg_parse(LIST("LM_LOG = FALSE" + CHAR(13)), sect_tables, lm_cfg_custom@, "t").
assert_true("a trailing carriage return is tolerated", sect_result["WARNINGS"]:LENGTH = 0 AND NOT sect_result["VALUES"]["LM"]["LM_LOG"]).
SET sect_result TO cfg_parse(LIST(CHAR(65279) + "LM_LOG = TRUE"), sect_tables, lm_cfg_custom@, "t").
assert_true("a byte-order mark at the start is tolerated", sect_result["WARNINGS"]:LENGTH = 0 AND sect_result["VALUES"]["LM"]["LM_LOG"]).
SET sect_result TO cfg_parse(LIST("P63_WARP_LEAD_S = 30", "P63_WARP_LEAD_S = 40"), sect_tables, lm_cfg_custom@, "t").
assert_near("the later line for a setting wins", sect_result["VALUES"]["LM"]["P63_WARP_LEAD_S"], 40, 1e-9).
SET sect_result TO cfg_parse(LIST("ROD_KEYS = x"), sect_tables, lm_cfg_custom@, "t").
assert_true("an enum warning lists the choices", sect_result["WARNINGS"][0]:CONTAINS("BOTH, HN or SHIFTCTRL")).

// [COMMON]: one logging setting for every computer; the LM reads it as LM_LOG and its own section overrides it.
LOCAL comm_tables IS LEXICON("COMMON", AGC_COMMON_SETTINGS, "LM", LM_SETTINGS, "CSM", LIST()).
SET sect_result TO cfg_parse(LIST("[COMMON]", "LOG = TRUE", "[LM]", "P63_WARP_LEAD_S = 5"), comm_tables, lm_cfg_custom@, "t").
assert_true("[COMMON] LOG is stored under COMMON", sect_result["VALUES"]["COMMON"]["LOG"] AND sect_result["WARNINGS"]:LENGTH = 0).
SET sect_result TO cfg_parse(LIST("[CSM]", "LOG = TRUE"), comm_tables, lm_cfg_custom@, "t").
assert_true("a common setting is accepted under [CSM] (the CSM overrides)", sect_result["WARNINGS"]:LENGTH = 0 AND sect_result["VALUES"]["CSM"]["LOG"]).
SET sect_result TO cfg_parse(LIST("[CSM]", "P63_WARP_LEAD_S = 5"), comm_tables, lm_cfg_custom@, "t").
assert_true("an LM-only setting under [CSM] is still skipped", sect_result["WARNINGS"]:LENGTH = 1 AND sect_result["WARNINGS"][0]:CONTAINS("CSM")).
SET sect_result TO cfg_parse(LIST("[COMMON]", "P63_WARP_LEAD_S = 5"), comm_tables, lm_cfg_custom@, "t").
assert_true("an LM-only setting under [COMMON] is skipped", sect_result["WARNINGS"]:LENGTH = 1).
SET LM_LOG TO FALSE.
cfg_load_all(LIST()).
LOCAL comm_file IS "0:/lm/logs/test_config_common.txt".
IF EXISTS(comm_file) { DELETEPATH(comm_file). }
LOG "[COMMON]" TO comm_file.
LOG "LOG = TRUE" TO comm_file.
cfg_load_all(LIST(comm_file)).
assert_true("LOG in [COMMON] sets LM_LOG", LM_LOG AND CFG_WARNINGS:LENGTH = 0).
DELETEPATH(comm_file).
LOG "[COMMON]" TO comm_file.
LOG "LOG = TRUE" TO comm_file.
LOG "[LM]" TO comm_file.
LOG "LM_LOG = FALSE" TO comm_file.
cfg_load_all(LIST(comm_file)).
assert_true("[LM] LM_LOG overrides [COMMON] LOG", NOT LM_LOG AND CFG_WARNINGS:LENGTH = 0).
DELETEPATH(comm_file).
LOG "LOG = TRUE" TO comm_file.
cfg_load_all(LIST(comm_file)).
assert_true("a flat LOG line (old file) still sets LM_LOG", LM_LOG AND CFG_WARNINGS:LENGTH = 0).
DELETEPATH(comm_file).
LOG "DSKY_START = N60" TO comm_file.
cfg_load_all(LIST(comm_file)).
assert_true("a flat DSKY_START line (old file) still applies", DSKY_START = "N60" AND CFG_WARNINGS:LENGTH = 0).
DELETEPATH(comm_file).
SET DSKY_START TO keep_start.

// Two files: the second wins. Temp files under 0:/lm/logs/.
LOCAL temp_old IS "0:/lm/logs/test_config_old.txt".
LOCAL temp_new IS "0:/lm/logs/test_config_new.txt".
IF EXISTS(temp_old) { DELETEPATH(temp_old). }
IF EXISTS(temp_new) { DELETEPATH(temp_new). }
LOG "P63_WARP_LEAD_S = 11" TO temp_old.
LOG "[LM]" TO temp_new.
LOG "P63_WARP_LEAD_S = 22" TO temp_new.
cfg_load_all(LIST(temp_old, temp_new)).
assert_near("the new file wins over the old one", P63_WARP_LEAD_S, 22, 1e-9).
assert_true("both files loaded without warnings", CFG_WARNINGS:LENGTH = 0).
cfg_load_all(LIST(temp_new, temp_old)).
assert_near("the file named last wins", P63_WARP_LEAD_S, 11, 1e-9).
assert_true("CFG_PATHS lists the old file first, then the new one", CFG_PATHS[0] = "0:/lm/lm_config.txt" AND CFG_PATHS[1] = "0:/agc_config.txt").
DELETEPATH(temp_old).
DELETEPATH(temp_new).

// Restore.
SET LM_LOG TO keep_log.
SET P63_WINDOW_MODE TO keep_mode.
SET P63_WARP_LEAD_S TO keep_warp.
SET P64_PITCH_SIGN TO keep_pitch.
SET DSKY_START TO keep_start.
SET P64_YAW_SIGN TO keep_yaw.
SET P66_ROD_SIGN TO keep_rod.
SET BODY_NAME TO keep_body.
SET PAD_PROFILE TO keep_profile.
SET ROD_KEYS TO keep_rodkeys.
SET IMU_ALIGN TO keep_imu.
SET ENG_THR_CONT TO keep_thr.
SET PLAN_NODES TO keep_nodes.
test_end().
