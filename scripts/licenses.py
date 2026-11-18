#!/usr/bin/env python3
"""The license notices of the parts that ship inside Moneten.app (issue #411, ADR 0020).

Licenses/notices.json names each part with its version, license, copyright lines, license texts,
and the paths it has inside the app. The pins of the repository decide which parts ship:
Tools/FinTSProbeJava/dependencies.lock (the jars and the JDK), Package.resolved, the pin of Sparkle
in scripts/sparkle-tools.sh, Sources/CLua/VERSION, and Sources/ExtensionHost/PublicSuffix/VERSION.

  licenses.py check              fail unless every pin has one entry at its version, every entry has a
                                 pin, every license text exists, and every GPL or LGPL part has a
                                 source archive with its SHA-256
  licenses.py build APP VERSION  write Contents/Resources/<lang>.lproj/Licenses.html into the app APP,
                                 in English and German, for the release VERSION
  licenses.py check-app APP      fail unless the app has both pages with every part at its version,
                                 has the legal folder of the Java runtime, and ships no jar, framework,
                                 or resource bundle that no entry claims
  licenses.py source-names       print the file name of each of these source archives
  licenses.py sources DIR        download the source archive of each GPL and LGPL part once into
                                 .build/tools/sources, check its SHA-256, and copy it into DIR

--root DIR runs on a copy of the repository, for scripts/test-licenses.py.
"""
import argparse, hashlib, html, json, os, re, shutil, sys, urllib.parse, urllib.request
from pathlib import Path

NOTICES = "Licenses/notices.json"
LANGUAGES = ("en", "de")
RELEASES = "https://github.com/MonetenApp/Moneten/releases/tag/v"

TEXT = {
	"en": {
		"title": "Licenses",
		"intro": "Moneten is free software under the GNU General Public License, version 3 or later. "
			"It ships the following parts of other projects, each under its own license. "
			"Each part names its version, its license, its copyright notices, and where its source is. "
			"The full license texts follow at the end.",
		"app_source": "Source code of Moneten",
		"version": "Version", "license": "License", "copyright": "Copyright", "project": "Project",
		"inside": "Inside the app", "source": "Source of this version",
		"attached": "A copy is attached to the release of Moneten {version}",
		"texts": "License texts", "see": "License text",
	},
	"de": {
		"title": "Lizenzen",
		"intro": "Moneten ist freie Software unter der GNU General Public License, Version 3 oder später. "
			"Die App enthält die folgenden Bestandteile anderer Projekte, jeden unter seiner eigenen Lizenz. "
			"Zu jedem Bestandteil stehen hier die Version, die Lizenz, die Urheberrechtsvermerke und der Ort des Quellcodes. "
			"Die vollständigen Lizenztexte folgen am Ende.",
		"app_source": "Quellcode von Moneten",
		"version": "Version", "license": "Lizenz", "copyright": "Urheberrecht", "project": "Projekt",
		"inside": "In der App", "source": "Quellcode dieser Version",
		"attached": "Eine Kopie liegt dem Release von Moneten {version} bei",
		"texts": "Lizenztexte", "see": "Lizenztext",
	},
}


class Failure(Exception):
	pass


def load(root):
	return json.loads((root / NOTICES).read_text(encoding="utf-8"))


def pins(root):
	"""The parts that the pins of the repository ship, as {id: version}."""
	found = {}
	for line in (root / "Tools/FinTSProbeJava/dependencies.lock").read_text().splitlines():
		line = line.strip()
		if not line or line.startswith("#"):
			continue
		coordinate = line.split()[0]
		key, _, version = coordinate.rpartition(":")
		found[key if key.startswith("jdk:") else "maven:" + key] = version
	for pin in json.loads((root / "Package.resolved").read_text())["pins"]:
		found["swiftpm:" + pin["identity"]] = pin["state"]["version"]
	sparkle = re.search(r"^VERSION=(\S+)$", (root / "scripts/sparkle-tools.sh").read_text(), re.M)
	if not sparkle:
		raise Failure("scripts/sparkle-tools.sh has no VERSION line.")
	found["swiftpm:sparkle"] = sparkle.group(1)
	lua = re.fullmatch(r"lua-(\S+)\.tar\.gz", (root / "Sources/CLua/VERSION").read_text().splitlines()[0])
	if not lua:
		raise Failure("Sources/CLua/VERSION does not start with lua-<version>.tar.gz.")
	found["vendor:lua"] = lua.group(1)
	found["vendor:public-suffix-list"] = (root / "Sources/ExtensionHost/PublicSuffix/VERSION").read_text().splitlines()[0]
	return found


def needs_source(part):
	return part["license"].startswith(("GPL", "LGPL"))


