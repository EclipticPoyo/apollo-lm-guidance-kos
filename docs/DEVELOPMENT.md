# Development notes

The run steps, pad tests and flight probes for each milestone, moved here from the README. For flying the lander see the [pilot's pack](PACK.pdf).

## Milestone run steps and pad tests

Logs: all the flight logs below (`lm_check.log`, `p63.log`, `p64.log`, `p65.log`, the planner's `lm_deorbit.log`) are off by default. Set `LOG = TRUE` under `[COMMON]` in `Ships/Script/agc_config.txt` (the repo's template is `scripts/agc_config.txt`; copy it once to `Ships/Script/`, like the stubs, because only the subfolders are junctioned; change `LOG = FALSE` to `TRUE`; or set `GLOBAL LM_LOG IS TRUE.` in `scripts/lm/lm_constants.ks`) to write them (for bug reports or flight analysis). The pad tests and probes always write their own logs.

Quick start (1.1): run the planner with `RUN plan.` (the stub `plan.ks`, copied by hand like `dsky.ks`, runs `scripts/lm/planner/lm_plan_ui.ks`) and press CLOSE when you have finished planning, fly the burns, then in the kOS terminal type `RUN dsky.` (the stub `dsky.ks` in `<KSP>/Ships/Script/`, copied by hand, runs `scripts/core/dsky.ks`) and `V37 E 63 E`. The DSKY takes the site from the saved plan only (`0:/lm/plan.json`); with no plan it still runs, its registers show `-----` and P63 refuses with OPR ERR and a message. The 1.0 start-up arguments (site latitude, longitude, height), the perilune fallback, the placeholder site and the start-up plan check line are gone. The milestone steps below were written for 1.0 and now say `RUN dsky.` where they started the old `lm_main.ks`.

`scripts/` mirrors the kOS archive: `scripts/<x>` is `0:/<x>`. One-time junctions per PC: `Script\core`, `Script\lm`, `Script\shared` and `Script\tests` to the repo's `scripts\` subfolders. Offline checks (no KSP): `python scripts/tests/check_names.py` (name clashes), `python scripts/tests/check_paths.py` (every `RUNPATH`/`RUNONCEPATH` target exists), `python scripts/tests/check_syntax.py` (balanced brackets and strings), `python scripts/tests/check_pack.py` (the pack's settings, nouns, verbs, programmes and quoted numbers still match the code; run it before a release and after changing a constant the pack quotes), `python scripts/tests/reference.py` (expected pad-test numbers). The settings file reader's pad test is `RUNPATH("0:/tests/test_config.ks").`. The boot file `scripts/boot/lm_boot.ks` (copied by hand to `<KSP>/Ships/Script/boot/` and chosen as the kOS part's boot file in the VAB) does `SWITCH TO 0.` when the ship loads. `RUN pad.` runs all the pad tests in turn (the one-line stub `pad.ks` in `<KSP>/Ships/Script/`, copied by hand, runs `scripts/tests/run_all.ks`) and prints one summary line each, also written to `0:/lm/logs/tests_summary.log`. The DSKY core's pad test is `RUNPATH("0:/tests/test_core.ks").` (log `0:/lm/logs/test_core.log`).

Milestone 1 (navigation and DSKY display, read-only: it steers nothing):

1. Junction `scripts/core`, `lm`, `shared` and `tests` into `<KSP>/Ships/Script/` (see above), so kOS sees them as `0:/core/` and so on.
2. In the kOS terminal, in the Moon's sphere of influence, with a saved plan: `RUN dsky.` (1.0 took the site as arguments; 1.1 reads it from the plan).
   Without a plan the registers show `-----`.
