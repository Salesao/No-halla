#!/usr/bin/env python3
"""Generate NoHalla/Resources/Assets.xcassets from the design sources.

Sources (read-only):
  design/exports/appicon-1024.png   -> AppIcon.appiconset (all macOS sizes, via sips)
  design/exports/menubar-icons.svg  -> five 18x18 template SVG imagesets
  design/mockups/onboarding-1.html  -> GateScene.imageset (decorative gate/fjord SVG)
  design/tokens.json                -> appearance colors for the GateScene variants

Only the Python standard library and the system `sips` tool are used.
The script is idempotent: it rewrites the generated sets on every run.
"""

import copy
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "design"
CATALOG = ROOT / "NoHalla" / "Resources" / "Assets.xcassets"

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

# Symbol id -> imageset name (design/ICONS.md).
MENUBAR_SYMBOLS = {
    "protected": "MenuBarProtected",
    "checking": "MenuBarGrace",
    "frozen": "MenuBarFrozen",
    "unknown": "MenuBarUnknown",
    "off": "MenuBarOff",
}

# Standard macOS AppIcon slots: (point size, scale). Pixel size = points * scale.
APPICON_SLOTS = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

INFO = {"author": "xcode", "version": 1}


def fail(message: str) -> None:
    print(f"gen-assets: error: {message}", file=sys.stderr)
    sys.exit(1)


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def fresh_set(name: str) -> Path:
    """Recreate a catalog set directory owned by this script."""
    directory = CATALOG / name
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    return directory


def png_dimensions(path: Path) -> tuple:
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        check=True, capture_output=True, text=True,
    )
    width = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    if width is None or height is None:
        fail(f"cannot read dimensions of {path}")
    return int(width.group(1)), int(height.group(1))


def generate_appicon() -> None:
    source = DESIGN / "exports" / "appicon-1024.png"
    if not source.is_file():
        fail(f"missing source {source}")
    if shutil.which("sips") is None:
        fail("sips is not available")

    directory = fresh_set("AppIcon.appiconset")
    images = []
    rendered = {}  # pixel size -> already generated file (shared between 1x/2x slots)
    for points, scale in APPICON_SLOTS:
        pixels = points * scale
        suffix = "" if scale == 1 else f"@{scale}x"
        filename = f"icon_{points}x{points}{suffix}.png"
        destination = directory / filename
        if pixels in rendered:
            shutil.copyfile(rendered[pixels], destination)
        else:
            subprocess.run(
                ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
                 str(source), "--out", str(destination)],
                check=True, capture_output=True, text=True,
            )
            rendered[pixels] = destination
        if png_dimensions(destination) != (pixels, pixels):
            fail(f"{filename} has wrong dimensions")
        images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })
    write_json(directory / "Contents.json", {"images": images, "info": INFO})
    print(f"AppIcon.appiconset: {len(images)} slots "
          f"({', '.join(str(p) for p in sorted(rendered))} px)")


def solid_color_attributes(element: ET.Element) -> None:
    """Template glyphs render from alpha only; bake currentColor to black."""
    for node in element.iter():
        for key, value in node.attrib.items():
            if "currentColor" in value:
                node.attrib[key] = value.replace("currentColor", "#000000")


def generate_menubar_icons() -> None:
    source = DESIGN / "exports" / "menubar-icons.svg"
    if not source.is_file():
        fail(f"missing source {source}")
    tree = ET.parse(source)
    symbols = {node.get("id"): node
               for node in tree.iter(f"{{{SVG_NS}}}symbol")}

    for symbol_id, name in MENUBAR_SYMBOLS.items():
        symbol = symbols.get(symbol_id)
        if symbol is None:
            fail(f"symbol '{symbol_id}' not found in {source.name}")
        attributes = dict(symbol.attrib)
        attributes.pop("id", None)
        attributes.update({"width": "18", "height": "18", "viewBox": "0 0 18 18"})
        standalone = ET.Element(f"{{{SVG_NS}}}svg", attributes)
        for child in symbol:
            standalone.append(copy.deepcopy(child))
        solid_color_attributes(standalone)
        svg_text = ET.tostring(standalone, encoding="unicode")
        ET.fromstring(svg_text)  # well-formedness guard

        directory = fresh_set(f"{name}.imageset")
        (directory / f"{name}.svg").write_text(svg_text + "\n", encoding="utf-8")
        write_json(directory / "Contents.json", {
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": INFO,
            "properties": {
                "preserves-vector-representation": True,
                "template-rendering-intent": "template",
            },
        })
        print(f"{name}.imageset: 18x18 template SVG (symbol '{symbol_id}')")


def generate_gate_scene(tokens: dict) -> None:
    """Decorative gate/fjord scene shared by hero, About and empty states.

    Geometry comes from the onboarding hero (design/mockups/onboarding-1.html);
    CSS color variables are resolved from tokens.json. The light variant is the
    unqualified fallback: every decorative color's contrast value in tokens.json
    equals its light value, so Increase Contrast resolves correctly through it.
    """
    source = DESIGN / "mockups" / "onboarding-1.html"
    if not source.is_file():
        fail(f"missing source {source}")
    match = re.search(r'<svg class="gate-scene".*?</svg>',
                      source.read_text(encoding="utf-8"), re.DOTALL)
    if match is None:
        fail(f"gate-scene SVG not found in {source.name}")
    template = match.group(0)

    colors = tokens["colors"]
    directory = fresh_set("GateScene.imageset")
    images = []
    for index, appearance in enumerate(tokens["appearance"][:2]):  # light, dark
        def resolve(match: re.Match) -> str:
            key = match.group(1)
            if key not in colors:
                fail(f"unknown color token '{key}' in gate scene")
            return colors[key][index]

        svg_text = re.sub(r"var\(--color-([a-z-]+)\)", resolve, template)
        if "var(--color-" in svg_text:
            fail("unresolved color variable in gate scene")
        ET.fromstring(svg_text)  # well-formedness guard

        filename = "GateScene.svg" if appearance == "light" else "GateSceneDark.svg"
        (directory / filename).write_text(svg_text + "\n", encoding="utf-8")
        entry = {"filename": filename, "idiom": "universal"}
        if appearance == "dark":
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
    write_json(directory / "Contents.json", {
        "images": images,
        "info": INFO,
        "properties": {"preserves-vector-representation": True},
    })
    print("GateScene.imageset: decorative SVG, light/dark variants")


def validate_catalog() -> None:
    """Round-trip every Contents.json and check referenced files exist."""
    for contents in sorted(CATALOG.rglob("Contents.json")):
        payload = json.loads(contents.read_text(encoding="utf-8"))
        for image in payload.get("images", []):
            filename = image.get("filename")
            if filename is None:
                continue
            path = contents.parent / filename
            if not path.is_file():
                fail(f"{contents}: referenced file missing: {filename}")
            if path.suffix == ".svg":
                ET.parse(path)
    print("catalog validation: ok")


def main() -> None:
    tokens_path = DESIGN / "tokens.json"
    if not tokens_path.is_file():
        fail(f"missing {tokens_path}")
    tokens = json.loads(tokens_path.read_text(encoding="utf-8"))

    CATALOG.mkdir(parents=True, exist_ok=True)
    write_json(CATALOG / "Contents.json", {"info": INFO})
    generate_appicon()
    generate_menubar_icons()
    generate_gate_scene(tokens)
    validate_catalog()
    print(f"done: {CATALOG}")


if __name__ == "__main__":
    main()
