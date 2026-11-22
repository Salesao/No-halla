#!/usr/bin/env python3
"""Generate chrome.i18n locale catalogs for the browser extension.

design/copy.json is the single source of truth for UI copy: every dotted key
maps to {"en": ..., "ru": ...}. This script selects the "gate." namespace and
emits extension/_locales/<lang>/messages.json, where each dotted key becomes a
Chrome message name with dots replaced by underscores
(gate.popup.title -> gate_popup_title).

Chrome reads printf-style placeholders (%d, %s) directly from "message", so
copy must not use named placeholders. Only the Python standard library is
used. The script is idempotent and fails on malformed entries, so a broken
source never produces a partial catalog.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "copy.json"
LOCALES = ROOT / "extension" / "_locales"

LANGUAGES = ("en", "ru")
PREFIX = "gate."
KEY_PATTERN = re.compile(r"^[A-Za-z0-9.]+$")
NAMED_PLACEHOLDER = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")


def fail(message: str) -> None:
    print(f"gen-extension-strings: error: {message}", file=sys.stderr)
    sys.exit(1)


def message_name(key: str) -> str:
    if not KEY_PATTERN.match(key):
        fail(f"key '{key}': only letters, digits and dots are allowed in a key")
    return key.replace(".", "_")


def main() -> None:
    try:
        copy = json.loads(SOURCE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {SOURCE}: {exc}")

    if not isinstance(copy, dict) or not copy:
        fail("copy.json must be a non-empty object of dotted keys")

    messages = {lang: {} for lang in LANGUAGES}
    for key in sorted(copy):
        if not key.startswith(PREFIX):
            continue
        entry = copy[key]
        if not isinstance(entry, dict):
            fail(f"key '{key}': expected an object with en/ru values")
        name = message_name(key)
        if name in messages[LANGUAGES[0]]:
            fail(
                f"key '{key}': message name '{name}' collides with another key"
            )
        for lang in LANGUAGES:
            value = entry.get(lang)
            if not isinstance(value, str) or not value:
                fail(f"key '{key}': missing or empty '{lang}' string")
            if NAMED_PLACEHOLDER.search(value):
                fail(
                    f"key '{key}': named placeholder in '{lang}' value; "
                    "normalize to printf-style %d/%s in design/copy.json first"
                )
            messages[lang][name] = {"message": value}

    if not messages["en"]:
        fail(f"copy.json contains no '{PREFIX}' keys")

    for lang in LANGUAGES:
        target = LOCALES / lang / "messages.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(
                messages[lang], ensure_ascii=False, indent=2, sort_keys=True
            )
            + "\n",
            encoding="utf-8",
        )
        print(
            f"gen-extension-strings: wrote {target.relative_to(ROOT)} "
            f"({len(messages[lang])} keys)"
        )


if __name__ == "__main__":
    main()