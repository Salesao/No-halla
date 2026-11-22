#!/usr/bin/env python3
"""Generate Firefox locale catalogs for the No-halla Gate extension.

design/copy.json remains the single shared source of UI copy: every dotted key
maps to {"en": ..., "ru": ...}. This script selects the "gate." namespace and
emits extension-firefox/_locales/<lang>/messages.json, where each dotted key
becomes a message name with dots replaced by underscores
(gate.popup.title -> gate_popup_title).

extension-firefox/localization-overrides.json holds only browser-specific
variants (Firefox prompts, the Firefox alarm behavior, the Firefox leak note,
and the Firefox permission wording). An override key must exist in the shared
copy; it replaces both the EN and the RU value. Unknown override keys, missing
or empty values, named placeholders, and message-name collisions all fail the
run before anything is written. Only the Python standard library is used; the
script is idempotent.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "copy.json"
OVERRIDES = ROOT / "extension-firefox" / "localization-overrides.json"
LOCALES = ROOT / "extension-firefox" / "_locales"

LANGUAGES = ("en", "ru")
PREFIX = "gate."
KEY_PATTERN = re.compile(r"^[A-Za-z0-9.]+$")
NAMED_PLACEHOLDER = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")


def fail(message: str) -> None:
    print(f"gen-firefox-strings: error: {message}", file=sys.stderr)
    sys.exit(1)


def message_name(key: str) -> str:
    if not KEY_PATTERN.match(key):
        fail(f"key '{key}': only letters, digits and dots are allowed in a key")
    return key.replace(".", "_")


def read_object(path: Path, label: str, allow_empty: bool = False) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {label} {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    if not value and not allow_empty:
        fail(f"{label} must be a non-empty object")
    return value


def main() -> None:
    copy = read_object(SOURCE, "copy source")
    overrides = read_object(OVERRIDES, "override source", allow_empty=True)

    gate_keys = sorted(key for key in copy if key.startswith(PREFIX))
    if not gate_keys:
        fail(f"copy.json contains no '{PREFIX}' keys")

    for key in overrides:
        if not key.startswith(PREFIX) or key not in copy:
            fail(f"override key '{key}' is not a known '{PREFIX}' key in copy.json")

    messages = {lang: {} for lang in LANGUAGES}
    for key in gate_keys:
        entry = overrides.get(key, copy[key])
        if not isinstance(entry, dict):
            fail(f"key '{key}': expected an object with en/ru values")
        name = message_name(key)
        if name in messages[LANGUAGES[0]]:
            fail(f"key '{key}': message name '{name}' collides with another key")
        for lang in LANGUAGES:
            value = entry.get(lang)
            if not isinstance(value, str) or not value.strip():
                fail(f"key '{key}': missing or empty '{lang}' string")
            if NAMED_PLACEHOLDER.search(value):
                fail(
                    f"key '{key}': named placeholder in '{lang}' value; "
                    "normalize to printf-style %d/%s in design/copy.json or the override file first"
                )
            messages[lang][name] = {"message": value}

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
            f"gen-firefox-strings: wrote {target.relative_to(ROOT)} "
            f"({len(messages[lang])} keys, {len(overrides)} overrides)"
        )


if __name__ == "__main__":
    main()