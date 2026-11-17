"""reference_alarm.py -- the alarm facility's numbers, in Python, to check the kOS code against.

Slot rule (Luminary ALARM_AND_ABORT.agc, ALARM): the first alarm goes in slot 1, the second in slot 2, the third in
slot 3; a later one replaces slot 3 with bit 15 added (here the code plus 40000, the codes being written as the octal
digits the DSKY shows). Run: python scripts/tests/reference_alarm.py
"""

BIT15 = 40000          # bit 15 written in octal digits


def alarm_raise(codes, code):
    """codes: list of three ints. Returns the new list (the old one is not changed)."""
    out = list(codes)
    for i in range(3):
        if out[i] == 0:
            out[i] = code
            return out
    out[2] = code + BIT15 if code < BIT15 else code      # multiple failure: slot 3 carries bit 15
    return out


def alarm_text(code):
    return str(code).zfill(5)


SEQUENCES = [
    [1406],
    [1202, 1201],
    [1202, 1201, 1406],
    [1202, 1201, 1406, 1210],
    [1202, 1201, 1406, 1210, 1202],
]

if __name__ == "__main__":
    for seq in SEQUENCES:
        codes = [0, 0, 0]
        for c in seq:
            codes = alarm_raise(codes, c)
        print(seq, "->", [alarm_text(c) for c in codes])
    assert alarm_text(1202) == "01202" and alarm_text(41210) == "41210"


# ---- the scripted alarms (lm_alarms.ks): parse and due ----

A11_SCRIPT = [(301, 1202), (364, 1202), (560, 1201), (585, 1202), (600, 1202)]


def alarm_script_parse(text, profile):
    clean = text.strip().upper()
    if clean in ("OFF", ""):
        return []
    if clean == "A11":
        return list(A11_SCRIPT) if profile == "A11" else []
    sched = []
    for item in clean.split(","):
        pair = item.strip().split("@")
        if len(pair) != 2:
            return None
        code_text = pair[0].strip()
        try:
            code = int(code_text)
            seconds = float(pair[1].strip())
        except ValueError:
            return None
        if len(code_text) != 4 or code < 0 or seconds < 0:
            return None
        sched.append((seconds, code))
    return sorted(sched, key=lambda e: e[0])        # stable: equal times keep their typed order


def alarm_script_due(sched, t_last, t_now):
    return [code for (t, code) in sched if t_last < t <= t_now]


if __name__ == "__main__":
    print("parse A11:", alarm_script_parse("A11", "A11"))
    print("parse A11 on J:", alarm_script_parse("A11", "J"))
    print("parse 1202@315,1201@548:", alarm_script_parse("1202@315,1201@548", "A11"))
    print("parse abc:", alarm_script_parse("abc", "A11"), " parse 1202@:", alarm_script_parse("1202@", "A11"))
    s = alarm_script_parse("A11", "A11")
    for a, b in [(299, 302), (300, 301), (301, 363), (363, 365), (0, 700)]:
        print("due", (a, b), alarm_script_due(s, a, b))
    assert alarm_script_parse("A11", "A11") == A11_SCRIPT and alarm_script_parse("A11", "J") == []
    assert alarm_script_due(s, 299, 302) == [1202] and alarm_script_due(s, 300, 301) == [1202]
    assert alarm_script_due(s, 301, 363) == [] and alarm_script_due(s, 363, 365) == [1202]
    assert alarm_script_due(s, 0, 700) == [1202, 1202, 1201, 1202, 1202]
    assert alarm_script_parse("abc", "A11") is None and alarm_script_parse("1202@", "A11") is None
