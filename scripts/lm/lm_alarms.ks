// lm_alarms.ks -- the scripted alarms of the ALARMS setting (pure, no dependencies). Real Apollo 11 hit program alarms 1202 and 1201 in
// the descent; the DSKY can replay them so the pilot meets the alarm display (PROG lamp, N09, RSET, the display restart), not fly with them
// as a failure. A schedule is a LIST of LIST(seconds after ignition, code), sorted by time.
//   OFF             no alarms (the default)
//   A11             the Apollo 11 pattern, on the A11 profile only: 1202 at 301 s, 1202 at 364 s, 1201 at 560 s, 1202 at 585 s, 1202 at 600 s
//   1202@315,1201@548   an own list: four-digit code, @, seconds after ignition
// Departure: the real alarms came from the rendezvous radar's data overloading the computer; here they are a timetable and the computer is
// not slowed (a restart reshows the display only).

// alarm_script_parse: text (the setting) and profile ("A11" or "J") -> the schedule, or FALSE when the text is not valid.
FUNCTION alarm_script_parse {
  PARAMETER text, profile.
  LOCAL clean IS text:TRIM():TOUPPER.
  LOCAL sched IS LIST().
  IF clean = "OFF" OR clean = "" { RETURN sched. }
  IF clean = "A11" {
    IF profile = "A11" {
      sched:ADD(LIST(301, 1202)).
      sched:ADD(LIST(364, 1202)).
      sched:ADD(LIST(560, 1201)).
      sched:ADD(LIST(585, 1202)).
      sched:ADD(LIST(600, 1202)).
    }
    RETURN sched.
  }
  LOCAL not_a_number IS -987654321.
  FOR item IN clean:SPLIT(",") {
    LOCAL pair IS item:TRIM():SPLIT("@").
    IF pair:LENGTH <> 2 { RETURN FALSE. }
    LOCAL code_text IS pair[0]:TRIM().
    LOCAL code IS code_text:TONUMBER(not_a_number).
    LOCAL seconds IS pair[1]:TRIM():TONUMBER(not_a_number).
    IF code_text:LENGTH <> 4 OR code = not_a_number OR code < 0 OR seconds = not_a_number OR seconds < 0 { RETURN FALSE. }
    // Insert in time order (a later time after an equal one keeps the typed order).
    LOCAL at IS sched:LENGTH.
    UNTIL at = 0 { IF sched[at - 1][0] > seconds { SET at TO at - 1. } ELSE { BREAK. } }
    sched:INSERT(at, LIST(seconds, code)).
  }
  RETURN sched.
}

// alarm_script_due: the codes whose time t satisfies t_last < t <= t_now, in time order.
FUNCTION alarm_script_due {
  PARAMETER sched, t_last, t_now.
  LOCAL due IS LIST().
  FOR entry IN sched { IF entry[0] > t_last AND entry[0] <= t_now { due:ADD(entry[1]). } }
  RETURN due.
}
