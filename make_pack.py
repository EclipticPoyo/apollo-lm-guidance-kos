"""Build the pilot's pack: python make_pack.py [--pdf]

Reads docs/pack/*.md (one file per pack page, in file name order) and docs/pack/pack.css, and writes
  site/index.html   all the pages in one self-contained file (fonts and images embedded), for GitHub Pages
  docs/PACK.pdf     with --pdf: A4 sheets, one or more per pack page, all at one text size, printed by Microsoft Edge or
                    Google Chrome (headless). The build fails if a sheet overflows
Needs the `markdown` package (pip install markdown). Nothing is edited by hand in the output: change the source and build again.
The design and the source format are in docs/superpowers/specs/2026-11-24-pilots-pack-design.md.

Source file: a front matter block, then Markdown.
    ---
    page: 3-3                         the page number in the header box
    section: Section 3 | Checklist    the header's right-hand cell, one line per "|"
    ---
Markdown as usual (## and ### headings, lists, pipe tables, raw HTML for figures) plus:
    `V37E 63E`        keys you type (bold typewriter)
    [[PRO]]           a DSKY button (boxed)
    ~V06 N62~         what a display shows
    {{+01234}}        a full register value, set in the Zerlina DSKY font (use only for whole register values)
    <!--table st-->   on the line before a table: its look (st = bold first column, vt = typewriter first column, nt = nouns)
    | == Descent |    a table row that starts with == is a band across the whole table
    > NOTE: text      a boxed note ("> CAUTION: text" is the red one)
    ```checklist      an Apollo-style checklist, see checklist() below
    ```strips         the flight sequence, see strips() below
    ```lamps          the DSKY lamps drawn as lamps, see lamps() below
                      Pages of sections 1, 2, 4 and A print in the light style (thin rules, black bars)
    ```fork           where the software versions part: a boxed question, see fork() below
    | == [J] Group |  a band for one version only ([A11] or [J]): filled in its colour, with its number at the end
    <!--sheet-->      on its own line: the page continues on a new sheet. Between blocks only, and a checklist that
                      goes on starts with a band:. The "(continued)" heading is added by the build
    {J text}          in a table cell: what Luminary 210 (J-class) shows or does instead, tagged 210 and in blue
    | **N63** | ...   in a <!--table nt--> table: a shaded key row
    {@3-3} {@3-0 Index}  a link to a page, by its number: the label is 3.3 (section 3) or the number, or your own words.
                      Works everywhere, checklists included. The build fails on a number no page has.

The two rendezvous routes (099 and 210) are the ROUTES table below: its pages get the version box in the header, the
version on their checklist bars (210's in blue) and the route timeline above the footer, with nothing in their source.
"""
import base64
import html
import pathlib
import re
import json
import shutil
import urllib.parse
import subprocess
import sys
import tempfile

try:
    import markdown
except ImportError:
    sys.exit("needs the markdown package: pip install markdown")

ROOT = pathlib.Path(__file__).parent.resolve()
DOCS = ROOT / "docs"
PACK = DOCS / "pack"
SITE = ROOT / "site"
PDF = DOCS / "PACK.pdf"

BROWSERS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]
SHEET_SCALE = 0.81        # every sheet prints at this size; a page too long for one sheet is split with <!--sheet-->
MAX_TYPE3 = 2        # the Zerlina digits print as Type 3 glyphs; anything more means a font went the slow way

LEGEND = ("&#8730; verify &nbsp; FL = flashing &nbsp; TIG = time of ignition &nbsp; TTG = time to go &nbsp; "
          "(...) = remark, not a step")


class PackError(Exception):
    pass


# ---------------------------------------------------------------------------------------------------------------------
# inline markup
# ---------------------------------------------------------------------------------------------------------------------
def inline_refs(text):
    """{@3-3} and {@3-3 label}: a link to the page with that number."""
    def link(m):
        page, label = m.group(1), m.group(2)
        if not label:
            label = page.replace("-", ".") if re.fullmatch(r"3-\d+", page) else page
        return f'<a class="ref" href="#p-{page}">{label}</a>'

    return re.sub(r"\{@([0-9A-Z]-[0-9]+[A-Za-z]?)(?: ([^{}]+))?\}", link, text)


