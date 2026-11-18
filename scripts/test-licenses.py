#!/usr/bin/env python3
"""Tests of scripts/licenses.py, run by scripts/check.sh and by the specs job of CI. Each test runs on a
copy of the files that the script reads, and on a made-up app folder, so it needs no build and no network."""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts/licenses.py"
FILES = ["Licenses", "LICENSE", "Tools/FinTSProbeJava/dependencies.lock", "Package.resolved", "scripts/sparkle-tools.sh",
	"Sources/CLua/VERSION", "Sources/ExtensionHost/PublicSuffix/VERSION"]


class LicensesTests(unittest.TestCase):
	def setUp(self):
		self.folder = tempfile.TemporaryDirectory()
		self.root = Path(self.folder.name) / "repo"
		for name in FILES:
			source, target = REPO / name, self.root / name
			target.parent.mkdir(parents=True, exist_ok=True)
			(shutil.copytree if source.is_dir() else shutil.copyfile)(source, target)
		self.notices = json.loads((self.root / "Licenses/notices.json").read_text())

	def tearDown(self):
		self.folder.cleanup()

	def run_script(self, *args):
		return subprocess.run([sys.executable, str(SCRIPT), "--root", str(self.root), *args], capture_output=True, text=True)

	def save(self):
		(self.root / "Licenses/notices.json").write_text(json.dumps(self.notices))

	def part(self, key):
		return next(part for part in self.notices["parts"] if part["id"] == key)

	def app(self):
		"""A made-up app with a file at each path that an entry names."""
		app = Path(self.folder.name) / "Moneten.app"
		for part in [self.notices["app"], *self.notices["parts"]]:
			for path in part["paths"]:
				path = app / "Contents" / path.replace("{version}", part.get("version", ""))
				path.parent.mkdir(parents=True, exist_ok=True)
				path.touch()
		self.assertEqual(self.run_script("build", str(app), "0.1.0").returncode, 0)
		return app

	def test_repository_passes(self):
		result = self.run_script("check")
		self.assertEqual(result.returncode, 0, result.stderr)

	def test_missing_entry_of_a_jar_fails(self):
		self.notices["parts"].remove(self.part("maven:org.glassfish.jaxb:txw2"))
		self.save()
		result = self.run_script("check")
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("maven:org.glassfish.jaxb:txw2 4.0.5 ships", result.stderr)

	def test_new_pin_without_entry_fails(self):
		lock = self.root / "Tools/FinTSProbeJava/dependencies.lock"
		lock.write_text(lock.read_text() + "org.example:example-tools:1.0.0 " + "0" * 64 + "\n")
		result = self.run_script("check")
		self.assertIn("maven:org.example:example-tools 1.0.0 ships", result.stderr)

	def test_other_version_fails(self):
		resolved = json.loads((self.root / "Package.resolved").read_text())
		resolved["pins"][0]["state"]["version"] = "7.13.0"
		(self.root / "Package.resolved").write_text(json.dumps(resolved))
		result = self.run_script("check")
		self.assertIn("swiftpm:grdb.swift ships in version 7.13.0", result.stderr)

	def test_new_sparkle_version_fails(self):
		script = self.root / "scripts/sparkle-tools.sh"
		script.write_text(script.read_text().replace("VERSION=2.10.1", "VERSION=2.11.0"))
		self.assertIn("swiftpm:sparkle ships in version 2.11.0", self.run_script("check").stderr)

	def test_entry_without_pin_fails(self):
		self.notices["parts"].append(dict(self.part("vendor:lua"), id="vendor:example"))
		self.save()
		self.assertIn("vendor:example, which no pin ships", self.run_script("check").stderr)

	def test_gpl_part_without_source_fails(self):
		del self.part("jdk:temurin-aarch64-mac")["source"]["sha256"]
		self.save()
		self.assertIn("needs a source archive", self.run_script("check").stderr)

	def test_missing_license_text_fails(self):
		(self.root / "Licenses/GRDB-LICENSE.txt").unlink()
		self.assertIn("Licenses/GRDB-LICENSE.txt of swiftpm:grdb.swift is missing", self.run_script("check").stderr)

	def test_built_app_passes(self):
		app = self.app()
		result = self.run_script("check-app", str(app))
		self.assertEqual(result.returncode, 0, result.stderr)
		page = (app / "Contents/Resources/de.lproj/Licenses.html").read_text()
		self.assertIn("<title>Moneten: Lizenzen</title>", page)
		self.assertIn('data-part="maven:com.github.hbci4j:hbci4j-core@4.1.17"', page)
		self.assertIn("hbci4j-core-4.1.17-sources.jar", page)
		self.assertIn("https://github.com/MonetenApp/Moneten/releases/tag/v0.1.0", page)

	def test_app_without_page_fails(self):
		app = self.app()
		(app / "Contents/Resources/en.lproj/Licenses.html").unlink()
		self.assertIn("The app has no Contents/Resources/en.lproj/Licenses.html", self.run_script("check-app", str(app)).stderr)

	def test_app_with_unclaimed_jar_fails(self):
		app = self.app()
		(app / "Contents/Resources/FinTSHelper/lib/example-tools-1.0.0.jar").touch()
		self.assertIn("ships Contents/Resources/FinTSHelper/lib/example-tools-1.0.0.jar", self.run_script("check-app", str(app)).stderr)

	def test_app_without_legal_folder_fails(self):
		app = self.app()
		shutil.rmtree(app / "Contents/Resources/FinTSHelper/runtime/legal")
		self.assertIn("runtime/legal/java.base/LICENSE, which the app lacks", self.run_script("check-app", str(app)).stderr)


if __name__ == "__main__":
	unittest.main()
