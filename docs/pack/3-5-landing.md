---
page: 3-5
section: Section 3 | Checklist: Landing
---
## 3.5 P65, P66 and touchdown

```checklist
band: AUTOMATIC LANDING | P65
- | COMPUTER | Nulls horizontal speed. Settles to 3 ft/s down
v: V06 N60. Terminal shows descent rate in m/s
band: RATE OF DESCENT | P66  /  optional
- | SAS | On
- | H or SHIFT | Slower, 1 ft/s a tap. First tap starts P66
- | N or CTRL | Faster, 1 ft/s a tap
n: Either pair works: if one does not register on your keyboard, use the other. Tap, do not hold: H and N also fire the RCS
- | FLY ATTITUDE | Yourself
if: TAP IN AUTO (SAS OFF)
  - | Ignored. Terminal says so
  - | Wrong way: flip P66_ROD_SIGN
end
- | SAS | Off. P66 turns back into P65. Rate kept
band: TOUCHDOWN | P68
- CONTACT | CONTACT LAMP | Lit
- | ENGINE | Cuts off a quarter second later
v: PROG 68, V06 N43 FL (lat, lon, height)
- | PRO | Ends P68. Position stored as the landing site
n: V34E ends it too. V32E shows N43 again
v: PROG 00, V37 N99 FL
- | X IN WINDOW | YES. Ends the computer
n: To leave the Moon again: 3.7
```

> NOTE: Early P66: with SAS on and the engine at full throttle, a ROD tap in P63 or P64 starts P66 as soon as P65 would. PRO or ENTR in P65 or P66 drops the steering target until you change the attitude mode.

> NOTE: J-class: no P65. P66 holds the approach rate and nulls horizontal speed itself. V06 N60 FL throughout. V57E clears the radar below 50 ft. P63 V06 N63 FL from ignition until V57E.
