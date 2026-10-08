import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import color_profiles as cp


class ColorProfilesTests(unittest.TestCase):
    def test_wallpaper_engine_identity_stays_stable(self):
        a = cp.wallpaper_key("/home/qwqc/Pictures/Wallpapers/WallpaperEngine/Lain_theme_3369752393.gif")
        b = cp.wallpaper_key("/home/qwqc/Pictures/Wallpapers/WallpaperEngine/Renamed_3369752393.jpg")
        self.assertEqual(a, b)
        self.assertEqual(a, "wpe:3369752393")

    def test_unlinked_wallpaper_does_not_change_globals(self):
        globals_ = {"primary": "aabbcc", "palette": {"onPrimary": "ffffff"}}
        self.assertEqual(cp.merged_overrides(globals_, "/foo.jpg", {"bindings": {}, "profiles": {}}), globals_)

    def test_profile_overrides_keep_role_priority(self):
        base = {"primary": "ff0000", "palette": {"onPrimary": "ffffff", "surface": "111111"}}
        data = {
            "bindings": {"wpe:3369752393": "rose"},
            "profiles": {"rose": {"name": "Rose", "primary": "abcdef",
                                   "accent": "#ff00cc", "palette": {"onPrimary": "000000"}}},
        }
        merged = cp.merged_overrides(base, "/tmp/WallpaperEngine/Lain_3369752393.gif", data)
        self.assertEqual(merged["primary"], "abcdef")
        self.assertEqual(merged["accent"], "ff00cc")
        self.assertEqual(merged["palette"], {"onPrimary": "000000", "surface": "111111"})
        self.assertEqual(base["primary"], "ff0000")

    def test_neutral_snapshot_does_not_freeze_light_mode(self):
        from save_colors import NEUTRAL_LIGHT
        source = {"primary": "234c15", "palette": {
            **NEUTRAL_LIGHT, "tertiary": "aabbcc"
        }, "neutral_preset_mode": "light"}
        snapshot = cp.snapshot_overrides(source)
        self.assertEqual(snapshot["primary"], "234c15")
        self.assertEqual(snapshot["palette"], {"tertiary": "aabbcc"})
        self.assertNotIn("mode", snapshot)

    def test_corrupted_store_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            original_store = cp.STORE
            path = Path(tmp) / "profiles.json"
            path.write_text("{broken JSON")
            cp.STORE = path
            try:
                with self.assertRaises(ValueError):
                    with cp.locked_store() as data:
                        data["profiles"]["new"] = {}
                self.assertEqual(path.read_text(), "{broken JSON")
            finally:
                cp.STORE = original_store

    def test_create_edit_link_unlink_and_persistence(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "wallpaper_profiles.json"
            env = {**os.environ, "CAELESTIA_COLOR_PROFILES_PATH": str(target),
                   "CAELESTIA_COLOR_PROFILES_NO_APPLY": "1"}
            cmd = [sys.executable, str(ROOT / "scripts/color_profiles.py")]
            wall = "/tmp/WallpaperEngine/Lain_3369752393.gif"
            def run(*args):
                return subprocess.check_output(cmd + list(args) + ["--wallpaper", wall], env=env, text=True).strip()
            profile_id = run("create", "--name", "Lain's palette", "--primary", "6688aa")
            run("edit", "--id", profile_id, "--accent", "#ffccee")
            self.assertEqual(json.loads(run("status"))["activeProfile"]["accent"], "ffccee")
            run("unlink")
            self.assertIsNone(json.loads(run("status"))["activeProfileId"])
            run("link", "--id", profile_id)
            self.assertEqual(json.loads(run("status"))["activeProfileId"], profile_id)
            self.assertEqual(json.loads(target.read_text())["version"], 1)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
