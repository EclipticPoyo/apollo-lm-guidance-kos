---
page: 3-9
section: Section 3 | Checklist: Abort
---
## 3.9 Aborts: P70 and P71

P70 flies to orbit on the descent engine: nothing separates. P71 drops the descent stage and flies on the ascent engine. One press starts either: no arming, no [[PRO]].

<!--table st-->
| When you are | For P70 (descent engine) press | For P71 (abort stage) press |
|---|---|---|
| In P63 to P66, from P63 ignition | `Backspace` (or `V37E 70E`) | `0` |
| Already in P70 | (flying it) | `0` |
| Landed, at P68, before [[PRO]] | Not possible | `0` |

No abort is possible before P63 ignition, after [[PRO]] or `V34E` at P68, in P71, or after an abort's cut-off. `V37E 71E` never stages: it works only if the descent stage has already gone.

```checklist
band: IN THE ABORT | P70 or P71
v: PROG 70 or 71. Time warp cancelled. What you were keying is dropped
[A11] v: V06 N63
[J] v: V06 N94
if: BELOW 25,000 FT (7.6 km) ABOVE THE SITE
  v: Vertical rise first, then pitch over, windows towards the surface
  - Q / E | Turn about the thrust axis from 10 s after the pitch-over
end
if: HIGH AND STILL BRAKING
  v: Ship turns up through the vertical, then onto the new direction
  - Q / E | Yours after the turn
end
- | SAS | **On**: ATT HOLD, you fly the attitude. **Off**: the computer steers again
- ANY TIME | DSKY | V16 N76E. KEY REL to go back
v: Targets: horizontal and radial speed 0.1 ft/s, cross-range 0.1 nm
if: V97 N63 FL (NO THRUST)
  - IN P70 | Press 0: P71 finishes the abort
  - PRO | Restart monitoring
  - ENTR | Engine off, new ignition in 5 s. PRO at V99 N63
  - V34E | End the programme
end
```

> CAUTION: V37 during an abort turns the engine off.

<!--sheet-->

```checklist
band: CUT-OFF AND ORBIT
- TTG 0:04 | COMPUTER | Cuts the engine. Aborts are over
[A11] v: V16 N63 FL
[J] v: V16 N94 FL
- | PRO |
v: V16 N85 FL: still to gain, R1 nose, R2 right, R3 window side
- | TRANSLATION | Trim to near zero
- | PRO |
v: PROG 00, V37 N99 FL
- | DSKY | V82E
band: ORBIT AIMED AT
n: Perilune 60,000 ft (18.3 km) above the site, climbing at 19.5 ft/s (5.9 m/s), cross-range steered up to 8.2 nm (15.2 km) towards the CSM's plane
[A11] n: Apolune follows the time since ignition: about 140 nm (260 km) early, about 43 nm (80 km) after 10 minutes
[J] n: Apolune follows the CSM: about 130 nm (240 km) at PDI with the CSM in place, never under 30 nm (56 km); 30 nm (56 km) with no CSM
```

> NOTE: Target the CSM before `V37E 63E`: P63 keeps that vessel. With none it warns, and an abort flies in your own orbit plane.

> NOTE: Only a P63 ignition in the same DSKY session allows an abort: not a loaded landed save. Leaving the descent with V34 or V37 also ends that permission. Late in the descent P70 runs dry before orbit: expect V97.
