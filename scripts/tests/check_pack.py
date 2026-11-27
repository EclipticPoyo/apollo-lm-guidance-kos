"""check_pack.py: does the pilot's pack (docs/pack/*.md) still match the code?  Run: python scripts/tests/check_pack.py

Offline, like check_names.py. It cannot judge prose, but it catches the drift that matters most:
  1. the settings table against LM_SETTINGS (lm_settings.ks), agc_config.txt and the defaults in lm_constants.ks;
  2. the nouns, verbs and programmes the code has against the ones the pack mentions, both ways;
  3. every setting name written anywhere in the pack is a real setting;
  4. the numbers the pack quotes (times, thresholds, limits, click sizes) against the constants they come from.
  5. every page link leads to a page, and no checklist or card tells the pilot to change a setting;
     the rendezvous pages say where the software versions part, and make_pack.py's route table names the right pages.
Exit code 0 when everything matches, 1 otherwise. Run it before a release and after changing a constant the pack quotes.
Add a line to NUMBERS when the pack starts quoting a new constant.
"""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
PACK_DIR = ROOT / "docs" / "pack"
PARTS = {p.stem: p.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n") for p in sorted((PACK_DIR / "parts").glob("*.txt"))}
# each page as it prints: a "use: name" line replaced by that part
PAGES = {p.name: re.sub(r"^use: (\S+)$", lambda m: PARTS.get(m.group(1), m.group(0)), p.read_text(encoding="utf-8").replace("\r\n", "\n"), flags=re.M)
         for p in sorted(PACK_DIR.glob("*.md"))}
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
                   SCRIPTS / "core" / "dsky_uplink.ks", SCRIPTS / "lm" / "rndz" / "lm_rndz.ks",
                   SCRIPTS / "lm" / "rndz" / "lm_p32.ks", SCRIPTS / "lm" / "rndz" / "lm_p34.ks")
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
# each line says its default, so it can still be read after the value has been changed: first after //, in one column
default_bars = set()
for live in re.finditer(r"^([A-Z][A-Z0-9_]+)\s*=\s*(\S+)(.*)$", shipped, re.M):
    checked += 1
    noted = re.match(r"\s*// default (\S+) *\| ", live.group(3))
    if not noted or noted.group(1) != live.group(2):
        fail(f"settings: the {live.group(1)} line of agc_config.txt does not start '// default {live.group(2)} |'")
    else:
        default_bars.add(live.group(0).index("|"))
checked += 1
if len(default_bars) > 1:
    fail(f"settings: the default column of agc_config.txt is not lined up (| at {sorted(default_bars)})")

# the pack's settings table (2-4-settings.md): "| NAME<br>NAME | default, default | use |"
page = PAGES.get("2-4-settings.md", "").split("\n### ")[0]      # the settings table only: P27 shares the page
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
# the metric figure in brackets after an Apollo one on a checklist
METRIC = re.compile(r" \((?:[\d.]+ to )?[\d.]+ (?:m/s|km|m)\)")

