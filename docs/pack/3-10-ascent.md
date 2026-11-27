---
page: 3-10
section: Section 3 | Checklist: Ascent
---
## 3.10 Ascent: planning and P12

```checklist
band: PLAN THE ASCENT | RUN plan.  /  landed, CSM in lunar orbit
- | DSKY | X, YES, if it is still running
- | MAP VIEW | Set the CSM as target
- | TERMINAL | RUN plan.
- | PLANNER | Choose Ascent in the menu. PLAN
v: PAD: lift-off time, N76 targets, rendezvous times, CSM overhead, next lift-off
[A11] n: Rendezvous times: CSI (keyed in P32) and TPI
[J] n: Rendezvous time: TPI (keyed in P34). Below it, a coelliptic fallback with its own lift-off, CSI and TPI
n: The first lift-off is at least 10 minutes ahead
if: THE LINE SAYS WHY IT FAILED
  - | Not landed / no target / CSM not in orbit / time warp on
  - | Site more than 30 deg from the CSM's orbit plane
end
if: WARNING ON THE PAD
  - | CSM outside 50 to 70 nm (93 to 130 km), or apolune and perilune over 10 nm (18.5 km) apart: not a rendezvous that was flown
  - | Cross-range over 8 nm (15 km): the rest is left for the rendezvous
  - | Propellant short: check the stage
end
- | PLANNER | Write the PAD down (CARD: LM Ascent PAD). Close
band: PRELIMINARY | P12  /  **SAS off, throttle zero, no time warp**
- | TERMINAL | RUN dsky.
- | DSKY | V37E 12E
n: The landing site is taken from where the ship stands: P68 is not needed
- | N33 FL | Lift-off time: key V25 N33 E from the PAD. PRO
[J] n: To fly the fallback, key its lift-off time here. Key its CSI and TPI times later, in P32
- | N76 FL | Targets: key V25 N76 E from the PAD. PRO
n: Key N76 only after PRO on N33: P12 first writes its own values there
if: OPR ERR
  - | Not landed / no CSM / no ascent engine: a warning says why
end
if: V50 N25 FL, 00203 (SAS IS ON)
  - SAS | **Off**. PRO
end
band: COUNT-DOWN
v: V06 N74: time to lift-off, yaw and pitch after the rise
- | SHIP | Warps to T-60 s by itself (KSP's warp cancel key stops it)
- TIG-0:35 | DSKY | Blank. Returns at TIG-30
- TIG-0:05 | V99 N74 FL | PRO (enable engine)
n: ENTR: no lift-off, nothing staged, on to the trim displays. V34E ends P12
- NEXT | POWERED FLIGHT | {@3-11}
```

> CAUTION: P12 does the staging. Never press the KSP staging key yourself.

> NOTE: Alarm 1703: the lift-off time was less than 30 s away or past. P12 moves it to about 30 s ahead and the rendezvous timing is lost. V34E ends P12.
