// agc_settings.ks -- the generic reader for the settings file of the whole AGC project (0:/agc_config.txt).
//
// The file has sections in square brackets, [LM] and [CSM], and one setting per line: NAME = value. Everything after // is a
// comment, blank lines are ignored, names and values are not case-sensitive. A line before any [section] counts as [LM], so
// the old flat lm/lm_config.txt still reads. This file knows no setting by name: the caller passes a table of settings per
// section (the LM's is in lm/lm_settings.ks) and gets typed values and a list of warnings back. It never stops the script.
//
// cfg_parse(lines, tables, custom, file_label) -> LEXICON("VALUES", section -> (name -> value), "WARNINGS", LIST of text)
//   lines       a LIST of the file's lines (a trailing carriage return and a byte-order mark are tolerated)
//   tables      LEXICON: section name -> LIST of rows. A row is LEXICON("NAME", text, "KIND", kind, "ALLOWED", text, "GROUP", text)
//               kind BOOL (TRUE/FALSE -> Boolean), ENUM (ALLOWED is a comma list -> upper-case text), NUMBER (ALLOWED may be
//               "MIN=0" -> number), SIGN (1 or -1 -> number), TEXT (kept as written), CUSTOM (the delegate checks it -> upper-case text)
//   custom      a delegate custom(name, value_text) that returns "" when the value is good, else the reason it is not
//   file_label  the text that starts each warning, so a warning says which file it came from
// A later line for the same setting wins. A [CSM] line is skipped with "no CSM settings yet" while that table is empty.
//
// [COMMON]: if tables has a "COMMON" entry, its settings do the same job for every computer and are written once. A common
// setting is also accepted under a computer's own section (an old flat file, or a computer overriding the common value) and is
// stored under that section. The caller merges: the computer's own value wins, else the [COMMON] one.

FUNCTION cfg_parse {
  PARAMETER lines, tables, custom, file_label.
  LOCAL values IS LEXICON().
  LOCAL warnings IS LIST().
  FOR table_name IN tables:KEYS { SET values[table_name] TO LEXICON(). }
  LOCAL sect_name IS "LM".
  LOCAL sect_known IS TRUE.
  FOR raw_line IN lines {
    LOCAL text IS raw_line:REPLACE(CHAR(65279), "").
    IF text:CONTAINS("//") { SET text TO text:SUBSTRING(0, text:FIND("//")). }
    SET text TO text:TRIM().
    IF text:STARTSWITH("[") AND text:ENDSWITH("]") {
      SET sect_name TO text:SUBSTRING(1, text:LENGTH - 2):TRIM():TOUPPER.
      SET sect_known TO tables:HASKEY(sect_name).
      IF NOT sect_known { warnings:ADD(cfg_note(file_label, raw_line, "unknown section " + sect_name + ", its lines are skipped")). }
    } ELSE IF text <> "" AND sect_known {
      LOCAL common_rows IS LIST().
      IF tables:HASKEY("COMMON") { SET common_rows TO tables["COMMON"]. }
      LOCAL reason IS cfg_one_line(text, sect_name, tables[sect_name], common_rows, values[sect_name], custom).
      IF reason <> "" { warnings:ADD(cfg_note(file_label, raw_line, reason)). }
    }
  }
  RETURN LEXICON("VALUES", values, "WARNINGS", warnings).
}

// cfg_note: the text of one warning.
FUNCTION cfg_note {
  PARAMETER file_label, raw_line, why.
  RETURN file_label + ": skipped " + CHAR(34) + raw_line:TRIM() + CHAR(34) + ": " + why.
}

// cfg_one_line: read one NAME = value line of a section into section_values. Returns "" when it was good, else the reason.
FUNCTION cfg_one_line {
  PARAMETER text, sect_name, rows, common_rows, section_values, custom.
  IF NOT text:CONTAINS("=") { RETURN "no = in the line". }
  LOCAL eq_pos IS text:FIND("=").
  LOCAL key IS text:SUBSTRING(0, eq_pos):TRIM():TOUPPER.
  LOCAL value IS text:SUBSTRING(eq_pos + 1, text:LENGTH - eq_pos - 1):TRIM().
  LOCAL row IS LEXICON().
  FOR candidate IN rows { IF candidate["NAME"] = key { SET row TO candidate. } }
  IF row:LENGTH = 0 { FOR candidate IN common_rows { IF candidate["NAME"] = key { SET row TO candidate. } } }
  IF row:LENGTH = 0 {
    IF rows:LENGTH = 0 { RETURN "no " + sect_name + " settings yet". }
    RETURN "unknown setting " + key.
  }
  IF value = "" { RETURN "no value for " + key. }
  LOCAL converted IS cfg_convert(row, value, custom).
  IF NOT converted[0] { RETURN converted[1]. }
  SET section_values[key] TO converted[1].
  RETURN "".
}

