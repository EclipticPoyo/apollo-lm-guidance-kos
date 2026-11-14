// lm_constants.ks -- constants for the LM guidance scripts (extended in plan Task 2).
//
// Frame conventions, measured with probe_frames.ks in lunar orbit (kOS 1.6.0.1,
// Sol + Mirage + TiltEm + RO; spec section 6 has the evidence).

// FRAME_SIGN makes the Luminary relation  Vsurface = V - FRAME_SIGN * (WM x R)  true in kOS.
//   V = SHIP:VELOCITY:ORBIT, R = Moon-centred position (= -SHIP:BODY:POSITION),
//   WM = Moon spin vector built from the NORTH POLE: unit(pole) * 2*pi / ROTATIONPERIOD.
//   Measured: V - Vsurface = -(WM x R) to ~1e-12 m/s, so FRAME_SIGN = -1.
// Do NOT build WM from BODY:ANGULARVEL: in this install it is ~23 degrees off the real spin axis.
GLOBAL FRAME_SIGN IS -1.

// AXES_ROTATE: the kOS raw axes turn with the Moon (a fixed LATLNG point stays put in them).
//   Consequence: a landing-site vector in raw axes is constant, so Luminary's per-cycle
//   "LAND = LAND - LAND x WM dt" update (LUNAR_LANDING_GUIDANCE_EQUATIONS lines 281-283)
//   must be skipped, or the Moon's rotation would be counted twice.
GLOBAL AXES_ROTATE IS TRUE.

// ---- Units ---------------------------------------------------------------
// Everything inside the scripts is SI (metres, seconds). Apollo units are only
// produced at the display, through the three functions below.
// Both factors are exact by definition (international foot and nautical mile).
GLOBAL FT_PER_M IS 1 / 0.3048.   // config: feet in one metre
GLOBAL M_PER_NM IS 1852.         // config: metres in one nautical mile

// KerboScript functions: FUNCTION name { PARAMETER x. ... RETURN value. }
// Parameter names must not match a built-in function (V, R, Q, ...), or kOS refuses to load the file.
FUNCTION m_to_ft   { PARAMETER metres.   RETURN metres * FT_PER_M. }     // metres -> feet
FUNCTION ms_to_fps { PARAMETER speed.    RETURN speed * FT_PER_M. }      // m/s -> ft/s
FUNCTION m_to_nm   { PARAMETER metres.   RETURN metres / M_PER_NM. }     // metres -> nautical miles

// ---- Configuration -------------------------------------------------------
// Not Luminary values: these are choices for this install, change them freely.
GLOBAL BODY_NAME IS "Moon".      // config: the body we land on; compared with SHIP:BODY:NAME
GLOBAL CYCLE_S IS 0.25.          // config: nominal cycle period, s (Luminary's guidance cycle is 2 s;
                                 //         we run faster for a smoother display, 4 Hz)

// Landing site, entered by the pilot before descent. Placeholder = the equator at 0 E.
// SITE_ALT is metres above the body's sea level (the terrain height at the site).
GLOBAL SITE_LAT IS 0.            // config: degrees north
GLOBAL SITE_LNG IS 0.            // config: degrees east
GLOBAL SITE_ALT IS 0.            // config: metres above sea level

// ---- Descent-orbit planner (milestone 2) -----------------------------------
// Apollo 11 pad-loaded ignition geometry, decoded from the LM Data Book
// (docs/superpowers/specs/2026-11-12-p63-apollo11-constants-research.md).
// Positions are relative to the landing site in the guidance frame (x up, z downrange).
GLOBAL RIGNX IS -39782.453328.   // Apollo 11 pad load: PDI position, up component, m
GLOBAL RIGNZ IS -436655.657.     // Apollo 11 pad load: PDI position, downrange component, m (negative = before the site)
GLOBAL VIGN IS 1690.256208.      // Apollo 11 pad load: speed at PDI, m/s

