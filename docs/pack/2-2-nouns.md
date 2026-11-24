---
page: 2-2
section: Section 2 | Reference
---
## 2.3 Nouns

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
| N60 | Horizontal speed, 0.1 ft/s | Descent rate, 0.1 ft/s | Height, ft |
| N61 | Braking time to go, MM SS | Time to ignition, MM SS | Out of plane, 0.1 nm |
| N62 | Speed along burn, 0.1 ft/s | Time to go, MM SS | Delta-v gained, 0.1 ft/s |
| N63 | Speed along burn, 0.1 ft/s | Descent rate, 0.1 ft/s | Height, ft |
| N64 | Seconds left, look angle (TT LL) | Descent rate, 0.1 ft/s | Height, ft |
| N66 | Radar height, ft | Antenna position (1, then 2 from P64) | Blank |
| N67 | Radar speed along X, ft/s | Along Y | Along Z |
| N68 | Range to site, 0.1 nm | Braking time to go, MM SS | Height difference, ft |
| N69 (J) | Site correction downrange, ft | Crossrange | Up |
| N92 (J) | Thrust wanted, whole percent | Descent rate, 0.1 ft/s | Height, ft |
| == Burns | | | |
| N18 | Roll, 0.01 deg | Pitch | Yaw (burn attitude) |
| N25 | Checklist code, octal (00051 in P51) | Blank | Blank |
| N33 | Ignition time, hours | minutes | seconds, 0.01 s |
| N40 | Time to go, MM SS | Still to gain, 0.1 ft/s | Gained, 0.1 ft/s |
| N42 | Apogee after, 0.1 nm | Perigee after, 0.1 nm | Burn size, 0.1 ft/s |
| N45 | Marks (0) | Time to ignition, MM SS | Middle gimbal, 0.01 deg |
| N81 | Delta-v X, 0.1 ft/s | Y | Z (local vertical) |
| N83 | P47 gained X | Y | Z, 0.1 ft/s |
| N85 | Still to gain X (nose) | Y (right) | Z (window), 0.1 ft/s |
| == Alarms | | | |
| N09 | Code 1, octal | Code 2 | Code 3 |

N66 and N67 come from the simulated radar and read zero above 12 km. (J) marks J-class only. In J-class, N60 R1 is the forward speed (along the way the window faces), N63 R1 is radar height minus calculated height (ft), and N68 R1 is downrange (0.1 nm) with R3 the speed over the surface (0.1 ft/s). Load N69 with `V25 N69 E`; P63 adds it to the site once at start, then clears it.
