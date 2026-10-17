#!/usr/bin/env python3
"""Apply (or check) the Timffle product name in user-visible web texts.

Ruffle grants no trademark rights (MIT/Apache-2.0 cover code, not names or logos), so everything a user of
the Timffle web extension, web demo or self-hosted player *sees* must say "Timffle", not "Ruffle". Upstream
Ruffle keeps adding and translating such strings, so after every merge from upstream run:

    python3 timffle/scripts/rebrand.py           # rewrite the texts
    python3 timffle/scripts/rebrand.py --check   # exit 1 if anything is left (CI / before a release)

What it changes: the word "Ruffle" in Fluent texts (web/packages/core/texts/**.ftl) and in the extension's
Chrome i18n messages (web/packages/extension/assets/_locales/**/messages.json), and the product name in the
extension HTML pages. Occurrences that name Ruffle's *wiki* stay "Ruffle", because those links really go to
Ruffle's wiki (descriptive use, and it credits Ruffle). Message ids (lower-case, such as
"context-menu-about-ruffle") are never touched.

What it deliberately does not change (see timffle/docs/BRANDING.md): code identifiers and public APIs
(RufflePlayer, window.RufflePlayer, <ruffle-player>, ruffle_core, npm workspace names) for compatibility with
pages written for Ruffle and to keep upstream merges small; source comments; credits that name Ruffle as
the upstream project. Code-level links (bug reports, "About", updates) are edited by hand and verified
by --check through CODE_CHECKS below.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NEW = "Timffle"
REPO_URL = "https://github.com/Im-Tim-mI/Timffle"

# "Ruffle" next to one of these (same clause, within WIKI_WINDOW characters) names Ruffle's wiki: keep it.
WIKI = re.compile(r"(?i)wiki|ウィキ|위키|вики|維基|维基|ويكي|ויקי|วิกิ")
WIKI_WINDOW = 16
CLAUSE_END = re.compile(r"[.!?。！？\n]")
WORD = re.compile(r"Ruffle")


def names_wiki(text, start, end):
    lo = max(0, start - WIKI_WINDOW)
    hi = min(len(text), end + WIKI_WINDOW)
    before = text[lo:start]
    after = text[end:hi]
    # Only look inside the same clause.
    before = CLAUSE_END.split(before)[-1]
    after = CLAUSE_END.split(after)[0]
    return bool(WIKI.search(before) or WIKI.search(after))


def rebrand_text(text):
    out = []
    pos = 0
    for m in WORD.finditer(text):
        out.append(text[pos:m.start()])
        out.append(m.group(0) if names_wiki(text, m.start(), m.end()) else NEW)
        pos = m.end()
    out.append(text[pos:])
    return "".join(out)


def rebrand_ftl(src):
    lines = []
    for line in src.split("\n"):
        if line.startswith("#"):
            lines.append(line)  # comments (licence headers, translator notes) stay as they are
            continue
        m = re.match(r"^(-?[A-Za-z][A-Za-z0-9_-]*\s*=)(.*)$", line)
        if m:  # "message-id = value": never touch the id
            lines.append(m.group(1) + rebrand_text(m.group(2)))
        else:  # continuation lines, variants ("[extension] About Ruffle ...")
            v = re.match(r"^(\s*\*?\[[^\]]*\])(.*)$", line)
            lines.append(v.group(1) + rebrand_text(v.group(2)) if v else rebrand_text(line))
    return "\n".join(lines)


def rebrand_messages_json(src):
    data = json.loads(src)
    changed = False
    for entry in data.values():
        if isinstance(entry, dict) and isinstance(entry.get("message"), str):
            new = rebrand_text(entry["message"])
            if new != entry["message"]:
                entry["message"] = new
                changed = True
    if not changed:
        return src
    # Rewrite only the "message" strings in place so the file keeps its own formatting.
    def repl(m):
        old = json.loads(m.group(2))
        new = rebrand_text(old)
        return m.group(0) if new == old else m.group(1) + json.dumps(new, ensure_ascii=False)
    return re.sub(r'("message"\s*:\s*)("(?:[^"\\]|\\.)*")', repl, src)


HTML_REPLACEMENTS = [
    ('href="https://ruffle.rs/"', f'href="{REPO_URL}"'),
    ('data-canonical-src="https://ruffle.rs/assets/logo.svg"', 'data-canonical-src="images/logo.svg"'),
]


def rebrand_html_part(src):
    for old, new in HTML_REPLACEMENTS:
        src = src.replace(old, new)
    # Product name in text and alt/title attributes; ids and classes are lower-case and unaffected.
    return rebrand_text(src)


def rebrand_html(src):
    # The attribution paragraph (class="timffle-attribution") names and links Ruffle on purpose.
    parts = re.split(r'(<p class="timffle-attribution"[\s\S]*?</p>)', src)
    return "".join(p if p.startswith('<p class="timffle-attribution"') else rebrand_html_part(p) for p in parts)


def targets():
    for p in sorted((ROOT / "web/packages/core/texts").glob("*/*.ftl")):
        yield p, rebrand_ftl
    for p in sorted((ROOT / "web/packages/extension/assets/_locales").glob("*/messages.json")):
        yield p, rebrand_messages_json
    for p in sorted((ROOT / "web/packages/extension/assets").glob("*.html")):
        yield p, rebrand_html
    yield ROOT / "web/packages/demo/index.html", rebrand_html


# Hand-edited code: (file, text that must be present, text that must be absent).
CODE_CHECKS = [
    ("web/packages/extension/manifest.json5", '"name": "Timffle - Flash Emulator"', '"short_name": "Ruffle"'),
    ("web/packages/extension/manifest.json5", f'"homepage_url": "{REPO_URL}', '"homepage_url": "https://ruffle.rs/'),
    ("web/packages/extension/build.ts", '|| "{4244f375-9038-4a8d-bc77-e47e6cc7a426}"', '|| "ruffle@ruffle.rs"'),
    ("web/packages/core/src/internal/constants.tsx", f'TIMFFLE_REPOSITORY = "{REPO_URL}"', None),
    ("web/packages/core/src/internal/ui/panic.tsx", "TIMFFLE_REPOSITORY + \"/issues/new", "ruffle-rs/ruffle/issues/new"),
    ("web/packages/core/src/internal/ui/panic.tsx", "TIMFFLE_REPOSITORY + \"/releases\"", 'RUFFLE_ORIGIN + "/downloads",'),
    ("web/packages/core/src/internal/player/inner.tsx", "window.open(TIMFFLE_REPOSITORY", "window.open(RUFFLE_ORIGIN"),
    ("web/packages/core/src/internal/ui/splash-screen.tsx", 'aria-label="Timffle"', "var(--ruffle-orange)"),
    ("web/packages/extension/assets/options.html", 'class="timffle-attribution"', None),
    ("web/packages/demo/src/navbar.tsx", 'alt="Timffle"', 'alt="Ruffle"'),
]


def main():
    check = "--check" in sys.argv[1:]
    problems = []
    for path, fn in targets():
        src = path.read_text(encoding="utf-8")
        new = fn(src)
        if new != src:
            rel = path.relative_to(ROOT)
            if check:
                problems.append(f"{rel}: still says Ruffle (run timffle/scripts/rebrand.py)")
            else:
                path.write_text(new, encoding="utf-8")
                print("rebranded", rel)
    for rel, must, must_not in CODE_CHECKS:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if must and must not in text:
            problems.append(f"{rel}: missing {must!r} (hand edit lost in a merge?)")
        if must_not and must_not in text:
            problems.append(f"{rel}: still contains {must_not!r}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    if check:
        print("rebrand check: OK")


if __name__ == "__main__":
    main()