// Planner limits. "spec" = design spec milestone 2; "chosen" = chosen here, change freely.
GLOBAL PLAN_XRANGE_MAX IS 2000.      // spec 6C: skip the plane change below this crossrange at the site, m
GLOBAL PLAN_LEAD_S IS 300.           // spec 6E: earliest burn after now, s
GLOBAL PLAN_PDI_TO_LAND_S IS 755.    // spec 6E: Apollo 11 PDI to touchdown (102:33:05 to 102:45:40), s
GLOBAL PLAN_NODE_GAP_S IS 300.       // chosen: least time between the plane-change burn and the DOI burn, s
GLOBAL PLAN_DV_MAX IS 100.          // spec 7: largest acceptable DOI delta-v, m/s
GLOBAL PLAN_VIGN_TOL IS 10.          // chosen: warn when the descent orbit PDI speed differs from VIGN by more, m/s
GLOBAL PLAN_MAX_AGE_S IS 7200.       // chosen: a plan older than this is stale (about 1 degree of Moon turn), s
GLOBAL PLAN_LAND_TOL_S IS 1.         // chosen: landing time converged when it moves less than this, s
GLOBAL PLAN_ITER_MAX IS 5.           // chosen: most timing passes before giving up
GLOBAL PLAN_TERRAIN_MIN_M IS 3000.   // chosen: least acceptable height above terrain on the descent orbit, m
// Post-check tolerances (spec section 8, plan pass criteria).
GLOBAL PLAN_CHK_ALT IS 1000.         // predicted PDI altitude vs the pad geometry, m
GLOBAL PLAN_CHK_RANGE IS 5000.       // predicted ground range to the site vs |RIGNZ|, m
GLOBAL PLAN_CHK_SPEED IS 5.          // predicted PDI speed vs the planned value, m/s
GLOBAL PLAN_CHK_BURN IS 0.01.        // node BURNVECTOR vs intended delta-v, m/s
GLOBAL LM_LOG IS FALSE.              // TRUE writes the diagnostic logs under 0:/lm/logs/ (cross-check, P63, P64, P65, planner report); off for normal flights
GLOBAL PLAN_PLAN_FILE IS "0:/lm/plan.json".   // where the plan is saved for later programmes

// Conventions that can only be measured in flight by scripts/tests/probe_predict.ks.
// Placeholders until the probe has been run; Task 2 of the plan records the results.
// Measured by probe_predict.ks in a 112 km lunar orbit (2026-11-12): raw axes are inertial, prediction
// matches them within 24 m over 900 s (frozen and live readings are identical, so the probe's
// "UNEXPECTED" verdict was a degenerate test, not a fault); BURNVECTOR is in the POSITIONAT frame.
GLOBAL PREDICT_AXES_INERTIAL IS TRUE.
GLOBAL NODE_NORMAL_SIGN IS -1.               // kOS node normal is opposite VCRS(r, v)
GLOBAL NODE_RADIAL_SIGN IS 1.
GLOBAL POSITIONAT_INCLUDES_NODES IS TRUE.

// ---- P63 braking phase and ignition (milestone 3) ------------------------------------------------------
// Apollo 11 pad loads (Luminary 099), decoded in docs/superpowers/specs/2026-11-12-p63-apollo11-constants-research.md
// from NASA LM Data Book Vol. II, Table LM5/4.5.1-1. Guidance-frame vectors are V(up, crossrange, downrange):
// x up from the landing site, y crossrange, z downrange (milestone 1 frame, lm_frame.ks).
GLOBAL RBRFG IS V(52.375308, 0, -3254.836061).   // pad load: braking target position, m
GLOBAL VBRFG IS V(-32.271005, 0, -0.316992).     // pad load: braking target velocity, m/s
GLOBAL ABRFG IS V(0.19022568, 0, -2.77502112).   // pad load: braking target acceleration, m/s^2
// JBRFG*: the pad load -5.7384e-3 is 8 x the downrange jerk (research note, "starred values"), so the jerk is
// -7.173e-4 m/s^3. Only the downrange component enters the time-to-go cubic.
GLOBAL JBRFG_Z IS -7.173e-4.                     // derived from the pad load JBRFG*, m/s^3
GLOBAL GAINBRAK IS 1.                            // pad load: lunar-rotation lead gain (CGCALC)
// CG_LEAD_DIV: the lead of the guidance axes is -tgo/CG_LEAD_DIV x GAINBRAK x (surface velocity) (CGCALC lines 660-682).
// The AGC variable is called TTF/8, which suggests 8, but the whole-branch review argued it is only a scaling label and
// the physical divisor is 4 (Klumpp). Unresolved from the source alone: flight test 2 compares the guidance axes
// with the direction to the site; the effect is only the crossrange orientation, near zero for an in-plane approach.
GLOBAL CG_LEAD_DIV IS 8.                         // config: 8 (literal TTF/8) or 4 (review's reading); see above
GLOBAL TCGFBRAK IS 30.                           // pad load, s: CG not recomputed inside this time-to-go (CGCALC lines 641-658)
GLOBAL TCGIBRAK IS 900.                          // pad load, s: and not beyond this one
GLOBAL TENDBRAK IS 62.                           // pad load, s: braking ends (P64 starts) when time-to-go falls below this
GLOBAL ZOOMTIME IS 26.                           // pad load, s: throttle-up after NOMINAL ignition (P63ZOOM)
GLOBAL LEADTIME IS -2.2.                         // pad load, s: guidance lead for engine lag (QUADGUID); negative
GLOBAL DELTTFAP IS -110.                         // pad load, s: added to time-to-go at the P64 start (milestone 4)
// Ignition algorithm gains (IGNALG; the positions and speed RIGNX, RIGNZ, VIGN are in the planner section above).
GLOBAL KIGNX IS -0.617631.                       // pad load, dimensionless
GLOBAL KIGNY IS -2.4770341207e-6.                // pad load, 1/m
GLOBAL KIGNV IS -410.                            // pad load, s
GLOBAL DDUMCRIT IS 0.08.                         // IGNALG converged when |DDUM| is below this, s (8 cs, THE_LUNAR_LANDING.agc:270)
// TRIMACCL: 3.50132708e-5 m/cs^2 (CONTROLLED_CONSTANTS.agc:105) = 0.350132708 m/s^2 (1 m/cs^2 = 1e4 m/s^2).
GLOBAL TRIMACCL IS 0.350132708.                  // pad load, m/s^2: trim acceleration for the zoom-time velocity correction

