---
page: 2-6
section: Section 2 | Reference
---
## 2.6 Refusals

The terminal's warnings area says why a programme refused. These are the fixes you might not guess.

<!--table st-->
| Message | Fix |
|---|---|
| == P63 | |
| RLS or TLAND is not loaded | SEND in the planner (or tick Skip simulated uplink), or load them from the PAD. |
| == P12 and P32 to P35 | |
| No CSM in lunar orbit | Target it, or plan the ascent again. |
| == P12 and P71 | |
| No ascent engine found | It must be one that is never decoupled. |
| The processor would be left on the descent stage | Move the kOS processor to the ascent stage. |
| == P20, P25, V83, V89, V90 | |
| No CSM in lunar orbit | Target it. |
| OPR ERR at V89 | Only in P00: end P20 or P25 first (`V56E`). |
| OPR ERR at V90 | Not during P12, P40 to P47 or P63 to P71. |
| OPR ERR at V82, V83, V89, V90 | Answer the request that broke in, or end the other display, first. |
| == P33 and P35 | |
| No TPI time (P33) | Run P32 first, or load it with `V25 N37 E`. |
| No intercept time (P35) | Run P34. The intercept must be more than 3 minutes ahead. |
| == P40, P41 and P42 | |
| No burn is set, or TIG is not loaded | Run P30, or P32 to P35. |
| The intercept time is not after TIG and now | Run P34 or P35 again. |
| == P70 and P71 | |
| No abort now | Only from a P63 ignition in this DSKY session to [[PRO]] at P68. |
| The descent stage is still on | `V37E 71E` never stages. Press `0`. |
| The ship is down, or the descent stage is gone | Use P71. |
