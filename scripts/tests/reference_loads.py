"""Reference model for release 1.3 (uplink and loads): expected words, ECADRs and keystrokes for the kOS pad tests.

kOS cannot run outside KSP, so the pad tests (test_store, test_load, test_p27, test_uplink, test_pad) carry literal expected
values produced here. `python scripts/tests/reference_loads.py` runs this file's own checks (exit 1 on a failure) and prints
the numbers the tests use; `python scripts/tests/reference_loads.py --print` prints only those.

Facts (checked against Luminary 099 UPDATE_PROGRAM.agc, PINBALL_NOUN_TABLES.agc, ERASABLE_ASSIGNMENTS.agc; see the spec's
"Research results"):
  ECADR = bank * 0o400 + (offset - 0o1400)     (E4,1422 is 2022 octal; UPSVFLAG E3,1501 is 1501 octal)
  V71 E II E AAAA E w1 E ... wN E V33 E        II = N + 2, octal, 3 <= II <= 20 decimal (UPDATE_PROGRAM: UP21 = 21 = max + 1)
  V72 E II E AAAA E w E ... V33 E              II = 2 * pairs + 1, odd, 3 <= II <= 19 decimal
  each word is 5 octal digits (a 15-bit word); a double-precision number is two words, the same sign in both, one's complement
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CELLS_FILE = HERE.parent / "lm" / "lm_cells.ks"
WORD_MASK = 0o77777


def ecadr(bank, offset):
    """ECADR of an erasable (bank 0 to 7, offset 768 to 1023 as a decimal number, i.e. octal 1400 to 1777)."""
    return bank * 256 + (offset - 768)


def load_cells():
    """{'099': {name: {...}}, '210': {...}} parsed from lm_cells.ks (the single source of the table)."""
    pat = re.compile(r'^LM_CELLS_(\d+):ADD\("(\w+)", LEXICON\("BANK", (\d+), "OFFSET", (\d+), "WORDS", (\d+), '
                     r'"SCALE", (\d+), "LABEL", "([^"]*)"\)\)\.', re.M)
    out = {}
    for ver, name, bank, off, words, scale, label in pat.findall(CELLS_FILE.read_text(encoding="utf-8")):
        out.setdefault(ver, {})[name] = dict(BANK=int(bank), OFFSET=int(off), WORDS=int(words), SCALE=int(scale), LABEL=label)
    return out


LM_CELLS = load_cells()


def dp_encode(value, scale_exp):
    """Double-precision word pair [hi, lo] for value at full scale 2**scale_exp (28 bits of magnitude, rounded)."""
    frac = abs(value) / 2.0 ** scale_exp
    mag = min(int(frac * 2 ** 28 + 0.5), 2 ** 28 - 1)
    hi, lo = mag >> 14, mag & 0x3FFF
    if value < 0 and mag > 0:
        hi, lo = WORD_MASK - hi, WORD_MASK - lo          # one's complement: the sign is in both words
    return [hi, lo]


def _signed(word):
    return -(WORD_MASK - word) if word >= 0o40000 else word


def dp_decode(words, scale_exp):
    """Inverse of dp_encode. A sign disagreement between the words adds up as signed numbers (what the AGC's DP add does)."""
    return (_signed(words[0]) * 16384 + _signed(words[1])) / 2.0 ** 28 * 2.0 ** scale_exp


def octal_text(n, width):
    text = format(n, "o")
    return text.rjust(width, "0")


def octal_parse(text):
    """Integer from octal digits, or -1 for empty text or any digit that is not 0 to 7."""
    if text == "" or any(c not in "01234567" for c in text):
        return -1
    return int(text, 8)


def keys_of(text):
    return list(text)


def v71_keys(ecadr_value, words):
    """The key names (one per key press) of a V71 block update ending in V33 E."""
    k = keys_of("V71") + ["E"] + keys_of(octal_text(len(words) + 2, 2)) + ["E"] + keys_of(octal_text(ecadr_value, 4)) + ["E"]
    for w in words:
        k += keys_of(octal_text(w, 5)) + ["E"]
    return k + keys_of("V33") + ["E"]


def v72_keys(pairs):
    """V72 scatter update: pairs is a list of (ecadr, word)."""
    k = keys_of("V72") + ["E"] + keys_of(octal_text(2 * len(pairs) + 1, 2)) + ["E"]
    for a, w in pairs:
        k += keys_of(octal_text(a, 4)) + ["E"] + keys_of(octal_text(w, 5)) + ["E"]
    return k + keys_of("V33") + ["E"]


# ---- Moon-fixed site vector (our frame: x through lat 0 lng 0, y through lat 0 lng 90 E, z north) ------------------------
import math


def site_to_rls(lat, lng, alt, radius):
    r = radius + alt
    la, lo = math.radians(lat), math.radians(lng)
    return [r * math.cos(la) * math.cos(lo), r * math.cos(la) * math.sin(lo), r * math.sin(la)]


def rls_to_site(vec, radius):
    r = math.sqrt(sum(c * c for c in vec))
    return dict(LAT=math.degrees(math.asin(vec[2] / r)), LNG=math.degrees(math.atan2(vec[1], vec[0])), ALT=r - radius)


def rls_words(vec, profile_ver="099"):
    scale = LM_CELLS[profile_ver]["RLS"]["SCALE"]
    out = []
    for c in vec:
        out += dp_encode(c, scale)
    return out


# ---- times: AGC clock in centiseconds from the clock zero -------------------------------------------------------------------
CLOCK_LIMIT_CS = 2 ** 28


def ut_to_cs(ut, clock_zero_ut):
    cs = round((ut - clock_zero_ut) * 100)
    return -1 if cs < 0 or cs >= CLOCK_LIMIT_CS else cs


def hms_cs(seconds):
    """N33 integers for a time (seconds since the clock zero): hours, minutes, seconds in hundredths."""
    cs = round(seconds * 100)
    return [cs // 360000, (cs // 6000) % 60, cs % 6000]


def signed5(n):
    return ("-" if n < 0 else "+") + "%05d" % abs(n)


def number_text(value, decimals):
    """A number rounded and printed without trailing zeros, as kOS prints ROUND(value, decimals): 0.674, 23.5, -4."""
    text = ("%." + str(decimals) + "f") % value
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def clock_text(seconds):
    """H:MM:SS.CC, like pad_clock_text in lm_pad.ks."""
    h, m, cs = hms_cs(seconds)
    return "%d:%02d:%02d.%02d" % (h, m, cs // 100, cs % 100)


def block_line(ecadr_value, words):
    """The keys of one V71 block as one PAD line (pad_block_line in lm_pad.ks): V71 E, count E, ECADR E, the words each followed by E,
    and V33 E."""
    return ("  V71 E " + octal_text(len(words) + 2, 2) + " E " + octal_text(ecadr_value, 4) + " E "
            + "".join(" " + octal_text(word, 5) + " E" for word in words) + "  V33 E")


def pad_lines(profile_ver, site, rls_vec, tland_ut, burns, clock_zero_ut, plane_change=False):
    """The PAD text for a plan. site is (lat, lng, alt). burns is a list holding the DOI burn as (label, tig_ut, dv_lv_m_per_s), dv in
    local vertical axes as a list of 3 numbers (x along track, y opposite the normal, z down). The DOI burn is uplinked as one 8-word
    V71 block (DELVLVC six words, then TIG two words: the GSOP external delta-V update, see
    docs/superpowers/ground-uplinks-research.md). A plane change (plane_change True) is the CSM's burn: it is not loaded in the LM
    and the PAD only adds a note. Returns a list of text lines (pad_build in lm_pad.ks must match exactly)."""
    cells = LM_CELLS[profile_ver]
    lines = ["PAD " + ("LUMINARY210" if profile_ver == "210" else "LUMINARY099") + "     CLOCK ZERO UT " + str(round(clock_zero_ut)),
             "UPLINK in P00, one block at a time (V34 E abandons a block)", ""]
    rls_e = ecadr(cells["RLS"]["BANK"], cells["RLS"]["OFFSET"])
    w = rls_words(rls_vec, profile_ver)
    lines.append("LANDING SITE (RLS)   address " + octal_text(rls_e, 4))
    lines.append("  lat " + number_text(site[0], 3) + "  long " + number_text(site[1], 3) + "  height " + str(round(site[2])) + " m")
    lines.append(block_line(rls_e, w))
    lines.append("")
    cs = ut_to_cs(tland_ut, clock_zero_ut)
    t_e = ecadr(cells["TLAND"]["BANK"], cells["TLAND"]["OFFSET"])
    tw = dp_encode(cs, cells["TLAND"]["SCALE"])
    lines.append("LANDING TIME (TLAND)   address " + octal_text(t_e, 4))
    lines.append("  " + str(cs) + " cs = " + clock_text(cs / 100.0) + " after the clock zero")
    lines.append(block_line(t_e, tw))
    lines.append("")
    label, tig_ut, dv = burns[0]
    t = hms_cs(tig_ut - clock_zero_ut)
    dvi = [round(c / 0.3048 * 10) for c in dv]
    bw = []
    for c in dv:
        bw += dp_encode(c / 100, cells["DELVLVC"]["SCALE"])
    bw += dp_encode(round((tig_ut - clock_zero_ut) * 100), cells["TIG"]["SCALE"])
    b_e = ecadr(cells["DELVLVC"]["BANK"], cells["DELVLVC"]["OFFSET"])
    lines.append(label + " BURN   address " + octal_text(b_e, 4))
    lines.append("  TIG  " + clock_text(tig_ut - clock_zero_ut) + "   N33 " + " ".join(signed5(n) for n in t))
    lines.append("  DV   N81 " + " ".join(signed5(n) for n in dvi) + "   (tenths ft/s, local vertical X Y Z)")
    lines.append(block_line(b_e, bw))
    if plane_change:
        lines.append("")
        lines.append("PC: a CSM burn, flown from its node; not loaded in the LM")
    return lines


# ---- self checks ----------------------------------------------------------------------------------------------------
FAILED = []


def check(name, cond):
    if not cond:
        FAILED.append(name)
        print("FAIL " + name)


def selftest():
    check("ecadr E4,1422 = 2022 octal", ecadr(4, 0o1422) == 0o2022)
    check("ecadr UPSVFLAG E3,1501 = 1501 octal", ecadr(3, 0o1501) == 0o1501)
    check("cells parsed", set(LM_CELLS) == {"099", "210"} and len(LM_CELLS["099"]) == 7)
    check("099 RLS ecadr 2022", ecadr(LM_CELLS["099"]["RLS"]["BANK"], LM_CELLS["099"]["RLS"]["OFFSET"]) == 0o2022)
    check("210 RLS ecadr 2020", ecadr(LM_CELLS["210"]["RLS"]["BANK"], LM_CELLS["210"]["RLS"]["OFFSET"]) == 0o2020)
    check("099 TLAND ecadr 2400", ecadr(5, 768) == 0o2400)
    # GSOP R-567 section 2 rev 12, 2.1.6 "Absolute Addresses for UPDATE Program" (revision 210 listing, read from the scanned page): RLS 02020, DELVSLV 03433
    c210 = LM_CELLS["210"]
    check("210 DELVLVC (DELVSLV) ecadr 3433 as in the GSOP table", ecadr(c210["DELVLVC"]["BANK"], c210["DELVLVC"]["OFFSET"]) == 0o3433)
    check("210 TLAND follows RLS by six words", ecadr(c210["TLAND"]["BANK"], c210["TLAND"]["OFFSET"]) == 0o2020 + 6)
    # the ascent loads (release 1.5), addresses from the assembled ERASABLE_ASSIGNMENTS listings
    for ver, zd, rd, xr in (("099", 0o2276, 0o2272, 0o3642), ("210", 0o2267, 0o2263, 0o3642)):
        c = LM_CELLS[ver]
        for name, want in (("ZDOTD", zd), ("RDOTD", rd), ("XRANGE", xr)):
            check("%s %s ecadr %o" % (ver, name, want),
                  name in c and ecadr(c[name]["BANK"], c[name]["OFFSET"]) == want)
    check("octal_parse", octal_parse("12345") == 5349 and octal_parse("1289") == -1 and octal_parse("") == -1)
    # the worked state-vector example of UPDATE_PROGRAM.agc: V71 E 21 E <ecadr> E ... (21 octal = 17 = 15 words + 2)
    check("count for 15 words is 21 octal", octal_text(15 + 2, 2) == "21")
    check("count for refsmmat 18 words is 24 octal", octal_text(18 + 2, 2) == "24")
    k = "".join(v71_keys(0o1501, [1, 2]))
    check("v71 keys shape", k == "V71E04E1501E00001E00002EV33E")
    check("v72 keys shape", "".join(v72_keys([(0o2022, 5)])) == "V72E03E2022E00005EV33E")
    for x, e in [(0, 27), (-1.5, 27), (1737400.0, 27), (-1737400.25, 27), (400000 * 100, 28), (-0.0123, 7)]:
        back = dp_decode(dp_encode(x, e), e)
        check("dp round trip %s e=%d" % (x, e), abs(back - x) <= 2.0 ** e / 2 ** 28)
    check("dp positive words are below 040000", all(w < 0o40000 for w in dp_encode(1737400.0, 27)))
    check("dp negative words are one's complement", all(w >= 0o40000 for w in dp_encode(-1737400.0, 27)))
    for lat, lng, alt in [(0.674, 23.473, -1930.0), (-3.0, 345.0, 1500.0)]:
        v = site_to_rls(lat, lng, alt, 1737400.0)
        back = rls_to_site([dp_decode(rls_words(v)[i:i + 2], 27) for i in (0, 2, 4)], 1737400.0)
        check("site round trip %s" % lat, abs(back["LAT"] - lat) < 0.001 and abs((back["LNG"] - lng + 180) % 360 - 180) < 0.001
              and abs(back["ALT"] - alt) < 1.0)
    check("ut_to_cs negative", ut_to_cs(-5, 0) == -1)
    check("ut_to_cs limit", ut_to_cs(2 ** 28 / 100.0, 0) == -1 and ut_to_cs(2 ** 28 / 100.0 - 1, 0) > 0)
    check("hms_cs", hms_cs(3 * 3600 + 25 * 60 + 12.34) == [3, 25, 1234])
    lines = pad_lines("099", (0.674, 23.473, -1930.0), site_to_rls(0.674, 23.473, -1930.0, 1737400.0), 400000.0, [("DOI", 399000.0, [-30.0, 0.0, 0.0])], 100000.0)
    check("pad has the header and the burn uplink block", lines[0].startswith("PAD LUMINARY099") and "DOI BURN   address 3433" in lines)
    check("a plan with no plane change has no PC note and no KEYED section", len(lines) == 15 and "KEYED (P00)" not in lines)
    check("DELVLVC and TIG are contiguous in both versions", all(
        LM_CELLS[v]["DELVLVC"]["BANK"] == LM_CELLS[v]["TIG"]["BANK"] and LM_CELLS[v]["DELVLVC"]["OFFSET"] + 6 == LM_CELLS[v]["TIG"]["OFFSET"]
        for v in ("099", "210")))
    two = pad_lines("099", (0.674, 23.473, -1930.0), site_to_rls(0.674, 23.473, -1930.0, 1737400.0), 400000.0,
                    [("DOI", 399000.0, [-30.0, 0.0, 0.0])], 100000.0, plane_change=True)
    check("with a plane change the PAD is the same plus the CSM note", two[:15] == lines and len(two) == 17
          and two[16] == "PC: a CSM burn, flown from its node; not loaded in the LM")
    check("pad TLAND is 30000000 cs", "  30000000 cs = 83:20:00.00 after the clock zero" in lines)
    return len(FAILED) == 0


def numbers_for_tests():
    """Print the literal numbers the pad tests use."""
    print("099 RLS ecadr octal", octal_text(ecadr(4, 786), 4), " 210 RLS", octal_text(ecadr(4, 784), 4))
    print("rls words (0.674, 23.473, -1930, r 1737400):", [octal_text(w, 5) for w in rls_words(site_to_rls(0.674, 23.473, -1930.0, 1737400.0))])
    print("v71 two words to 1501:", "".join(v71_keys(0o1501, [1, 2])))
    print("v72 one pair:", "".join(v72_keys([(0o2022, 5)])))
    print("octal_parse('12345') =", octal_parse("12345"))
    print("\n".join(pad_lines("099", (0.674, 23.473, -1930.0), site_to_rls(0.674, 23.473, -1930.0, 1737400.0), 400000.0, [("DOI", 399000.0, [-30.0, 0.0, 0.0])], 100000.0)))


if __name__ == "__main__":
    ok = selftest()
    if "--print" in sys.argv or ok:
        numbers_for_tests()
    print("reference_loads: " + ("all checks passed" if ok else "FAILED: " + ", ".join(FAILED)))
    sys.exit(0 if ok else 1)
