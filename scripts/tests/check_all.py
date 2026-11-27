"""check_all.py: every offline check in one go (no KSP needed).  Run: python scripts/tests/check_all.py

Runs check_names, check_syntax, check_paths and check_pack, then checks that run_all.ks (RUN pad.) lists every pad test:
each test_*.ks here, except the helper test_lib.ks, must be in its ra_names list, and every name listed must have a file.
Exit code 0 when everything passes, 1 otherwise.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHECKS = ("check_names.py", "check_syntax.py", "check_paths.py", "check_pack.py")
HELPERS = {"test_lib"}      # loaded by the tests, not a test itself


def pad_test_problems():
    runner = (HERE / "run_all.ks").read_text(encoding="utf-8")
    found = re.search(r"LOCAL ra_names IS LIST\((.*?)\)\.", runner, re.S)
    if not found:
        return ["run_all.ks: the ra_names list was not found"]
    listed = set(re.findall(r'"(test_\w+)"', found.group(1)))
    files = {p.stem.lower() for p in HERE.glob("test_*.ks")} - HELPERS
    problems = [f"{name}.ks is not in ra_names (run_all.ks), so RUN pad. skips it" for name in sorted(files - listed)]
    problems += [f"run_all.ks lists {name}, but there is no {name}.ks" for name in sorted(listed - files)]
    return problems


def main():
    failed = []
    for name in CHECKS:
        print(f"== {name}", flush=True)
        if subprocess.run([sys.executable, str(HERE / name)]).returncode != 0:
            failed.append(name)
    print("== pad test list")
    problems = pad_test_problems()
    print(f"pad test list: {len(problems)} problem(s)")
    for p in problems:
        print("  " + p)
    if problems:
        failed.append("pad test list")
    print("ALL CHECKS PASSED" if not failed else "FAILED: " + ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