def inline_buttons(text):
    """[[PRO]], {{+01234}}, ~V06 N62~ and page links (applied to the Markdown source before it is converted)."""
    text = inline_refs(text)
    text = re.sub(r"\{J ([^{}]+)\}", r'<span class="jv"><em class="tag">210</em>\1</span>', text)
    text = re.sub(r"\[\[(.+?)\]\]", r'<span class="pro">\1</span>', text)
    text = re.sub(r"\{\{(.+?)\}\}", r'<span class="reg">\1</span>', text)
    text = re.sub(r"~(.+?)~", r'<span class="dsp">\1</span>', text)
    return text


def inline_full(text):
    """The same, plus `keys`, for text that does not go through Markdown (notes). Escapes HTML first."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return inline_buttons(text)


# The signs beside CAUTION and NOTE, drawn as shapes: a typed character would depend on the PC's fonts (and can print as colour emoji).
CAUTION_SIGN = ('<svg class="sign" viewBox="0 0 24 22" aria-hidden="true"><path d="M12 1 L23.3 21 H0.7 Z" fill="#fff"/>'
                '<path d="M10.5 7.5 h3 l-0.5 7.5 h-2 Z M10.5 16.5 h3 v3 h-3 Z" fill="#B3261E"/></svg>')
NOTE_SIGN = ('<svg class="sign" viewBox="0 0 22 22" aria-hidden="true"><circle cx="11" cy="11" r="9.5" fill="none" stroke="currentColor" stroke-width="2"/>'
             '<path d="M9.6 5 h2.8 v2.8 h-2.8 Z M9.6 9.5 h2.8 v7.5 h-2.8 Z" fill="currentColor"/></svg>')


def note(kind, text):
    cls = "caut" if kind == "CAUTION" else "note"
    sign = CAUTION_SIGN if kind == "CAUTION" else NOTE_SIGN
    return f'<div class="{cls}"><b>{sign}{kind}</b><span>{inline_full(text)}</span></div>'


# ---------------------------------------------------------------------------------------------------------------------
# checklists
# ---------------------------------------------------------------------------------------------------------------------
VARIANT_CLASS = {"A11": "pa", "J": "pj"}
VARIANT_LABEL = {"A11": "099", "J": "210"}     # the printed tag: the Luminary version (the source markup keeps the profile names)


def version_tag(text):
    """("099" or "210", the rest) for text that starts with [A11] or [J]; ("", text) for text with no tag."""
    tagged = re.match(r"\[(A11|J)\]\s*", text)
    return (VARIANT_LABEL[tagged.group(1)], text[tagged.end():]) if tagged else ("", text)


# The two rendezvous routes, by page: each version's stops in flight order, and the page where they join again.
ROUTES = (("099", (("3-12", "CSI"), ("3-13", "CDH"), ("3-14", "TPI"))),
          ("210", (("3-15", "TPI"),)))
ROUTE_END = ("3-16", "MIDCOURSE")
ROUTE_AFTER = ("3-17", "BRAKING AND DOCKING")     # flown by both, after the join


def route_of(page):
    """The version whose route a page is on ("099" or "210"), "" for a page that is on neither."""
    return next((ver for ver, stops in ROUTES if any(number == page for number, _ in stops)), "")


def route_class(ver):
    """210 prints in blue: the class that says so."""
    return " j" if ver == "210" else ""


def with_parts(src):
    """Replace each "use: name" line by the lines of docs/pack/parts/name.txt, so a routine has one source."""
    def part(m):
        path = PACK / "parts" / f"{m.group(1)}.txt"
        if not path.exists():
            raise PackError(f"checklist: there is no part '{m.group(1)}' in docs/pack/parts")
        return path.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")

    return re.sub(r"^[ \t]*use:[ \t]*(\S+)[ \t]*$", part, src, flags=re.M)


def checklist(src, ver=""):
    """One checklist block. With a version (a page on a rendezvous route) every bar carries its number, 210's in blue.
    One directive per line:
        band: TITLE | small text        a black bar across the page
        band: TITLE | small | optional  the bar of a section that may be left out: green, marked OPTIONAL
        legend                          the one-line key to the symbols
        - time | control | action       a step: CONTROL - ACTION, with an optional time tag in the margin
        v: text                         a check mark: verify this
        n: text                         a remark in brackets (not a step)
        gate: margin | cell | cell      a row of figures in fixed columns, so that rows line up (the braking gates). A cell "30 ft/s (9.1 m/s)"
                                        makes two columns, the figure and its metric one; any other cell makes one
        **words**                       bold, in any of these: what the pilot does to the ship (SAS, RCS, throttle, target)
        PRO, ENTR                       the two keys written out are boxed by themselves, except in n: remarks; keys inside "V37E" are not
        if: HEADER                      opens a boxed branch; inside it, steps are "- control | action" and "v: text"
        end                             closes the branch
    A "!" at the start of a line draws a change bar in the margin for it (lines that changed since the last release).
    "[A11]" or "[J]" before -, v:, n:, gate: or if: marks a line (or a whole branch) for one software version only.
        goto: where | when to come back  a boxed jump to another checklist (the second field may be left out)
        abort: keys | page link         the red box on a descent checklist: what to press to abort, and its page
        use: name                       the lines of docs/pack/parts/name.txt: steps written out on more than one page"""
    src = with_parts(src)
    out = ['<div class="cl">']
    legend = ""
    box = None            # lines of the open IF branch
    box_head = box_variant = ""

    def metric(markup):
        return re.sub(r"\(((?:[\d.]+ to )?[\d.]+ (?:m/s|km|m))\)", r'<span class="si">(\1)</span>', markup)

    def text_html(value, keys=True):
        marked = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(value))
        if keys:
            marked = re.sub(r"\b(PRO|ENTR)\b", r'<span class="pro">\1</span>', marked)
        return metric(inline_refs(marked))

    def line(time, body, kind="", chg=False, variant=""):
        cls = " ".join(c for c in ("cln", kind, "chg" if chg else "", VARIANT_CLASS.get(variant, "")) if c)
        tm = "" if box is not None else f'<span class="ctm">{metric(html.escape(time))}</span>'
        return f'<div class="{cls}">{tm}<span class="cac">{body}</span></div>'

    for raw in src.split("\n"):
        text = raw.strip()
        if not text:
            continue
        chg = text.startswith("!")
        if chg:
            text = text[1:].strip()
        variant = ""
        tagged = re.match(r"\[(A11|J)\]\s*", text)
        if tagged:
            variant, text = tagged.group(1), text[tagged.end():]
        tag = f'<em class="tag">{VARIANT_LABEL[variant]}</em>' if variant else ""
        try:
            if variant and not text.startswith(("-", "v:", "n:", "gate:", "if:")):
                raise PackError("a version tag goes before -, v:, n:, gate: or if: only")
            if text.startswith("band:"):
                parts = [p.strip() for p in text[5:].split("|")]
                if parts[2:] not in ([], ["optional"]):
                    raise PackError("a band is TITLE | small text, with only | optional after them")
                small = f"<span>{text_html(parts[1])}</span>" if len(parts) > 1 and parts[1] else ""
                cls, mark = ("band opt", '<em class="optmark">OPTIONAL</em>') if parts[2:] else ("band", "")
                if ver:
                    cls, mark = cls + route_class(ver), mark + f'<em class="vmark">{ver}</em>'
                out.append(f'<div class="{cls}">{text_html(parts[0])}{small}{mark}</div>')
            elif text == "legend":
                legend = f'<div class="cl-legend">{LEGEND}</div>'   # sits above the checklist, outside its margin rule
            elif text.startswith("v:"):
                body = f"<i>&#8730;</i>{tag}{text_html(text[2:].strip())}"
                (box if box is not None else out).append(line("", body, "v", chg, variant))
            elif text.startswith("n:"):
                body = f"{tag}({text_html(text[2:].strip(), keys=False)})"
                (box if box is not None else out).append(line("", body, "n", chg, variant))
            elif text.startswith("gate:"):
                fields = [f.strip() for f in text[5:].split("|")]
                if box is not None or len(fields) < 2:
                    raise PackError("a gate: is margin | cell | ..., outside an if:")
                cells = [f'<span class="gtag">{tag}</span>']
                for cell in fields[1:]:
                    pair = re.fullmatch(r"(.+?) (\([\d.]+ (?:m/s|km|m)\))", cell)
                    if pair:
                        cells.append(f'<b class="gfig">{text_html(pair[1])}</b><span class="gsi">{text_html(pair[2])}</span>')
                    else:
                        cells.append(f'<span class="greg">{text_html(cell)}</span>')
                out.append(line(fields[0], "".join(cells), "g", chg, variant))
            elif text.startswith("goto:"):
                if box is not None:
                    raise PackError("a goto: inside an if:")
                parts = [p.strip() for p in text[5:].split("|", 1)]
                rows = f"<div><b>GO TO</b>{text_html(parts[0])}</div>"
                if len(parts) > 1:
                    rows += f"<div><b>BACK</b>{text_html(parts[1])}</div>"
                out.append(f'<div class="cgo">{rows}</div>')
            elif text.startswith("abort:"):
                parts = [p.strip() for p in text[6:].split("|")]
                if box is not None or len(parts) != 2:
                    raise PackError("an abort: is keys | page link, outside an if:")
                out.append(f'<div class="cabort"><b>{CAUTION_SIGN}ABORT</b><span>{text_html(parts[0])}</span><em>{text_html(parts[1])}</em></div>')
            elif text.startswith("if:"):
                if box is not None:
                    raise PackError("an if: inside an if:")
                box, box_head, box_variant = [], text_html(text[3:].strip()), variant
            elif text == "end":
                if box is None:
                    raise PackError("end without if:")
                cls = " ".join(c for c in ("cif", VARIANT_CLASS.get(box_variant, "")) if c)
                mark = f'<em class="tag">{VARIANT_LABEL[box_variant]}</em>' if box_variant else ""
                out.append(f'<div class="{cls}"><div class="cih">{mark}IF {box_head}</div>{"".join(box)}</div>')
                box = None
            elif text.startswith("-"):
                fields = [f.strip() for f in text[1:].split("|")]
                want = 2 if box is not None else 3
                if len(fields) != want:
                    raise PackError(f"a step here needs {want} fields separated by |")
                time, ctl, act = ("", *fields) if box is not None else fields
                if ctl and act:
                    body = f"<b>{text_html(ctl)}</b> &ndash; {text_html(act)}"
                else:
                    body = f"<b>{text_html(ctl)}</b>" if ctl else text_html(act)
                (box if box is not None else out).append(line(time, tag + body, "", chg, variant))
            else:
                raise PackError("unknown directive")
        except PackError as e:
            raise PackError(f"checklist line '{raw.strip()}': {e}")
    if box is not None:
        raise PackError("checklist: if: without end")
    out.append("</div>")
    return legend + chr(10).join(out)


# ---------------------------------------------------------------------------------------------------------------------
# the flight sequence and the lamps
# ---------------------------------------------------------------------------------------------------------------------
def block_lines(src):
    return [line.strip() for line in src.split("\n") if line.strip()]


def strips(src):
    """One line each:
        bar: TITLE | small text                          a black bar
        - phase | programmes | what you do | what the computer does
    "[J]" before the phase marks a strip for that version only: 210's is blue."""
    out = []
    for text in block_lines(src):
        if text.startswith("bar:"):
            parts = [p.strip() for p in text[4:].split("|", 1)]
            small = f"<span>{inline_full(parts[1])}</span>" if len(parts) > 1 else ""
            out.append(f'<div class="bar">{inline_full(parts[0])}{small}</div>')
            continue
        fields = [f.strip() for f in text[1:].split("|")]
        if not text.startswith("-") or len(fields) != 4:
            raise PackError(f"strips line '{text}': 'bar: ...' or '- phase | programmes | you | computer'")
        ver, fields[0] = version_tag(fields[0])
        name, progs, you, computer = (inline_full(f) for f in fields)
        out.append(f'<div class="ph{route_class(ver)}"><div class="nm">{name}<small>{progs}</small></div><div class="who">You</div><div class="what">{you}</div>'
                   f'<div class="who">Computer</div><div class="what">{computer}</div></div>')
    return "".join(out)


