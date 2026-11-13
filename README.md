# Apollo LM Guidance System

An Apollo Lunar Module-inspired guidance computer for Kerbal Space Program, written in KerboScript (kOS). It plans the descent and flies the powered descent and landing (P63 braking, P64 approach, P65 automatic landing, P66 rate of descent) with a DSKY-style display.

Target: the Sol planet pack with Mirage and TiltEm, Realism Overhaul (RO) and kOS 1.6.0.1.

**Not guaranteed:** it was only tested on one Realism Overhaul LM, in that setup. It has not been tested on any other lander and is not guaranteed to work at all.

## Install

**From the release zip:** unzip it into your KSP folder (it contains `Ships/Script/start.ks` and `Ships/Script/lm/`). Nothing else to do.

**From the source:**

1. Copy the `scripts` folder to `<KSP>/Ships/Script/lm`, so kOS sees it as `0:/lm/`.
2. Create `<KSP>/Ships/Script/start.ks` containing: `RUNPATH("0:/lm/lm_start.ks").`

## Run

On a lander in lunar orbit, in the kOS terminal:

```
RUN start.
```

Plan the descent in the window that opens, press CLOSE, and the DSKY starts.

## How to fly it

See the **[Pilot's Manual](docs/MANUAL.md)** ([PDF](docs/MANUAL.pdf)).

## Made with Claude

I wrote this with Claude (Anthropic's AI) in Claude Code. I decided what to build and tested it all in KSP; Claude wrote most of the code.

## More

- [Development notes and pad tests](docs/DEVELOPMENT.md)
- Based on the [Apollo Lunar Surface Journal](https://www.ibiblio.org/apollo/) and the Luminary 099 source in [chrislgarry/apollo-11](https://github.com/chrislgarry/apollo-11); [kOS documentation](https://ksp-kos.github.io/KOS_DOC/)
