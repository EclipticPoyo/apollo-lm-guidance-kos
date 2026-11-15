"""Cheap offline syntax check for the kOS scripts: balanced { } ( ) [ ] and no unterminated string.

kOS reports a syntax error only when the file is loaded in KSP, so this catches the commonest slip (a missing or extra
bracket, a string left open) before a flight. It ignores // comments and the contents of "strings". It is not a parser:
a missing full stop is not found. Each file is checked on its own.

Run from the repo root:   python scripts/tests/check_syntax.py
Exit code 0 = every file balanced, 1 = a problem (printed as file:line: what).
"""
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
PAIRS = {")": "(", "]": "[", "}": "{"}


def check_text(text):
    """Return a list of (line, message) for one file's text."""
    problems = []
    stack = []                      # (char, line) of each open bracket
    line_no = 1
    in_string = False
    string_line = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\n":
            if in_string:           # kOS strings cannot span lines
                problems.append((string_line, "unterminated string"))
                in_string = False
            line_no += 1
        elif in_string:
            if ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            string_line = line_no
        elif ch == "/" and text[i + 1:i + 2] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        elif ch in "({[":
            stack.append((ch, line_no))
        elif ch in PAIRS:
            if not stack:
                problems.append((line_no, "unmatched " + ch))
            elif stack[-1][0] != PAIRS[ch]:
                problems.append((line_no, "mismatched " + ch + " (opened " + stack[-1][0] + " on line " + str(stack[-1][1]) + ")"))
                stack.pop()
            else:
                stack.pop()
        i += 1
    if in_string:
        problems.append((string_line, "unterminated string"))
    for ch, ln in stack:
        problems.append((ln, "unclosed " + ch))
    return problems


def main():
    bad = 0
    for path in sorted(SCRIPTS.rglob("*.ks")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for line, msg in check_text(text):
            print(str(path.relative_to(SCRIPTS.parent)) + ":" + str(line) + ": " + msg)
            bad += 1
    if bad == 0:
        print("check_syntax: all .ks files balanced")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
