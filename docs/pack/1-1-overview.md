---
page: 1-1
section: Section 1 | System
---
## 1.1 Overview

You run two programs in the kOS terminal, one after the other. The **planner** works out the descent and saves a plan. The **DSKY** loads that plan and flies the burns and the landing. You act only through the DSKY keys and the KSP flight keys. The kOS terminal shows messages and live readouts.

<div class="fig"><div class="figbox"><svg viewBox="0 0 700 150" role="img" aria-label="The planner writes a plan, the DSKY reads it and flies the ship"><defs><marker id="a2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0,0 L10,5 L0,10 z" style="fill:var(--ink)"/></marker></defs><style>.fb{fill:var(--white);stroke:var(--ink);stroke-width:2}.ft{font:700 15px Arimo,Arial,sans-serif;fill:var(--ink);text-anchor:middle;letter-spacing:.06em}.fs{font:400 12px "Courier Prime","Courier New",monospace;fill:var(--ink);text-anchor:middle}.fa{stroke:var(--ink);stroke-width:2;fill:none}.fl{font:700 10.5px Arimo,Arial,sans-serif;fill:var(--ink);text-anchor:middle;letter-spacing:.08em}</style><rect class="fb" x="20" y="30" width="170" height="80"/><text class="ft" x="105" y="62">PLANNER</text><text class="fs" x="105" y="84">RUN plan.</text><line class="fa" x1="190" y1="70" x2="268" y2="70" marker-end="url(#a2)"/><text class="fl" x="229" y="58">THE PLAN</text><rect class="fb" x="270" y="30" width="170" height="80"/><text class="ft" x="355" y="62">DSKY</text><text class="fs" x="355" y="84">RUN dsky.</text><line class="fa" x1="440" y1="70" x2="518" y2="70" marker-end="url(#a2)"/><text class="fl" x="479" y="58">FLIES IT</text><rect class="fb" x="520" y="30" width="160" height="80"/><text class="ft" x="600" y="62">SHIP</text><text class="fs" x="600" y="84">engine, RCS</text><text class="fl" x="105" y="136">BEFORE THE DESCENT</text><text class="fl" x="355" y="136">YOU KEY IT</text><text class="fl" x="600" y="136">KSP VESSEL</text></svg></div><div class="cap">Figure 1-1. <span>Two programs, one ship</span></div></div>

## 1.2 Before you start

- A lander with a kOS processor, a descent engine and RCS thrusters for ullage.
- A bound lunar orbit above the powered-descent altitude, for example 110 km circular.
- No time warp running, and no maneuver nodes you want to keep (or tick "Replace existing maneuver nodes").

> NOTE: The maneuver nodes the planner draws are a picture only. Nothing steers to them.
