#!/usr/bin/env python3
"""Decide whether a CI run needs the macOS job, from the paths that a pull request changes.

The macOS job takes one of the few macOS runners of the organization for about half an hour. A pull
request that changes only documentation skips it. The specs job on Ubuntu still runs and checks the
links and paths of the docs and the specs. Every other path runs everything: a path that is not on
the list below, an empty diff, a push to main, a manual run, and a diff that git cannot compute.

Usage: ci-changes.py EVENT [BASE HEAD]. It prints macos=true or macos=false for $GITHUB_OUTPUT.
scripts/test-ci-changes.py checks that no test, script, or app code reads a file on the list.
"""

import subprocess
import sys

# Documentation that nothing in the macOS job reads. CHANGELOG.md, LICENSE, the pull request
# template, and the workflows are not on the list: scripts and the app read them, or they change CI.
DOC_FILES = {"README.md", "CLAUDE.md", "CONTRIBUTING.md", "SECURITY.md"}
DOC_FOLDERS = {
	"docs/": (".md",),
	"openspec/": (".md", ".yaml"),
	".github/ISSUE_TEMPLATE/": (".yml",),
}
# Documentation that a test reads. AllDataTests checks that this page describes every key of an export.
READ_BY_TESTS = {"docs/export-format.md"}


def is_doc(path):
	if path in READ_BY_TESTS:
		return False
	if path in DOC_FILES:
		return True
	return any(path.startswith(folder) and path.endswith(suffixes) for folder, suffixes in DOC_FOLDERS.items())


def needs_macos(paths):
	"""An empty list runs everything, so a diff that went wrong never skips the tests."""
	return not paths or not all(is_doc(path) for path in paths)


def changed_paths(base, head):
	# Without renames, a moved file counts with its old and its new path.
	out = subprocess.run(["git", "diff", "--no-renames", "--name-only", "-z", f"{base}...{head}"],
		check=True, capture_output=True).stdout
	return [p for p in out.decode().split("\0") if p]


def main(argv):
	event = argv[1] if len(argv) > 1 else ""
	if event != "pull_request":
		run = True
	else:
		try:
			paths = changed_paths(argv[2], argv[3])
		except (IndexError, subprocess.CalledProcessError) as error:
			print(f"No diff ({error}), so every job runs.", file=sys.stderr)
			paths = []
		for path in paths:
			print(f"{'docs ' if is_doc(path) else 'other'} {path}", file=sys.stderr)
		run = needs_macos(paths)
	print(f"macos={'true' if run else 'false'}")


if __name__ == "__main__":
	main(sys.argv)