// cfg_convert: check value (text) against the row's kind. Returns LIST(TRUE, typed value) or LIST(FALSE, reason).
FUNCTION cfg_convert {
  PARAMETER row, value, custom.
  LOCAL name IS row["NAME"].
  LOCAL kind IS row["KIND"].
  LOCAL upper IS value:TOUPPER.
  IF kind = "BOOL" {
    IF upper = "TRUE" { RETURN LIST(TRUE, TRUE). }
    IF upper = "FALSE" { RETURN LIST(TRUE, FALSE). }
    RETURN LIST(FALSE, name + " must be TRUE or FALSE").
  }
  IF kind = "ENUM" {
    LOCAL allowed IS row["ALLOWED"]:SPLIT(",").
    IF allowed:CONTAINS(upper) { RETURN LIST(TRUE, upper). }
    RETURN LIST(FALSE, name + " must be " + cfg_or_list(allowed)).
  }
  IF kind = "TEXT" { RETURN LIST(TRUE, value). }
  IF kind = "CUSTOM" {
    LOCAL why IS custom:CALL(name, value).
    IF why = "" { RETURN LIST(TRUE, upper). }
    RETURN LIST(FALSE, why).
  }
  // NUMBER and SIGN. TONUMBER gives the sentinel when the text is not a number.
  LOCAL not_a_number IS -987654321.
  LOCAL number IS value:TONUMBER(not_a_number).
  IF number = not_a_number { RETURN LIST(FALSE, name + " must be a number"). }
  IF kind = "SIGN" {
    IF number <> 1 AND number <> -1 { RETURN LIST(FALSE, name + " must be 1 or -1"). }
    RETURN LIST(TRUE, number).
  }
  IF row["ALLOWED"]:STARTSWITH("MIN=") {
    LOCAL least IS row["ALLOWED"]:SUBSTRING(4, row["ALLOWED"]:LENGTH - 4):TONUMBER(0).
    IF number < least { RETURN LIST(FALSE, name + " must not be below " + least). }
  }
  RETURN LIST(TRUE, number).
}

// cfg_or_list: "A, B or C" from a LIST of words.
FUNCTION cfg_or_list {
  PARAMETER words.
  IF words:LENGTH = 1 { RETURN words[0]. }
  LOCAL out_text IS "".
  LOCAL index IS 0.
  UNTIL index >= words:LENGTH - 1 {
    IF index > 0 { SET out_text TO out_text + ", ". }
    SET out_text TO out_text + words[index].
    SET index TO index + 1.
  }
  RETURN out_text + " or " + words[words:LENGTH - 1].
}

// AGC_COMMON_SETTINGS: the settings that do the same job for every computer (the [COMMON] section). One row per line in exactly
// this shape: scripts/tests/check_pack.py reads them with a regular expression. LOG is the one logging switch; the LM reads it
// as its LM_LOG (a later CSM would read LOG directly).
GLOBAL AGC_COMMON_SETTINGS IS LIST().
AGC_COMMON_SETTINGS:ADD(LEXICON("NAME", "LOG", "KIND", "BOOL", "ALLOWED", "TRUE,FALSE", "GROUP", "display")).
AGC_COMMON_SETTINGS:ADD(LEXICON("NAME", "DSKY_START", "KIND", "ENUM", "ALLOWED", "BLANK,N60", "GROUP", "display")).
AGC_COMMON_SETTINGS:ADD(LEXICON("NAME", "IMU_ALIGN", "KIND", "ENUM", "ALLOWED", "AUTO,REQUIRED", "GROUP", "burns")).
AGC_COMMON_SETTINGS:ADD(LEXICON("NAME", "ALARMS", "KIND", "CUSTOM", "ALLOWED", "", "GROUP", "alarms")).
