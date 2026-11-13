#!/bin/sh
# Checks the published MoneyMoney extensions against the extension host (ADR 0015, decision 19).
# Downloads every .lua file of https://moneymoney.app/extensions/ into .build/published/ (not in git),
# loads each Web Banking file in the host, and lists each name that a signed file uses and the host
# lacks: MM.* functions and the methods of connections, HTML documents, element lists, and JSON objects.
# Fails when a signed file uses a name that the host does not offer.
set -e
cd "$(dirname "$0")/.."
OUT=.build/published
mkdir -p "$OUT"
swift build --disable-keychain --product MonetenExtensionHost >/dev/null
HOST="$(swift build --disable-keychain --show-bin-path)/MonetenExtensionHost"
curl -fsSL https://moneymoney.app/extensions/ -o "$OUT/index.html"
grep -o 'href="/extensions/[^"]*\.lua"' "$OUT/index.html" | sed 's/^href="//; s/"$//' | sort -u | while read -r path; do
	file="$OUT/$(echo "$path" | sed 's|^/extensions/||; s|/|__|g')"
	[ -s "$file" ] || curl -fsSL "https://moneymoney.app$path" -o "$file"
done
exec python3 -I - "$OUT" "$HOST" <<'PYTHON'
import glob, json, os, re, subprocess, sys

out, host = sys.argv[1], sys.argv[2]
environment = {"productVersion": "0.1", "productBuild": 1, "variant": "retail", "language": "en", "locale": "en_US",
	"deviceUuid": "00000000-0000-4000-8000-000000000000", "country": "DE"}
# The limits of a session of the app (HostLimits).
limits = {"memory": 256 * 1048576, "processorSeconds": 60}
# Values that the API documents as nil in some builds.
may_be_nil = {"MM.APPSTORE", "MM.BETA", "MM.DEBUG", "MM.RETAIL"}

def session(name, text, call=None):
	"""Starts a host session with one Lua file and returns its events."""
	commands = [{"start": {"_0": {"package": {"name": name, "files": [{"name": name + ".lua", "text": text}]}, "decisions": {}, "environment": environment,
		"limits": limits}}}]
	if call:
		commands.append({"call": {"_0": {"function": {"_0": call}}}})
	result = subprocess.run([host], input="".join(json.dumps(c) + "\n" for c in commands), capture_output=True, text=True, timeout=60)
	return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

# The objects whose methods the census checks, by the call that makes them, and the methods that return another one.
CONSTRUCTORS = {"HTML": "html", "JSON": "json", "Connection": "connection"}
RETURNS = {("html", "xpath"): "elements", ("elements", "xpath"): "elements", ("elements", "get"): "elements",
	("elements", "children"): "elements", ("elements", "reverse"): "elements", ("json", "set"): "json"}
# Methods that only one kind of object has, so that a parameter which calls one of them is of that kind.
SIGNATURES = {"xpath": {"html", "elements"}, "each": {"elements"}, "length": {"elements"}, "attr": {"elements"},
	"children": {"elements"}, "click": {"elements"}, "submit": {"elements"}, "val": {"elements"},
	"dictionary": {"json"}, "request": {"connection"}, "getCookies": {"connection"}, "setCookie": {"connection"},
	"getBaseURL": {"connection"}}
# A script often reuses a name for a string, so a call of a string method is the string's, not the object's.
STRING_METHODS = {"byte", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "sub", "upper"}
NAME = r"[A-Za-z_]\w*"
CALL = re.compile(r"\s*:\s*(%s)\s*([(\"'{])" % NAME)

def code_of(text):
	"""The text with comments and the contents of strings blanked, so that offsets and lines stay."""
	out, i, n = list(text), 0, len(text)
	def blank(a, b):
		for k in range(a, min(b, n)):
			if out[k] != "\n":
				out[k] = " "
	while i < n:
		long = re.match(r"(--)?\[(=*)\[", text[i:i + 20])
		if long:
			end = text.find("]" + long.group(2) + "]", i)
			end = n if end < 0 else end
			blank(i if long.group(1) else i + len(long.group(0)), end)
			i = end + len(long.group(2)) + 2
		elif text.startswith("--", i):
			end = text.find("\n", i)
			end = n if end < 0 else end
			blank(i, end)
			i = end
		elif text[i] in "\"'":
			j = i + 1
			while j < n and text[j] not in (text[i], "\n"):
				j += 2 if text[j] == "\\" else 1
			blank(i + 1, j)
			i = j + 1
		else:
			i += 1
	return "".join(out)

def closing(code, start):
	depth = 0
	for k in range(start, len(code)):
		depth += code[k] in "([{"
		depth -= code[k] in ")]}"
		if depth == 0:
			return k
	return None

