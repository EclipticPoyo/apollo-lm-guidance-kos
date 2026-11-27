---
page: 3-11
section: Section 3 | Checklist: Ascent
---
## 3.11 Ascent: powered flight and orbit

```checklist
band: LIFT-OFF | about 7 minutes of burn
- TIG | COMPUTER | Lights the ascent engine, then separates the stages
[A11] v: V06 N63
[J] v: V06 N94
- TIG+0:09 | PITCH OVER | After the vertical rise to 40 ft/s (12 m/s) up
v: Windows face the surface for 10 s
[A11] n: The windows are also turned downrange before the pitch-over
- | Q / E | After that, turn about the thrust axis if you want. Released, it holds
- | SAS | **On**: ATT HOLD, you fly the attitude. **Off**: the computer steers again
n: In ATT HOLD the guidance runs on and the computer still cuts the engine off
if: V97 N74 FL (NO THRUST)
  - PRO | Restart monitoring
  - ENTR | Engine off, new ignition in 5 s. Settle the propellant (H), PRO at V99
  - V34E | End P12
end
n: Flown figures on this lander. R2 climb rate, R3 height
- TIG+4:00 | CHECK | up 192 ft/s (59 m/s), 35,000 ft (10.7 km)
- TIG+7:10 | CUT-OFF | About 60,000 ft (18.3 km), up 32 ft/s (9.8 m/s), 5510 ft/s (1680 m/s)
- TTG 0:04 | COMPUTER | Sets the cut-off time and cuts the engine
band: TRIM | RCS
[A11] v: V16 N63 FL
[J] v: V16 N94 FL
- | PRO |
v: V16 N85 FL: still to gain, R1 nose, R2 right, R3 window side
- | TRANSLATION | H / N along the nose, I J K L across. Drive R1-R3 to near zero
- | PRO | Ends P12. SAS on
v: PROG 00, V37 N99 FL
band: CHECK THE ORBIT | V82
- | DSKY | V82E
v: V16 N44 FL: apolune, perilune, time of free fall
n: Heights above the landing site. -59 59: the path does not come down
- | PRO | Ends the display (V34E too)
[A11] n: Aimed at apolune 15 nm (28 km) below the CSM
[J] n: Aimed at apolune 14 nm (26 km) below the CSM
band: NEXT | rendezvous
[A11] - NEXT | CSI | Coelliptic: turn to page {@3-12}
[J] - NEXT | TPI | Short: skip to page {@3-15}. TPI about 45 min after insertion
[J] - NEXT | CSI | Fallback lift-off flown: turn to page {@3-12}
```

> CAUTION: V37 during the powered ascent turns the engine off, as on the real LM. This includes V37E 00E. V82 is safe: it runs over P12.

> NOTE: Flown targets: insertion at 60,000 ft (18.3 km) above the landing site. The planner works the targets into the PAD.
