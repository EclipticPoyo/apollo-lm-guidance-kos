"""Build the release zip: python make_release.py [version]

The zip unzips straight into the KSP folder:
  Ships/Script/dsky.ks           the stub that runs the DSKY (RUN dsky.)
  Ships/Script/plan.ks           the stub that opens the planner (RUN plan.)
  Ships/Script/boot/lm_boot.ks   an optional boot file that selects the archive, so SWITCH TO 0. is not needed
  Ships/Script/agc_config.txt    the settings file for the whole project (an old lm/lm_config.txt is no longer shipped)
  Ships/Script/core, lm (with descent/, planner/, images/, an empty logs/), shared   from scripts/ (no tests/)
  README.md, CHANGELOG.md, docs/PACK.pdf, docs/images/*   the readme and the pilot's pack (the manual)
VERSION (the version defaults to it, and a different argument is refused).
Output: dist/apollo-lm-guidance-kos-<version>.zip (dist/ is git-ignored). The lowercase name is an aesthetic preference.
"""
import sys, zipfile, pathlib

root = pathlib.Path(__file__).parent
file_version = (root / "VERSION").read_text(encoding="utf-8").strip()   # bump VERSION first; the wiki manual shows it too
version = sys.argv[1] if len(sys.argv) > 1 else file_version
if version != file_version:
    sys.exit(f"refusing: asked for {version} but VERSION says {file_version}. Edit VERSION first.")
out_dir = root / "dist"
out_dir.mkdir(exist_ok=True)
out = out_dir / f"apollo-lm-guidance-kos-{version}.zip"

STUB = '// dsky.ks -- runs the DSKY (Ships/Script/core/dsky.ks, seen here as 0:/core/dsky.ks).\nRUNPATH("0:/core/dsky.ks").\n'
PLAN_STUB = '// plan.ks -- opens the LM planner (Ships/Script/lm/planner/lm_plan_ui.ks, seen here as 0:/lm/planner/lm_plan_ui.ks).\nRUNPATH("0:/lm/planner/lm_plan_ui.ks").\n'
# Files the DSKY and planner write while running (the dev machine's own clock zero, loads and uplink): never shipped.
RUNTIME_FILES = ("clock.txt", "store.txt", "uplink.txt", "profile.txt", "ascent.json")
# scripts/ mirrors the archive volume 0:, so scripts/<folder>/<file> ships as Ships/Script/<folder>/<file>. tests/ stays out.
files = []
for folder in ("core", "lm", "shared", "boot"):
    for p in sorted((root / "scripts" / folder).rglob("*")):
        if p.is_file() and p.suffix in (".ks", ".png", ".txt") and p.name not in RUNTIME_FILES:
            if p.name == "lm_config.txt":        # the old settings file stays in the repo but is replaced by agc_config.txt
                continue
            files.append((p, f"Ships/Script/{p.relative_to(root / 'scripts').as_posix()}"))
files.append((root / "scripts" / "agc_config.txt", "Ships/Script/agc_config.txt"))   # the settings file, at the top of Ships/Script
files += [(root / "VERSION", "VERSION"), (root / "README.md", "README.md"), (root / "CHANGELOG.md", "CHANGELOG.md"), (root / "docs" / "PACK.pdf", "docs/PACK.pdf")]
files += [(p, f"docs/images/{p.name}") for p in sorted((root / "docs" / "images").glob("*.png"))]

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("Ships/Script/dsky.ks", STUB)
    z.writestr("Ships/Script/plan.ks", PLAN_STUB)
    z.writestr("Ships/Script/lm/logs/", "")      # an empty folder for the logs (kOS also makes it if missing)
    for src, name in files:
        z.write(src, name)
print(f"wrote {out} ({len(files) + 2} files)")
