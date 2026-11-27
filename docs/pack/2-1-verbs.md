---
page: 2-1
section: Section 2 | Reference
---
## 2.1 Verbs and alarms

Key VERB, the number, then ENTR. A verb that needs data takes a noun first: `V16 N60 E`.

<!--table vt-->
| Verb | Does |
|---|---|
| == Show and load | |
| V05 | Show the alarm codes (with N09) |
| V04, V06 | Show a noun's registers (V04: V89's option) |
| V16 | Monitor a noun, live |
| V21 to V25 | Load a noun by keys (V21, V22, V23 one register each; V24 two; V25 all three): times, N55, N81, N76, N69 (210), N12 (octal). See {@2-5 2.5} |
| V35 | Lamp test, 5 s |
| V82 | Orbit display (N44), over P00 or any programme. [[PRO]] or `V34E` ends it |
| == Programmes and answers | |
| V37 | Change programme: V37 E, number, E. P12 P20 P25 P30 P32 P33 P34 P35 P40 P41 P42 P47 P51 P63 P68 P70 P71. 00 ends everything |
| V32 | Show a flashing request again |
| V33 | Proceed (same as [[PRO]]) |
| V34 | Terminate: ends a load or a programme prompt. Does nothing if none is pending |
| V50 V97 V99 | Shown by programmes, flashing. You answer, never key them |
| == Rendezvous ({@3-18}) | |
| V56 | End tracking (P20, P25) |
| V83 | Range, range rate and window angle (N54) |
| V89 | Turn an axis to the CSM (N12, N18). P00 only |
| V90 | Out of plane at a time (N16, N90) |
| V93 | The mark count starts again at the next mark |
| == Radar and others | |
| V57 / V58 | Radar updates permitted / inhibited (a flag only; 210 clears it below 50 ft) |
| V59 V60 V76 V77 V80 V81 V95 | Accepted and do nothing (V95 does not stop the marks) |

<!--sheet-->

### Alarms

<!--table vt-->
| Sign | Cause | Do |
|---|---|---|
| OPR ERR | Bad key, or a programme refused | [[RSET]]. Read the warnings first |
| PROG | Alarm raised | `V05 N09 E`, then [[RSET]] |
| 1201, 1202 | Only if the `ALARMS` setting asks for them (executive overflow, as on Apollo 11) | PROG lit and the display restarts. Carry on, [[RSET]] |
| 526 | P20: CSM over 400 nm | 099: [[PRO]] looks again, `V34E` ends P20. {J 210: shown once} |
| 1406 | Time to go did not converge | Carry on. Last value is kept |
| 1703 | Ignition too close. Moved to about 50 s ahead (P12: 30 s) | Check the new time. In P12 the rendezvous timing is lost |
| 1706 | P40: descent stage gone. P42: still on | `V34E`. [[PRO]] looks again |
| 600 to 606 | P32 cannot target CSI | See {@3-12}. V32 starts again |
| 611 | No TPI time for the elevation angle | P33: [[PRO]] keeps the time, V32 back to N13. P34: [[PRO]] starts again |
| 20607 | No path to the aim point (P34, P35, P40 to P42) | The programme ends. Target again |
| V97 | Engine gives no thrust (N62 in P63, N40 in P40, N74 in P12, N63 in an abort) | [[PRO]] retry, [[ENTR]] relight, `V34E` end. In P70 press `0` |
