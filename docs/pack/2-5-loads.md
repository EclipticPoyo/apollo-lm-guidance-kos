---
page: 2-5
section: Section 2 | Reference
---
## 2.5 Loads and the PAD

The planner writes the PAD, the sheet of numbers Mission Control would have read up, as key presses. SEND puts them in `0:/lm/uplink.txt` and the DSKY presses them at five a second in P00, with UPLINK ACTY lit. With Skip simulated uplink ticked, the DSKY loads the plan at start instead.

<div class="fig"><div class="photo small"><img src="images/planner.png" alt="The planner window before PLAN"></div><div class="cap">Figure 2-1. <span>The planner: site, options, PLAN and SEND, and where the PAD appears</span></div></div>

The PAD loads three things with V71 blocks: the site (`RLS`), the landing time (`TLAND`) and the DOI burn (delta-v and ignition time). Each block shows its address, the same numbers in plain form to check against the display, and its keys. The plane change is the CSM's burn and is only noted.

The **ascent PAD** has N33, N76 and the rendezvous times: CSI (N11) and TPI (N37); on 210 TPI, then a fallback set. With Skip simulated uplink ticked there, P12 fills N33, N76, N11 and N37 (210: N11 zero). Key a fallback by hand, after `V37E 12E`.

### Keyed load (V21 to V25)

<!--table st-->
| Keys | Does |
|---|---|
| `V25 N33 E` | Load N33 (burn time) R1 to R3. `V21` to `V23` load one register, `V24` loads R1 and R2 |
| `V25 N81 E` | Load N81 (delta-v) |
| `V25 N11 E`, `V25 N13 E`, `V25 N37 E` | Load the CSI, CDH or TPI time, keyed as N33 |
| `V25 N55 E` | Load N55: half orbits (0 to 99), TPI elevation and central angle (0 to 359.99) |
| `V25 N16 E` | Load N16 (V90's time), keyed as N33 |
| `V22 N12 E` | Load V89's option: octal digits, no sign (`2E`) |
| `V25 N76 E` | Load N76 (ascent targets, from the ascent PAD) |
| `V25 N69 E` | 210 only: landing site correction |

For each register key a sign (required), all five digits and [[ENTR]]: `+00025`. The load is stored after the last [[ENTR]] and the display goes to `V16` on that noun.

- Fewer than five digits is OPR ERR and the load waits. [[PRO]] leaves a register as it was, [[CLR]] drops what you keyed, `V34E` abandons the load ([[RSET]] does not).
- N33: `+00083 +00003 +02000` is 83 h 03 min 20.00 s from the clock zero. N81 is in tenths of ft/s along local vertical axes (X along the track, Y opposite the orbit normal, Z down). A change keyed at N81 in P34 or P35 moves the aim point at its [[PRO]].
- N76: `+55349 +00322 -00012` is 5534.9 ft/s horizontal, 32.2 ft/s radial and 1.2 nm of cross-range. There is no ascent uplink.