LAMP_COLOURS = ("white", "amber", "green")


def lamps(src):
    """One line each:  - LAMP | white, amber or green | when it is lit"""
    out = []
    for text in block_lines(src):
        fields = [f.strip() for f in text[1:].split("|")]
        if not text.startswith("-") or len(fields) != 3 or fields[1] not in LAMP_COLOURS:
            raise PackError(f"lamps line '{text}': '- LAMP | {' or '.join(LAMP_COLOURS)} | when it is lit'")
        name, colour, lit = fields
        out.append(f'<div class="lampitem"><span class="lamp {colour}">{html.escape(name)}</span><div>{inline_full(lit)}</div></div>')
    return f'<div class="lampgrid">{"".join(out)}</div>'


def fork(src):
    """Where the two versions part. The first line is the title, then one row for each version:
        - 099 or 210 | words in bold | the rest"""
    lines = block_lines(src)
    if len(lines) < 2 or lines[0].startswith("-"):
        raise PackError("fork: a title line, then a '- version | bold words | the rest' line for each version")
    rows = []
    for text in lines[1:]:
        fields = [f.strip() for f in text[1:].split("|")]
        if not text.startswith("-") or len(fields) != 3 or fields[0] not in VARIANT_LABEL.values():
            raise PackError(f"fork line '{text}': '- {' or '.join(VARIANT_LABEL.values())} | bold words | the rest'")
        ver, bold, rest = fields
        rows.append(f'<div class="fr{route_class(ver)}"><em>{ver}</em><span><b>{inline_full(bold)}</b> {inline_full(rest)}</span></div>')
    return f'<div class="fork"><div class="fh">{inline_full(lines[0])}</div>{"".join(rows)}</div>'


