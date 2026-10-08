import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class QuickColorsUiContracts(unittest.TestCase):
    def test_shared_quick_picker_is_owned_by_plugin(self):
        quick = (ROOT / "QuickColors.qml").read_text()
        settings = (ROOT / "SettingsUi.qml").read_text()
        self.assertIn("QuickColors {", settings)
        self.assertIn("id: spectrumField", quick)
        self.assertNotIn("id: spectrumField", settings)
        self.assertEqual(quick.count("SpectrumRing { tone:"), 3)
        self.assertIn('border.color: "#ffffff"', quick)
        self.assertNotIn('text: "B"', quick)
        self.assertNotIn('text: "L"', quick)
        self.assertNotIn('text: "D"', quick)

    def test_fast_global_and_wallpaper_profile_paths(self):
        quick = (ROOT / "QuickColors.qml").read_text()
        self.assertIn('root.profileRun(["create"])', quick)
        self.assertIn('root.profileRun(["unlink"])', quick)
        self.assertIn('root.profileRun(["undo"])', quick)
        self.assertIn('root.profileRun(["link", "--id", modelData])', quick)
        self.assertIn('root.run(["--" + root.wheelTarget, hex])', quick)
        self.assertIn('root.profileRun(["edit", "--id", root.profileState.activeProfileId, "--" + root.wheelTarget, hex])', quick)
        self.assertIn('onReleased: {\n                    root.applySpectrum();', quick)


if __name__ == "__main__":
    unittest.main()
