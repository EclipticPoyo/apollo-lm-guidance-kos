"""test_pads_page.py: browser tests of the PAD forms page.  Needs Microsoft Edge or Google Chrome; not run in CI.

    python scripts/tests/test_pads_page.py [--browser PATH]     behaviour tests, headless
    python scripts/tests/test_pads_page.py --shots DIR [--dark] [--short]   one PNG per card, and narrow.png

The tests run inside a temporary copy of the page: a script put in front of the page's own sets up the browser (broken or
blocked storage), a script after it drives window.Pads and the page's controls and writes PASS or FAIL lines.
"""
import argparse
import html
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "pads.html"
sys.path.insert(0, str(ROOT))
from make_pack import find_browser      # noqa: E402

BEFORE = r"""<script>
window.testErrors = [];
window.addEventListener("error", e => window.testErrors.push(String(e.message)));
const testMode = location.hash.slice(1) || "main";
if (testMode === "main") localStorage.clear();
if (testMode === "badjson") localStorage.setItem("lm-pads-v1", "not json");
if (testMode === "oldbox") localStorage.setItem("lm-pads-v1", '{"gone.box":"1","p30.n33.0.0.3":"12","p30.n33.0.0.4":7}');
if (testMode === "full") localStorage.setItem("lm-pads-short", "0");
if (testMode === "v210") localStorage.setItem("lm-pads-version", "210");
if (testMode === "dark") localStorage.setItem("pack-theme", "dark");
if (testMode === "blocked") Storage.prototype.setItem = function () { throw new Error("storage blocked"); };
</script>
"""

