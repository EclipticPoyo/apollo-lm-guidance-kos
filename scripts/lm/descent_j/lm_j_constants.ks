// lm_j_constants.ks -- the descent constants of the J-class profile (Luminary 210, Apollo 15 to 17).
//
// Source: the Apollo 17 final E-load ("FINAL LGC E-LOAD, LUMINARY 210, APOLLO 17, 11-02-72"), read from the page images; every value
// below is in docs/superpowers/specs/2026-11-13-luminary210-padloads-research.md with its Apollo 11 value beside it. Apollo 15, 16 and
// 17 share all of these except VIGN, RIGNX, RIGNZ and DELTTFAP, for which the Apollo 17 numbers are used (one J profile, user's choice).
// The real values are used as they are.
//
// Every name starts with J_ so this file can be loaded next to lm_constants.ks (kOS has one global namespace). The
// Apollo 11 constants stay in lm_constants.ks; nothing here changes them. Guidance-frame vectors are V(up, crossrange, downrange).
//
// Units: the pad load prints AGC units (m, m/cs, m/cs^2, m/cs^3). 1 m/cs = 100 m/s, 1 m/cs^2 = 1e4 m/s^2, 1 m/cs^3 = 1e6 m/s^3.

// ---- Ignition (IGNALG): where powered descent starts, and the gains that time it ----
GLOBAL J_RIGNX IS -47593.00514.        // pad load (Apollo 17): PDI position, up component, m
GLOBAL J_RIGNZ IS -469983.8606.        // pad load (Apollo 17): PDI position, downrange component, m
GLOBAL J_VIGN IS 1689.475188.          // pad load (Apollo 17): speed at PDI, m/s
GLOBAL J_KIGNX IS -0.334.              // pad load, dimensionless
GLOBAL J_KIGNY IS -7.240813648e-7.     // pad load, 1/m
GLOBAL J_KIGNV IS -498.                // pad load, s
GLOBAL J_ZOOMTIME IS 26.               // pad load, s: throttle-up after nominal ignition
GLOBAL J_LEADTIME IS -2.2.             // pad load, s: guidance lead for engine lag (negative)

// ---- Braking phase (P63) ----
GLOBAL J_RBRFG IS V(-950.4757622, 0, -3578.791217).   // braking target position, m (the target is about 950 m BELOW the site plane)
GLOBAL J_VBRFG IS V(-59.88380, 0, -50.828448).         // braking target velocity, m/s
GLOBAL J_ABRFG IS V(-0.2189220, 0, -2.530587).        // braking target acceleration, m/s^2
// JBRFG*: the pad load -4.609691263e-9 m/cs^3 is -4.6097e-3 m/s^3. Following the Apollo 11 convention (jerk = starred / 8)
// the downrange jerk is -5.762e-4 m/s^3. UNVERIFIED for Apollo 17 (research note: the scale factors were only cross-checked
// for VBRFG*). Only the downrange component enters the time-to-go cubic.
GLOBAL J_JBRFG_Z IS -5.76211408e-4.
GLOBAL J_GAINBRAK IS 0.9999999963.     // pad load: lunar-rotation lead gain
GLOBAL J_TCGFBRAK IS 30.               // pad load, s
GLOBAL J_TCGIBRAK IS 900.              // pad load, s
GLOBAL J_TENDBRAK IS 62.               // pad load, s: braking ends (P64 starts) when time-to-go falls below this

// ---- Approach phase (P64) ----
GLOBAL J_RAPFG IS V(48.31080, 0, -8.337926).          // approach target position, m
GLOBAL J_VAPFG IS V(-1.077395, 0, 0.0076049).         // approach target velocity, m/s
GLOBAL J_AAPFG IS V(0.02352395, 0, -0.1797183).       // approach target acceleration, m/s^2
// JAPFG*: the pad load 1.315931328e-8 m/cs^3 is 1.3159e-2 m/s^3, so by the same convention the downrange jerk is 1.645e-3 m/s^3.
// UNVERIFIED, and 24 times the Apollo 11 value (5.51e-4 starred): flagged in the research note. Used as read, as decided.
GLOBAL J_JAPFG_Z IS 1.64491416e-3.
GLOBAL J_GAINAPPR IS 0.                // pad load
GLOBAL J_TCGFAPPR IS 6.                // pad load, s (Apollo 11: 30)
GLOBAL J_TCGIAPPR IS 200.              // pad load, s
GLOBAL J_TENDAPPR IS 12.               // pad load, s: the approach ends and P66 starts when time-to-go falls below this
GLOBAL J_DELTTFAP IS -70.              // pad load (Apollo 17 and 16; Apollo 15 was -90), s: added to time-to-go at the P64 start
// Redesignation (source constants of Luminary 210, not pad loads): one click is one degree on both axes.
GLOBAL J_ELEACH_RAD IS 0.01746.        // source line 1447 (= AZEACH), rad
GLOBAL J_AZEACH_RAD IS 0.01746.        // source line 1444, rad (Apollo 11: 2 degrees)
// (P64DB, 0.3 degrees, is the attitude deadband Luminary 210 puts in force at the P64 start. It is not a constant here: it is a
// DAP deadband for the RCS jets, and in P64 the engine burns, so the steering lock stays on and no deadband applies; see lm_j_p63.ks.)
GLOBAL J_HLROFF IS 15.24.              // source (THE_LUNAR_LANDING): landing radar not used below this height, m (50 ft)

// ---- P66: rate of descent and horizontal nulling ----
GLOBAL J_RODSCALE IS 0.3048.           // pad load, m/s per click (1 ft/s)
GLOBAL J_TAUROD IS 1.5.                // pad load, s
GLOBAL J_LAG_TAU IS 0.2333.            // pad load (Apollo 11: 0.413333)
GLOBAL J_MINFORCE IS 4360.             // pad load, N (980 lbf)
GLOBAL J_MAXFORCE IS 28000.            // pad load, N (6300 lbf)
GLOBAL J_TAUHZ IS 5.                   // pad load, s: horizontal velocity-nulling time constant
GLOBAL J_QHZ IS 0.4.                   // pad load: weight on the previous horizontal command
GLOBAL J_HZ_PERIOD_S IS 2.             // Luminary's servicer pass, s: the horizontal law is evaluated this often and held in between (see lm_j_p66.ks)
GLOBAL J_AHZLIM IS 0.591001104.            // pad load, m/s^2 (1.93898 ft/s^2): limit on the horizontal acceleration command
