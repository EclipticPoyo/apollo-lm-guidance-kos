"""Build the manual as a web page for GitHub Pages: python make_site.py

Writes site/index.html (the pilot's manual, from docs/MANUAL.md), site/images/ and site/MANUAL.pdf.
Needs the `markdown` package (pip install markdown). The GitHub Actions workflow pages.yml runs this and publishes site/.
Nothing here is edited by hand: change docs/MANUAL.md and build again. site/ is git-ignored.
"""
import pathlib, shutil, sys

try:
    import markdown
except ImportError:
    sys.exit("needs the markdown package: pip install markdown")

root = pathlib.Path(__file__).parent.resolve()
docs = root / "docs"
site = root / "site"

REPO = "https://github.com/EclipticPoyo/apollo-lm-guidance-kos"
version = (root / "VERSION").read_text(encoding="utf-8").strip()
text = (docs / "MANUAL.md").read_text(encoding="utf-8").replace("\r\n", "\n")
text = text.replace("[README](../README.md)", f"[README]({REPO}#readme)")
# Same banner as the wiki: which release the manual matches, plus the PDF and source links.
text = text.replace("# LM Guidance Computer: Pilot's Manual\n",
                    f"# LM Guidance Computer: Pilot's Manual\n\n**Manual for release [v{version}]({REPO}/releases/tag/v{version})** · "
                    f"[Download as PDF](MANUAL.pdf) · [Source code]({REPO})\n", 1)
body = markdown.markdown(text, extensions=["tables", "fenced_code", "toc", "sane_lists"])

CSS = """
:root { color-scheme: light dark; --fg:#1a1a1a; --bg:#fff; --accent:#1d4e6b; --line:#c8d6df; --code:#eef2f5; --note:#fff4e0; }
@media (prefers-color-scheme: dark) {
  :root { --fg:#e6e6e6; --bg:#15191c; --accent:#7fb8d8; --line:#33414a; --code:#222b31; --note:#3a2f1a; }
}
body { font: 16px/1.55 system-ui, "Segoe UI", Arial, sans-serif; color: var(--fg); background: var(--bg); margin: 0; }
main { max-width: 56rem; margin: 0 auto; padding: 1rem 16px 4rem; }
h1 { border-bottom: 2px solid var(--accent); padding-bottom: .25rem; }
h2 { color: var(--accent); border-bottom: 1px solid var(--line); padding-bottom: .15rem; margin-top: 2.2rem; }
h3, h4 { color: var(--accent); }
a { color: var(--accent); }
code { font: .92em Consolas, "Courier New", monospace; background: var(--code); padding: 0 .25em; border-radius: 3px; }
pre { background: var(--code); padding: .6rem .8rem; overflow-x: auto; border-radius: 4px; }
pre code { padding: 0; background: none; }
table { border-collapse: collapse; display: block; overflow-x: auto; margin: .8rem 0; }
th, td { border: 1px solid var(--line); padding: .25rem .6rem; text-align: left; vertical-align: top; }
th { background: var(--code); }
blockquote { margin: 1rem 0; padding: .4rem .9rem; background: var(--note); border-left: 4px solid #e0a030; }
blockquote p { margin: .3rem 0; }
img { max-width: 100%; height: auto; border: 1px solid var(--line); }
"""
html = ('<!doctype html><html lang="en-GB"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>LM Guidance Computer: Pilot's Manual</title>"
        f"<style>{CSS}</style></head><body><main>{body}</main></body></html>")

if site.exists():
    shutil.rmtree(site)
site.mkdir()
(site / "index.html").write_text(html, encoding="utf-8")
shutil.copytree(docs / "images", site / "images", ignore=shutil.ignore_patterns("Thumbs.db", "desktop.ini", ".DS_Store"))
pdf = docs / "MANUAL.pdf"
if pdf.exists():
    shutil.copy2(pdf, site / "MANUAL.pdf")
else:
    print("note: docs/MANUAL.pdf not found; the PDF link on the page will be dead (python make_manual_pdf.py builds it)")
(site / ".nojekyll").write_text("", encoding="utf-8")
print(f"wrote {site / 'index.html'} ({len(html) // 1024} KB)")
