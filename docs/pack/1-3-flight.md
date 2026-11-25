---
page: 1-3
section: Section 1 | System
---
## 1.4 Flight sequence

<div class="flowrow"><div>Plan<span>RUN plan.</span></div><div>DOI<span>P30 P40</span></div><div>Braking<span>P63</span></div><div>Approach<span>P64</span></div><div>Landing<span>P65 P66</span></div><div>Down<span>P68</span></div></div>

<div class="flowrow"><div>Ascent plan<span>RUN plan.</span></div><div>Lift-off<span>P12</span></div><div>Trim<span>RCS</span></div><div>Orbit<span>V82</span></div></div>

<!--table st-->
| Phase | You | Computer |
|---|---|---|
| Plan | Pick a site. PLAN, SEND. | Finds the DOI burn, PDI and landing times. Writes the PAD. |
| DOI | `V37E 30E`, `V37E 40E`. Work the throttle on MAN. | Turns the ship, ullage, ignition, cut-off. |
| P63 | `V37E 63E`, [[PRO]] twice. | Turns, warps to T-60 s, burns to brake. |
| P64 | [[PRO]], then move the aim point. | Steers to the approach targets. |
| P65 / P66 | Watch, or set the rate of descent. | Nulls horizontal speed. Lands at 3 ft/s. |
| P68 | [[PRO]]. | Confirms the landing position. |
| Ascent plan | Target the CSM. PLAN. | Finds the lift-off time and the targets. Writes the PAD. |
| P12 | `V37E 12E`, key the PAD, [[PRO]]. | Warps, stages, flies the ascent, cuts the engine off. |
| Orbit | Trim with the RCS. `V82E`. | Shows what is left to gain, then apolune and perilune. |

## 1.5 Programmes

<!--table vt-->
| Prog | Role |
|---|---|
| P12 | Powered ascent, from the surface to lunar orbit. |
| P30 | Checks a burn's ignition time and delta-v. Fires nothing. |
| P40 | Flies that burn with the descent engine. |
| P41 | The same burn with the RCS, for a trim. |
| P47 | Thrust monitor for a burn you fly by hand. |
| P51 | Says the IMU's orientation is known. Only needed if `IMU_ALIGN` is REQUIRED. |
| P63 | Braking. |
| P64 | Approach and redesignation. Starts by itself from P63. |
| P65 | Automatic landing. Starts by itself from P64. |
| P66 | You control the rate of descent. You start it, from P63 to P65. |
| P68 | Confirms the landing. Starts at contact, or you key it on the ground. |
