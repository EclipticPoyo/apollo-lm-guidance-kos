---
page: 2-1
section: Section 2 | Reference
---
## 2.1 Verbs

Key VERB, the number, then ENTR. A verb that needs data takes a noun first: `V16 N60 E`.

<!--table vt-->
| Verb | Does |
|---|---|
| V05 | Show the alarm codes (with N09) |
| V06 | Show a noun's registers |
| V16 | Monitor a noun, live |
| V21 to V25 | Load a noun by keys (V21, V22, V23 one register each; V24 two; V25 all three): N33, N81, N76, N69 (J). See 2.5 |
| V32 | Show a flashing request again |
| V33 | Proceed (same as [[PRO]]) |
| V34 | Terminate: ends a load or a programme prompt. Does nothing if none is pending |
| V35 | Lamp test, 5 s |
| V37 | Change programme: V37 E, number, E. P12 P30 P40 P41 P47 P51 P63 P68. 00 ends the running one |
| V57 / V58 | Radar updates permitted / inhibited (a flag only) |
| V59 V60 V77 | Accepted and do nothing |
| V82 | Orbit display (N44), over P00 or any programme. [[PRO]] or `V34E` ends it |
| V50 V97 V99 | Shown by programmes, flashing. You answer, never key them |

## 2.2 Alarms

<!--table vt-->
| Sign | Cause | Do |
|---|---|---|
| OPR ERR | Bad key, or a programme refused | [[RSET]]. Read the terminal |
| PROG | Alarm raised | `V05 N09 E`, then [[RSET]] |
| 1201, 1202 | Only if the `ALARMS` setting asks for them (executive overflow, as on Apollo 11) | PROG lit and the display restarts. Carry on, [[RSET]] |
| 1406 | Time to go did not converge | Carry on. Last value is kept |
| 1703 | Ignition too close. Moved to about 50 s ahead (P12: 30 s) | Check the new time. In P12 the rendezvous timing is lost |
| 1706 | Descent stage gone | P40 cannot run |
| V97 | Engine gives no thrust (N62 in P63, N40 in P40, N74 in P12) | [[PRO]] retry, [[ENTR]] relight, `V34E` end |
