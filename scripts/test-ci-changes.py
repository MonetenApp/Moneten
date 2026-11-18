#!/usr/bin/env python3
"""Tests of scripts/ci-changes.py and of the path filter of release-ext.yml, run by scripts/check.sh and by the specs
job of CI."""

import contextlib
import importlib.util
import io
import json
import re
import shutil
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
# line), so that a second read on the same line still counts.
# A new line that names one fails the test, even in a file listed here: then either the file leaves the list,
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
		# A router that did not succeed runs the job through its result, even when it wrote macos=false before it
		# failed. A successful router that wrote nothing leaves the output empty, and != 'false' then runs the job.
		workflow = (ROOT / ".github/workflows/ci.yml").read_text()
		self.assertIn("if: ${{ !cancelled() && (needs.changes.result != 'success' || needs.changes.outputs.macos != 'false') }}", workflow)


RELEASE_EXT = ROOT / ".github/workflows/release-ext.yml"
# The inputs of the ext dry run besides the folders of the targets that ext builds.
EXT_INPUTS = {
	# The dry run itself, and the script that builds, packages, and checks the binary.
	".github/workflows/release-ext.yml",
	"scripts/release-ext.sh",
	# The package graph and the pinned dependencies.
	"Package.swift",
	"Package.resolved",
	# The example extension that the check of the script replays with the packaged binary.
	"Extensions/Example/**",
	"Fixtures/example/**",
}


def release_ext_filter():
	"""The paths of the pull_request trigger of release-ext.yml."""
	block = re.search(r"^  pull_request:\n    paths:\n((?:      - .+\n)+)", RELEASE_EXT.read_text(), re.M)
	return [line.strip()[2:] for line in block.group(1).splitlines()]


def dumped_package():
	"""The evaluated Package.swift as JSON from `swift package dump-package`, or None when no swift is on PATH."""
	if shutil.which("swift") is None:
		return None
	out = subprocess.run(["swift", "package", "dump-package"], cwd=ROOT, check=True, capture_output=True)
	return json.loads(out.stdout)


def ext_folders_from_dump(package):
	"""The source folders of ext and of every local target and local package that it reaches, from the evaluated
	manifest. A product of a remote package is pinned by Package.resolved. A dependency that names neither a local
	target nor a product of a known package fails, so no form of the manifest can hide a dependency."""
	targets = {t["name"]: t for t in package["targets"]}
	local = {d["fileSystem"][0]["identity"]: d["fileSystem"][0]["path"] for d in package["dependencies"] if "fileSystem" in d}
	remote = {next(iter(d.values()))[0]["identity"] for d in package["dependencies"] if "fileSystem" not in d}
	folders, seen, todo = set(), set(), ["ext"]
	while todo:
		name = todo.pop()
		if name in seen:
			continue
		seen.add(name)
		target = targets[name]
		folders.add(target.get("path") or f"Sources/{name}")
		for dependency in target["dependencies"]:
			kind, value = next(iter(dependency.items()))
			if kind in ("byName", "target") and value[0] in targets:
				todo.append(value[0])
			elif kind == "product" and value[1] in local:
				folders.add(local[value[1]])
			elif kind == "product" and value[1] in remote:
				continue
			elif kind == "byName" and remote and not local:
				# A bare name that is no local target is a product of the remote packages, which Package.resolved pins.
				continue
			else:
				raise ValueError(f"{name} depends on {dependency}, which this check cannot place")
	return folders


