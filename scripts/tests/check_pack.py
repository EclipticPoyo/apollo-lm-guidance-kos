"""check_pack.py: does the pilot's pack (docs/pack/*.md) still match the code?  Run: python scripts/tests/check_pack.py

Offline, like check_names.py. It cannot judge prose, but it catches the drift that matters most:
  1. the settings table against LM_SETTINGS (lm_settings.ks), agc_config.txt and the defaults in lm_constants.ks;
  2. the nouns, verbs and programmes the code has against the ones the pack mentions, both ways;
  3. every setting name written anywhere in the pack is a real setting;
  4. the numbers the pack quotes (times, thresholds, limits, click sizes) against the constants they come from.
Exit code 0 when everything matches, 1 otherwise. Run it before a release and after changing a constant the pack quotes.
Add a line to NUMBERS when the pack starts quoting a new constant.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
PACK_DIR = ROOT / "docs" / "pack"
PAGES = {p.name: p.read_text(encoding="utf-8").replace("\r\n", "\n") for p in sorted(PACK_DIR.glob("*.md"))}
PACK = "\n".join(PAGES.values())

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
DEG = 180 / 3.141593

# ---- 1. settings ----------------------------------------------------------------------------------------------------
settings_src = (SCRIPTS / "lm" / "lm_settings.ks").read_text(encoding="utf-8")
common_src = (SCRIPTS / "core" / "agc_settings.ks").read_text(encoding="utf-8")
common_names = re.findall(r'AGC_COMMON_SETTINGS:ADD\(LEXICON\("NAME", "(\w+)"', common_src)
cfg_names = re.findall(r'LM_SETTINGS:ADD\(LEXICON\("NAME", "(\w+)"', settings_src) + common_names
ALIAS = {"LOG": "LM_LOG"}               # the common name and the constant the LM keeps it in
LM_ONLY_ALIAS = {"LM_LOG"}              # an accepted old name of a common setting: not listed in the shipped file or the pack
cfg_names = [n for n in cfg_names if n not in LM_ONLY_ALIAS]
if not cfg_names:
    fail("settings: no LM_SETTINGS rows found in lm_settings.ks")
shipped = (SCRIPTS / "agc_config.txt").read_text(encoding="utf-8").replace("\r\n", "\n")
shipped_names = re.findall(r"^(?:// )?([A-Z][A-Z0-9_]+)\s*= ", shipped, re.M)    # a live line (the shipped file holds the defaults)
for name in cfg_names:
    checked += 1
    if name not in shipped_names:
        fail(f"settings: {name} has no commented line in agc_config.txt")
for live in re.finditer(r"^([A-Z][A-Z0-9_]+)\s*=\s*(\S+)", shipped, re.M):     # a live line must equal the code's default
    const = ALIAS.get(live.group(1), live.group(1))
    if const in C:
        checked += 1
        want, got = C[const], live.group(2)
        same = (abs(float(got) - want) < 1e-9) if isinstance(want, float) else (str(want).upper() == got.upper())
        if not same:
            fail(f"settings: agc_config.txt sets {live.group(1)} = {got} but the default in lm_constants.ks is {want}")
for name in shipped_names:
    if name not in cfg_names:
        fail(f"settings: agc_config.txt has a line for {name}, which is not in LM_SETTINGS")

# the pack's settings table (2-3-settings.md): "| NAME<br>NAME | default, default | use |"
page = PAGES.get("2-3-settings.md", "")
pack_names = set()
for r in page.split("\n"):
    if not r.startswith("| ") or r.startswith("| Setting") or r.startswith("|---"):
        continue
    cells = [c.strip() for c in r.strip().strip("|").split("|")]
    names = [n.strip() for n in cells[0].split("<br>")]
    defaults = [d.strip() for d in cells[1].split(",")]
    pack_names.update(n for n in names if n not in LM_ONLY_ALIAS)
    for name, default in zip(names, defaults):
        const = ALIAS.get(name, name)
        if const not in C:
            fail(f"settings: {name} is in the pack but not in lm_constants.ks")
            continue
        checked += 1
        want = C[const]
        ok = (abs(float(default) - want) < 1e-9) if isinstance(want, float) else (str(want).upper() == default.upper())
        if not ok:
            fail(f"settings: {name} default is {default} in the pack but {want} in lm_constants.ks")
# the table is the pilot's short list: it may leave out the rarely used settings, but never name one the code lacks
for name in pack_names:
    if name not in cfg_names:
        fail(f"settings: {name} is in the pack's settings table but is not in LM_SETTINGS")
OMITTED_OK = set()          # settings the pack deliberately leaves out; none yet, so the check below lists every omission
for name in cfg_names:
    checked += 1
    if name not in pack_names and name not in OMITTED_OK:
        fail(f"settings: {name} can be set in agc_config.txt but is not in the pack's settings table (add it, or add it to OMITTED_OK)")
# any other ALL_CAPS_WITH_UNDERSCORE word in the pack that looks like a setting must be one
for name in sorted(set(re.findall(r"\b([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b", PACK))):
    checked += 1
    if name not in cfg_names and name not in LM_ONLY_ALIAS and name not in C:
        fail(f"settings: the pack names {name}, which is neither a setting nor a constant")

# ---- 2. nouns, verbs, programmes ---------------------------------------------------------------------------------------
nouns_src = (SCRIPTS / "lm" / "lm_nouns.ks").read_text(encoding="utf-8")
code_nouns = {int(n) for n in re.findall(r"\d+", re.search(r"GLOBAL LM_NOUNS IS LIST\((.*?)\)\.", nouns_src, re.S).group(1))}
code_verbs = {int(n) for n in re.findall(r"\d+", re.search(r"GLOBAL LM_VERBS IS LIST\((.*?)\)\.", nouns_src, re.S).group(1))}
code_verbs |= {50, 59, 60, 97, 99}      # accepted do-nothing verbs (lm_vehicle.ks VERB_ACTIONS) and the programme-posted V50, V97 and V99
vehicle_src = (SCRIPTS / "lm" / "lm_vehicle.ks").read_text(encoding="utf-8")
code_progs = {int(n) for n in re.findall(r'^\s*"(\d\d)",\s*LEXICON\("START"', vehicle_src, re.M)} | {0, 27}   # P00 idle, P27 is in the core
pack_nouns = {int(n) for n in re.findall(r"\bN(\d\d)\b", PACK)}
pack_verbs = {int(n) for n in re.findall(r"\bV(\d\d)\b", PACK)}
pack_progs = {int(n) for n in re.findall(r"\bP(\d\d)\b", PACK)}
for n in sorted(code_nouns):
    checked += 1
    if n not in pack_nouns:
        fail(f"nouns: N{n:02d} exists in LM_NOUNS but the pack never mentions it")
for v in sorted(code_verbs):
    checked += 1
    if v not in pack_verbs:
        fail(f"verbs: V{v:02d} is implemented but the pack never mentions it")
for p in sorted(code_progs):
    checked += 1
    if p not in pack_progs and p != 0:
        fail(f"programmes: P{p:02d} exists in the vehicle but the pack never mentions it")
NOT_IMPLEMENTED_MENTIONS = {70, 73}     # the pack says these are not implemented
INTERNAL_NOUNS = {1, 2, 22, 99}         # P27's own displays (N01, N02) and V37 N99
for v in sorted(pack_verbs - code_verbs - NOT_IMPLEMENTED_MENTIONS):
    fail(f"verbs: the pack mentions V{v:02d}, which the code does not implement")
for n in sorted(pack_nouns - code_nouns - INTERNAL_NOUNS):
    fail(f"nouns: the pack mentions N{n:02d}, which is not in LM_NOUNS")
for p in sorted(pack_progs - code_progs):
    fail(f"programmes: the pack mentions P{p:02d}, which the vehicle does not have")

# ---- 3. quoted numbers --------------------------------------------------------------------------------------------------
WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10}
# (what, page file, regex with one group that captures the pack's number, value the code gives)
NUMBERS = [
    ("P63 hands over to P64 below this time to go (TENDBRAK)", "3-3-p63.md", r"time to go under (\d+) s", C["TENDBRAK"]),
    ("J-class P64 hands over to P66 below this time to go (J_TENDAPPR)", "1-4-profile.md", r"P64 hands to P66 under (\d+) s to go", C["J_TENDAPPR"]),
    ("V97 acceleration limit (DVMON_ACCEL_MS2)", "3-3-p63.md", r"under ([\d.]+) m/s2", C["DVMON_ACCEL_MS2"]),
    ("V97 re-ignition delay (DVMON_RETRY_S)", "3-3-p63.md", r"relight in (\d+) s", C["DVMON_RETRY_S"]),
    ("engine cut-off delay after contact (P66_CUTOFF_DELAY_S)", "3-5-landing.md", r"Cuts off (a quarter) second later", C["P66_CUTOFF_DELAY_S"]),
    ("rate-of-descent click in ft/s (RODSCALE)", "3-5-landing.md", r"Slower, (\d+) ft/s a tap", C["RODSCALE"] / FT),
    ("P65 landing rate in ft/s (V2FG)", "1-3-flight.md", r"Lands at (\d+) ft/s", 0.9144 / FT),
    ("radar altitude limit in km (RADAR_ALT_MAX_M)", "1-2-panel.md", r"altitude above (\d+) km", C["RADAR_ALT_MAX_M"] / 1000),
    ("radar velocity limit in ft/s (RADAR_V_MAX)", "1-2-panel.md", r"velocity above (\d+) ft/s", C["RADAR_V_MAX"] / FT),
    ("PDI to landing time in s (PLAN_PDI_TO_LAND_S)", "A-1-differences.md", r"landing time minus (\d+) s", C["PLAN_PDI_TO_LAND_S"]),
    ("warp stops before ignition in s (P63_WARP_LEAD_S)", "1-3-flight.md", r"warps to T-(\d+) s", C["P63_WARP_LEAD_S"]),
    ("ullage start before ignition in s (30 - ULLAGE_START_AFTER_TIG30)", "3-3-p63.md", r"ullage at about TIG-([\d.]+) s", round(30 - C["ULLAGE_START_AFTER_TIG30"], 1)),
    ("full thrust after ignition in s (ZOOMTIME)", "3-3-p63.md", r"Full thrust at TIG\+(\d+) s", C["ZOOMTIME"]),
    ("redesignation pitch click in degrees (P64_ELEACH_RAD)", "3-4-p64.md", r"W / S \| Aim point ([\d.]+) deg", round(C["P64_ELEACH_RAD"] * DEG, 1)),
    ("redesignation yaw click in degrees (P64_AZEACH_RAD)", "3-4-p64.md", r"A / D \| Aim point (\d+) deg", round(C["P64_AZEACH_RAD"] * DEG)),
    ("J-class redesignation click in degrees (J_ELEACH_RAD)", "3-4-p64.md", r"each click is (\d+) deg", round(C["J_ELEACH_RAD"] * DEG)),
    ("redesignation window closes at this time to go in s (TCGFAPPR + P64_REDES_CLOSE_S)", "3-4-p64.md", r"TTG (\d+) S \| WINDOW", C["TCGFAPPR"] + C["P64_REDES_CLOSE_S"]),
    ("uplink keys a second (1 / UPLINK_KEY_PERIOD_S)", "2-4-loads.md", r"at (five) a second", round(1 / C["UPLINK_KEY_PERIOD_S"])),
    ("first ascent lift-off at least this far ahead, minutes (ASC_LEAD_S)", "3-7-ascent.md", r"at least (\d+) minutes ahead", C["ASC_LEAD_S"] / 60),
    ("planner's furthest site from the CSM plane, deg (ASC_PLANE_MAX_DEG)", "3-7-ascent.md", r"more than (\d+) deg from the CSM", C["ASC_PLANE_MAX_DEG"]),
    ("lowest flown CSM altitude, nm (ASC_CSM_MIN_NM)", "3-7-ascent.md", r"CSM outside (\d+) to", C["ASC_CSM_MIN_NM"]),
    ("highest flown CSM altitude, nm (ASC_CSM_MAX_NM)", "3-7-ascent.md", r"CSM outside \d+ to (\d+) nm", C["ASC_CSM_MAX_NM"]),
    ("CSM eccentricity warning, nm (ASC_CSM_ECC_NM)", "3-7-ascent.md", r"perilune over (\d+) nm apart", C["ASC_CSM_ECC_NM"]),
    ("PAD cross-range limit, nm (ASC_XRANGE_PAD_M)", "3-7-ascent.md", r"Cross-range over (\d+) nm", C["ASC_XRANGE_PAD_M"] / 1852),
    ("ascent warp stops before lift-off in s (P63_WARP_LEAD_S)", "3-7-ascent.md", r"Warps to T-(\d+) s", C["P63_WARP_LEAD_S"]),
    ("P12 lift-off too close, s (ASC_SPOT_MIN_S)", "3-7-ascent.md", r"less than (\d+) s away", C["ASC_SPOT_MIN_S"]),
    ("P12 moved lift-off, s ahead (ASC_SPOT_AHEAD_S)", "3-7-ascent.md", r"moves it to about (\d+) s ahead", C["ASC_SPOT_AHEAD_S"]),
    ("vertical rise ends at, ft/s (ASC_RISE_RDOT)", "3-8-ascent-flight.md", r"Vertical rise to (\d+) ft/s", C["ASC_RISE_RDOT"] / FT),
    ("windows toward the surface, s (ASC_XOVR_S)", "3-8-ascent-flight.md", r"face the surface for (\d+) s", C["ASC_XOVR_S"]),
    ("timed ascent cut-off, s to go (ASC_T_CUT)", "3-8-ascent-flight.md", r"TTG 0:0(\d) \| COMPUTER", C["ASC_T_CUT"]),
    ("ascent V97 re-ignition delay (DVMON_RETRY_S)", "3-8-ascent-flight.md", r"new ignition in (\d+) s", C["DVMON_RETRY_S"]),
    ("insertion height, ft (ASC_HINJECT_M)", "3-8-ascent-flight.md", r"insertion at (\d+),000 ft", round(C["ASC_HINJECT_M"] / FT / 1000)),
    ("Apollo 11 apolune below the CSM, nm (ASC_APO_BELOW_A11_M)", "3-8-ascent-flight.md", r"apolune (\d+) nm \(Apollo 11\)", C["ASC_APO_BELOW_A11_M"] / 1852),
    ("J apolune below the CSM, nm (ASC_APO_BELOW_J_M)", "3-8-ascent-flight.md", r"or (\d+) nm \(J-class\)", C["ASC_APO_BELOW_J_M"] / 1852),
    ("free-fall time limit, ft (TFF_LIMIT_M)", "A-3-glossary-ascent.md", r"comes down to (\d+),000 ft", round(C["TFF_LIMIT_M"] / FT / 1000)),
]
for what, fname, pattern, want in NUMBERS:
    checked += 1
    m = re.search(pattern, PAGES.get(fname, ""), re.I)   # checklist lines are written in sentence case but printed in capitals
    if not m:
        fail(f"numbers: {fname} no longer says '{what}' (pattern {pattern})")
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
        fail(f"numbers: {what}: {fname} says {got}, the code gives {want}")

print(f"check_pack: {checked} checks, {len(problems)} problem(s)")
for p in problems:
    print("  " + p)
sys.exit(1 if problems else 0)