// BURNBABY timing (BURN_BABY_BURN--MASTER_IGNITION_ROUTINE.agc). All offsets in seconds.
GLOBAL ULLAGE_START_AFTER_TIG30 IS 22.4.         // P63 table word 2240 cs (line 133), read as centiseconds: ullage on at TIG-7.6
GLOBAL ULLAGE_OFF_AFTER_IGN IS 0.5.              // FIXDELAY 50 cs after light-up (lines 530-531)

// Throttle dead band. The Apollo logic (THROTTLE_CONTROL_ROUTINES.agc lines 79-99) works around a dead band
// in the DPS; the RO LMDE has one too: commanded fractions of full thrust in between are not available.
GLOBAL THR_DEAD_LOW IS 0.65.                     // config: RO LMDE, lower edge of the dead band (confirmed in flight test, plan Task 10)
GLOBAL THR_DEAD_HIGH IS 0.942.                   // config: RO LMDE, upper edge of the dead band
GLOBAL THR_MIN_FRAC IS 0.1.                      // config: RO LMDE minimum throttle (RealFuels, project probe notes)

// Landing-site marker (kOS cannot create map waypoints): the planner window's map pin (lm_site_pins.ks, sized by PINS_* there) is shown
// in map view on the site in use while a programme runs. Not Apollo.
GLOBAL SITE_MARK_LABEL IS "LM SITE".             // config: the text beside the pin

// Which ship face the crew window looks out of: "TOP", "BOTTOM", "STAR" or "PORT" (a face of SHIP:FACING).
GLOBAL WINDOW_AXIS IS "BOTTOM".                  // config: RO LM crew window face; read from the user's WASD observation (D turns the window anticlockwise seen head-on), confirm in flight test 1

// P63 turn-then-warp (chosen, not Apollo: the real LM did not warp). After V37 E 63 E the ship turns to the burn attitude;
// once it has stayed within P63_SETTLE_ERR_DEG of it and turned slower than P63_SETTLE_RATE_DEG_S for P63_SETTLE_HOLD_S,
// P63 warps to P63_WARP_LEAD_S before ignition (once only: cancel it with KSP's own warp-cancel key and it does not restart).
GLOBAL P63_WARP_LEAD_S IS 60.                  // config: stop the warp this long before ignition (TIG), s. Tune after flight test 1
GLOBAL P63_WARP_MIN_S IS 10.                     // no warp when the stop time is less than this far ahead, s
GLOBAL P63_SETTLE_ERR_DEG IS 2.                  // config: attitude counts as reached inside this error, degrees
GLOBAL P63_SETTLE_RATE_DEG_S IS 0.3.             // config: and turning slower than this, degrees per second
GLOBAL P63_SETTLE_HOLD_S IS 5.                   // config: for this long, s

