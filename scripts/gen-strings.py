#!/usr/bin/env python3
"""Generate NoHalla/Resources/Localizable.xcstrings from design/copy.json (D10).

design/copy.json is the single source of truth for UI copy: every dotted key
maps to {"en": ..., "ru": ...}. This script emits an Xcode String Catalog with
sourceLanguage "en" and a translated stringUnit per language. Keys containing
printf-style placeholders (%d / %@) are plain stringUnits without variations;
formatting happens at runtime via L10n.string(_:_:) (String(format:)).

Keys under the `gate.` namespace belong to the standalone Chrome extension and
are generated into extension/_locales by scripts/gen-extension-strings.py. They
are skipped here so the app catalog contains only app strings.

Only the Python standard library is used. The script is idempotent: it
rewrites the catalog on every run and fails on malformed entries.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "copy.json"
CATALOG = ROOT / "NoHalla" / "Resources" / "Localizable.xcstrings"

LANGUAGES = ("en", "ru")
# Extension-only copy; scripts/gen-extension-strings.py owns this namespace.
EXTENSION_PREFIX = "gate."
# Named placeholders must be normalized to printf-style before generation (D22).
NAMED_PLACEHOLDER = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")


def fail(message: str) -> None:
    print(f"gen-strings: error: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    try:
        copy = json.loads(SOURCE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {SOURCE}: {exc}")

    if not isinstance(copy, dict) or not copy:
        fail("copy.json must be a non-empty object of dotted keys")

    strings = {}
    for key in sorted(copy):
        if key.startswith(EXTENSION_PREFIX):
            continue
        entry = copy[key]
        if not isinstance(entry, dict):
            fail(f"key '{key}': expected an object with en/ru values")
        localizations = {}
        for lang in LANGUAGES:
            value = entry.get(lang)
            if not isinstance(value, str) or not value:
                fail(f"key '{key}': missing or empty '{lang}' string")
            if NAMED_PLACEHOLDER.search(value):
                fail(
                    f"key '{key}': named placeholder in '{lang}' value; "
                    "normalize to %d/%@ in design/copy.json first (D22)"
                )
            localizations[lang] = {
                "stringUnit": {"state": "translated", "value": value}
            }
        strings[key] = {"localizations": localizations}

    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"gen-strings: wrote {CATALOG.relative_to(ROOT)} ({len(strings)} keys, en+ru)")


if __name__ == "__main__":
    main()
