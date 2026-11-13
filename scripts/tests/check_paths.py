"""Check that every script path in a RUNPATH / RUNONCEPATH call exists.

kOS only finds a missing file when the line runs, which can be in the middle of a flight. This reads every
scripts/**/*.ks and, for each RUNPATH("0:/...") or RUNONCEPATH("0:/...") with a plain quoted path, checks that
scripts/<path after 0:/> exists (scripts/ is the archive volume 0:). A path built with + is not a literal, so it is
skipped, and so are // comment lines. Only RUNPATH and RUNONCEPATH are checked (not EXISTS, LOG or DELETEPATH, whose
targets may legitimately not exist yet).

Run from the repo root:   python scripts/tests/check_paths.py
Exit code 0 = every target exists, 1 = a target is missing (printed as file:line: missing target).
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent

# RUNPATH("0:/dir/file.ks" ...) or RUNONCEPATH("0:/dir/file.ks" ...); group 1 is the quoted path.
# A "+" right after the closing quote means the path is built from pieces, so it is not a literal.
CALL = re.compile(r'\b(?:RUNPATH|RUNONCEPATH)\s*\(\s*"([^"]*)"\s*(?!\+)', re.I)


def main() -> int:
    missing = 0
    for path in sorted(SCRIPTS.rglob("*.ks")):
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw.lstrip().startswith("//"):
                continue
            code = raw.split("//")[0]   # paths hold single slashes only, so this only cuts trailing comments
            for match in CALL.finditer(code):
                target = match.group(1)
                if not target.startswith("0:/"):
                    continue
                relative = target[3:]
                found = SCRIPTS / relative
                if not found.exists() and not (SCRIPTS / (relative + ".ks")).exists():
                    missing += 1
                    print(f"{path.relative_to(SCRIPTS.parent)}:{number}: missing target {target}")
    print("all paths resolve" if missing == 0 else f"{missing} missing target(s)")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
