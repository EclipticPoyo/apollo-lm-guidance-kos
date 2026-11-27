---
page: 2-4
section: Section 2 | Reference
---
## 2.4 Settings

One text file, `agc_config.txt`, in `Ships/Script/`. Edit a value, save, restart the DSKY. A bad line is skipped and a warning says so.

The checklists assume the craft is ready to fly. To start with the archive already selected, so that `SWITCH TO 0.` is not needed, pick `boot/lm_boot.ks` as the boot file on the kOS processor in the VAB or SPH.

<!--table vt-->
| Setting | Default | Use |
|---|---|---|
| ENG_THR_CONT | MAN | MAN: the throttle lever is yours from ignition. AUTO: the computer works the throttle, and a short burn stays at minimum. |
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

### Update programme P27 (V71, V72)

Only in P00. Everything is octal.

<!--table st-->
| Keys | Does |
|---|---|
| `V71E`, `II E`, `AAAA E`, `XXXXX E` for each word, `V33E` | Block update: write the words from address `AAAA`. `II` is the number of words plus 2 (3 to 24 octal) |
| `V72E`, `II E`, `AAAA E` `XXXXX E` pairs, `V33E` | Scatter update: `II` is odd (3 to 23 octal), twice the pairs plus 1 |
| `V34E` | Throw the block away |

~V21 N01~ flashes while P27 runs. R1 shows the digits you key, R3 the address the word goes to. At the verify step (N02) answer `V33E` to store or `V34E` to discard. An 8 or 9, a bad count, or an address the store does not hold gives OPR ERR and the whole block is dropped.

> NOTE: The AGC clock counts from the vessel's mission time zero, which KSP restarts at an undock. The planner saves that zero in `clock.txt`, so you can plan docked, undock, then send.
