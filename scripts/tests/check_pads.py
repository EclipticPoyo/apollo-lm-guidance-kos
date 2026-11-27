"""check_pads.py: offline checks on the PAD forms page (docs/pads.html).  Run: python scripts/tests/check_pads.py

Reads the card data (the JSON block in the page) and checks the cards against the Apollo 11 Final Flight Plan pages they
recreate, the block format, that nothing is fetched, that every noun the planner writes on a PAD has a row to go on,
and that the page is delivered (site, zip, public repo) and linked to.
Exit code 0 when everything passes, 1 otherwise.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "pads.html"
PLANNER = ROOT / "scripts" / "lm" / "planner"
CREDIT = "https://www.nasa.gov/wp-content/uploads/static/apollo50th/pdf/a11final-fltpln.pdf"

PUBLIC = "https://eclipticpoyo.github.io/apollo-lm-guidance-kos/pads.html"

# id, page of the source PDF, shape: flight order
CARDS = [("p27", 70, "portrait"), ("p30", 76, "portrait"), ("doi", 78, "landscape"), ("pdi", 80, "landscape"),
         ("surface", 84, "landscape"), ("ascent", 86, "portrait"), ("csi", 88, "landscape"), ("cdh", 90, "landscape"),
         ("tpi", 92, "landscape")]
SIZE = {"portrait": (190, 277), "landscape": (277, 190)}
# the cards each planner noun must have a row on (design spec, "Where the planner's figures go")
NOUN_CARDS = {33: ["doi", "ascent"], 81: ["doi"], 76: ["ascent"], 11: ["csi"], 37: ["csi", "tpi"], 43: ["p27"]}
NEEDS = {"reg": ("cols", "cell_w", "row_h", "label_w", "label_side", "rows"), "line": ("w",), "area": ("w", "h"),
         "text": ("text",), "shade": ("w", "h")}
WORD = re.compile(r"^(.+)\*(\d+)[.:]?$")
CELL = re.compile(r"^[_ost+0X][.:]?$")

count = 0
problems = []


def check(ok, what):
    global count
    count += 1
    if not ok:
        problems.append(what)
    return ok


def pattern_cells(pattern):
    """Grid cells a row pattern covers, or None if a token is not valid."""
    n = 0
    for token in pattern.split():
        word = WORD.match(token)
        if word:
            n += int(word.group(2))
        elif CELL.match(token):
            n += 1
        else:
            return None
    return n


def row_patterns(block, row):
    cells = row.get("cells")
    return list(cells) if isinstance(cells, list) else [cells] * block["cols"]


def check_block(card, block):
    """Format and size of one block; returns its (width, height) in mm, or None if it is malformed."""
    where = f"{card['id']}.{block.get('id')}"
    kind = block.get("type")
    if not check(kind in NEEDS, f"{where}: unknown block type {kind!r}"):
        return None
    missing = [k for k in ("id", "x", "y") + NEEDS[kind] if k not in block]
    if not check(not missing, f"{where}: missing {', '.join(missing)}"):
        return None
    if kind != "reg":
        height = block.get("h", 6 if kind == "line" else 0)
        return block.get("w", 0), height
    check(block["label_side"] in ("left", "right"), f"{where}: label_side {block['label_side']!r}")
    counts = set()
    for i, row in enumerate(block["rows"]):
        patterns = row_patterns(block, row)
        check(len(patterns) == block["cols"], f"{where} row {i}: {len(patterns)} patterns for {block['cols']} columns")
        check(isinstance(row.get("label"), list), f"{where} row {i}: label is not a list")
        for p in patterns:
            n = pattern_cells(p) if isinstance(p, str) else None
            if check(bool(n), f"{where} row {i}: bad pattern {p!r}"):
                counts.add(n)
    if not check(len(counts) == 1, f"{where}: rows have differing cell counts {sorted(counts)}"):
        return None
    width = block["label_w"] + block["cols"] * counts.pop() * block["cell_w"]
    height = block["row_h"] * len(block["rows"])
    if block.get("title"):
        height += block.get("title_h", block["row_h"])
    return width, height


def printed_texts(card):
    """Everything the card prints."""
    yield card.get("title", "")
    for block in card["blocks"]:
        for key in ("text", "label", "title"):
            if isinstance(block.get(key), str):
                yield block[key]
        for row in block.get("rows", []):
            yield " ".join(row.get("label", []))
            for p in row_patterns(block, row):
                for token in str(p).split():
                    if WORD.match(token):
                        yield WORD.match(token).group(1)


def noun_rows(card, noun):
    """(block, row) for every row of the card marked with this noun."""
    return [(b, r) for b in card["blocks"] for r in b.get("rows", []) if r.get("noun") == noun] + \
        [(b, None) for b in card["blocks"] if b.get("noun") == noun]


def planner_nouns():
    ascent = (PLANNER / "lm_ascent_plan.ks").read_text(encoding="utf-8")
    burns = (PLANNER / "lm_pad.ks").read_text(encoding="utf-8")
    found = re.findall(r"asc_pad_key\((\d+)", ascent) + re.findall(r"V25 N(\d+)", ascent) + \
        re.findall(r"N(33|81) ", burns)
    return {int(n) for n in found}


def check_cards(cards):
    ids = [c.get("id") for c in cards]
    order = [c[0] for c in CARDS]
    check(ids == order, f"the cards are {ids}, expected all nine in flight order")
    known = {c[0]: (c[1], c[2]) for c in CARDS}
    for card in cards:
        cid = card.get("id")
        if cid not in known:
            continue
        page, shape = known[cid]
        check((card.get("page"), card.get("shape")) == (page, shape),
              f"{cid}: page {card.get('page')} {card.get('shape')}, expected {page} {shape}")
        check(bool(card.get("title")), f"{cid}: no title")
        seen = [b.get("id") for b in card["blocks"]]
        check(len(seen) == len(set(seen)), f"{cid}: block ids repeat")
        wide, high = SIZE[shape]
        for block in card["blocks"]:
            size = check_block(card, block)
            if size:
                inside = block["x"] >= 0 and block["y"] >= 0 and block["x"] + size[0] <= wide + 0.01 \
                    and block["y"] + size[1] <= high + 0.01
                check(inside, f"{cid}.{block['id']}: reaches outside the {wide} x {high} mm card "
                              f"(to {block['x'] + size[0]:.1f}, {block['y'] + size[1]:.1f})")
        for text in printed_texts(card):
            check(not re.search(r"\([+-]?\d[\d.:]*\)", text), f"{cid}: an Apollo 11 value is printed: {text!r}")
            check(not re.search(r"\b\d{3}\+\d", text), f"{cid}: a backup computer address is printed: {text!r}")


def reg_block(card, block_id):
    return next((b for b in card["blocks"] if b["id"] == block_id and b["type"] == "reg"), None)


def check_nouns(card, *nouns):
    for noun in nouns:
        check(bool(noun_rows(card, noun)), f"{card['id']}: no row marked {noun}")


def check_titles(card, *titles):
    for title in titles:
        check(any(b["type"] == "reg" and b.get("title") == title for b in card["blocks"]),
              f"{card['id']}: no register block titled {title!r}")


def check_card_rows(by_id):
    """What particular cards must carry."""
    if "p27" in by_id:
        data = reg_block(by_id["p27"], "data")
        if check(bool(data) and data["cols"] == 3, "p27: no three-column register block 'data'"):
            labels = [r["label"][-1] for r in data["rows"]]
            check(labels == "01 02 03 04 05 06 07 10 11 12 13 14 15 16 17 20 21 22 23 24".split(),
                  f"p27: the data rows are numbered {labels}")
            check(row_patterns(data, data["rows"][0])[0].startswith("INDEX*3"), "p27: row 01 does not start with INDEX")
            check(all(row_patterns(data, r) == ["o o o o o"] * 3 for r in data["rows"][1:]),
                  "p27: rows 02 to 24 are not five octal boxes in each column")
        check_nouns(by_id["p27"], "N34", "N43")
    if "ascent" in by_id:
        check_nouns(by_id["ascent"], "N33", "N76")
    if "doi" in by_id:
        check_nouns(by_id["doi"], "N33", "N81", "N42", "N86", "N85")
    if "pdi" in by_id:
        check_titles(by_id["pdi"], "PDI PAD", "PDI ABORT < 10 MIN", "PDI ABORT > 10 MIN", "NO PDI +12 ABORT")
    if "surface" in by_id:
        check_titles(by_id["surface"], "T 2 ABORT", "T 3 ABORT")
        check_nouns(by_id["surface"], "N43", "N74", "N76")
    if "cdh" in by_id:
        check_nouns(by_id["cdh"], "N13")
    if "tpi" in by_id:
        check_nouns(by_id["tpi"], "N37", "N81", "N54", "N58", "N59")
    if "p30" in by_id:
        rows = noun_rows(by_id["p30"], "N33")
        got = [row_patterns(b, r) for b, r in rows if r]
        want = [[p] * 2 for p in ("+ 0 0 _ _ _", "+ 0 0 0 _ _", "+ 0 _ _. _ _")]
        check(got == want, f"p30: the N33 rows are {got}")


def check_planner(by_id):
    nouns = planner_nouns()
    check({11, 33, 37, 76, 81} <= nouns, f"the planner's PAD nouns were not found in its source: {sorted(nouns)}")
    for noun in sorted(nouns | set(NOUN_CARDS)):
        if not check(noun in NOUN_CARDS, f"the planner writes N{noun} on a PAD and no card is listed for it"):
            continue
        for cid in NOUN_CARDS[noun]:
            check(cid in by_id and bool(noun_rows(by_id[cid], f"N{noun:02d}")),
                  f"{cid}: no row for the planner's N{noun}")


def check_file(page):
    links = re.findall(r"<link\b[^>]*>", page)                   # the tab icon only, held in the page itself
    check(len(links) == 1 and links[0].startswith('<link rel="icon" href="data:image/svg+xml,'),
          f"<link> elements other than the one built-in tab icon: {[a[:60] for a in links]}")
    check(not re.search(r"<script[^>]*\ssrc\s*=", page), "the page loads a script file")
    check("url(http" not in page, "the page's styles fetch an address")
    outside = [a for a in re.findall(r"""\b(?:src|href)\s*=\s*["']([^"']*)["']""", page)
               if re.match(r"(?:[a-z]+:)?//", a)]
    manual = PUBLIC.replace("pads.html", "")                     # the way back to the manual, above the cards
    check(outside == [manual, CREDIT], f"outside addresses other than the manual and the one credit link: {outside}")
    foot = re.search(r"<footer[^>]*>(.*?)</footer>", page, re.S)
    text = " ".join(re.sub(r"<[^>]+>", " ", foot.group(1)).split()) if foot else ""
    check("Apollo 11 Final Flight Plan" in text, "the foot line does not name the Apollo 11 Final Flight Plan")


def colour_rules(css, selector):
    """The colour variables of every rule with exactly this selector."""
    found = re.findall(r"(?:^|\}|\{)\s*" + re.escape(selector) + r"\s*\{([^}]*)\}", css, re.M)
    return [dict(re.findall(r"(--[a-z]+)\s*:\s*(#[0-9A-Fa-f]+)", body)) for body in found]


def check_colours(page):
    """The page wears the manual's colours: pack.css's own variables, light and dark, and no other fixed colour."""
    pack = re.sub(r"/\*.*?\*/", "", (ROOT / "docs" / "pack" / "pack.css").read_text(encoding="utf-8"), flags=re.S)
    style = re.sub(r"/\*.*?\*/", "", "".join(re.findall(r"<style>(.*?)</style>", page, re.S)), flags=re.S)
    light, dark = (colour_rules(pack, s) for s in (":root", ":root[data-theme=dark]"))
    light = [d for d in light if d]
    check(bool(light) and bool(dark), "pack.css: the colour variables were not found")
    if not (light and dark):
        return
    for selector, want in ((":root", light[0]), (":root[data-theme=dark]", dark[0]),
                           (":root, :root[data-theme=dark]", light[0])):
        got = [d for d in colour_rules(style, selector) if d]
        check(got == [want], f"the page's colours under '{selector}' are not the manual's: {got}")
    rest = re.sub(r":root[^{}]*\{[^}]*\}", "", style)
    fixed = re.findall(r"#[0-9a-fA-F]{3,6}", rest)
    check(not fixed, f"colours that do not follow the theme: {fixed}")


# What short cards hide (designs 2026-11-27-pad-short-cards-design.md and 2026-11-27-pad-sources.md): register blocks,
# and blanks by the start of their id
HIDDEN = {"p27": ("n34", ""), "p30": ("bt fdai n86 bss", ""), "doi": ("bt fdai n86 bss ags", "lr_ rr_ p52_"),
          "pdi": ("fdai deda early phasing late_tpi n33 n81 n42 bt inertial n86 n11 n37", "sun_"),
          "surface": ("t2_tig phasing csi tpi period pdt", ""), "ascent": ("deda", ""),
          "csi": ("pitch deda n86 ags", "p52_ ags_ ags371_ csm_"),
          "cdh": ("fdai deda n86 ags pc_ags", "ags_ csm_ ydot1_ ydot3_"), "tpi": ("n42 fdai bt ags", "ags_ csm_")}
# Where figures come from (2026-11-27-pad-sources.md): P the planner, D the DSKY. Marked registers, then the loose
# marks beside the headings of blanks.
MARKS = {"p27": ({"data": "P", "n43": "P"}, []), "p30": ({"n33": "P", "n81": "P", "n42": "D"}, []),
         "doi": ({"n33": "P", "n81": "P", "n42": "D", "n85": "D"}, []), "pdi": ({"tgo": "D"}, []),
         "surface": ({}, ["D"] * 5), "ascent": ({"tig": "P", "n76": "P"}, ["P"]),
         "csi": ({"n11": "P", "n37": "P", "n81": "D", "n85": "D"}, ["D"] * 5),
         "cdh": ({"n13": "D", "n81": "D", "n85": "D", "pc_n85": "D"}, ["D"] * 4),
         "tpi": ({"n37": "P", "n81": "D", "n54": "D", "n59": "D 099", "n85": "D"}, ["D", "D", "D", "D 099"])}
CARD_LINES = {"3-2-p30": "P30 LM Maneuver", "3-5-doi": "DOI", "3-6-p63": "PDI", "3-8-landing": "Lunar Surface",
              "3-10-ascent": "LM Ascent PAD", "3-12-csi": "CSI", "3-13-cdh": "CDH", "3-14-tpi": "TPI",
              "3-15-tpi-210": "TPI", "3-16-midcourse": "TPI"}


def check_short(by_id):
    for cid, card in by_id.items():
        regs, prefixes = (words.split() for words in HIDDEN.get(cid, ("", "")))
        for block in card["blocks"]:
            where, show = f"{cid}.{block['id']}", block.get("show")
            check(show in (None, "full", "short"), f"{where}: show {show!r}")
            check(show != "short" or block["type"] in ("text", "shade"),
                  f"{where}: a box only short cards have would lose what is typed in it")
            if block["type"] in ("line", "area"):
                wanted = any(block["id"].startswith(p) for p in prefixes)
                check((show == "full") == wanted,
                      f"{where}: hidden in short cards is {show == 'full'}, expected {wanted}")
        got = sorted(b["id"] for b in card["blocks"] if b["type"] == "reg" and b.get("show") == "full")
        check(got == sorted(regs), f"{cid}: register blocks hidden in short cards are {got}, expected {sorted(regs)}")


def check_marks(by_id):
    """P and D marks, the line above each card, and the card's name in the checklist that uses it."""
    for cid, card in by_id.items():
        regs, loose = MARKS.get(cid, ({}, []))
        got = {}
        for block in card["blocks"]:
            marks = {r["mark"] for r in block.get("rows", []) if "mark" in r}
            if marks:
                check(block.get("show") != "full", f"{cid}.{block['id']}: marked, but short cards hide it")
                check(len(marks) == 1 and all("mark" in r for r in block["rows"]),
                      f"{cid}.{block['id']}: rows marked {sorted(marks)}, not all alike")
                got[block["id"]] = sorted(marks)[0]
        check(got == regs, f"{cid}: marked registers are {got}, expected {regs}")
        badges = [b for b in card["blocks"] if b.get("badge")]
        check(sorted(b.get("text") for b in badges) == sorted(loose),
              f"{cid}: loose marks are {[b.get('text') for b in badges]}, expected {loose}")
        check(all(b.get("show") == "short" for b in badges), f"{cid}: a loose mark shows on the full card")
        note = card.get("note", "")
        pages = re.findall(r"\b(\d)\.(\d+)\b", note)
        check(note.startswith("When:") and bool(pages), f"{cid}: no line saying when, with a manual page: {note!r}")
        for section, number in pages:
            check(any((ROOT / "docs" / "pack").glob(f"{section}-{number}-*.md")),
                  f"{cid}: the manual has no page {section}.{number}")
    for stem, name in CARD_LINES.items():
        text = (ROOT / "docs" / "pack" / f"{stem}.md").read_text(encoding="utf-8")
        check(f"CARD: {name}" in text, f"{stem}.md does not name its card (CARD: {name})")