// Crew window in P63 (the planner window chooses it and saves it in the plan; this is the default and what a plan without it gets).
//   "UP"   the window is held toward straight up from the Moon from the first turn: the profile of the later missions
//          (user's report; NOT verified in the source, which is Luminary 099, the Apollo 11 version). No stick roll in the burn.
//   "KEEP" Luminary 099 (Apollo 11): the ship keeps the roll it had; no programmed roll; in AUTO the stick can roll it.
GLOBAL DSKY_START IS "BLANK".                  // what the DSKY shows when it starts: BLANK (PROG 00, nothing else, as a real DSKY after a fresh start) or N60 (V16 N60, a descent monitor); config file setting
GLOBAL P63_WINDOW_MODE IS "UP".
// Window roll (Luminary: none in P63; the pilot may roll with the stick in AUTO, see lm_control.ks win_hold).
GLOBAL P63_ROLL_DETENT IS 0.1.                   // config: roll stick (-1 to 1) beyond this overrides the roll, like the LM hand controller out of detent
GLOBAL P63_ROLL_STICK_LEAD_DEG IS 30.          // config, CHOSEN: with the roll stick at full deflection the window command is this many degrees ahead of the ship's roll; the ship rolls toward it, so the rate depends on how fast kOS steering follows (tune: more = faster)
GLOBAL P63_ROLL_STICK_SIGN IS -1.                // config: -1 because milestone 5 flight 1 showed Q and E rolled the window the wrong way round with +1 (user, 2026-11-13); flip back if it is ever the other way

// Steering tuning and the coast deadband (probe_steer.ks, 2026-11-12; Luminary's DAP deadbands: 0.3, 1.0 and 5.0 degrees,
// DAP_INTERFACE_SUBROUTINES.agc 62-111). kOS's cooked steering chases the attitude exactly and, on RCS jets, never stops
// pulsing (about 0.8 kg/s in the probe). P63 therefore (1) makes the steering slower to react: the settling times of the
// torque loops times P63_STEER_TS_MULT and the torque dead zone times P63_STEER_EPS_MULT (probe: hold chatter 12.5 kg per
// 15 s fell to 0.2 to 2 kg), and (2) before the countdown lets the ship drift: the steering lock is dropped once the
// attitude is within P63_DB_RELEASE_DEG and turning slower than P63_DB_RATE_DEG_S, and taken again when the error passes
// P63_DB_RELOCK_DEG. From the countdown on (and in the burn, which needs the gimbal) the lock stays on.
GLOBAL P63_STEER_TS_MULT IS 2.                   // config: kOS PITCHTS, YAWTS, ROLLTS (default 2 s) multiplied by this
GLOBAL P63_STEER_STOP_MULT IS 0.5.               // config: kOS MAXSTOPPINGTIME (default 2 s) multiplied by this: it brakes the turn earlier, less overshoot. UNTESTED in combination: flight test 2a showed a 13 degree overshoot with TS x2 alone; probe_steer's STOP1_EPS10 (this x0.5) had rebounds of 1.8 to 2.7 degrees
GLOBAL P63_STEER_EPS_MULT IS 10.                // config: kOS TORQUEEPSILONMIN and MAX (defaults 0.0002, 0.001) multiplied by this
GLOBAL P63_DB_RELEASE_DEG IS 0.5.                // config: drift freely once the error is below this, degrees
GLOBAL P63_DB_RATE_DEG_S IS 0.15.                // config: and the ship is turning slower than this, degrees per second
GLOBAL P63_DB_RELOCK_DEG IS 1.0.                 // config: steer again when the error passes this, degrees (Luminary's powered-flight deadband)

