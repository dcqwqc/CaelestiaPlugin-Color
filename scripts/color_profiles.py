#!/usr/bin/env python3
"""Wallpaper-specific Caelestia color profiles (no changes to global overrides).

One profile can be linked to many wallpapers. Wallpaper Engine items use their
Workshop ID, so the binding survives a different preview filename or host.
Normal image paths use their path relative to ~/Pictures/Wallpapers when possible.
"""
import argparse
import fcntl
import json
import os
import re
import subprocess
import uuid
from contextlib import contextmanager
from pathlib import Path

HOME = Path.home()
STORE = Path(os.environ.get("CAELESTIA_COLOR_PROFILES_PATH", HOME / ".config/caelestia/wallpaper_profiles.json"))
GLOBAL = HOME / ".config/caelestia/color_overrides.json"
CURRENT = HOME / ".local/state/caelestia/wallpaper/path.txt"
WALLS = HOME / "Pictures/Wallpapers"
ALLOWED = {"primary", "accent", "palette", "hyprland_border", "folder_color"}
HEX = re.compile(r"^#?[0-9a-fA-F]{6}$")
WPE = re.compile(r"_([0-9]{7,12})\.(?:png|jpe?g|webp|gif)$", re.I)


def wallpaper_key(path=None):
    path = path or os.environ.get("WALLPAPER_PATH", "")
    if not path:
        try:
            path = CURRENT.read_text().strip()
        except OSError:
            return ""
    p = Path(path).expanduser()
    s = str(p)
    if "/WallpaperEngine/" in s:
        m = WPE.search(p.name)
        if m:
            return "wpe:" + m.group(1)
    m = re.search(r"/steamapps/workshop/content/431960/([0-9]+)/", s)
    if m:
        return "wpe:" + m.group(1)
    try:
        return "file:" + p.resolve().relative_to(WALLS.resolve()).as_posix()
    except ValueError:
        return "path:" + str(p.resolve())


def load():
    if not STORE.exists():
        return {"version": 1, "profiles": {}, "bindings": {}}
    try:
        d = json.loads(STORE.read_text())
    except (OSError, ValueError) as exc:
        raise ValueError(f"Invalid wallpaper profiles at {STORE}; original preserved") from exc
    if (not isinstance(d, dict) or d.get("version") != 1
            or not isinstance(d.get("profiles"), dict)
            or not isinstance(d.get("bindings"), dict)):
        raise ValueError(f"Unknown wallpaper profile format at {STORE}; original preserved")
    return d


@contextmanager
def locked_store():
    STORE.parent.mkdir(parents=True, exist_ok=True)
    with (STORE.parent / (STORE.name + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = load()
        yield data
        tmp = STORE.with_name(STORE.name + "." + str(os.getpid()) + ".tmp")
        with tmp.open("w") as f:
            os.fchmod(f.fileno(), 0o600)
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
        tmp.replace(STORE)


def clean_hex(value):
    if value is None or not HEX.fullmatch(value):
        raise ValueError("Expected #RRGGBB hex color")
    return value.lstrip("#").lower()


def sanitize_profile(profile):
    """Reject invalid data instead of passing corrupt custom colors to M3."""
    out = {}
    for name in ("primary", "accent", "hyprland_border", "folder_color"):
        if name in profile:
            try:
                out[name] = clean_hex(profile[name])
            except (TypeError, ValueError):
                pass
    if isinstance(profile.get("palette"), dict):
        from save_colors import clean_palette
        out["palette"] = clean_palette(profile["palette"])
    return out


def active_profile(path=None, store=None):
    data = store if store is not None else load()
    identifier = data.get("bindings", {}).get(wallpaper_key(path))
    profile = data.get("profiles", {}).get(identifier)
    return (identifier, profile) if isinstance(profile, dict) else (None, None)


def merged_overrides(global_overrides, path=None, store=None):
    """Profile colors win over global defaults, exact role overrides win last."""
    _, profile = active_profile(path, store)
    if profile is None:
        return global_overrides
    overlay = sanitize_profile(profile)
    result = dict(global_overrides)
    if "palette" in overlay:
        result["palette"] = {**(global_overrides.get("palette") or {}), **overlay.pop("palette")}
    result.update(overlay)
    return result


def refresh():
    if os.environ.get("CAELESTIA_COLOR_PROFILES_NO_APPLY") == "1":
        return
    helper = Path(__file__).resolve().with_name("apply_color_overrides.py")
    subprocess.run([str(helper)], check=True, timeout=60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("status", "create", "link", "unlink", "edit", "delete"))
    parser.add_argument("--id")
    parser.add_argument("--name")
    parser.add_argument("--primary")
    parser.add_argument("--accent")
    parser.add_argument("--wallpaper")
    args = parser.parse_args()
    key = wallpaper_key(args.wallpaper)
    if args.action == "status":
        d = load()
        selected, active = active_profile(args.wallpaper, d)
        print(json.dumps({"wallpaperKey": key, "activeProfileId": selected,
                          "activeProfile": active, "profiles": d["profiles"],
                          "bindings": d["bindings"]}, ensure_ascii=False))
        return
    with locked_store() as d:
        if args.action == "create":
            try:
                existing = json.loads(GLOBAL.read_text())
            except (OSError, ValueError):
                existing = {}
            data = sanitize_profile(existing)
            if args.primary:
                data["primary"] = clean_hex(args.primary)
            if args.accent:
                data["accent"] = clean_hex(args.accent)
            if args.name:
                name = args.name.strip()[:80]
            else:
                name = "Wallpaper colors " + str(len(d["profiles"]) + 1)
            identifier = uuid.uuid4().hex[:12]
            d["profiles"][identifier] = {"name": name or "Untitled", **data}
            if key:
                d["bindings"][key] = identifier
            print(identifier)
        elif args.action == "link":
            if not key or args.id not in d["profiles"]:
                parser.error("A current wallpaper and valid --id are required")
            d["bindings"][key] = args.id
        elif args.action == "unlink":
            d["bindings"].pop(key, None)
        elif args.action == "edit":
            if args.id not in d["profiles"]:
                parser.error("Profile --id not found")
            profile = d["profiles"][args.id]
            for field in ("primary", "accent"):
                value = getattr(args, field)
                if value is not None:
                    profile[field] = clean_hex(value)
            if args.name is not None:
                profile["name"] = args.name.strip()[:80] or "Untitled"
        elif args.action == "delete":
            if args.id not in d["profiles"]:
                parser.error("Profile --id not found")
            del d["profiles"][args.id]
            d["bindings"] = {k: v for k, v in d["bindings"].items() if v != args.id}
    refresh()


if __name__ == "__main__":
    main()
