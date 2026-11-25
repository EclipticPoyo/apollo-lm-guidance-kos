---
page: 1-3
section: Section 1 | System
---
## 1.4 Flight sequence

<div class="flowrow"><div>Plan<span>RUN plan.</span></div><div>DOI<span>P30 P40</span></div><div>Braking<span>P63</span></div><div>Approach<span>P64</span></div><div>Landing<span>P65 P66</span></div><div>Down<span>P68</span></div></div>

<!--table st-->
| Phase | You | Computer |
|---|---|---|
| Plan | Pick a site. PLAN, SEND. | Finds the DOI burn, PDI and landing times. Writes the PAD. |
| DOI | `V37E 30E`, `V37E 40E`. Work the throttle on MAN. | Turns the ship, ullage, ignition, cut-off. |
| P63 | `V37E 63E`, [[PRO]] twice. | Turns, warps to T-60 s, burns to brake. |
| P64 | [[PRO]], then move the aim point. | Steers to the approach targets. |
| P65 / P66 | Watch, or set the rate of descent. | Nulls horizontal speed. Lands at 3 ft/s. |
| P68 | [[PRO]]. | Confirms the landing position. |

## 1.5 Programmes

<!--table vt-->
| Prog | Role |
|---|---|
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

## 1.6 Software profile

The planner's menu picks the profile and saves it with the plan.

| | Apollo 11 (Luminary 099) | J-class (Luminary 210) |
|---|---|---|
| Pad loads | Apollo 11 | Apollo 17 |
| Redesignation | 0.5 deg and 2 deg a click | 1 deg a click, both axes |
| P65 | Yes | None. P64 hands to P66 under 12 s to go. |
| P66 | Holds your rate | Also nulls horizontal speed by itself |
