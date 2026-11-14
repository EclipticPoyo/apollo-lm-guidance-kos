# Apollo LM Guidance System

An Apollo Lunar Module-inspired guidance computer for Kerbal Space Program, written in KerboScript (kOS). It plans the descent and flies the powered descent and landing (P63 braking, P64 approach, P65 automatic landing, P66 rate of descent) with a DSKY-style display.

Target: the Sol planet pack with Mirage and TiltEm, Realism Overhaul (RO) and kOS 1.6.0.1.

**Not guaranteed:** it was only tested on one Realism Overhaul LM, in that setup. It has not been tested on any other lander and is not guaranteed to work at all.

## Install

**From the release zip:** unzip it into your KSP folder (it contains the stubs `Ships/Script/dsky.ks` and `plan.ks` and the folders `core/`, `lm/` and `shared/` beside it). Nothing else to do.

**From the source:**

1. Copy the `core`, `lm` and `shared` folders from `scripts` into `<KSP>/Ships/Script/`, so kOS sees them as `0:/core/`, `0:/lm/` and `0:/shared/`.
2. Create two one-line stubs in `<KSP>/Ships/Script/`: `dsky.ks` containing `RUNPATH("0:/core/dsky.ks").` and `plan.ks` containing `RUNPATH("0:/lm/planner/lm_plan_ui.ks").`

**Test craft:** the `craft/` folder in the repository has the two Realism Overhaul landers the program was flown on, `H Class.craft` and `J Class.craft` (KSP 1.12.5). Copy them to `<KSP>/saves/<your save>/Ships/VAB/`. They need the same mods as above and may need part changes with other mod versions.

## Run

On a lander in lunar orbit, in the kOS terminal, first plan the descent:

```
RUN plan.
```

Pick a site, press PLAN, press CLOSE and fly the burns. Then start the DSKY and type `V37 E 63 E`:

```
RUN dsky.
```

## How to fly it

See the **[Pilot's Manual](docs/MANUAL.md)** ([PDF](docs/MANUAL.pdf)).

## Made with Claude

I wrote this with Claude (Anthropic's AI) in Claude Code. I decided what to build, flew and tested everything in KSP, and checked it against the Apollo source. Claude wrote most of the code.

## More

- The DSKY digits are drawn from the Zerlina font by Eugene Dorr (from his "dsky-fonts" collection, SIL Open Font License 1.1; licence in `lm/images/Zerlina-OFL.txt`)
- [Roadmap](https://github.com/EclipticPoyo/apollo-lm-guidance-kos/blob/main/ROADMAP.md): what is planned next
- [Development notes and pad tests](docs/DEVELOPMENT.md)
- Based on the [Apollo Lunar Surface Journal](https://www.ibiblio.org/apollo/) and the Luminary 099 source in [chrislgarry/apollo-11](https://github.com/chrislgarry/apollo-11); [kOS documentation](https://ksp-kos.github.io/KOS_DOC/)