AFTER = r"""<pre id="results"></pre>
<script>
(function () {
const out = document.getElementById("results");
const R = "p30.n33.0.0";                       // the N33 hour row, column 0
const KEY = "lm-pads-v1";
const stored = () => JSON.parse(localStorage.getItem(KEY) || "{}");
const el = id => document.querySelector('[data-id="' + id + '"]');
const same = (got, want, what) => {
  if (got !== want) throw new Error(what + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want));
};
const drawn = () => {
  const cards = JSON.parse(document.getElementById("cards").textContent);
  same(document.querySelectorAll(".card").length, cards.length, "cards drawn");
  document.querySelectorAll(".card").forEach(c => same(c.querySelectorAll("[data-id]").length > 0, true, "boxes on " + c.dataset.card));
};
const test = (name, body) => {
  try {
    if (testMode !== "persist") Pads.clearCard("p30");
    body();
    same(window.testErrors.join("; "), "", "page errors");
    out.textContent += "PASS " + name + "\n";
  } catch (err) {
    out.textContent += "FAIL " + name + " (" + err.message + ")\n";
  }
};

if (testMode === "main") {
  test("draws", drawn);
  test("type_advances", () => {
    same(Pads.type(R + ".3", "1"), R + ".4", "next box");
    same(Pads.value(R + ".3"), "1", "shown");
    same(stored()[R + ".3"], "1", "stored");
  });
  test("type_refused", () => {
    same(Pads.type(R + ".3", "a"), R + ".3", "next box");
    same(Pads.value(R + ".3"), "", "shown");
    same(stored()[R + ".3"], undefined, "stored");
  });
  test("type_crosses_rows", () => same(Pads.type(R + ".5", "9"), "p30.n33.0.1.4", "next box"));
  test("minus_normalised", () => {
    const sign = "p30.n42.0.1.0";
    Pads.type(sign, "−");
    same(Pads.value(sign), "-", "minus sign");
    Pads.set(sign, "");
    Pads.type(sign, "–");
    same(Pads.value(sign), "-", "dash");
    same(Pads.type(sign, "5"), sign, "a digit in a sign box");
  });
  test("octal", () => {
    const box = "p27.data.0.1.0";
    same(Pads.type(box, "8"), box, "an 8 in an octal box");
    same(Pads.value(box), "", "shown");
    same(Pads.type(box, "7"), "p27.data.0.1.1", "next box");
    Pads.clearCard("p27");
  });
  test("back_clears_previous", () => {
    Pads.set(R + ".4", "7");
    same(Pads.back(R + ".5"), R + ".4", "previous box");
    same(Pads.value(R + ".4"), "", "emptied");
    Pads.set(R + ".5", "3");
    same(Pads.back("p30.n33.0.1.4"), R + ".5", "previous row");
    same(Pads.value(R + ".5"), "", "emptied");
  });
  test("paste_by_position", () => {
    Pads.paste(R + ".0", "+00123");
    same([3, 4, 5].map(i => Pads.value(R + "." + i)).join(""), "123", "entry boxes");
    same(Object.keys(stored()).filter(k => k.startsWith("p30.")).length, 3, "boxes stored");
  });
  test("paste_register_on_first_entry_box", () => {
    Pads.paste(R + ".3", "+00045");
    same([3, 4, 5].map(i => Pads.value(R + "." + i)).join(""), "045", "entry boxes");
    Pads.clearCard("p30");
    Pads.paste("p30.n33.0.2.2", "+045.00");
    same([2, 3, 4, 5].map(i => Pads.value("p30.n33.0.2." + i)).join(""), "4500", "point in the pasted text");
  });
  test("paste_part_of_a_row", () => {
    Pads.paste(R + ".4", "89012");
    same([3, 4, 5].map(i => Pads.value(R + "." + i) || "-").join(""), "-89", "entry boxes");
    same(Pads.value("p30.n33.0.1.4"), "", "next row untouched");
  });
  test("clear_card_only", () => {
    localStorage.setItem(KEY, JSON.stringify({ "x.y": "1" }));
    Pads.set(R + ".3", "4");
    Pads.set("p30.remarks", "note");
    Pads.clearCard("p30");
    same(Object.keys(stored()).join(","), "x.y", "keys left");
    same(Pads.value(R + ".3") + Pads.value("p30.remarks"), "", "shown");
  });
  test("two_tabs", () => {
    Pads.set(R + ".3", "1");
    const other = stored();
    other["x.tab"] = "9";
    localStorage.setItem(KEY, JSON.stringify(other));
    Pads.set(R + ".4", "4");
    same(stored()["x.tab"], "9", "the other tab's box");
    same(stored()[R + ".3"], "1", "the first box");
    same(stored()[R + ".4"], "4", "the new box");
  });
  test("keyboard_wiring", () => {
    const box = el(R + ".3");
    box.focus();
    box.value = "5";
    box.dispatchEvent(new InputEvent("input", { data: "5", inputType: "insertText", bubbles: true }));
    same(Pads.value(R + ".3"), "5", "typed");
    same(document.activeElement.dataset.id, R + ".4", "focus moved");
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: "Backspace", bubbles: true, cancelable: true }));
    same(document.activeElement.dataset.id, R + ".3", "focus moved back");
    same(Pads.value(R + ".3"), "", "emptied");
    box.value = "q";
    box.dispatchEvent(new InputEvent("input", { data: "q", inputType: "insertText", bubbles: true }));
    same(box.value, "", "refused character not shown");
    const data = new DataTransfer();
    data.setData("text/plain", "+00123");
    box.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    same([3, 4, 5].map(i => el(R + "." + i).value).join(""), "123", "pasted");
    const remarks = el("p30.remarks");
    remarks.value = "free text, 12";
    remarks.dispatchEvent(new InputEvent("input", { data: "2", inputType: "insertText", bubbles: true }));
    same(stored()["p30.remarks"], "free text, 12", "remarks saved");
  });
  test("tab_order", () => {
    const ids = [...document.querySelectorAll('[data-card="p30"] [data-id]')].map(e => e.dataset.id)
      .filter(i => i.startsWith("p30.n33."));
    same(ids.slice(0, 4).join(" "), [R + ".3", R + ".4", R + ".5", "p30.n33.0.1.4"].join(" "), "first boxes");
    same(ids[ids.length - 1], "p30.n33.1.2.5", "last box");
  });
  test("buttons", () => {
    const button = name => [...document.querySelectorAll("#card-p30 button")].find(b => b.textContent === name);
    const confirmWas = window.confirm, printWas = window.print;
    Pads.set(R + ".3", "4");
    window.confirm = () => false;
    button("Clear").click();
    same(Pads.value(R + ".3"), "4", "kept when refused");
    window.confirm = () => true;
    button("Clear").click();
    same(Pads.value(R + ".3"), "", "cleared");
    let printed = null;
    window.print = () => { printed = document.body.dataset.print; };
    button("Print").click();
    same(printed, "p30", "printing one card");
    same(document.getElementById("card-p30").classList.contains("printing"), true, "card marked");
    window.dispatchEvent(new Event("afterprint"));
    same(document.body.dataset.print, undefined, "mark cleared");
    same(document.querySelectorAll(".printing").length, 0, "card unmarked");
    printed = "none";
    document.getElementById("print-all").click();
    same(printed, undefined, "printing all");
    window.confirm = confirmWas;
    window.print = printWas;
  });
  test("clear_all", () => {
    const button = document.getElementById("clear-all"), confirmWas = window.confirm;
    const doi = "doi.n33.0.0.3";
    localStorage.setItem("pack-theme", "light");
    Pads.set(R + ".3", "4");
    Pads.set(doi, "7");
    window.confirm = () => false;
    button.click();
    same(Pads.value(R + ".3") + Pads.value(doi), "47", "kept when refused");
    window.confirm = () => true;
    button.click();
    same(Pads.value(R + ".3") + Pads.value(doi), "", "every card cleared");
    same(Object.keys(stored()).filter(k => !k.startsWith("x.")).join(","), "", "boxes stored (x.* are other tests' own)");
    same(localStorage.getItem("pack-theme"), "light", "the theme choice stays");
    window.confirm = confirmWas;
  });
  const seen = id => el(id).offsetParent !== null;
  const switchTo = short => {
    if (document.body.classList.contains("short") !== short) document.getElementById("short").click();
  };
  const HIDDEN = "p30.fdai.0.0.3", KEPT = "p30.n33.0.0.3";
  test("short_button", () => {
    const button = document.getElementById("short");
    same(document.body.classList.contains("short"), true, "opens on short cards");
    same(button.textContent, "Full cards", "label on short cards");
    same(seen(HIDDEN), false, "box on the short card");
    same(seen(KEPT), true, "a box the computer uses");
    button.click();
    same(button.textContent, "Short cards", "label on full cards");
    same(localStorage.getItem("lm-pads-short"), "0", "choice kept");
    same(seen(HIDDEN), true, "box on the full card");
    Pads.set(HIDDEN, "5");
    button.click();
    same(localStorage.getItem("lm-pads-short"), "1", "choice kept");
    same(seen(HIDDEN), false, "box hidden again");
    button.click();
    same(Pads.value(HIDDEN), "5", "what was typed in it");
    switchTo(true);
    Pads.clearCard("p30");
    same(Pads.value(HIDDEN), "", "Clear empties hidden boxes too");
  });
  test("short_skips_hidden", () => {
    const last = "p30.n42.1.2.5";
    switchTo(false);
    same(Pads.type(last, "1"), "p30.bt.0.0.3", "next box on the full card");
    switchTo(true);
    same(Pads.type(last, "2"), "p30.remarks", "next box on the short card");
    same(Pads.back("p30.remarks"), last, "previous box on the short card");
    switchTo(false);
  });
  test("short_condensed", () => {
    const card = () => document.querySelector('.card[data-card="p30"]').getBoundingClientRect();
    const gap = () => el("p30.remarks").getBoundingClientRect().top - el("p30.n42.0.2.1").getBoundingClientRect().bottom;
    const mm = 96 / 25.4;
    switchTo(false);
    const full = card().height, apart = gap();
    Pads.set("p30.remarks", "moved");
    switchTo(true);
    same(Math.round(card().height / mm), 199, "short card height in mm");
    same(gap() < 20 * mm, true, "remarks slide up");
    same(el("p30.remarks").value, "moved", "what was typed moves with its box");
    switchTo(false);
    same(card().height, full, "full card height back");
    same(gap(), apart, "remarks back");
  });
  test("short_marks", () => {
    const shown = selector => [...document.querySelectorAll(selector)].filter(e => e.offsetParent !== null);
    const rows = () => shown('[data-card="p30"] .rowmark').map(e => e.textContent).join(" ");
    const loose = () => shown('[data-card="surface"] .badge').length;
    const hints = () => shown(".sheet .hint").length;
    same(rows() + "|" + loose(), "|0", "no marks on full cards");
    same(hints(), 9, "a line above every full card");
    switchTo(true);
    same(rows(), "P P D", "marks down the P30 card");
    same(loose(), 5, "marks on the surface card");
    same(hints(), 9, "a line above every short card");
    const mark = shown('[data-card="p30"] .rowmark')[0].getBoundingClientRect();
    const text = shown('[data-card="p30"] .label span:not(.rowmark)').map(e => e.getBoundingClientRect())
      .filter(r => r.width && r.bottom > mark.top && r.top < mark.bottom && r.right > mark.left && r.left < mark.right);
    same(text.length, 0, "labels under the first mark");
    switchTo(false);
    const css = [...document.querySelectorAll("style")].map(s => s.textContent).join(" ");
    same(/@media print \{[^@]*\.hint/.test(css.replace(/\s+/g, " ")), true, "the lines are left off paper");
  });
  // a mouse click in the middle of every box must reach that box, not something drawn over it
  for (const short of [true, false]) test(short ? "clicks_reach_short" : "clicks_reach_full", () => {
    switchTo(short);
    const covered = [...document.querySelectorAll(".card [data-id]")].filter(box => box.offsetParent !== null).filter(box => {
      box.scrollIntoView({ block: "center", inline: "center" });
      const r = box.getBoundingClientRect();
      return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2) !== box;
    }).map(box => box.dataset.id);
    window.scrollTo(0, 0);
    const cards = {};
    covered.forEach(id => { const c = id.split(".")[0]; cards[c] = (cards[c] || 0) + 1; });
    same(covered.length, 0, "boxes a click misses " + JSON.stringify(cards) + ", first " + covered.slice(0, 3));
  });
  const address = column => [1, 2, 3, 4].map(i => Pads.value("p27.data." + column + ".1." + i)).join("");
  const grey = id => el(id).classList.contains("prefill");
  const bracket = () => [...document.querySelectorAll('[data-card="tpi"] .fill')].map(e => e.textContent).join(" ");
  test("prefill", () => {
    const version = document.getElementById("version"), verb = "p27.verb1.0.0.0", first = "p27.data.0.1.1";
    Pads.clearCard("p27");
    same(version.textContent, "Version: 099", "starts on 099");
    same(Pads.value(verb) + Pads.value("p27.verb1.0.0.1") + " " + Pads.value("p27.purpose2"), "71 TLAND", "filled in");
    same(address(0) + " " + address(1) + " " + address(2), "2022 2400 3433", "099 addresses");
    same(bracket(), "+026.60 +130.00", "099 TPI settings");
    same(grey(verb), true, "lighter lettering");
    same(Object.keys(stored()).filter(k => k.startsWith("p27.")).length, 0, "nothing stored for them");
    version.click();
    same(version.textContent, "Version: 210", "switched");
    same(localStorage.getItem("lm-pads-version"), "210", "choice kept");
    same(address(0) + " " + address(1) + " " + address(2), "2020 2026 3433", "210 addresses");
    same(bracket(), "+000.00 +130.00", "210 TPI settings");
    Pads.type(first, "5");
    same(Pads.value(first) + " " + grey(first), "5 false", "typed over");
    version.click();
    same(Pads.value(first), "5", "what was typed stays across versions");
    same(Pads.back(first), first, "Backspace on a typed box");
    same(Pads.value(first) + " " + grey(first), "2 true", "the filled-in figure returns");
    same(Pads.back(first), "p27.data.0.1.0", "Backspace on a filled-in box moves back");
    Pads.set(verb, "3");
    Pads.clearCard("p27");
    same(Pads.value(verb) + " " + grey(verb), "7 true", "Clear brings it back");
  });
  test("prefill_keys", () => {
    Pads.clearCard("p27");
    const box = el("p27.verb1.0.0.0");
    box.focus();
    box.value = "q";
    box.dispatchEvent(new InputEvent("input", { data: "q", inputType: "insertText", bubbles: true }));
    same(box.value + " " + grey("p27.verb1.0.0.0"), "7 true", "a refused character leaves it");
    box.value = "";
    box.dispatchEvent(new InputEvent("input", { inputType: "deleteContentBackward", bubbles: true }));
    same(box.value, "7", "deleting it brings it back");
    const purpose = el("p27.purpose1");
    purpose.focus();
    purpose.value = "";
    purpose.dispatchEvent(new InputEvent("input", { inputType: "deleteContentBackward", bubbles: true }));
    same(purpose.value, "", "free text can be emptied while one types");
    purpose.blur();
    same(purpose.value, "SITE", "and is filled in again afterwards");
  });
  test("saving", () => same(Pads.saving, true, "saving"));
  test("print_css", () => {
    const css = [...document.querySelectorAll("style")].map(s => s.textContent).join(" ").replace(/\s+/g, " ");
    same(css.includes("print-color-adjust: exact"), true, "exact colours");
    same(/@page portrait ?\{/.test(css), true, "portrait page");
    same(/@page landscape ?\{/.test(css), true, "landscape page");
  });
  test("theme_button", () => {
    const root = document.documentElement, button = document.getElementById("theme");
    const colour = (selector, property) => getComputedStyle(document.querySelector(selector))[property];
    const look = () => [colour("body", "backgroundColor"), colour(".card", "backgroundColor"),
      colour(".card .shade:not(.dark)", "backgroundColor"), colour(".card .cell input:not(.prefill)", "color"),
      colour(".card .dot", "backgroundColor")].join(" | ");
    if (root.dataset.theme === "dark") button.click();
    same(root.dataset.theme, "light", "theme");
    same(look(), ["rgb(216, 215, 211)", "rgb(251, 251, 249)", "rgb(233, 233, 228)", "rgb(17, 17, 17)",
      "rgb(17, 17, 17)"].join(" | "), "light colours");
    same(button.textContent.trim(), "Dark mode", "button in light");
    button.click();
    same(root.dataset.theme, "dark", "theme after a click");
    same(localStorage.getItem("pack-theme"), "dark", "choice kept under the manual's name");
    same(look(), ["rgb(16, 17, 18)", "rgb(27, 28, 30)", "rgb(44, 45, 48)", "rgb(232, 232, 228)",
      "rgb(232, 232, 228)"].join(" | "), "dark colours");
    same(button.textContent.trim(), "Light mode", "button in dark");
    button.click();
    same(localStorage.getItem("pack-theme"), "light", "choice kept");
  });
  Pads.set("p30.remarks", "kept");          // read back by the next run
}
if (testMode === "persist") {
  test("persists", () => {
    same(Pads.value("p30.remarks"), "kept", "value");
    same(el("p30.remarks").value, "kept", "shown");
  });
}
if (testMode === "v210") test("version_remembered", () => {
  same(document.getElementById("version").textContent, "Version: 210", "button");
  same([1, 2, 3, 4].map(i => Pads.value("p27.data.0.1." + i)).join(""), "2020", "site address");
});
if (testMode === "full") test("full_remembered", () => {
  same(document.body.classList.contains("short"), false, "full cards");
  same(el("p30.fdai.0.0.3").offsetParent !== null, true, "the box short cards hide");
});
if (testMode === "dark") test("theme_remembered", () => same(document.documentElement.dataset.theme, "dark", "theme"));
if (testMode === "badjson") test("bad_storage_not_json", () => { drawn(); same(Pads.value(R + ".3"), "", "empty"); });
if (testMode === "oldbox") {
  out.textContent += "";
  try {
    drawn();
    same(el(R + ".3").value + el(R + ".4").value, "", "values that do not fit are not shown");
    same(window.testErrors.join("; "), "", "page errors");
    out.textContent += "PASS bad_storage_old_layout\n";
  } catch (err) {
    out.textContent += "FAIL bad_storage_old_layout (" + err.message + ")\n";
  }
}
if (testMode === "blocked") {
  test("storage_blocked", () => {
    drawn();
    same(Pads.type(R + ".3", "1"), R + ".4", "next box");
    same(el(R + ".3").value, "1", "shown");
    same(Pads.saving, false, "saving");
    const note = document.getElementById("note");
    same(note.offsetParent !== null && note.textContent.includes("not saved"), true, "note shown");
    const was = document.documentElement.dataset.theme;
    document.getElementById("theme").click();
    same(document.documentElement.dataset.theme !== was, true, "the theme still switches");
    const was2 = document.body.classList.contains("short");
    same(was2, true, "opens on short cards with nothing saved");
    document.getElementById("short").click();
    same(document.body.classList.contains("short"), false, "the cards still switch");
  });
}
})();
</script>
"""