def check(root):
	notices = load(root)
	errors = []
	shipped = pins(root)
	entries = {}
	for part in notices["parts"]:
		if part["id"] in entries:
			errors.append(f"{NOTICES} has two entries for {part['id']}.")
		entries[part["id"]] = part
	for key, version in sorted(shipped.items()):
		part = entries.get(key)
		if part is None:
			errors.append(f"{key} {version} ships, but {NOTICES} has no entry for it. Add its license, copyright lines, and license text.")
		elif part["version"] != version:
			errors.append(f"{key} ships in version {version}, but {NOTICES} has the notice of {part['version']}. "
				"Check its license and copyright lines at the new version, then update the entry.")
	for key in sorted(set(entries) - set(shipped)):
		errors.append(f"{NOTICES} has an entry for {key}, which no pin ships. Remove it.")
	for part in [notices["app"], *notices["parts"]]:
		name = part.get("id", part["name"])
		is_app = part is notices["app"]
		if not part.get("texts"):
			errors.append(f"{name} names no license text.")
		for text in part.get("texts", []):
			if not (root / text).is_file():
				errors.append(f"The license text {text} of {name} is missing.")
		if not part.get("paths"):
			errors.append(f"{name} names no path inside the app.")
		if not is_app and not part["copyright"] and not part.get("note") and not part.get("notice"):
			errors.append(f"{name} has no copyright line and no note that says where its notices are.")
		source = part.get("source", {})
		attached = source.get("url", "").startswith("https://") and re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", ""))
		if not is_app and needs_source(part) and not attached:
			errors.append(f"{name} is under {part['license']}, so it needs a source archive with an https URL and its SHA-256.")
	if errors:
		raise Failure("\n".join(errors))
	return notices


def source_name(part):
	return urllib.parse.unquote(part["source"]["url"].rsplit("/", 1)[1])


def paths(part):
	return [path.replace("{version}", part.get("version", "")) for path in part["paths"]]


def page(notices, lang, version, contents):
	t = TEXT[lang]
	e = html.escape
	texts = []
	for part in [notices["app"], *notices["parts"]]:
		for text in part["texts"]:
			if text not in texts:
				texts.append(text)
	anchor = {text: f"text-{i + 1}" for i, text in enumerate(texts)}
	out = [
		"<!doctype html>",
		f'<html lang="{lang}"><head><meta charset="utf-8">',
		'<meta name="viewport" content="width=device-width, initial-scale=1">',
		f"<title>Moneten: {e(t['title'])}</title>",
		"<style>",
		":root { color-scheme: light dark; }",
		"body { font: 14px/1.5 -apple-system, system-ui, sans-serif; max-width: 52em; margin: 2em auto; padding: 0 16px; }",
		"section { border-top: 1px solid color-mix(in srgb, currentColor 20%, transparent); padding-top: 0.5em; margin-top: 1.5em; }",
		"dt { font-weight: 600; } dd { margin: 0 0 0.4em 0; overflow-wrap: anywhere; }",
		"pre { white-space: pre-wrap; font: 12px/1.4 ui-monospace, Menlo, monospace; }",
		"</style></head><body>",
		f"<h1>Moneten: {e(t['title'])}</h1>",
		f"<p>{e(t['intro'])}</p>",
		f'<p>{e(t["app_source"])}: <a href="{e(notices["app"]["home"])}">{e(notices["app"]["home"])}</a>. '
		f'{e(t["license"])}: {e(notices["app"]["license"])}, <a href="#{anchor[notices["app"]["texts"][0]]}">{e(t["see"])}</a>.</p>',
	]
	for part in notices["parts"]:
		out.append(f'<section id="{e(part["id"])}" data-part="{e(part["id"])}@{e(part["version"])}">')
		out.append(f"<h2>{e(part['name'])}</h2><dl>")
		out.append(f"<dt>{e(t['version'])}</dt><dd>{e(part['version'])}</dd>")
		links = ", ".join(f'<a href="#{anchor[text]}">{e(t["see"])} {i + 1}</a>' if len(part["texts"]) > 1
			else f'<a href="#{anchor[text]}">{e(t["see"])}</a>' for i, text in enumerate(part["texts"]))
		out.append(f"<dt>{e(t['license'])}</dt><dd>{e(part['license'])} ({links})</dd>")
		if part["copyright"]:
			out.append(f"<dt>{e(t['copyright'])}</dt><dd>" + "<br>".join(e(line) for line in part["copyright"]) + "</dd>")
		out.append(f'<dt>{e(t["project"])}</dt><dd><a href="{e(part["home"])}">{e(part["home"])}</a></dd>')
		out.append(f"<dt>{e(t['inside'])}</dt><dd>" + "<br>".join(e("Contents/" + path) for path in paths(part)) + "</dd>")
		if "source" in part:
			source = f'<a href="{e(part["source"]["url"])}">{e(part["source"]["url"])}</a>'
			if "sha256" in part["source"]:
				source += (f'<br>{e(t["attached"].format(version=version))}: '
					f'<a href="{e(RELEASES + version)}">{e(source_name(part))}</a> (SHA-256 {e(part["source"]["sha256"])})')
			out.append(f"<dt>{e(t['source'])}</dt><dd>{source}</dd>")
		out.append("</dl>")
		if "note" in part:
			out.append(f"<p>{e(part['note'][lang])}</p>")
		if "notice" in part:
			out.append(f"<pre>{e(part['notice'])}</pre>")
		out.append("</section>")
	out.append(f"<section><h2>{e(t['texts'])}</h2></section>")
	for text in texts:
		out.append(f'<section id="{anchor[text]}"><h3>{e(Path(text).name)}</h3><pre>{e(contents[text])}</pre></section>')
	out.append("</body></html>")
	return "\n".join(out) + "\n"