def short_rect(block, moved=True):
    """(x0, y0, x1, y1) of a block, on the short card (moved) or where the full card has it."""
    if block["type"] == "reg":
        cells = block["rows"][0]["cells"]
        per = pattern_cells(cells[0] if isinstance(cells, list) else cells)
        w = block["label_w"] + block["cols"] * per * block["cell_w"]
        h = block["row_h"] * len(block["rows"]) + (block.get("title_h", block["row_h"]) if block.get("title") else 0)
    else:
        w, h = block.get("w", 0), block.get("h", 6 if block["type"] == "line" else 0)
    dx, dy = block.get("move", (0, 0)) if moved else (0, 0)
    return block["x"] + dx, block["y"] + dy, block["x"] + dx + w, block["y"] + dy + h


def overlap(a, b):
    return min(a[2], b[2]) - max(a[0], b[0]) > .3 and min(a[3], b[3]) - max(a[1], b[1]) > .3


def check_condensed(by_id):
    """Short cards close their gaps: smaller cards, everything on them, nothing slid on top of anything else."""
    for cid, card in by_id.items():
        full = SIZE[card["shape"]]
        size = card.get("short_size")
        if not check(isinstance(size, list) and len(size) == 2, f"{cid}: no short_size"):
            continue
        check(size[0] <= full[0] and size[1] < full[1] - 20, f"{cid}: the short card is not smaller: {size}")
        seen = [b for b in card["blocks"] if b.get("show") != "full"]
        for b in seen:
            r = short_rect(b)
            check(r[0] >= -.35 and r[1] >= -.35 and r[2] <= size[0] + .35 and r[3] <= size[1] + .35,
                  f"{cid}.{b['id']}: off the short card ({r[2]:.1f}, {r[3]:.1f} on {size[0]} x {size[1]})")
        content = [b for b in seen if b["type"] in ("reg", "line", "area") or
                   (b["type"] == "text" and b["text"] and not b.get("boxed"))]
        for i, a in enumerate(content):
            for b in content[i + 1:]:
                if (a.get("badge") and b["type"] == "text") or (b.get("badge") and a["type"] == "text"):
                    continue      # a mark sits close beside its heading, whose width here is only an estimate
                badge, other = (a, b) if a.get("badge") else (b, a)
                if badge.get("badge") and other["type"] == "area" and                         short_rect(badge)[3] <= short_rect(other)[1] + 8:
                    continue      # or beside a free space's label, above where one types
                if a.get("move", [0, 0]) != b.get("move", [0, 0]) and overlap(short_rect(a), short_rect(b)):
                    check(overlap(short_rect(a, False), short_rect(b, False)),
                          f"{cid}: condensing slid {a['id']} onto {b['id']}")
        reached = None
        for top, bottom in sorted((short_rect(b)[1], short_rect(b)[3]) for b in content):
            if reached is not None:
                check(top - reached <= 25, f"{cid}: a gap of {top - reached:.0f} mm is left above {top:.0f} mm")
            reached = bottom if reached is None else max(reached, bottom)


