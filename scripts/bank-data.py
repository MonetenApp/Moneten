#!/usr/bin/env python3
"""Builds, signs, and checks the bank data files of the release bank-data (add-software-update, group 6).

  bank-data.py build --out DIR [--jar FILE] [--lock FILE] [--corrections FILE] [--serial N]
                         write DIR/blz.properties: the bank list of the hbci4java jar that the lock pins,
                         after the check of its SHA-256, with the corrections of the project applied, and
                         a header with the serial, the time in UTC as yyyymmddHHMMSS, and the version of
                         the jar. The app installs a list only when its serial is above the installed one
                         and its jar is not older than its own, so nobody can replay an older list.
  bank-data.py sign --key-file KEY [--sign-update TOOL] FILE
                         write FILE.sig, the Ed25519 signature of FILE in Base64, with the private key KEY
                         in the format of Sparkle, through the sign_update tool of Sparkle or else openssl
  bank-data.py verify --public-key KEY FILE
                         fail unless KEY, the public key in Base64, signed FILE, and FILE is a bank list
  bank-data.py check FILE
                         fail unless FILE is a bank list that the app reads
  bank-data.py public-key FILE
                         print the public key of the private key file FILE, for the check of the workflow
  bank-data.py dry-run --out DIR [--jar FILE] [--sign-update TOOL]
                         build the files and sign them with a throwaway key, check them, check that one
                         changed byte fails, and publish nothing
  bank-data.py check-latest --repo OWNER/NAME
                         after an upload: fail when the latest release is a version of the app whose
                         feed URL does not answer, or when it is no version of the app, such as bank-data,
                         although one is published. Reads GitHub with gh and curl.

The app runs the same checks with BankData.verify and BankData.isReadableBankList in Sources/FinTS.
Checking needs OpenSSL 3 or later, and so does signing without sign_update. The workflow signs with
the update key only through sign_update, as the release does, and openssl gets only the test key and
throwaway keys, in a file of a temporary folder that only the user can read, never in an argument.
"""

import argparse
import base64
import datetime
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

LOCK = "Tools/FinTSProbeJava/dependencies.lock"
CORRECTIONS = "BankData/corrections.properties"
CORE = "com.github.hbci4j:hbci4j-core"
BANK_LIST = "blz.properties"
# Every file of the release. Each has its signature beside it, under its name with ".sig".
FILES = [BANK_LIST]
# The largest file the app accepts, BankDataUpdater.listLimit.
LIMIT = 8 << 20
ENTRY = re.compile(r"[0-9]{8}=[^|]*(\|[^|]*){7,}")
# The header lines before the first entry, after "#" or "!" and spaces, as BankData.Header reads them.
SERIAL = re.compile(r"serial=([0-9]{14})")
VERSION = re.compile(r"hbci4java=([0-9]+(?:\.[0-9]+)*)")
ED25519_PUBLIC_PREFIX = bytes.fromhex("302a300506032b6570032100")
ED25519_PRIVATE_PREFIX = bytes.fromhex("302e020100300506032b657004220420")


class Failure(Exception):
	pass


def openssl():
	"""An OpenSSL 3 or later. The LibreSSL of macOS in /usr/bin cannot sign Ed25519 with -rawin."""
	for path in (os.environ.get("MONETEN_OPENSSL"), shutil.which("openssl"),
			"/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"):
		if path and os.access(path, os.X_OK):
			version = subprocess.run([path, "version"], capture_output=True, text=True).stdout
			match = re.match(r"OpenSSL (\d+)\.", version)
			if match and int(match.group(1)) >= 3:
				return path
	raise Failure("signing needs OpenSSL 3 or later, which macOS does not include: brew install openssl@3, or set MONETEN_OPENSSL.")