# ---------------------------------------------------------------------------------------------------------------------
# the route timeline
# ---------------------------------------------------------------------------------------------------------------------
ROUTE_TRACKS = ((13, (240, 335, 430)), (47, (430,)))       # for each of ROUTES: its height, and where its stops sit (not to scale; the TPIs line up)


def route_strip(page):
    """The timeline above the footer of a route page and of the shared pages after them; "" elsewhere.
    INSERTION on the left, one track per version, then the join and braking and docking. Every stop is a link and this page's is
    filled. The drawing has no colours of its own: pack.css gives them, so it follows the dark theme."""
    if not route_of(page) and page not in (ROUTE_END[0], ROUTE_AFTER[0]):
        return ""

    def stop(target, name, x, y, width, cls=""):
        here = " here" if target == page else ""
        return (f'<a href="#p-{target}" class="stop{cls}{here}"><rect x="{x - width // 2}" y="{y - 10}" width="{width}" height="20" rx="10"/>'
                f'<text x="{x}" y="{y}">{name} {target.replace("-", ".")}</text></a>')

    tracks, marks = [], []
    for (ver, stops), (y, places) in zip(ROUTES, ROUTE_TRACKS):
        cls = route_class(ver)
        tracks.append(f'<path class="trk{cls}" d="M96 30 C128 30 128 {y} 160 {y} H476 C503 {y} 503 30 530 30"/>')
        marks.append(f'<g class="rv{cls}"><rect x="152" y="{y - 9}" width="34" height="18" rx="2"/><text x="169" y="{y}">{ver}</text></g>')
        marks += [stop(number, name, x, y, 86, cls) for (number, name), x in zip(stops, places)]
    return ('<div class="route"><svg viewBox="0 0 880 60">' + "".join(tracks)
            + '<circle cx="96" cy="30" r="5"/><text class="from" x="86" y="30">INSERTION</text>'
            + '<path class="trk" d="M650 30 H680"/>' + "".join(marks) + stop(*ROUTE_END, 590, 30, 120)
            + stop(*ROUTE_AFTER, 776, 30, 192) + "</svg></div>")


