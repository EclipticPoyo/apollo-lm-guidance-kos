---
page: 2-3
section: Section 2 | Reference
---
## 2.4 Settings

One text file, `agc_config.txt`, in `Ships/Script/`. Edit a value, save, restart the DSKY. A bad line is skipped and the terminal says so.

<!--table vt-->
| Setting | Default | Use |
|---|---|---|
| ENG_THR_CONT | AUTO | MAN: the throttle lever is yours from ignition. Use for the DOI. |
| IMU_ALIGN | AUTO | REQUIRED: burns need P51 first. |
| PLAN_NODES | TRUE | FALSE: the planner removes its nodes. |
| P63_WINDOW_MODE | UP | UP: window faces the site. KEEP: keeps roll. |
| ROD_KEYS | BOTH | BOTH, HN or SHIFTCTRL. |
| P64_PITCH_SIGN<br>P64_YAW_SIGN<br>P66_ROD_SIGN | 1, -1, 1 | Flip if a key moves the wrong way. |
| P63_WARP_LEAD_S | 60 | Seconds before ignition at which a warp stops (P63, P40, P41, P12). |
| BODY_NAME | Moon | The body you land on. |
| DSKY_START | BLANK | N60: start on the descent monitor `V16 N60`. |
| ALARMS | OFF | A11, or your own list as code@seconds. |
| LOG | FALSE | TRUE writes logs for bug reports. |