3. A DSKY window opens. Type or click `V16 N60 E` (and N61-N68 as they come online). The X in the window (then YES) ends the program.
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
3. `V16 N61 E` shows the braking time to go in R1 (`+MM SS`); P63 hands over to P64 by itself when it falls below 62 s (milestone 4, below). V37 E 00 E ends it at any time (V34 E only answers P63's enable prompt, as in Luminary). The SAS button is the AUTO / ATT HOLD switch.
4. Pad tests: `RUNPATH("0:/tests/test_p63.ks").` and `test_math.ks` (logs `0:/lm/logs/test_p63.log`, `0:/lm/logs/test_math.log`). Flight log: `0:/lm/logs/p63.log`. Steering probe: `tests/probe_steer.ks`.

Milestone 4 (P64 approach and redesignation; flown and working in UP window mode):

1. Fly P63 as above. When braking is over the terminal prints "P63 COMPLETE. P64 STARTS." and "P64 started", PROG shows 64 and the display shows `V06 N64` flashing (KEY REL lit): R1 is the look angle to the site in degrees, R2 the descent rate (ft/s), R3 the height (ft). P64 steers and throttles on to the approach targets (the window faces the site in `UP` mode; `KEEP` keeps the ship's roll as in P63) and hands over to P65 by itself, about 150 s later, at 12 s to go (milestone 5, below). V37 E 00 E ends it at any time (V34 E only answers P63's enable prompt, as in Luminary).
2. **Redesignation:** press **PRO** once to permit it (the flashing stops). Then each tap of the pitch keys (W and S in KSP's default key map) moves the aim point 0.5 degree and each tap of the yaw keys (A and D) 2 degrees (flight 2 confirms which keys give pitch and yaw on the RO LM), in AUTO only (SAS off), until about 34 s before the end of P64. A held key is one click. The terminal prints nothing per click: the look angle in R1 changes and a green arrow (no label) stands on the site in the flight view during P64 and follows the aim point. The terminal prints "REDESIGNATION CLOSED" once when the window closes. If a key moves the aim point the wrong way, flip `P64_PITCH_SIGN` or `P64_YAW_SIGN` in `lm_config.txt`.
3. Pad tests: `RUNPATH("0:/tests/test_p64.ks").`, `test_p63.ks` and `test_math.ks` (logs `0:/lm/logs/test_p64.log` and so on). Flight log: `0:/lm/logs/p64.log`. Reference numbers: `python scripts/tests/reference.py`.

Milestone 5 (P65 final descent, P66 rate of descent, touchdown; flown and working):

1. Fly P63 and P64 as above. At 12 s to go P64 hands over to P65 (the terminal prints "P65 started" and then clears, PROG shows 65 and the display `V06 N60`: R1 horizontal speed, R2 descent rate, R3 height, ft/s and ft; the top three terminal lines show a live readout: the descent rate in m/s, the P65 target and a key hint). P65 nulls the horizontal speed and settles to a descent of 3 ft/s (0.9 m/s); the thrust direction follows the guidance and the ship keeps its roll (a roll key still rolls it in AUTO).
2. **P66:** switch SAS on (the ATT HOLD switch), then tap **Shift** (throttle up) or **Ctrl** (throttle down), or **H** (slower) or **N** (faster), in KSP: each tap is one rate-of-descent click (the Shift/Ctrl detector counts a lever move of `ROD_LEVER_STEP` = 0.001, so even a very short tap on a weak keyboard registers; H and N are the fallback) and the first one starts P66 (PROG 66). As in Luminary 099, a click in AUTO (SAS off) is ignored and SAS on by itself does nothing. Shift raises the commanded rate by 1 ft/s (a slower descent), Ctrl lowers it (a faster descent); the readout's "P66 COMMANDED" line shows the new rate in m/s and nothing is printed per click. In P66 the throttle holds the commanded rate and the attitude is no longer guided: you fly it with SAS on (the ship keeps the last P65 direction if you switch SAS off again). The clicks use the throttle keys' lever, which the programme keeps near the middle. If a key moves the rate the wrong way, flip `P66_ROD_SIGN` in `lm_config.txt`.
3. **Touchdown:** the CONTACT lamp lights when the lander touches down (the ship's status turns LANDED) and the engine cuts off on the next cycle, a quarter of a second later (stop it yourself first if you like); PROG shows 68 and the programme ends with the controls handed back. This is not what the crew did (they stopped the engine by hand) and is documented as a simplification.
4. **Site marker (experimental):** while a programme runs, the same green map pin the planner window uses, labelled "LM SITE", stands on the landing site in map view (during P64 an unlabelled arrow also stands on it in the flight view) (kOS cannot create real map waypoints, so it is a vecdraw arrow standing above the site and pointing down at it). Its size is set by `PINS_*` in `lm/planner/lm_site_pins.ks`. It follows the site when you redesignate.
5. Pad tests: `RUNPATH("0:/tests/test_p65.ks").`, `test_p64.ks`, `test_p63.ks` and `test_math.ks`. Flight log: `0:/lm/logs/p65.log`. Reference numbers: `python scripts/tests/reference.py` ("Milestone 5" section). One-off probe: `tests/probe_rod.ks` (the throttle keys as the ROD input).

## Release 1.5: ascent

Spec `docs/superpowers/specs/2026-11-25-ascent-design.md`, research `docs/superpowers/research-1.5-ascent.md` (probe results in section 10a), plan `docs/superpowers/plans/2026-11-25-ascent.md`, the KSP session `docs/superpowers/ksp-batch-1.5.md`.

- **Pieces:** guidance as pure functions (`lm/ascent/lm_ascent_guid.ks`), P12 (`lm/ascent/lm_p12.ks`, on `lm_burnbaby.ks` with `bb_table_p12`), the planner (`lm/planner/lm_ascent_plan.ks`), the delta-V pass shared with P40, P41 and P47 (`lm/burn/lm_servicer.ks`), staging and ascent steering (`lm/descent/lm_control.ks`), the extended-verb display behind V82 (`ks["EXT"]` in `core/dsky_core.ks`).
- **Offline:** `python scripts/tests/reference_ascent.py` (the reference model: guidance, engine filter, a full ascent, the phasing; it gives the pad tests their numbers).
- **Pad tests** (in `RUN pad.`): `test_ascent` (guidance), `test_v82` (orbit numbers and the extended display), `test_ascent_plan` (phasing, lift-off search, PAD), `test_p12` (the programme, including a whole ascent in software; allow several minutes). `test_load`, `test_store` and `test_burnbaby` were extended.
- **Probes:** `scripts/tests/probe_ascent_all.ks` (parts, decoupler, engines) and `probe_ascent_fly.ks` (staging, RCS steering and propellant use in flight; it flies the ship).
- **Logs:** `0:/lm/logs/p12.log` is rewritten at each P12 start: the `#` lines at ignition and cut-off always (with the CSM's angle ahead), one row per cycle with `LOG = TRUE`.

## Release 1.4: burn programmes

All pad tests (`RUN pad.`) pass in KSP, and the DOI, a P41 trim and a P63 landing (as a regression) were flown (`docs/superpowers/ksp-batch-1.4-checklist-2.md`). Plan `docs/superpowers/plans/2026-11-23-burn-programmes.md`, spec `docs/superpowers/specs/2026-11-23-burn-programmes-design.md`.

- **New pad test** (in `RUN pad.`): `test_burn` (the S40 routines, P41SPOT, apsides and MGA in `lm/burn/lm_burn_s.ks`); `test_plan` was extended for `plan_lv_to_dv`. Python reference: `python scripts/tests/reference_burn.py`. Passes in KSP.
- **New pad test** (in `RUN pad.`): `test_burnbaby` (the burn engine `lm/burn/lm_burnbaby.ks`: the P63 table against `seq_step` step by step, the P40 and P41 tables, cutoff, retime and `resp_read`). Passes in KSP.
- **New pad test** (in `RUN pad.`): `test_p41` (P41 RCS burn and P47 thrust monitor, `lm/burn/lm_p41.ks`: refusals, R02, the R60 and countdown displays, the blank, the 1703 slip, VG falling as a made-up push is measured, flashing N85 at TIG and its returns, no engine ever lit, P47's 20 s wait and N83 with ENTR, V32, PRO and V34). Passes in KSP. Run it with `RUNPATH("0:/tests/test_p41.ks").`
- **New pad test** (in `RUN pad.`): `test_p40` (P40 DPS burn, `lm/burn/lm_p40.ks`: refusals, alarm 1706, R02, the R60 and P40AUTO displays, the 1703 slip, the countdown, prompt and ignition, the measured-delta-V cutoff on a simulated burn, AUTO zoom, MAN throttle and the lever floor, alarm 1407, V97, impulse burn, POST and TRIM, V34 and GOPOST, N40 and N85). Passes in KSP. Run it with `RUNPATH("0:/tests/test_p40.ks").`
- **New pad test** (in `RUN pad.`): `test_p30` (P30 external delta-V, `lm/burn/lm_p30.ks`: the N33, N81, N42, N45 sequence and each display's returns, the apsides of the DOI orbit, `LM_VEH["XDELV"]` and its timing by profile, refusals, zero delta-V, N42 and N45). Passes in KSP.

## Release 1.3.1: landing aids

Spec `docs/superpowers/specs/2026-11-15-landing-aids-design.md` (with the audit `docs/superpowers/audit-2026-11-15-landing.md` and the Luminary reading `...-landing-aids-reading.md`), plan `docs/superpowers/plans/2026-11-15-landing-aids.md`, the one KSP session `docs/superpowers/ksp-batch-1.3.1.md`.

- **Core pieces:** `core/dsky_alarm.ks` (alarm slots, lamp latch), the pending request (a programme step returns `REQUEST`; the core owns the flash, the KEY REL lamp and V32/V33/V34/PRO/ENTR, see the contract at the top of `dsky_core.ks`), `core_restart_display`, V35. The LM adds `lm_alarms.ks` (the `ALARMS` script), `descent/lm_p68.ks`, `descent_j/lm_j_nouns.ks`, the radar state (`lm_vehicle.ks`), the thrust monitor (`dvmon_*` in `lm_control.ks`) and the DLAND cell (`lm_cells.ks`).
- **New pad tests** (in `RUN pad.`): `test_alarm`, `test_keyrel`, `test_lr`, `test_script`, `test_p66`, `test_p68`, `test_dland`; `test_core`, `test_load`, `test_p27`, `test_p63`, `test_p64`, `test_p65` and `test_j` were extended. Python reference: `python scripts/tests/reference_alarm.py`. None had run in KSP when this was written.
- **The `ALARMS` setting** (`agc_config.txt`): `OFF`, `A11` or `code@seconds,...`; the schedule runs on the time since ignition.

## Release 1.3: uplink and loads

Nothing here has run in KSP at the time of writing: it was built with the KSP test session deferred to the end (`docs/superpowers/ksp-batch-1.3.md`). Spec `docs/superpowers/specs/2026-11-14-uplink-and-loads-design.md` (with its "Research results"), plan `docs/superpowers/plans/2026-11-14-uplink-and-loads.md`.

- **Offline checks (no KSP):** `python scripts/tests/reference_loads.py` (the reference model: ECADR rule, double-precision words, the V71/V72/V25 keystrokes and the PAD text; it reads the cell table from `lm/lm_cells.ks`), `check_syntax.py` (balanced brackets and strings, since kOS only finds a syntax error when the file loads), `check_names.py`, `check_paths.py`.
- **Pad tests** (added to `RUN pad.`): `test_store` (store, words, RLS and TLAND conversions, the plan from the store and the auto-mode fill), `test_load` (V21 to V25 and the LM's N33 and N81 loads), `test_p27` (V71, V72, V33, V34, refusals), `test_uplink` (the key-file feed), `test_pad` (the PAD builder, against the reference model). `test_plan` also checks `plan_lv_components`.
- **The store** is `core/dsky_store.ks` (vehicle-independent: cells of 15-bit words, ECADR lookup, octal and double-precision helpers); the LM's table is `lm/lm_cells.ks`, one cell per line (Python reads it too). To add a cell: find its bank and offset in `ERASABLE_ASSIGNMENTS` on the Virtual AGC site (`ibiblio.org/apollo/listings/Luminary099/`, Luminary210 likewise: the GitHub clone has no assembled listing), convert the octal offset to decimal (1400 octal is 768), take its scale from the same listing, and add a line for both versions. ECADR = bank x 256 + offset - 768 (E4,1422 octal is 2022 octal).
- **Core contract:** the vehicle LEXICON gains `STORE`, `P27_OK`, `UPLINK_FILE`, `LOADS` and `LOAD_COMMIT` (documented at the top of `dsky_core.ks`). The key state `ks` gains `LOAD`, `P27`, `VEHICLE` and `PROGRAM`; `key_press` keeps its signature, and the loaders read the vehicle through `ks["VEHICLE"]`.
- **Departures from Apollo** are listed in the pack, appendix A. Behaviour taken from the source: P27 only in P00, V71 count II = words + 2 (octal, 3 to 20 decimal), V72 odd count, V33 verifies and stores, V34 terminates, UPLINK ACTY off on every exit (`UPDATE_PROGRAM.agc`); RLS B-27 metres Moon-fixed, TIG and TLAND centiseconds B-28, N81 VEL3 (`ERASABLE_ASSIGNMENTS.agc`, `R30.agc`, `PINBALL_NOUN_TABLES.agc`). Assumed, not checked: the B-7 m/cs scale of `DELVLVC`, and the PINBALL load-verb behaviour (only skimmed).
- **Clock zero:** TLAND and TIG are centiseconds from the vessel's mission-time zero (`TIME:SECONDS - MISSIONTIME`), printed on the PAD. KSP restarts `MISSIONTIME` when the lander undocks (measured 2026-11-14: 961 s before, 35 s just after), so the planner saves its zero in `0:/lm/clock.txt` when an uplink-mode PAD is made (`lm_clock_zero_save`) and the DSKY reads it (`lm_clock_zero_ut`); with no file, or a believable-looking one missing, the DSKY uses its own vessel's `TIME:SECONDS - MISSIONTIME`. Skip simulated uplink (the old auto mode) deletes the file (plan.json holds UT).

## Release 1.2: J-class descent (Luminary 210)

Design and findings: `docs/superpowers/specs/2026-11-13-j-class-pads-design.md`, `...-luminary210-logic-changes.md`, `...-luminary210-padloads-research.md`, `...-j-class-mass-performance-study.md`. The J programmes are copies of the Apollo 11 ones in `scripts/lm/descent_j/` (names `j_...` and `J_...`; the 099 files are untouched), chosen by the plan's `PROFILE` (`lm_vehicle.ks`).

1. Offline: `python scripts/tests/check_names.py`, `python scripts/tests/check_paths.py`, `python scripts/tests/reference_j.py` (expected numbers for `test_j.ks` and the mass study).
2. Pad tests: `RUN pad.` (now includes `test_j`; logs `0:/lm/logs/test_j.log` and so on). `test_plan` and `test_core` gained profile checks.
3. Flights: the batch is in `docs/superpowers/ksp-batch-1.2.md`. Logs: `j_p63.log`, `j_p64.log`, `j_p66.log`.
