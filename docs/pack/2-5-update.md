---
page: 2-5
section: Section 2 | Reference
---
## 2.6 Update programme P27 (V71, V72)

Only in P00. Everything is octal.

<!--table st-->
| Keys | Does |
|---|---|
| `V71E`, `II E`, `AAAA E`, `XXXXX E` for each word, `V33E` | Block update: write the words from address `AAAA`. `II` is the number of words plus 2 (3 to 24 octal) |
| `V72E`, `II E`, `AAAA E` `XXXXX E` pairs, `V33E` | Scatter update: `II` is odd (3 to 23 octal), twice the pairs plus 1 |
| `V34E` | Throw the block away |

~V21 N01~ flashes while P27 runs. R1 shows the digits you key, R3 the address the word goes to. At the verify step (N02) answer `V33E` to store or `V34E` to discard. An 8 or 9, a bad count, or an address the store does not hold gives OPR ERR and the whole block is dropped.

> NOTE: The AGC clock counts from the vessel's mission time zero, which KSP restarts at an undock. The planner saves that zero in `clock.txt`, so you can plan docked, undock, then send.
