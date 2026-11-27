---
page: 3-18
section: Section 3 | Checklist: Rendezvous
---
## 3.18 Rendezvous: tracking and displays (P20, P25, V83, V89, V90)

P20 points the front windows at the CSM, underneath the programme you select, and counts marks. P25 only points. SAS off lets them steer, SAS on holds them off; the computer never switches SAS.

```checklist
band: TRACKING | P20, in lunar orbit | optional
n: Skip it and the burns are still targeted: the marks are only counted (N45 R1). On the real LM they fed the navigation
- | KSP | **Target the CSM. RCS on, SAS off**
- | DSKY | V37E 20E (V37E 25E points only, no marks)
n: With SAS on the terminal says P20: SAS IS ON, TURN IT OFF TO STEER (P25 the same)
- | V50 N18 FL | More than 15 deg off: PRO turns, ENTR asks again later, V34E ends tracking
- | V50 N18 FL | After the turn it flashes again: ENTR
- | MARKS | V16 N45E: R1 counts, one every 30 s. V93E: the next reads 1
- | END | V56E
band: RANGE | V83, any time
- | DSKY | V83E: V16 N54. R1 range 0.01 nm, R2 range rate 0.1 ft/s (- closing), R3 angle of the front windows 0.01 deg
- | PRO | Ends it
band: OUT OF PLANE | V90
- | DSKY | V90E
- | V06 N16 FL | Your TIG. V25 N16E changes it (zero: now), V32E reloads it. PRO
v: V06 N90: R1 your distance out of the CSM's plane 0.01 nm, R2 its rate 0.1 ft/s, R3 bearing of the CSM 0.01 deg
- | PRO | Ends it (V32E: back to N16)
- | PLANE TRIM | At the burn's final N81: V22 N81E, minus the N90 R2, E
band: POINT | V89, in P00, tracking ended
- | DSKY | V89E
- | V04 N12 FL | R2 1: front windows. For the top hatch: V22 N12E 2E. PRO
- | V06 N18 FL | Attitude a minute ahead. PRO (V32E again, V34E ends)
- | V50 N18 FL | PRO turns. ENTR when it returns
```

Bearing is clockwise from forward, seen from above. The front windows' angle runs from forward (0) through overhead (90) and back (180).

<!--sheet-->

### Tracking under other programmes

- Every V37 switches tracking off. P30 and P32 to P35 switch it on again, so P20 works under them and is idle in P40 to P47 and the descent.
- Marks need the CSM within 30 deg of the front windows, within 400 nm (740 km), with the Moon not in the way. They freeze at the final computation (first [[PRO]] at N45). The count is cleared when P20 starts and when P40, P41 or P42 ends.
- Within 15 deg it holds the attitude without asking. It looks every 6 s. It steers in physics warp, not in rails time warp.
- The request breaks into whatever is shown. While you are keying, or your own display is up, it waits with **KEY REL** lit: press [[KEY REL]] to let it in. While it is up, [[PRO]], [[ENTR]], V32 and V34 answer it, and the display underneath comes back afterwards.
- **PROG** shows 20 or 25 only while no other programme runs. A `RUNNING IN BACKGROUND:` line at the top of the kOS terminal shows its state and the marks.

### CSM over 400 nm (740 km) away (P20)

{A11 Alarm 526 and a flashing `V05 N09`. [[PRO]] looks again, `V34E` ends P20}

{J Alarm 526 once. P20 looks again by itself every 5 s}

> NOTE: V83, V89 and V90 are refused during a load, while a request has broken in, and while another such display is up.
