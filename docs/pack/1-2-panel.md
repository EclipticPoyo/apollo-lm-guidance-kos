---
page: 1-2
section: Section 1 | System
---
## 1.2 The DSKY

The DSKY (display and keyboard) is the only way to talk to the computer. The window shows what Apollo crews saw: lamps, a programme and verb/noun display, and three registers.

<div class="fig">
<div class="photo">
<img src="images/dsky.png" alt="The DSKY window in P00 with verb 16 noun 44 monitoring">
<span class="co r" style="top:19%">1</span><span class="co r" style="top:50%">2</span><span class="co l" style="top:35%">3</span><span class="co r" style="top:78%">4</span>
</div>
<div class="cap">Figure 1-2. <span>DSKY window in P00, monitoring N44 (V82)</span></div>
</div>

1. **PROG, VERB, NOUN.** What is running, what the display is doing, and which data it shows.
2. **R1, R2, R3.** Three registers, each a sign and five digits with no decimal point. Units depend on the noun ({@2-2 2.2}).
3. **Lamps.** Shown below.
4. **Keys.** [[PRO]] proceeds. [[ENTR]] accepts what you keyed. [[CLR]] drops what you are keying. [[RSET]] clears OPR ERR, PROG and the terminal's warnings. [[KEY REL]] gives the display back to a flashing request.

### Lamps

```lamps
- COMP ACTY | green | A programme is running. Dark when nothing runs.
- PROG | amber | A programme alarm. Stays lit until [[RSET]]. `V05 N09 E` shows the codes.
- OPR ERR | white | A bad key entry or a refused programme. [[RSET]] clears it.
- ALT, VEL | amber | Landing radar altitude or velocity data is not good (altitude above 12 km, velocity above 2000 ft/s, or a failed check).
- KEY REL | white | What you keyed covers a display or a flashing request, or a tracking request is waiting. The [[KEY REL]] button gives the display back.
- CONTACT | white | The lander has touched down.
- ATT HOLD | white | SAS is on and the computer has recognised it. A ROD click starts P66 while it is lit.
- UPLINK ACTY | white | An uplink is loading.
```

NO ATT, STBY, TEMP, GIMBAL LOCK, RESTART and TRACKER never light.

<!--sheet-->

### Drift gauge

<div class="fig"><div class="photo gauge"><img src="images/los-rate.png" alt="The LOS RATE window: the level needle above the middle, the upright one left of it"></div><div class="cap">Figure 1-3. <span>Drift gauge on the 2 mrad/s scale: thrust up and left</span></div></div>

A small **LOS RATE** window right of the DSKY stands for the LM's cross-pointer: how fast the line to the CSM is turning. Two dark needles cross on a light dial, which has a mark at each quarter of full scale: the level one moves up and down (towards the nose is up), the upright one left and right, seen through the front windows. A needle off the middle means: thrust that way; on an end mark it is at full scale or more. Between the dial and the keys: **RANGE** to the CSM (ft under 10,000 ft, then nm), **RATE** (ft/s, minus is closing) and the next braking gate with its speed, signed the same way ({@3-17}). The two keys under the dial set the full scale, 20 or 2 mrad/s; the lit one is in use. `-` at the top shrinks the window to its name and `+` brings it back.

It shows while P20 or P25 runs or in P47, with the CSM within 40 nm and the LM not landed. With the front windows more than 30 deg off the CSM both needles stand at the middle and the line above the keys says `+Z OFF THE CSM`; the figures stay.
