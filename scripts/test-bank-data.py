#!/usr/bin/env python3
"""Tests of scripts/bank-data.py, run by scripts/check.sh and by the specs job of CI. They build from a
made-up jar and sign with throwaway keys, so they need no network and no secret."""

import base64
import hashlib
import io
import json
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

	def test_project_corrections_give_flatexdegiro_its_current_address(self):
		"""The entries of the jar of hbci4java 4.1.17 near the Bankleitzahlen of flatexDEGIRO Bank (#234)."""
		neighbor = "10130600=Isbank AG|Berlin|ISBKDEFXBER|06||https://www.bv-activebanking.de/hbciTunnel/hbciTransfer.jsp||300|"
		jar_list = "\r\n".join([
			neighbor,
			"10130800=biw Bank für Investments und Wertpapiere|Willich|BIWBDE33XXX|01||https://konto.biw-bank.de/hbci/||300|",
			"30330800=BIW Bank für Investments und Wertpapiere|Willich|BIWBDE33303|01|||||",
			"76030080=Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank|Nürnberg, Mittelfr|CSDBDE71XXX|01||https://brokerage-hbci.consorsbank.de/hbci||300|",
		]) + "\r\n"
		corrections = (SCRIPT.parent.parent / "BankData" / "corrections.properties").read_text(encoding="utf-8")
		result, path = self.build(jar_list.encode("utf-8"), corrections)
		self.assertEqual(result.returncode, 0, result.stderr)
		entries = dict(line.split("=", 1) for line in path.read_bytes().decode("utf-8").split("\r\n") if line and not line.startswith("#"))
		for code in ["10130800", "30330800", "76030800"]:
			fields = entries[code].split("|")
			self.assertEqual(fields[5], "https://banking.flatexdegiro.com/hbci", code)
			self.assertEqual(fields[7], "300", code)
		self.assertEqual(entries["10130800"].split("|")[2], "BIWBDE33XXX")
		self.assertEqual(entries["30330800"].split("|")[2], "BIWBDE33303")
		self.assertEqual("10130600=" + entries["10130600"], neighbor)
		self.assertTrue(entries["76030080"].endswith("|https://brokerage-hbci.consorsbank.de/hbci||300|"))

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


# STUB_LATEST is the tag of the latest release, empty for none, "error" for an answer other than 404, or
# "{" and the JSON that GitHub sends. STUB_RELEASES is what gh api --paginate --slurp prints for the list
# of releases, "fail" for a list that cannot be read, or "@full:" and a page that follows a full page
# of 100 releases.
GH_STUB = """#!/bin/sh
case "$*" in
*/releases/latest*)
	[ "$STUB_LATEST" != error ] || { echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; }
	[ -n "$STUB_LATEST" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
	case "$STUB_LATEST" in
	{*) printf '%s\\n' "$STUB_LATEST" ;;
	*) printf '{"tag_name": "%s", "draft": false}\\n' "$STUB_LATEST" ;;
	esac ;;
*--paginate\\ --slurp\\ *)
	case "$STUB_RELEASES" in
	fail) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
	@full:*) python3 -c 'import json, sys; print(json.dumps([[{"tag_name": "ext-v0.0.%d" % n, "draft": False} for n in range(100)], json.loads(sys.argv[1])]))' "${STUB_RELEASES#@full:}" ;;
	*) printf '%s\\n' "$STUB_RELEASES" ;;
	esac ;;
*) echo "gh: the stub knows no call $*" >&2; exit 1 ;;
esac
"""
CURL_STUB = """#!/bin/sh
[ "$STUB_FEED" = yes ] || exit 22
"""


def releases(*pages):
	"""The output of gh api --paginate --slurp for pages of (tag, draft) pairs."""
	return json.dumps([[{"tag_name": tag, "draft": draft, "prerelease": False} for tag, draft in page] for page in pages])


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

	def assertFails(self, result, message):
		self.assertNotEqual(result.returncode, 0, result.stdout)
		self.assertIn(message, result.stderr)

	def test_no_version_of_the_app_skips_the_feed(self):
		for latest, listing in (("ext-v0.1.0", releases([("ext-v0.1.0", False), ("v0.1.0", True)])), ("", releases([])),
				("ext-v0.2.0", releases([("ext-v0.2.0", False), ("v0.1.0-beta.1", False)])),
				("bank-data", releases([("bank-data", False), ("ext-v0.1.0", False)])),
				("bank-data", "@full:[]")):
			result = self.check(latest, listing, feed=False)
			self.assertEqual(result.returncode, 0, result.stderr)
			self.assertIn("No version of the app is published yet", result.stdout)

	def test_a_version_as_the_latest_release_needs_the_feed(self):
		self.assertEqual(self.check("v0.1.0", releases([("v0.1.0", False)]), feed=True).returncode, 0)
		self.assertFails(self.check("v0.1.0", releases([("v0.1.0", False)]), feed=False), "does not answer")

	def test_bank_data_as_the_latest_release_fails_once_a_version_is_published(self):
		self.assertFails(self.check("bank-data", releases([("bank-data", False), ("v0.1.0", False)]), feed=True),
			"the latest release is bank-data")

	def test_another_latest_release_fails_once_a_version_is_published(self):
		self.assertFails(self.check("ext-v0.2.0", releases([("ext-v0.2.0", False), ("v0.1.0", False)]), feed=True), "v0.1.0")

	def test_no_latest_release_fails_once_a_version_is_published(self):
		# GitHub leaves a release marked as a pre-release out of the latest release.
		listing = json.dumps([[{"tag_name": "v0.1.0", "draft": False, "prerelease": True}]])
		self.assertFails(self.check("", listing, feed=True), "the latest release is none")

	def test_a_version_on_the_second_page_fails(self):
		self.assertFails(self.check("ext-v0.1.0", '@full:[{"tag_name": "v0.1.0", "draft": false}]', feed=True),
			"although these versions are published: v0.1.0")

	def test_an_error_for_the_latest_release_fails(self):
		self.assertFails(self.check("error", releases([("ext-v0.1.0", False)]), feed=True), "does not answer for the latest release")

	def test_a_latest_release_without_a_string_tag_fails(self):
		for latest in ("{}", '{"tag_name": 1}', '{"tag_name": null}'):
			self.assertFails(self.check(latest, releases([]), feed=True), "GitHub sent no tag for the latest release")

	def test_a_list_that_cannot_be_read_fails(self):
		for latest in ("", "ext-v0.1.0", "bank-data"):
			self.assertFails(self.check(latest, "fail", feed=True), "cannot be read")

	def test_a_list_of_another_shape_fails(self):
		for listing, message in (
				("", "is not JSON"),
				("{}", "has no page"),
				("[]", "has no page"),
				("[{}]", "page 1 of the list of releases is not a list"),
				('[[{"tag_name": "v0.1.0"}]]', "without a string tag_name and a Boolean draft"),
				('[[{"tag_name": "v0.1.0", "draft": "false"}]]', "without a string tag_name and a Boolean draft"),
				('[[{"tag_name": 1, "draft": false}]]', "without a string tag_name and a Boolean draft"),
				('[[{"draft": false}]]', "without a string tag_name and a Boolean draft"),
				('[["v0.1.0 false"]]', "without a string tag_name and a Boolean draft"),
				('[[], [{"tag_name": "v0.1.0", "draft": false}]]', "page 1 of the list of releases holds 0 releases")):
			for latest in ("", "ext-v0.1.0"):
				with self.subTest(listing=listing, latest=latest):
					self.assertFails(self.check(latest, listing, feed=True), message)


if __name__ == "__main__":
	unittest.main()
