import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = str(ROOT / "scripts" / "color_profiles.py")
WALL = "/home/qwqc/Pictures/Wallpapers/WallpaperEngine/Sample_3369752393.gif"


class ProfileLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "wallpaper_profiles.json"
        self.env = {**os.environ,
                    "CAELESTIA_COLOR_PROFILES_PATH": str(self.path),
                    "CAELESTIA_COLOR_PROFILES_NO_APPLY": "1"}

    def tearDown(self):
        self.temp.cleanup()

    def call(self, action, *params, success=True):
        proc = subprocess.run([sys.executable, CLI, action, "--wallpaper", WALL,
                               *params], text=True, capture_output=True, env=self.env)
        if success:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        else:
            self.assertNotEqual(proc.returncode, 0)
        return proc.stdout.strip()

    def status(self):
        return json.loads(self.call("status"))

    def test_crud_undo_and_shared_profile_binding(self):
        original = self.status()
        self.assertEqual(original["wallpaperKey"], "wpe:3369752393")
        ident = self.call("create", "--name", "Midnight")
        self.assertEqual(self.status()["activeProfileId"], ident)
        self.call("edit", "--id", ident, "--name", "Purple nights",
                  "--primary", "#3e64a2", "--accent", "#b070c0")
        self.assertEqual(self.status()["activeProfile"]["name"], "Purple nights")
        self.call("set-role", "--id", ident, "--role", "primaryContainer",
                  "--color", "#abcdef")
        self.assertEqual(self.status()["activeProfile"]["palette"]["primaryContainer"], "abcdef")
        self.call("reset-role", "--id", ident, "--role", "primaryContainer")
        self.assertNotIn("palette", self.status()["activeProfile"])
        duplicate = self.call("duplicate", "--id", ident)
        self.assertNotEqual(ident, duplicate)
        self.assertEqual(self.status()["activeProfileId"], duplicate)
        self.call("unlink")
        self.assertIsNone(self.status()["activeProfileId"])
        self.call("link", "--id", ident)
        self.call("delete", "--id", ident)
        self.assertIsNone(self.status()["activeProfileId"])
        self.call("undo")
        self.assertEqual(self.status()["activeProfileId"], ident)
        self.assertEqual(self.status()["activeProfile"]["name"], "Purple nights")
        self.call("undo")
        self.assertIsNone(self.status()["activeProfileId"])
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_invalid_role_leaves_store_unchanged(self):
        ident = self.call("create", "--name", "Test")
        before = self.path.read_bytes()
        self.call("set-role", "--id", ident, "--role", "unexpected",
                  "--color", "#abc123", success=False)
        self.assertEqual(self.path.read_bytes(), before)
        self.call("set-role", "--id", ident, "--role", "secondary",
                  "--color", "invalid-color", success=False)
        self.assertEqual(self.path.read_bytes(), before)

    def test_concurrent_creates_do_not_lose_profiles(self):
        cmds = [
            [sys.executable, CLI, "create", "--wallpaper", WALL, "--name", "Alpha"],
            [sys.executable, CLI, "create", "--wallpaper", WALL, "--name", "Beta"],
        ]
        first = subprocess.Popen(cmds[0], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        second = subprocess.Popen(cmds[1], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out_a, err_a = first.communicate(timeout=10)
        out_b, err_b = second.communicate(timeout=10)
        self.assertEqual(first.returncode, 0, err_a)
        self.assertEqual(second.returncode, 0, err_b)
        stored = self.status()
        self.assertEqual(len(stored["profiles"]), 2)
        self.assertIn(out_a.strip(), stored["profiles"])
        self.assertIn(out_b.strip(), stored["profiles"])

    def test_corrupt_store_keeps_global_palette_in_apply_hook(self):
        import color_profiles as cp
        original = cp.STORE
        try:
            cp.STORE = self.path
            self.path.write_text("NOT JSON")
            global_colors = {"primary": "abcdef", "palette": {"onSurface": "eeeeee"}}
            self.assertEqual(cp.merged_overrides(global_colors, WALL), global_colors)
            self.assertEqual(self.path.read_text(), "NOT JSON")
        finally:
            cp.STORE = original

    def test_renamed_preview_same_profile(self):
        ident = self.call("create", "--name", "Portable")
        renamed = subprocess.run(
            [sys.executable, CLI, "status", "--wallpaper",
             "/home/qwqc/Pictures/Wallpapers/WallpaperEngine/New_name_3369752393.jpg"],
            text=True, capture_output=True, env=self.env, check=True,
        )
        self.assertEqual(json.loads(renamed.stdout)["activeProfileId"], ident)


if __name__ == "__main__":
    unittest.main()
