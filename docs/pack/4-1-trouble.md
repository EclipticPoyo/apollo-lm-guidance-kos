---
page: 4-1
section: Section 4 | Trouble
---
## 4.1 If something goes wrong

<!--table st-->
| Problem | Action |
|---|---|
| A key moves the wrong way | Flip the sign setting ({@2-4 2.4}). |
| P63, P12 or P32 to P35 refuses to start | See {@2-6 2.6}. Plan again if needed. |
| P40, P41 or P42 refuses after the DSKY was restarted | The burn is not saved. Target again: P32 or P33 to [[PRO]] at N81, P34 to N58, or P35. |
| The engine stopped after V37 in the ascent | V37 ends P12 and its burn. Nothing restarts it by itself: fly the rest by hand. |
| A rate-of-descent tap does nothing | Use H and N, or Shift and Ctrl: if one pair does not register on your keyboard, use the other. `ROD_KEYS` ({@2-4 2.4}) can limit it to one pair. {A11 Check SAS is on} |
| `Backspace` or `0` does nothing | Click outside the kOS terminal. Aborts run from a P63 ignition in this DSKY session to [[PRO]] at P68 ({@3-9}). |
| An abort aims at a very high apolune | {J The abort follows the CSM: one far from its place asks for up to 700 nm, which the ascent stage may not manage. Check the planner's CSM line} |
| P32 shows 605 or 606 at the PAD's CSI time | The orbit you reached differs from the planned one. V32, load N11 with zeros (`V25 N11 E`), [[PRO]] twice: your next apolune ({@3-12}). |
| No drift gauge | It needs P20, P25 or P47, a CSM in lunar orbit (the ascent plan's, else the target) within 40 nm, and the LM not landed. |
| The needles stay at the middle | Point the front windows within 30 deg of the CSM, or switch to 2 mrad/s. |
| OPR ERR lit | Read the warnings, then [[RSET]] (it clears them). |
| A warning or message has gone | Read `0:/lm/logs/dsky.log`: every line since the DSKY started. |
| Anything else | The X in the DSKY window, then YES, ends the computer and gives you the controls. |
| Reporting a bug | Send `0:/lm/logs/dsky.log` (before the DSKY is run again) and `rod.log`. Set `LOG` to TRUE, fly again, and send the other logs in that folder. |
