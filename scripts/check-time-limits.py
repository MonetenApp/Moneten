#!/usr/bin/env python3
"""Fails on an upper time limit in a test that bypasses budget(_:) of Tests/TestSupport (issue #372).

A comparison is an upper time limit when its limit side is a constant, that is a number or an expression of
duration literals such as `.milliseconds(300)`, and its other side is a time. The comparison may point either
way: `elapsed < .seconds(1)` and `.seconds(1) > elapsed` are the same limit. A side compared with a duration
literal is always a time. A side compared with a number is a time when it measures one, as in
`elapsed / .milliseconds(1) < 5`, or when its name says so, as in `milliseconds`, `slept`, or
`secondsToTermination(...)`.

The check passes a line with `budget(`, a lower bound such as `elapsed >= .seconds(5)`, which a slow runner never
fails, and a wait on a deadline such as `ContinuousClock.now < deadline`, which compares two times. A limit with its
own room for a slow runner carries `// time-ok: <reason>` on its line.

With file arguments the check reads those files instead of Tests/. scripts/test-check-time-limits.py runs it on
its probes.
"""

import pathlib
import re
import sys

OPERATOR = re.compile(r"(?<=\s)(<=|>=|<|>)(?=\s)")
DURATION = re.compile(r"(?:\bDuration)?\.(?:nanoseconds|microseconds|milliseconds|seconds|minutes|hours)\(|\bDuration\.")
NUMBER = re.compile(r"^-?\d[\d_]*(?:\.\d[\d_]*)?$")
# Names of values that hold a time. A false match only costs a `// time-ok:` comment.
TIME_NAME = re.compile(r"(?i)elapsed|milli|micro|nano|second|duration|slept|clock|time(?!s\b)|\bnow\b|\bspent\b")
OPENING, CLOSING = "([{", ")]}"


def without_strings_and_comment(line: str, in_block: bool) -> tuple[str, bool]:
	"""The code of `line` with string contents blanked and the comment dropped, and whether a `\"\"\"` block is open after it."""
	out, i, in_string = [], 0, False
	while i < len(line):
		if in_block:
			if line.startswith('"""', i):
				in_block = False
				i += 3
			else:
				i += 1
			continue
		if in_string:
			if line[i] == "\\":
				i += 2
			elif line[i] == '"':
				in_string = False
				out.append('""')
				i += 1
			else:
				i += 1
			continue
		if line.startswith('"""', i):
			in_block = True
			out.append('""')
			i += 3
		elif line[i] == '"':
			in_string = True
			i += 1
		elif line.startswith("//", i):
			break
		else:
			out.append(line[i])
			i += 1
	return "".join(out), in_block


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
	"""A number, or arithmetic of duration literals and numbers, without a measured time."""
	if NUMBER.match(side):
		return True
	if not DURATION.search(side):
		return False
	rest = DURATION.sub("", side)
	return not TIME_NAME.search(rest)


def is_time(side: str) -> bool:
	return bool(DURATION.search(side) or TIME_NAME.search(side) or "clock_gettime" in side)


def raw_limits(code: str) -> list[str]:
	"""The upper time limits in one line of code that do not go through budget(_:)."""
	found = []
	for match in OPERATOR.finditer(code):
		left = operand(code, match.start() - 1, -1)
		right = operand(code, match.end(), 1)
		op = match.group(1)
		measured, limit = (left, right) if op in ("<", "<=") else (right, left)
		if not limit or not measured or "budget(" in limit or is_constant(measured) or not is_constant(limit):
			continue
		if DURATION.search(limit) or is_time(measured):
			found.append(f"{left} {op} {right}")
	return found


def check(path: pathlib.Path, shown: pathlib.Path) -> list[str]:
	"""The raw limits of one file, each as `path:line: comparison`."""
	problems, in_block = [], False
	for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
		code, in_block = without_strings_and_comment(line, in_block)
		if "// time-ok: " in line:
			continue
		for limit in raw_limits(code):
			problems.append(f"{shown}:{number}: {limit}")
	return problems


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