# the sheets Print all must give: the nine cards in flight order
SHAPES = ["portrait", "portrait", "landscape", "landscape", "landscape", "portrait", "landscape", "landscape",
          "landscape"]

# mode, tests expected from it; "main" and "persist" share one browser profile, in that order
RUNS = [("main", ["draws", "type_advances", "type_refused", "type_crosses_rows", "minus_normalised",
                  "octal", "back_clears_previous", "paste_by_position", "paste_register_on_first_entry_box",
                  "paste_part_of_a_row", "clear_card_only", "two_tabs", "keyboard_wiring", "tab_order", "buttons",
                  "clear_all", "short_button", "short_skips_hidden", "short_condensed", "short_marks", "clicks_reach_short", "clicks_reach_full", "prefill", "prefill_keys", "saving", "print_css", "theme_button"]),
        ("persist", ["persists"]), ("badjson", ["bad_storage_not_json"]), ("oldbox", ["bad_storage_old_layout"]),
        ("blocked", ["storage_blocked"]), ("dark", ["theme_remembered"]),
        ("full", ["full_remembered"]),
        ("v210", ["version_remembered"])]


def run(browser, profile, url, *extra):
    cmd = [browser, "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
           f"--user-data-dir={profile}", "--virtual-time-budget=5000", *extra, url]
    return subprocess.run(cmd, check=True, capture_output=True, timeout=120).stdout.decode("utf-8", "replace")


