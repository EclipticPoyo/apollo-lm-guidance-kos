---
page: 2-6
section: Section 2 | Reference
---
## 2.7 Refusals

### P63 refused: the terminal says why

<!--table st-->
| Message | Fix |
|---|---|
| RLS or TLAND is not loaded | Press SEND in the planner (or tick Skip simulated uplink). Or load them from the PAD. |
| Saved plan is for another site | Plan again. |
| Planned PDI time has passed | Plan again. |
| Orbit is not bound | Get into orbit. |
| No engine found | Check staging. |

### P12 refused: the terminal says why

<!--table st-->
| Message | Fix |
|---|---|
| The ship is not LANDED | P12 starts only on the surface. |
| No CSM in orbit | Target the CSM, or plan the ascent again. |
| No ascent engine found | The ascent engine must be one that is never decoupled. |
| The processor would be left on the descent stage | Move the kOS processor to the ascent stage. |
