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
| Planner | Replaces Mission Control. It fits your orbit to the pad-load geometry and sets PDI at landing time minus 755 s. Manoeuvre nodes are a picture only. |
| == Radar and display | | |
| Landing radar | Simulated from terrain height. V57 and V58 set a flag only, and the radar feeds no navigation. |
| Lamps and alarms | Only the lamps described on {@1-2} are driven. One alarm lamp (PROG), no MASTER ALARM, no fuel display. Only the alarms in {@2-1 2.1} are raised. |
| Prompts | Only V32 shows a flashing display again (ENTR does not). If you ignore the P63 start display, P63 carries on at TIG-35 s. A programme's new display replaces your monitor at once (the real one mostly waited for KEY REL). |
| == Burns | | |
| P30 | N45's middle gimbal angle is assumed. One PRO ends P30. |
| P40 to P42 | Need a burn set by P30 or P32 to P35 (Luminary flies whatever it holds). A P34 or P35 burn is solved afresh every 2 s. |
| IMU and attitude | Aligned from the start (`IMU_ALIGN`). P51 is one request, with no star sighting. N18 angles are measured from the attitude the DSKY started in, not gimbal angles. |
| Throttle lever | With RCS on and the engine off, a raised lever fires the RCS (KSP's behaviour), so the lever is released after a burn. |
| == Loads and uplink | | |
| Uplink | A stream of key presses read from a file, with no hardware error checking. V70, V73 and state-vector loads are not implemented. |
| Clock | Zero is the vessel's mission time zero, saved in clock.txt. |
| Plane change | The CSM's burn. The PAD only notes it. |