# ---------------------------------------------------------------------------------------------------------------------
# a page
# ---------------------------------------------------------------------------------------------------------------------
def render_body(body, ver=""):
    holders = []

    def hold(markup):
        holders.append(markup)
        return f"\n\nPACKHOLD{len(holders) - 1}\n\n"

    body = re.sub(r"```checklist\n(.*?)```", lambda m: hold(checklist(m.group(1), ver)), body, flags=re.S)
    body = re.sub(r"```strips\n(.*?)```", lambda m: hold(strips(m.group(1))), body, flags=re.S)
    body = re.sub(r"```lamps\n(.*?)```", lambda m: hold(lamps(m.group(1))), body, flags=re.S)
    body = re.sub(r"```fork\n(.*?)```", lambda m: hold(fork(m.group(1))), body, flags=re.S)
    body = re.sub(r"^> (NOTE|CAUTION): (.*)$", lambda m: hold(note(m.group(1), m.group(2))), body, flags=re.M)
    body = inline_buttons(body)
    out = markdown.markdown(body, extensions=["tables", "sane_lists", "md_in_html"])

    # table classes from <!--table x-->, bands from "== text" rows, and a wrapper so a wide table scrolls on a phone
    out = re.sub(r"<!--table (\w+)-->\s*<table>", r'<table class="\1">', out)

    def bands(m):
        table = m.group(0)
        cols = len(re.findall(r"<th[ >]", table))                  # not <thead>
        if table.startswith('<table class="nt">'):       # a noun the flight cards use: its number is written in **bold**
            table = re.sub(r"<tr>(\s*<td><strong>)", r'<tr class="key">\1', table)
        def band(r):
            ver, text = version_tag(r.group(1))
            cls, mark = (f"band ver{route_class(ver)}", f'<em class="vmark">{ver}</em>') if ver else ("band", "")
            return f'<tr class="{cls}"><td colspan="{cols}">{text}{mark}</td></tr>'

        return re.sub(r"<tr>\s*<td>== (.*?)</td>.*?</tr>", band, table, flags=re.S)

    out = re.sub(r"<table.*?</table>", bands, out, flags=re.S)
    out = re.sub(r"(<table.*?</table>)", r'<div class="tw">\1</div>', out, flags=re.S)
    for i, markup in enumerate(holders):
        out = re.sub(rf"<p>PACKHOLD{i}</p>", lambda _: markup, out)
        if f"PACKHOLD{i}" in out:
            raise PackError("internal: a placeholder was left in the page")
    return out


