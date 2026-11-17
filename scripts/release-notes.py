#!/usr/bin/env python3
"""Reads CHANGELOG.md, the only source of the release notes, and writes the update feed from it.

  release-notes.py check                     fail on a line that breaks the format of CHANGELOG.md
  release-notes.py cut <version>             rename "Unreleased" to the version with the date of today
  release-notes.py section <version>         print the entries of one version
  release-notes.py check-release <version> --build N (--feed FILE | --first-release)
                                             fail when the version cannot be released after the feed
  release-notes.py appcast <version> --build N --min-macos 15.0 --url URL --length N --signature SIG
                                   (--feed FILE | --first-release) --out FILE
                                             add or replace the item of a version, and rewrite the notes
                                             of every item from CHANGELOG.md
  release-notes.py remove <version> --feed FILE --public-key KEY --out FILE
                                             take the item of a version out of the feed, after the
                                             checks of check-feed, unless it is the last item
  release-notes.py stale-releases            read the releases of GitHub as JSON lines {"tag", "body"} and
                                             print the tag of each one whose text differs from its section
  release-notes.py check-feed --feed FILE --public-key KEY
                                             fail unless the update key KEY signed the feed and every
                                             disk image in it lies in a release of the repository
  release-notes.py check-newer --feed FILE --current FILE
                                             fail unless the feed has a higher revision than the current
                                             feed and lists every version of it
  release-notes.py openssl                   print the path of an OpenSSL 3 or later, which check-feed uses
  release-notes.py public-key FILE           print the public key of the private key file FILE of Sparkle,
                                             for the test key and throwaway keys only

The format is in the design of the change add-software-update. A version is 1.2.3 or 1.2.3-beta.4.
The feed this script writes is not signed. sign_update of Sparkle signs it afterwards, and this
script drops that signature when it reads the feed, because every change needs a new one.
Every feed that appcast or remove writes has a revision one above the current feed, in each item,
because Sparkle hands the app only the items. The app refuses a feed below the highest revision
that it read, so nobody can replay an older signed feed (spec: "Check the update feed").
"""

import argparse
import base64
import datetime
import email.utils
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

