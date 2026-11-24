// tig_node.ks -- prints the N33 keys (TIG) for the next maneuver node, for the 1.4 batch 1 VELOCITYAT probe.
// RUNPATH("0:/tests/tig_node.ks").  TIG is the AGC clock time: MISSIONTIME + time to the node (no clock.txt = zero is TIME - MISSIONTIME).
// Also written to 0:/lm/logs/tig_node.log so it can be read without a screenshot.
IF EXISTS("0:/lm/logs/tig_node.log") { DELETEPATH("0:/lm/logs/tig_node.log"). }
FUNCTION tn_say {
  PARAMETER text.
  PRINT text.
  LOG text TO "0:/lm/logs/tig_node.log".
}
IF NOT HASNODE {
  tn_say("No maneuver node. Make one first.").
} ELSE {
  LOCAL tig_s IS MISSIONTIME + NEXTNODE:ETA.
  LOCAL hours IS FLOOR(tig_s / 3600).
  LOCAL minutes IS FLOOR(MOD(tig_s, 3600) / 60).
  LOCAL hundredths IS ROUND(MOD(tig_s, 60) * 100).
  tn_say("Node is " + ROUND(NEXTNODE:ETA) + " s ahead (MISSIONTIME " + ROUND(MISSIONTIME) + ", UT " + ROUND(TIME:SECONDS) + ").").
  tn_say("Key:  V25 N33 E").
  tn_say("  R1  +" + hours:TOSTRING:PADLEFT(5):REPLACE(" ", "0") + "  E").
  tn_say("  R2  +" + minutes:TOSTRING:PADLEFT(5):REPLACE(" ", "0") + "  E").
  tn_say("  R3  +" + hundredths:TOSTRING:PADLEFT(5):REPLACE(" ", "0") + "  E").
  tn_say("Then V25 N81 E:  -00328 E  +00000 E  +00000 E").
}
