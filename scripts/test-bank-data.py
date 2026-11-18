#!/usr/bin/env python3
"""Tests of scripts/bank-data.py, run by scripts/check.sh and by the specs job of CI. They build from a
made-up jar and sign with throwaway keys, so they need no network and no secret."""

import base64
import hashlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "bank-data.py"
ENTRY = "12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|"
HEADER = "# Bank list of Moneten, signed with the update key.\r\n# serial=20261117084700\r\n# hbci4java=4.1.17\r\n"


def run(*args):
	return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)


class BankDataTests(unittest.TestCase):
	def setUp(self):
		self.folder = tempfile.TemporaryDirectory()
		self.dir = Path(self.folder.name)

	def tearDown(self):
		self.folder.cleanup()

	def jar(self, bank_list):
		"""A made-up jar with the bank list and a lock that pins it."""
		data = io.BytesIO()
		with zipfile.ZipFile(data, "w") as archive:
			archive.writestr("blz.properties", bank_list)
		jar = self.dir / "core.jar"
		jar.write_bytes(data.getvalue())
		lock = self.dir / "dependencies.lock"
		lock.write_text("# comment\ncom.github.hbci4j:hbci4j-core:4.1.17 %s\n" % hashlib.sha256(jar.read_bytes()).hexdigest())
		return jar, lock

	def build(self, bank_list, corrections=None):
		jar, lock = self.jar(bank_list)
		fixes = self.dir / "corrections.properties"
		fixes.write_text(corrections or "# none\n", encoding="utf-8")
		out = self.dir / "out"
		result = run("build", "--out", str(out), "--jar", str(jar), "--lock", str(lock), "--corrections", str(fixes), "--serial", "20261117084700")
		return result, out / "blz.properties"

	def test_build_keeps_the_list_without_corrections(self):
		text = ENTRY + "\r\n76030080=Beispielbank|Nürnberg|CSDBDE71XXX|00||https://fints.example.org/fints|300|300|\r\n"
		result, path = self.build(text.encode("utf-8"))
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(path.read_bytes(), (HEADER + text).encode("utf-8"))

	def test_corrections_replace_in_place_and_add_at_the_end(self):
		text = ENTRY + "\r\n76030080=Beispielbank|Nürnberg|CSDBDE71XXX|00||https://fints.example.org/fints|300|300|\r\n"
		moved = "12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.moved.example/fints|300|300|"
		added = "10010010=Postbank|Berlin|PBNKDEFFXXX|00||https://fints.example.net/fints|300|300|"
		result, path = self.build(text.encode("utf-8"), "# moved\n%s\n%s\n" % (added, moved))
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(path.read_bytes().decode("utf-8").split("\r\n")[3:],
			[moved, "76030080=Beispielbank|Nürnberg|CSDBDE71XXX|00||https://fints.example.org/fints|300|300|", added, ""])

	def test_build_writes_the_serial_of_now_in_utc(self):
		jar, lock = self.jar((ENTRY + "\r\n").encode())
		out = self.dir / "out"
		self.assertEqual(run("build", "--out", str(out), "--jar", str(jar), "--lock", str(lock)).returncode, 0)
		lines = (out / "blz.properties").read_bytes().decode().split("\r\n")
		self.assertRegex(lines[1], r"^# serial=20[0-9]{12}$")
		self.assertEqual(lines[2], "# hbci4java=4.1.17")
		self.assertNotEqual(run("build", "--out", str(out), "--jar", str(jar), "--lock", str(lock), "--serial", "2026").returncode, 0)

	def test_build_refuses_a_jar_that_the_lock_does_not_pin(self):
		jar, lock = self.jar(ENTRY.encode())
		lock.write_text("com.github.hbci4j:hbci4j-core:4.1.17 %s\n" % ("0" * 64))
		result = run("build", "--out", str(self.dir / "out"), "--jar", str(jar), "--lock", str(lock))
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("SHA-256", result.stderr)

	def test_build_refuses_a_correction_that_is_no_entry(self):
		result, _ = self.build(ENTRY.encode(), "12030000=Musterbank|Berlin\n")
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("no entry", result.stderr)

	def test_check_refuses_what_the_app_refuses(self):
		for name, data in (("empty", b""), ("comment only", b"# x\n"), ("short code", ENTRY[1:].encode()),
				("few fields", b"12030000=Musterbank|Berlin|BYLADEM1001\n"), ("backslash", ENTRY.replace("Muster", "Muster\\u0062").encode()),
				("not UTF-8", b"\xff\xfe"), ("no header", (ENTRY + "\n").encode()),
				("serial after the first entry", (ENTRY + "\n# serial=20261117084700\n# hbci4java=4.1.17\n").encode()),
				("two serials", ("# serial=20261117084700\n# serial=20261118084700\n# hbci4java=4.1.17\n" + ENTRY + "\n").encode()),
				("short serial", ("# serial=2026111708470\n# hbci4java=4.1.17\n" + ENTRY + "\n").encode()),
				("two versions", ("# serial=20261117084700\n! hbci4java=4.1.17\n# hbci4java=4.1.18\n" + ENTRY + "\n").encode())):
			path = self.dir / "list"
			path.write_bytes(data)
			self.assertNotEqual(run("check", str(path)).returncode, 0, name)
		path.write_bytes((HEADER + ENTRY + "\n").encode())
		self.assertEqual(run("check", str(path)).returncode, 0)
		path.write_bytes(("! serial=20261117084700\n!hbci4java=4.1.17\n" + ENTRY + "\n").encode())
		self.assertEqual(run("check", str(path)).returncode, 0)

	def test_sign_and_verify_with_a_throwaway_key(self):
		if run("public-key", str(Path(__file__).resolve().parent.parent / "Fixtures/update/test-update.key")).returncode != 0:
			self.skipTest("no OpenSSL 3")
		key = self.dir / "throwaway.key"
		key.write_text(base64.b64encode(os.urandom(32)).decode())
		public = run("public-key", str(key)).stdout.strip()
		path = self.dir / "blz.properties"
		path.write_bytes((HEADER + ENTRY + "\r\n").encode())
		self.assertEqual(run("sign", "--key-file", str(key), str(path)).returncode, 0)
		self.assertEqual(len(base64.b64decode(Path(str(path) + ".sig").read_text().strip())), 64)
		self.assertEqual(run("verify", "--public-key", public, str(path)).returncode, 0)
		other = self.dir / "other.key"
		other.write_text(base64.b64encode(os.urandom(32)).decode())
		self.assertNotEqual(run("verify", "--public-key", run("public-key", str(other)).stdout.strip(), str(path)).returncode, 0)
		path.write_bytes((HEADER + ENTRY.replace("Berlin", "Berlim") + "\r\n").encode())
		self.assertNotEqual(run("verify", "--public-key", public, str(path)).returncode, 0)