def with_scripts(page, before, after):
    page = page.replace("<head>", "<head>\n" + before, 1)
    head, tail = page.rsplit("</body>", 1)
    return head + after + "</body>" + tail


def with_choices(src, choices):
    """A copy of the page at src, opened with these choices already in the browser's storage."""
    setup = "".join(f'localStorage.setItem("{k}", "{v}");' for k, v in choices.items())
    src.write_text(PAGE.read_text(encoding="utf-8").replace("<head>", f"<head><script>{setup}</script>", 1),
                   encoding="utf-8")
    return src


def print_sheets(browser, tmp, short):
    """Print all, to a PDF: one A4 sheet to a card, in the card's shape.  Returns what is wrong, or "" """
    src = with_choices(tmp / f"print-{short}.html", {"lm-pads-short": short})
    pdf = tmp / f"pads-{short}.pdf"
    run(browser, tmp / f"profile-print-{short}", src.as_uri(), "--no-pdf-header-footer", f"--print-to-pdf={pdf}")
    data = pdf.read_bytes()
    pages = len(re.findall(rb"/Type\s*/Page(?![s\w])", data))
    boxes = [[float(v) for v in box.split()] for box in re.findall(rb"/MediaBox\s*\[([^\]]+)\]", data)]
    got = ["portrait" if b[3] - b[1] > b[2] - b[0] else "landscape" for b in boxes]
    if pages != len(SHAPES) or got != SHAPES:
        return f"{pages} pages, shapes {got}"
    odd = [b for b in boxes if sorted(round((b[i + 2] - b[i]) * 25.4 / 72) for i in (0, 1)) != [210, 297]]
    return f"sheets that are not A4: {odd}" if odd else ""


