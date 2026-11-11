"""Packaging gates: what `omarchy plugin add` needs, and nothing personal."""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((PROJECT / "manifest.json").read_text(encoding="utf-8"))
FILES = [p for p in PROJECT.rglob("*")
         if p.is_file() and ".git" not in p.relative_to(PROJECT).parts and "__pycache__" not in p.parts]


class PackagingTests(unittest.TestCase):
    def test_manifest_points_at_the_bar_widget(self):
        self.assertEqual(MANIFEST["schemaVersion"], 1)
        self.assertFalse(MANIFEST["id"].startswith("omarchy."))
        self.assertTrue((PROJECT / MANIFEST["entryPoints"]["barWidget"]).is_file())
        widget = (PROJECT / "BarWidget.qml").read_text(encoding="utf-8")
        self.assertIn(f'moduleName: "{MANIFEST["id"]}"', widget)

    @unittest.skipUnless(shutil.which("omarchy-plugin-validate"), "needs Omarchy")
    def test_omarchy_accepts_the_folder(self):
        result = subprocess.run(["omarchy-plugin-validate", str(PROJECT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_scripts_are_found_next_to_the_qml(self):
        ticker = (PROJECT / "MarketTicker.qml").read_text(encoding="utf-8")
        self.assertIn('localFilePath(Qt.resolvedUrl("market-feed/fetch_markets.py"))', ticker)
        self.assertIn('localFilePath(Qt.resolvedUrl("market-feed/watchlist.py"))', ticker)

    def test_no_personal_paths_or_symlinks(self):
        for path in FILES:
            with self.subTest(path=str(path.relative_to(PROJECT))):
                self.assertFalse(path.is_symlink())
                self.assertNotRegex(path.read_text(encoding="utf-8", errors="ignore"), r"/(?:home|Users)/\w")


if __name__ == "__main__":
    unittest.main()
