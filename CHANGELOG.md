# Changelog

All notable changes to the Apollo LM guidance computer for kOS. Dates are when the work was merged.
The release zip is built with `python make_release.py <version>`.

## 1.3 (2026-11-15, uplink and loads)

The DSKY gets an erasable store of the cells the descent needs, loaded the way the real crew loaded them, and the planner can print a PAD of the data to load. The planner now makes a PAD and an uplink by default: press **SEND** after PLAN, or tick **Skip simulated uplink** to keep the 1.2 steps.

### Added
- **Erasable store** of named cells with Luminary's addresses and scaling: the landing site `RLS`, the landing time `TLAND`, a burn's ignition time `TIG` and delta-v `DELVLVC`, for both software versions (099 and 210).
- **Keyed loads V21 to V25** with sign, digits, ENTR, PRO, CLR and the flashing verb and noun (a decimal register needs a sign and all five digits: ENTR with fewer digits is OPR ERR and the load waits, without a sign it is OPR ERR and the load starts again, as in PINBALL; during a P27 update PROG shows 27, R1 fills from the left and R3 shows the update buffer address as Luminary does), and the new nouns **N33** (time of ignition) and **N81** (delta-v, local vertical axes).
- **The update programme P27:** V71 (block) and V72 (scatter) with V33 (verify and store) and V34 (terminate), in octal, only in P00; UPLINK ACTY lights while keys arrive from the uplink.
- **Planner uplink:** by default the planner prints a PAD (UPLINK keys for RLS, TLAND and the DOI burn's delta-v and TIG as one eight-word block, as the real ground's external delta-v update) and **SEND** writes the uplink file, which the DSKY presses in when it starts. A plane-change burn is the CSM's, so the PAD only notes it. A **Skip simulated uplink** box gives the 1.2 behaviour: the DSKY loads the saved plan itself.
- `PAD_PROFILE` setting in `lm_config.txt` (the software version when there is no plan).
- **The PAD** is laid out as labelled blocks (landing site, landing time, DOI burn), each with a line of what it holds in plain numbers and its keys on one line, spaced so they can be read. The burn block shows the TIG and delta-v as N33 and N81 will read them, so the PAD can be checked against the display.
- **The loads are kept:** the erasable store is saved to `0:/lm/store.txt` when the DSKY ends and read back at the next start, as the computer's erasable memory stayed; a new plan deletes it. The planner also saves the AGC clock zero (`0:/lm/clock.txt`), because KSP restarts a vessel's mission time when it undocks.
- **The DSKY window has a close cross (X)** in its top right corner; it asks *End DSKY?* with YES and NO.

### Changed
- P63 reads the landing site and time from the store. With Skip simulated uplink ticked the saved plan fills the store when the DSKY starts, as if already uplinked, so the steps are as in 1.2. With nothing loaded P63 says which of RLS and TLAND is missing.
- The plan file now also carries each burn's delta-v in local vertical axes (`LV_DOI`, `LV_PC`) for the PAD.
- V34 is Terminate as in Luminary: it answers a request only (it abandons a keyed load or an update, and ends P63 at its enable prompt) and does nothing elsewhere. The DSKY ends from the X in its window, then YES.
- A keyed load keeps showing each value you entered while you key the next register; keyed digits show at once, and only a monitored noun refreshes once a second.
- **The planner window** is reorganised: pad loads and windows, then the largest plane change and replace nodes, then the Skip simulated uplink box; PLAN and SEND sit side by side (SEND is hidden when the uplink is skipped), and the close cross is in the top corner. The window is wider so the PAD fits.
- A stale V34 is no longer put back on the display after `V37 E 00 E`.

### Not yet
- Nothing flies a loaded burn (the burn programmes P30 and P40 come in a later release; see the roadmap); V70, V73 and state-vector loads are not implemented.

## 1.2 (2026-11-14, J-class pads)

The planner chooses between the Apollo 11 pad loads (as before) and the J-class loads of Luminary 210 (Apollo 15 to 17, the Apollo 17 values). The J-class descent has its own files in `lm/descent_j/`; the Apollo 11 files are unchanged.

### Changed
- **DSKY digits** are pictures (rendered from the Zerlina font, SIL Open Font License, by Eugene Dorr) instead of text in the `digital-7` font, so nothing has to be installed and the digits look like the real display. All digits are the same size. Small spacing tidy-ups on the display side (rounded COMP ACTY and PROG corners).