// ---- P64 approach phase and redesignation (milestone 4) ------------------------------------------------------------
// Apollo 11 pad loads (research note, "Approach phase"; NASA LM Data Book). Guidance-frame vectors V(up, crossrange, downrange).
GLOBAL RAPFG IS V(33.858708, 0, -8.1668112).     // pad load: approach target position, m
GLOBAL VAPFG IS V(-1.5218664, 0, 0.0755904).     // pad load: approach target velocity, m/s
GLOBAL AAPFG IS V(-0.07997952, 0, -0.1560576).   // pad load: approach target acceleration, m/s^2
// JAPFG*: the pad load 5.51e-4 is 8 x the downrange jerk (same convention as JBRFG*), so the jerk is 6.8875e-5 m/s^3.
GLOBAL JAPFG_Z IS 6.8875e-5.                     // derived from the pad load JAPFG*, m/s^3
GLOBAL GAINAPPR IS 0.                            // pad load: lunar-rotation lead gain in the approach (CGCALC)
GLOBAL TCGFAPPR IS 30.                           // pad load, s: CG not recomputed inside this time-to-go (CGCALC)
GLOBAL TCGIAPPR IS 200.                          // pad load, s: and not beyond this one
GLOBAL TENDAPPR IS 12.                           // pad load, s: the approach ends (P65 starts) when time-to-go falls below this
// EXNORM window vector and REDESIG limits (LUNAR_LANDING_GUIDANCE_EQUATIONS.agc). The source stores sin(25 deg)/8 and
// sin(15 deg)/8 to compare with a quantity kept at 1/8 size, so the real values are sin 25 and sin 15.
GLOBAL P64_PROJMAX IS 0.42262.                   // source line 1455: sin(25 deg)
GLOBAL P64_PROJMIN IS 0.25882.                   // source line 1456: sin(15 deg)
GLOBAL P64_DEPRCRIT IS -0.02.                    // source line 1470 (-.02 B-1 at half size): the up component of the unit line of sight to the redesignated site may not rise above this (about 1.1 degrees below the horizontal)
GLOBAL P64_ELEACH_RAD IS 0.00873.                // source line 1212: one pitch click moves the aim point 1/2 degree (elevation), rad
GLOBAL P64_AZEACH_RAD IS 0.03491.                // source line 1211: one yaw click moves the aim point 2 degrees (azimuth), rad
// Pilot clicks (the keyboard gives -1, 0 or 1 on each axis, held for as long as the key is down). Not Apollo values.
GLOBAL P64_CLICK_THRESH IS 0.5.                  // chosen: a stick value at or beyond this (either sign) is a click
GLOBAL P64_CLICK_REARM IS 0.2.                   // chosen: the stick must come back inside this before the next click counts
GLOBAL P64_PITCH_SIGN IS -1.                     // chosen: -1 because the user found W and S moving the aim point the wrong way in the J flight (2026-11-14): W should bring the aim point closer to the ship and S send it farther away (the user's wish; the real LM's direction is not confirmed, see the Luminary redesignator monitor); flip to 1 for the other way
GLOBAL P64_YAW_SIGN IS -1.                       // chosen: -1 because flight 2 showed the A key (yaw -1) moved the aim point to the RIGHT; with -1 A moves it left, D right (user, 2026-11-12)
GLOBAL P64_REDES_CLOSE_S IS 4.                   // chosen: redesignation stops this long above TCGFAPPR (Luminary: TREDES reaches zero two 2 s guidance passes before it, TDISPSET)

// Simulated landing radar (plan Task 5; SERVICER.agc, P20-P25.agc).
GLOBAL DELQFIX IS 60.96.                         // pad load, m (200 ft): the altitude test allows this plus HCALC/8 (SERVICER.agc:1152-1154)
GLOBAL RADAR_DV_FIXED IS 2.286.                  // m/s (7.5 ft/s): the velocity test allows this plus |V|/8 (SERVICER.agc:1089, 1280-1286)
GLOBAL RADAR_DV_FRAC IS 0.125.                   // the 1/8 in "7.5 + |V|/8"
GLOBAL RADAR_V_MAX IS 609.6.                     // m/s (2000 ft/s): velocity is read only below this (SERVICER.agc:1381-1384)
GLOBAL RADAR_ALT_MAX_M IS 12000.                 // chosen, m: radar altitude counts as available below this (hardware range is not in the sources)

