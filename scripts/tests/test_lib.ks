// test_lib.ks -- small test helpers shared by the planner pad tests (test_plan.ks).
// Same behaviour as the helpers inside test_math.ks (which is left as it is).
//   test_begin(log_path)  start a fresh log file and reset the counters
//   report(text)          print a line and append it to the log
//   assert_near / assert_vec / assert_true   record PASS or FAIL
//   test_end()            print and log "TESTS: N passed, M failed"

GLOBAL TESTS_PASSED IS 0.
GLOBAL TESTS_FAILED IS 0.
GLOBAL TEST_LOG IS "0:/lm/test.log".

FUNCTION test_begin {
  PARAMETER log_path.
  SET TEST_LOG TO log_path.
  SET TESTS_PASSED TO 0.
  SET TESTS_FAILED TO 0.
  // LOG appends, so delete the old file first.
  IF EXISTS(TEST_LOG) { DELETEPATH(TEST_LOG). }
}

FUNCTION report {
  PARAMETER text.
  PRINT text.
  LOG text TO TEST_LOG.
}

// assert_near: pass when |actual - expected| <= tol.
FUNCTION assert_near {
  PARAMETER name, actual, expected, tol.
  IF ABS(actual - expected) <= tol {
    report("PASS " + name).
    SET TESTS_PASSED TO TESTS_PASSED + 1.
  } ELSE {
    report("FAIL " + name + " got " + actual + " expected " + expected).
    SET TESTS_FAILED TO TESTS_FAILED + 1.
  }
}

// assert_vec: two vectors are near when the length of their difference is within tol.
FUNCTION assert_vec {
  PARAMETER name, actual, expected, tol.
  assert_near(name, (actual - expected):MAG, 0, tol).
}

FUNCTION assert_true {
  PARAMETER name, condition.
  IF condition {
    report("PASS " + name).
    SET TESTS_PASSED TO TESTS_PASSED + 1.
  } ELSE {
    report("FAIL " + name).
    SET TESTS_FAILED TO TESTS_FAILED + 1.
  }
}

FUNCTION test_end {
  report("TESTS: " + TESTS_PASSED + " passed, " + TESTS_FAILED + " failed").
}
