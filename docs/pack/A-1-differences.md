---
page: A-1
section: Appendix A | Differences
---
## A.1 Differences from the real LM

The computer recreates what the crew saw and did, using KSP data. Only the differences that affect how you fly or read it are listed.

<!--table st-->
| Item | Here, compared with the real LM |
|---|---|
| == General | |
| Hardware | The AGC's processor, memory and operating system are not emulated. The guidance equations come from the Luminary source. |
| Touchdown | The engine cuts off by itself. The crew did it by hand. |
| Planner | Replaces Mission Control. It fits your orbit to the pad-load geometry and sets PDI at landing time minus 755 s. Maneuver nodes are a picture only. |
| == Radar and display | | |
| Landing radar | Simulated from terrain height. V57 and V58 set a flag only, and the radar feeds no navigation. |
| Lamps and alarms | Only the lamps in table 1-1 are driven. One alarm lamp (PROG), no MASTER ALARM, no fuel display. Only the alarms in 2.2 are raised. |
| Prompts | Only V32 shows a flashing display again (ENTR does not). If you ignore the P63 start display, P63 carries on at TIG-35 s. |
| == Burns | | |
| P30 | N45's middle gimbal angle is assumed. One PRO ends P30. |
| P40 and P41 | No Lambert solver yet: the delta-v always comes from P30. Luminary solves the burn itself when none is loaded. |
| IMU and attitude | Aligned from the start (`IMU_ALIGN`). P51 is one request, with no star sighting. N18 angles are measured from the attitude the DSKY started in, not gimbal angles. |
| Throttle lever | With RCS on and the engine off, a raised lever fires the RCS (KSP's behaviour), so the lever is released after a burn. |
| == Loads and uplink | | |
| Uplink | A stream of key presses read from a file, with no hardware error checking. V70, V73 and state-vector loads are not implemented. |
| Clock | Zero is the vessel's mission time zero, saved in clock.txt. |
| Plane change | The CSM's burn. The PAD only notes it. |
| == Ascent | |
| CSM | The KSP vessel named in the ascent plan, else the target, read when P12 starts. Nothing is uplinked, and a later change of target has no effect. |
| Start and staging | P12 starts only when landed, because it stages the ship. It separates and lights by itself: no ABORT STAGE or ENGINE ARM presses. It also stores where the ship stands as the landing site (the real P12 only read it). |
| Guidance | Run every computer cycle (the real LM: every 2 s). Delta-v is KSP's velocity change less gravity. No abort guidance system. |
| Attitude | kOS steering with any RCS jet (the real ascent used the +X jets). A released turn about the thrust axis is held a moment further on. The throttle does not fire the RCS until cut-off. |
| Lift-off time | The planner simulates the ascent and applies the rendezvous plans that were flown. In test flights the CSM ended about a quarter degree further ahead than planned. |
| Warp | KSP time warp up to the count-down. |
| V82 | This vehicle only, and no time to perilune. |
| == J-class | | |
| P66 | Leaves out alarm 1466 and the engine-arm test. PRO or V32 stand in for the arm switch. |
