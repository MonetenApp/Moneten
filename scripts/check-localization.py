#!/usr/bin/env python3
"""Checks that every text of the interface has a German translation.

The compiler writes the key of every literal that the app looks up, in the app and in the libraries,
to a .stringsdata file when the build sets SWIFT_EMIT_LOC_STRINGS=YES. scripts/check.sh and
scripts/build-app.sh set it. This script reads these files below the derived data folder of that
build and compares their keys with App/Resources/Localizable.xcstrings. It fails for a key that the
catalog lacks, for an entry without a German value, for an entry that no code uses, for a value
whose placeholders differ from those of its key, and for a plural without a text in "one" and "other".
It also checks that App/Resources/InfoPlist.xcstrings gives each key of the Info.plist an English and a
German value, and that every title of the menu bar is a text that the catalog translates (see menu_title_problems).

    python3 scripts/check-localization.py .build/periphery           check
    python3 scripts/check-localization.py .build/periphery --update  add missing entries, remove unused ones
    python3 scripts/check-localization.py .build/periphery --catalog PATH   check another catalog

--update adds a new key with an empty German value, so the check still fails until someone writes
the German text in the catalog. It refuses to run when no .stringsdata file comes from a source of
this repository, because it would then remove every entry. --catalog reads and writes PATH instead
of App/Resources/Localizable.xcstrings, for example a copy to try a change of this script on.

A value may put the placeholders of its key in another order with positions such as %2$@, but each
position keeps the type of the key. Only a plural variation, such as the "one" form of
"%lld transactions", may leave out a placeholder. A form of a substitution writes its number as %arg
and may name another placeholder of the key only by its position, such as %1$@.
"""
import glob
import json
import os
import plistlib
import re
import sys

# The real path, so that a checkout reached through a symbolic link matches the paths of the compiler.
ROOT = os.path.realpath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "App", "Resources", "Localizable.xcstrings")
INFO_PLIST = os.path.join(ROOT, "App", "Info.plist")
INFO_CATALOG = os.path.join(ROOT, "App", "Resources", "InfoPlist.xcstrings")
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
			for form in ("one", "other"):
				found = list(units(plural[form])) if form in plural else None
				if found is not None and not (found and all(u.get("value") for _, u, _ in found)):
					problems.append(f"Plural form {form!r} has no text in {name}: {key!r}")
		substitutions = localization.get("substitutions", {})
		for label, unit, in_plural in units(localization):
			value = unit.get("value", "")
			if not value:
				continue
			where = f" ({label})" if label else ""
			# A form of a substitution writes the substituted number as %arg. Any other placeholder in it
			# needs the position of a placeholder of the key, such as %1$@, with the type of that placeholder.
			if "substitution" in label:
				rest = value.replace("%arg", "")
				matches = [m for m in PLACEHOLDER.finditer(rest) if m.group(0) != "%%"]
				if any(m.group("position") is None or expected.get(int(m.group("position"))) != m.group("type") for m in matches):
					problems.append(f"Placeholders differ in {name} for {key!r}{where}: a form of a substitution holds only %arg "
						f"and positions of the key ({describe(expected)}), not {', '.join(m.group(0) for m in matches)} in {value!r}")
				continue
			found = placeholders(value, substitutions)
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


# A view of the menu bar whose first argument, unless it has a label such as action:, is its title.
MENU_VIEW = re.compile(r"\b(?:Button|Toggle|Menu|CommandMenu|Picker|Text)\(")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# A title of a property: `removeTitle`, `self.removeTitle`, `model.removeTitle`, or `$0.title` in a ForEach.
PROPERTY = re.compile(r"^(?:(?P<receiver>\$?\w+)\.)?(?P<name>[a-z]\w*)$")
TYPE = re.compile(r"\b(?:struct|class|enum|extension|actor)\s+(?P<name>[A-Z][\w.]*)[^{};]*\{")


def without_comments(text):
	"""The text with each // comment removed, but not a // inside a string literal such as a URL."""
	out, i, in_string = [], 0, False
	while i < len(text):
		c = text[i]
		if in_string:
			if c == "\\":
				out.append(text[i:i + 2])
				i += 2
				continue
			in_string = c != '"' and c != "\n"
		elif c == '"':
			in_string = True
		elif text.startswith("//", i):
			i = text.find("\n", i)
			if i < 0:
				break
			continue
		out.append(c)
		i += 1
	return "".join(out)


def call_end(text, start):
	"""The index of the comma or closing bracket that ends the argument starting at `start`, outside string literals."""
	depth, i, in_string = 0, start, False
	while i < len(text):
		c = text[i]
		if in_string:
			if c == "\\":
				i += 1
			elif c == '"':
				in_string = False
		elif c == '"':
			in_string = True
		elif c in "([{":
			depth += 1
		elif c in ")]}" and depth:
			depth -= 1
		elif c in "),]}" and not depth:
			break
		i += 1
	return i


