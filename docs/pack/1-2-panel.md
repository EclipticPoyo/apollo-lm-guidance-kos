---
page: 1-2
section: Section 1 | System
---
## 1.3 The DSKY

The DSKY (display and keyboard) is the only way to talk to the computer. The window shows what Apollo crews saw: lamps, a programme and verb/noun display, and three registers.

<div class="fig">
<div class="photo">
<img src="images/dsky.png" alt="The DSKY window in P63 with verb 16 noun 60 monitoring">
<span class="co r" style="top:17%">1</span><span class="co r" style="top:54%">2</span><span class="co l" style="top:40%">3</span><span class="co r" style="top:77%">4</span>
</div>
<div class="cap">Figure 1-2. <span>DSKY window in P63, monitoring N60</span></div>
</div>

1. **PROG, VERB, NOUN.** What is running, what the display is doing, and which data it shows.
2. **R1, R2, R3.** Three registers, each a sign and five digits with no decimal point. Units depend on the noun (2.3).
3. **Lamps.** See table 1-1.
4. **Keys.** [[PRO]] proceeds. [[ENTR]] accepts what you keyed. [[CLR]] drops what you are keying. [[RSET]] clears OPR ERR and PROG. [[KEY REL]] gives the display back to a flashing request.

### Table 1-1. Lamps

<!--table st-->
| Lamp | Lit when |
|---|---|
| COMP ACTY | A programme is running. Dark when nothing runs. |
| PROG | A programme alarm. Stays lit until [[RSET]]. `V05 N09 E` shows the codes. |
| OPR ERR | A bad key entry or a refused programme. [[RSET]] clears it. |
| KEY REL | A flashing request is waiting behind what you keyed. The [[KEY REL]] button gives the display back. |
| ALT, VEL | Landing radar altitude or velocity data is not good (altitude above 12 km, velocity above 2000 ft/s, or a failed check). |
| CONTACT | The lander has touched down. |
| ATT HOLD | SAS is on and the computer has recognised it. A ROD click starts P66 while it is lit. |
| UPLINK ACTY | An uplink is loading. NO ATT, STBY, TEMP, GIMBAL LOCK, RESTART and TRACKER never light. |
