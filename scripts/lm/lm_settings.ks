// lm_settings.ks -- reads the pilot's settings file 0:/lm/lm_config.txt and overrides the matching constants.
//
// lm_constants.ks loads this at its end, so every constant has its default there first, and the file only changes what it
// names. A missing file changes nothing. One setting per line: NAME = value. Everything after // is a comment, blank lines
// are ignored, and names are not case-sensitive. A line with an unknown name or a bad value is skipped and noted in the
// list CFG_WARNINGS (dsky.ks prints them at start-up); it never stops the script.
//
// Only the settings in CFG_NAMES below can be set from the file. The tuning constants stay in lm_constants.ks.
// KerboScript cannot set a global by a name held in text, so cfg_apply_line has one branch per setting.

GLOBAL CFG_PATH IS "0:/lm/lm_config.txt".
GLOBAL CFG_WARNINGS IS LIST().
GLOBAL CFG_NAMES IS LIST("LM_LOG", "P63_WINDOW_MODE", "P63_WARP_LEAD_S", "P64_PITCH_SIGN", "P64_YAW_SIGN", "P66_ROD_SIGN", "BODY_NAME").

// cfg_apply_line: apply one line of the file. Returns "" when the line was empty, a comment or applied, else the reason it
// was skipped (also added to CFG_WARNINGS).
FUNCTION cfg_apply_line {
  PARAMETER raw_line.
  LOCAL text IS raw_line.
  IF text:CONTAINS("//") { SET text TO text:SUBSTRING(0, text:FIND("//")). }
  SET text TO text:TRIM().
  IF text = "" { RETURN "". }
  IF NOT text:CONTAINS("=") { RETURN cfg_skip(raw_line, "no = in the line"). }
  LOCAL eq_pos IS text:FIND("=").
  LOCAL key IS text:SUBSTRING(0, eq_pos):TRIM():TOUPPER.
  LOCAL value IS text:SUBSTRING(eq_pos + 1, text:LENGTH - eq_pos - 1):TRIM().
  IF NOT CFG_NAMES:CONTAINS(key) { RETURN cfg_skip(raw_line, "unknown setting " + key). }
  IF value = "" { RETURN cfg_skip(raw_line, "no value for " + key). }
  IF key = "LM_LOG" {
    IF value:TOUPPER = "TRUE" { SET LM_LOG TO TRUE. RETURN "". }
    IF value:TOUPPER = "FALSE" { SET LM_LOG TO FALSE. RETURN "". }
    RETURN cfg_skip(raw_line, "LM_LOG must be TRUE or FALSE").
  }
  IF key = "P63_WINDOW_MODE" {
    IF value:TOUPPER = "UP" OR value:TOUPPER = "KEEP" { SET P63_WINDOW_MODE TO value:TOUPPER. RETURN "". }
    RETURN cfg_skip(raw_line, "P63_WINDOW_MODE must be UP or KEEP").
  }
  IF key = "BODY_NAME" { SET BODY_NAME TO value. RETURN "". }
  // The rest are numbers. TONUMBER gives the sentinel when the text is not a number.
  LOCAL not_a_number IS -987654321.
  LOCAL number IS value:TONUMBER(not_a_number).
  IF number = not_a_number { RETURN cfg_skip(raw_line, key + " must be a number"). }
  IF key = "P63_WARP_LEAD_S" {
    IF number < 0 { RETURN cfg_skip(raw_line, "P63_WARP_LEAD_S must not be negative"). }
    SET P63_WARP_LEAD_S TO number. RETURN "".
  }
  // The three sign settings are +1 or -1.
  IF number <> 1 AND number <> -1 { RETURN cfg_skip(raw_line, key + " must be 1 or -1"). }
  IF key = "P64_PITCH_SIGN" { SET P64_PITCH_SIGN TO number. }
  IF key = "P64_YAW_SIGN" { SET P64_YAW_SIGN TO number. }
  IF key = "P66_ROD_SIGN" { SET P66_ROD_SIGN TO number. }
  RETURN "".
}

// cfg_skip: note why a line was skipped; returns the note.
FUNCTION cfg_skip {
  PARAMETER raw_line, why.
  LOCAL skip_note IS "lm_config.txt: skipped " + CHAR(34) + raw_line:TRIM() + CHAR(34) + ": " + why.
  CFG_WARNINGS:ADD(skip_note).
  RETURN skip_note.
}

// cfg_load: read the whole file and apply every line. A missing file is not an error.
FUNCTION cfg_load {
  PARAMETER cfg_file.
  SET CFG_WARNINGS TO LIST().
  IF NOT EXISTS(cfg_file) { RETURN. }
  FOR file_line IN OPEN(cfg_file):READALL:STRING:SPLIT(CHAR(10)) { cfg_apply_line(file_line). }
}

cfg_load(CFG_PATH).