def behaviour(browser, tmp):
    src = tmp / "pads-test.html"
    src.write_text(with_scripts(PAGE.read_text(encoding="utf-8"), BEFORE, AFTER), encoding="utf-8")
    passed, failed = 0, 0
    for mode, expected in RUNS:
        profile = tmp / ("profile-main" if mode in ("main", "persist") else f"profile-{mode}")
        dom = run(browser, profile, f"{src.as_uri()}#{mode}", "--dump-dom")
        found = re.search(r'<pre id="results">(.*?)</pre>', dom, re.S)
        lines = html.unescape(found.group(1)).split("\n") if found else []
        lines = [line for line in lines if line.startswith(("PASS ", "FAIL "))]
        for line in lines:
            print(line)
        names = {line.split()[1] for line in lines}
        for name in expected:
            if name not in names:
                print(f"FAIL {name} (no result from the {mode} run)")
                failed += 1
        passed += sum(line.startswith("PASS ") for line in lines)
        failed += sum(line.startswith("FAIL ") for line in lines)
    for name, short in (("print_sheets", 0), ("print_sheets_short", 1)):
        problem = print_sheets(browser, tmp, short)
        print(f"PASS {name}" if not problem else f"FAIL {name} ({problem})")
        passed, failed = passed + (not problem), failed + bool(problem)
    print(f"test_pads_page: {passed} passed, {failed} failed")
    return 1 if failed else 0


