---
page: 2-2
section: Section 2 | Reference
---
## 2.2 Nouns: descent

Each register is a sign and five digits with no decimal point. Scale the digits by the unit in the table.

<div class="regs">
<div><span class="reg">+01234</span><span>in 0.1 ft/s is 123.4 ft/s</span></div>
<div><span class="reg">+01234</span><span>in 0.1 nm is 123.4 nm</span></div>
<div><span class="reg">-00030</span><span>descent rate in 0.1 ft/s is 3.0 ft/s down (negative is down)</span></div>
</div>

<!--table nt-->
| Noun | R1 | R2 | R3 |
|---|---|---|---|
| == Descent | | | |
| N43 | Latitude, 0.01 deg | Longitude, 0.01 deg | Height, 0.1 nm |
| **N60** | Horizontal speed, 0.1 ft/s {J Forward speed, the way the window faces} | Descent rate, 0.1 ft/s | Height, ft |
| N61 | Braking time to go, MM SS | Time to ignition, MM SS | Out of plane, 0.1 nm |
| **N62** | Speed along burn, 0.1 ft/s | Time to go, MM SS | Delta-v gained, 0.1 ft/s |
| **N63** | Speed along burn, 0.1 ft/s {J Radar minus calculated height, ft} | Descent rate, 0.1 ft/s | Height, ft |
| **N64** | Seconds left, look angle (TT LL) | Descent rate, 0.1 ft/s | Height, ft |
| N66 | Radar height, ft | Antenna position (1, then 2 from P64) | Blank |
| N67 | Radar speed along X, ft/s | Along Y | Along Z |
| N68 | Range to site, 0.1 nm {J Downrange, 0.1 nm} | Braking time to go, MM SS | Height difference, ft {J Speed over the surface, 0.1 ft/s} |
| N69 (210) | Site correction downrange, ft | Crossrange | Up |
| N92 (210) | Thrust wanted, whole percent | Descent rate, 0.1 ft/s | Height, ft |

Shaded rows are the nouns on the flight cards. N66 and N67 come from the simulated radar and read zero above 12 km. (210) marks Luminary 210 only: load N69 with `V25 N69 E`; P63 adds it once at its start, then clears it.