def check_bank_list(data, name):
	"""The check of BankData.isReadableBankList: UTF-8, no backslash, at least one entry, and every line
	that is not empty or a comment a Bankleitzahl, "=", and at least eight fields separated by "|"."""
	if len(data) > LIMIT:
		raise Failure("%s has %d bytes, more than the %d that the app accepts." % (name, len(data), LIMIT))
	try:
		text = data.decode("utf-8")
	except UnicodeDecodeError:
		raise Failure("%s is not UTF-8." % name)
	if "\\" in text:
		raise Failure("%s contains a backslash, which Java reads as an escape." % name)
	entries = 0
	serial = version = None
	for number, line in enumerate(text.splitlines(), 1):
		line = line.strip(" \t")
		if entries == 0 and line.startswith(("#", "!")):
			comment = line[1:].lstrip(" ")
			for key, pattern in (("serial", SERIAL), ("hbci4java", VERSION)):
				if comment.startswith(key):
					found = pattern.fullmatch(comment)
					if not found or (serial if key == "serial" else version) is not None:
						raise Failure("%s, line %d, is a second or malformed %s line." % (name, number, key))
					if key == "serial":
						serial = found.group(1)
					else:
						version = found.group(1)
		if not line or line.startswith(("#", "!")):
			continue
		if not ENTRY.fullmatch(line):
			raise Failure("%s, line %d, is no entry of the bank list." % (name, number))
		entries += 1
	if entries == 0:
		raise Failure("%s has no entry." % name)
	if serial is None or version is None:
		raise Failure("%s has no header with the serial and the version of hbci4java before its first entry." % name)
	return entries


def lock_entry(lock):
	with open(lock) as f:
		for line in f:
			parts = line.split()
			if len(parts) == 2 and parts[0].startswith(CORE + ":"):
				return parts[0].split(":")[2], parts[1]
	raise Failure("%s does not pin %s." % (lock, CORE))


def core_jar(lock, jar):
	"""The bytes of the hbci4java jar that the lock pins: the file `jar`, the copy of
	scripts/hbci4java-jars.sh, or a download from Maven Central. Each must match the SHA-256 of the lock."""
	version, sha = lock_entry(lock)
	candidates = [jar] if jar else [".build/hbci4java/lib/hbci4j-core-%s.jar" % version]
	for path in candidates:
		if path and os.path.exists(path):
			with open(path, "rb") as f:
				data = f.read()
			break
	else:
		if jar:
			raise Failure("cannot read %s." % jar)
		url = "https://repo1.maven.org/maven2/com/github/hbci4j/hbci4j-core/%s/hbci4j-core-%s.jar" % (version, version)
		with urllib.request.urlopen(url, timeout=120) as response:
			data = response.read()
	if hashlib.sha256(data).hexdigest() != sha:
		raise Failure("the hbci4java jar does not match the SHA-256 of %s." % lock)
	return data


def apply_corrections(data, corrections):
	"""Replaces the entry of each Bankleitzahl that the corrections name, in place, and adds the others
	at the end. The corrections have the format of the bank list."""
	if not corrections or not os.path.exists(corrections):
		return data
	with open(corrections, "rb") as f:
		fixes = f.read()
	changes = {}
	for line in (line.strip() for line in fixes.decode("utf-8").splitlines()):
		if not line or line.startswith(("#", "!")):
			continue
		if not ENTRY.fullmatch(line) or "\\" in line:
			raise Failure("%s has a line that is no entry of the bank list: %s" % (corrections, line))
		changes[line[:8]] = line
	if not changes:
		return data
	lines = data.decode("utf-8").splitlines()
	out = []
	for line in lines:
		code = line[:8]
		out.append(changes.pop(code) if code in changes and line[8:9] == "=" else line)
	out.extend(changes[code] for code in sorted(changes))
	# The jar writes CRLF, and the corrections keep its line ends.
	return ("\r\n".join(out) + "\r\n").encode("utf-8")


def build(out, jar=None, lock=LOCK, corrections=CORRECTIONS, serial=None):
	with zipfile.ZipFile(io.BytesIO(core_jar(lock, jar))) as archive:
		data = archive.read(BANK_LIST)
	data = apply_corrections(data, corrections)
	serial = serial or datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
	if not re.fullmatch(r"[0-9]{14}", serial):
		raise Failure("the serial %s is not yyyymmddHHMMSS." % serial)
	header = "# Bank list of Moneten, signed with the update key.\r\n# serial=%s\r\n# hbci4java=%s\r\n" % (serial, lock_entry(lock)[0])
	data = header.encode("utf-8") + data
	entries = check_bank_list(data, BANK_LIST)
	os.makedirs(out, exist_ok=True)
	with open(os.path.join(out, BANK_LIST), "wb") as f:
		f.write(data)
	print("%s: %d banks, SHA-256 %s" % (os.path.join(out, BANK_LIST), entries, hashlib.sha256(data).hexdigest()))


def seed_of(key_file):
	try:
		with open(key_file, "rb") as f:
			seed = base64.b64decode(f.read().strip(), validate=True)[:32]
	except (OSError, ValueError) as error:
		raise Failure("cannot read the private key %s: %s" % (key_file, error))
	if len(seed) != 32:
		raise Failure("%s is not a private key of Sparkle." % key_file)
	return seed


