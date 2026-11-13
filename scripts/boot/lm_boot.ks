// lm_boot.ks -- boot file: makes the archive (volume 0:) the current volume when the ship loads, so RUN dsky., RUN plan.
// and RUN pad. work without typing SWITCH TO 0. first.
//
// Copy it to <KSP>/Ships/Script/boot/ (the release zip does), then pick "boot/lm_boot.ks" as the boot file on the kOS
// processor in the VAB or SPH (right-click the part, "Boot file"). kOS runs it each time the ship is loaded or the CPU is
// rebooted. It does nothing else.

WAIT 1.                      // give the ship a moment to finish loading
SWITCH TO 0.
CLEARSCREEN.
PRINT "Archive selected. RUN plan. to plan, RUN dsky. for the DSKY.".
