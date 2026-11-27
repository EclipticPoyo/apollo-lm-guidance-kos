---
page: 3-17
section: Section 3 | Checklist: Rendezvous
---
## 3.17 Rendezvous: braking and docking

By hand, after the second midcourse: P20 holds the windows on the CSM, the drift gauge shows the rest. Not flown this way.

```checklist
band: SET UP | P20, after the second midcourse
- | SHIP | **RCS on, SAS off**
- | DSKY | V37E 20E
- | V50 N18 FL | PRO turns the front windows to the CSM; when it flashes again, ENTR
n: It comes back if the windows get more than 15 deg off the CSM: PRO. If only KEY REL lights, press K
v: Drift gauge, right of the DSKY: LOS RATE, with RANGE, RATE (- closing) and the next gate
if: YOU WANT THE DELTA-V COUNTED (INSTEAD OF P20)
  - DSKY | V37E 47E: V16 N83, 0.1 ft/s gained. R1 nose, R2 right, R3 window side. ENTR zeroes it
  - SHIP | **SAS on**, front windows on the CSM by hand: P47 does not point (P47: TRACKING OFF: POINT BY HAND)
end
band: DRIFT | from the 6000 ft (1830 m) gate to docking
n: Further out leave small drifts: on a good intercept the line turns, up to about 0.55 mrad/s (Apollo 11's chart)
- | LEVEL NEEDLE UP, DOWN | H up, N down
- | UPRIGHT NEEDLE RIGHT, LEFT | L right, J left
- | SCALE | 20 mrad/s at first. 2 mrad/s when the needles hardly move
n: Thrust until the needle is at the middle. +Z OFF THE CSM: point the windows at it
band: BRAKING GATES | slow down in steps as the range falls
n: By each range in the margin, be closing no faster than the speed beside it. The gauge names the next gate
n: R1, R2: V16 N54 (V83E, PRO ends it) there. R1 range 0.01 nm, R2 range rate 0.1 ft/s, minus closing
gate: 6000 FT (1830 m) | 30 ft/s (9.1 m/s) | R1 +00099 | R2 -00300
gate: 3000 FT (915 m) | 20 ft/s (6.1 m/s) | R1 +00049 | R2 -00200
gate: 1500 FT (460 m) | 10 ft/s (3 m/s) | R1 +00025 | R2 -00100
[A11] gate: 600 FT (180 m) | 5 ft/s (1.5 m/s) | R1 +00010 | R2 -00050
[J] gate: 500 FT (150 m) | 5 ft/s (1.5 m/s) | R1 +00008 | R2 -00050
- | TRANSLATION | K slows the closing, I speeds it up (front windows on the CSM)
band: DOCKING | from about 100 ft (30 m)
- | TRANSLATION | Slow to under 0.5 ft/s (0.15 m/s)
v: Terminal: WITHIN 100 FT: SAS ON, CLOSE THE DSKY
- | SHIP | **SAS on**
- | DSKY | **X, YES**: closes it, ending P20 or P47
- | KSP | Dock with KSP's controls, from the LM or the CSM
```

> CAUTION: A good intercept is a collision course: if you cannot slow in time, translate sideways. No physics warp within 8200 ft (2.5 km) of the CSM: KSP makes it jump (the screen warns).

> NOTE: The message is given once, with P20, P25 or P47 running, when the range has been over 500 ft (150 m) and is then within 100 ft (30 m) at under 0.5 ft/s (0.15 m/s). The gauge shows within 40 nm (74 km) of the CSM ({@1-2 1.2}). The computer does not fly the docking.
