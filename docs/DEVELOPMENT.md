# Development notes

The run steps, pad tests and flight probes for each milestone, moved here from the README. For flying the lander see the [manual](MANUAL.md).

## Milestone run steps and pad tests

Logs: all the flight logs below (`lm_check.log`, `p63.log`, `p64.log`, `p65.log`, the planner's `lm_deorbit.log`) are off by default. Set `LM_LOG = TRUE` in `scripts/lm/lm_config.txt` (remove the `//` in front of it; or set `GLOBAL LM_LOG IS TRUE.` in `scripts/lm/lm_constants.ks`) to write them (for bug reports or flight analysis). The pad tests and probes always write their own logs.

Quick start (1.1): run the planner with `RUN plan.` (the stub `plan.ks`, copied by hand like `dsky.ks`, runs `scripts/lm/planner/lm_plan_ui.ks`) and press CLOSE when you have finished planning, fly the burns, then in the kOS terminal type `RUN dsky.` (the stub `dsky.ks` in `<KSP>/Ships/Script/`, copied by hand, runs `scripts/core/dsky.ks`) and `V37 E 63 E`. The DSKY takes the site from the saved plan only (`0:/lm/plan.json`); with no plan it still runs, its registers show `-----` and P63 refuses with OPR ERR and a message. The 1.0 start-up arguments (site latitude, longitude, height), the perilune fallback, the placeholder site and the start-up plan check line are gone. The milestone steps below were written for 1.0 and now say `RUN dsky.` where they started the old `lm_main.ks`.

`scripts/` mirrors the kOS archive: `scripts/<x>` is `0:/<x>`. One-time junctions per PC: `Script\core`, `Script\lm`, `Script\shared` and `Script\tests` to the repo's `scripts\` subfolders. Offline checks (no KSP): `python scripts/tests/check_names.py` (name clashes), `python scripts/tests/check_paths.py` (every `RUNPATH`/`RUNONCEPATH` target exists), `python scripts/tests/reference.py` (expected pad-test numbers). The settings file reader's pad test is `RUNPATH("0:/tests/test_config.ks").`. The boot file `scripts/boot/lm_boot.ks` (copied by hand to `<KSP>/Ships/Script/boot/` and chosen as the kOS part's boot file in the VAB) does `SWITCH TO 0.` when the ship loads. `RUN pad.` runs all the pad tests in turn (the one-line stub `pad.ks` in `<KSP>/Ships/Script/`, copied by hand, runs `scripts/tests/run_all.ks`) and prints one summary line each, also written to `0:/lm/logs/tests_summary.log`. The DSKY core's pad test is `RUNPATH("0:/tests/test_core.ks").` (log `0:/lm/logs/test_core.log`).

Milestone 1 (navigation and DSKY display, read-only: it steers nothing):

1. Junction `scripts/core`, `lm`, `shared` and `tests` into `<KSP>/Ships/Script/` (see above), so kOS sees them as `0:/core/` and so on.
2. In the kOS terminal, in the Moon's sphere of influence, with a saved plan: `RUN dsky.` (1.0 took the site as arguments; 1.1 reads it from the plan).
   Without a plan the registers show `-----`.
3. A DSKY window opens. Type or click `V16 N60 E` (and N61-N68 as they come online). `V34 E` ends the program.
4. Cross-check results (our maths against kOS's own readings) are logged to `0:/lm/logs/lm_check.log`.

Milestone 2 (landing-site selection and deorbit planner; it adds maneuver nodes, you fly them):

1. In a bound lunar orbit above the PDI altitude (for example about 110 km circular), with no time warp and no maneuver nodes,
   the easy way is the planner window: `RUN plan.` (pick an Apollo site or type lat/long, press PLAN).
   Or from the terminal: `RUNPATH("0:/lm/planner/lm_deorbit.ks", lat, lng).` (degrees; optional 3rd argument: site height in m above sea level).
   Optional 4th argument: the largest plane-change burn to accept in m/s (default 200). Optional 5th: `TRUE` replaces existing nodes.
2. The script adds a plane-change node (only if the site is more than 2 km out of the orbit plane) and a DOI node, checks the result against
   kOS's own orbit prediction, and prints and logs a report to `0:/lm/logs/lm_deorbit.log`. On any failure it removes its own nodes and says why.
3. Fly the nodes by hand. The plan is saved to `0:/lm/plan.json` for the later descent programmes.
   Warp to each node yourself. After the DOI burn, start `RUN dsky.`: it uses the saved plan's site
   (it never warps by itself; warping is part of P63 from milestone 3: V37 E 63 E turns the lander to the burn attitude, then warps to 60 s before ignition).
   At PDI (the perilune of the descent orbit) `V16 N60 E` shows HCALC (about 15 km above the site radius for the default constants)
   and `V16 N68 E` the range to the site.
4. Pad tests: `RUNPATH("0:/tests/test_plan.ks").` (log `0:/lm/logs/test_plan.log`). One-off flight probe: `RUNPATH("0:/tests/probe_predict.ks").`

Milestone 3 (P63 braking; flown and working):

1. Fly the planner's nodes as above, so the lander is on the descent orbit.
2. `RUN dsky.` then `V37 E 63 E`. The lander turns to the burn attitude, warps to 60 s before ignition, counts down (the display is blank from TIG-35, counts from TIG-30, ullage at about TIG-7.5), asks for the engine at TIG-5 (**PRO** enables it), lights at TIG and goes to full throttle 26 s later. The window profile (windows up, or keep the roll as Apollo 11) is set in the planner window.
3. `V16 N61 E` shows the braking time to go in R1 (`+MM SS`); P63 hands over to P64 by itself when it falls below 62 s (milestone 4, below). `V34 E` ends it at any time. The SAS button is the AUTO / ATT HOLD switch.
4. Pad tests: `RUNPATH("0:/tests/test_p63.ks").` and `test_math.ks` (logs `0:/lm/logs/test_p63.log`, `0:/lm/logs/test_math.log`). Flight log: `0:/lm/logs/p63.log`. Steering probe: `tests/probe_steer.ks`.

Milestone 4 (P64 approach and redesignation; flown and working in UP window mode):

1. Fly P63 as above. When braking is over the terminal prints "P63 COMPLETE. P64 STARTS." and "P64 started", PROG shows 64 and the display shows `V06 N64` flashing (KEY REL lit): R1 is the look angle to the site in degrees, R2 the descent rate (ft/s), R3 the height (ft). P64 steers and throttles on to the approach targets (the window faces the site in `UP` mode; `KEEP` keeps the ship's roll as in P63) and hands over to P65 by itself, about 150 s later, at 12 s to go (milestone 5, below). `V34 E` ends it at any time.
2. **Redesignation:** press **PRO** once to permit it (the flashing stops). Then each tap of the pitch keys (W and S in KSP's default key map) moves the aim point 0.5 degree and each tap of the yaw keys (A and D) 2 degrees (flight 2 confirms which keys give pitch and yaw on the RO LM), in AUTO only (SAS off), until about 34 s before the end of P64. A held key is one click. The terminal prints nothing per click: the look angle in R1 changes and a green arrow (no label) stands on the site in the flight view during P64 and follows the aim point. The terminal prints "REDESIGNATION CLOSED" once when the window closes. If a key moves the aim point the wrong way, flip `P64_PITCH_SIGN` or `P64_YAW_SIGN` in `lm_config.txt`.
3. Pad tests: `RUNPATH("0:/tests/test_p64.ks").`, `test_p63.ks` and `test_math.ks` (logs `0:/lm/logs/test_p64.log` and so on). Flight log: `0:/lm/logs/p64.log`. Reference numbers: `python scripts/tests/reference.py`.

Milestone 5 (P65 final descent, P66 rate of descent, touchdown; flown and working):

1. Fly P63 and P64 as above. At 12 s to go P64 hands over to P65 (the terminal prints "P65 started" and then clears, PROG shows 65 and the display `V06 N60`: R1 horizontal speed, R2 descent rate, R3 height, ft/s and ft; the top three terminal lines show a live readout: the descent rate in m/s, the P65 target and a key hint). P65 nulls the horizontal speed and settles to a descent of 3 ft/s (0.9 m/s); the thrust direction follows the guidance and the ship keeps its roll (a roll key still rolls it in AUTO).
2. **P66:** switch SAS on (the ATT HOLD switch), then tap **Shift** (throttle up) or **Ctrl** (throttle down) in KSP: each tap is one rate-of-descent click and the first one starts P66 (PROG 66). As in Luminary 099, a click in AUTO (SAS off) is ignored and SAS on by itself does nothing. Shift raises the commanded rate by 1 ft/s (a slower descent), Ctrl lowers it (a faster descent); the readout's "P66 COMMANDED" line shows the new rate in m/s and nothing is printed per click. In P66 the throttle holds the commanded rate and the attitude is no longer guided: you fly it with SAS on (the ship keeps the last P65 direction if you switch SAS off again). The clicks use the throttle keys' lever, which the programme keeps near the middle. If a key moves the rate the wrong way, flip `P66_ROD_SIGN` in `lm_config.txt`.
3. **Touchdown:** the CONTACT lamp lights when the lander touches down (the ship's status turns LANDED) and the engine cuts off on the next cycle, a quarter of a second later (stop it yourself first if you like); PROG shows 68 and the programme ends with the controls handed back. This is not what the crew did (they stopped the engine by hand) and is documented as a simplification.
4. **Site marker (experimental):** while a programme runs, the same green map pin the planner window uses, labelled "LM SITE", stands on the landing site in map view (during P64 an unlabelled arrow also stands on it in the flight view) (kOS cannot create real map waypoints, so it is a vecdraw arrow standing above the site and pointing down at it). Its size is set by `PINS_*` in `lm/planner/lm_site_pins.ks`. It follows the site when you redesignate.
5. Pad tests: `RUNPATH("0:/tests/test_p65.ks").`, `test_p64.ks`, `test_p63.ks` and `test_math.ks`. Flight log: `0:/lm/logs/p65.log`. Reference numbers: `python scripts/tests/reference.py` ("Milestone 5" section). One-off probe: `tests/probe_rod.ks` (the throttle keys as the ROD input).
