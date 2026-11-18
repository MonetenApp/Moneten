#!/usr/bin/env python3
"""Tests of scripts/licenses.py, run by scripts/check.sh and by the specs job of CI. Each test runs on a
copy of the files that the script reads, and on a made-up app folder, so it needs no build and no network."""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts/licenses.py"
# The files that licenses.py reads, as it lists them for the check at a tag.
FILES = subprocess.run([sys.executable, str(SCRIPT), "inputs"], capture_output=True, text=True, check=True).stdout.split()
MACH_O = b"\xcf\xfa\xed\xfe" + bytes(28)


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
		"""A made-up app with a file at each path that an entry names, and a Java runtime with two modules."""
		app = Path(self.folder.name) / "Moneten.app"
		for part in [self.notices["app"], *self.notices["parts"]]:
			for path in part.get("paths", []):
				path = app / "Contents" / path.replace("{version}", part.get("version", ""))
				path.parent.mkdir(parents=True, exist_ok=True)
				if path.suffix in (".framework", ".bundle") or path.name == "runtime":
					path.mkdir()
				else:
					path.write_bytes(MACH_O if "." not in path.name else b"")
		runtime = app / "Contents/Resources/FinTSHelper/runtime"
		(runtime / "release").write_text('JAVA_VERSION="17.0.21"\nMODULES="java.base java.desktop"\n')
		for module in ("java.base", "java.desktop"):
			(runtime / "legal" / module).mkdir(parents=True)
			(runtime / "legal" / module / "LICENSE").touch()
		(runtime / "lib").mkdir(exist_ok=True)
		(runtime / "lib/libjava.dylib").write_bytes(MACH_O)
		self.assertEqual(self.run_script("build", str(app), "0.1.0").returncode, 0)
		return app

	def add(self, app, path, data=b""):
		path = app / "Contents" / path
		path.parent.mkdir(parents=True, exist_ok=True)
		path.write_bytes(data)
		return self.run_script("check-app", str(app))

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
		self.assertIn("hbci4java-4.1.17-source.tar.gz", page)
		self.assertIn("https://github.com/hbci4j/hbci4java/archive/refs/tags/hbci4j-core-4.1.17.tar.gz", page)
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
		self.assertIn("lacks legal/java.base/LICENSE", self.run_script("check-app", str(app)).stderr)

	def test_app_without_legal_folder_of_one_module_fails(self):
		app = self.app()
		shutil.rmtree(app / "Contents/Resources/FinTSHelper/runtime/legal/java.desktop")
		self.assertIn("lacks legal/java.desktop/LICENSE, the notices of its module java.desktop", self.run_script("check-app", str(app)).stderr)

	def test_app_with_nested_parts_fails(self):
		for path, data in [("Helpers/Tools/lib/example-tools-1.0.0.jar", b""), ("Resources/Example/libexample.dylib", MACH_O),
				("Library/LoginItems/Example.app/Contents/Frameworks/Example.framework/Example", MACH_O),
				("PlugIns/Example.appex/Contents/MacOS/Example", MACH_O), ("Resources/example-tool", MACH_O)]:
			with self.subTest(path=path):
				app = self.app()
				result = self.add(app, path, data)
				self.assertNotEqual(result.returncode, 0)
				self.assertIn("which no entry of Licenses/notices.json claims", result.stderr)
				shutil.rmtree(app)

	def test_app_with_parts_inside_claimed_bundles_passes(self):
		app = self.app()
		self.assertEqual(self.add(app, "Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer", MACH_O).returncode, 0)
		self.assertEqual(self.add(app, "Resources/FinTSHelper/runtime/lib/server/libjvm.dylib", MACH_O).returncode, 0)
		self.assertEqual(self.add(app, "Resources/notes.txt", b"text").returncode, 0)

	def test_jar_inside_a_claimed_bundle_fails(self):
		for path in ("Frameworks/Sparkle.framework/Versions/B/Resources/example-tools-1.0.0.jar",
				"Resources/FinTSHelper/runtime/lib/example-tools-1.0.0.jar"):
			with self.subTest(path=path):
				app = self.app()
				result = self.add(app, path)
				self.assertIn(f"the jar Contents/{path}, which no entry", result.stderr)
				shutil.rmtree(app)

	def test_fat_64_binary_without_extension_fails(self):
		for magic in (b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
			with self.subTest(magic=magic.hex()):
				app = self.app()
				self.assertIn("Contents/Resources/example-tool, which no entry", self.add(app, "Resources/example-tool", magic + bytes(28)).stderr)
				shutil.rmtree(app)

	def test_debug_library_of_the_app_passes(self):
		self.assertEqual(self.add(self.app(), "MacOS/Moneten.debug.dylib", MACH_O).returncode, 0)

	def test_source_url_without_version_fails(self):
		self.part("maven:com.github.hbci4j:hbci4j-core")["source"]["url"] = "https://example.com/hbci4java-4.1.17.tar.gz"
		self.save()
		self.assertIn("must contain its version as a placeholder", self.run_script("check").stderr)

	def test_new_version_never_keeps_the_old_source(self):
		archives = Path(self.folder.name) / "archives"
		archives.mkdir()
		(archives / "hbci4java-4.1.17.tar.gz").write_bytes(b"source of 4.1.17")
		(archives / "hbci4java-4.1.18.tar.gz").write_bytes(b"source of 4.1.18")
		part = self.part("maven:com.github.hbci4j:hbci4j-core")
		part["source"]["url"] = "https://example.invalid/hbci4java-{version}.tar.gz"
		part["source"]["sha256"] = hashlib.sha256(b"source of 4.1.17").hexdigest()
		self.save()
		self.assertIn("hbci4java-4.1.17-source.tar.gz", self.run_script("source-names").stdout)
		# The new version in the lock and in the entry, with the SHA-256 of the old source left alone.
		lock = self.root / "Tools/FinTSProbeJava/dependencies.lock"
		lock.write_text(lock.read_text().replace("hbci4j-core:4.1.17", "hbci4j-core:4.1.18"))
		part["version"] = "4.1.18"
		self.save()
		self.assertEqual(self.run_script("check").returncode, 0)
		names = self.run_script("source-names").stdout
		self.assertIn("hbci4java-4.1.18-source.tar.gz", names)
		self.assertNotIn("4.1.17", names)
		# The download reads the archives from a local folder, which only a part outside the GPL may name.
		part["source"]["url"] = archives.as_uri() + "/hbci4java-{version}.tar.gz"
		part["license"] = "MIT"
		del self.part("jdk:temurin-aarch64-mac")["source"]["sha256"]
		self.part("jdk:temurin-aarch64-mac")["license"] = "MIT"
		self.save()
		result = self.run_script("sources", str(Path(self.folder.name) / "out"))
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("hbci4java-4.1.18.tar.gz of maven:com.github.hbci4j:hbci4j-core 4.1.18 has a wrong SHA-256", result.stderr)

	def test_other_package_in_the_project_fails(self):
		project = self.root / "App/project.yml"
		project.write_text(project.read_text().replace("packages:\n", "packages:\n  Example:\n    url: https://example.com/example\n    exactVersion: 1.0.0\n"))
		self.assertIn("App/project.yml adds the packages Example:", self.run_script("check").stderr)

	def test_other_package_in_inline_form_fails(self):
		project = self.root / "App/project.yml"
		inline = '  Example: {url: "https://example.com/example", exactVersion: "1.0.0"}\n'
		project.write_text(project.read_text().replace("packages:\n", "packages:\n" + inline))
		self.assertIn("App/project.yml adds the packages Example: {url", self.run_script("check").stderr)

	def test_unreachable_source_fails_with_its_name(self):
		part = self.part("maven:com.github.hbci4j:hbci4j-core")
		part["source"]["url"] = (Path(self.folder.name) / "missing").as_uri() + "/hbci4java-{version}.tar.gz"
		part["license"] = "MIT"
		del self.part("jdk:temurin-aarch64-mac")["source"]["sha256"]
		self.part("jdk:temurin-aarch64-mac")["license"] = "MIT"
		self.save()
		result = self.run_script("sources", str(Path(self.folder.name) / "out"))
		self.assertIn("of maven:com.github.hbci4j:hbci4j-core 4.1.17 cannot be downloaded", result.stderr)
		self.assertNotIn("Traceback", result.stderr)

	def test_test_only_package_needs_no_path(self):
		resolved = json.loads((self.root / "Package.resolved").read_text())
		resolved["pins"].append({"identity": "example-testing", "kind": "remoteSourceControl", "location": "https://example.com/t",
			"state": {"revision": "0" * 40, "version": "1.0.0"}})
		(self.root / "Package.resolved").write_text(json.dumps(resolved))
		self.notices["parts"].append({"id": "swiftpm:example-testing", "version": "1.0.0", "testOnly": True})
		self.save()
		self.assertEqual(self.run_script("check").returncode, 0, self.run_script("check").stderr)
		app = self.app()
		self.assertEqual(self.run_script("check-app", str(app)).returncode, 0)
		self.assertNotIn("example-testing", (app / "Contents/Resources/en.lproj/Licenses.html").read_text())


if __name__ == "__main__":
	unittest.main()
