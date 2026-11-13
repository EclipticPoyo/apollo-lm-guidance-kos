// run_all.ks -- runs every pad test in turn and prints one summary line per test.
//   RUN pad.                       (the one-line stub pad.ks in Ships/Script runs this file)
//   RUNPATH("0:/tests/run_all.ks").
// The tests are the ones that need no flight: test_core, test_config, test_math, test_plan, test_p63, test_p64, test_p65. Each writes its own
// log under 0:/lm/logs/ (test_*.log); this script reads the last line of each ("TESTS: N passed, M failed") and writes the
// summary to 0:/lm/logs/tests_summary.log. If a test stops with an error, the summary says so and the next test still runs.

LOCAL ra_names IS LIST("test_core", "test_config", "test_math", "test_plan", "test_p63", "test_p64", "test_p65").
LOCAL ra_summary IS "0:/lm/logs/tests_summary.log".
IF EXISTS(ra_summary) { DELETEPATH(ra_summary). }

// ra_last_line: the last non-empty line of a log file, or "no log" when the file is missing.
FUNCTION ra_last_line {
  PARAMETER log_path.
  IF NOT EXISTS(log_path) { RETURN "no log written". }
  LOCAL last_text IS "".
  FOR line_text IN OPEN(log_path):READALL:STRING:SPLIT(CHAR(10)) {
    LOCAL trimmed IS line_text:TRIM().
    IF trimmed <> "" { SET last_text TO trimmed. }
  }
  RETURN last_text.
}

LOCAL ra_failed IS FALSE.
FOR ra_name IN ra_names {
  LOCAL ra_log IS "0:/lm/logs/" + ra_name + ".log".
  IF EXISTS(ra_log) { DELETEPATH(ra_log). }       // so a test that dies early cannot show an old result
  PRINT "Running " + ra_name + " ...".
  RUNPATH("0:/tests/" + ra_name + ".ks").
  LOCAL ra_line IS ra_name + ": " + ra_last_line(ra_log).
  IF NOT ra_line:CONTAINS("0 failed") { SET ra_failed TO TRUE. }
  PRINT ra_line.
  LOG ra_line TO ra_summary.
}
IF ra_failed {
  PRINT "SOME TESTS DID NOT PASS. Details: 0:/lm/logs/<test>.log and " + ra_summary.
} ELSE {
  PRINT "ALL TESTS PASSED.".
}
