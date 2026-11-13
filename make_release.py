"""Build the release zip: python make_release.py [version]

The zip unzips straight into the KSP folder:
  Ships/Script/start.ks          the stub that runs the starter
  Ships/Script/lm/*.ks, *.png    the LM computer and its lamp images (scripts/lm_*.ks; no tests/)
  README.md, docs/MANUAL.md, docs/images/*   the readme and the pilot's manual
Output: dist/Apollo-LM-Guidance-kOS-<version>.zip (dist/ is git-ignored).
"""
import sys, zipfile, pathlib

root = pathlib.Path(__file__).parent
version = sys.argv[1] if len(sys.argv) > 1 else "dev"
out_dir = root / "dist"
out_dir.mkdir(exist_ok=True)
out = out_dir / f"Apollo-LM-Guidance-kOS-{version}.zip"

STUB = '// start.ks -- runs the LM starter (Ships/Script/lm/lm_start.ks, seen here as 0:/lm/).\nRUNPATH("0:/lm/lm_start.ks").\n'
files = [(p, f"Ships/Script/lm/{p.name}") for p in sorted((root / "scripts").glob("lm_*.ks"))]
files += [(p, f"Ships/Script/lm/{p.name}") for p in sorted((root / "scripts").glob("*.png"))]
files += [(root / "README.md", "README.md"), (root / "docs" / "MANUAL.md", "docs/MANUAL.md")]
files += [(p, f"docs/images/{p.name}") for p in sorted((root / "docs" / "images").glob("*.png"))]

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("Ships/Script/start.ks", STUB)
    for src, name in files:
        z.write(src, name)
print(f"wrote {out} ({len(files) + 1} files)")