def parse_page(path):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, flags=re.S)
    if not m:
        raise PackError(f"{path.name}: no front matter")
    meta = dict(re.findall(r"^(\w+):\s*(.*)$", m.group(1), flags=re.M))
    for key in ("page", "section"):
        if key not in meta:
            raise PackError(f"{path.name}: front matter lacks '{key}'")
    return meta, m.group(2)


def split_sheets(body):
    """A page's source cut at its <!--sheet--> lines. A sheet with no heading of its own gets the last one, "(continued)"."""
    sheets = re.split(r"^<!--sheet-->[ \t]*$", body, flags=re.M)
    heading = ""
    for n, text in enumerate(sheets):
        if len(sheets) > 1:
            if not text.strip():
                raise PackError("<!--sheet-->: a sheet with nothing on it")
            if len(re.findall(r"^```", text, flags=re.M)) % 2:
                raise PackError("<!--sheet--> inside a block: close the checklist before it and open it again after")
        found = re.findall(r"^## (.*)$", text, flags=re.M)
        if n:
            text = text.lstrip("\n")
            first = re.match(r"```checklist\n\s*(\S+)", text)
            if first and first.group(1) != "band:":
                raise PackError("<!--sheet-->: a checklist that goes on to a new sheet starts there with a band:")
            if heading and not text.startswith("## "):
                text = f"## {heading} (continued)\n\n{text}"
            sheets[n] = text
        if found:
            heading = found[-1]
    return sheets


def page_html(meta, body, number, version, part=0, parts=1):
    sec = "<br>".join(html.escape(s.strip()) for s in meta["section"].split("|"))
    anchor = f' id="p-{html.escape(meta["page"])}"' if part == 0 else ""          # a link goes to the page's first sheet
    onward = '<div class="onward">Continued on the next sheet</div>' if part < parts - 1 else ""
    style = "page lite" if meta["page"][0] in "124A" else "page"          # reference pages: thin rules and black bars
    ver = route_of(meta["page"])
    hdr, vbox = ("hdr v", f'<div class="vbox{route_class(ver)}">{ver}</div>') if ver else ("hdr", "")
    return (f'<div class="{style}"{anchor}><div class="{hdr}"><div><b>LM Guidance Computer</b><span>PILOT\'S PACK</span></div>'
            f'<div class="sec">{sec}</div>{vbox}<div>{html.escape(meta["page"])}</div></div>'
            f'<div class="pb">{render_body(body, ver)}{onward}</div>{route_strip(meta["page"])}'
            f'<div class="ftr"><span>Release {version}</span><span>{inline_refs("{@0-1 Contents} &nbsp; {@3-0 Index}")}</span>'
            f'<span>LGC-{number}</span></div></div>')


def check_links(pages_html, ids):
    """Every link must lead to a page, no link may be left as source text, and no page number may be used twice."""
    twice = sorted({i for i in ids if ids.count(i) > 1})
    if twice:
        raise PackError(f"two pages are numbered {', '.join(twice)}")
    for number, markup in enumerate(pages_html, 1):
        found = re.search(r'id="p-([^"]+)"', markup)
        where = f"page {found.group(1)}" if found else f"sheet {number}"
        if "{@" in markup:
            left = markup[markup.index("{@"):][:30]
            raise PackError(f"{where}: a link is written wrongly: {left!r}")
        for target in re.findall(r'href="#p-([^"]*)"', markup):
            if target not in ids:
                raise PackError(f"{where}: link to a page that does not exist: {target}")


# ---------------------------------------------------------------------------------------------------------------------
# assembling
# ---------------------------------------------------------------------------------------------------------------------
MIME = {".png": "image/png", ".woff2": "font/woff2", ".otf": "font/otf", ".jpg": "image/jpeg"}


def data_uri(path):
    return f"data:{MIME[path.suffix.lower()]};base64," + base64.b64encode(path.read_bytes()).decode()


