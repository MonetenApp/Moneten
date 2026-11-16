#!/usr/bin/env python3
"""Print the checks selected by a CI event and its changed paths."""
import argparse
import json


def plan(event, paths):
    full = event != "pull_request" or not paths
    docs_only = bool(paths) and all(
        p.startswith(("docs/", "openspec/", ".github/ISSUE_TEMPLATE/")) or p.endswith(".md")
        for p in paths
    )
    return {
        "macos": full or not docs_only,
        "app": full or (not docs_only and any(
            p.startswith(("App/", "Sources/", "scripts/", ".github/workflows/", ".github/actions/"))
            for p in paths
        )),
        "periphery": full or (not docs_only and any(p.endswith(".swift") for p in paths)),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("event", choices=["pull_request", "push", "workflow_dispatch"])
    args = parser.parse_args()
    import sys
    print(json.dumps(plan(args.event, sys.stdin.buffer.read().decode().split("\0")[:-1])))
