// lm_settings.ks -- the LM's settings: reads the pilot's settings files and overrides the matching constants.
//
// lm_constants.ks loads this at its end, so every constant has its default there first, and the files only change what they
// name. Two files are read, in this order, so the later one wins: the old 0:/lm/lm_config.txt (flat, no sections, counts as
// [LM]) and the project's 0:/agc_config.txt ([LM] and [CSM] sections). A missing file changes nothing. The reader itself is
// core/agc_settings.ks; this file holds the LM's table of settings (LM_SETTINGS) and the one SET line per setting.
// A line with an unknown name or a bad value is skipped and noted in the list CFG_WARNINGS (dsky.ks prints them at
// start-up); it never stops the script.
//
// Only the settings in LM_SETTINGS can be set from a file. The tuning constants stay in lm_constants.ks.
// Keep one row per line in exactly this shape: scripts/tests/check_pack.py reads them with a regular expression.
// KerboScript cannot set a global by a name held in text, so lm_cfg_publish has one SET per setting.

RUNONCEPATH("0:/core/agc_settings.ks").
RUNONCEPATH("0:/lm/lm_alarms.ks").          // alarm_script_parse, to check the ALARMS setting

GLOBAL CFG_PATH IS "0:/lm/lm_config.txt".                         // the old flat file (still read, first)
GLOBAL CFG_PATHS IS LIST("0:/lm/lm_config.txt", "0:/agc_config.txt").
GLOBAL CFG_WARNINGS IS LIST().

GLOBAL LM_SETTINGS IS LIST().
LM_SETTINGS:ADD(LEXICON("NAME", "LM_LOG", "KIND", "BOOL", "ALLOWED", "TRUE,FALSE", "GROUP", "display")).
LM_SETTINGS:ADD(LEXICON("NAME", "P63_WINDOW_MODE", "KIND", "ENUM", "ALLOWED", "UP,KEEP", "GROUP", "descent")).
LM_SETTINGS:ADD(LEXICON("NAME", "P63_WARP_LEAD_S", "KIND", "NUMBER", "ALLOWED", "MIN=0", "GROUP", "descent")).
LM_SETTINGS:ADD(LEXICON("NAME", "BODY_NAME", "KIND", "TEXT", "ALLOWED", "", "GROUP", "descent")).
LM_SETTINGS:ADD(LEXICON("NAME", "P64_PITCH_SIGN", "KIND", "SIGN", "ALLOWED", "", "GROUP", "controls")).
LM_SETTINGS:ADD(LEXICON("NAME", "P64_YAW_SIGN", "KIND", "SIGN", "ALLOWED", "", "GROUP", "controls")).
LM_SETTINGS:ADD(LEXICON("NAME", "P66_ROD_SIGN", "KIND", "SIGN", "ALLOWED", "", "GROUP", "controls")).
LM_SETTINGS:ADD(LEXICON("NAME", "ROD_KEYS", "KIND", "ENUM", "ALLOWED", "BOTH,HN,SHIFTCTRL", "GROUP", "controls")).
LM_SETTINGS:ADD(LEXICON("NAME", "ENG_THR_CONT", "KIND", "ENUM", "ALLOWED", "AUTO,MAN", "GROUP", "burns")).
LM_SETTINGS:ADD(LEXICON("NAME", "PLAN_NODES", "KIND", "BOOL", "ALLOWED", "TRUE,FALSE", "GROUP", "planner")).

GLOBAL CFG_NAMES IS LIST().
FOR setting_row IN LM_SETTINGS { CFG_NAMES:ADD(setting_row["NAME"]). }
FOR setting_row IN AGC_COMMON_SETTINGS { CFG_NAMES:ADD(setting_row["NAME"]). }

// lm_cfg_custom: the check for the settings of kind CUSTOM. Returns "" when the value is good, else the reason.
FUNCTION lm_cfg_custom {
  PARAMETER name, value_text.
  IF name = "ALARMS" {
    IF alarm_script_parse(value_text, "A11"):ISTYPE("Boolean") { RETURN "ALARMS must be OFF, A11 or a list like 1202@315,1201@548". }
  }
  RETURN "".
}

// cfg_merged: a setting the LM takes from [LM] first, else from [COMMON]. Returns LIST(found, value). name_list holds the
// names to look for in [LM] in order (the LM's own name for a common setting comes first, e.g. LM_LOG before LOG).
FUNCTION cfg_merged {
  PARAMETER parsed_values, name_list, common_name.
  IF parsed_values:HASKEY("LM") {
    FOR lm_name IN name_list { IF parsed_values["LM"]:HASKEY(lm_name) { RETURN LIST(TRUE, parsed_values["LM"][lm_name]). } }
  }
  IF parsed_values:HASKEY("COMMON") { IF parsed_values["COMMON"]:HASKEY(common_name) { RETURN LIST(TRUE, parsed_values["COMMON"][common_name]). } }
  RETURN LIST(FALSE, 0).
}

