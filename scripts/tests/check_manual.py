"""check_manual.py: does docs/MANUAL.md still match the code?  Run: python scripts/tests/check_manual.py

Offline, like check_names.py. It cannot judge prose, but it catches the drift that matters most:
  1. the settings table against CFG_NAMES (lm_settings.ks) and the defaults in lm_constants.ks;
  2. the nouns and verbs the code has against the ones the manual mentions;
  3. the numbers the manual quotes (times, thresholds, limits, click sizes) against the constants they come from.
Exit code 0 when everything matches, 1 otherwise. Run it before a release and after changing a constant the manual quotes.
Add a line to NUMBERS when the manual starts quoting a new constant.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
MANUAL = (ROOT / "docs" / "MANUAL.md").read_text(encoding="utf-8").replace("\r\n", "\n")

problems = []
checked = 0


def fail(msg):
    problems.append(msg)


# ---- read the constants -------------------------------------------------------------------------------------------
def read_constants(*paths):
    """GLOBAL NAME IS <number | "text" | TRUE | FALSE>.  -> {name: python value}; other expressions are skipped."""
    out = {}
    for p in paths:
        for line in Path(p).read_text(encoding="utf-8").replace("\r\n", "\n").split("\n"):
            m = re.match(r"\s*GLOBAL\s+(\w+)\s+IS\s+(.+?)\.\s*(//.*)?$", line)
            if not m:
                continue
            name, expr = m.group(1).upper(), m.group(2).strip()
            if re.fullmatch(r"-?\d+(\.\d+)?", expr):
                out[name] = float(expr)
            elif expr.upper() in ("TRUE", "FALSE"):
                out[name] = expr.upper()
            elif re.fullmatch(r'"[^"]*"', expr):
                out[name] = expr.strip('"')
    return out


C = read_constants(SCRIPTS / "lm" / "lm_constants.ks", SCRIPTS / "lm" / "descent_j" / "lm_j_constants.ks",
                   SCRIPTS / "core" / "dsky_uplink.ks")
FT = 0.3048

# ---- 1. settings ----------------------------------------------------------------------------------------------------
settings_src = (SCRIPTS / "lm" / "lm_settings.ks").read_text(encoding="utf-8")
cfg_names = re.findall(r'"(\w+)"', re.search(r"GLOBAL CFG_NAMES IS LIST\((.*?)\)\.", settings_src, re.S).group(1))
sect = MANUAL.split("## 8. Settings")[1].split("\n## ")[0]
rows = [r for r in sect.split("\n") if r.startswith("| `")]
manual_names = set()
for r in rows:
    cells = [c.strip() for c in r.strip("|").split("|")]
    names = re.findall(r"`(\w+)`", cells[0])
    manual_names.update(names)
    defaults = [d.strip().strip("`").strip('"') for d in cells[1].split(",")]
    for name, default in zip(names, defaults):
        if name not in C:
            fail(f"settings: {name} is in the manual but not in lm_constants.ks")
            continue
        checked += 1
        want = C[name]
        ok = (abs(float(default) - want) < 1e-9) if isinstance(want, float) else (str(want).upper() == default.upper())
        if not ok:
            fail(f"settings: {name} default is {default} in the manual but {want} in lm_constants.ks")
for name in cfg_names:
    checked += 1
    if name not in manual_names:
        fail(f"settings: {name} can be set in lm_config.txt but is not in the manual's settings table")
for name in manual_names:
    if name not in cfg_names:
        fail(f"settings: {name} is in the manual's settings table but is not in CFG_NAMES")

# ---- 2. nouns and verbs -----------------------------------------------------------------------------------------------
nouns_src = (SCRIPTS / "lm" / "lm_nouns.ks").read_text(encoding="utf-8")
code_nouns = {int(n) for n in re.findall(r"\d+", re.search(r"GLOBAL LM_NOUNS IS LIST\((.*?)\)\.", nouns_src, re.S).group(1))}
code_verbs = {int(n) for n in re.findall(r"\d+", re.search(r"GLOBAL LM_VERBS IS LIST\((.*?)\)\.", nouns_src, re.S).group(1))}
code_verbs |= {59, 60, 97, 99}          # accepted do-nothing verbs (lm_vehicle.ks VERB_ACTIONS) and the programme-posted V97 and V99
manual_nouns = {int(n) for n in re.findall(r"\bN(\d\d)\b", MANUAL)}
manual_verbs = {int(n) for n in re.findall(r"\bV(\d\d)\b", MANUAL)}
for n in sorted(code_nouns):
    checked += 1
    if n not in manual_nouns:
        fail(f"nouns: N{n:02d} exists in LM_NOUNS but the manual never mentions it")
for v in sorted(code_verbs):
    checked += 1
    if v not in manual_verbs:
        fail(f"verbs: V{v:02d} is implemented but the manual never mentions it")
NOT_IMPLEMENTED_MENTIONS = {70, 73}     # the manual says these are not implemented
INTERNAL_NOUNS = {1, 2, 22, 99}         # P27's own displays (N01, N02) and V37 N99; N22 is named only as a Luminary noun
for v in sorted(manual_verbs - code_verbs - NOT_IMPLEMENTED_MENTIONS):
    fail(f"verbs: the manual mentions V{v:02d}, which the code does not implement")
for n in sorted(manual_nouns - code_nouns - INTERNAL_NOUNS):
    fail(f"nouns: the manual mentions N{n:02d}, which is not in LM_NOUNS")

# ---- 3. quoted numbers --------------------------------------------------------------------------------------------------
WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10}
plan_ui = (SCRIPTS / "lm" / "planner" / "lm_plan_ui.ks").read_text(encoding="utf-8")
pc_default = float(re.search(r'pc_cell:ADDTEXTFIELD\("(\d+)"\)', plan_ui).group(1))
# (what, regex with one group that captures the manual's number, value the code gives)
NUMBERS = [
    ("P63 hands over to P64 below this time to go (TENDBRAK)", r"nearly over \(time to go below (\d+) s\)", C["TENDBRAK"]),
    ("J-class P64 hands over to P66 below this time to go (J_TENDAPPR)", r"time to go falls below (\d+) s, P64 hands over straight", C["J_TENDAPPR"]),
    ("V97 acceleration limit (DVMON_ACCEL_MS2)", r"under ([\d.]+) m/s²", C["DVMON_ACCEL_MS2"]),
    ("V97 re-ignition delay (DVMON_RETRY_S)", r"lights it again (\d+) s later", C["DVMON_RETRY_S"]),
    ("engine cut-off delay after contact (P66_CUTOFF_DELAY_S)", r"engine cuts off (a quarter) of a second", C["P66_CUTOFF_DELAY_S"]),
    ("rate-of-descent click in ft/s (RODSCALE)", r"one rate-of-descent click of (\d+) ft/s", C["RODSCALE"] / FT),
    ("P65 landing rate in ft/s (V2FG)", r"settles to a descent of (\d+) ft/s", 0.9144 / FT),
    ("radar altitude limit in km (RADAR_ALT_MAX_M)", r"altitude above (\d+) km", C["RADAR_ALT_MAX_M"] / 1000),
    ("radar velocity limit in ft/s (RADAR_V_MAX)", r"velocity above (\d+) ft/s", C["RADAR_V_MAX"] / FT),
    ("rated descent thrust in kN (J_DPS_RATED_KN)", r"([\d.]+) kN rating", C["J_DPS_RATED_KN"]),
    ("J-class radar cut-off in ft (J_HLROFF)", r"not used below (\d+) ft", C["J_HLROFF"] / FT),
    ("plane change threshold in km (PLAN_XRANGE_MAX)", r"more than (\d+) km out of your orbit plane", C["PLAN_XRANGE_MAX"] / 1000),
    ("planner default for the largest plane change in m/s", r"\(default (\d+) m/s\)", pc_default),
    ("PDI to landing time in s (PLAN_PDI_TO_LAND_S)", r"landing minus (\d+) s", C["PLAN_PDI_TO_LAND_S"]),
    ("warp stops before ignition in s (P63_WARP_LEAD_S)", r"warps to (\d+) s before ignition", C["P63_WARP_LEAD_S"]),
    ("ullage start before ignition in s (30 - ULLAGE_START_AFTER_TIG30)", r"ullage fires at about ([\d.]+) s before ignition", round(30 - C["ULLAGE_START_AFTER_TIG30"], 1)),
    ("throttle-up after ignition in s (ZOOMTIME)", r"full throttle (\d+) s later", C["ZOOMTIME"]),
    ("P64 time-to-go step, Apollo 11 (DELTTFAP)", r"not (-\d+) s\)", C["DELTTFAP"]),
    ("P64 time-to-go step, J-class (J_DELTTFAP)", r"step is (-\d+) s, not", C["J_DELTTFAP"]),
    ("redesignation pitch click in degrees (P64_ELEACH_RAD)", r"\*\*W\*\* or \*\*S\*\* \(pitch\) moves the aim point ([\d.]+)°", round(C["P64_ELEACH_RAD"] * 180 / 3.141593, 1)),
    ("redesignation yaw click in degrees (P64_AZEACH_RAD)", r"\*\*A\*\* or \*\*D\*\* \(yaw\) moves it (\d+)°", round(C["P64_AZEACH_RAD"] * 180 / 3.141593)),
    ("J-class redesignation click in degrees (J_ELEACH_RAD)", r"each redesignation click moves the aim point \*\*(\d+)°\*\*", round(C["J_ELEACH_RAD"] * 180 / 3.141593)),
    ("redesignation window closes at this time to go in s (TCGFAPPR + P64_REDES_CLOSE_S)", r"when (\d+) s of time to go remain", C["TCGFAPPR"] + C["P64_REDES_CLOSE_S"]),
    ("uplink keys a second (1 / UPLINK_KEY_PERIOD_S)", r"at (five) a second", round(1 / C["UPLINK_KEY_PERIOD_S"])),
    ("J-class horizontal nulling time constant in s (J_TAUHZ * (1 + J_QHZ))", r"time constant about (\d+) s", round(C["J_TAUHZ"] * (1 + C["J_QHZ"]))),
]
for what, pattern, want in NUMBERS:
    checked += 1
    m = re.search(pattern, MANUAL)
    if not m:
        fail(f"numbers: the manual no longer says '{what}' (pattern {pattern})")
        continue
    got = m.group(1)
    got = WORDS.get(got, got)
    if got == "a quarter":
        got = 0.25
    try:
        ok = abs(float(got) - float(want)) < 1e-6 + 0.005 * abs(float(want))
    except (TypeError, ValueError):
        ok = got == want
    if not ok:
        fail(f"numbers: {what}: the manual says {got}, the code gives {want}")

print(f"check_manual: {checked} checks, {len(problems)} problem(s)")
for p in problems:
    print("  " + p)
sys.exit(1 if problems else 0)
