#!/usr/bin/env python3
"""Runs the menu title rule of scripts/check-localization.py on probe sources: it must report exactly the titles that
show verbatim, and pass the ones that the catalog translates."""

import importlib.util
import pathlib
import sys

# Importing the check would otherwise write scripts/__pycache__ on every run.
sys.dont_write_bytecode = True

scripts = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("check_localization", scripts / "check-localization.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# Each line of the menus ends with "probe: verbatim" when the check must report it, and with "probe: pass" when not.
MENUS = """struct ProbeCommands: Commands {
	var body: some Commands {
		CommandMenu("Account") { // probe: pass
			Button("Add Category") { add() } // probe: pass
			Button(model.hasPassword ? "Change Password..." : "Set Password...") { change() } // probe: pass
			Button(model.removeTitle ?? "Remove...") { remove() } // probe: verbatim
			Button(model.removeTitle ?? String(localized: "Remove...")) { remove() } // probe: pass
			Button(model.settingsTitle) { open() } // probe: pass
			Button(model.plainTitle) { open() } // probe: verbatim
			Button(String(localized: "Lock")) { lock() } // probe: pass
			Button(model.name + "...") { open() } // probe: verbatim
			Button(account.name) { open() } // probe: verbatim
			Button(action: open) { Text("Open") } // probe: pass
			Toggle("Checkmarks", isOn: $checkmarks) // probe: pass
			Button("Help") { NSWorkspace.shared.open(URL(string: "https://example.com/help")!) } // probe: pass
		}
	}
}
"""
MODEL = """extension AppModel {
	var settingsTitle: String {
		switch selection {
		// A comment with "a quoted word" is no title.
		case .account: String(localized: "Account Settings...")
		case nil: String(localized: "Settings...")
		}
	}

	var plainTitle: String? {
		selection == nil ? nil : "Plain Title..."
	}

	var removeTitle: String? {
		String(localized: "Remove Account...")
	}
}
"""
# A view that is no menu may name an account in a button.
VIEW = """struct ProbeView: View {
	var body: some View { Button(account.name) { open() } }
}
"""

sources = {"Probe/Commands.swift": MENUS, "Probe/Model.swift": MODEL, "Probe/View.swift": VIEW}
lines = MENUS.splitlines()
expected = {n for n, line in enumerate(lines, start=1) if line.rstrip().endswith("probe: verbatim")}
reported = set()
for problem in check.menu_title_problems(sources):
	# A problem in the body of a property names the line of the menu title after "at".
	location = problem.split(" at ", 1)[1] if problem.startswith("Probe/Model.swift") else problem
	reported.add(int(location.split(":")[1].split(",")[0]))
missed, wrong = sorted(expected - reported), sorted(reported - expected)
for n in missed:
	print(f"Commands.swift:{n}: not reported: {lines[n - 1].strip()}")
for n in wrong:
	print(f"Commands.swift:{n}: reported, but passes: {lines[n - 1].strip()}")
if missed or wrong:
	sys.exit(1)
print(f"Menu title check: {len(expected)} verbatim probes reported, {sum('probe: pass' in l for l in lines)} passing probes kept.")