# STUB_LATEST is the tag of the latest release, empty for none, or "error" for an answer other than 404.
# STUB_RELEASES holds the lines "tag draft" of every release, or "fail" for a list that cannot be read.
GH_STUB = """#!/bin/sh
case "$*" in
*/releases/latest*)
	[ "$STUB_LATEST" != error ] || { echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; }
	[ -n "$STUB_LATEST" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
	echo "$STUB_LATEST" ;;
*)
	[ "$STUB_RELEASES" != fail ] || { echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; }
	printf "$STUB_RELEASES" ;;
esac
"""
CURL_STUB = """#!/bin/sh
[ "$STUB_FEED" = yes ] || exit 22
"""


class CheckLatestTests(unittest.TestCase):
	"""check-latest with stubs of gh and curl in place of GitHub."""

	def setUp(self):
		self.folder = tempfile.TemporaryDirectory()
		for name, text in (("gh", GH_STUB), ("curl", CURL_STUB)):
			path = Path(self.folder.name) / name
			path.write_text(text)
			path.chmod(0o755)

	def tearDown(self):
		self.folder.cleanup()

	def check(self, latest, releases, feed):
		env = dict(os.environ, PATH=self.folder.name + os.pathsep + os.environ["PATH"],
			STUB_LATEST=latest, STUB_RELEASES=releases, STUB_FEED="yes" if feed else "no")
		return subprocess.run([sys.executable, str(SCRIPT), "check-latest", "--repo", "MonetenApp/Moneten"],
			capture_output=True, text=True, env=env)

	def test_no_version_of_the_app_skips_the_feed(self):
		for latest, releases in (("ext-v0.1.0", "ext-v0.1.0 false\\nv0.1.0 true\\n"), ("", ""),
				("ext-v0.2.0", "ext-v0.2.0 false\\nv0.1.0-beta.1 false\\n"),
				("bank-data", "bank-data false\\next-v0.1.0 false\\n")):
			result = self.check(latest, releases, feed=False)
			self.assertEqual(result.returncode, 0, result.stderr)
			self.assertIn("No version of the app is published yet", result.stdout)

	def test_a_version_as_the_latest_release_needs_the_feed(self):
		self.assertEqual(self.check("v0.1.0", "v0.1.0 false\\n", feed=True).returncode, 0)
		result = self.check("v0.1.0", "v0.1.0 false\\n", feed=False)
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("does not answer", result.stderr)

	def test_bank_data_as_the_latest_release_fails_once_a_version_is_published(self):
		result = self.check("bank-data", "bank-data false\\nv0.1.0 false\\n", feed=True)
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("the latest release is bank-data", result.stderr)

	def test_another_latest_release_fails_once_a_version_is_published(self):
		result = self.check("ext-v0.2.0", "ext-v0.2.0 false\\nv0.1.0 false\\n", feed=True)
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("v0.1.0", result.stderr)

	def test_no_latest_release_fails_once_a_version_is_published(self):
		# GitHub leaves a release marked as a pre-release out of the latest release.
		result = self.check("", "v0.1.0 false\\n", feed=True)
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("the latest release is none", result.stderr)

	def test_an_error_for_the_latest_release_fails(self):
		result = self.check("error", "ext-v0.1.0 false\\n", feed=True)
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("does not answer for the latest release", result.stderr)

	def test_a_list_that_cannot_be_read_fails(self):
		for latest in ("", "ext-v0.1.0", "bank-data"):
			result = self.check(latest, "fail", feed=True)
			self.assertNotEqual(result.returncode, 0, latest)
			self.assertIn("cannot be read", result.stderr)


if __name__ == "__main__":
	unittest.main()