NUMBERS = [
    ("J-class: the approach hands to P66 at this time to go, as the checklist says (J_TENDAPPR)", "3-7-p64.md", r"TTG (\d+) S \| P66", C["J_TENDAPPR"]),
    ("J-class short rendezvous: insertion to TPI, min (ASC_J_TPI_S)", "3-15-tpi-210.md", r"TPI about (\d+) min after insertion", C["ASC_J_TPI_S"] / 60),
    ("J-class short rendezvous on the ascent page, min (ASC_J_TPI_S)", "3-11-ascent-flight.md", r"about (\d+) min after insertion", C["ASC_J_TPI_S"] / 60),
    ("P63 hands over to P64 below this time to go (TENDBRAK)", "3-6-p63.md", r"time to go under (\d+) s", C["TENDBRAK"]),
    ("V97 acceleration limit (DVMON_ACCEL_MS2)", "3-6-p63.md", r"under ([\d.]+) m/s2", C["DVMON_ACCEL_MS2"]),
    ("V97 re-ignition delay (DVMON_RETRY_S)", "3-6-p63.md", r"relight in (\d+) s", C["DVMON_RETRY_S"]),
    ("engine cut-off delay after contact (P66_CUTOFF_DELAY_S)", "3-8-landing.md", r"Cuts off (a quarter) second later", C["P66_CUTOFF_DELAY_S"]),
    ("rate-of-descent click in ft/s (RODSCALE)", "3-8-landing.md", r"Slower, (\d+) ft/s a tap", C["RODSCALE"] / FT),
    ("P65 landing rate in ft/s (V2FG)", "1-1-overview.md", r"Lands at (\d+) ft/s", 0.9144 / FT),
    ("radar altitude limit in km (RADAR_ALT_MAX_M)", "1-2-panel.md", r"altitude above (\d+) km", C["RADAR_ALT_MAX_M"] / 1000),
    ("radar velocity limit in ft/s (RADAR_V_MAX)", "1-2-panel.md", r"velocity above (\d+) ft/s", C["RADAR_V_MAX"] / FT),
    ("PDI to landing time in s (PLAN_PDI_TO_LAND_S)", "A-1-differences.md", r"landing time minus (\d+) s", C["PLAN_PDI_TO_LAND_S"]),
    ("warp stops before ignition in s (P63_WARP_LEAD_S)", "1-1-overview.md", r"warps to T-(\d+) s", C["P63_WARP_LEAD_S"]),
    ("ullage start before ignition in s (30 - ULLAGE_START_AFTER_TIG30)", "3-6-p63.md", r"TIG-0:0([\d.]+) \| RCS \| Ullage", round(30 - C["ULLAGE_START_AFTER_TIG30"], 1)),
    ("full thrust after ignition in s (ZOOMTIME)", "3-6-p63.md", r"TIG\+0:(\d+) \| ENGINE \| Full thrust", C["ZOOMTIME"]),
    ("redesignation pitch click in degrees (P64_ELEACH_RAD)", "3-7-p64.md", r"W / S \| Aim point ([\d.]+) deg", round(C["P64_ELEACH_RAD"] * DEG, 1)),
    ("redesignation yaw click in degrees (P64_AZEACH_RAD)", "3-7-p64.md", r"A / D \| Aim point (\d+) deg", round(C["P64_AZEACH_RAD"] * DEG)),
    ("J-class redesignation click in degrees (J_ELEACH_RAD)", "3-7-p64.md", r"\[J\] - \| W / S, A / D \| Aim point (\d+) deg", round(C["J_ELEACH_RAD"] * DEG)),
    ("redesignation window closes at this time to go in s (TCGFAPPR + P64_REDES_CLOSE_S)", "3-7-p64.md", r"TTG (\d+) S \| WINDOW", C["TCGFAPPR"] + C["P64_REDES_CLOSE_S"]),
    ("uplink keys a second (1 / UPLINK_KEY_PERIOD_S)", "2-5-loads.md", r"at (five) a second", round(1 / C["UPLINK_KEY_PERIOD_S"])),
    ("first ascent lift-off at least this far ahead, minutes (ASC_LEAD_S)", "3-10-ascent.md", r"at least (\d+) minutes ahead", C["ASC_LEAD_S"] / 60),
    ("planner's furthest site from the CSM plane, deg (ASC_PLANE_MAX_DEG)", "3-10-ascent.md", r"more than (\d+) deg from the CSM", C["ASC_PLANE_MAX_DEG"]),
    ("lowest flown CSM altitude, nm (ASC_CSM_MIN_NM)", "3-10-ascent.md", r"CSM outside (\d+) to", C["ASC_CSM_MIN_NM"]),
    ("highest flown CSM altitude, nm (ASC_CSM_MAX_NM)", "3-10-ascent.md", r"CSM outside \d+ to (\d+) nm", C["ASC_CSM_MAX_NM"]),
    ("CSM eccentricity warning, nm (ASC_CSM_ECC_NM)", "3-10-ascent.md", r"perilune over (\d+) nm apart", C["ASC_CSM_ECC_NM"]),
    ("PAD cross-range limit, nm (ASC_XRANGE_PAD_M)", "3-10-ascent.md", r"Cross-range over (\d+) nm", C["ASC_XRANGE_PAD_M"] / 1852),
    ("ascent warp stops before lift-off in s (P63_WARP_LEAD_S)", "3-10-ascent.md", r"Warps to T-(\d+) s", C["P63_WARP_LEAD_S"]),
    ("P12 lift-off too close, s (ASC_SPOT_MIN_S)", "3-10-ascent.md", r"less than (\d+) s away", C["ASC_SPOT_MIN_S"]),
    ("P12 moved lift-off, s ahead (ASC_SPOT_AHEAD_S)", "3-10-ascent.md", r"moves it to about (\d+) s ahead", C["ASC_SPOT_AHEAD_S"]),
    ("vertical rise ends at, ft/s (ASC_RISE_RDOT)", "3-11-ascent-flight.md", r"vertical rise to (\d+) ft/s", C["ASC_RISE_RDOT"] / FT),
    ("windows towards the surface, s (ASC_XOVR_S)", "3-11-ascent-flight.md", r"face the surface for (\d+) s", C["ASC_XOVR_S"]),
    ("timed ascent cut-off, s to go (ASC_T_CUT)", "3-11-ascent-flight.md", r"TTG 0:0(\d) \| COMPUTER", C["ASC_T_CUT"]),
    ("ascent V97 re-ignition delay (DVMON_RETRY_S)", "3-11-ascent-flight.md", r"new ignition in (\d+) s", C["DVMON_RETRY_S"]),
    ("insertion height, ft (ASC_HINJECT_M)", "3-11-ascent-flight.md", r"insertion at (\d+),000 ft", round(C["ASC_HINJECT_M"] / FT / 1000)),
    ("Apollo 11 apolune below the CSM, nm (ASC_APO_BELOW_A11_M)", "3-11-ascent-flight.md", r"\[A11\] n: Aimed at apolune (\d+) nm", C["ASC_APO_BELOW_A11_M"] / 1852),
    ("J apolune below the CSM, nm (ASC_APO_BELOW_J_M)", "3-11-ascent-flight.md", r"\[J\] n: Aimed at apolune (\d+) nm", C["ASC_APO_BELOW_J_M"] / 1852),
    ("free-fall time limit, ft (TFF_LIMIT_M)", "A-4-glossary-ascent.md", r"comes down to (\d+),000 ft", round(C["TFF_LIMIT_M"] / FT / 1000)),
    ("abort cross-range steered out, nm (ABT_YLIM_M)", "3-9-abort.md", r"cross-range (?:steered )?up to ([\d.]+) nm", round(C["ABT_YLIM_M"] / 1852, 1)),
    ("abort vertical rise below, ft (ASC_RISE_ALT_M)", "3-9-abort.md", r"Below (\d+),000 ft above the site", round(C["ASC_RISE_ALT_M"] / FT / 1000)),
    ("abort yaw after the rise, s (ASC_XOVR_S)", "3-9-abort.md", r"from (\d+) s after the pitch-over", C["ASC_XOVR_S"]),
    ("abort perilune aimed at, ft (ASC_HINJECT_M)", "3-9-abort.md", r"perilune (\d+),000 ft", round(C["ASC_HINJECT_M"] / FT / 1000)),
    ("abort insertion radial speed, ft/s (ABT_RDOTD)", "3-9-abort.md", r"climbing at ([\d.]+) ft/s", round(C["ABT_RDOTD"] / FT, 1)),
    ("abort V97 re-ignition delay (DVMON_RETRY_S)", "3-9-abort.md", r"new ignition in (\d+) s", C["DVMON_RETRY_S"]),
    ("J abort least apolune, nm (J_ABT_RAMIN)", "3-9-abort.md", r"never under (\d+) nm", round((C["J_ABT_RAMIN"] * FT - 1734484) / 1852)),
    ("planner warning for the CSM, deg (A11)", "3-1-startup.md", r"\[A11\] n: Amber when more than (\d+) deg off", C["ABT_PLAN_TOL_A11_DEG"]),
    ("planner warning for the CSM, deg (J)", "3-1-startup.md", r"\[J\] n: Amber when more than (\d+) deg off", C["ABT_PLAN_TOL_J_DEG"]),
    ("TPI elevation angle loaded when there is none, deg (P32_ELEV_DEG)", "3-12-csi.md", r"R2 ([\d.]+) deg", C["P32_ELEV_DEG"]),
    ("lowest perilune after CSI or CDH, ft (RNDZ_MIN_PERILUNE)", "3-12-csi.md", r"under (\d+),000 ft", round(C["RNDZ_MIN_PERILUNE"] / FT / 1000)),
    ("least time between CSI, CDH and TPI, min (RNDZ_MIN_GAP)", "3-12-csi.md", r"under (\d+) minutes", C["RNDZ_MIN_GAP"] / 60),
    ("CSI iteration limit (RNDZ_MAX_COUNT)", "3-12-csi.md", r"within (\d+) tries", C["RNDZ_MAX_COUNT"]),
    ("largest CSI delta-V, ft/s (RNDZ_DV_LIMIT)", "3-12-csi.md", r"over (\d+) ft/s", round(C["RNDZ_DV_LIMIT"] / FT)),
    ("the CSM's travel from TPI to the intercept, deg (P34_CENTANG_DEG)", "3-14-tpi.md", r"travel ([\d.]+) deg", C["P34_CENTANG_DEG"]),
    ("the same on the 210 TPI page (P34_CENTANG_DEG)", "3-15-tpi-210.md", r"travel ([\d.]+) deg", C["P34_CENTANG_DEG"]),
    ("drift gauge range, nm (GAUGE_RANGE_M)", "3-17-braking.md", r"shows within (\d+) nm", C["GAUGE_RANGE_M"] / 1852),
    ("the same on the panel page (GAUGE_RANGE_M)", "1-2-panel.md", r"CSM within (\d+) nm", C["GAUGE_RANGE_M"] / 1852),
    ("drift gauge angle limit, deg (GAUGE_AXIS_DEG)", "1-2-panel.md", r"more than (\d+) deg off the CSM", C["GAUGE_AXIS_DEG"]),
    ("drift gauge high scale, mrad/s (GAUGE_HI_MRAD)", "3-17-braking.md", r"(\d+) mrad/s at first", C["GAUGE_HI_MRAD"]),
    ("drift gauge low scale, mrad/s (GAUGE_LO_MRAD)", "3-17-braking.md", r"(\d+) mrad/s when the needles", C["GAUGE_LO_MRAD"]),
    ("docking message range, ft (DOCK_RANGE_M)", "3-17-braking.md", r"within (\d+) ft at under", round(C["DOCK_RANGE_M"] / FT)),
    ("docking message speed, ft/s (DOCK_SPEED_MS)", "3-17-braking.md", r"at under ([\d.]+) ft/s", round(C["DOCK_SPEED_MS"] / FT, 2)),
    ("physics warp warning range, ft (WARP_NEAR_M)", "3-17-braking.md", r"physics warp within (\d+) ft", round(C["WARP_NEAR_M"] / FT)),
    ("docking message armed beyond, ft (DOCK_ARM_M)", "3-17-braking.md", r"has been over (\d+) ft", round(C["DOCK_ARM_M"] / FT)),
    ("P35's TIG ahead, min (RNDZ_MID_LEAD_S)", "3-16-midcourse.md", r"set (\d+) minutes ahead", C["RNDZ_MID_LEAD_S"] / 60),
    ("P20 asks beyond this angle, deg (TRK_NEAR_DEG)", "3-18-tracking.md", r"More than (\d+) deg off", C["TRK_NEAR_DEG"]),
    ("time between marks, s (TRK_MARK_S)", "3-18-tracking.md", r"one every (\d+) s", C["TRK_MARK_S"]),
    ("largest angle for a mark, deg (TRK_MARK_DEG)", "3-18-tracking.md", r"within (\d+) deg of the front windows", C["TRK_MARK_DEG"]),
    ("P20 range limit, nm (TRK_RANGE_M)", "3-18-tracking.md", r"within (\d+) nm", C["TRK_RANGE_M"] / 1852),
    ("time between looks at the CSM, s (TRK_PASS_S)", "3-18-tracking.md", r"looks every (\d+) s", C["TRK_PASS_S"]),
    ("range recheck, 210, s (TRK_RECHECK_S)", "3-18-tracking.md", r"by itself every (\d+) s", C["TRK_RECHECK_S"]),
    ("P42 ullage before TIG, J, s (APS_ULLAGE_ON_J)", "3-3-p40.md", r"Ullage (\d+) s before TIG", -C["APS_ULLAGE_ON_J"]),
    ("P42 ullage before TIG, A11, s (APS_ULLAGE_ON_A11)", "3-3-p40.md", r"\[A11\] n: Ullage ([\d.]+) s", -C["APS_ULLAGE_ON_A11"]),
    ("P42 ullage on the 210 TPI page, s (APS_ULLAGE_ON_J)", "3-15-tpi-210.md", r"Ullage (\d+) s before TIG", -C["APS_ULLAGE_ON_J"]),
]
for what, fname, pattern, want in NUMBERS:
    checked += 1
    m = re.search(pattern, METRIC.sub("", PAGES.get(fname, "")), re.I)   # checklist lines are written in sentence case but printed in capitals
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

