#!/usr/bin/env python3
"""Put Timffle's own interface texts into the extension's Chrome message catalogs.

Ruffle translates the extension through web/packages/extension/assets/_locales/<language>/messages.json
(Crowdin keeps those files up to date, and merging a new Ruffle nightly means taking its version of them).
Timffle adds texts of its own (the socket pages and the question window), so they cannot live only in
those files. Their source of truth is timffle/locales/<language>.json (see timffle/locales/README.md);
this script copies them into the catalogs, every key starting with "timffle_":

    python3 timffle/scripts/sync_locales.py           # rewrite the catalogs
    python3 timffle/scripts/sync_locales.py --check   # exit 1 if a catalog is stale or a text is broken

Run it after every merge from upstream (after rebrand.py), and whenever a file in timffle/locales changes.
It also checks the texts: every language of the extension has a file with every key, placeholders ($VERSION$),
the literal tokens the user types ({host}, {port}) and the <1>...</1> link/bold tags survive translation.
The one exception is the Logitech discount box (keys timffle_promo_*): it is a Taiwanese shop's code, so only the
English and Chinese files have those texts, and no other language may carry them.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "timffle/locales"
CATALOGS = ROOT / "web/packages/extension/assets/_locales"
PREFIX = "timffle_"
SOURCE_LANGUAGE = "en"
# Texts that only some languages carry: the interface shows the Logitech discount box in these languages only.
REGIONAL_PREFIX = "timffle_promo_"
REGIONAL_LANGUAGES = {"en", "zh_CN", "zh_TW"}

PLACEHOLDER = re.compile(r"\$([A-Za-z0-9_@]+)\$")
LITERAL = re.compile(r"\{[a-z]+\}")
TAG = re.compile(r"</?\d>")


def load_source(path):
    """{key: {"message": ..., ...}} from a file whose values are strings or complete catalog entries."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("must be a JSON object")
    entries = {}
    for key, value in data.items():
        if isinstance(value, str):
            value = {"message": value}
        if not isinstance(value, dict) or not isinstance(value.get("message"), str):
            raise ValueError(f"{key}: needs a string or an object with a string \"message\"")
        entries[key] = value
    return entries


def wanted(language, master):
    """The keys the file of `language` must have: all of them, except the texts of the regional box in other languages."""
    return [key for key in master if language in REGIONAL_LANGUAGES or not key.startswith(REGIONAL_PREFIX)]


def problems_in(language, entries, master):
    problems = []
    for key, entry in entries.items():
        where = f"timffle/locales/{language}.json: {key}"
        if not key.startswith(PREFIX):
            problems.append(f"{where}: keys must start with {PREFIX!r}")
            continue
        if key not in master:
            problems.append(f"{where}: not in {SOURCE_LANGUAGE}.json")
            continue
        if key not in wanted(language, master):
            problems.append(f"{where}: only {', '.join(sorted(REGIONAL_LANGUAGES))} carry the {REGIONAL_PREFIX}* texts")
            continue
        message = entry["message"]
        if not message.strip():
            problems.append(f"{where}: empty text")
            continue
        want = master[key]["message"]
        if language == SOURCE_LANGUAGE:
            defined = {name.lower() for name in master[key].get("placeholders", {})}
            used = {name.lower() for name in PLACEHOLDER.findall(message)}
            if defined != used:
                problems.append(f"{where}: placeholders used {sorted(used)} but defined {sorted(defined)}")
            continue
        if sorted(m.lower() for m in PLACEHOLDER.findall(message)) != sorted(m.lower() for m in PLACEHOLDER.findall(want)):
            problems.append(f"{where}: placeholders differ from {SOURCE_LANGUAGE} ({PLACEHOLDER.findall(want)})")
        if sorted(LITERAL.findall(message)) != sorted(LITERAL.findall(want)):
            problems.append(f"{where}: literal tokens differ from {SOURCE_LANGUAGE} ({LITERAL.findall(want)})")
        if sorted(TAG.findall(message)) != sorted(TAG.findall(want)):
            problems.append(f"{where}: tags differ from {SOURCE_LANGUAGE} ({TAG.findall(want)})")
        if "description" in entry or "placeholders" in entry:
            problems.append(f"{where}: only {SOURCE_LANGUAGE}.json carries descriptions and placeholders")
    for key in wanted(language, master):
        if key not in entries:
            problems.append(f"timffle/locales/{language}.json: missing {key}")
    return problems


def generated(language, entries, master):
    """The catalog entries for one language, in the order of the master file."""
    out = {}
    for key in master:
        if key not in entries:
            continue
        entry = {"message": entries[key]["message"]}
        if language == SOURCE_LANGUAGE:
            for extra in ("description", "placeholders"):
                if extra in master[key]:
                    entry[extra] = master[key][extra]
        elif "placeholders" in master[key]:
            entry["placeholders"] = master[key]["placeholders"]
        out[key] = entry
    return out


def render(catalog_text, entries):
    catalog = json.loads(catalog_text)
    catalog = {key: value for key, value in catalog.items() if not key.startswith(PREFIX)}
    catalog.update(entries)
    return json.dumps(catalog, indent=4, ensure_ascii=False) + "\n"


def main():
    check = "--check" in sys.argv[1:]
    problems = []
    try:
        master = load_source(SOURCES / f"{SOURCE_LANGUAGE}.json")
    except (OSError, ValueError) as error:
        print(f"timffle/locales/{SOURCE_LANGUAGE}.json: {error}", file=sys.stderr)
        sys.exit(1)
    problems += problems_in(SOURCE_LANGUAGE, master, master)

    languages = sorted(p.parent.name for p in CATALOGS.glob("*/messages.json"))
    if SOURCE_LANGUAGE not in languages:
        problems.append(f"{CATALOGS}: no {SOURCE_LANGUAGE} catalog")
    for orphan in sorted(p.stem for p in SOURCES.glob("*.json") if p.stem not in languages):
        problems.append(f"timffle/locales/{orphan}.json: the extension has no such language (_locales/{orphan})")

    changed = []
    for language in languages:
        path = SOURCES / f"{language}.json"
        if not path.exists():
            problems.append(f"timffle/locales/{language}.json: missing (every language of the extension needs one)")
            continue
        try:
            entries = load_source(path)
        except (OSError, ValueError) as error:
            problems.append(f"timffle/locales/{language}.json: {error}")
            continue
        if language != SOURCE_LANGUAGE:
            problems += problems_in(language, entries, master)
        catalog_path = CATALOGS / language / "messages.json"
        old = catalog_path.read_text(encoding="utf-8")
        new = render(old, generated(language, entries, master))
        if new != old:
            if check:
                problems.append(
                    f"{catalog_path.relative_to(ROOT)}: out of date (run timffle/scripts/sync_locales.py)"
                )
            else:
                catalog_path.write_text(new, encoding="utf-8")
                changed.append(language)

    if changed:
        print(f"updated {len(changed)} catalogs:", " ".join(changed))
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    if check:
        regional = sum(key.startswith(REGIONAL_PREFIX) for key in master)
        print(
            f"locales check: OK ({len(languages)} languages, {len(master) - regional} texts each, "
            f"{regional} more in {' '.join(sorted(REGIONAL_LANGUAGES))})"
        )


if __name__ == "__main__":
    main()
