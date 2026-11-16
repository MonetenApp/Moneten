#!/usr/bin/env python3
"""Tests of scripts/release-notes.py, run by scripts/check.sh and by the specs job of CI."""

import base64
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "release-notes.py"

GOOD = """# Changelog

## Unreleased

- **Moneten now needs macOS 15 or later.**

## 0.2.0-beta.2 (2026-12-08)

- Faster search.
- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.

## 0.2.0-beta.1 (2026-12-01)

- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.

## 0.1.3 (2026-11-20)

- Larger display of photoTAN images.
- Fixed the sum of a split transaction.
"""


class ReleaseNotesTests(unittest.TestCase):
	def setUp(self):
		self.folder = tempfile.TemporaryDirectory()
		self.dir = Path(self.folder.name)
		self.changelog = self.dir / "CHANGELOG.md"
		self.changelog.write_text(GOOD)

	def tearDown(self):
		self.folder.cleanup()

	def run_script(self, *args):
		return subprocess.run([sys.executable, str(SCRIPT), "--changelog", str(self.changelog), *args],
			capture_output=True, text=True)

	def assert_fails(self, text, line, message):
		self.changelog.write_text(text)
		result = self.run_script("check")
		self.assertNotEqual(result.returncode, 0, text)
		self.assertIn("line %d:" % line, result.stderr)
		self.assertIn(message, result.stderr)

	# check

	def test_good_file_passes(self):
		self.assertEqual(self.run_script("check").returncode, 0)

	def test_repository_changelog_passes(self):
		result = subprocess.run([sys.executable, str(SCRIPT), "check"], cwd=SCRIPT.parent.parent, capture_output=True, text=True)
		self.assertEqual(result.returncode, 0, result.stderr)

	def test_nested_list_fails(self):
		self.assert_fails(GOOD.replace("- Faster search.", "- Faster search.\n  - In the sidebar too."), 10, "no nesting")

	def test_html_fails(self):
		self.assert_fails(GOOD.replace("Faster search.", "Faster <b>search</b>."), 9, "no HTML")

	def test_link_without_https_fails(self):
		self.assert_fails(GOOD.replace("](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.\n\n## 0.2.0-beta.1",
			"](http://example.org) from a QR code.\n\n## 0.2.0-beta.1"), 10, "https://")

	def test_empty_released_section_fails(self):
		self.assert_fails(GOOD.replace("- Larger display of photoTAN images.\n- Fixed the sum of a split transaction.\n", ""), 16, "no entries")

	def test_version_twice_fails(self):
		self.assert_fails(GOOD.replace("## 0.2.0-beta.1 (2026-12-01)", "## 0.1.3 (2026-12-01)"), 16, "appears twice")

	def test_heading_inside_section_fails(self):
		self.assert_fails(GOOD.replace("- Faster search.", "### Fixes\n- Faster search."), 9, "heading")

	def test_empty_unreleased_passes(self):
		self.changelog.write_text(GOOD.replace("- **Moneten now needs macOS 15 or later.**\n", ""))
		self.assertEqual(self.run_script("check").returncode, 0)

	# cut and section

	def test_cut_pre_release(self):
		self.changelog.write_text(GOOD.replace("0.2.0-beta.2", "0.1.4"))
		result = self.run_script("cut", "0.2.0-beta.3", "--date", "2026-12-15")
		self.assertEqual(result.returncode, 0, result.stderr)
		text = self.changelog.read_text()
		self.assertTrue(text.startswith("# Changelog\n\n## Unreleased\n\n## 0.2.0-beta.3 (2026-12-15)\n\n- **Moneten now needs macOS 15 or later.**\n\n## 0.1.4"))
		self.assertEqual(self.run_script("check").returncode, 0)

	def test_cut_stable_takes_entries_of_its_pre_releases_once(self):
		result = self.run_script("cut", "0.2.0", "--date", "2026-12-15")
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(self.run_script("section", "0.2.0").stdout.splitlines(), [
			"- **Moneten now needs macOS 15 or later.**",
			"- Faster search.",
			"- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.",
		])
		# The pre-release sections stay as they are.
		self.assertEqual(self.run_script("section", "0.2.0-beta.1").stdout.splitlines(), [
			"- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.",
		])

	def test_cut_with_today(self):
		self.assertEqual(self.run_script("cut", "0.2.0").returncode, 0)
		import datetime
		self.assertIn("## 0.2.0 (%s)" % datetime.date.today().isoformat(), self.changelog.read_text())

	def test_cut_existing_version_fails(self):
		self.assertNotEqual(self.run_script("cut", "0.1.3").returncode, 0)

	def test_cut_empty_unreleased_fails(self):
		self.changelog.write_text(GOOD.replace("- **Moneten now needs macOS 15 or later.**\n", ""))
		self.assertNotEqual(self.run_script("cut", "0.1.4").returncode, 0)

	def test_section_prints_exactly_its_entries(self):
		result = self.run_script("section", "0.1.3")
		self.assertEqual(result.stdout, "- Larger display of photoTAN images.\n- Fixed the sum of a split transaction.\n")

	def test_section_of_unknown_version_fails(self):
		self.assertNotEqual(self.run_script("section", "9.9.9").returncode, 0)

	# appcast and check-release

	def appcast(self, version, build, out, feed=None, url=None):
		source = ["--feed", str(feed)] if feed else ["--first-release"]
		return self.run_script("appcast", version, "--build", str(build), *source, "--min-macos", "15.0",
			"--url", url or "https://github.com/MonetenApp/Moneten/releases/download/v%s/Moneten-%s.dmg" % (version, version),
			"--length", "1000", "--signature", "sig-%s==" % version, "--out", str(out))

	def test_appcast_is_idempotent_and_keeps_older_items(self):
		first = self.dir / "first.xml"
		self.assertEqual(self.appcast("0.1.3", 100, first).returncode, 0)
		again = self.dir / "again.xml"
		self.assertEqual(self.appcast("0.1.3", 100, again, feed=first).returncode, 0)
		self.assertEqual(first.read_bytes(), again.read_bytes())

		self.changelog.write_text(GOOD.replace("## Unreleased\n\n- **Moneten now needs macOS 15 or later.**\n",
			"## Unreleased\n\n## 0.1.4 (2026-11-27)\n\n- Fixed the balance of a credit card.\n"))
		second = self.dir / "second.xml"
		self.assertEqual(self.appcast("0.1.4", 105, second, feed=first).returncode, 0)
		text = second.read_text()
		self.assertIn("sig-0.1.3==", text)
		self.assertIn("sig-0.1.4==", text)
		self.assertLess(text.index("<title>0.1.4</title>"), text.index("<title>0.1.3</title>"))
		self.assertIn("Fixed the balance of a credit card.", text)

	def test_appcast_rewrites_notes_from_changelog_and_escapes_them(self):
		feed = self.dir / "feed.xml"
		self.appcast("0.1.3", 100, feed)
		self.changelog.write_text(GOOD.replace("Fixed the sum of a split transaction.", "Fixed the sum of a split transaction & its parts <3."))
		# The heading text of the release is not HTML, so check passes no entry with a tag; "<3" is no tag.
		rewritten = self.dir / "rewritten.xml"
		result = self.appcast("0.1.3", 100, rewritten, feed=feed)
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertIn("split transaction &amp; its parts &lt;3.", rewritten.read_text())

	def test_appcast_marks_pre_release_with_channel_beta(self):
		feed = self.dir / "feed.xml"
		self.assertEqual(self.appcast("0.2.0-beta.1", 100, feed).returncode, 0)
		text = feed.read_text()
		self.assertIn("<sparkle:channel>beta</sparkle:channel>", text)
		self.assertIn("<sparkle:shortVersionString>0.2.0-beta.1</sparkle:shortVersionString>", text)
		self.assertIn("<sparkle:version>100</sparkle:version>", text)
		self.assertIn('<description sparkle:format="markdown">', text)
		self.assertIn("<pubDate>Tue, 01 Dec 2026 00:00:00 +0000</pubDate>", text)

	def test_appcast_without_readable_feed_fails(self):
		result = self.appcast("0.1.3", 100, self.dir / "out.xml", feed=self.dir / "missing.xml")
		self.assertNotEqual(result.returncode, 0)
		self.assertIn("cannot read the current feed", result.stderr)
		self.assertFalse((self.dir / "out.xml").exists())

	def test_appcast_refuses_latest_url(self):
		result = self.appcast("0.1.3", 100, self.dir / "out.xml",
			url="https://github.com/MonetenApp/Moneten/releases/latest/download/Moneten.dmg")
		self.assertNotEqual(result.returncode, 0)

	def test_check_release_refuses_lower_build_and_lower_version(self):
		feed = self.dir / "feed.xml"
		self.changelog.write_text(GOOD.replace("## Unreleased\n\n- **Moneten now needs macOS 15 or later.**\n",
			"## Unreleased\n\n## 0.1.4 (2026-12-20)\n\n- Fixed the balance of a credit card.\n"))
		self.assertEqual(self.appcast("0.2.0-beta.1", 200, feed).returncode, 0)
		low_build = self.run_script("check-release", "0.2.0-beta.2", "--build", "200", "--feed", str(feed))
		self.assertIn("build 200 is not above", low_build.stderr)
		low_version = self.run_script("check-release", "0.1.4", "--build", "300", "--feed", str(feed))
		self.assertIn("version 0.1.4 is not above version 0.2.0-beta.1", low_version.stderr)
		ok = self.run_script("check-release", "0.2.0-beta.2", "--build", "201", "--feed", str(feed))
		self.assertEqual(ok.returncode, 0, ok.stderr)
		missing = self.run_script("check-release", "0.3.0", "--build", "400", "--feed", str(feed))
		self.assertIn("no section for version 0.3.0", missing.stderr)

	def test_same_version_refuses_a_lower_build(self):
		feed = self.dir / "feed.xml"
		self.assertEqual(self.appcast("0.1.3", 200, feed).returncode, 0)
		lower = self.run_script("check-release", "0.1.3", "--build", "100", "--feed", str(feed))
		self.assertIn("build 100 is below build 200 of version 0.1.3", lower.stderr)
		self.assertNotEqual(self.appcast("0.1.3", 100, self.dir / "out.xml", feed=feed).returncode, 0)
		self.assertFalse((self.dir / "out.xml").exists())
		same = self.run_script("check-release", "0.1.3", "--build", "200", "--feed", str(feed))
		self.assertEqual(same.returncode, 0, same.stderr)

	# stale-releases

	def test_stale_releases_lists_only_changed_texts(self):
		releases = [
			{"tag": "v0.1.3", "body": "- Larger display of photoTAN images.\r\n- Fixed the sum of a split transaction."},
			{"tag": "v0.2.0-beta.1", "body": "- An old text."},
			{"tag": "v0.2.0-beta.2", "body": "- Faster search.\n- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.\n"},
			{"tag": "bank-data", "body": "Bank data files."},
			{"tag": "v0.0.9", "body": "No section in the changelog."},
		]
		result = subprocess.run([sys.executable, str(SCRIPT), "--changelog", str(self.changelog), "stale-releases"],
			input="\n".join(json.dumps(r) for r in releases) + "\n", capture_output=True, text=True)
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual(result.stdout.split(), ["v0.2.0-beta.1"])

	# check-feed

	def openssl(self):
		result = self.run_script("openssl")
		self.assertEqual(result.returncode, 0, result.stderr)
		return result.stdout.strip()

	def key_pair(self, name):
		"""An Ed25519 key as a PEM file for openssl, and its public key in Base64 as the app has it."""
		private = self.dir / ("%s.pem" % name)
		subprocess.run([self.openssl(), "genpkey", "-algorithm", "ed25519", "-out", str(private)], check=True, capture_output=True)
		public = subprocess.run([self.openssl(), "pkey", "-in", str(private), "-pubout", "-outform", "DER"], check=True, capture_output=True).stdout
		return private, base64.b64encode(public[-32:]).decode()

	def signed_feed(self, private, url=None, signed_length=None):
		"""Writes a feed and appends the signature block of sign_update, as Sparkle does."""
		feed = self.dir / "feed.xml"
		self.assertEqual(self.appcast("0.1.3", 100, feed).returncode, 0)
		if url:
			# appcast refuses such a URL, so the test puts it in afterwards.
			feed.write_bytes(feed.read_bytes().replace(
				b"https://github.com/MonetenApp/Moneten/releases/download/v0.1.3/Moneten-0.1.3.dmg", url.encode()))
		return self.sign(feed, private, signed_length)

	def sign(self, feed, private, signed_length=None):
		data = feed.read_bytes()
		signed = data[:signed_length] if signed_length is not None else data
		(self.dir / "data").write_bytes(signed)
		signature = subprocess.run([self.openssl(), "pkeyutl", "-sign", "-rawin", "-inkey", str(private), "-in", str(self.dir / "data")],
			check=True, capture_output=True).stdout
		feed.write_bytes(data + b"<!-- sparkle-signatures:\nedSignature: %s\nlength: %d\n-->\n" % (base64.b64encode(signature), len(signed)))
		return feed

	def check_feed(self, feed, public):
		return self.run_script("check-feed", "--feed", str(feed), "--public-key", public)

	def test_openssl_is_not_the_libressl_of_macos(self):
		version = subprocess.run([self.openssl(), "version"], capture_output=True, text=True).stdout
		self.assertTrue(version.startswith("OpenSSL "), version)

	def test_check_feed_accepts_a_feed_of_the_update_key(self):
		private, public = self.key_pair("update")
		result = self.check_feed(self.signed_feed(private), public)
		self.assertEqual(result.returncode, 0, result.stderr)

	def test_check_feed_refuses_a_changed_byte(self):
		private, public = self.key_pair("update")
		feed = self.signed_feed(private)
		feed.write_bytes(feed.read_bytes().replace(b"Fixed the sum", b"Fixed the sun", 1))
		self.assertIn("did not sign the feed", self.check_feed(feed, public).stderr)

	def test_check_feed_refuses_another_key(self):
		private, _ = self.key_pair("update")
		_, other = self.key_pair("other")
		self.assertIn("did not sign the feed", self.check_feed(self.signed_feed(private), other).stderr)

	def test_check_feed_refuses_a_feed_without_signature(self):
		_, public = self.key_pair("update")
		feed = self.dir / "feed.xml"
		self.appcast("0.1.3", 100, feed)
		self.assertIn("has no signature", self.check_feed(feed, public).stderr)

	def test_check_feed_refuses_text_the_signature_does_not_cover(self):
		private, public = self.key_pair("update")
		feed = self.signed_feed(private, signed_length=200)
		self.assertIn("does not cover the whole feed", self.check_feed(feed, public).stderr)

	def test_check_feed_refuses_a_signed_http_or_foreign_disk_image(self):
		private, public = self.key_pair("update")
		for url in ("http://github.com/MonetenApp/Moneten/releases/download/v0.1.3/Moneten-0.1.3.dmg",
				"https://example.com/MonetenApp/Moneten/releases/download/v0.1.3/Moneten-0.1.3.dmg"):
			result = self.check_feed(self.signed_feed(private, url=url), public)
			self.assertIn("has a disk image outside", result.stderr, url)

	# remove

	def two_versions(self):
		"""An unsigned feed with 0.1.3 alone, and one with 0.1.3 and 0.1.4."""
		self.changelog.write_text(GOOD.replace("## Unreleased\n\n- **Moneten now needs macOS 15 or later.**\n",
			"## Unreleased\n\n## 0.1.4 (2026-11-27)\n\n- Fixed the balance of a credit card.\n"))
		first, second = self.dir / "first.xml", self.dir / "second.xml"
		self.assertEqual(self.appcast("0.1.3", 100, first).returncode, 0)
		self.assertEqual(self.appcast("0.1.4", 105, second, feed=first).returncode, 0)
		return first, second

	def remove(self, feed, public, version="0.1.4"):
		return self.run_script("remove", version, "--feed", str(feed), "--public-key", public, "--out", str(self.dir / "removed.xml"))

	def test_remove_takes_a_version_out_of_a_checked_feed(self):
		private, public = self.key_pair("update")
		first, second = self.two_versions()
		result = self.remove(self.sign(second, private), public)
		self.assertEqual(result.returncode, 0, result.stderr)
		self.assertEqual((self.dir / "removed.xml").read_bytes(), first.read_bytes())

	def test_remove_refuses_an_unsigned_feed(self):
		_, public = self.key_pair("update")
		_, second = self.two_versions()
		self.assertIn("has no signature", self.remove(second, public).stderr)
		self.assertFalse((self.dir / "removed.xml").exists())

	def test_remove_refuses_a_feed_of_another_key(self):
		private, _ = self.key_pair("update")
		_, other = self.key_pair("other")
		_, second = self.two_versions()
		self.assertIn("did not sign the feed", self.remove(self.sign(second, private), other).stderr)
		self.assertFalse((self.dir / "removed.xml").exists())

	def test_remove_refuses_a_forged_disk_image(self):
		"""Without the check, remove would keep the forged item, and the owner would sign it."""
		private, public = self.key_pair("update")
		_, second = self.two_versions()
		second.write_bytes(second.read_bytes().replace(b"https://github.com/MonetenApp/Moneten/releases/download/v0.1.3/",
			b"https://example.com/v0.1.3/"))
		for feed in (second, self.sign(second, private)):
			result = self.remove(feed, public)
			self.assertNotEqual(result.returncode, 0)
			self.assertFalse((self.dir / "removed.xml").exists())
		self.assertIn("has a disk image outside", result.stderr)


if __name__ == "__main__":
	unittest.main()