# ---- 4. page links, and checklists that assume a craft ready to fly ------------------------------------------------------
PAGE_IDS = {name: re.search(r"^page:\s*(\S+)", text, re.M).group(1) for name, text in PAGES.items()}
for name, text in PAGES.items():
    for target in re.findall(r"\{@([^\s}]*)", text):
        checked += 1
        if target not in PAGE_IDS.values():
            fail(f"links: {name} links to page {target}, which no page has")
SETTING_WORDS = ("agc_config", "_SIGN", "boot/", "skip simulated")
for name, text in PAGES.items():
    if PAGE_IDS[name].startswith("3-") or PAGE_IDS[name] in ("0-2", "0-3", "0-4", "0-5"):
        for word in SETTING_WORDS:
            checked += 1
            if word.lower() in text.lower():
                fail(f"checklists: {name} mentions a setting ({word}); settings belong on the reference pages")
        checked += 1
        if re.search(r"^> (NOTE|CAUTION): J-class", text, re.M):
            fail(f"checklists: {name} puts J-class changes in a note; write them at their steps, tagged [A11] and [J]")

# ---- 5. order of keys and warnings that a pilot following the checklists depends on ----------------------------------------
def must(ok, msg):
    global checked
    checked += 1
    if not ok:
        fail("checklists: " + msg)


