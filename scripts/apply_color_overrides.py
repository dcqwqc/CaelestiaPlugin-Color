#!/usr/bin/env python3
import glob
import json
import re
from pathlib import Path
import subprocess
import math
import shutil

from caelestia.utils.scheme import get_scheme
from caelestia.utils.theme import apply_colours

ICON_ROOTS = [str(Path.home() / ".local/share/icons"), "/usr/share/icons"]
PAPIRUS_THEMES = ["Papirus", "Papirus-Dark", "Papirus-Light"]
ICON_SIZES = ["16x16", "22x22", "24x24", "32x32", "48x48", "64x64"]


def accent_shades(hex_color):
    """Papirus' three folder tones derived from the shared accent colour."""
    from colorsys import rgb_to_hls, hls_to_rgb

    h = hex_color.lstrip("#")
    try:
        rgb = tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    except Exception:
        return None

    hl, ll, sl = rgb_to_hls(*rgb)

    def shade(factor):
        r, g, b = hls_to_rgb(hl, max(0, ll * factor), sl)
        return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"

    # Front is the accent itself, back is darker, the symbol darker still.
    return f"#{h.lower()}", shade(0.8), shade(0.3)


def recolour(src_file, dst_file, front, back, sym):
    try:
        content = Path(src_file).read_text()
        content = content.replace("#5294e2", front)
        content = content.replace("#4877b1", back)
        content = content.replace("#1d344f", sym)
        Path(dst_file).write_text(content)
        return True
    except Exception:
        return False


def generate_custom_papirus(hex_color):
    """Build the custom folder/home icon set for every Papirus copy we can write.

    Papirus may be a user-local copy on one host but only a system package on
    another. Writing solely to the user data dir silently did nothing on a
    system-wide install, which is how the two machines drifted apart on folder
    colour, so walk both roots and report the ones needing elevation.
    """
    import os

    shades = accent_shades(hex_color)
    if shades is None:
        return
    front, back, sym = shades

    for root in ICON_ROOTS:
        for theme in PAPIRUS_THEMES:
            base = os.path.join(root, theme)
            if not os.path.isdir(base):
                continue
            for size in ICON_SIZES:
                places = os.path.join(base, size, "places")
                if not os.path.isdir(places):
                    continue
                if not os.access(places, os.W_OK):
                    print(f"{places} is not writable; re-run papirus-folders as root to refresh it")
                    break

                for src_file in glob.glob(f"{places}/folder-blue*.svg"):
                    if src_file.endswith("bluegrey.svg") or "-bluegrey-" in src_file:
                        continue
                    recolour(src_file, src_file.replace("folder-blue", "folder-custom"),
                             front, back, sym)

                # papirus-folders only repoints the folder-* icons, so Home and
                # Desktop would keep upstream blue and clash with the accent.
                for src_file in glob.glob(f"{places}/user-blue*.svg"):
                    if "bluegrey" in src_file:
                        continue
                    dst_file = src_file.replace("user-blue", "user-custom")
                    if not recolour(src_file, dst_file, front, back, sym):
                        continue
                    link = dst_file.replace("user-custom", "user")
                    try:
                        if os.path.islink(link) or os.path.exists(link):
                            os.remove(link)
                        os.symlink(os.path.basename(dst_file), link)
                    except Exception:
                        pass