def ext_folders(manifest=None):
	"""The source folders of the product ext and of every target that it depends on, as Package.swift declares them.

	Each target of Package.swift stands on one line. A target whose declaration or dependency list does not close
	on its line fails the test, so a form this reader does not know never drops a dependency. A dependency on a
	product of another package is pinned by Package.resolved, so only local targets count.
	"""
	text = manifest if manifest is not None else (ROOT / "Package.swift").read_text()
	targets = {}
	start = re.compile(r"^\s*\.(?:target|executableTarget|testTarget)\(")
	declaration = re.compile(r'^\s*\.(?:target|executableTarget|testTarget)\(name: "(\w+)"(.*)$')
	for line in text.splitlines():
		if not start.match(line):
			continue
		found = declaration.match(line)
		if not found or line.count("(") != line.count(")"):
			raise ValueError(f"Package.swift declares a target that does not stand on one line: {line.strip()}")
		name, rest = found.groups()
		local = ""
		if "dependencies: [" in rest:
			begin = rest.index("dependencies: [") + len("dependencies: [")
			depth, end = 1, begin
			while end < len(rest) and depth:
				depth += {"[": 1, "]": -1}.get(rest[end], 0)
				end += 1
			if depth:
				raise ValueError(f"the dependencies of {name} do not close on their line")
			local = re.sub(r"\.product\([^)]*\)", "", rest[begin:end - 1])
		elif "dependencies:" in rest:
			raise ValueError(f"the dependencies of {name} are not a list on their line")
		path = re.search(r'path: "([^"]+)"', rest)
		targets[name] = (path.group(1) if path else f"Sources/{name}", re.findall(r'"(\w+)"', local))
	seen, todo = set(), ["ext"]
	while todo:
		name = todo.pop()
		if name not in seen:
			seen.add(name)
			todo.extend(targets[name][1])
	return {targets[name][0] for name in seen}


def script_reads(text, files):
	"""The tracked files that the lines of a script name, a path written with ./ included."""
	read = set()
	for line in text.splitlines():
		if COMMENT.match(line):
			continue
		for token in re.findall(r"[\w./${}-]+", line):
			# A path behind a variable such as $ROOT/ or ${ROOT}/, or behind ../ after a cd, counts as the
			# repository path it names, so that a hidden prefix never hides a read.
			token = re.sub(r"^(\$\{?\w+\}?/|\.{1,2}/)+", "", token).rstrip("/")
			if "$" in token:
				continue
			read |= {f for f in files if f and (f == token or f.startswith(token + "/"))}
	return read


def in_filter(patterns, path):
	"""Whether a path of a pull request starts the dry run. The filter uses exact paths and folder/** only."""
	return any(path.startswith(p[:-2]) if p.endswith("/**") else path == p for p in patterns)


