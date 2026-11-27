# Apollo LM Guidance System

An Apollo Lunar Module-inspired guidance computer for Kerbal Space Program, written in KerboScript (kOS), with a DSKY-style display. It plans and flies a lunar landing, aborts, the ascent back to orbit and the rendezvous with the command and service module (CSM).

**Manual:** the [Pilot's Pack](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/) ([PDF](docs/PACK.pdf), or only the [cards and checklists](docs/CHECKLISTS.pdf)) · **Forms:** the [LM PADs](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/pads.html), the crew's data cards recreated (also `docs/pads.html`)

**Supported landers:** Apollo LM replicas in Realism Overhaul only. It has been flown on the test craft below; other replicas are untested. The [changelog](CHANGELOG.md) lists what has not been flown.

## Requirements

- Kerbal Space Program 1.12.5
- [kOS](https://github.com/KSP-KOS/KOS) 1.6.0.1, with a kOS processor on the lander
- [Realism Overhaul](https://github.com/KSP-RO/RealismOverhaul) and its dependencies
- Sol (replaces RSS, from BallisticFox's Discord) or [Real Solar System](https://github.com/KSP-RO/RealSolarSystem) with its dependencies and textures

Both are supported. It was tested with Sol, Mirage and TiltEm together. Mirage is recommended with Sol, and works best with TiltEm; this program does not need TiltEm.

## Install

Download the zip from [Releases](https://github.com/EclipticPoyo/apollo-lm-guidance-kos/releases) and unzip it into your KSP folder. To install from source, see the [development notes](docs/DEVELOPMENT.md).

**Test craft:** `craft/` in the repository has the two landers it was flown on (`H Class`, `J Class`) and two CSMs for the ascent. Copy them to `<KSP>/saves/<your save>/Ships/VAB/`. Other mod versions may need part changes.

## First flight

**Follow the [Pilot's Pack](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/) to fly.** Start with the [overview](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/#p-1-1), then work through the [checklists](https://eclipticpoyo.github.io/apollo-lm-guidance-kos/#p-3-1). They give every key to press and what you should see.

To check it is installed, put the lander in lunar orbit and type in the kOS terminal:

```
SWITCH TO 0.
RUN plan.
```

The planner window opens. Pick a site, press PLAN, then SEND, and close it. Then start the DSKY, and carry on from the checklists:

```
RUN dsky.
```

## Made with Claude

I wrote this with Claude (Anthropic's AI) in Claude Code. I decided what to build, flew and tested everything in KSP, and checked it against the Apollo source. Claude wrote most of the code.

## More

- [Roadmap](https://github.com/EclipticPoyo/apollo-lm-guidance-kos/blob/main/ROADMAP.md)
- Based on the [Apollo Lunar Surface Journal](https://www.ibiblio.org/apollo/), the Luminary 099 source in [chrislgarry/apollo-11](https://github.com/chrislgarry/apollo-11) and the Luminary 210 source in [virtualagc](https://github.com/virtualagc/virtualagc); [kOS documentation](https://ksp-kos.github.io/KOS_DOC/)
- DSKY digits from Eugene Dorr's Zerlina font ("dsky-fonts", SIL Open Font License 1.1; `lm/images/Zerlina-OFL.txt`)
