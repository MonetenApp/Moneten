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
  release-notes.py remove <version> --feed FILE --out FILE
                                             take the item of a version out of the feed

The format is in the design of the change add-software-update. A version is 1.2.3 or 1.2.3-beta.4.
The feed this script writes is not signed. sign_update of Sparkle signs it afterwards, and this
script drops that signature when it reads the feed, because every change needs a new one.
"""

import argparse
import datetime
import email.utils
import re
import sys
import xml.etree.ElementTree as ET

CHANGELOG = "CHANGELOG.md"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
VERSION = r"(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?"
HEADING = re.compile(r"## (?:Unreleased|(%s) \((\d{4}-\d{2}-\d{2})\))$" % VERSION)
ENTRY = re.compile(r"- \S.*$")
LINK = re.compile(r"\]\(([^)]*)\)")
HTML = re.compile(r"<[A-Za-z/!]")
VERSION_ONLY = re.compile(VERSION + "$")


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


def sparkle(tag):
	return "{%s}%s" % (SPARKLE, tag)


def read_feed(path):
	"""Returns the items of a feed as dicts. The notes are not read, they come from CHANGELOG.md."""
	try:
		root = ET.parse(path).getroot()
	except (OSError, ET.ParseError) as error:
		raise Failure("cannot read the current feed %s: %s" % (path, error))
	items = []
	for item in root.iter("item"):
		enclosure = item.find("enclosure")
		version = item.findtext(sparkle("shortVersionString"))
		if enclosure is None or version is None:
			raise Failure("an item of %s has no version or no enclosure." % path)
		items.append({
			"version": version,
			"build": int(item.findtext(sparkle("version"))),
			"min_macos": item.findtext(sparkle("minimumSystemVersion")),
			"url": enclosure.get("url"),
			"length": int(enclosure.get("length")),
			"signature": enclosure.get(sparkle("edSignature")),
		})
	return items


def write_feed(path, items, sections):
	"""Writes the items newest first. The same items and CHANGELOG.md always give the same bytes."""
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


def current_items(args):
	if args.first_release:
		return []
	return read_feed(args.feed)


def check_release(sections, version, build, items):
	"""The rules of step 1 of the release workflow: a section, a higher build, and a higher version."""
	version_key(version)
	find(sections, version)
	for item in items:
		if item["version"] == version:
			continue
		if build <= item["build"]:
			raise Failure("build %d is not above build %d of version %s in the feed." % (build, item["build"], item["version"]))
		if version_key(version) <= version_key(item["version"]):
			raise Failure("version %s is not above version %s in the feed." % (version, item["version"]))


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
	command.add_argument("--out", required=True)
	args = parser.parse_args()

	try:
		if args.command == "check":
			load(args.changelog)
		elif args.command == "cut":
			cut(args.changelog, args.version, args.date or datetime.date.today().isoformat())
		elif args.command == "section":
			print("\n".join(find(load(args.changelog), args.version).entries))
		elif args.command == "check-release":
			check_release(load(args.changelog), args.version, args.build, current_items(args))
		elif args.command == "appcast":
			sections = load(args.changelog)
			items = current_items(args)
			check_release(sections, args.version, args.build, items)
			if not args.url.startswith("https://") or "/latest/" in args.url:
				raise Failure("the URL of the disk image must name its own release: %s" % args.url)
			items = [i for i in items if i["version"] != args.version]
			items.append({
				"version": args.version, "build": args.build, "min_macos": args.min_macos,
				"url": args.url, "length": args.length, "signature": args.signature,
			})
			write_feed(args.out, items, sections)
		elif args.command == "remove":
			items = read_feed(args.feed)
			left = [i for i in items if i["version"] != args.version]
			if len(left) == len(items):
				raise Failure("the feed has no item for version %s." % args.version)
			write_feed(args.out, left, load(args.changelog))
	except Failure as error:
		sys.exit("%s: %s" % (args.changelog if args.command in ("check", "cut") else "release-notes.py", error))


if __name__ == "__main__":
	main()
