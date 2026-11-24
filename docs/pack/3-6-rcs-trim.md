---
page: 3-6
section: Section 3 | Checklist: RCS trim
---
## 3.6 RCS trim (P41, P47)

```checklist
band: LOAD THE BURN
- | DSKY | V25 N33 E, V25 N81 E (or the uplink)
- | DSKY | V37E 30E. PRO through its displays
if: P41 REFUSES
  - | No P30, or time and delta-v not loaded
end
band: RCS BURN | P41  /  nose X, right Y, window side Z
- | DSKY | V37E 41E
n: The ship turns as in P40
v: V16 N85 (blank for a few s before TIG)
v: Terminal counts down: TIG in M:SS
- TIG | N85 | Flashes
- | TRANSLATION | H / N along the nose. Drive R1-R3 to near zero
- | PRO | Or V34E. Ends P41
n: ENTR shows the display again. The engine is never lit
band: THRUST MONITOR | P47  /  a burn you fly entirely by hand
- | DSKY | V37E 47E
v: V16 N83 FL after about 20 s (velocity gained, ship axes)
- | ENTR | Zeroes the count
- | PRO | Ends P47
```
