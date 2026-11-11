#!/usr/bin/env python3
"""Fails when app code replaces the system materials of the window chrome, see ADR 0012.

The sidebar, the toolbar, and the window frame use the materials of macOS. MoneyMoney parity
applies to the content, not to these surfaces. A modifier may break a rule only with a comment
`// chrome-ok: <reason>` on the line where it starts.

The check reads source text, not the view tree. It handles a modifier split over several lines
and the closure form `.background { ... }`, and it tests itself on the cases below on every run.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "App" / "Sources"
# The debug harness draws offscreen snapshots and is never window chrome.
SKIP = {"DebugHarness.swift"}

GLOBAL = [
    (re.compile(r"\.toolbarBackground(Visibility)?\s*\("), "the toolbar keeps its system material"),
    (re.compile(r"\.toolbarColorScheme\s*\("), "the toolbar keeps its system material"),
    (re.compile(r"\bNSVisualEffectView\b"), "use the system materials, not a hand-made effect view"),
    (re.compile(r"titlebarAppearsTransparent"), "the title bar keeps its system look"),
    (re.compile(r"\.windowStyle\s*\(\s*\.hiddenTitleBar"), "the title bar keeps its system look"),
    (re.compile(r"\b\w*[wW]indows?\b[\w?!.\[\]]*\.backgroundColor\s*="), "the window keeps its system background"),
    (re.compile(r"\.containerBackground\s*\("), "the window keeps its system background"),
]
CHROME_FILE = re.compile(r"\.listStyle\(\.sidebar\)|NavigationSplitView")
IN_CHROME = [
    (re.compile(r"\.scrollContentBackground\s*\(\s*\.hidden"), "the sidebar keeps its system material"),
    (re.compile(r"\.listRowBackground\s*\("), "sidebar rows keep the system selection and background"),
]
# The content of a `.background(...)` or `.background { ... }` that fills with a color or a material.
FILL = re.compile(r"^\s*(Palette\.|Color\b|\.(ultraThin|thin|regular|thick|ultraThick|bar)Material|\.windowBackground|\.(black|white|gray)\b)"
    r"|\.fill\(\s*(Palette\.|Color\b)")
BACKGROUND = re.compile(r"\.background\s*([({])")


def argument(text: str, start: int, opener: str) -> str:
    """The text inside the brackets that open at `start`, across lines."""
    closer = {"(": ")", "{": "}"}[opener]
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return text[start + 1:]


def exempt(lines: list[str], number: int) -> bool:
    return bool(re.search(r"chrome-ok:\s*\S", lines[number - 1]))


def problems(text: str, name: str) -> list[str]:
    lines = text.splitlines()
    found = []
    chrome = bool(CHROME_FILE.search(text))
    for pattern, why in GLOBAL + (IN_CHROME if chrome else []):
        for m in pattern.finditer(text):
            number = text.count("\n", 0, m.start()) + 1
            if not exempt(lines, number):
                found.append(f"{name}:{number}: {why} (ADR 0012): {lines[number - 1].strip()}")
    if chrome:
        for m in BACKGROUND.finditer(text):
            number = text.count("\n", 0, m.start()) + 1
            if FILL.search(argument(text, m.start(1), m.group(1))) and not exempt(lines, number):
                found.append(f"{name}:{number}: no color or material behind the sidebar or the split view (ADR 0012): {lines[number - 1].strip()}")
    return found


def self_test() -> list[str]:
    sidebar = "List {}\n.listStyle(.sidebar)\n"
    forbidden = [
        sidebar + ".scrollContentBackground(.hidden)",
        sidebar + ".background(Palette.sidebar)",
        sidebar + ".background(\n    Palette.sidebar\n)",
        sidebar + ".background { Color.gray }",
        sidebar + ".background(Capsule().fill(Palette.sidebar))",
        sidebar + ".background(.thinMaterial)",
        "window?.backgroundColor = .gray",
        "NSApp.windows.first?.backgroundColor = .gray",
        ".toolbarBackground(.visible, for: .windowToolbar)",
        sidebar + ".background(Palette.sidebar) // chrome-ok:",
    ]
    allowed = [
        sidebar + ".background(Capsule().fill(.tint))",
        sidebar + ".background(.primary.opacity(0.08), in: Circle())",
        sidebar + ".background(Palette.sidebar) // chrome-ok: offscreen preview",
        "Form {}\n.scrollContentBackground(.hidden)",
        "Text(\"x\").background(Palette.band)",
    ]
    failures = [f"not caught: {c!r}" for c in forbidden if not problems(c, "case")]
    failures += [f"wrongly caught: {c!r}" for c in allowed if problems(c, "case")]
    return failures


def main() -> int:
    failures = self_test()
    if failures:
        print("check-ui self-test failed:\n" + "\n".join(failures))
        return 1
    found = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name not in SKIP:
            found += problems(path.read_text(encoding="utf-8"), str(path.relative_to(ROOT)))
    for p in found:
        print(p)
    if found:
        print(f"\n{len(found)} chrome rule(s) broken. See docs/decisions/0012-system-glass-for-window-chrome.md.")
        return 1
    print("check-ui: the window chrome keeps the system materials")
    return 0


if __name__ == "__main__":
    sys.exit(main())
