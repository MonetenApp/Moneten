#!/usr/bin/env python3
"""Checks that every text of the interface has a German translation.

The compiler writes the key of every literal that the app looks up, in the app and in the libraries,
to a .stringsdata file when the build sets SWIFT_EMIT_LOC_STRINGS=YES. scripts/check.sh and
scripts/build-app.sh set it. This script reads these files below the derived data folder of that
build and compares their keys with App/Resources/Localizable.xcstrings. It fails for a key that the
catalog lacks, for an entry without a German value, and for an entry that no code uses.

    python3 scripts/check-localization.py .build/periphery           check
    python3 scripts/check-localization.py .build/periphery --update  add missing entries, remove unused ones

--update adds a new key with an empty German value, so the check still fails until someone writes
the German text in the catalog.
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App", "Resources", "Localizable.xcstrings")
# The debug harness and the perf check write only to their log, so their texts stay English.
IGNORED = {"App/Sources/DebugHarness.swift", "App/Sources/PerfCheck.swift"}


def extracted_keys(derived_data):
	"""Maps each key to whether it comes from the app (True) or only from a library (False)."""
	files = glob.glob(os.path.join(derived_data, "Build", "Intermediates.noindex", "**", "*.stringsdata"), recursive=True)
	if not files:
		sys.exit(f"No .stringsdata files below {derived_data}. Build the app with SWIFT_EMIT_LOC_STRINGS=YES first.")
	keys = {}
	for path in files:
		with open(path, encoding="utf-8") as f:
			data = json.load(f)
		source = os.path.relpath(data["source"], ROOT)
		# Only the sources of this repository, and not those of a file that a later build removed.
		if source.startswith("..") or source in IGNORED or not os.path.exists(os.path.join(ROOT, source)):
			continue
		if not (source.startswith("App/Sources/") or source.startswith("Sources/")):
			continue
		for table, entries in data["tables"].items():
			if table != "Localizable":
				sys.exit(f"{source}: the table {table} is not Localizable. The app has one catalog.")
			for entry in entries:
				keys[entry["key"]] = keys.get(entry["key"], False) or source.startswith("App/")
	return keys


def units(localization):
	"""The string units of one language: one, or one for each plural variation."""
	if "stringUnit" in localization:
		return [localization["stringUnit"]]
	variations = localization.get("variations", {}).get("plural", {})
	return [v["stringUnit"] for v in variations.values() if "stringUnit" in v]


def is_translated(entry):
	german = entry.get("localizations", {}).get("de")
	if not german:
		return False
	found = units(german)
	return bool(found) and all(u.get("state") == "translated" and u.get("value") for u in found)


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	update = "--update" in sys.argv
	if len(args) != 1:
		sys.exit(__doc__)
	keys = extracted_keys(args[0])
	with open(CATALOG, encoding="utf-8") as f:
		catalog = json.load(f)
	strings = catalog["strings"]
	missing = sorted(k for k in keys if k not in strings)
	unused = sorted(k for k in strings if k not in keys)
	if update:
		for key in missing:
			entry = {"localizations": {"de": {"stringUnit": {"state": "new", "value": ""}}}}
			# Xcode marks a key that it does not find in the app as stale. A key of a library is kept by hand.
			if not keys[key]:
				entry["extractionState"] = "manual"
			strings[key] = entry
		for key in unused:
			del strings[key]
		catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))
		with open(CATALOG, "w", encoding="utf-8") as f:
			f.write(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")
		print(f"Added {len(missing)} and removed {len(unused)} entries in {os.path.relpath(CATALOG, ROOT)}.")
		missing, unused = [], []
	untranslated = sorted(k for k in keys if k in strings and not is_translated(strings[k]))
	for key in missing:
		print(f"Missing in the catalog: {key!r}")
	for key in unused:
		print(f"Not used by any code: {key!r}")
	for key in untranslated:
		print(f"No German translation: {key!r}")
	if missing or unused or untranslated:
		print("Run scripts/check-localization.py with --update, then write the German values. CONTRIBUTING.md explains it.")
		sys.exit(1)
	print(f"All {len(keys)} texts of the interface have a German translation.")


main()
