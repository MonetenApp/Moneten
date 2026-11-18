#!/usr/bin/env python3
"""Tests of scripts/ci-changes.py, run by scripts/check.sh and by the specs job of CI."""

import contextlib
import importlib.util
import io
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/ci-changes.py"
spec = importlib.util.spec_from_file_location("ci_changes", SCRIPT)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

# The code that the macOS job builds or runs. The scripts that only the specs job or a person runs
# may read the docs, because the specs job runs on every pull request.
CONSUMERS = ["Tests", "Sources", "App", "Tools", "scripts", "Package.swift", ".github/workflows/ci.yml"]
UBUNTU_ONLY = ["scripts/check-docs.py", "scripts/check-ui.py", "scripts/roadmap.py", "scripts/ci-changes.py", "scripts/test-ci-changes.py"]

# Lines outside comments that name a file on the list but do not read it, as (file, listed path, part of the
# line), so that a second read on the same line still counts. A
# new line that names one fails the test, even in a file listed here: then either the file leaves the list,
# or the line goes here with its reason.
MENTIONS = {
	# A README.md inside an extension package, not the one of the repository.
	("App/Sources/PerfCheck.swift", "README.md", '"README.md", "manifest.json"].map'),
	("Tests/ExtensionCatalogTests/FileInstallTests.swift", "README.md", '"README.md": "# Broker'),
	("Tests/ExtensionCatalogTests/InstallerTests.swift", "README.md", '"LICENSE", "README.md", "manifest.json"])'),
	("Tests/ExtensionCatalogTests/Support.swift", "README.md", '"README.md": Data("# Example Bank'),
	# Error messages that send the reader to the page.
	("scripts/build-app.sh", "docs/releasing.md", 'private key in the Keychain. See docs/releasing.md."'),
	("scripts/release.sh", "docs/releasing.md", 'docs/releasing.md explains how the owner adds it."'),
	("scripts/release.sh", "docs/releasing.md", 'no FinTS product ID. See docs/releasing.md."'),
	("scripts/release.sh", "docs/releasing.md", 'publish by hand as docs/releasing.md describes."'),
	("scripts/check-localization.py", "CONTRIBUTING.md", 'CONTRIBUTING.md explains it.")'),
}

# A comment line of Swift, Java, Lua, YAML, and the scripts. "#expect(" in Swift is code.
COMMENT = re.compile(r"^\s*(//|#(\s|!|$)|\*|/\*|--)")
TOKEN = re.compile(r"[\w./-]+")


def docs():
	files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True).stdout.decode().split("\0")
	return {path for path in files if path and ci.is_doc(path)}


def references(listed):
	"""Yield (file, path, line) for each line outside comments that names a listed file or a folder of one.

	The scan reads paths as they are written. It misses a path that code joins from parts, a shell continuation
	line that starts with -- or *, which it takes for a comment, and code that walks a whole folder tree.
	"""
	pattern = "|".join(["docs", "openspec", "ISSUE_TEMPLATE"] + [re.escape(name) for name in ci.DOC_FILES])
	out = subprocess.run(["git", "grep", "-n", "-I", "-E", pattern, "--", *CONSUMERS] + [f":!{path}" for path in UBUNTU_ONLY],
		cwd=ROOT, capture_output=True).stdout.decode()
	folders = {str(parent) for path in listed for parent in Path(path).parents if str(parent) != "."}
	for line in out.splitlines():
		file, _, text = line.split(":", 2)
		if COMMENT.match(text):
			continue
		for token in TOKEN.findall(text):
			path = re.sub(r"^(\.{1,2}/)+", "", token).rstrip("./")
			# A folder counts only as a path, such as docs/ or openspec/changes, not as the word "docs".
			if path in listed or (path in folders and "/" in token):
				yield file, path, text


class Routing(unittest.TestCase):
	def test_docs_only_skips(self):
		self.assertFalse(ci.needs_macos(["README.md", "docs/vision.md", "docs/decisions/0001-record-architecture-decisions.md",
			"openspec/changes/add-budgets/proposal.md", "openspec/config.yaml", ".github/ISSUE_TEMPLATE/bug-report.yml"]))

	def test_swift_runs(self):
		self.assertTrue(ci.needs_macos(["Sources/Domain/Ledger.swift"]))
		self.assertTrue(ci.needs_macos(["README.md", "App/Sources/AppModel.swift"]))

	def test_doc_that_a_test_reads_runs(self):
		self.assertTrue(ci.needs_macos(["docs/export-format.md"]))

	def test_unknown_path_runs(self):
		for path in ["unknown.md", "docs/diagram.png", "docs/run.sh", "openspec/specs/.gitkeep", "Fixtures/example/README.md",
				"Tools/FinTSHelper/README.md", "CHANGELOG.md", "LICENSE", ".github/pull_request_template.md"]:
			with self.subTest(path=path):
				self.assertTrue(ci.needs_macos([path]))

	def test_workflow_runs(self):
		self.assertTrue(ci.needs_macos([".github/workflows/ci.yml"]))
		self.assertTrue(ci.needs_macos([".github/workflows/release.yml"]))

	def test_empty_diff_runs(self):
		self.assertTrue(ci.needs_macos([]))

	def test_events(self):
		def run(*args):
			out = subprocess.run([sys.executable, str(SCRIPT), *args], cwd=ROOT, capture_output=True, text=True)
			self.assertEqual(out.returncode, 0, out.stderr)
			return out.stdout.strip()
		self.assertEqual(run("push"), "macos=true")
		self.assertEqual(run("workflow_dispatch"), "macos=true")
		# A diff that git cannot compute runs everything.
		self.assertEqual(run("pull_request", "0" * 40, "HEAD"), "macos=true")
		self.assertEqual(run("pull_request"), "macos=true")


