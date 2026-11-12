#!/bin/sh
# Checks the published MoneyMoney extensions against the extension host (ADR 0015, decision 19).
# Downloads every .lua file of https://moneymoney.app/extensions/ into .build/published/ (not in git),
# loads each Web Banking file in the host, and lists each MM.* and connection name that a signed file
# uses and the host lacks. Fails when a signed file uses a name that the host does not offer.
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
# Values that the API documents as nil in some builds.
may_be_nil = {"MM.APPSTORE", "MM.BETA", "MM.DEBUG", "MM.RETAIL"}

def session(name, text, call=None):
	"""Starts a host session with one Lua file and returns its events."""
	commands = [{"start": {"_0": {"package": {"name": name, "files": [{"name": name + ".lua", "text": text}]}, "decisions": {}, "environment": environment}}}]
	if call:
		commands.append({"call": {"_0": {"function": {"_0": call}}}})
	result = subprocess.run([host], input="".join(json.dumps(c) + "\n" for c in commands), capture_output=True, text=True, timeout=60)
	return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

uses, signed, failed = {}, set(), {}
for path in sorted(glob.glob(os.path.join(out, "*.lua"))):
	text = open(path, encoding="utf-8", errors="replace").read()
	if "WebBanking" not in text:
		continue
	name = os.path.basename(path)[:-4]
	if "-- SIGNATURE:" in text:
		signed.add(name)
	names = {"MM." + n for n in re.findall(r"(?<![\w.])MM\.([A-Za-z_]\w*)", text)}
	names |= {"connection:" + n for n in re.findall(r"\bconnection[:.]([A-Za-z_]\w*)", text)}
	uses[name] = names - may_be_nil
	events = session(name.split("__")[-1], text)
	if not events or "loaded" not in events[0]:
		failed[name] = events[0]["failed"]["_0"] if events and "failed" in events[0] else "no answer"

wanted = sorted(set().union(*uses.values()))
probe = "WebBanking{version = 1}\nlocal names = " + json.dumps(wanted).replace("[", "{").replace("]", "}") + """
function Probe()
	local missing, connection = {}, Connection()
	for _, name in ipairs(names) do
		local object, key = name:match("^(%a+)[.:](.+)$")
		local value = object == "MM" and MM[key] or connection[key]
		if value == nil then table.insert(missing, name) end
	end
	return missing
end
"""
events = session("Probe", probe, "Probe")
result = next((e["result"]["_0"] for e in events if "result" in e), None)
if result is None:
	sys.exit("The probe did not run: %s" % events)
missing = set(result or [])
print("%d Web Banking files, %d signed, %d names in use." % (len(uses), len(signed), len(wanted)))
for name, message in sorted(failed.items()):
	print("load %s %s: %s" % ("signed" if name in signed else "unsigned", name, message))
problems = 0
for name in sorted(uses):
	lacking = sorted(uses[name] & missing)
	if lacking:
		print("%s %s uses %s" % ("signed" if name in signed else "unsigned", name, ", ".join(lacking)))
		problems += name in signed
sys.exit(1 if problems else 0)
PYTHON