class ReleaseExtFilter(unittest.TestCase):
	"""The dry run of release-ext.yml starts for every input of ext, and for nothing else."""

	def test_the_filter_names_exactly_the_inputs_of_ext(self):
		package = dumped_package()
		folders = ext_folders_from_dump(package) if package is not None else ext_folders()
		print(f"ext inputs from {'swift package dump-package' if package is not None else 'the line reader'}", file=sys.stderr)
		self.assertEqual(folders, {"Tools/ext", "Sources/Domain", "Sources/CLua", "Sources/ExtensionHost", "Sources/ExtensionConnector"})
		patterns = release_ext_filter()
		self.assertEqual(len(patterns), len(set(patterns)), "a path appears twice")
		self.assertEqual(set(patterns), {f"{folder}/**" for folder in folders} | EXT_INPUTS)
		for pattern in patterns:
			with self.subTest(pattern=pattern):
				self.assertNotRegex(pattern.removesuffix("/**"), r"[*?\[\]!+]", "in_filter knows exact paths and folder/** only")

	def test_every_file_that_the_script_reads_is_in_the_filter(self):
		files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True).stdout.decode().split("\0")
		patterns = release_ext_filter()
		read = script_reads((ROOT / "scripts/release-ext.sh").read_text(), files)
		self.assertTrue({"Tools/ext/Ext.swift", "Sources/ExtensionHost/Manifest.swift", "Fixtures/example/fixture.json"} <= read)
		self.assertEqual({path for path in read if not in_filter(patterns, path)}, set())

	def test_a_dependency_list_that_does_not_close_on_its_line_fails(self):
		manifest = (ROOT / "Package.swift").read_text()
		line = '.target(name: "ExtensionConnector", dependencies: ["Domain", "ExtensionHost"]),'
		self.assertIn(line, manifest)
		several = manifest.replace(line, '.target(name: "ExtensionConnector", dependencies: [\n\t\t\t"Domain", "ExtensionHost", "Sync",\n\t\t]),')
		with self.assertRaises(ValueError):
			ext_folders(several)

	def test_a_nested_list_keeps_the_dependencies_after_it(self):
		manifest = (ROOT / "Package.swift").read_text()
		line = '.target(name: "ExtensionConnector", dependencies: ["Domain", "ExtensionHost"]),'
		nested = manifest.replace(line, '.target(name: "ExtensionConnector", dependencies: [.target(name: "Domain", condition: .when(platforms: [.macOS])), "ExtensionHost", "Sync"]),')
		self.assertIn("Sources/Sync", ext_folders(nested))

	def test_the_evaluated_manifest_gives_the_same_inputs_as_the_line_reader(self):
		package = dumped_package()
		if package is None:
			self.skipTest("no swift on PATH")
		self.assertEqual(ext_folders_from_dump(package), ext_folders())

	def test_the_evaluated_manifest_follows_any_form_of_a_dependency(self):
		package = {
			"dependencies": [],
			"targets": [
				{"name": "ext", "path": "Tools/ext", "dependencies": [{"byName": ["Domain", None]}, {"target": ["Sync", None]}]},
				{"name": "Domain", "path": None, "dependencies": []},
				{"name": "Sync", "path": None, "dependencies": [{"byName": ["Domain", None]}]},
			],
		}
		self.assertEqual(ext_folders_from_dump(package), {"Tools/ext", "Sources/Domain", "Sources/Sync"})
		package["dependencies"] = [{"fileSystem": [{"identity": "kit", "path": "Packages/Kit"}]}]
		package["targets"][0]["dependencies"].append({"product": ["Kit", "kit", None, None]})
		self.assertEqual(ext_folders_from_dump(package), {"Tools/ext", "Sources/Domain", "Sources/Sync", "Packages/Kit"})
		# With a local package, a bare name that is no local target could come from it, so it fails.
		package["targets"][2]["dependencies"].append({"byName": ["Kit", None]})
		with self.assertRaises(ValueError):
			ext_folders_from_dump(package)

	def test_a_path_behind_a_variable_or_a_parent_folder_counts_as_read(self):
		files = ["Sources/Sync/SyncCoordinator.swift"]
		for line in ['cat "$ROOT/Sources/Sync/SyncCoordinator.swift"', "cat ${ROOT}/Sources/Sync/SyncCoordinator.swift",
				"cd Tools && cat ../Sources/Sync/SyncCoordinator.swift"]:
			with self.subTest(line=line):
				self.assertEqual(script_reads(line, files), {"Sources/Sync/SyncCoordinator.swift"})

	def test_a_path_written_with_dot_slash_counts_as_read(self):
		files = ["Sources/Sync/SyncCoordinator.swift", "Sources/Domain/Money.swift"]
		self.assertEqual(script_reads("cat ./Sources/Sync/SyncCoordinator.swift", files), {"Sources/Sync/SyncCoordinator.swift"})
		self.assertEqual(script_reads("cat Sources/Sync/SyncCoordinator.swift", files), {"Sources/Sync/SyncCoordinator.swift"})

	def test_a_change_outside_the_inputs_skips(self):
		patterns = release_ext_filter()
		for path in ["Sources/Storage/Vault.swift", "Sources/FinTS/FinTSConnector.swift", "Sources/ExtensionCatalog/Installer.swift",
				"Sources/MonetenExtensionHost/main.swift", "Sources/Sync/SyncCoordinator.swift", "App/Sources/AppModel.swift",
				"Tests/ExtToolTests/CommandTests.swift", "Fixtures/extensions/monzo/Monzo.lua", "docs/releasing-ext.md",
				"scripts/release.sh", ".github/workflows/ci.yml", "Tools/FinTSHelper/build.gradle"]:
			with self.subTest(path=path):
				self.assertFalse(in_filter(patterns, path))

	def test_a_change_to_an_input_runs(self):
		patterns = release_ext_filter()
		for path in ["Tools/ext/Ext.swift", "Sources/ExtensionHost/Manifest.swift", "Sources/Domain/Money.swift", "Sources/CLua/lvm.c",
				"Sources/ExtensionConnector/ExtensionConnector.swift", "Package.swift", "Package.resolved", "scripts/release-ext.sh",
				".github/workflows/release-ext.yml", "Extensions/Example/Example.lua", "Fixtures/example/expected.json"]:
			with self.subTest(path=path):
				self.assertTrue(in_filter(patterns, path))


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
