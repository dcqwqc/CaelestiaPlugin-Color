"""Global primary and accent must remain independently editable."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import save_colors


class GlobalAccentTests(unittest.TestCase):
    def test_accent_does_not_change_primary_or_precise_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            cfg = home / ".config/caelestia"
            cfg.mkdir(parents=True)
            target = cfg / "color_overrides.json"
            existing = {"primary": "234c15", "palette": {"onPrimary": "fefefe"}}
            target.write_text(json.dumps(existing))
            with patch.object(Path, "home", return_value=home), \
                 patch.object(sys, "argv", ["save_colors.py", "--accent", "#ab84d6"]), \
                 patch.object(save_colors.subprocess, "run"):
                save_colors.main()
            actual = json.loads(target.read_text())
            self.assertEqual(actual["primary"], "234c15")
            self.assertEqual(actual["accent"], "ab84d6")
            self.assertEqual(actual["palette"], existing["palette"])

    def test_reset_accent_preserves_primary(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            cfg = home / ".config/caelestia"
            cfg.mkdir(parents=True)
            target = cfg / "color_overrides.json"
            target.write_text(json.dumps({"primary": "123456", "accent": "abcdef"}))
            with patch.object(Path, "home", return_value=home), \
                 patch.object(sys, "argv", ["save_colors.py", "--reset-accent"]), \
                 patch.object(save_colors.subprocess, "run"):
                save_colors.main()
            actual = json.loads(target.read_text())
            self.assertEqual(actual["primary"], "123456")
            self.assertNotIn("accent", actual)


if __name__ == "__main__":
    unittest.main()
