---
page: 3-1
section: Section 3 | Checklist: Start-up
---
## 3.1 Start-up and planning

```checklist
legend
band: BEFORE THE DESCENT | RUN plan.
- | ORBIT | Bound lunar orbit. No time warp
v: No maneuver nodes you want to keep
- | TERMINAL | SWITCH TO 0.
n: Once per session, or set the boot file to boot/lm_boot.ks
- | TERMINAL | RUN plan.
v: Planner window open
- | SITE | Apollo site, or custom (lat, lon in deg, east +)
- | SOFTWARE | Apollo 11 or J-class
- | PLAN | Press
v: PLAN OK! DOI, PDI, LDG (UT)
if: THE LINE SAYS WHY IT FAILED
  - | No bound orbit / warp on / terrain too low / plane change too large
  v: Fix, then PLAN again
end
- | SEND | Press
- | PLANNER | Close (cross in corner)
band: DSKY | RUN dsky.
- | TERMINAL | RUN dsky.
v: UPLINK ACTY lit while the keys are pressed in
- | DSKY | V16 N33 E
v: R1-R3 = DOI TIG (h, min, s)
- | DSKY | V16 N81 E
v: R1-R3 = DOI delta-v (X, Y, Z)
if: NOTHING LOADED
  - | P63 will refuse. PLAN again, SEND
  - | Skip simulated uplink ticked: the DSKY loads the plan at start
end
```

> CAUTION: A kOS processor runs one script at a time. End the planner before RUN dsky. Start the DSKY before the descent and do not restart it during the descent.