def public_key_of(key_file):
	result = subprocess.run([openssl(), "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
		input=ED25519_PRIVATE_PREFIX + seed_of(key_file), capture_output=True)
	if result.returncode != 0:
		raise Failure("%s is not a private key of Sparkle." % key_file)
	return base64.b64encode(result.stdout[-32:]).decode()


def sign(key_file, path, sign_update=None):
	if sign_update:
		result = subprocess.run([sign_update, "--ed-key-file", key_file, "-p", path], capture_output=True, text=True)
		signature = result.stdout.strip()
		try:
			valid = len(base64.b64decode(signature, validate=True)) == 64
		except ValueError:
			valid = False
		if result.returncode != 0 or not valid:
			raise Failure("sign_update could not sign %s." % path)
		with open(path + ".sig", "w") as f:
			f.write(signature + "\n")
		return
	seed = seed_of(key_file)
	with tempfile.TemporaryDirectory() as folder:
		key = os.path.join(folder, "key.der")
		with open(os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as f:
			f.write(ED25519_PRIVATE_PREFIX + seed)
		result = subprocess.run([openssl(), "pkeyutl", "-sign", "-keyform", "DER", "-inkey", key, "-rawin", "-in", path],
			capture_output=True)
	if result.returncode != 0 or len(result.stdout) != 64:
		raise Failure("openssl could not sign %s." % path)
	with open(path + ".sig", "w") as f:
		f.write(base64.b64encode(result.stdout).decode() + "\n")


def verify(public_key, path):
	try:
		key = base64.b64decode(public_key, validate=True)
	except ValueError:
		key = b""
	if len(key) != 32:
		raise Failure("the public update key is not 32 bytes in Base64.")
	try:
		with open(path + ".sig") as f:
			signature = base64.b64decode(f.read().strip(), validate=True)
	except (OSError, ValueError) as error:
		raise Failure("cannot read the signature of %s: %s" % (path, error))
	if len(signature) != 64:
		raise Failure("the signature of %s is not 64 bytes." % path)
	with tempfile.TemporaryDirectory() as folder:
		files = {name: os.path.join(folder, name) for name in ("key.der", "signature")}
		for name, data in (("key.der", ED25519_PUBLIC_PREFIX + key), ("signature", signature)):
			with open(files[name], "wb") as f:
				f.write(data)
		result = subprocess.run([openssl(), "pkeyutl", "-verify", "-pubin", "-keyform", "DER", "-inkey", files["key.der"],
			"-rawin", "-in", path, "-sigfile", files["signature"]], capture_output=True)
	if result.returncode != 0:
		raise Failure("the update key did not sign %s." % path)
	if os.path.basename(path) == BANK_LIST:
		with open(path, "rb") as f:
			check_bank_list(f.read(), path)


def dry_run(out, jar=None, sign_update=None):
	"""Builds and signs with a throwaway key that exists only in a temporary folder."""
	build(out, jar)
	with tempfile.TemporaryDirectory() as folder:
		key_file = os.path.join(folder, "throwaway.key")
		with open(os.open(key_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as f:
			f.write(base64.b64encode(os.urandom(32)).decode())
		public = public_key_of(key_file)
		for name in FILES:
			path = os.path.join(out, name)
			sign(key_file, path, sign_update)
			verify(public, path)
			changed = os.path.join(folder, name)
			with open(path, "rb") as f:
				data = bytearray(f.read())
			data[len(data) // 2] ^= 0x01
			with open(changed, "wb") as f:
				f.write(data)
			shutil.copy(path + ".sig", changed + ".sig")
			try:
				verify(public, changed)
			except Failure:
				pass
			else:
				raise Failure("the check accepted %s after one changed byte." % name)
	tool = "sign_update" if sign_update else "openssl"
	print("dry run: %s signed by %s with a throwaway key %s, checked, and refused after one changed byte." % (", ".join(FILES), tool, public))


# A stable version of the app, which carries the update feed when it is the latest release.
APP_TAG = re.compile(r"v[0-9]+\.[0-9]+\.[0-9]+")


def app_releases(text):
	"""The published stable versions of the app in the pages of the list of releases that
	gh api --paginate --slurp printed. Fails unless each page is a list, each page before the last
	holds 100 releases, and each release has a string tag_name and a Boolean draft, so a page that is
	cut short or an answer of another shape never reads as a list without a version. A release marked
	as a pre-release still counts, so the list ignores the field prerelease."""
	try:
		pages = json.loads(text)
	except ValueError as error:
		raise Failure("the list of releases is not JSON: %s" % error)
	if not isinstance(pages, list) or not pages:
		raise Failure("the list of releases has no page")
	published = []
	for number, page in enumerate(pages, 1):
		if not isinstance(page, list):
			raise Failure("page %d of the list of releases is not a list" % number)
		if number < len(pages) and len(page) != 100:
			raise Failure("page %d of the list of releases holds %d releases, but each page before the last holds 100" % (number, len(page)))
		for release in page:
			if not isinstance(release, dict) or not isinstance(release.get("tag_name"), str) or not isinstance(release.get("draft"), bool):
				raise Failure("page %d of the list of releases holds a release without a string tag_name and a Boolean draft: %.200s"
					% (number, json.dumps(release)))
			if not release["draft"] and APP_TAG.fullmatch(release["tag_name"]):
				published.append(release["tag_name"])
	return published


def check_latest(repo):
	"""The feed URL of the app follows the latest release. GitHub marks the only published release as the
	latest one even when it was created with --latest=false, so ext-v0.1.0 or bank-data can be the latest
	release before the first version of the app. That is fine while no version is published: the first
	version takes the mark with --latest. GitHub leaves a release marked as a pre-release out of the
	latest release, so only the full list of releases shows that no version is published."""
	result = subprocess.run(["gh", "api", "repos/%s/releases/latest" % repo], capture_output=True, text=True)
	if result.returncode == 0:
		try:
			latest = json.loads(result.stdout).get("tag_name")
		except (ValueError, AttributeError):
			latest = None
		if not isinstance(latest, str):
			raise Failure("GitHub sent no tag for the latest release: %.200s" % result.stdout.strip())
	elif "HTTP 404" in result.stderr:
		latest = ""
	else:
		raise Failure("GitHub does not answer for the latest release: %s" % result.stderr.strip())
	if APP_TAG.fullmatch(latest):
		feed = "https://github.com/%s/releases/latest/download/appcast.xml" % repo
		if subprocess.run(["curl", "-fsSIL", "--retry", "3", "-o", os.devnull, feed]).returncode != 0:
			raise Failure("the feed URL %s does not answer." % feed)
		print("The latest release %s carries the feed." % latest)
		return
	result = subprocess.run(["gh", "api", "--paginate", "--slurp", "repos/%s/releases?per_page=100" % repo], capture_output=True, text=True)
	if result.returncode != 0:
		raise Failure("the releases of %s cannot be read: %s" % (repo, result.stderr.strip()))
	published = app_releases(result.stdout)
	if published:
		raise Failure("the latest release is %s, not a version of the app, although these versions are published: %s, so the feed URL breaks. Mark the newest version as latest."
			% (latest or "none", ", ".join(published)))
	print("No version of the app is published yet%s, so there is no feed to check." % (" (the latest release is %s)" % latest if latest else ""))


def main(argv):
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	commands = parser.add_subparsers(dest="command", required=True)
	p = commands.add_parser("build")
	p.add_argument("--out", required=True)
	p.add_argument("--jar")
	p.add_argument("--lock", default=LOCK)
	p.add_argument("--corrections", default=CORRECTIONS)
	p.add_argument("--serial")
	p = commands.add_parser("sign")
	p.add_argument("--key-file", required=True)
	p.add_argument("--sign-update")
	p.add_argument("file")
	p = commands.add_parser("verify")
	p.add_argument("--public-key", required=True)
	p.add_argument("file")
	p = commands.add_parser("check")
	p.add_argument("file")
	p = commands.add_parser("public-key")
	p.add_argument("file")
	p = commands.add_parser("dry-run")
	p.add_argument("--out", required=True)
	p.add_argument("--jar")
	p.add_argument("--sign-update")
	p = commands.add_parser("check-latest")
	p.add_argument("--repo", required=True)
	args = parser.parse_args(argv)
	try:
		if args.command == "build":
			build(args.out, args.jar, args.lock, args.corrections, args.serial)
		elif args.command == "sign":
			sign(args.key_file, args.file, args.sign_update)
		elif args.command == "verify":
			verify(args.public_key, args.file)
		elif args.command == "check":
			with open(args.file, "rb") as f:
				print("%d banks" % check_bank_list(f.read(), args.file))
		elif args.command == "public-key":
			print(public_key_of(args.file))
		elif args.command == "dry-run":
			dry_run(args.out, args.jar, args.sign_update)
		elif args.command == "check-latest":
			check_latest(args.repo)
	except Failure as error:
		print("bank-data.py: %s" % error, file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