def build(root, app, version):
	notices = check(root)
	contents = {text: (root / text).read_text(encoding="utf-8") for part in [notices["app"], *notices["parts"]] for text in part["texts"]}
	for lang in LANGUAGES:
		folder = Path(app) / "Contents/Resources" / f"{lang}.lproj"
		folder.mkdir(parents=True, exist_ok=True)
		(folder / "Licenses.html").write_text(page(notices, lang, version, contents), encoding="utf-8")


def check_app(root, app):
	notices = check(root)
	contents = Path(app) / "Contents"
	errors = []
	for lang in LANGUAGES:
		path = contents / "Resources" / f"{lang}.lproj/Licenses.html"
		if not path.is_file():
			errors.append(f"The app has no {path.relative_to(Path(app))}.")
			continue
		text = path.read_text(encoding="utf-8")
		for part in notices["parts"]:
			if f'data-part="{html.escape(part["id"])}@{html.escape(part["version"])}"' not in text:
				errors.append(f"{path.relative_to(Path(app))} lacks {part['id']} {part['version']}.")
	claimed = set()
	for part in [notices["app"], *notices["parts"]]:
		for path in paths(part):
			claimed.add(path)
			if not (contents / path).exists():
				errors.append(f"{part.get('id', part['name'])} names Contents/{path}, which the app lacks.")
	shipped = [p for p in (contents / "Resources/FinTSHelper/lib").glob("*.jar")]
	shipped += list((contents / "Frameworks").glob("*")) + list((contents / "Resources").glob("*.bundle"))
	for path in sorted(shipped):
		if str(path.relative_to(contents)) not in claimed:
			errors.append(f"The app ships Contents/{path.relative_to(contents)}, which no entry of {NOTICES} claims.")
	if errors:
		raise Failure("\n".join(errors))


def sources(root, folder):
	notices = check(root)
	cache = root / ".build/tools/sources"
	cache.mkdir(parents=True, exist_ok=True)
	Path(folder).mkdir(parents=True, exist_ok=True)
	for part in notices["parts"]:
		if "sha256" not in part.get("source", {}):
			continue
		name = source_name(part)
		cached = cache / name
		if not cached.is_file() or sha256(cached) != part["source"]["sha256"]:
			partial = cache / (name + ".part")
			request = urllib.request.Request(part["source"]["url"], headers={"User-Agent": "Moneten release"})
			with urllib.request.urlopen(request, timeout=300) as response, open(partial, "wb") as out:
				shutil.copyfileobj(response, out)
			if sha256(partial) != part["source"]["sha256"]:
				partial.unlink()
				raise Failure(f"The source archive {part['source']['url']} has a wrong SHA-256.")
			partial.rename(cached)
		shutil.copyfile(cached, Path(folder) / name)
		print(Path(folder) / name)


def sha256(path):
	digest = hashlib.sha256()
	with open(path, "rb") as f:
		for block in iter(lambda: f.read(1 << 20), b""):
			digest.update(block)
	return digest.hexdigest()


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--root", default=Path(__file__).resolve().parent.parent, type=Path)
	sub = parser.add_subparsers(dest="command", required=True)
	sub.add_parser("check")
	p = sub.add_parser("build"); p.add_argument("app"); p.add_argument("version")
	p = sub.add_parser("check-app"); p.add_argument("app")
	sub.add_parser("source-names")
	p = sub.add_parser("sources"); p.add_argument("folder")
	args = parser.parse_args()
	try:
		if args.command == "check":
			check(args.root)
			print(f"{NOTICES} covers every shipped part.")
		elif args.command == "build":
			build(args.root, args.app, args.version)
		elif args.command == "check-app":
			check_app(args.root, args.app)
			print(f"{args.app} carries the license notices of every part.")
		elif args.command == "source-names":
			for part in check(args.root)["parts"]:
				if "sha256" in part.get("source", {}):
					print(source_name(part))
		else:
			sources(args.root, args.folder)
	except Failure as failure:
		sys.exit(str(failure))


if __name__ == "__main__":
	main()