def shots(browser, tmp, folder, theme, short):
    folder.mkdir(parents=True, exist_ok=True)
    page = PAGE.read_text(encoding="utf-8")
    data = re.search(r'<script type="application/json" id="cards">(.*?)</script>', page, re.S)
    px = 96 / 25.4
    for card in json.loads(data.group(1)):
        wide, high = (190, 277) if card["shape"] == "portrait" else (277, 190)
        only = (f"<style>header, footer, .bar, .hint {{ display: none !important }} .sheet:not(#card-{card['id']}) "
                f"{{ display: none !important }} body, main, .sheet, .wrap {{ margin: 0 !important; padding: 0 !important }} "
                f".card {{ margin: 4mm !important }}</style>")
        src = tmp / f"{card['id']}.html"
        with_choices(src, {"pack-theme": theme, "lm-pads-short": int(short)})
        src.write_text(src.read_text(encoding="utf-8").replace("</head>", only + "</head>", 1), encoding="utf-8")
        out = folder / f"{card['id']}.png"
        run(browser, tmp / "profile-shots", src.as_uri(), "--hide-scrollbars", "--force-device-scale-factor=1.6",
            f"--window-size={int((wide + 8) * px) + 2},{int((high + 8) * px) + 2}", f"--screenshot={out}")
        print(out)
    (tmp / "page.html").write_text(page, encoding="utf-8")
    narrow = tmp / "narrow-frame.html"
    narrow.write_text('<!doctype html><body style="margin:0;background:#c00"><iframe src="page.html" '
                      'style="width:360px;height:900px;border:0;background:#fff"></iframe></body>', encoding="utf-8")
    out = folder / "narrow.png"
    run(browser, tmp / "profile-shots", narrow.as_uri(), "--hide-scrollbars", "--window-size=600,920",
        f"--screenshot={out}")
    print(out)
    return 0


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--browser", help="path of msedge.exe or chrome.exe")
    args.add_argument("--shots", metavar="DIR", help="write screenshots instead of testing")
    args.add_argument("--dark", action="store_true", help="with --shots: the cards in dark mode")
    args.add_argument("--short", action="store_true", help="with --shots: the short cards")
    opts = args.parse_args()
    browser = opts.browser or find_browser()
    if not browser:
        sys.exit("needs Microsoft Edge or Google Chrome")
    if not PAGE.exists():
        print("FAIL there is no docs/pads.html")
        return 1
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        if opts.shots:
            return shots(browser, Path(tmp), Path(opts.shots).resolve(), "dark" if opts.dark else "light",
                         opts.short)
        return behaviour(browser, Path(tmp))


if __name__ == "__main__":
    sys.exit(main())
