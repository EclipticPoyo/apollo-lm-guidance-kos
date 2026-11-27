---
page: 0-4
section: Abort card
---
## Abort card: leaving a landing

From P63 ignition until [[PRO]] at P68. One press: no arming, no [[PRO]]. Details in {@3-9}.

<!--table st-->
| Want | Press | You get |
|---|---|---|
| Abort on the descent engine | `Backspace` | P70. Nothing separates |
| Abort stage | `0`, once | P71. The computer stages |

```checklist
legend
band: BEFORE P63
- | CRAFT | Nothing assigned to Abort or action group 10
- | MAP VIEW | **Target the CSM**
band: ABORT | click outside the kOS terminal first
- NOW | KEY | Backspace (P70) or 0 (P71)
v: PROG 70 or 71
[A11] v: V06 N63
[J] v: V06 N94
- | COMPUTER | SAS off, full throttle, steers to orbit
if: V97 N63 FL IN P70 (THE DESCENT TANKS ARE DRY)
  - KEY | 0
  v: PROG 71, the stages separate
end
- TTG 0:04 | COMPUTER | Cuts the engine
[A11] v: V16 N63 FL
[J] v: V16 N94 FL
- | PRO |
v: V16 N85 FL
- | TRANSLATION | Trim R1-R3 to near zero
- | PRO |
- | DSKY | V82E
v: Apolune, perilune. PRO
```

> CAUTION: Do not stage with Space to abort. The dropped stage keeps its thrust and can hit you.

> CAUTION: 0 drops the descent stage at once. There is no confirmation and no way back to P70.
