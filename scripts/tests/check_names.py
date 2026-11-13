"""Find KerboScript variable/parameter names that clash with a kOS built-in function.

kOS refuses to load a file that creates a name like V, R or Q (built-in functions),
with "Not allowed to SET a name that will clobber or hide the BUILTIN_FUNCTION".

It also reports a FUNCTION whose name equals a GLOBAL/LOCAL variable name anywhere in the scripts: kOS names are
case-insensitive, so GUI_KEEP the list and gui_keep the function are the same name, and the call fails with
"called with not enough arguments".

Run from the repo root:   python scripts/tests/check_names.py
Exit code 0 = no clashes, 1 = clashes found (each printed with file and line).

kos_builtins.txt (same folder) holds the built-in names, taken from the kOS source
([Function("...")] attributes). Names are matched case-insensitively, like KerboScript.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
BUILTINS = {line.strip() for line in (HERE / "kos_builtins.txt").read_text().splitlines() if line.strip()}

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
# Statements that create or assign a name. Group 1 holds the name(s) that follow.
PATTERNS = [
    re.compile(rf"\bPARAMETER\s+({IDENT}(?:\s*,\s*{IDENT}(?:\s+IS\s+[^,.]+)?)*)", re.I),
    re.compile(rf"\b(?:LOCAL|GLOBAL|DECLARE)\s+(?:LOCAL\s+|GLOBAL\s+|PARAMETER\s+)?({IDENT})", re.I),
    re.compile(rf"\bFOR\s+({IDENT})\s+IN\b", re.I),
    re.compile(rf"\bSET\s+({IDENT})\s+TO\b", re.I),
    # LOCK STEERING / THROTTLE / WHEELSTEERING / WHEELTHROTTLE are kOS's documented flight-control locks
    # (docs commands/flight/cooked.rst), not new names: they are not clashes.
    re.compile(rf"\bLOCK\s+(?!(?:STEERING|THROTTLE|WHEELSTEERING|WHEELTHROTTLE)\b)({IDENT})\s+TO\b", re.I),
    re.compile(rf"\bFUNCTION\s+({IDENT})", re.I),
]


def strip_noise(line: str) -> str:
    """Remove strings and // comments so words inside them are not scanned."""
    line = re.sub(r'"[^"]*"', '""', line)
    return line.split("//")[0]


def names_in(text: str):
    for pattern in PATTERNS:
        for match in pattern.finditer(text):
            # A PARAMETER statement may list several names: "PARAMETER a, b, c."
            for part in match.group(1).split(","):
                found = re.match(rf"\s*({IDENT})", part)
                if found:
                    yield found.group(1)


def main() -> int:
    clashes = 0
    functions = {}   # lower-case function name -> where it is defined
    variables = {}   # lower-case GLOBAL/LOCAL variable name -> where it is created
    for path in sorted(SCRIPTS.rglob("*.ks")):
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            text = strip_noise(raw)
            where = f"{path.relative_to(SCRIPTS.parent)}:{number}"
            for match in re.finditer(rf"\bFUNCTION\s+({IDENT})", text, re.I):
                functions.setdefault(match.group(1).lower(), where)
            for match in re.finditer(rf"\b(?:LOCAL|GLOBAL)\s+({IDENT})\s+IS\b", text, re.I):
                variables.setdefault(match.group(1).lower(), where)
    for name in sorted(functions.keys() & variables.keys()):
        clashes += 1
        print(f"{functions[name]}: function '{name}' has the same name as the variable at {variables[name]}")
    for path in sorted(SCRIPTS.rglob("*.ks")):
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for name in names_in(strip_noise(raw)):
                if name.lower() in BUILTINS:
                    clashes += 1
                    print(f"{path.relative_to(SCRIPTS.parent)}:{number}: '{name}' hides built-in {name.upper()}()")
    print("no clashes" if clashes == 0 else f"{clashes} clash(es)")
    return 1 if clashes else 0


if __name__ == "__main__":
    sys.exit(main())
