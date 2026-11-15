#!/usr/bin/env python3
"""Checks that every text of the interface has a German translation.

The compiler writes the key of every literal that the app looks up, in the app and in the libraries,
to a .stringsdata file when the build sets SWIFT_EMIT_LOC_STRINGS=YES. scripts/check.sh and
scripts/build-app.sh set it. This script reads these files below the derived data folder of that
build and compares their keys with App/Resources/Localizable.xcstrings. It fails for a key that the
catalog lacks, for an entry without a German value, for an entry that no code uses, for a value
whose placeholders differ from those of its key, and for a plural without "one" and "other".

    python3 scripts/check-localization.py .build/periphery           check
    python3 scripts/check-localization.py .build/periphery --update  add missing entries, remove unused ones
    python3 scripts/check-localization.py .build/periphery --catalog PATH   check another catalog

--update adds a new key with an empty German value, so the check still fails until someone writes
the German text in the catalog. It refuses to run when no .stringsdata file comes from a source of
this repository, because it would then remove every entry. --catalog reads and writes PATH instead
of App/Resources/Localizable.xcstrings, for example a copy to try a change of this script on.

A value may put the placeholders of its key in another order with positions such as %2$@, but each
position keeps the type of the key. Only a plural variation, such as the "one" form of
"%lld transactions", may leave out a placeholder.
"""
import glob
import json
import os
import re
import sys

# The real path, so that a checkout reached through a symbolic link matches the paths of the compiler.
ROOT = os.path.realpath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "App", "Resources", "Localizable.xcstrings")
# The debug harness and the perf check write only to their log, so their texts stay English.
IGNORED = {"App/Sources/DebugHarness.swift", "App/Sources/PerfCheck.swift"}
# A printf placeholder: an optional position, flags, width, precision, length, and the conversion.
# %% is a literal percent sign, and %#@name@ names a substitution of the catalog.
PLACEHOLDER = re.compile(
	r"%(?:%|#@(?P<substitution>\w+)@|(?:(?P<position>\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
	r"(?P<type>(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGaAcCsSp]))"
)
LANGUAGES = {"de": "German", "en": "English"}


def extracted_keys(derived_data):
	"""Maps each key to whether it comes from the app (True) or only from a library (False)."""
	files = glob.glob(os.path.join(derived_data, "Build", "Intermediates.noindex", "**", "*.stringsdata"), recursive=True)
	if not files:
		sys.exit(f"No .stringsdata files below {derived_data}. Build the app with SWIFT_EMIT_LOC_STRINGS=YES first.")
	keys = {}
	accepted = 0
	for path in files:
		with open(path, encoding="utf-8") as f:
			data = json.load(f)
		source = os.path.relpath(os.path.realpath(data["source"]), ROOT)
		# Only the sources of this repository, and not those of a file that a later build removed.
		if source.startswith("..") or source in IGNORED or not os.path.exists(os.path.join(ROOT, source)):
			continue
		if not (source.startswith("App/Sources/") or source.startswith("Sources/")):
			continue
		accepted += 1
		for table, entries in data["tables"].items():
			if table != "Localizable":
				sys.exit(f"{source}: the table {table} is not Localizable. The app has one catalog.")
			for entry in entries:
				keys[entry["key"]] = keys.get(entry["key"], False) or source.startswith("App/")
	# Without one file of this repository, every entry would look unused, and --update would remove it.
	if not accepted:
		sys.exit(f"None of the {len(files)} .stringsdata files below {derived_data} comes from a source in {ROOT}. "
			"Build this checkout first. Nothing was changed.")
	return keys


def units(node, label="", in_plural=False):
	"""Yields each string unit of one language with its label, and whether it is a plural form."""
	if "stringUnit" in node:
		yield label, node["stringUnit"], in_plural
	for kind, forms in node.get("variations", {}).items():
		for name, form in forms.items():
			yield from units(form, f"{label} {kind} {name!r}".strip(), in_plural or kind == "plural")
	for name, substitution in node.get("substitutions", {}).items():
		yield from units(substitution, f"{label} substitution {name!r}".strip(), True)