doi = PAGES.get("3-5-doi.md", "")
before_p63 = doi.split("V37E 63E")[0]
must("Target the CSM" in before_p63, "3-5-doi.md keys P63 before it says to target the CSM (P63 takes the CSM at its start)")
must(re.search(r"^\[J\] .*V25 N69 E", before_p63, re.M), "3-5-doi.md keys P63 before the J site correction (N69 is added at P63 start)")
landing = PAGES.get("3-8-landing.md", "")
automatic = landing.split("band: RATE OF DESCENT")[0]
must(re.search(r"^\[J\] n: .*PRO.*V32E", automatic, re.M), "3-8-landing.md: the J warning against PRO and V32E is not in the automatic landing band")
must(re.search(r"^\[J\] n: .*PRO.*V32E", PAGES.get("0-2-landing-card.md", ""), re.M), "0-2-landing-card.md lacks the J warning against PRO and V32E")
must("Rate kept" not in landing, "3-8-landing.md says the rate is kept when SAS goes off: P65 resumes its own rate")
# the rendezvous is split by software version (the user, 2026-11-26): each version reads its own pages, so 3.12 to 3.15 carry no tags
for name, text in PAGES.items():
    if PAGE_IDS[name] in ("3-12", "3-13", "3-14", "3-15"):
        must(not re.search(r"\[(A11|J)\]", text), f"{name} has a version tag: that page is for one version only")
    # an optional section says first what is lost by skipping it
    for after in re.findall(r"^band: [^\n]*\| *optional *\n([^\n]*)", text, re.M):
        must(after.startswith("n:"), f"{name}: an optional bar is not followed by an n: line saying what is lost")

