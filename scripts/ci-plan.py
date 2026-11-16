#!/usr/bin/env python3
"""Print the checks selected by a CI event and its changed paths."""
import argparse
import json


# Only allowed docs skip macOS. Ubuntu-only docs checks still run; macOS-consumed inputs run the full plan.
MACOS_INPUTS = ("docs/export-format.md", "Fixtures/", "Extensions/")
DOC_FILES = {"README.md", "CLAUDE.md", "CONTRIBUTING.md"}
DOC_FOLDERS = {
    "docs/": (".md", ".txt"),
    "openspec/": (".md", ".yaml", ".yml"),
    ".github/ISSUE_TEMPLATE/": (".md", ".yaml", ".yml"),
}


def plan(event, paths):
    docs_only = bool(paths) and all(
        (p in DOC_FILES or any(p.startswith(folder) and p.endswith(suffixes) for folder, suffixes in DOC_FOLDERS.items()))
        and not any(p == source or source.endswith("/") and p.startswith(source) for source in MACOS_INPUTS)
        for p in paths
    )
    run = event != "pull_request" or not docs_only
    return dict(macos=run, app=run, periphery=run)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("event", choices=["pull_request", "push", "workflow_dispatch"])
    args = parser.parse_args()
    import sys
    print(json.dumps(plan(args.event, sys.stdin.buffer.read().decode().split("\0")[:-1])))
