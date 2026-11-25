---
page: 3-8
section: Section 3 | Checklist: Ascent
---
## 3.8 Ascent: powered flight and orbit

```checklist
band: LIFT-OFF | about 7 minutes of burn
- TIG | COMPUTER | Lights the ascent engine, then separates the stages
v: V06 N63 (Apollo 11) or V06 N94 (J-class)
v: Vertical rise to 40 ft/s up, then pitch over
v: Windows face the surface for 10 s
n: Apollo 11 also turns the windows downrange before it pitches over
- | Q / E | After that, turn about the thrust axis if you want. Released, it holds
- | SAS | On: ATT HOLD, you fly the attitude. Off: the computer steers again
n: In ATT HOLD the guidance runs on and the computer still cuts the engine off
if: V97 N74 FL (NO THRUST)
  - PRO | Restart monitoring
  - ENTR | Engine off, new ignition in 5 s. Settle the propellant (H), PRO at V99
  - V34E | End P12
end
- TTG 0:04 | COMPUTER | Sets the cut-off time and cuts the engine
band: TRIM | RCS
v: V16 N63 or N94 FL
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
```

> CAUTION: V37 during the powered ascent turns the engine off, as on the real LM. This includes V37E 00E. V82 is safe: it runs over P12.

> NOTE: Flown targets: insertion at 60,000 ft above the landing site, apolune 15 nm (Apollo 11) or 14 nm (J-class) below the CSM. The planner works them into the PAD.
