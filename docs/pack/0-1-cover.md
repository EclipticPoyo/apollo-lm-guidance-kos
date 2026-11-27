---
page: 0-1
section: Contents
---
<div class="cover"><p class="t1">LM Guidance<br>Computer</p><p class="t2">PILOT'S PACK</p></div>

An Apollo Lunar Module guidance computer for Kerbal Space Program, written in kOS for Realism Overhaul on Sol. It recreates what the LM crew saw and did, with the descent guidance ported from Luminary 099 (Apollo 11) and Luminary 210 (Apollo 15 to 17), and the ascent guidance from Luminary 210. It does not emulate AGC hardware.

> CAUTION: Developed and flown on one lander in one set-up (Sol with Mirage, Realism Overhaul, kOS 1.6.0.1). Nothing else has been tested. Fly at your own risk.

## Contents

<!--table toc-->
| Section | Title | Page |
|---|---|---|
| | {@0-2 Landing card} | {@0-2} |
| | {@0-3 Ascent card} | {@0-3} |
| | {@0-4 Abort card} | {@0-4} |
| | {@0-5 Rendezvous card} | {@0-5} |
| | **[PAD forms: write your figures here](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/pads.html)** | [online](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/pads.html) |
| 1 | {@1-1 System} | {@1-1} |
| 2 | {@2-1 Reference: verbs, alarms, nouns, settings, loads, update, refusals} | {@2-1} |
| 3 | {@3-0 Checklists: the index} | {@3-0 3-0} |
| 4 | {@4-1 If something goes wrong} | {@4-1} |
| A | {@A-1 Differences from the real LM, glossary} | {@A-1} |

## How entries are written

<!--table vt-->
| Entry | Means |
|---|---|
| `V37E 63E` | Keys to press. V is VERB, N is NOUN, E is ENTR. This one means VERB 3 7 ENTR 6 3 ENTR. |
| [[PRO]] | A single DSKY button. |
| ~V06 N62~ | What the display shows. |
| `W S` | A KSP flight key. These are read while the KSP window has focus. |
| TIG-0:05, TIG+0:26 | In the margin: time before or after ignition (TIG). |
| FL | The display is flashing: it is waiting for you. |
| **Bold** | In checklists, something you do to the ship: SAS, RCS, throttle, target. |
| {A11} {J} | Your software, picked in the planner: Apollo 11 is 099, J-class is 210. A tagged line is for that one only; 210 lines are blue. Untagged lines are for both. |
| 099, 210 box | Beside a page number or on a bar: that page or section is on that version's rendezvous route. |
| Route diagram | At the foot of a page: the two rendezvous routes. The filled stop is the page you are on. |
| &#8730; | Check that the display or state shown is what you see. In checklists, CONTROL - SETTING lines are actions, and (remarks) are not steps. |
