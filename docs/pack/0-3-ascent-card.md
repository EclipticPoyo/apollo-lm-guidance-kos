---
page: 0-3
section: Ascent card
---
## Ascent card: a normal ascent

The short version of {@3-10} and {@3-11}. Details and branches are in the checklists.

```checklist
legend
band: PLAN | landed, CSM in orbit
- | MAP VIEW | **Target the CSM**
- | TERMINAL | RUN plan.
- | PLANNER | Ascent, PLAN, write down the PAD (CARD: LM Ascent PAD, times too), close
band: P12 | {@3-10}  /  **SAS off, throttle zero**
- | TERMINAL | RUN dsky.
- | DSKY | V37E 12E
- | N33 FL | V25 N33 E (PAD). PRO
- | N76 FL | V25 N76 E (PAD). PRO
v: V06 N74, warps to T-60 s
- TIG-0:05 | V99 N74 FL | PRO
band: ASCENT | {@3-11}
v: Stages, lights
[A11] v: V06 N63
[J] v: V06 N94
n: Nothing to key. Q / E turns the ship after the windows-down time
v: Cut-off
[A11] v: V16 N63 FL
[J] v: V16 N94 FL
- | PRO |
band: ORBIT | {@3-11}
- | N85 FL | Trim R1-R3 to near zero. PRO
- | DSKY | V82E
v: Apolune, perilune. PRO
band: NEXT | rendezvous
[A11] - NEXT | CSI | Turn to page {@3-12}
[J] - NEXT | TPI | Skip to page {@3-15}
[J] - NEXT | CSI | Fallback lift-off: turn to page {@3-12}
```

> CAUTION: Never stage by hand. V37 during the ascent turns the engine off.