// ---- P65 final descent and P66 rate of descent (milestone 5) ---------------------------------------------------------
// Apollo 11 pad loads (research note, "Vertical phase"); sources in LUNAR_LANDING_GUIDANCE_EQUATIONS.agc.
GLOBAL V2FG IS V(-0.9144, 0, 0).                 // pad load: P65 target velocity in guidance axes (up, crossrange, downrange), m/s (-3 ft/s: 0.9144 m/s down, no horizontal speed)
GLOBAL TAUVERT IS 10.                            // pad load, s: P65 velocity-nulling time constant (source 897-913)
GLOBAL RODSCALE IS 0.3048.                       // pad load, m/s: one ROD click changes the commanded descent rate by this (1 ft/s)
GLOBAL TAUROD IS 1.5.                            // pad load, s: P66 rate-of-descent time constant
GLOBAL LAG_TAU IS 0.413333.                      // pad load: engine lag over TAUROD, the P66 lag-compensation gain (source 1048-1075)
GLOBAL MINFORCE IS 4360.                         // pad load, N (980 lbf): the least thrust P66 commands
GLOBAL MAXFORCE IS 28000.                        // pad load, N (6300 lbf): the most thrust P66 commands (about 60 % of the RO LMDE full thrust)
// The RO LMDE's thrust is not the throttle command: measured in the milestone 3 and 4 flights (steady stretches of p63.log and
// p64.log), commanded throttle 0.1 gave 0.182 of full thrust, 0.2 gave 0.282, 0.65 gave 0.648 and 1.0 gave 0.998. P65 and P66 turn the
// thrust they want into the throttle that gives it by this table (thr_for_thrust, lm_guidance.ks): without it P65 flew 0.4 m/s^2 too
// much thrust near hover and climbed (milestone 5 flight 1). Points in rising order; chosen from flight data, not Apollo values.
GLOBAL THR_CURVE_THRUST IS LIST(0.182, 0.282, 0.648, 1.0).     // measured: thrust as a fraction of full thrust ...
GLOBAL THR_CURVE_THROTTLE IS LIST(0.1, 0.2, 0.65, 1.0).        // ... at this commanded throttle
GLOBAL THR_MIN_THRUST_FRAC IS 0.182.             // measured: the least thrust the engine gives (at its minimum throttle 0.1)
// Thrust trim (P65 and P66): the curve above is only good to about 0.015 of full thrust (flight 1b: P65 settled at -1.8 m/s, not -0.91,
// from a 0.014 error), so the throttle is also trimmed by the difference between the thrust wanted and the thrust measured, as Luminary's
// throttle routine does (PIF = FC - FP, THROTTLE_CONTROL_ROUTINES.agc 37-47, 122). Chosen values.
GLOBAL THR_TRIM_GAIN IS 0.2.                     // chosen, per second: the trim moves this fraction of the thrust error each second (about a 5 s time constant, slower than the engine's response)
GLOBAL THR_TRIM_MAX IS 0.1.                      // chosen: the trim never exceeds this much of full thrust either way
GLOBAL THR_TRIM_BAND IS 0.6.                     // chosen: no trim when the thrust wanted is above this (near the engine's dead band the curve is not what matters)
GLOBAL P66_MIN_TILT_COS IS 0.1.                  // chosen: P66 commands nothing new when the thrust axis is within this cosine of horizontal (cos(tilt) is divided by)
GLOBAL P66_ROD_SIGN IS 1.                        // chosen: +1 = Shift (lever up) raises the commanded rate = slower descent; flip to -1 after the first flight (UNVERIFIED)
GLOBAL ROD_LEVER_STEP IS 0.004.                  // chosen: the throttle lever moving this far from its reference is a ROD click (probe: no noise at all, the lever is exactly 0.5 at rest; a key moves it 0.008 per frame at 60 fps; flight 1 with 0.02 missed short taps)
GLOBAL ROD_LEVER_REARM_S IS 0.05.                // chosen: the lever must stay at its reference this long before the next click counts (flight 1: 0.15 s swallowed quick double taps)
GLOBAL P66_CUTOFF_DELAY_S IS 0.25.               // chosen, s: engine cut-off this long after contact (one 0.25 s cycle: the next cycle) unless the pilot has stopped it (Apollo: the crew stopped it); the first value, 1 s, felt too slow in flight (user, 2026-11-13)
GLOBAL P66_CONTACT_FALLBACK IS FALSE.            // chosen: TRUE adds a contact test from height and speed (only if the ship status LANDED proves late; HCALC is the centre of mass above the SITE radius, not the terrain, so it can fire in the air over lower ground)
GLOBAL P66_CONTACT_ALT_M IS 1.                   // chosen, m: the fallback height above the site under this ...
GLOBAL P66_CONTACT_RATE IS 0.5.                  // chosen, m/s: ... and vertical speed under this
GLOBAL ROD_LEVER_JUMP IS 0.3.                    // chosen: a lever change bigger than this in one sample is the X (cut) or Z (full throttle) key or our own re-centring, not a ROD click

// The logs go in 0:/lm/logs/. Make the folder if it is missing (a fresh install, or a release zip unzipped without it).
IF NOT EXISTS("0:/lm/logs") { CREATEDIR("0:/lm/logs"). }

// The pilot's settings file (0:/lm/lm_config.txt) overrides a few of the constants above; see lm_settings.ks.
RUNONCEPATH("0:/lm/lm_settings.ks").
