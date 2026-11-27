# Development notes

How to run, test and check the code. For flying the lander see the [pilot's pack](PACK.pdf).

## Layout

`scripts/` mirrors the kOS archive: `scripts/<x>` is `0:/<x>`.

| Folder | Holds |
|---|---|
| `core/` | The DSKY core, independent of the vehicle. Its contract is the header of `dsky_core.ks`; only the entry script `dsky.ks` names the LM |
| `lm/` | The lander: vehicle table and nouns, `descent/`, `descent_j/` (J-class), `burn/`, `ascent/`, `rndz/`, `planner/`, `images/`, `logs/` |
| `shared/` | Code used by both |
| `tests/` | Pad tests, probes, Python models and offline checks |
| `boot/` | Optional boot file |

The planner chooses the software profile (`A11` or `J`) and saves it with the plan. The J-class descent programmes are separate copies in `descent_j/`, with `j_` and `J_` names.

## Setup in KSP

Install the mods listed in the [README](../README.md), then:

1. Put `core`, `lm`, `shared` and `tests` from `scripts/` into `<KSP>/Ships/Script/`. Linking them (Windows: `mklink /J <KSP>\Ships\Script\lm <repo>\scripts\lm`, and so on) lets edits and logs stay in the repository.
2. Copy `scripts/agc_config.txt` to `<KSP>/Ships/Script/`. Copy it again only when the template changes, and keep your own values.
3. Make the one-line stubs in `<KSP>/Ships/Script/`:

| Stub | Contents |
|---|---|
| `dsky.ks` | `RUNPATH("0:/core/dsky.ks").` |
| `plan.ks` | `RUNPATH("0:/lm/planner/lm_plan_ui.ks").` |
| `pad.ks` | `RUNPATH("0:/tests/run_all.ks").` |

4. Optional: copy `scripts/boot/lm_boot.ks` to `<KSP>/Ships/Script/boot/` and choose it as the boot file on the kOS part. It selects the archive when the ship loads.

## Running

Type `SWITCH TO 0.` once per session (unless the boot file does it), then `RUN plan.`, `RUN dsky.` or `RUN pad.`. The pilot's pack has the flight checklists.

## Logs

Logs are written under `0:/lm/logs/` (git-ignored). Pad tests and probes always write theirs, and the DSKY always writes `dsky.log` (every terminal warning and message with the mission clock, started afresh each run). Flight logs mostly need `LOG = TRUE` under `[COMMON]` in `agc_config.txt`; `p12.log`, `abort.log` and `rod.log` are written even without it; the first two gain a row per cycle when it is set.

## Offline checks (no KSP)

```
python scripts/tests/check_all.py
```

It runs the checks below and verifies that `RUN pad.` lists every pad test.

| Check | Finds |
|---|---|
| `check_names.py` | Names that clash with kOS built-ins or differ only by case |
| `check_syntax.py` | Unbalanced brackets and strings |
| `check_paths.py` | Script paths that do not resolve |
| `check_pack.py` | The pilot's pack out of step with the code |

The `reference*.py` models give the numbers the pad tests expect: `reference.py` (descent), `reference_j.py`, `reference_loads.py`, `reference_alarm.py`, `reference_burn.py`, `reference_ascent.py`, `reference_abort.py` and `reference_rndz.py`.

## Pad tests

`RUN pad.` runs every `test_*.ks` in turn (no flying needed) and writes a summary to `0:/lm/logs/tests_summary.log` and one log per test. Allow several minutes. One test alone: `RUNPATH("0:/tests/test_<name>.ks").`

A new test uses `test_lib.ks`, loads everything it calls, keeps its helper names unique (all tests share one session), and is added to `ra_names` in `run_all.ks`.

The rendezvous maths and programmes are covered by `test_conics`, `test_axes`, `test_csm`, `test_rndz`, `test_p32`, `test_p34`, `test_aim` (burns on an aim point), `test_p42`, `test_p20` (P20 and P25), `test_rverbs` (V83, V89, V90) and `test_term` (the drift gauge's maths and the docking message). The core's second slot, priority displays, answering displays and octal loads are in `test_back`. P20, P25 and the three verbs write `p20.log` (every tracking change, mark and result).

## Session helpers

`tests/rndz_setup.ks` sets up a rendezvous test. With the LM and a CSM in lunar orbit and the DSKY closed, it prints both orbits, the next apolune (as N11 keys), the CSM's phase angle then, and a TPI time (as N37 keys) or how far to move the CSM; once P33 has run, also the height difference and the elevation angle predicted at TPI. For TPI it prints the next time with the CSM 26.6 degrees up, a time for a short rendezvous (about 70 ft/s), the range and closing speed, and, with an intercept time in the saved DSKY store, the predicted miss. It only reads. Log: `rndz_setup.log`, added to by each run. A stub `rdzset.ks` holding `RUNPATH("0:/tests/rndz_setup.ks").` saves typing.

`tests/demo_gauge.ks` shows the drift gauge's window with made-up rates (any craft, nothing steered), to check it before a flight.

## Probes

One-off scripts that measure how KSP and kOS behave. Read the header of each before running it: some fly the ship or stage it, so quicksave first.

| Probe | Question |
|---|---|
| `probe_lander` | Mass, engines and propellant |
| `probe_window` | Which face the crew window is on |
| `probe_control`, `probe_steer` | The controls and steering settings used by the descent |
| `probe_predict` | Frame conventions for the planner |
| `probe_rendezvous` | The CSM's state, prediction accuracy, load distances, docking ports and RCS |
| `probe_axes` | The height at which the raw axes stop turning with the Moon |
| `probe_needle` | Whether a picture can be slid smoothly over another widget (the drift gauge's needles) |
| `probe_rod`, `probe_translation` | Whether the rate-of-descent keys can be read |
| `probe_throttle` | RCS fore-by-throttle, engine shutdown and the lever |
| `probe_ascent`, `probe_ascent_fly`, `probe_ascent_all` | Parts, staging and the ascent engine |
| `probe_abort`, `probe_abort_stage` | Abort keys and staging in flight |

## The stored loads

The DSKY's erasable store is `core/dsky_store.ks`; the lander's cell table is `lm/lm_cells.ks`, one cell per line (a Python model reads it too). To add a cell, find its bank, offset and scale in `ERASABLE_ASSIGNMENTS` on the [Virtual AGC listings](https://www.ibiblio.org/apollo/listings/Luminary099/) (and Luminary210), convert the octal offset to decimal (octal 1400 is 768), and add a line for both versions. The uplink address is bank x 256 + offset - 768.

## Releases

`python make_pack.py --pdf` builds the pack (needs the `markdown` package and Edge or Chrome). `python make_release.py <version>` writes the zip to `dist/`; the version must match `VERSION`.
