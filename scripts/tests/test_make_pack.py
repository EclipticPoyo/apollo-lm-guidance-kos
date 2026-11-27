"""test_make_pack.py: the pack build's page links and variant lines.  Run: python scripts/tests/test_make_pack.py

Not part of check_all.py: it imports make_pack.py, which needs the `markdown` package.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import make_pack as mp

# page links: the default label is 3.N in section 3 and the page id elsewhere
assert mp.inline_refs("{@3-3}") == '<a class="ref" href="#p-3-3">3.3</a>'
assert mp.inline_refs("{@0-4}").endswith('>0-4</a>')
assert 'href="#p-2-2A"' in mp.inline_refs("{@2-2A}")            # a page number may end in a letter, either case
assert mp.inline_refs("{@3-0 Index}").endswith('>Index</a>')

# they work wherever text is written: Markdown, notes, and every kind of checklist text
assert 'href="#p-3-3"' in mp.render_body("See {@3-3}.")
assert 'href="#p-3-3"' in mp.render_body("> NOTE: see {@3-3}.")
assert 'href="#p-3-3"' in mp.checklist("- | DSKY | V37E 40E {@3-3}")
assert 'href="#p-3-4"' in mp.checklist("band: BURN | {@3-4}")
assert 'href="#p-3-4"' in mp.checklist("v: see {@3-4}")
assert 'href="#p-3-4"' in mp.checklist("n: see {@3-4}")
assert 'href="#p-3-4"' in mp.checklist("if: SEE {@3-4}\n- A | b\nend")
assert 'href="#p-3-4"' in mp.checklist("if: X\n- A | see {@3-4}\nend")

# variant lines carry a class and a text tag, so they read in black and white too
j = mp.checklist("[J] - | W / S | 1 deg")
assert 'class="cln pj"' in j and '<em class="tag">210</em>' in j
a = mp.checklist("[A11] v: x")
assert 'class="cln v pa"' in a and '<em class="tag">099</em>' in a
box = mp.checklist("[A11] if: X\n- A | b\nend")
assert 'class="cif pa"' in box and '<em class="tag">099</em>' in box
assert '<em class="tag">210</em>' in mp.checklist("[J] - | W / S | 1 deg")
assert '<span class="jv"><em class="tag">210</em>speed</span>' == mp.inline_buttons("{J speed}")
assert '<span class="av"><em class="tag">099</em>speed</span>' == mp.inline_buttons("{A11 speed}")
assert 'N69 <em class="tag vtag j">210</em>' == mp.inline_buttons("N69 {J}")
assert '<em class="tag vtag">099</em> burns' == mp.inline_buttons("{A11} burns")
assert 'class="cln pj"' in mp.checklist("if: X\n[J] - A | b\nend")
assert 'class="cln v chg pj"' in mp.checklist("![J] v: x")
assert 'tag' not in mp.checklist("- | A | b")

# PRO and ENTR written out are boxed in steps and checks, not in remarks; keys run together in a verb entry are not
keys = mp.checklist("- | PRO | turns; then ENTR\nv: PRO each\nn: PRO again")
assert keys.count('<span class="pro">PRO</span>') == 2 and keys.count('<span class="pro">ENTR</span>') == 1
assert 'class="pro"' not in mp.checklist("- | DSKY | V37E 20E, PROG 00, V16 N45E")

# a tag on a line that cannot carry one is an error, not silently dropped
for src in ("[J] band: X", "[J] end", "[J] legend"):
    try:
        mp.checklist(src)
    except mp.PackError:
        continue
    raise AssertionError(f"no error for {src}")

# every page is a link target
sheet = mp.page_html({"page": "3-3", "section": "x"}, "t", 1, "0")
assert 'id="p-3-3"' in sheet
# and every footer leads back to the contents and the checklist index
assert 'href="#p-0-1"' in sheet and 'href="#p-3-0"' in sheet

# the build refuses a dead link, a mistyped link left as text, and two pages with one number
mp.check_links(['<a class="ref" href="#p-3-3">3.3</a>'], ["3-3"])
for pages, ids in ((['<a class="ref" href="#p-9-9">9-9</a>'], ["3-3"]), (["{@ 3-3}"], ["3-3"]), (["{@3-3"], ["3-3"]),
                   ([""], ["3-3", "3-3"])):
    try:
        mp.check_links(pages, ids)
    except mp.PackError:
        continue
    raise AssertionError(f"no error for {pages} {ids}")

# a routine written out on several pages has one source, docs/pack/parts/, copied in by the build
assert "V37E 41E" in mp.checklist("use: p41")
for src in ("use: nothing", "[J] use: p41"):
    try:
        mp.checklist(src)
    except mp.PackError:
        continue
    raise AssertionError(f"no error for {src}")

# a jump to another checklist is one clear boxed step, saying where to go and when to come back
go = mp.checklist("goto: {@3-3 3.3 ENGINE BURNS} | here for the midcourses")
assert 'class="cgo"' in go and "GO TO" in go and "BACK" in go and 'href="#p-3-3"' in go
assert "BACK" not in mp.checklist("goto: {@3-3}")
try:
    mp.checklist("if: X\ngoto: {@3-3}\nend")
except mp.PackError:
    pass
else:
    raise AssertionError("no error for goto: inside an if:")

# every sheet prints at one text size; a long page continues on another sheet, split where its source says
assert mp.SHEET_SCALE == 0.81 and str(mp.SHEET_SCALE) in mp.FIT
assert mp.split_sheets("one") == ["one"]
two = mp.split_sheets("## 3.9 Title\n\n```checklist\nband: A\n```\n\n<!--sheet-->\n\n```checklist\nband: B\n```\n")
assert len(two) == 2 and two[1].startswith("## 3.9 Title (continued)\n") and "band: B" in two[1] and "band: B" not in two[0]
own = mp.split_sheets("## 2.1 A\n\ntext\n<!--sheet-->\n## 2.2 B\n\nmore")
assert own[1].startswith("## 2.2 B")                  # a sheet with its own heading gets no "continued" one
three = mp.split_sheets("## 1 T\n\na\n<!--sheet-->\nb\n<!--sheet-->\nc")
assert three[2].startswith("## 1 T (continued)\n") and "(continued) (continued)" not in three[2]
for body in ("a\n<!--sheet-->\n", "<!--sheet-->\nb",                                      # an empty sheet
             "```checklist\nband: A\n<!--sheet-->\n- | X | y\n```",                          # a break inside a checklist block
             "```checklist\nband: A\n```\n<!--sheet-->\n```checklist\n- | X | y\n```"):       # a break that is not between bands
    try:
        mp.split_sheets(body)
    except mp.PackError:
        continue
    raise AssertionError(f"no error for {body!r}")
meta = {"page": "3-9", "section": "x"}
first, last = mp.page_html(meta, "a", 1, "0", part=0, parts=2), mp.page_html(meta, "b", 2, "0", part=1, parts=2)
assert 'id="p-3-9"' in first and 'id="p-' not in last          # a link goes to the first sheet
assert "Continued on the next sheet" in first and "Continued on the next sheet" not in last

# reference tables: a version note inside a cell and a key row; Markdown inside a styled block
cell = mp.render_body("| A | B |\n|---|---|\n| x | y {J radar {@3-3} height} |")
assert 'class="jv"' in cell and '<em class="tag">210</em>' in cell and 'href="#p-3-3"' in cell
keyed = mp.render_body("<!--table nt-->\n| N | R |\n|---|---|\n| **N63** | speed |\n| N66 | radar |")
assert keyed.count('<tr class="key">') == 1 and keyed.index('<tr class="key">') < keyed.index("N63") < keyed.index("N66")
need = mp.render_body('<div class="need" markdown="1">\n\n- one\n- two\n\n</div>')
assert 'class="need"' in need and "<li>one</li>" in need

# sections 1, 2, 4 and the appendix print in the light style; the cards, contents and checklists do not
for page, lite in (("1-1", True), ("2-2A", True), ("4-1", True), ("A-1", True), ("0-1", False), ("0-4", False), ("3-0", False), ("3-11", False)):
    first = mp.page_html({"page": page, "section": "x"}, "t", 1, "0").split(">")[0]
    assert ('class="page lite"' in first) == lite, (page, first)

# the flight sequence as strips under black bars
strip = mp.render_body("```strips\nbar: Descent | {@3-1} to {@3-8}\n- Braking | P63 | `V37E 63E`, [[PRO]] twice. | Turns & burns.\n```")
assert 'class="bar"' in strip and 'href="#p-3-8"' in strip and 'class="ph"' in strip and "<code>V37E 63E</code>" in strip
assert 'class="pro"' in strip and "Turns &amp; burns." in strip and "You" in strip and "Computer" in strip

# the DSKY lamps drawn as lamps
lamp = mp.render_body("```lamps\n- OPR ERR | white | A bad key.\n- PROG | amber | An alarm.\n- COMP ACTY | green | Running.\n```")
assert 'class="lampgrid"' in lamp and '<span class="lamp white">OPR ERR</span>' in lamp and '<span class="lamp amber">PROG</span>' in lamp

for src in ("```strips\n- A | B | C\n```", "```strips\nfoo\n```", "```lamps\n- X | pink | y\n```", "```lamps\n- X | white\n```"):
    try:
        mp.render_body(src)
    except mp.PackError:
        continue
    raise AssertionError(f"no error for {src!r}")

# an optional section: a green bar with the word on it; the word carries the meaning in black and white
opt = mp.checklist("band: TRACKING | P20 | optional")
assert 'class="band opt"' in opt and '<em class="optmark">OPTIONAL</em>' in opt and "<span>P20</span>" in opt
assert 'opt' not in mp.checklist("band: RANGE | V83")
try:
    mp.checklist("band: A | b | perhaps")
except mp.PackError:
    pass
else:
    raise AssertionError("no error for an unknown third field of a band")

# a page on a rendezvous route is marked as its version's: the header box, the bars, the timeline above the footer
bars = "```checklist\nband: A | b\n```"


def sheet_of(page, **kw):
    return mp.page_html({"page": page, "section": "x"}, bars, 1, "0", **kw)


for page, ver, cls in (("3-12", "099", "band"), ("3-14", "099", "band"), ("3-15", "210", "band j")):
    for kw in ({}, {"part": 1, "parts": 2}):                       # a continued sheet too
        s = sheet_of(page, **kw)
        assert re.search(rf'class="vbox[ j]*">{ver}</div><div>{page}</div>', s), page
        assert f'<div class="{cls}">' in s and f'<em class="vmark">{ver}</em>' in s and 'class="route"' in s, page
end = sheet_of("3-16")
assert 'class="route"' in end and "vbox" not in end and "vmark" not in end
for page in ("3-3", "3-4", "3-10", "3-18"):
    s = sheet_of(page)
    assert 'class="route"' not in s and "vbox" not in s and "vmark" not in s, page
strip = mp.route_strip("3-13")
assert all(f'href="#p-{p}"' in strip for p in ("3-12", "3-13", "3-14", "3-15", "3-16"))
assert '<a href="#p-3-13" class="stop here">' in strip and '<a href="#p-3-15" class="stop j">' in strip
assert strip.count(" here") == 1 and 'fill="#' not in strip and 'stroke="#' not in strip      # pack.css colours it
assert '<a href="#p-3-16" class="stop here">' in mp.route_strip("3-16") and mp.route_strip("3-18") == ""
assert '<a href="#p-3-17" class="stop here">' in mp.route_strip("3-17") and 'href="#p-3-17"' in strip
for ver, stops in mp.ROUTES:                                       # the table agrees with the pages
    for page, _ in stops:
        assert f"Rendezvous {ver}:" in mp.parse_page(next(mp.PACK.glob(page + "-*.md")))[1], page
assert next(mp.PACK.glob(mp.ROUTE_END[0] + "-*.md"), None)

# where the routes part: a fork box; the index bar and the overview row of one version
box = mp.render_body("```fork\nWhich software?\n- 099 | Carry on here: | CSI, CDH\n- 210 | Stop. | Skip to page {@3-15}\n```")
assert 'class="fork"' in box and '<div class="fh">Which software?</div>' in box and 'href="#p-3-15"' in box
assert '<div class="fr"><em>099</em><span><b>Carry on here:</b> CSI, CDH</span></div>' in box and '<div class="fr j"><em>210</em>' in box
for src in ("T\n- 111 | a | b", "T\n- 099 | a", "- 099 | a | b", "T"):
    try:
        mp.render_body(f"```fork\n{src}\n```")
    except mp.PackError:
        continue
    raise AssertionError(f"no error for the fork {src!r}")
idx = mp.render_body("<!--table idx-->\n| P | C |\n|---|---|\n| == [A11] One | |\n| == [J] Two | |\n| == Both | |")
assert '<tr class="band ver"><td colspan="2">One<em class="vmark">099</em></td></tr>' in idx
assert '<tr class="band ver j"><td colspan="2">Two<em class="vmark">210</em></td></tr>' in idx
assert '<tr class="band"><td colspan="2">Both</td></tr>' in idx
ph = mp.render_body("```strips\n- [J] 210 burns | P34 | a | b\n- Tracking | P20 | a | b\n```")
assert ph.count('<div class="ph j">') == 1 and "[J]" not in ph

# a table of three columns or more is stacked on a phone, so each cell after the first carries its column's heading
wide = mp.render_body('<!--table st-->\n| Want | Press "now" | You get |\n|---|---|---|\n| a | b | c |\n| == One | | |')
assert '<td>a</td>' in wide and '<td data-l="Press &quot;now&quot;">b</td>' in wide and '<td data-l="You get">c</td>' in wide
assert '<tr class="band"><td colspan="3">One</td></tr>' in wide
assert "data-l" not in mp.render_body("<!--table st-->\n| Problem | Action |\n|---|---|\n| a | b |")      # two columns: no labels

# phone rules: after every rule they override (a media query adds no weight, so the later rule wins), and screen only, not print
css = (mp.PACK / "pack.css").read_text(encoding="utf-8")
assert css.count("@media(max-width") == 0 and css.count("@media screen and (max-width:640px)") == 1
tail = css[css.index("@media screen and (max-width:640px)"):].rstrip()
assert tail.count("{") == tail.count("}") and not re.search(r"^\S", tail.split("\n", 1)[1].rsplit("}", 1)[0], re.M)   # the last block in the file

print("test_make_pack: OK")