CHANGELOG = "CHANGELOG.md"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
# The namespace of the revision. Sparkle keeps an element outside its own namespace under its
# qualified name, so the app reads "moneten:revision", and the prefix must stay.
MONETEN = "https://github.com/MonetenApp/Moneten/xml-namespaces/feed"
REVISION = "{%s}revision" % MONETEN
VERSION = r"(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?"
HEADING = re.compile(r"## (?:Unreleased|(%s) \((\d{4}-\d{2}-\d{2})\))$" % VERSION)
ENTRY = re.compile(r"- \S.*$")
LINK = re.compile(r"\]\(([^)]*)\)")
HTML = re.compile(r"<[A-Za-z/!]")
VERSION_ONLY = re.compile(VERSION + "$")
DOWNLOADS = "https://github.com/MonetenApp/Moneten/releases/download/"
# The block that sign_update of Sparkle appends to a feed. It signs the first "length" bytes.
SIGNATURE_BLOCK = re.compile(rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: (\d+)\n-->\s*\Z")
# An Ed25519 public key in DER is this prefix and the 32 bytes of the key.
ED25519_PUBLIC_PREFIX = bytes.fromhex("302a300506032b6570032100")


class Failure(Exception):
	pass


def version_key(version):
	"""A stable version sorts after its pre-releases: 0.2.0-beta.2 < 0.2.0 < 0.2.1-beta.1."""
	match = VERSION_ONLY.match(version)
	if not match:
		raise Failure("%s is not a version like 1.2.3 or 1.2.3-beta.4." % version)
	major, minor, patch, beta = match.groups()
	return (int(major), int(minor), int(patch), int(beta) if beta else float("inf"))


def is_pre_release(version):
	return "-" in version


class Section:
	def __init__(self, line, version, date):
		self.line = line
		self.version = version  # None for "Unreleased"
		self.date = date
		self.entries = []


def parse(text):
	"""Returns the sections in file order. Raises Failure with the line number of the first error."""
	lines = text.split("\n")
	if not lines or lines[0] != "# Changelog":
		raise Failure("line 1: the file must start with \"# Changelog\".")
	sections = []
	seen = {}
	for number, line in enumerate(lines[1:], start=2):
		if line.strip() == "":
			continue
		if line.startswith("## "):
			match = HEADING.match(line)
			if not match:
				raise Failure("line %d: a heading is \"## Unreleased\" or \"## 1.2.3 (2026-11-20)\": %s" % (number, line))
			version, date = match.group(1), match.group(6)
			if version is None and sections:
				raise Failure("line %d: \"Unreleased\" must be the first section." % number)
			if version is not None and not sections:
				raise Failure("line %d: the first section must be \"Unreleased\"." % number)
			if version is not None:
				if version in seen:
					raise Failure("line %d: version %s appears twice, first in line %d." % (number, version, seen[version]))
				seen[version] = number
				try:
					datetime.date.fromisoformat(date)
				except ValueError:
					raise Failure("line %d: %s is not a date." % (number, date))
			sections.append(Section(number, version, date))
			continue
		if not sections:
			raise Failure("line %d: text before the first section." % number)
		if not ENTRY.match(line):
			raise Failure("line %d: a section holds only entries that start with \"- \", with no nesting or headings: %s" % (number, line))
		if HTML.search(line):
			raise Failure("line %d: an entry contains no HTML: %s" % (number, line))
		for target in LINK.findall(line):
			if not target.startswith("https://"):
				raise Failure("line %d: a link must start with https://: %s" % (number, target))
		sections[-1].entries.append(line)
	if not sections:
		raise Failure("the file has no \"Unreleased\" section.")
	for section in sections[1:]:
		if not section.entries:
			raise Failure("line %d: version %s has no entries." % (section.line, section.version))
	return sections


def render(sections):
	out = ["# Changelog", ""]
	for section in sections:
		out.append("## Unreleased" if section.version is None else "## %s (%s)" % (section.version, section.date))
		out.append("")
		if section.entries:
			out.extend(section.entries)
			out.append("")
	return "\n".join(out)


def load(path):
	with open(path, encoding="utf-8") as f:
		return parse(f.read())


def find(sections, version):
	for section in sections:
		if section.version == version:
			return section
	raise Failure("%s has no section for version %s." % (CHANGELOG, version))


def cut(path, version, today):
	version_key(version)
	sections = load(path)
	if any(s.version == version for s in sections):
		raise Failure("%s already has a section for version %s." % (CHANGELOG, version))
	unreleased = sections[0]
	entries = list(unreleased.entries)
	if not is_pre_release(version):
		# The notes of a stable version list everything since the last stable version, so its
		# pre-releases give their entries too, newest first and each entry once.
		for section in sections[1:]:
			if section.version.startswith(version + "-") and section.entries:
				entries.extend(e for e in section.entries if e not in entries)
	if not entries:
		raise Failure("\"Unreleased\" has no entries for version %s." % version)
	released = Section(0, version, today)
	released.entries = entries
	unreleased.entries = []
	text = render([unreleased, released] + sections[1:])
	parse(text)
	with open(path, "w", encoding="utf-8") as f:
		f.write(text)


# The feed

ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("moneten", MONETEN)


def sparkle(tag):
	return "{%s}%s" % (SPARKLE, tag)


def read_feed(path):
	"""Returns the items of a feed as dicts and the revision of the feed, None for a feed without
	items. The notes are not read, they come from CHANGELOG.md."""
	try:
		root = ET.parse(path).getroot()
	except (OSError, ET.ParseError) as error:
		raise Failure("cannot read the current feed %s: %s" % (path, error))
	items = []
	revisions = set()
	for item in root.iter("item"):
		enclosure = item.find("enclosure")
		version = item.findtext(sparkle("shortVersionString"))
		if enclosure is None or version is None:
			raise Failure("an item of %s has no version or no enclosure." % path)
		revision = item.findtext(REVISION)
		if revision is None or not revision.isdigit():
			raise Failure("version %s in %s has no revision." % (version, path))
		revisions.add(int(revision))
		items.append({
			"version": version,
			"build": int(item.findtext(sparkle("version"))),
			"min_macos": item.findtext(sparkle("minimumSystemVersion")),
			"url": enclosure.get("url"),
			"length": int(enclosure.get("length")),
			"signature": enclosure.get(sparkle("edSignature")),
		})
	if len(revisions) > 1:
		raise Failure("the items of %s have different revisions." % path)
	return items, (revisions.pop() if revisions else None)


def write_feed(path, items, sections, revision):
	"""Writes the items newest first. The same items, revision, and CHANGELOG.md always give the same bytes."""
	rss = ET.Element("rss", {"version": "2.0"})
	channel = ET.SubElement(rss, "channel")
	ET.SubElement(channel, "title").text = "Moneten"
	ET.SubElement(channel, "link").text = "https://github.com/MonetenApp/Moneten/releases"
	ET.SubElement(channel, "description").text = "Updates of Moneten"
	ET.SubElement(channel, "language").text = "en"
	for data in sorted(items, key=lambda i: version_key(i["version"]), reverse=True):
		section = find(sections, data["version"])
		day = datetime.date.fromisoformat(section.date)
		item = ET.SubElement(channel, "item")
		ET.SubElement(item, "title").text = data["version"]
		ET.SubElement(item, "pubDate").text = email.utils.format_datetime(
			datetime.datetime(day.year, day.month, day.day, tzinfo=datetime.timezone.utc))
		ET.SubElement(item, sparkle("version")).text = str(data["build"])
		ET.SubElement(item, sparkle("shortVersionString")).text = data["version"]
		ET.SubElement(item, sparkle("minimumSystemVersion")).text = data["min_macos"]
		ET.SubElement(item, REVISION).text = str(revision)
		if is_pre_release(data["version"]):
			ET.SubElement(item, sparkle("channel")).text = "beta"
		# The entries as Markdown text. ElementTree escapes < and &, so no entry can break the feed.
		description = ET.SubElement(item, "description", {sparkle("format"): "markdown"})
		description.text = "\n".join(section.entries)
		ET.SubElement(item, "enclosure", {
			"url": data["url"],
			"length": str(data["length"]),
			"type": "application/octet-stream",
			sparkle("edSignature"): data["signature"],
		})
	ET.indent(rss, space="\t")
	with open(path, "wb") as f:
		f.write(b'<?xml version="1.0" encoding="utf-8"?>\n')
		f.write(ET.tostring(rss, encoding="utf-8"))
		f.write(b"\n")


def current_feed(args):
	"""The items of the current feed and the revision of the next feed."""
	if args.first_release:
		return [], 1
	items, revision = read_feed(args.feed)
	if revision is None:
		raise Failure("the current feed %s has no items, so its revision is unknown." % args.feed)
	return items, revision + 1


def check_release(sections, version, build, items):
	"""The rules of step 1 of the release workflow: a section, a higher build, and a higher version."""
	version_key(version)
	find(sections, version)
	for item in items:
		if item["version"] == version:
			# A tag that was moved to an older commit must not replace the item with a lower build.
			if build < item["build"]:
				raise Failure("build %d is below build %d of version %s in the feed." % (build, item["build"], version))
			continue
		if build <= item["build"]:
			raise Failure("build %d is not above build %d of version %s in the feed." % (build, item["build"], item["version"]))
		if version_key(version) <= version_key(item["version"]):
			raise Failure("version %s is not above version %s in the feed." % (version, item["version"]))


def stale_releases(sections, lines):
	"""The tags whose release text differs from their section, so publish edits only those."""
	versions = {s.version: "\n".join(s.entries) for s in sections if s.version}
	stale = []
	for line in lines:
		if not line.strip():
			continue
		release = json.loads(line)
		tag = release["tag"]
		text = versions.get(tag[1:] if tag.startswith("v") else None)
		# GitHub may store a text with CRLF line ends, and gh release edit adds no final newline.
		if text is not None and release["body"].replace("\r\n", "\n").strip() != text.strip():
			stale.append(tag)
	return stale


def openssl():
	"""An OpenSSL 3 or later. The LibreSSL of macOS in /usr/bin cannot verify Ed25519 with -rawin."""
	for path in (os.environ.get("MONETEN_OPENSSL"), shutil.which("openssl"),
			"/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"):
		if path and os.access(path, os.X_OK):
			version = subprocess.run([path, "version"], capture_output=True, text=True).stdout
			match = re.match(r"OpenSSL (\d+)\.", version)
			if match and int(match.group(1)) >= 3:
				return path
	raise Failure("the feed check needs OpenSSL 3 or later, which macOS does not include: brew install openssl@3, or set MONETEN_OPENSSL.")


# The PKCS#8 prefix of an Ed25519 private key in DER, before its 32 byte seed.
ED25519_PRIVATE_PREFIX = bytes.fromhex("302e020100300506032b657004220420")


def public_key_of(path):
	"""The public key in Base64 of a private key file of Sparkle, which holds the 32 byte seed in
	Base64. The seed goes to openssl through a pipe, never in an argument."""
	try:
		with open(path, "rb") as f:
			seed = base64.b64decode(f.read().strip())[:32]
	except (OSError, ValueError) as error:
		raise Failure("cannot read the private key %s: %s" % (path, error))
	result = subprocess.run([openssl(), "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
		input=ED25519_PRIVATE_PREFIX + seed, capture_output=True)
	if result.returncode != 0 or len(seed) != 32:
		raise Failure("%s is not a private key of Sparkle." % path)
	return base64.b64encode(result.stdout[-32:]).decode()


def check_feed(path, public_key):
	"""Fails unless the update key signed the feed as Sparkle checks it, and every disk image lies in
	a release of the repository. The release script signs a new feed that keeps the items of the
	current one, so an unchecked current feed could carry a forged item into a signed feed."""
	try:
		with open(path, "rb") as f:
			text = f.read()
	except OSError as error:
		raise Failure("cannot read the feed %s: %s" % (path, error))
	match = SIGNATURE_BLOCK.search(text)
	if not match:
		raise Failure("the feed %s has no signature of Sparkle at its end." % path)
	signature, length = base64.b64decode(match.group(1)), int(match.group(2))
	# The signature covers exactly the text before its block, so nothing unsigned hides in the file.
	if length != match.start():
		raise Failure("the signature of the feed %s does not cover the whole feed." % path)
	try:
		key = base64.b64decode(public_key, validate=True)
	except ValueError:
		key = b""
	if len(key) != 32:
		raise Failure("the public update key is not 32 bytes in Base64.")
	with tempfile.TemporaryDirectory() as folder:
		files = {name: os.path.join(folder, name) for name in ("key.der", "feed", "signature")}
		for name, data in (("key.der", ED25519_PUBLIC_PREFIX + key), ("feed", text[:length]), ("signature", signature)):
			with open(files[name], "wb") as f:
				f.write(data)
		result = subprocess.run([openssl(), "pkeyutl", "-verify", "-pubin", "-keyform", "DER", "-inkey", files["key.der"],
			"-rawin", "-in", files["feed"], "-sigfile", files["signature"]], capture_output=True)
	if result.returncode != 0:
		raise Failure("the update key did not sign the feed %s." % path)
	for item in read_feed(path)[0]:
		if not (item["url"] or "").startswith(DOWNLOADS):
			raise Failure("version %s in the feed %s has a disk image outside %s: %s" % (item["version"], path, DOWNLOADS, item["url"]))


def check_newer(path, current):
	"""Fails unless the feed at path may replace the current feed: an app that read the current feed
	accepts only a higher revision, and a release that was published meanwhile must stay in it."""
	items, revision = read_feed(path)
	current_items, current_revision = read_feed(current)
	if revision is None or (current_revision is not None and revision <= current_revision):
		raise Failure("revision %s of the feed %s is not above revision %s of the current feed." % (revision, path, current_revision))
	versions = {i["version"] for i in items}
	for item in current_items:
		if item["version"] not in versions:
			raise Failure("the feed %s misses version %s of the current feed." % (path, item["version"]))


def main():
	parser = argparse.ArgumentParser(description="Reads CHANGELOG.md and writes the update feed.")
	parser.add_argument("--changelog", default=CHANGELOG, help=argparse.SUPPRESS)
	commands = parser.add_subparsers(dest="command", required=True)
	commands.add_parser("check")
	command = commands.add_parser("cut")
	command.add_argument("version")
	command.add_argument("--date", default=None, help=argparse.SUPPRESS)
	commands.add_parser("section").add_argument("version")
	for name in ("check-release", "appcast"):
		command = commands.add_parser(name)
		command.add_argument("version")
		command.add_argument("--build", type=int, required=True)
		source = command.add_mutually_exclusive_group(required=True)
		source.add_argument("--feed")
		source.add_argument("--first-release", action="store_true")
		if name == "appcast":
			command.add_argument("--min-macos", required=True)
			command.add_argument("--url", required=True)
			command.add_argument("--length", type=int, required=True)
			command.add_argument("--signature", required=True)
			command.add_argument("--out", required=True)
	command = commands.add_parser("remove")
	command.add_argument("version")
	command.add_argument("--feed", required=True)
	command.add_argument("--public-key", required=True)
	command.add_argument("--out", required=True)
	commands.add_parser("stale-releases")
	commands.add_parser("openssl")
	commands.add_parser("public-key").add_argument("file")
	command = commands.add_parser("check-feed")
	command.add_argument("--feed", required=True)
	command.add_argument("--public-key", required=True)
	command = commands.add_parser("check-newer")
	command.add_argument("--feed", required=True)
	command.add_argument("--current", required=True)
	args = parser.parse_args()

	try:
		if args.command == "check":
			load(args.changelog)
		elif args.command == "cut":
			cut(args.changelog, args.version, args.date or datetime.date.today().isoformat())
		elif args.command == "section":
			print("\n".join(find(load(args.changelog), args.version).entries))
		elif args.command == "check-release":
			check_release(load(args.changelog), args.version, args.build, current_feed(args)[0])
		elif args.command == "appcast":
			sections = load(args.changelog)
			items, revision = current_feed(args)
			check_release(sections, args.version, args.build, items)
			if not args.url.startswith("https://") or "/latest/" in args.url:
				raise Failure("the URL of the disk image must name its own release: %s" % args.url)
			items = [i for i in items if i["version"] != args.version]
			items.append({
				"version": args.version, "build": args.build, "min_macos": args.min_macos,
				"url": args.url, "length": args.length, "signature": args.signature,
			})
			write_feed(args.out, items, sections, revision)
		elif args.command == "remove":
			# The owner signs the result, so a forged item of an unchecked feed would get a valid signature.
			check_feed(args.feed, args.public_key)
			items, revision = read_feed(args.feed)
			left = [i for i in items if i["version"] != args.version]
			if len(left) == len(items):
				raise Failure("the feed has no item for version %s." % args.version)
			if not left:
				raise Failure("%s is the last version in the feed. A feed without items carries no revision, so an app could not "
					"tell it from an older feed. Release the fixed version first, then withdraw this one." % args.version)
			write_feed(args.out, left, load(args.changelog), revision + 1)
		elif args.command == "stale-releases":
			for tag in stale_releases(load(args.changelog), sys.stdin):
				print(tag)
		elif args.command == "openssl":
			print(openssl())
		elif args.command == "public-key":
			print(public_key_of(args.file))
		elif args.command == "check-feed":
			check_feed(args.feed, args.public_key)
		elif args.command == "check-newer":
			check_newer(args.feed, args.current)
	except Failure as error:
		sys.exit("%s: %s" % (args.changelog if args.command in ("check", "cut") else "release-notes.py", error))


if __name__ == "__main__":
	main()