- **DSKY numbers match the Luminary displays:** no decimal points anywhere (fractional registers are five digits in the unit of the last digit: N61 R3 and N68 R1 in tenths of a nm, N60, N62, N63 and N64 R2 in tenths of ft/s); N64 R1 shows `+TT LL` (time to redesignation close and look angle); N68 R2 is the time to go; MIN/SEC clamps at 59:59.
- **No dashes:** the real DSKY cannot show a dash, so a register with no value yet shows zeros (the stored value) and is blank only when there is no navigation state.
- **Start-up:** the DSKY starts blank (PROG 00, no verb or noun) like a real DSKY after a fresh start; key `V16 N60 E` yourself, or set `DSKY_START = N60` in `lm_config.txt` for the old behaviour. ENTR needs a verb (and a noun, except V37 and V34), otherwise OPR ERR. A typed verb stays on the display while the noun is keyed.
- **P64 redesignation:** the default pitch sign is now -1 (both profiles): W brings the aim point closer, S sends it farther.

### Added
- **Planner:** the result line gives DOI, PDI and LDG as the game's UT clock (HH:MM; set the game's clock to UT); it used to give the vessel's mission elapsed time.
- **Planner:** a "Pad loads and descent guidance" menu; the choice is saved in `plan.json` as `PROFILE` (`A11` or `J`; plans without it are Apollo 11).
- **J-class descent:** Apollo 17 pad loads (`lm_j_constants.ks`), P63 and P64 with them, redesignation clicks of 1 degree on both axes, a 15 m landing-radar cut-off, and **P66 straight after P64** (Luminary 210 has no P65), starting at the current descent rate.
- **P66 horizontal control (J-class):** the thrust direction nulls the horizontal speed over the surface (Luminary `P66HZ`).
- Pad test `test_j.ks`; `reference_j.py` (expected numbers and the mass and performance study).

Flown 2026-11-14 (J Class craft, Apollo 11 site): P63, P64 with redesignation, the handover to P66 at 12 s, horizontal nulling (1.9 to 0.1 m/s), the rate clicks and touchdown all behaved; the Apollo 11 profile was also re-flown on the same craft with no change from 1.1.

## 1.1 (2026-11-13)

The DSKY becomes a core that runs programmes from a table; the LM is its first vehicle. The descent itself (P63 to P66, displays, lamps, keys, logs) flies as in 1.0; only the terminal output changed.

### Changed
- **Terminal:** the P64 "REDESIGNATED" message at every click and the P66 "COMMANDED DESCENT RATE" message at every click are gone.
- **Start-up:** `RUN dsky.` starts the DSKY (the stub `dsky.ks` runs `core/dsky.ks`). The planner is run first by itself with `RUN plan.` (a stub for `lm/planner/lm_plan_ui.ks`); `RUN start.` is gone.
- **Site:** the DSKY takes the landing site from the saved plan only. The site arguments, the perilune fallback, the placeholder site and the start-up plan check line are removed. With no plan the DSKY runs, registers show `-----`, and P63 refuses (OPR ERR and a message).
- **Layout:** scripts are in `core/` (the DSKY core), `lm/` (with `descent/` and `planner/`) and `shared/`; the install is the folders, not one `lm` folder.
- **DSKY window look:** grey housing with rounded corners, framed lamp and display panels of equal width, black square keys with white captions laid out as on the real keypad, bold annunciator and VERB/NOUN/PROG captions, thicker register rules, no rule below R3.
- **COMP ACTY:** lights while the computer is working (a programme step, a programme request, or a display change) and is dark when idle, as the Luminary Executive does; before, it lit for a quarter second at any display change.
- **Registers:** R1 to R3 refresh once a second like a monitor verb (Luminary `MONDEL`), and at once when the noun changes.
- **Internals:** `lm_main.ks`, `lm_start.ks` and `lm_display.ks` are replaced by `dsky_core.ks`, `dsky_keys.ks`, `dsky_display.ks`, `lm_vehicle.ks` and `lm_nouns.ks`. A software-version field (`LUMINARY099`) is on the vehicle and changes nothing yet.