def embed_css(css):
    return re.sub(r"url\((fonts/[^)]+)\)", lambda m: f"url({data_uri(PACK / m.group(1))})", css)


def embed_images(markup):
    def swap(m):
        path = DOCS / m.group(1)
        if not path.exists():
            raise PackError(f"image not found: {path}")
        return f'src="{data_uri(path)}"'

    return re.sub(r'src="(images/[^"]+)"', swap, markup)


FIT = """
(function(){
  var W = 748, H = 1077;   /* the printable area of an A4 sheet with 6 mm margins, in CSS px */
  var Z = SHEET_Z;          /* one text size for every sheet */
  function fit(){
    document.querySelectorAll('.sheet').forEach(function(s){
      var p = s.firstElementChild;
      p.style.width = (W / Z) + 'px';
      p.style.zoom = Z;   /* zoom, not transform: a transform is fragmented at the unscaled height when printed */
      s.setAttribute('data-fill', (p.getBoundingClientRect().height / H).toFixed(3));
    });
    document.body.setAttribute('data-fitted', '1');
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit); else window.addEventListener('load', fit);
})();
""".replace("SHEET_Z", str(SHEET_SCALE))


TOPBAR = ('<p class="topbar"><a href="PACK.pdf">Download as PDF (A4, print it)</a> <a href="https://github.com/EclipticPoyo/apollo-lm-guidance-kos">Source code</a> '
          '<button type="button" id="theme" aria-label="Switch between light and dark mode">Dark mode</button></p>')
# The theme switch (web page only; the PDF build leaves it out, so the PDF is always light). It follows the system setting until the
# reader clicks the button, then remembers the choice in the browser.
THEME_HEAD = ("<script>(function(){var t;try{t=localStorage.getItem('pack-theme')}catch(e){}"
              "if(!t)t=(window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';"
              "document.documentElement.setAttribute('data-theme',t)})()</script>")
_MOON = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M13 10.2A6 6 0 0 1 5.8 3 6 6 0 1 0 13 10.2z" fill="currentColor"/></svg>'
_SUN = ('<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><circle cx="8" cy="8" r="3.2" fill="currentColor"/>'
        '<path d="M8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.4 1.4M11.6 11.6L13 13M3 13l1.4-1.4M11.6 4.4L13 3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>')
THEME_BODY = ("<script>(function(){var b=document.getElementById('theme'),r=document.documentElement,MOON=" + json.dumps(_MOON) + ",SUN=" + json.dumps(_SUN) + ";"
              "function label(){var d=r.getAttribute('data-theme')=='dark';b.innerHTML=(d?SUN:MOON)+' '+(d?'Light mode':'Dark mode')}label();"
              "b.addEventListener('click',function(){var t=r.getAttribute('data-theme')=='dark'?'light':'dark';"
              "r.setAttribute('data-theme',t);try{localStorage.setItem('pack-theme',t)}catch(e){}label()})})()</script>")


# The browser tab icon: a tiny DSKY on a dark tile: the grey housing, a black display with three green register lines and a column of lamps,
# and two rows of keys. An SVG in the page head (no extra file, so the page stays self-contained). Not used in the PDF.
FAVICON_SVG = ("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='5' fill='#26272A'/>"
               "<rect x='3' y='3' width='26' height='26' rx='2.5' fill='#8C8D91'/>"
               "<rect x='5' y='5' width='22' height='12' rx='1.2' fill='#101214'/>"
               "<path d='M7.2 8.4h2.6M7.2 11h2.6M7.2 13.6h2.6' stroke='#3DDC97' stroke-width='1.4'/>"
               "<path d='M12 8h12M12 11h12M12 14h12' stroke='#3DDC97' stroke-width='1.8' stroke-linecap='round'/>"
               "<rect x='6' y='19.6' width='5' height='3' rx='.7' fill='#15161A'/><rect x='11.6' y='19.6' width='5' height='3' rx='.7' fill='#15161A'/><rect x='17.2' y='19.6' width='5' height='3' rx='.7' fill='#15161A'/><rect x='22.8' y='19.6' width='5' height='3' rx='.7' fill='#15161A'/><rect x='6' y='23.8' width='5' height='3' rx='.7' fill='#15161A'/><rect x='11.6' y='23.8' width='5' height='3' rx='.7' fill='#15161A'/><rect x='17.2' y='23.8' width='5' height='3' rx='.7' fill='#15161A'/><rect x='22.8' y='23.8' width='5' height='3' rx='.7' fill='#15161A'/></svg>")
