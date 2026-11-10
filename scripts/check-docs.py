#!/usr/bin/env python3
"""Checks that the documentation points at things that exist.

- Every relative Markdown link resolves to a file, and its #anchor to a heading.
- Every path in code font exists, read from the repository root or from the folder of the doc,
  or git ignores it.
- Every folder and file in a layout tree that starts with "MonetenMoneten/" exists.
- Every name in code font in docs/data-model.md, above its section on later types, is declared
  in Sources/ or is a table of the database.
- The status in each ADR file matches the index table in docs/decisions/README.md.

Proposals and specs describe planned work and may name folders that do not exist yet, and the
OpenSpec tool files under .claude/ are generated, so the path checks skip them.

Prints one line per problem and exits with 1 when there is any.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP = {p.name for p in ROOT.iterdir()} - {".git", ".build", "dist"}
PLANNED = re.compile(r"^(\.claude/|openspec/changes/[^/]+/(proposal\.md|specs/))")
BUILTIN = {"Bool", "Int", "Int64", "String", "Double", "Decimal", "Date", "UUID", "UserDefaults", "nil"}
files = [ROOT / f for f in subprocess.run(["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()]
problems = []


def outside_fences(text):
	"""Yields (line number, line) for every line that is not inside a fenced code block."""
	in_fence = False
	for n, line in enumerate(text.splitlines(), 1):
		if line.lstrip().startswith("```"):
			in_fence = not in_fence
		elif not in_fence:
			yield n, line


def anchors(path):
	"""The anchors that GitHub generates for the headings of a file."""
	seen = {}
	for _, line in outside_fences(path.read_text()):
		m = re.match(r"#+\s+(.*)$", line)
		if not m:
			continue
		base = re.sub(r"[^\w\- ]", "", re.sub(r"[`*]", "", m.group(1).strip().lower())).replace(" ", "-")
		count = seen.get(base, 0)
		seen[base] = count + 1
		yield base if count == 0 else f"{base}-{count}"


def path_exists(md, path):
	"""A path exists, or git ignores it, as for a local file such as App/Local.xcconfig that each developer creates."""
	if (ROOT / path).exists() or (md.parent / path).exists():
		return True
	return subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT).returncode == 0


def check_links_and_paths(md, rel):
	check_paths = not PLANNED.match(str(rel))
	for n, line in outside_fences(md.read_text()):
		for target in re.findall(r"\]\(([^)\s]+)\)", line):
			if re.match(r"[a-z]+:", target):
				continue
			file_part, _, anchor = target.partition("#")
			dest = (md.parent / file_part).resolve() if file_part else md
			if not dest.exists():
				problems.append(f"{rel}:{n}: link to missing file {target}")
			elif anchor and dest.suffix == ".md" and anchor not in set(anchors(dest)):
				problems.append(f"{rel}:{n}: link to missing heading {target}")
		if not check_paths:
			continue
		for code in re.findall(r"`([^`\s]+)`", line):
			looks_like_path = code.split("/")[0] in TOP or code.endswith("/") or re.search(r"/[\w.-]+\.(swift|md|sh|py|yml|plist|json)$", code)
			if "/" in code and looks_like_path and not re.match(r"[~/]|[a-z]+:", code) and not re.search(r"[<>*{}$]", code):
				if not path_exists(md, code.rstrip("/")):
					problems.append(f"{rel}:{n}: path in code font does not exist: {code}")


def check_layout_trees(md, rel):
	"""Checks trees such as "MonetenMoneten/", "├── Sources/", "│   ├── Domain/"."""
	lines = md.read_text().splitlines()
	for start, line in enumerate(lines):
		if line.strip() != "MonetenMoneten/":
			continue
		stack = []
		for n in range(start + 1, len(lines)):
			m = re.match(r"^([│ ]*)[├└]── (\S+)", lines[n])
			if not m:
				break
			depth = len(m.group(1)) // 4
			stack = stack[:depth] + [m.group(2).rstrip("/")]
			if not (ROOT / "/".join(stack)).exists():
				problems.append(f"{rel}:{n + 1}: layout tree names a missing path: {'/'.join(stack)}")


def check_data_model():
	source = "\n".join(p.read_text() for p in (ROOT / "Sources").rglob("*.swift"))
	declared = set(re.findall(r"\b(?:struct|enum|class|protocol|typealias)\s+(\w+)", source))
	declared |= set(re.findall(r"\b(?:var|let|func)\s+(\w+)", source))
	for cases in re.findall(r"\bcase\s+([\w, ]+)", source):
		declared |= {c.strip() for c in cases.split(",")}
	declared |= set(re.findall(r'(?:table:\s*|databaseTableName\s*=\s*|registerMigration\()"(\w+)"', source))
	declared |= {p.name for p in (ROOT / "Sources").iterdir()}
	rel = "docs/data-model.md"
	for n, line in outside_fences((ROOT / rel).read_text()):
		if line.startswith("## Types that the specs add later"):
			break
		for code in re.findall(r"`([^`]+)`", line):
			for name in re.findall(r"^(\w+)\??(?::\s.*)?$|^(\w+)\.\w+\(", code):
				name = name[0] or name[1]
				if name and name not in declared and name not in BUILTIN:
					problems.append(f"{rel}:{n}: {name} is not declared in Sources/")


def check_adr_index():
	index = (ROOT / "docs/decisions/README.md").read_text()
	for adr in sorted((ROOT / "docs/decisions").glob("0*.md")):
		status = re.search(r"^Status:\s*(\S+)", adr.read_text(), re.M)
		row = re.search(rf"\[{adr.name[:4]}\]\({re.escape(adr.name)}\)\s*\|[^|]*\|\s*([^|\s]+)", index)
		if not status or not row or status.group(1) != row.group(1):
			problems.append(f"docs/decisions/{adr.name}: status {status and status.group(1)} differs from the index ({row and row.group(1)})")


for md in files:
	rel = md.relative_to(ROOT)
	check_links_and_paths(md, rel)
	check_layout_trees(md, rel)
check_data_model()
check_adr_index()

print("\n".join(problems) or "Documentation check passed.")
sys.exit(1 if problems else 0)
