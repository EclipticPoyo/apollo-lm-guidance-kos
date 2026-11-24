---
page: 3-2
section: Section 3 | Checklist: DOI
---
## 3.2 DOI burn (P30, P40)

```checklist
band: CHECK THE BURN | P30
- | DSKY | V37E 30E
- | N33 FL | TIG. PRO
- | N81 FL | Delta-v. PRO
- | N42 FL | Orbit after the burn. PRO
- | N45 FL | Time to ignition. PRO
if: OPR ERR
  - | Time or delta-v not loaded, or time passed
  - DSKY | V25 N33 E / V25 N81 E, or replan
end
band: FLY THE BURN | P40  /  Moon, circular orbit, RCS on, SAS off, descent stage on
- BEFORE | THROTTLE | Zero (Ctrl)
- TIG-4:00 | DSKY | V37E 40E
n: At least 4 min before ignition. Earlier is fine
v: V50 N18 FL
- | PRO | Ship turns (V06 N18 steady)
- | ENTR | When V50 N18 returns
n: ENTR at the first display skips the turn
v: V50 N25 FL, 00203 (ENG THR CONT = MAN only)
- | ENTR |
- TIG-1:00 | SHIP | Warps by itself
v: V06 N40 counts up to zero
n: Display blanks at TIG-35 s. RCS ullage at about TIG-7.5 s
- TIG-0:05 | V99 N40 FL | PRO (enable engine)
n: ENTR skips the burn. V34E ends P40
- TIG | ENGINE | Lights at minimum thrust
- | THROTTLE | MAN: lever drives the engine from ignition
- TIG+0:15 | TERMINAL | Raise throttle
- | SHIFT | Hold to about 40 pct thrust
- | LEVER | Keep out of the 60-92.5 pct band
n: AUTO: a short burn stays at minimum
- CUT-OFF | COMPUTER | Cuts the engine
v: V16 N40 FL
- | PRO |
v: V16 N85 FL
- | TRANSLATION | Trim R1-R3 to near zero
- | PRO |
- NOW | DSKY | V37E 63E
n: Do not coast to PDI. P63 warps you there
if: ALARM
  - 1703 | Ignition too close. Moved to about 50 s ahead
  - 1706 | Descent stage gone
end
```

> CAUTION: P40 refuses without P30 and a loaded time and delta-v. On MAN the throttle is yours from ignition, so set the lever to zero before you start.
