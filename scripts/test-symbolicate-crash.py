import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class SymbolicateCrashTests(unittest.TestCase):
	def test_help_and_usage(self):
		result = subprocess.run(["scripts/symbolicate-crash.sh", "--help"], capture_output=True, text=True)
		self.assertEqual(result.returncode, 0)
		self.assertIn("report.txt", result.stdout)
		result = subprocess.run(["scripts/symbolicate-crash.sh"], capture_output=True, text=True)
		self.assertEqual(result.returncode, 2)
		self.assertIn("usage:", result.stderr)

	def test_uuid_and_offset_select_symbols(self):
		with tempfile.TemporaryDirectory() as tmp:
			root = Path(tmp)
			dwarf = root / "Symbols with spaces" / "Moneten.dSYM/Contents/Resources/DWARF/Moneten"
			dwarf.parent.mkdir(parents=True)
			dwarf.touch()
			tools = root / "tools"
			tools.mkdir()
			commands = {
				"dwarfdump": 'printf "UUID: 70B89F27-1634-3580-A695-57CDB41D7743 (arm64) Moneten\\n"',
				"otool": 'printf "segname __TEXT\\nvmaddr 0x100000000\\n"',
				"atos": '[ "$4" = arm64 ] && [ "$6" = 0x100000000 ] && [ "$7" = 0x100001000 ] || exit 1\nprintf "intentionalCrash()\\n"',
			}
			for name, body in commands.items():
				tool = tools / name
				tool.write_text("#!/bin/sh\n" + body + "\n")
				tool.chmod(0o755)
			report = root / "report.txt"
			report.write_text("Moneten crash report\nFrame: Moneten 70B89F27-1634-3580-A695-57CDB41D7743 0x1000\n")
			env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"]}
			args = ["scripts/symbolicate-crash.sh", str(report), str(dwarf.parents[4])]
			result = subprocess.run(args, capture_output=True, text=True, env=env)
			self.assertEqual(result.returncode, 0, result.stderr)
			self.assertIn("-> intentionalCrash()", result.stdout)
			report.write_text("Frame: Moneten 00000000-0000-0000-0000-000000000001 0x1000\n")
			result = subprocess.run(args, capture_output=True, text=True, env=env)
			self.assertNotEqual(result.returncode, 0)
			self.assertIn("No matching dSYM", result.stderr)
			report.write_text("Frame: Moneten 70B89F27-1634-3580-A695-57CDB41D7743 $(touch bad)\n")
			result = subprocess.run(args, capture_output=True, text=True, env=env)
			self.assertNotEqual(result.returncode, 0)
			self.assertIn("Invalid frame line", result.stderr)


if __name__ == "__main__":
	unittest.main()
