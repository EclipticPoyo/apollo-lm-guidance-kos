---
page: 1-1
section: Section 1 | System
---
## 1.1 Overview and flight sequence

You run two programs in the kOS terminal, one after the other. The **planner** (`RUN plan.`) works out the descent, or the ascent from the surface, and saves a plan. The **DSKY** (`RUN dsky.`) loads that plan and flies it. You act through the DSKY keys and the KSP flight keys. While the DSKY runs, the terminal shows live readouts at the top, then **warnings** (stay until [[RSET]] or the next V37) and **messages**. All of them are also in `0:/lm/logs/dsky.log`.

### Before you start

<div class="need" markdown="1">

- A lander with a kOS processor, a descent engine and RCS thrusters for ullage.
- Nothing on the Abort action group (`Backspace`) or action group 10 (`0`): they are the abort controls.
- A bound lunar orbit above the powered-descent altitude, for example 110 km circular.
- No time warp, and no manoeuvre nodes you want to keep (or tick "Replace nodes").
- Ascent: landed, a CSM in lunar orbit, an ascent engine never decoupled, and the kOS processor on that stage.
- Software, picked in the planner: Luminary 099 (the menu's Apollo 11: Apollo 11 pad loads, coelliptic rendezvous) or 210 (J-class: Apollo 17 pad loads, short rendezvous). Checklists tag the differences.

</div>

```strips
bar: Descent | {@3-1} to {@3-8}
- Plan | RUN plan. | Pick a site. PLAN, SEND. | Finds the DOI burn, PDI and landing times. Writes the PAD.
- DOI | P30 P40 | `V37E 30E`, `V37E 40E`. Work the throttle. | Turns the ship, ullage, ignition, cut-off.
- Braking | P63 | `V37E 63E`, [[PRO]] twice. | Turns, warps to T-60 s, burns to brake.
- Approach | P64 | [[PRO]], then move the aim point. | Steers to the approach targets.
- Landing | P65 P66 P68 | Watch, or set the rate of descent. [[PRO]] when down. | Nulls horizontal speed. Lands at 3 ft/s. P68 confirms the position: it starts at contact, or you key it on the ground.
bar: Abort and ascent | {@3-9} to {@3-11}
- Lift-off | RUN plan. P12 | Target the CSM, PLAN. `V37E 12E`, key the PAD, [[PRO]]. | Finds the lift-off time and targets. Warps, stages, flies, cuts off.
- Orbit | V82 | Trim with the RCS. `V82E`. | Shows what is left to gain, then apolune and perilune.
- Abort | P70 P71 | `Backspace` or `0`, once. | Takes the controls and flies back to orbit.
bar: Rendezvous | {@3-12} to {@3-18}
- {A11} burns | P32 to P35 | CSI, CDH, TPI, then the midcourses. Target each, then fly it. | Targets them from the two orbits.
- [J] {J} burns | P34 P35 | TPI, then the midcourses. No CSI or CDH, except on the fallback. | Targets them from the two orbits.
- Braking | P20 | `V37E 20E`. Brake at the gates by hand, close the DSKY, dock. | Holds the windows on the CSM, shows range, range rate and drift, and says when to dock.
- Tracking | P20 P25 | `V37E 20E`, answer `V50 N18`. | Points the windows at the CSM underneath those, and counts marks.
```

Outside the sequence: **P47** monitors a burn you fly by hand. **P51** says the IMU's orientation is known, and is only needed if `IMU_ALIGN` is REQUIRED. The planner's manoeuvre nodes are a picture only: nothing steers to them.