// lm_cfg_publish: set the constants named in the values (a setting the files did not name keeps its default). The common
// settings are read from [LM] (the old flat files and any override) and then from [COMMON]; LM_LOG is the LM's name for LOG.
FUNCTION lm_cfg_publish {
  PARAMETER parsed_values.
  LOCAL found IS cfg_merged(parsed_values, LIST("LM_LOG", "LOG"), "LOG").
  IF found[0] { SET LM_LOG TO found[1]. }
  SET found TO cfg_merged(parsed_values, LIST("DSKY_START"), "DSKY_START").
  IF found[0] { SET DSKY_START TO found[1]. }
  SET found TO cfg_merged(parsed_values, LIST("IMU_ALIGN"), "IMU_ALIGN").
  IF found[0] { SET IMU_ALIGN TO found[1]. }
  SET found TO cfg_merged(parsed_values, LIST("ALARMS"), "ALARMS").
  IF found[0] { SET ALARMS TO found[1]. }
  IF NOT parsed_values:HASKEY("LM") { RETURN. }
  LOCAL lm_vals IS parsed_values["LM"].
  IF lm_vals:HASKEY("P63_WINDOW_MODE") { SET P63_WINDOW_MODE TO lm_vals["P63_WINDOW_MODE"]. }
  IF lm_vals:HASKEY("P63_WARP_LEAD_S") { SET P63_WARP_LEAD_S TO lm_vals["P63_WARP_LEAD_S"]. }
  IF lm_vals:HASKEY("BODY_NAME") { SET BODY_NAME TO lm_vals["BODY_NAME"]. }
  IF lm_vals:HASKEY("P64_PITCH_SIGN") { SET P64_PITCH_SIGN TO lm_vals["P64_PITCH_SIGN"]. }
  IF lm_vals:HASKEY("P64_YAW_SIGN") { SET P64_YAW_SIGN TO lm_vals["P64_YAW_SIGN"]. }
  IF lm_vals:HASKEY("P66_ROD_SIGN") { SET P66_ROD_SIGN TO lm_vals["P66_ROD_SIGN"]. }
  IF lm_vals:HASKEY("ROD_KEYS") { SET ROD_KEYS TO lm_vals["ROD_KEYS"]. }
  IF lm_vals:HASKEY("ENG_THR_CONT") { SET ENG_THR_CONT TO lm_vals["ENG_THR_CONT"]. }
  IF lm_vals:HASKEY("PLAN_NODES") { SET PLAN_NODES TO lm_vals["PLAN_NODES"]. }
}

// lm_cfg_parse: parse lines with the LM's table (and the CSM's empty one).
FUNCTION lm_cfg_parse {
  PARAMETER file_lines, file_label.
  RETURN cfg_parse(file_lines, LEXICON("COMMON", AGC_COMMON_SETTINGS, "LM", LM_SETTINGS, "CSM", LIST()), lm_cfg_custom@, file_label).
}

// cfg_apply_line: apply one line as an [LM] line. Returns "" when the line was empty, a comment or applied, else the reason
// it was skipped (also added to CFG_WARNINGS).
FUNCTION cfg_apply_line {
  PARAMETER raw_line.
  LOCAL parsed IS lm_cfg_parse(LIST(raw_line), "settings").
  lm_cfg_publish(parsed["VALUES"]).
  IF parsed["WARNINGS"]:LENGTH = 0 { RETURN "". }
  CFG_WARNINGS:ADD(parsed["WARNINGS"][0]).
  RETURN parsed["WARNINGS"][0].
}

// cfg_read_file: apply one whole file; its warnings are added to CFG_WARNINGS. A missing file is not an error.
FUNCTION cfg_read_file {
  PARAMETER cfg_file.
  IF NOT EXISTS(cfg_file) { RETURN. }
  LOCAL parsed IS lm_cfg_parse(OPEN(cfg_file):READALL:STRING:SPLIT(CHAR(10)), cfg_file).
  FOR note_text IN parsed["WARNINGS"] { CFG_WARNINGS:ADD(note_text). }
  lm_cfg_publish(parsed["VALUES"]).
}

// cfg_load: read one file (starts a fresh warning list).
FUNCTION cfg_load {
  PARAMETER cfg_file.
  SET CFG_WARNINGS TO LIST().
  cfg_read_file(cfg_file).
}

// cfg_load_all: read each file of the list in order, so the later file wins (starts a fresh warning list).
FUNCTION cfg_load_all {
  PARAMETER cfg_files.
  SET CFG_WARNINGS TO LIST().
  FOR cfg_file IN cfg_files { cfg_read_file(cfg_file). }
}

cfg_load_all(CFG_PATHS).