# a pilot reading straight down is told where the versions part (the user, 2026-11-26)
csi = PAGES.get("3-12-csi.md", "")
split = re.search(r"```fork\n(.*?)```", csi, re.S)
must(split and "{@3-15}" in split.group(1) and split.start() < csi.index("```checklist"), "3-12-csi.md has no fork box to 3.15 above its first step")
for name in ("3-11-ascent-flight.md", "0-3-ascent-card.md"):
    for tag, target in (("A11", "3-12"), ("J", "3-15")):
        must(re.search(rf"^\[{tag}\] - NEXT \|.* page \{{@{target}\}}", PAGES.get(name, ""), re.M), f"{name}: no [{tag}] NEXT step naming page {target}")
for tag, ver in (("A11", "099"), ("J", "210")):
    must(f"== [{tag}] Rendezvous: {ver}" in PAGES.get("3-0-index.md", ""), f"3-0-index.md: the {ver} group bar is not tagged [{tag}]")
must(re.search(r"^- \[J\] 210 burns \|", PAGES.get("1-1-overview.md", ""), re.M), "1-1-overview.md has no 210 burns row")

# the route marks come from make_pack.py's ROUTES table (read as text: this check needs no markdown package). Renumbering
# section 3 moves the pages under it, so it must still name each version's pages, all of them, and the page where they join
ROUTE = {node.targets[0].id: ast.literal_eval(node.value) for node in ast.parse((ROOT / "make_pack.py").read_text(encoding="utf-8")).body
         if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") in ("ROUTES", "ROUTE_END")}
for ver, stops in ROUTE["ROUTES"]:
    headed = [(PAGE_IDS[name], found.group(1)) for name, text in PAGES.items()
              if (found := re.search(rf"^## .*Rendezvous {ver}: (\w+)", text, re.M))]
    must(sorted(stops) == sorted(headed), f"make_pack.py ROUTES has {sorted(stops)} for {ver}; the pages headed 'Rendezvous {ver}:' are {sorted(headed)}")
end_page, end_name = ROUTE["ROUTE_END"]
must(any(PAGE_IDS[name] == end_page and re.search(rf"^## .*{end_name}", text, re.M | re.I) for name, text in PAGES.items()),
     f"make_pack.py ROUTE_END: page {end_page} is not headed {end_name}")

# the craft ships with the throttle switch on MAN (the user, 2026-11-26), and the checklists are written for it
must(C.get("ENG_THR_CONT") == "MAN", "the shipped ENG_THR_CONT is not MAN")
for name, text in PAGES.items():
    if PAGE_IDS[name].startswith("3-") or PAGE_IDS[name] in ("0-2", "0-3", "0-4", "0-5"):
        must(not re.search(r"\bMAN:|AUTO: a short|ENG THR CONT", text), f"{name} words a step for the throttle switch: write it for the shipped MAN")
must(re.search(r"^\[J\] n: Shorter than in 099", PAGES.get("3-7-p64.md", ""), re.M), "3-7-p64.md no longer says the J-class P64 is shorter")
must(re.search(r"rate-of-descent tap does nothing \| 099: check SAS is on", PAGES.get("4-1-trouble.md", "")),
     "4-1-trouble.md asks every version to check SAS for a rate-of-descent tap: J-class does not need it")

# a checklist reads straight down its page (the user, 2026-11-26): inside it, a link is only on a NEXT step, a goto: box or the abort box
for name, text in PAGES.items():
    if not PAGE_IDS[name].startswith("3-"):
        continue
    for block in re.findall(r"```checklist\n(.*?)```", text, re.S):
        for line in block.split("\n"):
            if "{@" in line:
                must(re.match(r"\s*(\[(A11|J)\] )?- NEXT \||\s*goto:|\s*abort:", line), f"{name} has a jump in the middle of a procedure: {line.strip()}")
for name, part in (("3-5-doi.md", "p30"), ("3-5-doi.md", "p40-ignition"), ("3-5-doi.md", "p40-cutoff"), ("3-12-csi.md", "p41"),
                   ("3-13-cdh.md", "p41"), ("3-14-tpi.md", "p41"), ("3-16-midcourse.md", "p41"),
                   ("3-6-p63.md", "abort"), ("3-7-p64.md", "abort"), ("3-8-landing.md", "abort"),
                   ("3-3-p40.md", "p42-start"), ("3-3-p40.md", "p42-burn"), ("3-15-tpi-210.md", "p42-start"), ("3-15-tpi-210.md", "p42-burn")):
    must(part in PARTS and PARTS[part] in PAGES.get(name, ""), f"{name} does not write out the {part} steps")

# every figure in ft, ft/s or nm on a checklist or flight card has its metric one in brackets (the user, 2026-11-27). Not a
# register's scale (0.1 ft/s), nor words quoted from the terminal
SI = {"ft": (0.3048, ("m", "km")), "ft/s": (0.3048, ("m/s",)), "nm": (1852.0, ("km",))}
for name, text in PAGES.items():
    if not (PAGE_IDS[name].startswith("3-") or PAGE_IDS[name] in ("0-2", "0-3", "0-4", "0-5")):
        continue
    for line in text.split("\n"):
        if "Terminal:" in line:
            continue
        for m in re.finditer(r"(?<![\d.,])(?:([\d,.]*\d) to )?([\d,.]*\d) (ft/s|ft|nm)\b(?!/)(?: \((?:([\d.]+) to )?([\d.]+) (m/s|km|m)\))?", line, re.I):
            low, high, unit, si_low, si_high, si_unit = m.groups()
            if high in ("0.1", "0.01"):
                continue
            scale, units = SI[unit.lower()]
            must(si_unit in units, f"{name}: '{m.group(0)}' has no metric figure in brackets ({' or '.join(units)})")
            if si_unit not in units:
                continue
            for apollo, si in ((low, si_low), (high, si_high)):
                if apollo is None:
                    continue
                want = float(apollo.replace(",", "")) * scale / (1000 if si_unit == "km" else 1)
                must(si is not None and abs(float(si) - want) <= 0.025 * want, f"{name}: '{m.group(0)}': {apollo} {unit} is {want:.2f} {si_unit}")

# ---- 6. the reference sections ---------------------------------------------------------------------------------------------------
# the shaded (key) rows of the noun tables are the nouns the flight cards name, so the emphasis cannot drift from the cards
CARD_NOUNS = {n for name, text in PAGES.items() if PAGE_IDS[name] in ("0-2", "0-3", "0-4", "0-5") for n in re.findall(r"\bN(\d\d)\b", text)}
NOUN_TEXT = "\n".join(text for name, text in PAGES.items() if PAGE_IDS[name] in ("2-2", "2-3"))
shaded = set(re.findall(r"^\| \*\*N(\d\d)", NOUN_TEXT, re.M))
rows = set(re.findall(r"^\| (?:\*\*)?N(\d\d)", NOUN_TEXT, re.M))
must(shaded == CARD_NOUNS & rows, f"noun tables: shaded {sorted(shaded)}, but the cards name {sorted(CARD_NOUNS & rows)}")
# in sections 1 and 2 the heading's number is the page's number
for name, text in PAGES.items():
    if PAGE_IDS[name][0] in "12":
        first = re.search(r"^## (\d\.\d+) ", text, re.M)
        must(first and first.group(1) == PAGE_IDS[name].replace("-", "."), f"{name}: page {PAGE_IDS[name]} is headed {first.group(1) if first else 'nothing'}")
        must(len(re.findall(r"^## ", text, re.M)) == 1, f"{name}: more than one numbered heading; use ### below the first")

print(f"check_pack: {checked} checks, {len(problems)} problem(s)")
for p in problems:
    print("  " + p)
sys.exit(1 if problems else 0)
