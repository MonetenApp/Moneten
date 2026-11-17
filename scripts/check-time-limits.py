#!/usr/bin/env python3
"""Fails on an upper time limit in a test that bypasses budget(_:) of Tests/TestSupport (issue #372).

A comparison is an upper time limit when its limit side is a constant and its other side is a time. A constant is a
number, or arithmetic of duration literals with literal arguments such as `.milliseconds(300)`. The comparison may
point either way: `elapsed < .seconds(1)` and `.seconds(1) > elapsed` are the same limit. A side compared with a
duration literal is always a time. A side compared with a number is a time when it measures one, as in
`elapsed / .milliseconds(1) < 5` or `.nanoseconds(ticks)`, when its name says so, as in `milliseconds`, `slept`, or
`secondsToTermination(...)`, or when the file declares it as a `TimeInterval` or a `Duration`.

The check passes a comparison with `budget(`, a lower bound such as `elapsed >= .seconds(5)`, which a slow runner
never fails, and a wait on a deadline such as `ContinuousClock.now < deadline`, which compares two times. It skips
strings and comments. It reads each line, and the whole argument of `#expect(` and `#require(` across lines. A limit
with its own room for a slow runner carries `// time-ok: <reason>` on its line, or on any line of its `#expect(`.

The check is a lint, not a proof. Known gaps, which review catches:
- A limit held in a variable, such as `elapsed < limit` or `.seconds(grace)`, passes, whatever its name.
- A comparison split over lines outside `#expect(` and `#require(` passes.
- XCTest asserts such as `XCTAssertLessThan` pass. The project uses Swift Testing only.

With file arguments the check reads those files instead of Tests/. scripts/test-check-time-limits.py runs it on
the probes in scripts/time-limit-probes.swift.
"""

import pathlib
import re
import sys

OPERATOR = re.compile(r"(?<=\s)(<=|>=|<|>)(?=\s)")
UNITS = r"(?:nanoseconds|microseconds|milliseconds|seconds|minutes|hours)"
DURATION = re.compile(rf"(?:\bDuration)?\.{UNITS}\(|\bDuration\.")
LITERAL_DURATION = re.compile(rf"(?:\bDuration)?\.{UNITS}\(\s*-?\d[\d_]*(?:\.\d[\d_]*)?\s*\)")
NUMBER = re.compile(r"^-?\d[\d_]*(?:\.\d[\d_]*)?$")
ARITHMETIC = re.compile(r"^[\d_.\s()+\-*/]*$")
# Names of values that hold a time. A false match only costs a `// time-ok:` comment.
TIME_NAME = re.compile(r"(?i:elapsed|milli|micro|nano|second|duration|slept|clock)|\b[Tt]ime(?!s\b)|[a-z]Time\b|\bnow\b|\bspent\b")
DECLARED_TIME = re.compile(r"\b(\w+)\s*:\s*(?:TimeInterval|Duration)\b")
ASSERTION = re.compile(r"#(?:expect|require)\(")
OPENING, CLOSING = "([{", ")]}"


def code_lines(text: str) -> list[str]:
	"""The lines of `text` with string contents blanked and comments dropped, so that each keeps its number."""
	lines, out, i = [], [], 0
	in_string = in_block = False
	comment_depth = 0
	while i < len(text):
		c = text[i]
		if c == "\n":
			lines.append("".join(out))
			out = []
			in_string = False
			i += 1
		elif comment_depth:
			if text.startswith("*/", i):
				comment_depth -= 1
				i += 2
			elif text.startswith("/*", i):
				comment_depth += 1
				i += 2
			else:
				i += 1
		elif in_block:
			if text.startswith('"""', i):
				in_block = False
				out.append('"')
				i += 3
			else:
				i += 1
		elif in_string:
			if c == "\\":
				i += 2
			elif c == '"':
				in_string = False
				out.append('"')
				i += 1
			else:
				i += 1
		elif text.startswith('"""', i):
			in_block = True
			out.append('"')
			i += 3
		elif c == '"':
			in_string = True
			out.append('"')
			i += 1
		elif text.startswith("//", i):
			while i < len(text) and text[i] != "\n":
				i += 1
		elif text.startswith("/*", i):
			comment_depth = 1
			i += 2
		else:
			out.append(c)
			i += 1
	lines.append("".join(out))
	return lines


