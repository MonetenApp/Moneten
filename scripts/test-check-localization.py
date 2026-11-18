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
			Button(String(localized: "Open", comment: "A command of the File menu")) { open() } // probe: pass
			Button(model.name + "...") { open() } // probe: verbatim
			Button(account.name) { open() } // probe: verbatim
			Button(action: open) { Text("Open") } // probe: pass
			Toggle("Checkmarks", isOn: $checkmarks) // probe: pass
			Button("Help") { NSWorkspace.shared.open(URL(string: "https://example.com/help")!) } // probe: pass
			Button(model.signedTitle) { open() } // probe: pass
			Button(menuTitle) { open() } // probe: pass
			ForEach(RefreshInterval.allCases, id: \\.self) { Button($0.title) { choose($0) } } // probe: pass
			ForEach(kinds, id: \\.self) { Button($0.label) { choose($0) } } // probe: verbatim
			Button(model.groupedTitle) { open() } // probe: verbatim
			Button(model.upperTitle) { open() } // probe: verbatim
			ForEach(Kind.allCases, id: \\.self) { Button($0.title) { choose($0) } } // probe: verbatim
			ForEach(model.kinds, id: \\.self) { kind in Button(kind.title) { choose(kind) } } // probe: pass
		}
	}

	var menuTitle: String {
		String(localized: "Window", comment: "The menu of the windows")
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

	/// A literal in parentheses that only group it is the title, and so is one whose method gives a String.
	var groupedTitle: String {
		return ("Open")
	}

	var upperTitle: String {
		return "Open".uppercased()
	}

	/// A literal in a condition or in an argument is no title.
	var signedTitle: String {
		if selection?.name == "Giro" { return String(localized: "Giro", comment: "An account").replacingOccurrences(of: "-", with: "\\u{2212}") }
		return mode != "plain" ? String(localized: "Signed") : String(localized: "Plain")
	}
}
"""
# A view that is no menu may name an account in a button. Other types have properties of the same names, with
# literals that are no menu title: the check must take the property of AppModel or of the menu itself.
VIEW = """struct ProbeView: View {
	var body: some View { Button(account.name) { open() } }
	var settingsTitle: String { "Not a menu title" }
	var menuTitle: String { "Not a menu title either" }
}
"""
# The libraries hold properties that a menu shows for each case, such as the title of a refresh interval.
LIBRARY = """public enum RefreshInterval: CaseIterable {
	case never, hourly
	public var title: String {
		switch self {
		case .never: String(localized: "Never")
		case .hourly: String(localized: "Every hour")
		}
	}
}

enum Kind: CaseIterable {
	case giro
	var label: String { "Giro" }
	/// A plain title of another type than RefreshInterval, which the menu of the refresh intervals does not show.
	var title: String { "Giro" }
}
"""

sources = {"App/Sources/AAProbeView.swift": VIEW, "App/Sources/ProbeCommands.swift": MENUS, "App/Sources/ProbeModel.swift": MODEL,
	"Sources/Domain/Probe.swift": LIBRARY}
lines = MENUS.splitlines()
expected = {n for n, line in enumerate(lines, start=1) if line.rstrip().endswith("probe: verbatim")}
reported = set()
for problem in check.menu_title_problems(sources):
	# A problem in the body of a property names the line of the menu title after "at".
	location = problem.split(" at ", 1)[1] if " for the menu title at " in problem else problem
	reported.add(int(location.split(":")[1].split(",")[0]))
missed, wrong = sorted(expected - reported), sorted(reported - expected)
for n in missed:
	print(f"Commands.swift:{n}: not reported: {lines[n - 1].strip()}")
for n in wrong:
	print(f"Commands.swift:{n}: reported, but passes: {lines[n - 1].strip()}")
if missed or wrong:
	sys.exit(1)
print(f"Menu title check: {len(expected)} verbatim probes reported, {sum('probe: pass' in l for l in lines)} passing probes kept.")