def main():
    config_dir = Path.home() / ".config/caelestia"
    overrides_file = config_dir / "color_overrides.json"

    scheme = get_scheme()

    overrides = {}
    if overrides_file.exists():
        try:
            overrides = json.loads(overrides_file.read_text())
        except Exception:
            pass

    primary_override = overrides.get("primary")
    desired_mode = overrides.get("mode")

    # Keep the chosen shared appearance mode when changing wallpapers. Dynamic
    # schemes support both modes; non-dynamic themes may expose fewer choices.
    if desired_mode:
        try:
            scheme.mode = desired_mode
        except ValueError:
            print(f"Scheme mode {desired_mode!r} is unavailable for {scheme.name!r}; keeping {scheme.mode!r}")

    if primary_override:
        # Regenerate the full M3 palette from the override color so secondary/tertiary
        # also harmonize with the chosen color instead of keeping wallpaper-derived tones.
        try:
            from materialyoucolor.hct import Hct
            from caelestia.utils.material.generator import gen_scheme
            hex_int = int(primary_override.strip("#"), 16)
            hct = Hct.from_int(0xFF000000 | hex_int)
            colours = gen_scheme(scheme, hct)
        except Exception as e:
            print("Full palette generation failed, falling back to partial override:", e)
            scheme._update_colours()
            colours = dict(scheme.colours)
            colours["primary"] = primary_override.strip("#")
            colours["primary_paletteKeyColor"] = primary_override.strip("#")
    else:
        scheme._update_colours()
        colours = dict(scheme.colours)

    # Per-role overrides are deliberately applied *after* Material 3 palette
    # generation. This makes the seed colour a convenient starting point while
    # still allowing exact control of every shell colour without the generator
    # re-tinting surfaces, containers or semantic colours behind the user's back.
    palette_overrides = overrides.get("palette", {})
    if isinstance(palette_overrides, dict):
        for role, value in palette_overrides.items():
            if role not in colours or not isinstance(value, str):
                continue
            clean = value.strip().lstrip("#")
            if re.fullmatch(r"[0-9a-fA-F]{6}", clean):
                colours[role] = clean.lower()

    scheme._colours = colours
    scheme.save()

    apply_colours(scheme.colours, scheme.mode)

    # Ghostty intentionally stays dark even when the desktop is light, but its
    # terminal palette follows the dark variant of the active Caelestia scheme.
    ghostty_theme = Path.home() / ".config/caelestia/update_ghostty_theme.py"
    if ghostty_theme.exists():
        try:
            subprocess.run([str(ghostty_theme)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass


    # Hyprtoolkit powers native Hyprland dialogs (e.g. "Application Not Responding").
    # It does not use GTK colours; without this file its built-in accent is #00ffcc.
    # Keep these system dialogs deliberately dark, while syncing the accent to the
    # rendered Caelestia primary so the buttons/highlights follow Color Settings.
    try:
        rendered_primary = str(scheme.colours.get("primary", primary_override or "89b4fa")).strip().lstrip("#")
        if not re.fullmatch(r"[0-9a-fA-F]{6}", rendered_primary):
            rendered_primary = "89b4fa"
        ht_dir = Path.home() / ".config/hypr"
        ht_dir.mkdir(parents=True, exist_ok=True)
        ht_conf = ht_dir / "hyprtoolkit.conf"
        ht_conf.write_text(
            "# Generated by CaelestiaPlugin-Color\n"
            "# Native Hyprtoolkit dialogs: dark neutral surfaces + Caelestia accent.\n"
            "background = 0xFF0A0A0A\n"
            "base = 0xFF171717\n"
            "text = 0xFFF5F5F5\n"
            "alternate_base = 0xFF202020\n"
            "bright_text = 0xFFFFFFFF\n"
            f"accent = 0xFF{rendered_primary.upper()}\n"
            f"accent_secondary = 0xFF{rendered_primary.upper()}\n"
            "rounding_large = 14\n"
            "rounding_small = 8\n"
        )
    except Exception as e:
        print("Failed to update hyprtoolkit theme:", e)

    if primary_override:
        hex_color = "#" + primary_override.strip("#")
        for gtk_version in ["gtk-3.0", "gtk-4.0"]:
            gtk_css = Path.home() / f".config/{gtk_version}/gtk.css"
            if gtk_css.exists():
                try:
                    content = gtk_css.read_text()
                    new_content = re.sub(
                        r'(@define-color\s+accent_color\s+)#[0-9a-fA-F]+(;)',
                        f'\\1{hex_color}\\2', content)
                    new_content = re.sub(
                        r'(@define-color\s+accent_bg_color\s+)#[0-9a-fA-F]+(;)',
                        f'\\1{hex_color}\\2', new_content)
                    gtk_css.write_text(new_content)
                except Exception as e:
                    print(f"Failed to update {gtk_version}/gtk.css:", e)

    folder_override = overrides.get("folder_color")
    papirus_folders = shutil.which("papirus-folders")
    if folder_override and papirus_folders:
        generate_custom_papirus(folder_override)
        # Papirus-Light and Papirus-Dark symlink their larger size directories
        # into the base Papirus theme, so the base theme has to be recoloured
        # too or every icon above 24x24 stays upstream blue.
        for theme in PAPIRUS_THEMES:
            subprocess.run([papirus_folders, "-C", "custom", "-t", theme, "-u"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif papirus_folders:
        for theme in PAPIRUS_THEMES:
            subprocess.run([papirus_folders, "-D", "-t", theme, "-u"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print("papirus-folders is not installed; keeping the current folder icons")

    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    

if __name__ == "__main__":
    main()