### Added
- **Live readout:** a live descent-rate readout (descent rate in m/s, target or commanded rate, key hint) in the top three lines of the terminal (P65 and P66), drawn in place so it does not scroll, with the terminal cleared when it first appears and when the programme number changes (P65 to P66, contact); the DSKY core gets a general `STATUS` output for programmes to use.
- **P64:** a green arrow (no label) stands on the landing site in the flight view (it follows the redesignated site).
- **P64:** prints "REDESIGNATION CLOSED" once, when the aim point can no longer be moved.
- **Boot file:** `boot/lm_boot.ks`, optional, selects the archive when the ship loads so `SWITCH TO 0.` is not needed.
- **Settings file:** `lm/lm_config.txt` (plain text, `NAME = value`, every setting commented out by default) overrides `LM_LOG`, `P63_WINDOW_MODE`, `P63_WARP_LEAD_S`, `P64_PITCH_SIGN`, `P64_YAW_SIGN`, `P66_ROD_SIGN` and `BODY_NAME`. Bad lines are skipped with a warning at start-up. Read by `lm/lm_settings.ks`.
- Pad test `test_config.ks` for it.
- Pad test `test_core.ks` for the programme table; `check_paths.py` checks every script path offline.

## 1.0 (2026-11-13)

First release: a flyable powered descent from a lunar orbit to touchdown, flown in KSP (Realism Overhaul, Sol, kOS 1.6.0.1).

### Added
- **Starter:** `RUN start.` opens the deorbit planner, then the LM computer, with a saved-plan check.
- **Pilot's manual** (`docs/MANUAL.md`, also as PDF) with a flight checklist and screenshots, and a short README.
- **Release tooling:** `make_release.py` (zip), `make_manual_pdf.py`, `publish_public.py` (public export), `publish_wiki.py` (wiki pages from the manual).

### Changed
- Release cleanup: all logs are off unless `LM_LOG` is TRUE in `lm_constants.ks`; cycle count removed; short tips at the start of each programme.

## Milestone 5: P65 and P66 (2026-11-13)

### Added
- **P65 automatic landing:** nulls the horizontal speed and settles to a 3 ft/s descent; hands over from P64 at 12 s to go.
- **P66 rate of descent:** starts with SAS on plus a throttle-key click (as Luminary GUILDEN); throttle keys change the descent rate.
- CONTACT lamp, engine cut-off one cycle (0.25 s) after contact, and P68 after a pilot engine stop.
- Landing-site map pin shown while a programme runs.
- The thrust the guidance wants is turned into a throttle through the RO LMDE's measured curve plus a thrust trim, because the engine gives more thrust than commanded at low throttle.

### Fixed
- Roll stick sign (Q and E rolled the window the wrong way).

## Milestone 4: P64 approach (2026-11-12)

### Added
- P64 approach guidance with hand-over from P63, the EXNORM window vector and stick-click redesignation of the landing site.
- Flown in `UP` window mode; `KEEP` is assumed, not flown.

### Fixed
- Yaw click sign: A moves the aim point left, D right.

## Milestone 3: P63 braking (2026-11-12)

### Added
- P63 braking: BURNBABY ignition countdown, IGNALG ignition time, quadratic guidance with lag lead, throttle logic and ullage.
- V37 programme selection, P63 nouns, and the SAS button as the AUTO / ATT HOLD switch.
- Window roll modes (`UP` and `KEEP`), chosen in the planner.
- Slower kOS steering and a coast deadband so the ship drifts as the LM did; warp stops 60 s before ignition.

### Fixed
- Radar altitude now uses the terrain height under the ship (`ALT:RADAR` was the altitude above sea level).

## Milestone 2: site selection and deorbit planner (2026-11-12)

### Added
- Deorbit planner: Apollo site menu, latitude/longitude entry, plane-change, DOI and PDI burns as manoeuvre nodes, with sanity checks and a saved plan file.
- Apollo sites and the custom point shown as labelled pins in map view.
- DSKY window with real panel layout, clickable keypad, lamps and flashing entry.
- `lm_main` uses the saved plan's site and warps to 3 min before PDI.

## Milestone 1: navigation and DSKY (2026-11-12)

### Added
- Landing-site frame (TiltEm-safe Moon spin vector built from the north pole) and navigation state (position, velocities, altitude, predicted landing point).
- DSKY-style display and key entry, and the main executive with V16 monitor verbs and V34 terminate.
- Pad tests, expected-number reference script and the name-clash checker.
