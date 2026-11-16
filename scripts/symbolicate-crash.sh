#!/bin/sh
exec python3 - "$@" <<'PY'
import argparse
import pathlib
import re
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description="Symbolicate a pasted Moneten crash report with the release dSYMs.")
parser.add_argument("--version", action="version", version="symbolicate-crash 1")
parser.add_argument("report", metavar="report.txt", type=pathlib.Path)
parser.add_argument("symbols", metavar="dSYMs-folder", type=pathlib.Path)
args = parser.parse_args()
report = args.report
folder = args.symbols
if not report.is_file() or not folder.is_dir():
	sys.exit("The report file and dSYMs folder must exist.")

def run(*args):
	return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

try:
	symbols = {}
	for dwarf in folder.rglob("*.dSYM/Contents/Resources/DWARF/*"):
		if not dwarf.is_file():
			continue
		for binary_uuid, arch in re.findall(r"UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", run("dwarfdump", "--uuid", str(dwarf))):
			symbols[uuid.UUID(binary_uuid)] = (dwarf, arch)
	frames = 0
	missing = 0
	for line in report.read_text().splitlines():
		if not line.startswith("Frame:"):
			continue
		match = re.fullmatch(r"Frame: (\S+) ([0-9A-Fa-f-]{36}|Unknown) (0x[0-9a-fA-F]+)", line)
		if not match:
			sys.exit("Invalid frame line in the report.")
		name, binary_uuid, offset = match.groups()
		symbol = None if binary_uuid == "Unknown" else symbols.get(uuid.UUID(binary_uuid))
		if symbol is None:
			print(f"{line} -> No matching dSYM", file=sys.stderr)
			missing += 1
			continue
		dwarf, arch = symbol
		load_commands = run("otool", "-l", "-arch", arch, str(dwarf))
		segment = re.search(r"segname __TEXT\s+vmaddr (0x[0-9a-fA-F]+)", load_commands)
		if not segment:
			sys.exit("The matching dSYM has no __TEXT address.")
		base = int(segment[1], 16)
		address = base + int(offset, 16)
		result = run("atos", "-o", str(dwarf), "-arch", arch, "-l", hex(base), hex(address)).strip()
		print(f"{line} -> {result}")
		frames += 1
	if frames == 0:
		sys.exit("No frame could be symbolicated. Check the release dSYMs.")
	if missing:
		print(f"{missing} frame(s) have no matching dSYM. System frames need Apple's symbols.", file=sys.stderr)
except (OSError, ValueError, subprocess.CalledProcessError) as error:
	sys.exit(f"Symbolication failed: {error}")
PY
