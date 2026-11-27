---
page: 0-5
section: Rendezvous card
---
## Rendezvous card: orbit to docking

The short version of {@3-12} to {@3-18}. 210, direct flight: start at TPI. Its coelliptic fallback flies CSI and CDH as 099 does.

```checklist
legend
band: CSI | {@3-12}  /  099, and the 210 fallback
- | MAP VIEW | **Target the CSM**
- | DSKY | V37E 20E (optional tracking), V37E 32E
- | N11 FL | V25 N11 E (PAD). PRO
- | N55 FL | PRO
- | N37 FL | V25 N37 E (PAD). PRO
v: V06 N75, N81, N82: PRO each
- | N45 | PRO, through them again. PRO ends
- | DSKY | V37E 41E: fly N85 to zero. PRO
band: CDH | {@3-13}
- | DSKY | V37E 33E
- | N13 FL | PRO. Through N75 and N81, N45 as at CSI
- | DSKY | V37E 41E: fly N85 to zero. PRO
band: TPI | {@3-14} 099  /  {@3-15} 210
- | DSKY | V37E 34E
[A11] - | N37 FL | PRO (the time from P33)
[A11] - | N55 FL | PRO
[J] - | N37 FL | V25 N37 E (PAD). PRO
[J] - | N55 FL | R2 zero. PRO
[A11] v: N58, N59, N45. Again: N81, N59, N45. PRO
[J] v: N58, N81, N45. Again. PRO
[A11] - | DSKY | V37E 41E: fly N85 to zero. PRO
[J] - | DSKY | V37E 42E: P42 burns it
band: MIDCOURSE | {@3-16}  /  about 15 and 30 min after TPI
- | DSKY | V37E 35E, PRO through N45 twice
- | DSKY | V37E 41E: fly N85 to zero. PRO
band: BRAKING | {@3-17}
- | SHIP | **RCS on, SAS off**
- | DSKY | V37E 20E. PRO to turn, ENTR when it asks again (delta-v count instead: V37E 47E)
v: Gauge: RANGE, RATE (- closing), next gate. V83E (V16 N54): R1 0.01 nm, R2 0.1 ft/s
- | GAUGE | From 6000 ft (1830 m), thrust towards the needle: H up, N down, L right, J left
gate: GATE | 6000 ft (1830 m) | 30 ft/s (9.1 m/s)
gate: GATE | 3000 ft (915 m) | 20 ft/s (6.1 m/s)
gate: GATE | 1500 ft (460 m) | 10 ft/s (3 m/s)
[A11] gate: GATE | 600 ft (180 m) | 5 ft/s (1.5 m/s)
[J] gate: GATE | 500 ft (150 m) | 5 ft/s (1.5 m/s)
band: DOCKING | from 100 ft (30 m)
- | SHIP | **SAS on**
- | DSKY | **X, YES** (closes it)
- | KSP | Dock from the LM or the CSM
```

> CAUTION: A good intercept is a collision course. If you cannot slow in time, translate sideways.
