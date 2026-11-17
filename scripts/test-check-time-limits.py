#!/usr/bin/env python3
"""Runs scripts/check-time-limits.py on scripts/time-limit-probes.swift: it must report exactly the probes marked raw."""

import importlib.util
import pathlib
import sys

scripts = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("check_time_limits", scripts / "check-time-limits.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

probes = scripts / "time-limit-probes.swift"
lines = probes.read_text(encoding="utf-8").splitlines()
expected = {n for n, line in enumerate(lines, start=1) if line.rstrip().endswith("probe: raw")}
reported = {int(problem.split(":")[1]) for problem in check.check(probes, probes)}
missed, wrong = sorted(expected - reported), sorted(reported - expected)
for n in missed:
	print(f"{probes.name}:{n}: not reported: {lines[n - 1].strip()}")
for n in wrong:
	print(f"{probes.name}:{n}: reported, but passes: {lines[n - 1].strip()}")
if missed or wrong:
	sys.exit(1)
print(f"Time limit check: {len(expected)} raw probes reported, {sum('probe: pass' in l for l in lines)} passing probes kept.")
