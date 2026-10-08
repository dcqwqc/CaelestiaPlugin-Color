#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from pathlib import Path

HEX_RE = re.compile(r"^[0-9a-fA-F]{6}$")

M3_ROLES = {
    "primary_paletteKeyColor", "secondary_paletteKeyColor", "tertiary_paletteKeyColor",
    "neutral_paletteKeyColor", "neutral_variant_paletteKeyColor",
    "background", "onBackground", "surface", "surfaceDim", "surfaceBright",
    "surfaceContainerLowest", "surfaceContainerLow", "surfaceContainer",
    "surfaceContainerHigh", "surfaceContainerHighest", "onSurface", "surfaceVariant",
    "onSurfaceVariant", "inverseSurface", "inverseOnSurface", "outline",
    "outlineVariant", "shadow", "scrim", "surfaceTint",
    "primary", "primaryDim", "onPrimary", "primaryContainer", "onPrimaryContainer",
    "inversePrimary", "primaryFixed", "primaryFixedDim", "onPrimaryFixed",
    "onPrimaryFixedVariant",
    "secondary", "secondaryDim", "onSecondary", "secondaryContainer",
    "onSecondaryContainer", "secondaryFixed", "secondaryFixedDim",
    "onSecondaryFixed", "onSecondaryFixedVariant",
    "tertiary", "tertiaryDim", "onTertiary", "tertiaryContainer",
    "onTertiaryContainer", "tertiaryFixed", "tertiaryFixedDim",
    "onTertiaryFixed", "onTertiaryFixedVariant",
    "error", "errorDim", "onError", "errorContainer", "onErrorContainer",
    "success", "onSuccess", "successContainer", "onSuccessContainer",
}
ALLOWED_ROLES = M3_ROLES | {f"term{i}" for i in range(16)}

NEUTRAL_LIGHT = {
    "background": "ffffff",
    "onBackground": "171717",
    "surface": "ffffff",
    "surfaceDim": "eeeeee",
    "surfaceBright": "ffffff",
    "surfaceContainerLowest": "ffffff",
    "surfaceContainerLow": "fafafa",
    "surfaceContainer": "f5f5f5",
    "surfaceContainerHigh": "eeeeee",
    "surfaceContainerHighest": "e5e5e5",
    "onSurface": "171717",
    "surfaceVariant": "f2f2f2",
    "onSurfaceVariant": "525252",
    "outline": "737373",
    "outlineVariant": "d4d4d4",
    "inverseSurface": "171717",
    "inverseOnSurface": "fafafa",
    "shadow": "000000",
    "scrim": "000000",
}

NEUTRAL_DARK = {
    "background": "0a0a0a",
    "onBackground": "f5f5f5",
    "surface": "0a0a0a",
    "surfaceDim": "0a0a0a",
    "surfaceBright": "2a2a2a",
    "surfaceContainerLowest": "050505",
    "surfaceContainerLow": "111111",
    "surfaceContainer": "171717",
    "surfaceContainerHigh": "202020",
    "surfaceContainerHighest": "2a2a2a",
    "onSurface": "f5f5f5",
    "surfaceVariant": "262626",
    "onSurfaceVariant": "d4d4d4",
    "outline": "a3a3a3",
    "outlineVariant": "404040",
    "inverseSurface": "f5f5f5",
    "inverseOnSurface": "171717",
    "shadow": "000000",
    "scrim": "000000",
}


def clean_hex(value):
    if value is None:
        return None
    value = str(value).strip().lstrip("#")
    return value.lower() if HEX_RE.fullmatch(value) else None


def clean_palette(value):
    if not isinstance(value, dict):
        return {}
    out = {}
    for role, colour in value.items():
        if role not in ALLOWED_ROLES:
            continue
        cleaned = clean_hex(colour)
        if cleaned:
            out[role] = cleaned
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--primary")
    parser.add_argument("--accent")
    parser.add_argument("--border")
    parser.add_argument("--folder")
    parser.add_argument("--palette-json")
    parser.add_argument("--saved-json")
    parser.add_argument("--preset", choices=["neutral-light", "neutral-dark", "clear-palette"])
    parser.add_argument("--reset-primary", action="store_true")
    parser.add_argument("--reset-accent", action="store_true")
    parser.add_argument("--reset-border", action="store_true")
    parser.add_argument("--reset-folder", action="store_true")
    args = parser.parse_args()

    config_dir = Path.home() / ".config/caelestia"
    overrides_file = config_dir / "color_overrides.json"
    hypr_vars_file = config_dir / "hypr-vars.lua"

    overrides = {}
    if overrides_file.exists():
        try:
            loaded = json.loads(overrides_file.read_text())
            if isinstance(loaded, dict):
                overrides = loaded
        except Exception:
            pass

    if args.reset_primary:
        overrides.pop("primary", None)
    elif (value := clean_hex(args.primary)):
        overrides["primary"] = value

    if args.reset_accent:
        overrides.pop("accent", None)
    elif (value := clean_hex(args.accent)):
        overrides["accent"] = value

    if args.reset_border:
        overrides.pop("hyprland_border", None)
    elif (value := clean_hex(args.border)):
        overrides["hyprland_border"] = value

    if args.reset_folder:
        overrides.pop("folder_color", None)
    elif (value := clean_hex(args.folder)):
        overrides["folder_color"] = value

    if args.palette_json is not None:
        try:
            overrides["palette"] = clean_palette(json.loads(args.palette_json))
        except Exception:
            overrides["palette"] = {}
        if not overrides["palette"]:
            overrides.pop("palette", None)

    if args.saved_json is not None:
        try:
            incoming = json.loads(args.saved_json)
        except Exception:
            incoming = []
        saved = []
        if isinstance(incoming, list):
            for item in incoming:
                value = clean_hex(item)
                if value and value not in saved:
                    saved.append(value)
                if len(saved) >= 32:
                    break
        overrides["saved_colors"] = saved
        if not saved:
            overrides.pop("saved_colors", None)

    if args.preset == "neutral-light":
        palette = clean_palette(overrides.get("palette", {}))
        palette.update(NEUTRAL_LIGHT)
        overrides["palette"] = palette
        overrides["mode"] = "light"
    elif args.preset == "neutral-dark":
        palette = clean_palette(overrides.get("palette", {}))
        palette.update(NEUTRAL_DARK)
        overrides["palette"] = palette
        overrides["mode"] = "dark"
    elif args.preset == "clear-palette":
        overrides.pop("palette", None)

    config_dir.mkdir(parents=True, exist_ok=True)
    tmp = overrides_file.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(overrides, indent=4) + "\n")
    tmp.replace(overrides_file)

    lua_fields = []
    if "hyprland_border" in overrides:
        lua_fields.append(
            f'    activeWindowBorderColour = "rgba({overrides["hyprland_border"]}e6)"'
        )
    hypr_vars_file.write_text("return {\n" + ",\n".join(lua_fields) + "\n}\n")

    if args.reset_primary or args.reset_border:
        mode = "dark"
        scheme_file = Path.home() / ".local/state/caelestia/scheme.json"
        if scheme_file.exists():
            try:
                mode = json.loads(scheme_file.read_text()).get("mode", "dark")
            except Exception:
                pass
        subprocess.run(
            ["caelestia", "scheme", "set", "-m", mode],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    apply_script = Path(__file__).resolve().parent / "apply_color_overrides.py"
    if apply_script.exists():
        subprocess.run([str(apply_script)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
