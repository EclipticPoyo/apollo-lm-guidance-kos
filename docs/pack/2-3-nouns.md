---
page: 2-3
section: Section 2 | Reference
---
## 2.3 Nouns: burns, ascent, orbit, alarms

<!--table nt-->
| Noun | R1 | R2 | R3 |
|---|---|---|---|
| == Burns | | | |
| **N11** | CSI time, hours | minutes | seconds, 0.01 s |
| **N13** | CDH time, hours | minutes | seconds, 0.01 s |
| N18 | Roll, 0.01 deg | Pitch | Yaw (burn attitude) |
| N25 | Checklist code, octal (00051 in P51) | Blank | Blank |
| **N33** | Ignition time, hours | minutes | seconds, 0.01 s |
| **N37** | TPI time, hours | minutes | seconds, 0.01 s |
| **N40** | Time to go, MM SS | Still to gain, 0.1 ft/s | Gained, 0.1 ft/s |
| N42 | Apogee after, 0.1 nm | Perigee after, 0.1 nm | Burn size, 0.1 ft/s |
| **N45** | Marks (P20) | Time to ignition, MM SS | Middle gimbal, 0.01 deg (P32 to P35: -00.01 until the final computation) |
| N52 | Angle the LM travels to the intercept, 0.01 deg | Blank | Blank |
| **N55** | Half orbits from CSI to CDH, whole | TPI elevation angle, 0.01 deg | Central angle, 0.01 deg |
| **N58** | Perilune after TPI, 0.1 nm | TPI delta-v, 0.1 ft/s | Intercept delta-v, 0.1 ft/s |
| **N59** | Delta-v along the sight line, 0.1 ft/s | Right | Down |
| **N75** | Height difference at CDH, 0.1 nm (+ = CSM higher) | Time between burns, MM SS | Second time between burns, MM SS |
| **N81** | Delta-v X, 0.1 ft/s | Y | Z (local vertical) |
| **N82** | CDH delta-v X, 0.1 ft/s | Y | Z (local vertical) |
| N83 | P47 gained X | Y | Z, 0.1 ft/s |
| **N85** | Still to gain X (nose) | Y (right) | Z (window), 0.1 ft/s |

<!--sheet-->

<!--table nt-->
| Noun | R1 | R2 | R3 |
|---|---|---|---|
| == Tracking | | | |
| N12 | Option code, octal (00003 in V89) | 00001 front windows, else top hatch | Blank |
| N16 | V90 time, hours | minutes | seconds, 0.01 s |
| **N54** | Range, 0.01 nm | Range rate, 0.1 ft/s | Window angle, 0.01 deg |
| N90 | Out of plane, 0.01 nm | Its rate, 0.1 ft/s | Bearing of the CSM, 0.01 deg |
| == Ascent and orbit | | | |
| N44 | Apolune, 0.1 nm | Perilune, 0.1 nm | Time of free fall, MM SS |
| **N74** | Time from ignition, MM SS | Yaw after the rise, 0.01 deg | Pitch after the rise, 0.01 deg |
| **N76** | Horizontal speed wanted, 0.1 ft/s | Radial speed wanted, 0.1 ft/s | Cross-range, 0.1 nm |
| **N94** | Still to gain along the thrust axis, 0.1 ft/s | Altitude rate, 0.1 ft/s | Height, ft |
| == Alarms | | | |
| N09 | Code 1, octal | Code 2 | Code 3 |

Shaded rows are the nouns on the flight cards. In P12, P70 and P71 heights are above the landing site. {A11} N63 R1 is the speed in orbit. P12's N74 angles run from 0 to 359.99. In an abort N76 shows the targets the computer chose. N44 heights are above the landing site.
