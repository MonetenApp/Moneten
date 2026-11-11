#!/usr/bin/env python3
"""Fails when app code replaces the Liquid Glass of the window chrome, see ADR 0012.

The sidebar, the toolbar, and the window frame use the materials of macOS. MoneyMoney parity
applies to the content, not to these surfaces. A line may break a rule only with a comment
`// chrome-ok: <reason>` on the same line.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "App" / "Sources"
# The debug harness draws offscreen snapshots and is never window chrome.
SKIP = {"DebugHarness.swift"}

# Anywhere in the app: APIs that override the system chrome.
GLOBAL = [
    (re.compile(r"\.toolbarBackground(Visibility)?\("), "the toolbar keeps its system glass"),
    (re.compile(r"\bNSVisualEffectView\b"), "use the system materials, not a hand-made effect view"),
    (re.compile(r"titlebarAppearsTransparent"), "the title bar keeps its system look"),
    (re.compile(r"\b(window|NSWindow)\w*\.backgroundColor\s*="), "the window keeps its system background"),
    (re.compile(r"\.containerBackground\("), "the window keeps its system background"),
]
# In files that build the sidebar or the split view: no opaque fill behind the sidebar.
CHROME_FILE = re.compile(r"\.listStyle\(\.sidebar\)|NavigationSplitView")
IN_CHROME = [
    (re.compile(r"\.scrollContentBackground\(\.hidden\)"), "the sidebar keeps its glass material"),
    (re.compile(r"\.background\(\s*(Palette\.|Color\b|Color\(|\.(ultraThin|thin|regular|thick|ultraThick|bar)Material|\.windowBackground|\.black|\.white|\.gray)"),
        "no opaque or custom fill behind the sidebar or the split view"),
    (re.compile(r"\.listRowBackground\("), "sidebar rows keep the system selection and background"),
]


def main() -> int:
    problems = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name in SKIP:
            continue
        text = path.read_text(encoding="utf-8")
        rules = GLOBAL + (IN_CHROME if CHROME_FILE.search(text) else [])
        for number, line in enumerate(text.splitlines(), 1):
            if "chrome-ok:" in line:
                continue
            for pattern, why in rules:
                if pattern.search(line):
                    problems.append(f"{path.relative_to(ROOT)}:{number}: {why} (ADR 0012): {line.strip()}")
    for p in problems:
        print(p)
    if problems:
        print(f"\n{len(problems)} chrome rule(s) broken. See docs/decisions/0012-system-glass-for-window-chrome.md.")
        return 1
    print("check-ui: window chrome keeps the system glass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