def operand(code: str, start: int, step: int) -> str:
	"""The operand that begins next to `start` and runs in the direction `step`, up to the end of its expression."""
	depth, i = 0, start
	opening, closing = (OPENING, CLOSING) if step > 0 else (CLOSING, OPENING)
	while 0 <= i < len(code):
		c = code[i]
		# The body of a `while` or an `if` ends its condition.
		if depth == 0 and c == "{" and step > 0:
			break
		if c in opening:
			depth += 1
		elif c in closing:
			if depth == 0:
				break
			depth -= 1
		elif depth == 0:
			if c == "," or code[i:i + 2] in ("&&", "||") or code[i - 1:i + 1] in ("&&", "||"):
				break
			# An assignment, but not `==`, `!=`, `<=`, or `>=`.
			if c == "=" and code[i - 1:i] not in ("<", ">", "!", "=") and code[i + 1:i + 2] != "=":
				break
			if code[i:i + 2] in ("? ", ": "):
				break
		i += step
	part = code[start:i] if step > 0 else code[i + 1:start + 1]
	part = re.sub(r"^\s*(?:try|await|return|while|if|guard|let \w+ =|var \w+ =)\s+", "", part.strip())
	return part.strip()


def is_constant(side: str) -> bool:
	"""A number, or arithmetic of numbers and duration literals whose arguments are numbers."""
	return bool(NUMBER.match(side) or (DURATION.search(side) and ARITHMETIC.match(LITERAL_DURATION.sub("0", side))))


def is_time(side: str, times: set[str]) -> bool:
	if DURATION.search(side) or TIME_NAME.search(side) or "clock_gettime" in side:
		return True
	return any(name in times for name in re.findall(r"\b\w+\b", side))


def raw_limits(code: str, times: set[str]) -> list[str]:
	"""The upper time limits in one expression that do not go through budget(_:)."""
	found = []
	for match in OPERATOR.finditer(code):
		left = operand(code, match.start() - 1, -1)
		right = operand(code, match.end(), 1)
		op = match.group(1)
		measured, limit = (left, right) if op in ("<", "<=") else (right, left)
		if not limit or not measured or "budget(" in limit or is_constant(measured) or not is_constant(limit):
			continue
		if DURATION.search(limit) or is_time(measured, times):
			found.append(f"{left} {op} {right}")
	return found


def assertions(lines: list[str]) -> list[tuple[int, int, str]]:
	"""Each `#expect(` and `#require(` that spans lines, as its first and last index and its argument on one line."""
	text = "\n".join(lines)
	starts = [0]
	for line in lines:
		starts.append(starts[-1] + len(line) + 1)
	spans = []
	for match in ASSERTION.finditer(text):
		depth, i = 1, match.end()
		while i < len(text) and depth:
			depth += {"(": 1, ")": -1}.get(text[i], 0)
			i += 1
		first = next(n for n in range(len(lines)) if starts[n + 1] > match.start())
		last = next(n for n in range(first, len(lines)) if starts[n + 1] > i - 1)
		if last > first:
			spans.append((first, last, re.sub(r"\s*\n\s*", " ", text[match.end():i - 1])))
	return spans


def check(path: pathlib.Path, shown: pathlib.Path) -> list[str]:
	"""The raw limits of one file, each as `path:line: comparison`."""
	source = path.read_text(encoding="utf-8")
	original = source.splitlines()
	lines = code_lines(source)
	times = set(DECLARED_TIME.findall("\n".join(lines)))
	found: dict[int, list[str]] = {}
	for n, code in enumerate(lines):
		if n < len(original) and "// time-ok: " in original[n]:
			continue
		if limits := raw_limits(code, times):
			found[n] = limits
	for first, last, argument in assertions(lines):
		# One report for each assertion, and none for one that a line of it already gave.
		if any(n in found for n in range(first, last + 1)) or any("// time-ok: " in original[n] for n in range(first, min(last + 1, len(original)))):
			continue
		if limits := raw_limits(argument, times):
			found[first] = limits
	return [f"{shown}:{n + 1}: {limit}" for n in sorted(found) for limit in found[n]]


def main(arguments: list[str]) -> int:
	root = pathlib.Path(__file__).resolve().parent.parent
	files = [pathlib.Path(a) for a in arguments] or sorted((root / "Tests").rglob("*.swift"))
	problems = [p for f in files for p in check(f, f.resolve().relative_to(root) if f.resolve().is_relative_to(root) else f)]
	for problem in problems:
		print(problem, flush=True)
	if problems:
		print("A time limit in a test goes through budget(_:) of Tests/TestSupport, or says why not with // time-ok: <reason>.", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
