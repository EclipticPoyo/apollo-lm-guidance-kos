---
page: 2-4
section: Section 2 | Reference
---
## 2.5 Loads and the PAD

The planner writes the PAD, the sheet of numbers Mission Control would have read up, as key presses. SEND puts them in `0:/lm/uplink.txt` and the DSKY presses them at five a second in P00, with UPLINK ACTY lit. With Skip simulated uplink ticked, the DSKY loads the plan at start instead.

<div class="fig"><div class="photo"><img src="images/planner.png" alt="The planner window with its PAD"></div><div class="cap">Figure 2-1. <span>The planner: site, options, PLAN and SEND, the PAD</span></div></div>

The PAD loads three things with V71 blocks: the site (`RLS`), the landing time (`TLAND`) and the DOI burn (delta-v and ignition time). Each block shows its address, the same numbers in plain form to check against the display, and its keys. The plane change is the CSM's burn and is only noted.

### Keyed load (V21 to V25)

<!--table st-->
| Keys | Does |
|---|---|
| `V25 N33 E` | Load N33 (burn time) R1 to R3. `V21` to `V23` load one register, `V24` loads R1 and R2 |
| `V25 N81 E` | Load N81 (delta-v) |
| `V25 N76 E` | Load N76 (ascent targets, from the ascent PAD) |
| `V25 N69 E` | J-class only: landing site correction |

For each register key a sign (required), all five digits and [[ENTR]]: `+00025`. The load is stored after the last [[ENTR]] and the display goes to `V16` on that noun.

- Fewer than five digits is OPR ERR and the load waits. [[PRO]] leaves a register as it was. [[CLR]] drops what you keyed.
- `V34E` abandons the load. [[RSET]] leaves it running.
- N33: `+00083 +00003 +02000` is 83 h 03 min 20.00 s from the clock zero. N81 is in tenths of ft/s along local vertical axes (X along the track, Y opposite the orbit normal, Z down).
- N76: `+55349 +00322 -00012` is 5534.9 ft/s horizontal, 32.2 ft/s radial and 1.2 nm of cross-range. The ascent PAD is keyed, as the crew did; there is no ascent uplink.