def first_argument(text, start):
	"""The first argument of the call whose parenthesis ends just before `start`."""
	return text[start:call_end(text, start)].strip()


def without_localized(text):
	"""The text without each call String(localized: ...), also one with more arguments such as comment:."""
	key = "String(localized:"
	out, i = [], 0
	while (found := text.find(key, i)) >= 0:
		out.append(text[i:found])
		# Every argument up to the closing parenthesis of the call.
		end = call_end(text, found + len(key))
		while end < len(text) and text[end] == ",":
			end = call_end(text, end + 1)
		i = end + 1
	out.append(text[i:])
	return "".join(out)


def block_end(text, start):
	"""The index after the brace that closes the block whose body starts at `start`."""
	depth, i = 1, start
	while i < len(text) and depth:
		depth += {"{": 1, "}": -1}.get(text[i], 0)
		i += 1
	return i


def types_at(text, position):
	"""The names of the types whose body holds `position`, innermost last."""
	return [m.group("name").split(".")[-1] for m in TYPE.finditer(text) if m.end() <= position < block_end(text, m.end())]


def properties(sources, name):
	"""Each computed property `name` of type String or String? in `sources` as (path, innermost type, body)."""
	declaration = re.compile(r"\bvar\s+" + re.escape(name) + r"\s*:\s*String\??\s*\{")
	found = []
	for path, text in sorted(sources.items()):
		for match in declaration.finditer(text):
			owners = types_at(text, match.start())
			found.append((path, owners[-1] if owners else None, text[match.end():block_end(text, match.end()) - 1]))
	return found


# A word before "(" that opens a group, not a call: `return ("Open")` returns the literal.
KEYWORDS = {"return", "if", "guard", "case", "in", "else", "where", "while", "switch", "throw", "try", "await", "let", "var"}


def in_call(before):
	"""Whether the end of `before`, code with masked literals, lies inside the arguments of a call."""
	openers = []
	for i, c in enumerate(before):
		if c in "([{":
			word = re.search(r"([\w)\]?!>]*)\s*$", before[:i]).group(1)
			openers.append(c == "(" and bool(word) and word not in KEYWORDS)
		elif c in ")]}" and openers:
			openers.pop()
	return any(openers)


def returned_literals(body):
	"""The literals that a property body gives as its value, such as `case .account: "Remove Account..."`.

	A literal among the arguments of a call, such as `of: "-"` of replacingOccurrences, and one after ==, !=, or
	case, or before {, is no title. One in parentheses that only group it, such as `return ("Open")`, and one whose
	method gives a String, such as `"Open".uppercased()`, is.
	"""
	code = without_localized(without_comments(body))
	masked = STRING_LITERAL.sub(lambda m: '"' + "x" * (len(m.group(0)) - 2) + '"', code)
	literals = []
	for match in STRING_LITERAL.finditer(code):
		before, after = masked[:match.start()], code[match.end():]
		if in_call(before) or re.search(r"(?:==|!=|~=|\bcase|,)\s*$", before) or re.match(r"\s*(?:\{|==|!=)", after):
			continue
		literals.append(match.group(0))
	return literals


def collection_type(code, position):
	"""The type of the innermost ForEach around `position` when it runs over `Type.allCases`, else None."""
	found = None
	for match in re.finditer(r"\bForEach\(", code[:position]):
		end = call_end(code, match.end())
		# The arguments of the call end at its closing parenthesis.
		while end < len(code) and code[end] == ",":
			end = call_end(code, end + 1)
		block = code.find("{", end)
		if block < 0 or block > position or block_end(code, block + 1) <= position:
			continue
		of = re.match(r"\s*([A-Z]\w*)\.allCases\b", code[match.end():])
		found = of.group(1) if of else None
	return found


