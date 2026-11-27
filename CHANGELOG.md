# Changelog

All notable changes to the Apollo LM guidance computer for kOS. Dates are when the work was merged.
The release zip is built with `python make_release.py <version>`.

## 1.5 (2026-11-27, ascent, aborts and rendezvous)

The computer now brings you back up: from the landing site to lunar orbit, on to the CSM, and from any point of the descent back to orbit with one keypress. This is the last lunar module release.

Flown in KSP, all passing:
- **P12** with both software versions. The logged ascents reached the insertion targets within 1 m/s and 8 m, and left the CSM 0.24 to 0.29 degrees further ahead than planned.
- **Aborts:** early in braking, late in the approach, from P66 until the descent tanks ran dry (then abort stage), and abort stage from the surface as far as the pitch-over.
- **Rendezvous:** CSI, CDH, TPI and a midcourse from test orbits (P32 to P35, burned with P41 and P42), P20 with its verbs, and the 210 route from the surface to a docking with braking by hand in P47.

Not flown, listed at the end of this section.

### Added
- **P12, the powered ascent**, on the shared burn engine: flashing N33 (lift-off time) and N76 (targets), the N74 countdown, the V99 N74 engine prompt, then separation and ignition by the computer, vertical rise, pitch-over, timed cut-off and an RCS trim on N85. SAS is the AUTO / ATT HOLD switch, as in the descent; the roll keys turn the ship about its thrust axis. Alarm 1703 moves a lift-off that is too close; V97 shows an engine with no thrust and can relight it. kOS warps to 60 s before lift-off. P12 takes the landing site from where the ship stands, so a craft that never ran P68 can start it.
- **Ascent guidance** ported from Luminary 210, with the Luminary 099 differences chosen by the software version (rise exit, N63 or N94, engine tail-off).
- **P70 and P71, the aborts:** P70 on the descent engine, P71 on the ascent engine, flown by the ascent guidance to 60,000 ft above the site. `Backspace` is ABORT and `0` is ABORT STAGE (once, no confirmation; the computer stages); `V37 E 70 E` and `71 E` also work, and never stage. Allowed from P63 ignition until PRO at P68. Includes the turn up through the vertical from a braking attitude, `V97` when the descent engine runs dry (then `0`), and Luminary's targets: Apollo 11's speed from the time since ignition, J-class from the CSM's lead angle.
- **Rendezvous targeting:** P32 (CSI), P33 (CDH), P34 (TPI) and P35 (midcourse), with their alarms. The result is set for the burn programmes; for P34 and P35 it is an aim point and an intercept time, and P40 and P41 work out the velocity to gain from it on every pass, as Luminary does.
- **P42**, the ascent engine burn. Alarm 1706 while the descent stage is on.
- **Tracking:** P20 and P25 run underneath other programmes, in a second programme slot whose requests break in as priority displays. P20 turns the front windows to the CSM (V50 N18).
- **Verbs** V04, V56, V82 (orbit display), V83, V89, V90, V93, and V76, V80, V81 and V95 (accepted, no effect).
- **Nouns** N11, N12, N13, N16, N37, N44, N52, N54, N55, N58, N59, N74, N75, N76, N82, N90 and N94, with their loads and cells at the Luminary addresses.
- **A drift gauge:** a small window with two crossing needles for the line-of-sight rate to the CSM, with range, range rate and the next braking gate, in P20, P25 or P47 within 40 nm. The stand-in for the LM's rendezvous radar instruments.
- **Planner:** an *Ascent* page that gives the lift-off time for the rendezvous plan that was flown (coelliptic for Apollo 11, short rendezvous for J-class), the next opportunity, and an ascent PAD with the lift-off, insertion and rendezvous keys, with a coelliptic fallback on J-class. *Skip simulated uplink* lets P12 load them from the saved plan. The *Deorbit* page checks where the CSM will be at PDI beside where an abort expects it.
- **Pack:** the ascent, abort and rendezvous checklists and cards, with the Luminary 099 and 210 rendezvous routes shown separately; a warning sign on every CAUTION box and a mark on every NOTE box.
- `0:/lm/logs/dsky.log`: every terminal warning and message with the mission clock.