def known_by(mention, item):
	"""Whether a found (file, path, line) is the mention (file, path, part of the line)."""
	(f, p, part), (file, path, text) = mention, item
	return (file, path) == (f, p) and part in text


class Readers(unittest.TestCase):
	def test_nothing_in_the_macos_job_reads_a_listed_doc(self):
		listed = docs()
		self.assertIn("README.md", listed)
		self.assertIn("openspec/config.yaml", listed)
		self.assertNotIn("docs/export-format.md", listed)
		found = set(references(listed))
		unknown = {(file, path) for file, path, text in found if not any(known_by(m, (file, path, text)) for m in MENTIONS)}
		self.assertEqual(unknown, set(), "a file on the list is read by the macOS job: drop it from the list in ci-changes.py")
		gone = {mention for mention in MENTIONS if not any(known_by(mention, item) for item in found)}
		self.assertEqual(gone, set(), "a mention is gone: remove it from MENTIONS")

	def test_the_scan_finds_a_reader(self):
		# The test of the export format reads its page. Without READ_BY_TESTS the scan must name it.
		listed = docs() | {"docs/export-format.md"}
		self.assertIn(("Tests/StorageTests/AllDataTests.swift", "docs/export-format.md"), {(f, p) for f, p, _ in references(listed)})


class Failures(unittest.TestCase):
	def test_a_failed_router_runs_everything(self):
		def broken(argv):
			raise RuntimeError("probe")
		saved, ci.decide = ci.decide, broken
		try:
			out = io.StringIO()
			with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
				ci.main(["ci-changes.py", "pull_request", "a", "b"])
		finally:
			ci.decide = saved
		self.assertEqual(out.getvalue().strip(), "macos=true")

	def test_the_macos_job_skips_only_on_an_explicit_docs_only_decision(self):
		# A failed, cancelled, or silent router leaves the output empty, and != 'false' then runs the job.
		workflow = (ROOT / ".github/workflows/ci.yml").read_text()
		self.assertIn("if: ${{ !cancelled() && (needs.changes.result != 'success' || needs.changes.outputs.macos != 'false') }}", workflow)


class Diff(unittest.TestCase):
	"""The router on a real repository: renames, deletions, odd names, and a name that is not UTF-8."""

	def setUp(self):
		self.dir = tempfile.TemporaryDirectory()
		self.repo = Path(self.dir.name)
		self.git("init", "-q", "-b", "main")
		self.git("config", "user.email", "ci@example.invalid")
		self.git("config", "user.name", "CI")
		for name in ["docs/old.md", "docs/gone.md", "README.md", "Sources/notes.md"]:
			(self.repo / name).parent.mkdir(parents=True, exist_ok=True)
			(self.repo / name).write_text("text\n")
		self.git("add", "-A")
		self.git("commit", "-q", "-m", "base")
		self.git("checkout", "-q", "-b", "change")

	def tearDown(self):
		self.dir.cleanup()

	def git(self, *args):
		subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)

	def route(self):
		self.git("add", "-A")
		self.git("commit", "-q", "-m", "change")
		out = subprocess.run([sys.executable, str(SCRIPT), "pull_request", "main", "HEAD"], cwd=self.repo,
			capture_output=True, text=True)
		self.assertEqual(out.returncode, 0, out.stderr)
		return out.stdout.strip()

	def test_a_rename_and_a_deletion_of_docs_skip(self):
		self.git("mv", "docs/old.md", "docs/new.md")
		self.git("rm", "-q", "docs/gone.md")
		self.assertEqual(self.route(), "macos=false")

	def test_a_doc_renamed_out_of_the_docs_runs(self):
		self.git("mv", "docs/old.md", "Sources/old.md")
		self.assertEqual(self.route(), "macos=true")

	def test_a_file_renamed_into_the_docs_runs(self):
		# Without --no-renames, git would name only the new path, docs/notes.md, and the router would skip.
		self.git("mv", "Sources/notes.md", "docs/notes.md")
		self.assertEqual(self.route(), "macos=true")

	def test_an_odd_name_in_the_docs_skips(self):
		(self.repo / "docs/a b\nc.md").write_text("text\n")
		self.assertEqual(self.route(), "macos=false")

	def test_a_name_that_is_not_utf8_runs(self):
		# APFS refuses such a name on disk, so the name goes into the index only.
		blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.repo, input=b"text\n", check=True,
			capture_output=True).stdout.decode().strip()
		subprocess.run([b"git", b"update-index", b"--add", b"--cacheinfo", f"100644,{blob},".encode() + b"docs/x\xff.md"],
			cwd=self.repo, check=True, capture_output=True)
		self.git("commit", "-q", "-m", "change")
		out = subprocess.run([sys.executable, str(SCRIPT), "pull_request", "main", "HEAD"], cwd=self.repo, capture_output=True, text=True)
		self.assertEqual(out.returncode, 0, out.stderr)
		self.assertEqual(out.stdout.strip(), "macos=true")


if __name__ == "__main__":
	unittest.main()