def menu_title_problems(sources):
	"""Lists each title of the menu bar that the catalog cannot translate.

	`sources` maps the path of each Swift file of the app and the libraries to its text. The menus are the files of
	the app that declare a Commands type. SwiftUI looks up a literal title, such as Button("Add Category"), also both
	literals of a ternary, in the catalog, and the compiler extracts its key. A title of type String shows verbatim,
	so it comes from String(localized:). A literal after ?? next to such a title is a String too. A title that names
	a property, such as Button(model.removeTitle), passes when every literal that the property returns is the key of
	a String(localized:). The property of `model.` is one of AppModel, a bare name one of the type that holds the
	menu, and `$0.title` one of the type of `Type.allCases` in the ForEach around it. When no ForEach names the
	type, every type that declares the property counts, and the title fails only when all of them return a plain
	literal. "Remove Account Group..." stayed English for both reasons (issue #463).
	"""
	problems = []
	for path, text in sorted(sources.items()):
		if not path.startswith("App/") or not re.search(r":\s*Commands\s*\{", text):
			continue
		code = without_comments(text)
		for match in MENU_VIEW.finditer(code):
			argument = first_argument(code, match.end())
			if not argument or re.match(r"\w+\s*:", argument):
				continue
			where = f"{path}:{code.count(chr(10), 0, match.start()) + 1}"
			value, *fallbacks = [part.strip() for part in without_localized(argument).split("??")]
			if any(STRING_LITERAL.search(part) for part in fallbacks):
				problems.append(f"{where}: the literal after ?? in the menu title {argument!r} is a String and shows verbatim. "
					"Write String(localized: ...).")
			if STRING_LITERAL.search(value):
				if "+" in STRING_LITERAL.sub("", value):
					problems.append(f"{where}: the menu title {argument!r} joins a literal to a String, so it shows verbatim. "
						"Write String(localized: ...) with the whole text.")
				continue
			if not value:
				continue
			title = PROPERTY.match(value)
			candidates = properties(sources, title.group("name")) if title else []
			receiver = title.group("receiver") if title else None
			if receiver == "model":
				candidates = [c for c in candidates if c[1] == "AppModel"]
			elif receiver in (None, "self"):
				candidates = [c for c in candidates if c[1] in types_at(code, match.start())]
			elif element := collection_type(code, match.start()):
				candidates = [c for c in candidates if c[1] == element]
			if not candidates:
				problems.append(f"{where}: the menu title {argument!r} is neither a literal nor a String property of the app, "
					"so this check cannot see its text. Use a literal or a property that returns String(localized: ...).")
				continue
			plain = [(source, body) for source, _, body in candidates if returned_literals(body)]
			# The type of an element that no ForEach names stays open: then the title shows verbatim only when every type
			# that has a property of its name returns a plain literal.
			if len(candidates) > 1 and len(plain) < len(candidates):
				continue
			for source, body in plain:
				for literal in returned_literals(body):
					problems.append(f"{source}: {title.group('name')} returns the literal {literal} for the menu title at {where}, "
						f"which shows verbatim. Write String(localized: {literal}).")
	return problems


def swift_sources():
	"""The Swift files of the app and of the libraries, which hold the properties that a menu title may name."""
	sources = {}
	for folder in (("App", "Sources"), ("Sources",)):
		for path in sorted(glob.glob(os.path.join(ROOT, *folder, "**", "*.swift"), recursive=True)):
			relative = os.path.relpath(path, ROOT)
			if relative not in IGNORED:
				with open(path, encoding="utf-8") as f:
					sources[relative] = f.read()
	return sources


def info_plist_problems():
	"""Lists each key of InfoPlist.xcstrings without a translated English and German value.

	A key without an English value makes the bundle show the key itself, such as
	NSHumanReadableCopyright, so the English value must be the text of App/Info.plist: the value of a
	top-level key, or the key itself for a nested text such as the description of a type.
	"""
	with open(INFO_PLIST, "rb") as f:
		plist = plistlib.load(f)
	with open(INFO_CATALOG, encoding="utf-8") as f:
		strings = json.load(f)["strings"]
	problems = []
	for key, entry in sorted(strings.items()):
		for language, name in LANGUAGES.items():
			unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
			if unit.get("state") != "translated" or not unit.get("value"):
				problems.append(f"No {name} value in InfoPlist.xcstrings: {key!r}")
		english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
		expected = plist[key] if isinstance(plist.get(key), str) else key
		if english and english != expected:
			problems.append(f"The English value of {key!r} in InfoPlist.xcstrings is {english!r}, but App/Info.plist has {expected!r}")
	return problems


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
	info = info_plist_problems()
	menus = menu_title_problems(swift_sources())
	for key in missing:
		print(f"Missing in the catalog: {key!r}")
	for key in unused:
		print(f"Not used by any code: {key!r}")
	for key in untranslated:
		print(f"No German translation: {key!r}")
	for problem in formats + info + menus:
		print(problem)
	if missing or unused or untranslated:
		print("Run scripts/check-localization.py with --update, then write the German values. CONTRIBUTING.md explains it.")
	if formats:
		print("Give each value the placeholders of its key, and each plural the forms \"one\" and \"other\".")
	if info:
		print("Give each key of App/Resources/InfoPlist.xcstrings the English text of App/Info.plist and a German value.")
	if missing or unused or untranslated or formats or info or menus:
		sys.exit(1)
	print(f"All {len(keys)} texts of the interface have a German translation.")


if __name__ == "__main__":
	main()
