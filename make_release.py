"""Build the release zip: python make_release.py [version]

The zip unzips straight into the KSP folder:
  Ships/Script/dsky.ks           the stub that runs the DSKY (RUN dsky.)
  Ships/Script/plan.ks           the stub that opens the planner (RUN plan.)
  Ships/Script/boot/lm_boot.ks   an optional boot file that selects the archive, so SWITCH TO 0. is not needed
  Ships/Script/core, lm (with descent/, planner/, images/, lm_config.txt, an empty logs/), shared   from scripts/ (no tests/)
  README.md, CHANGELOG.md, docs/MANUAL.md, docs/MANUAL.pdf (if built), docs/images/*   the readme and the pilot's manual
Output: dist/apollo-lm-guidance-kos-<version>.zip (dist/ is git-ignored). The lowercase name is an aesthetic preference.
"""
import sys, zipfile, pathlib

root = pathlib.Path(__file__).parent
version = sys.argv[1] if len(sys.argv) > 1 else "dev"
out_dir = root / "dist"
out_dir.mkdir(exist_ok=True)
out = out_dir / f"apollo-lm-guidance-kos-{version}.zip"

STUB = '// dsky.ks -- runs the DSKY (Ships/Script/core/dsky.ks, seen here as 0:/core/dsky.ks).\nRUNPATH("0:/core/dsky.ks").\n'
PLAN_STUB = '// plan.ks -- opens the deorbit planner (Ships/Script/lm/planner/lm_plan_ui.ks, seen here as 0:/lm/planner/lm_plan_ui.ks).\nRUNPATH("0:/lm/planner/lm_plan_ui.ks").\n'
# scripts/ mirrors the archive volume 0:, so scripts/<folder>/<file> ships as Ships/Script/<folder>/<file>. tests/ stays out.
files = []
for folder in ("core", "lm", "shared", "boot"):
    for p in sorted((root / "scripts" / folder).rglob("*")):
        if p.is_file() and p.suffix in (".ks", ".png", ".txt"):
            files.append((p, f"Ships/Script/{p.relative_to(root / 'scripts').as_posix()}"))
files += [(root / "README.md", "README.md"), (root / "CHANGELOG.md", "CHANGELOG.md"), (root / "docs" / "MANUAL.md", "docs/MANUAL.md")]
if (root / "docs" / "MANUAL.pdf").exists():
    files.append((root / "docs" / "MANUAL.pdf", "docs/MANUAL.pdf"))
files += [(p, f"docs/images/{p.name}") for p in sorted((root / "docs" / "images").glob("*.png"))]

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("Ships/Script/dsky.ks", STUB)
    z.writestr("Ships/Script/plan.ks", PLAN_STUB)
    z.writestr("Ships/Script/lm/logs/", "")      # an empty folder for the logs (kOS also makes it if missing)
    for src, name in files:
        z.write(src, name)
print(f"wrote {out} ({len(files) + 2} files)")