FAVICON = "data:image/svg+xml," + urllib.parse.quote(FAVICON_SVG, safe="/:=' ")


def build_html(pages, sheets):
    css = embed_css((PACK / "pack.css").read_text(encoding="utf-8"))
    if sheets:
        pages = [f'<div class="sheet">{p}</div>' for p in pages]
    body = "\n".join(pages)
    return ("<!doctype html><html lang=\"en-GB\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<title>LM Guidance Computer: Pilot's Pack</title>"
            f"<link rel=\"icon\" type=\"image/svg+xml\" href=\"{FAVICON}\">"
            f"<style>{css}</style>{'' if sheets else THEME_HEAD}</head><body{' class=\"sheets\"' if sheets else ''}><div class=\"wrap\">{'' if sheets else TOPBAR}{embed_images(body)}</div>"
            + (f"<script>{FIT}</script>" if sheets else THEME_BODY) + "</body></html>")


def find_browser():
    return next((b for b in BROWSERS if pathlib.Path(b).exists()), None) or shutil.which("msedge") or shutil.which("chrome")


def make_pdf(pages):
    browser = find_browser()
    if not browser:
        sys.exit("needs Microsoft Edge or Google Chrome for --pdf")
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "pack.html"
        src.write_text(build_html(pages, sheets=True), encoding="utf-8")
        (SITE / "pack-sheets.html").write_text(src.read_text(encoding="utf-8"), encoding="utf-8")   # the sheets as a web page, to look at
        # 1. read back how full each sheet is
        dom = subprocess.run([browser, "--headless=new", "--disable-gpu", "--virtual-time-budget=8000", "--dump-dom", src.as_uri()],
                             check=True, capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
        fills = re.findall(r'data-fill="([\d.]+)"', dom)
        # 2. print it
        subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=8000",
                        f"--print-to-pdf={PDF}", src.as_uri()], check=True, capture_output=True, timeout=120)
    return [float(f) for f in fills]


def main():
    pdf = "--pdf" in sys.argv[1:]
    # numbers in a name are compared as numbers, so that page 3-10 comes after 3-9
    files = sorted(PACK.glob("*.md"), key=lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", p.name)])
    if not files:
        sys.exit(f"no pages in {PACK}")
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    pages, names, sheet_names = [], [], []
    try:
        for f in files:
            meta, body = parse_page(f)
            parts = split_sheets(body)
            for part, text in enumerate(parts):
                pages.append(page_html(meta, text, len(pages) + 1, version, part, len(parts)))
                sheet_names.append(meta["page"] + (f" sheet {part + 1}" if len(parts) > 1 else ""))
            names.append(meta["page"])
        check_links(pages, names)
    except PackError as e:
        sys.exit(f"error: {e}")

    SITE.mkdir(exist_ok=True)
    out = SITE / "index.html"
    out.write_text(build_html(pages, sheets=False), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB, {len(names)} pages on {len(pages)} sheets)")
    if PDF.exists() and not pdf:
        shutil.copy2(PDF, SITE / "PACK.pdf")        # the published site links to the PDF committed in docs/

    if pdf:
        fills = make_pdf(pages)
        count = len(re.findall(rb"/Type\s*/Page[^s]", PDF.read_bytes()))
        print(f"wrote {PDF} ({PDF.stat().st_size // 1024} KB, {count} sheets for {len(names)} pages)")
        bad = False
        if count != len(pages):
            print(f"WARNING: the PDF has {count} sheets, not the {len(pages)} built: a sheet spilled over")
            bad = True
        # what made the first PDF scroll slowly: Type 3 glyph fonts (a variable font, or an unembeddable one) and shading patterns
        # (a CSS gradient). Keep static fonts and plain lines, and these stay at the figures below.
        raw = PDF.read_bytes()
        type3, shades = len(re.findall(rb"/Subtype\s*/Type3", raw)), len(re.findall(rb"/ShadingType", raw))
        if type3 > MAX_TYPE3 or shades:
            print(f"WARNING: the PDF has {type3} Type 3 fonts (the Zerlina digits give {MAX_TYPE3}) and {shades} shading patterns; it will scroll slowly. "
                  "Use static font files (not variable) and no CSS gradients or box shadows in the pages.")
            bad = True
        for name, fill in zip(sheet_names, fills):
            if fill > 1:
                print(f"  page {name}: {fill:.2f} sheets of text  <- too long: add a <!--sheet--> break, or cut it")
                bad = True
        if len(fills) != len(pages):
            print("WARNING: could not read the fit of every page")
            bad = True
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