def constant(path, name):
    found = re.search(r"GLOBAL " + name + r" IS ([\d.]+)\.", (ROOT / "scripts" / "lm" / path).read_text(encoding="utf-8"))
    check(bool(found), f"{path}: {name} was not found")
    return float(found.group(1)) if found else 0.0


def expected_prefill():
    """The figures that never change, read from the code that decides them: boxes by card, bracket figures by card."""
    keys = {}                                       # (version, index) -> address, from the planner's pad test
    for line in (ROOT / "scripts" / "tests" / "test_pad.ks").read_text(encoding="utf-8").splitlines():
        found = re.search(r"V71 E (\d\d) E (\d{4}) E", line)
        if found:
            keys[("210" if "lines_j" in line else "099", found.group(1))] = found.group(2)
    check(len(keys) == 6, f"test_pad.ks: expected three V71 blocks for each version, found {sorted(keys)}")
    boxes = {}
    for column, (purpose, index) in enumerate((("SITE", "10"), ("TLAND", "04"), ("DOI", "12"))):
        n = column + 1
        boxes.update({f"p27.purpose{n}": purpose, f"p27.verb{n}.0.0.0": "7", f"p27.verb{n}.0.0.1": "1",
                      f"p27.data.{column}.0.3": index[0], f"p27.data.{column}.0.4": index[1]})
        old, new = keys.get(("099", index), "????"), keys.get(("210", index), "????")
        for cell in range(4):
            digit = old[cell] if old[cell] == new[cell] else {"099": old[cell], "210": new[cell]}
            boxes[f"p27.data.{column}.1.{cell + 1}"] = digit
    climb = f"{round(constant('lm_constants.ks', 'ASC_PHASE_RDOT') / 0.3048 * 10):05d}"      # N76 R2, 0.1 ft/s
    ascent = {}
    for cell, digit in enumerate(climb):
        ascent[f"ascent.n76.0.1.{cell + 1}"] = digit
        ascent[f"ascent.n76.1.1.{cell + 1}"] = {"210": digit}       # the second column is 210's fallback
    elevation = constant("rndz/lm_p32.ks", "P32_ELEV_DEG")
    travel = constant("rndz/lm_p34.ks", "P34_CENTANG_DEG")
    brackets = {"csi": ["+00001", f"+{round(elevation * 100):05d}"],      # CDH half an orbit after CSI
                "tpi": [{"099": f"+{elevation:06.2f}", "210": "+000.00"}, f"+{travel:06.2f}"]}
    return {"p27": boxes, "ascent": ascent}, brackets