### Changed
- `ENG_THR_CONT` now ships as `MAN`: the throttle lever is yours from ignition in P40, as the checklists are written. Set `AUTO` in `agc_config.txt` for the computer's throttle.
- The kOS terminal has fixed areas for live readouts, warnings (kept until RSET or the next V37 selection) and messages, and no longer scrolls. Texts are much shorter. It is cleared when the DSKY closes.
- The planner window is titled *LM planner* and has a menu for the two pages. A new deorbit plan removes the old ascent plan.
- KEY REL also lights while your own display covers a programme's, as on the real LM.
- Keypad clicks are queued and pressed in order, so fast clicking loses no keys.
- The turn of the kOS raw axes is now measured in navigation and the burns, where a fixed turn at the Moon's spin rate was assumed.

### Fixed
- **N83 and N85 R3 were reversed** (the RO LM's windows are on its underside). R3 now reads positive towards the windows.
- P30's delta-v was turned to the axes of the ignition time and then turned again from the time of P30. It is now carried once.
- The N18 angles in P40 and P41 could be out by about 0.55 degrees for each hour since the DSKY started.

### Departures from Apollo
Documented in the pack, appendix A. The main ones:
- The CSM is a KSP vessel; nothing is uplinked for the ascent or the rendezvous. P12 starts only when landed.
- Ascent guidance runs every computer cycle; kOS steering flies the attitude with any RCS jet; the computer separates and lights without the crew's switch presses.
- Aborts: two keys stand in for the panel buttons and the computer stages. J-class targets are moved to this site's height and Apollo 11's speeds are left as they were, so its abort apolunes are about 13 nm higher than Apollo's at the Apollo 11 site.
- Rendezvous: no radar (a P20 mark is only a count), orbits are predicted as two-body orbits, and the PAD's rendezvous times are the planner's own. P20 stays on for braking, where Apollo 11 went to P00 and P47. The docking is yours.
- P20 ends if the KSP target is lost.

### Not flown
- The surface abort past the pitch-over, and the J-class abort targets that follow the CSM.
- P25, P40 on an aim point (a TPI on the descent engine), the J-class coelliptic fallback, and P32 or P33 with P20 running underneath.
- The 099 rendezvous as one flight from the surface to a docking: its ascent and its burns were flown separately.
- Added or reworded after the last flight, and checked on the pad only: the gauge's range, rate and gate lines, the P47 and P20 SAS messages, P20 steering in physics warp and its warning near the CSM, braking in P20 with the DSKY closed to dock, and the `RUNNING IN BACKGROUND:` line.

## 1.4 (2026-11-25, burn programmes)

The computer now flies its own burns, starting with the DOI, on one shared burn engine. The DOI, a P41 trim and the P63 landing (as a regression) were flown in KSP and passed; the engine timings are the Apollo values and needed no tuning.

### The manual is now the Pilot's Pack
- **`docs/PACK.pdf` replaces `docs/MANUAL.md`**: a short pack in the style of the Apollo checklists and handbooks (a landing card, an overview, reference tables for verbs, nouns, alarms, settings and loads, checklists from start-up to touchdown, and a short appendix of differences from the real LM). Written as Markdown in `docs/pack/` and built by `make_pack.py` (A4 PDF through Edge or Chrome, and the web page for GitHub Pages); `check_pack.py` replaces `check_manual.py` and also checks every verb, noun, programme and setting the pack names against the code. `make_site.py` and `make_manual_pdf.py` are gone, and the wiki is one landing page that links to the pack.

### Added
- **P30, external delta-V** (`lm/burn/lm_p30.ks`): checks a burn from the loaded time of ignition and delta-v (N33, N81) and shows the orbit after it (N42) and the time to ignition (N45). Fires nothing.
- **P40, the descent-engine burn** (`lm/burn/lm_p40.ks`): R60 attitude turn, checklist request, countdown, ullage, engine prompt, ignition, cut-off from a timed task, flashing N40 and N85. The ENG THR CONT switch is the `ENG_THR_CONT` setting: `AUTO` (minimum thrust at ignition, full thrust 26 s later on a long burn) or `MAN` (minimum for 15 s, then the pilot's lever). Alarms 1703 (ignition time slipped) and 1706 (descent stage gone).
- **P41, an RCS burn, and P47, a thrust monitor** (`lm/burn/lm_p41.ks`): N85 shows the velocity to be gained along the ship's axes; N83 the velocity gained since P47 started.
- **P51** (`IMU_ALIGN` `REQUIRED` makes the burns wait for it; the default `AUTO` needs nothing), verb 50 prompts, nouns N18, N25, N40, N42, N45, N83 and N85.
- **The burn engine** `lm/burn/lm_burnbaby.ks`: one state machine (Luminary's BURNBABY) driven by a table per programme. P63 (both profiles) now runs on it too; the old sequence is kept as a frozen copy in `test_burnbaby.ks` and the pad tests compare the two step by step. The J-class P63 still calls `j_seq_*`, now thin wrappers that give the table `J_ZOOMTIME`.
- **Settings:** `ENG_THR_CONT`, `IMU_ALIGN` and `PLAN_NODES` (the planner leaves its manoeuvre nodes as a visual aid, or removes them once the plan is saved). The PAD says to fly the DOI with P30 then P40.
- Pad tests `test_burn`, `test_burnbaby`, `test_burnctl`, `test_p30`, `test_p40`, `test_p41`; `reference_burn.py`. The pack has the burn checklists.

### Departures from Apollo (documented in the pack, appendix A)
- The state at ignition comes from KSP's orbit prediction, not an integrator; the delta-v gained is measured from the velocity less gravity, not from accelerometers; there is no finite-burn correction.
- The IMU is aligned from the start; the N45 middle gimbal angle is an assumed reference; the 10 percent level is this lander's minimum throttle (about 18 percent of full thrust); a raised throttle lever fires the RCS after the engine runs, so it is released at cut-off.

### Changed
- **A shorter Shift or Ctrl tap now counts as a ROD click** (`ROD_LEVER_STEP` 0.004 to 0.001), for keyboards that register a very short modifier-key press weakly. H and N are unchanged and work on any keyboard.
- **The burn programmes' delta-V no longer drifts with the Moon's spin.** The raw axes turn with the Moon, and the servicer pass differenced velocities taken in two different axes, so the spin showed up as a steady change along the radius (about 0.3 m/s a minute in a 60 nmi orbit: the third register of N85 kept growing). The start of each pass is now turned to the axes of the end of the pass first.
- **P41 counts down to ignition in the terminal** (`TIG IN m:ss`), since its display shows N85 and goes blank before TIG; it says when TIG has passed.
- **The terminal is cleared when a programme ends**, so nothing from the burn or the descent is left to garble what follows.
- **On `ENG THR CONT = MAN` the throttle lever drives the descent engine directly** from ignition (the program only raises a lever that is below the engine's minimum), and the lever is zeroed at cut-off.
- **`PAD_PROFILE` is no longer a setting.** The software version is the planner's PAD menu. A saved plan carries it, and in uplink mode the planner saves it in `0:/lm/profile.txt` with the PAD, where the DSKY reads it at start; the planner's mismatch warning is gone. An old `PAD_PROFILE` line in a settings file is skipped with a warning. **Skip simulated uplink** now also loads the DOI burn (N33 and N81) into the DSKY's store, so P30 and P40 work from the saved plan.
- **The DSKY runs over any body.** It no longer refuses to start away from the Moon, and no longer stops when the ship leaves the Moon's sphere of influence (a whole mission needs it in Earth orbit and on the way). The landing programmes and the planner still refuse anywhere but `BODY_NAME`.
- **One settings file for the whole project:** `agc_config.txt` at the top of `Ships/Script/` (next to `dsky.ks` and `plan.ks`), with `[LM]` and `[CSM]` sections (the CSM has none yet). A `[COMMON]` section holds the settings that do the same job for every computer, written once: `LOG` (the logging switch; `LM_LOG` still works as the old name and as the LM's own override), `DSKY_START`, `IMU_ALIGN` and `ALARMS`; the rest stay under `[LM]`. The same settings as before otherwise. An old `lm/lm_config.txt` is still read first, and a setting in `agc_config.txt` wins over it; the zip no longer ships `lm_config.txt`. Installing over an edited `agc_config.txt` replaces it, as `lm_config.txt` was before. The reader is `core/agc_settings.ks`.

## 1.3.2 (2026-11-22, ROD click keys)

A patch release for a report that, with SAS on, ROD clicks did not take P65 to P66 (the reporter's throttle keys did nothing). The clicks now have a second input, the diagnostics say what a dropped click was, and `rod.log` records every click.

### Changed
- **ATT HOLD lamp** in the DSKY window (the free slot at the bottom of the left column): lit while the computer sees SAS on, so you know a ROD click will start P66. Not a real DSKY lamp; it stands in for the ATT HOLD switch's position.
- **ROD clicks can be given with H and N** (KSP's fore and aft translation keys; H slower, N faster) as well as Shift and Ctrl. A pilot whose throttle keys did nothing could not start P66 (reported on 1.3.1), and the throttle lever has to be written back to centre, which a controller axis can fight. The two inputs have separate detectors, so one never disturbs the other. The new `ROD_KEYS` setting picks `BOTH` (default), `HN` (the lever is then neither read nor written) or `SHIFTCTRL` (as 1.3.1). With RCS on, H and N also fire the jets along the thrust axis while held. `P66_ROD_SIGN` flips the direction.
- A ROD click that cannot be used now says why in the terminal (SAS off, engine not lit and zoomed in P63, no valid navigation state in P65), and every click is written to `rod.log` (always, whatever `LM_LOG` says; the other logs still need `LM_LOG`). This is for a report that SAS was on and the clicks did nothing; it changes no flight behaviour.

## 1.3.1 (2026-11-17, landing aids)

The landing gets closer to Luminary 099 and 210: an alarm facility, a pending-request mechanism with a working KEY REL, the procedure verbs and radar nouns, the flashing displays Luminary has at the P63 start, in P64 and in the J-class P63 and P66, P66 returning to P65, and P68. It is a patch release: the burn programmes are 1.4.

### Added
- **Alarm facility** in the DSKY core: PROG latches on an alarm until **RSET**, three alarm slots (a fourth overwrites the third with bit 15 set), **V05 N09** shows the codes. Scripted alarms: the `ALARMS` setting (`OFF`, `A11` for the Apollo 11 1202/1201 pattern, or `code@seconds,...` after ignition) raises them and restarts the display as the real software did.
- **Flashing requests the core owns:** KEY REL (the lamp lights when you key over a request; the **KEY REL** button restores it), **V32** (recycle), **V33** (proceed, never an error), **V34** (terminate a request); RSET no longer ends a keyed load or update.
- **Radar state:** V57 and V58 (updates permitted/inhibited, a flag only), V77, V59/V60 accepted; nouns **N66** and **N67** from the simulated radar; the radar altitude test runs only after the high gate, as in the source.
- **P63 starts with `V06 N61` flashing** until **PRO** (it goes on by itself at 35 s before ignition); **P64's `V06 N64`** flashes while redesignation is open; **V97 N62** appears if the engine gives no thrust (PRO monitors again, ENTR re-ignites 5 s later, V34 ends P63).
- **P66 returns to P65** when SAS goes off; an early P66 from a ROD click in P63 or P64; PRO or ENTR in P65/P66 drops the steering target.
- **P68** (landing confirmation): after contact it shows `V06 N43` (the true latitude, longitude and height) and stores the position as the landing site; `V37 E 68 E` selects it once down. New noun **N43**.
- **J-class (Luminary 210):** P63 flashes `V06 N63` until `V57 E`; P66 flashes `V06 N60` (V34 ends it, PRO or V32 hold the last direction); nouns **N60**, **N63**, **N68** show the 210 contents; new nouns **N92** (wanted thrust in percent) and **N69** (landing-site correction, loadable with V25).
- **V35** lamp test.

### Changed
- P65 and J's P66 hand over to P68 at touchdown instead of ending.
- P63 holds the attitude it has until **PRO**, then turns to the burn attitude as one smooth rotation (at most 10 degrees a second) instead of one big RCS burst.
- P68 gives the steering back, and `V16 N43 E` keeps showing the landing position after P68 ends.
- When a programme ends with **PRO** or `V34 E`, PROG goes to 00 and `V37 N99` flashes, as Luminary does; `V37 E` answers it.
- P65's and P66's terminal readout is drawn in place at the top of the terminal, not as scrolling messages.
- `P64_PITCH_SIGN` now defaults to +1, after the Apollo 11 flight: **W** sends the aim point farther away and **S** brings it closer.
- The pilot's manual is rewritten: the flight comes before the DSKY reference, with a key-by-key landing, units in every register, a quick reference and a glossary; the wiki is split into pages. `scripts/tests/check_manual.py` checks the manual's settings, nouns, verbs and quoted numbers against the code.

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
