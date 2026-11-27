---
page: A-2
section: Appendix A | Differences
---
## A.2 Differences: ascent, aborts, rendezvous, 210

<!--table st-->
| Item | Here, compared with the real LM |
|---|---|
| == Ascent | |
| CSM | The KSP vessel named in the ascent plan, else the target, read when P12 starts. Nothing is uplinked, and a later change of target has no effect. |
| Start and staging | P12 starts only when landed, because it stages the ship. It separates and lights by itself: no ABORT STAGE or ENGINE ARM presses. It also stores where the ship stands as the landing site (the real P12 only read it). |
| Guidance | Run every computer cycle (the real LM: every 2 s). Delta-v is KSP's velocity change less gravity. No abort guidance system. |
| Attitude | kOS steering with any RCS jet (the real ascent used the +X jets). A released turn about the thrust axis is held a moment further on. The throttle does not fire the RCS until cut-off. |
| Lift-off time | The planner simulates the ascent and applies the rendezvous plans that were flown. In test flights the CSM ended about a quarter degree further ahead than planned. |
| Warp | KSP time warp up to the count-down. |
| V82 | This vehicle only, and no time to perilune. |
| == Aborts | | |
| Controls | `Backspace` and `0` replace ABORT and ABORT STAGE. The computer sets SAS and throttle and does the staging: no ENGINE ARM or V50 N25. A staging by Space counts as abort stage. |
| When | P70 is refused once landed. `0` does nothing after an abort's cut-off (the real button worked until the programme ended). No 15-minute surface limit, button lock-out or abort guidance system. |
| CSM and targets | The KSP vessel kept from P63; without one, your orbit plane at ignition. 210 targets are moved to this site's height. 099 speeds are the real ones, unmoved, so apolunes are about 13 nm higher than Apollo's here. |
| Flight | The roll is held while the ship turns over. A dry descent engine is judged by the ascent's thrust limit, so the RCS cannot hide V97. |

<!--sheet-->

<!--table st-->
| Item | Here, compared with the real LM |
|---|---|
| == Rendezvous | |
| CSM | The KSP vessel named in the ascent plan, else the target. It is read where it is: no uplinked state. |
| Prediction | Both orbits are carried forward as simple two-body orbits. |
| P32, P33 | [[PRO]] on a zero N11 takes the next apolune. With none stored, N55 starts at 1 and 26.60 deg. A burn time that has passed asks for a new one. N82 cannot be loaded. With no TPI time from P32, P33 takes one loaded by hand. |
| P34, P35 | No precision offsets (NN does nothing). A passed TPI time asks for a new one. P35 sets TIG 180 s ahead in both profiles. A path that cannot be solved is alarm 20607. |
| P42 | At alarm 1706, [[PRO]] does not go on with the descent stage still on, as Luminary's did. |
| P41 steering | Set by the stage: with the descent stage gone, P41 takes the ascent steering by itself. The real crew could key the autopilot's configuration; there is no such entry here. |
| PAD times | Our planner's, not the ground's: CSI at the apolune of the planned insertion orbit (not worked out again from the orbit reached), TPI at the flown intervals. The 210 fallback takes Apollo 15's CSI to TPI time. |
| Drift gauge | For the cross-pointer on the rendezvous radar: two crossing needles on a dial in a window beside the DSKY. The full scales are the real ones; which needle showed which axis, and which way it moved, was not found, so ours mean "thrust this way". Centred beyond 30 deg off the CSM. Read from KSP twice a second. |
| Range figures | For the tapemeter on range and range rate: digits on the drift gauge, read from KSP, ft under 10,000 ft and nm beyond. The next-gate line is ours; the crew had the gates on a card. |
| Braking | Apollo 11 went to P00 and then P47 for braking, pointing by hand. Here P20 stays on and holds the windows on the CSM; P47 is optional. |
| Docking | The time-to-dock message is ours. The computer does not fly the docking. |
| == Tracking | |
| P20 | No rendezvous radar: no radar displays or state correction. A mark is only a count; its rate and the Moon test are ours. |
| Others | P25 points without pause. SAS is AUTO or ATT HOLD. V95 does nothing. |
| == Luminary 210 | | |
| P66 | Leaves out alarm 1466 and the engine-arm test. PRO or V32 stand in for the arm switch. |
