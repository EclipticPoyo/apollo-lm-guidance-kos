"""Build the pilot's pack: python make_pack.py [--pdf]

Reads docs/pack/*.md (one file per pack page, in file name order) and docs/pack/pack.css, and writes
  site/index.html   all the pages in one self-contained file (fonts and images embedded), for GitHub Pages
  docs/PACK.pdf     with --pdf: one A4 sheet per pack page, printed by Microsoft Edge or Google Chrome (headless)
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
"""
import base64
import html
import pathlib
import re
import json
import shutil
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
MIN_SCALE = 0.72          # a page that has to shrink below this to fit one sheet is too long: split or cut it
MAX_TYPE3 = 2        # the Zerlina digits print as Type 3 glyphs; anything more means a font went the slow way

LEGEND = ("&#8730; verify &nbsp; FL = flashing &nbsp; TIG = time of ignition &nbsp; TTG = time to go &nbsp; "
          "(...) = remark, not a step")


class PackError(Exception):
    pass


# ---------------------------------------------------------------------------------------------------------------------
# inline markup
# ---------------------------------------------------------------------------------------------------------------------
def inline_buttons(text):
    """[[PRO]], {{+01234}} and ~V06 N62~ (applied to the Markdown source before it is converted)."""
    text = re.sub(r"\[\[(.+?)\]\]", r'<span class="pro">\1</span>', text)
    text = re.sub(r"\{\{(.+?)\}\}", r'<span class="reg">\1</span>', text)
    text = re.sub(r"~(.+?)~", r'<span class="dsp">\1</span>', text)
    return text


def inline_full(text):
    """The same, plus `keys`, for text that does not go through Markdown (notes). Escapes HTML first."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return inline_buttons(text)


def note(kind, text):
    cls = "caut" if kind == "CAUTION" else "note"
    return f'<div class="{cls}"><b>{kind}</b><span>{inline_full(text)}</span></div>'


# ---------------------------------------------------------------------------------------------------------------------
# checklists
# ---------------------------------------------------------------------------------------------------------------------
def checklist(src):
    """One checklist block. One directive per line:
        band: TITLE | small text        a black bar across the page
        legend                          the one-line key to the symbols
        - time | control | action       a step: CONTROL - ACTION, with an optional time tag in the margin
        v: text                         a check mark: verify this
        n: text                         a remark in brackets (not a step)
        if: HEADER                      opens a boxed branch; inside it, steps are "- control | action" and "v: text"
        end                             closes the branch
    A "!" at the start of a line draws a change bar in the margin for it (lines that changed since the last release)."""
    out = ['<div class="cl">']
    legend = ""
    box = None            # lines of the open IF branch
    box_head = ""

    def line(time, body, kind="", chg=False):
        cls = ("cln " + kind + (" chg" if chg else "")).strip()
        tm = "" if box is not None else f'<span class="ctm">{html.escape(time)}</span>'
        return f'<div class="{cls}">{tm}<span class="cac">{body}</span></div>'

    for raw in src.split("\n"):
        text = raw.strip()
        if not text:
            continue
        chg = text.startswith("!")
        if chg:
            text = text[1:].strip()
        try:
            if text.startswith("band:"):
                parts = [p.strip() for p in text[5:].split("|", 1)]
                small = f"<span>{html.escape(parts[1])}</span>" if len(parts) > 1 else ""
                out.append(f'<div class="band">{html.escape(parts[0])}{small}</div>')
            elif text == "legend":
                legend = f'<div class="cl-legend">{LEGEND}</div>'   # sits above the checklist, outside its margin rule
            elif text.startswith("v:"):
                body = f"<i>&#8730;</i>{html.escape(text[2:].strip())}"
                (box if box is not None else out).append(line("", body, "v", chg))
            elif text.startswith("n:"):
                body = f"({html.escape(text[2:].strip())})"
                (box if box is not None else out).append(line("", body, "n", chg))
            elif text.startswith("if:"):
                if box is not None:
                    raise PackError("an if: inside an if:")
                box, box_head = [], html.escape(text[3:].strip())
            elif text == "end":
                if box is None:
                    raise PackError("end without if:")
                out.append(f'<div class="cif"><div class="cih">IF {box_head}</div>{"".join(box)}</div>')
                box = None
            elif text.startswith("-"):
                fields = [f.strip() for f in text[1:].split("|")]
                want = 2 if box is not None else 3
                if len(fields) != want:
                    raise PackError(f"a step here needs {want} fields separated by |")
                time, ctl, act = ("", *fields) if box is not None else fields
                if ctl and act:
                    body = f"<b>{html.escape(ctl)}</b> &ndash; {html.escape(act)}"
                else:
                    body = f"<b>{html.escape(ctl)}</b>" if ctl else html.escape(act)
                (box if box is not None else out).append(line(time, body, "", chg))
            else:
                raise PackError("unknown directive")
        except PackError as e:
            raise PackError(f"checklist line '{raw.strip()}': {e}")
    if box is not None:
        raise PackError("checklist: if: without end")
    out.append("</div>")
    return legend + chr(10).join(out)


# ---------------------------------------------------------------------------------------------------------------------
# a page
# ---------------------------------------------------------------------------------------------------------------------
def render_body(body):
    holders = []

    def hold(markup):
        holders.append(markup)
        return f"\n\nPACKHOLD{len(holders) - 1}\n\n"

    body = re.sub(r"```checklist\n(.*?)```", lambda m: hold(checklist(m.group(1))), body, flags=re.S)
    body = re.sub(r"^> (NOTE|CAUTION): (.*)$", lambda m: hold(note(m.group(1), m.group(2))), body, flags=re.M)
    body = inline_buttons(body)
    out = markdown.markdown(body, extensions=["tables", "sane_lists"])

    # table classes from <!--table x-->, bands from "== text" rows, and a wrapper so a wide table scrolls on a phone
    out = re.sub(r"<!--table (\w+)-->\s*<table>", r'<table class="\1">', out)

    def bands(m):
        table = m.group(0)
        cols = table.count("<th")
        return re.sub(r"<tr>\s*<td>== (.*?)</td>.*?</tr>",
                      lambda r: f'<tr class="band"><td colspan="{cols}">{r.group(1)}</td></tr>', table, flags=re.S)

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


def page_html(meta, body, number, version):
    sec = "<br>".join(html.escape(s.strip()) for s in meta["section"].split("|"))
    return (f'<div class="page"><div class="hdr"><div><b>LM Guidance Computer</b><span>PILOT\'S PACK</span></div>'
            f'<div class="sec">{sec}</div><div>{html.escape(meta["page"])}</div></div>'
            f'<div class="pb">{render_body(body)}</div>'
            f'<div class="ftr"><span>Release {version}</span><span>LGC-{number}</span></div></div>')


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
  function fit(){
    document.querySelectorAll('.sheet').forEach(function(s){
      var p = s.firstElementChild, z = 1;
      for (var i = 0; i < 8; i++){
        p.style.width = (W / z) + 'px';
        p.style.zoom = z;   /* zoom, not transform: a transform is fragmented at the unscaled height when printed */
        var h = p.getBoundingClientRect().height;
        if (h <= H || z <= 0.4) break;
        z = z * H / h * 0.995;
      }
      s.setAttribute('data-scale', z.toFixed(3));
    });
    document.body.setAttribute('data-fitted', '1');
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit); else window.addEventListener('load', fit);
})();
"""


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