def follow(code, pos, kinds, calls):
	"""Adds each method call of the chain at pos on an object of one of kinds; returns the kinds of its end."""
	while kinds:
		m = CALL.match(code, pos)
		if not m:
			return kinds
		calls.add((frozenset(kinds), m.group(1), code.count("\n", 0, pos) + 1))
		end = closing(code, m.start(2)) if m.group(2) in "({" else m.end(2)
		if end is None:
			return set()
		pos, kinds = end + 1, {RETURNS[(k, m.group(1))] for k in kinds if (k, m.group(1)) in RETURNS}
	return kinds

def kinds_at(code, pos, names):
	"""The kinds of the object that the expression at pos makes."""
	m = re.compile(r"\s*(%s)\s*\(" % "|".join(CONSTRUCTORS)).match(code, pos)
	if m:
		end = closing(code, m.end() - 1)
		return follow(code, end + 1, {CONSTRUCTORS[m.group(1)]}, set()) if end else set()
	m = re.compile(r"\s*(%s)(?=\s*:)" % NAME).match(code, pos)
	return follow(code, m.end(), names[m.group(1)], set()) if m and m.group(1) in names else set()

def method_calls(text):
	"""The method calls on objects of the API as (kinds, method, line). A name has the kinds of every
	object that the file assigns to it or that its method calls show, wherever in the file."""
	code = code_of(text)
	names = {"connection": {"connection"}}
	for m in re.finditer(r"(?<![\w.:])(%s)\s*:\s*(%s)\s*[(\"'{]" % (NAME, NAME), code):
		if m.group(2) in SIGNATURES:
			names.setdefault(m.group(1), set()).update(SIGNATURES[m.group(2)])
	for _ in range(3):
		for m in re.finditer(r"(?<![\w.:])(%s)\s*=(?!=)" % NAME, code):
			kinds = kinds_at(code, m.end(), names)
			if kinds:
				names.setdefault(m.group(1), set()).update(kinds)
		for m in re.finditer(r":\s*each\s*\(\s*function\s*\(\s*%s\s*,\s*(%s)" % (NAME, NAME), code):
			names.setdefault(m.group(1), set()).add("elements")
	calls = set()
	for m in re.finditer(r"(?<![\w.:])(%s)(?=\s*:)" % NAME, code):
		follow(code, m.end(), names.get(m.group(1), set()), calls)
	for m in re.finditer(r"(?<![\w.:])(%s)\s*\(" % "|".join(CONSTRUCTORS), code):
		end = closing(code, m.end() - 1)
		if end:
			follow(code, end + 1, {CONSTRUCTORS[m.group(1)]}, calls)
	return {(kinds, method, line) for kinds, method, line in calls if method not in STRING_METHODS}

uses, signed, failed, where = {}, set(), {}, {}
for path in sorted(glob.glob(os.path.join(out, "*.lua"))):
	text = open(path, encoding="utf-8", errors="replace").read()
	if "WebBanking" not in text:
		continue
	name = os.path.basename(path)[:-4]
	if "-- SIGNATURE:" in text:
		signed.add(name)
	names = {"MM." + n for n in re.findall(r"(?<![\w.])MM\.([A-Za-z_]\w*)", text)}
	for kinds, method, line in method_calls(text):
		use = "|".join(sorted(kinds)) + ":" + method
		names.add(use)
		where.setdefault((name, use), line)
	uses[name] = names - may_be_nil
	answer = next((e for e in session(name.split("__")[-1], text) if "loaded" in e or "failed" in e), {"failed": {"_0": "no answer"}})
	if "failed" in answer:
		failed[name] = answer["failed"]["_0"]

wanted = sorted(set().union(*uses.values()))
probe = "WebBanking{version = 1}\nlocal names = " + json.dumps(wanted).replace("[", "{").replace("]", "}") + """
function Probe()
	local html = HTML("<p>a</p>")
	local objects = {MM = MM, connection = Connection(), html = html, elements = html:xpath("//p"), json = JSON("{}")}
	local missing = {}
	for _, name in ipairs(names) do
		local kinds, key = name:match("^([%a|]+)[.:](.+)$")
		local found = false
		for kind in kinds:gmatch("%a+") do
			found = found or objects[kind][key] ~= nil
		end
		if not found then table.insert(missing, name) end
	end
	return missing
end
"""
events = session("Probe", probe, "Probe")
result = next((e["result"]["_0"] for e in events if "result" in e), None)
if result is None:
	sys.exit("The probe did not run: %s" % events)
missing = set(result or [])
print("%d Web Banking files, %d signed, %d names in use, %d loaded in the host." % (len(uses), len(signed), len(wanted), len(uses) - len(failed)))
for name, message in sorted(failed.items()):
	print("load %s %s: %s" % ("signed" if name in signed else "unsigned", name, message))
problems = 0
for name in sorted(uses):
	lacking = sorted(uses[name] & missing)
	if lacking:
		print("%s %s uses %s" % ("signed" if name in signed else "unsigned", name, ", ".join("%s (line %d)" % (use, where[(name, use)]) if (name, use) in where else use for use in lacking)))
		problems += name in signed
sys.exit(1 if problems else 0)
PYTHON
