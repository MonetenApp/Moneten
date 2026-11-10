#!/usr/bin/env python3
"""Checks that the documentation points at things that exist.

- Every relative Markdown link resolves to a file, and its #anchor to a heading.
- Every path in code font that starts with a top-level folder of the repository exists.
  Proposals and specs describe planned work and may name folders that do not exist yet,
  and the OpenSpec tool files under .claude/ are generated, so the path check skips them.
- The status in each ADR file matches the index table in docs/decisions/README.md.

Prints one line per problem and exits with 1 when there is any.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOP = {p.name for p in ROOT.iterdir() if not p.name.startswith(".")} | {".github"}
files = [ROOT / f for f in subprocess.run(["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()]
problems = []


def slug(heading):
    s = re.sub(r"[`*_]", "", heading.strip().lower())
    s = re.sub(r"[^\w\- ]", "", s)
    return s.replace(" ", "-")


def anchors(path):
    return {slug(m.group(1)) for m in re.finditer(r"^#+\s+(.*)$", path.read_text(), re.M)}


PLANNED = re.compile(r"^(\.claude/|openspec/changes/[^/]+/(proposal\.md|specs/))")

for md in files:
    text = md.read_text()
    rel = md.relative_to(ROOT)
    check_paths = not PLANNED.match(str(rel))
    in_fence = False
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for target in re.findall(r"\]\(([^)\s]+)\)", line):
            if re.match(r"[a-z]+:", target):
                continue
            file_part, _, anchor = target.partition("#")
            dest = (md.parent / file_part).resolve() if file_part else md
            if not dest.exists():
                problems.append(f"{rel}:{n}: link to missing file {target}")
            elif anchor and dest.suffix == ".md" and anchor not in anchors(dest):
                problems.append(f"{rel}:{n}: link to missing heading {target}")
        for code in re.findall(r"`([^`\s]+)`", line):
            looks_like_path = code.split("/")[0] in TOP or code.endswith("/") or re.search(r"/[\w.-]+\.(swift|md|sh|py|yml|plist|json)$", code)
            if check_paths and "/" in code and looks_like_path and not re.match(r"[~/.]|[a-z]+:", code) and not re.search(r"[<>*{}$]", code):
                if not (ROOT / code.rstrip("/")).exists():
                    problems.append(f"{rel}:{n}: path in code font does not exist: {code}")

index = (ROOT / "docs/decisions/README.md").read_text()
for adr in sorted((ROOT / "docs/decisions").glob("0*.md")):
    status = re.search(r"^Status:\s*(\S+)", adr.read_text(), re.M)
    row = re.search(rf"\[{adr.name[:4]}\]\({re.escape(adr.name)}\)\s*\|[^|]*\|\s*([^|\s]+)", index)
    if not status or not row or status.group(1) != row.group(1):
        problems.append(f"docs/decisions/{adr.name}: status {status and status.group(1)} differs from the index ({row and row.group(1)})")

print("\n".join(problems) or "Documentation check passed.")
sys.exit(1 if problems else 0)