def check_prefill(by_id):
    boxes, brackets = expected_prefill()
    for cid, card in by_id.items():
        got, want = card.get("prefill", {}), boxes.get(cid, {})
        wrong = sorted(k for k in set(got) | set(want) if got.get(k) != want.get(k))
        check(not wrong, f"{cid}: filled-in boxes differ from the code at {wrong[:4]}"
                         f"{' and more' if len(wrong) > 4 else ''}")
        fills = [b["fill"] for b in card["blocks"] if "fill" in b]
        check(fills == brackets.get(cid, []), f"{cid}: bracket figures are {fills}, expected {brackets.get(cid, [])}")


def check_delivery():
    """The page reaches the pilot: the site, the zip, the public repo and the pointers to it."""
    for names in (("make_pack.py",), ("make_release.py",), ("publish_public.py",),
                  ("tools/pages.yml", ".github/workflows/pages.yml")):
        found = [ROOT / n for n in names if (ROOT / n).exists()]
        if not found and names == ("publish_public.py",):      # private: the public repo has no copy
            continue
        check(bool(found) and "pads.html" in found[0].read_text(encoding="utf-8"), f"{names[0]} does not name pads.html")
    for name in ("README.md", "docs/pack/2-5-loads.md"):
        check(PUBLIC in (ROOT / name).read_text(encoding="utf-8"), f"{name} does not link to {PUBLIC}")


def main():
    if check(PAGE.exists(), "there is no docs/pads.html"):
        page = PAGE.read_text(encoding="utf-8")
        check_file(page)
        check_colours(page)
        data = re.search(r'<script type="application/json" id="cards">(.*?)</script>', page, re.S)
        if check(bool(data), "the card data block is missing"):
            try:
                cards = json.loads(data.group(1))
            except ValueError as err:
                check(False, f"the card data is not valid JSON: {err}")
            else:
                check_cards(cards)
                if len(problems) == 0 or all("expected all nine" in p for p in problems):   # rows need sound blocks
                    by_id = {c["id"]: c for c in cards}
                    check_card_rows(by_id)
                    check_planner(by_id)
                    check_short(by_id)
                    check_condensed(by_id)
                    check_marks(by_id)
                    check_prefill(by_id)
    check_delivery()
    for p in problems:
        print("  " + p)
    print(f"check_pads: {count} checks, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
