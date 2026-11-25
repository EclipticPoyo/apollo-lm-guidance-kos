# Apollo LM Guidance System

An Apollo Lunar Module-inspired guidance computer for Kerbal Space Program, written in KerboScript (kOS). It plans the descent, flies the DOI and other burns (P30, P40, P41, P47), flies the powered descent and landing (P63 braking, P64 approach, P65 automatic landing, P66 rate of descent) and flies the ascent back to lunar orbit (P12), with a DSKY-style display.

**Not guaranteed:** it was only tested on one Realism Overhaul LM, in that setup. It has not been tested on any other lander and is not guaranteed to work at all.

**Status:** flown and confirmed in KSP on that lander: planning, P63 braking, P64 approach with redesignation (both window modes), P65 automatic landing, P66 rate of descent and touchdown, with the Apollo 11 profile; and planning, P63, P64, P66 and touchdown with the J-class profile.

**Release 1.4 (burn programmes: P30, P40, P41, P47)** passes its pad tests, and the DOI burn, an RCS trim and a P63 landing (as a regression) were flown and confirmed in KSP.

**Release 1.5 (ascent: P12, the planner's lift-off time and PAD, V82)** was flown in KSP from the surface to lunar orbit. It reaches the insertion targets; whether the lift-off time leads to a rendezvous cannot be tested until the rendezvous programmes exist.

## Dependencies

**Required**

- Kerbal Space Program 1.12.5
- [kOS](https://github.com/KSP-KOS/KOS) 1.6.0.1 (a kOS processor on the lander)
- [Realism Overhaul](https://github.com/KSP-RO/RealismOverhaul) (RO) and its own dependencies
- Sol (replaces RSS), available from BallisticFox's Discord

**Recommended**

- Mirage
- TiltEm, if you use Mirage (Mirage works best with it; this program does not need it)

It was only tested with these installed together.

## Install

**From the release zip:** unzip it into your KSP folder (it contains the stubs `Ships/Script/dsky.ks` and `plan.ks` and the folders `core/`, `lm/` and `shared/` beside it). Nothing else to do.

**From the source:**

1. Copy the `core`, `lm` and `shared` folders from `scripts` into `<KSP>/Ships/Script/`, so kOS sees them as `0:/core/`, `0:/lm/` and `0:/shared/`.
2. Create two one-line stubs in `<KSP>/Ships/Script/`: `dsky.ks` containing `RUNPATH("0:/core/dsky.ks").` and `plan.ks` containing `RUNPATH("0:/lm/planner/lm_plan_ui.ks").`

**Test craft:** the `craft/` folder in the repository has the two Realism Overhaul landers the program was flown on, `H Class.craft` and `J Class.craft` (KSP 1.12.5). Copy them to `<KSP>/saves/<your save>/Ships/VAB/`. They need the mods under Dependencies and may need part changes with other mod versions.

## Run

On a lander in lunar orbit, in the kOS terminal, first plan the descent:

```
RUN plan.
```

Pick a site, press PLAN, then SEND (this writes the data Mission Control would uplink; tick *Skip simulated uplink* to let the DSKY load the plan itself), close the planner with the cross in its corner and fly the burns. Then start the DSKY, which presses the uplink in, and type `V37 E 63 E`:

```
RUN dsky.
```

After landing, to go back to orbit: close the DSKY, target the CSM, `RUN plan.`, choose *Ascent*, press PLAN, then `RUN dsky.` and `V37 E 12 E`.

## How to fly it

See the **[Pilot's Pack](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/)**, the manual: a landing card, reference tables and checklists. Download the [PDF](docs/PACK.pdf) (A4, one page per sheet) to print it.

## Made with Claude

I wrote this with Claude (Anthropic's AI) in Claude Code. I decided what to build, flew and tested everything in KSP, and checked it against the Apollo source. Claude wrote most of the code.

## More

- The DSKY digits (and the register values in the Pilot's Pack) are drawn from the Zerlina font by Eugene Dorr (from his "dsky-fonts" collection, SIL Open Font License 1.1; licence in `lm/images/Zerlina-OFL.txt`)
- [Roadmap](https://github.com/EclipticPoyo/apollo-lm-guidance-kos/blob/main/ROADMAP.md)
- [Development notes and pad tests](docs/DEVELOPMENT.md)
- Based on the [Apollo Lunar Surface Journal](https://www.ibiblio.org/apollo/) and the Luminary 099 source in [chrislgarry/apollo-11](https://github.com/chrislgarry/apollo-11); [kOS documentation](https://ksp-kos.github.io/KOS_DOC/)
