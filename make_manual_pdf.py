"""Build docs/MANUAL.pdf from docs/MANUAL.md: python make_manual_pdf.py

Needs the `markdown` package (pip install markdown) and Microsoft Edge or Google Chrome: the page is rendered to
HTML and printed to PDF by the browser's headless mode. Re-run it whenever docs/MANUAL.md changes.
"""
import pathlib, subprocess, sys, tempfile, re, shutil

try:
    import markdown
except ImportError:
    sys.exit("needs the markdown package: pip install markdown")

root = pathlib.Path(__file__).parent.resolve()
docs = root / "docs"
out = docs / "MANUAL.pdf"

BROWSERS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]
browser = next((b for b in BROWSERS if pathlib.Path(b).exists()), None) or shutil.which("msedge") or shutil.which("chrome")
if not browser:
    sys.exit("needs Microsoft Edge or Google Chrome")

text = (docs / "MANUAL.md").read_text(encoding="utf-8")
# The README link is for the repo; in the PDF it is plain text.
text = text.replace("[README](../README.md)", "README")
body = markdown.markdown(text, extensions=["tables", "fenced_code", "toc", "sane_lists"])

CSS = """
@page { size: A4; margin: 18mm 16mm 20mm 16mm;
        @bottom-center { content: counter(page); font: 9pt Segoe UI, Arial, sans-serif; color: #666; } }
body { font: 10.5pt/1.45 "Segoe UI", Arial, sans-serif; color: #1a1a1a; }
h1 { font-size: 22pt; margin: 0 0 4pt; border-bottom: 2px solid #2a6f97; padding-bottom: 4pt; }
h2 { font-size: 15pt; margin: 18pt 0 6pt; color: #1d4e6b; border-bottom: 1px solid #c8d6df; padding-bottom: 2pt; break-after: avoid; }
h3 { font-size: 12pt; margin: 12pt 0 4pt; color: #1d4e6b; break-after: avoid; }
h4 { font-size: 10.5pt; margin: 10pt 0 3pt; break-after: avoid; }
p, li { orphans: 3; widows: 3; }
code { font: 9.5pt Consolas, "Courier New", monospace; background: #eef2f5; padding: 0 3px; border-radius: 3px; white-space: nowrap; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; break-inside: auto; font-size: 9.5pt; }
tr { break-inside: avoid; }
th, td { border: 1px solid #c8d6df; padding: 3pt 6pt; text-align: left; vertical-align: top; }
th { background: #e4edf3; }
blockquote { margin: 8pt 0; padding: 6pt 10pt; background: #fff4e0; border-left: 4px solid #e0a030; }
blockquote p { margin: 0; }
img { max-width: 62%; display: block; margin: 8pt auto 2pt; border: 1px solid #c8d6df; }
em { color: #444; }
a { color: #1d4e6b; text-decoration: none; }
ul { padding-left: 18pt; } ol { padding-left: 20pt; }
"""
html = (f'<!doctype html><html><head><meta charset="utf-8"><title>LM Guidance Computer: Pilot\'s Manual</title>'
        f'<base href="{docs.as_uri()}/"><style>{CSS}</style></head><body>{body}</body></html>')

with tempfile.TemporaryDirectory() as tmp:
    page = pathlib.Path(tmp) / "manual.html"
    page.write_text(html, encoding="utf-8")
    cmd = [browser, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
           f"--print-to-pdf={out}", page.as_uri()]
    subprocess.run(cmd, check=True, capture_output=True, timeout=120)

print(f"wrote {out} ({out.stat().st_size // 1024} KB)")
