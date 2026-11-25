// probe_ascent_all.ks -- throwaway probe for release 1.5: both ascent probes in one run. IT SEPARATES THE STAGES AND FLIES.
// QUICKSAVE (F5) FIRST; quickload (hold F9) afterwards to get the landed ship back.
//   RUNPATH("0:/tests/probe_ascent_all.ks").
// Setup: the lander landed on the Moon, upright, throttle at zero, no CSM needed. About 8 minutes, no time warp.
// Logs: 0:/lm/logs/probe_ascent.log and 0:/lm/logs/probe_ascent_fly.log

RUNPATH("0:/tests/probe_ascent.ks").
RUNPATH("0:/tests/probe_ascent_fly.ks").
