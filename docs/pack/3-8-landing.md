---
page: 3-8
section: Section 3 | Checklist: Landing
---
## 3.8 P65, P66 and touchdown

```checklist
use: abort
band: AUTOMATIC LANDING
[A11] - | COMPUTER | P65 nulls horizontal speed. Settles to 3 ft/s (0.9 m/s) down
[A11] v: V06 N60. Terminal shows descent rate in m/s
[J] - | COMPUTER | P66 holds the approach's rate of descent and nulls horizontal speed. No P65
[J] v: V06 N60 FL throughout. Terminal shows P66 messages
[J] n: Do not key PRO or V32E (either ends the horizontal nulling for the rest of the landing; the last attitude is held) or V34E (ends P66)
band: RATE OF DESCENT | P66
[A11] - | SAS | **On**
[A11] - | H or SHIFT | Slower, 1 ft/s (0.3 m/s) a tap. First tap starts P66
[J] - | H or SHIFT | Slower, 1 ft/s (0.3 m/s) a tap. Any attitude mode: SAS not needed
- | N or CTRL | Faster, 1 ft/s (0.3 m/s) a tap
n: Either pair works: if one does not register on your keyboard, use the other. Tap, do not hold: H and N also fire the RCS
[A11] - | FLY ATTITUDE | Yourself
[A11] if: TAP IN AUTO (SAS OFF)
  - | Ignored. A warning says so
end
[A11] - | SAS | **Off**. P66 turns back into P65, which resumes (3 ft/s (0.9 m/s) down)
[A11] n: With SAS on and the engine at full throttle, a ROD tap in P63 or P64 starts P66 as soon as P65 would
[A11] n: PRO or ENTR in P65 or P66 drops the steering target until you change the attitude mode
[J] - | SAS | **On**: you fly the attitude. **Off**: the computer nulls horizontal speed again
band: TOUCHDOWN | P68
- CONTACT | CONTACT LAMP | Lit
- | ENGINE | Cuts off a quarter second later
v: PROG 68, V06 N43 FL (lat, lon, height)
- | PRO | Ends P68. Position stored as the landing site
n: This ends the abort window: until then 0 starts P71
n: V34E ends it too. V32E shows N43 again
v: PROG 00, V37 N99 FL
- | X IN WINDOW | YES. Ends the computer
- NEXT | ASCENT | To leave the Moon again: {@3-10}
```