def build_html(pages, sheets):
    css = embed_css((PACK / "pack.css").read_text(encoding="utf-8"))
    if sheets:
        pages = [f'<div class="sheet">{p}</div>' for p in pages]
    body = "\n".join(pages)
    return ("<!doctype html><html lang=\"en-GB\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<title>LM Guidance Computer: Pilot's Pack</title>"
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
        # 1. read back how far each page had to shrink to fit its sheet
        dom = subprocess.run([browser, "--headless=new", "--disable-gpu", "--virtual-time-budget=8000", "--dump-dom", src.as_uri()],
                             check=True, capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
        scales = re.findall(r'data-scale="([\d.]+)"', dom)
        # 2. print it
        subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=8000",
                        f"--print-to-pdf={PDF}", src.as_uri()], check=True, capture_output=True, timeout=120)
    return [float(s) for s in scales]


def main():
    pdf = "--pdf" in sys.argv[1:]
    files = sorted(PACK.glob("*.md"))
    if not files:
        sys.exit(f"no pages in {PACK}")
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    pages, names = [], []
    try:
        for n, f in enumerate(files, 1):
            meta, body = parse_page(f)
            pages.append(page_html(meta, body, n, version))
            names.append(meta["page"])
    except PackError as e:
        sys.exit(f"error: {e}")

    SITE.mkdir(exist_ok=True)
    out = SITE / "index.html"
    out.write_text(build_html(pages, sheets=False), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB, {len(pages)} pages)")
    if PDF.exists() and not pdf:
        shutil.copy2(PDF, SITE / "PACK.pdf")        # the published site links to the PDF committed in docs/

    if pdf:
        scales = make_pdf(pages)
        count = len(re.findall(rb"/Type\s*/Page[^s]", PDF.read_bytes()))
        print(f"wrote {PDF} ({PDF.stat().st_size // 1024} KB, {count} sheets for {len(pages)} pages)")
        bad = False
        if count != len(pages):
            print("WARNING: the sheet count differs from the page count: a page spilled onto a second sheet")
            bad = True
        # what made the first PDF scroll slowly: Type 3 glyph fonts (a variable font, or an unembeddable one) and shading patterns
        # (a CSS gradient). Keep static fonts and plain lines, and these stay at the figures below.
        raw = PDF.read_bytes()
        type3, shades = len(re.findall(rb"/Subtype\s*/Type3", raw)), len(re.findall(rb"/ShadingType", raw))
        if type3 > MAX_TYPE3 or shades:
            print(f"WARNING: the PDF has {type3} Type 3 fonts (the Zerlina digits give {MAX_TYPE3}) and {shades} shading patterns; it will scroll slowly. "
                  "Use static font files (not variable) and no CSS gradients or box shadows in the pages.")
            bad = True
        for name, z in zip(names, scales):
            flag = "  <- too long: split or cut it" if z < MIN_SCALE else ""
            bad = bad or bool(flag)
            if z < 1 or flag:
                print(f"  page {name}: shrunk to {z:.2f}{flag}")
        if len(scales) != len(pages):
            print("WARNING: could not read the fit of every page")
            bad = True
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