def is_translated(entry):
	german = entry.get("localizations", {}).get("de")
	if not german:
		return False
	found = list(units(german))
	return bool(found) and all(u.get("state") == "translated" and u.get("value") for _, u, _ in found)


def placeholders(text, substitutions=None):
	"""Maps the position of each placeholder to its type, or returns a text that says why it cannot."""
	types = {}
	running = 0
	for match in PLACEHOLDER.finditer(text):
		if match.group(0) == "%%":
			continue
		kind = match.group("type")
		position = match.group("position")
		name = match.group("substitution")
		if name is not None:
			substitution = (substitutions or {}).get(name)
			if substitution is None:
				return f"the substitution {name!r} is not defined"
			kind = substitution.get("formatSpecifier")
			position = substitution.get("argNum")
		if position is None:
			running += 1
			position = running
		position = int(position)
		if types.get(position, kind) != kind:
			return f"position {position} is both %{types[position]} and %{kind}"
		types[position] = kind
	return types


def describe(types):
	return ", ".join(f"{position}: %{kind}" for position, kind in sorted(types.items())) or "none"


def format_problems(key, entry):
	"""Lists each value whose placeholders differ from those of the key, and each incomplete plural."""
	problems = []
	expected = placeholders(key)
	if isinstance(expected, str):
		return [f"The key {key!r} has broken placeholders: {expected}"]
	for language, localization in entry.get("localizations", {}).items():
		name = LANGUAGES.get(language, language)
		for plural in plurals(localization):
			if not {"one", "other"} <= plural.keys():
				problems.append(f"Plural needs \"one\" and \"other\" in {name}: {key!r} has {sorted(plural)}")
		substitutions = localization.get("substitutions", {})
		for label, unit, in_plural in units(localization):
			# The forms of a substitution count only the substituted number, not the placeholders of the key.
			if "substitution" in label:
				continue
			value = unit.get("value", "")
			if not value:
				continue
			found = placeholders(value, substitutions)
			where = f" ({label})" if label else ""
			if isinstance(found, str):
				problems.append(f"Placeholders differ in {name} for {key!r}{where}: {found} in {value!r}")
				continue
			added = {p: k for p, k in found.items() if expected.get(p) != k}
			left_out = {p: k for p, k in expected.items() if p not in found}
			if added or (left_out and not in_plural):
				problems.append(f"Placeholders differ in {name} for {key!r}{where}: "
					f"the key has {describe(expected)}, {value!r} has {describe(found)}")
	return problems


def plurals(node):
	"""Yields each plural variation of one language, also those of its substitutions and devices."""
	variations = node.get("variations", {})
	if "plural" in variations:
		yield variations["plural"]
	for forms in variations.values():
		for form in forms.values():
			yield from plurals(form)
	for substitution in node.get("substitutions", {}).values():
		yield from plurals(substitution)


def main():
	global CATALOG
	args = []
	update = False
	rest = sys.argv[1:]
	while rest:
		arg = rest.pop(0)
		if arg == "--update":
			update = True
		elif arg == "--catalog" and rest:
			CATALOG = os.path.abspath(rest.pop(0))
		elif arg.startswith("--"):
			sys.exit(__doc__)
		else:
			args.append(arg)
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
	formats = [p for k in sorted(keys) if k in strings for p in format_problems(k, strings[k])]
	for key in missing:
		print(f"Missing in the catalog: {key!r}")
	for key in unused:
		print(f"Not used by any code: {key!r}")
	for key in untranslated:
		print(f"No German translation: {key!r}")
	for problem in formats:
		print(problem)
	if missing or unused or untranslated:
		print("Run scripts/check-localization.py with --update, then write the German values. CONTRIBUTING.md explains it.")
	if formats:
		print("Give each value the placeholders of its key, and each plural the forms \"one\" and \"other\".")
	if missing or unused or untranslated or formats:
		sys.exit(1)
	print(f"All {len(keys)} texts of the interface have a German translation.")


main()
