import Storage
import Testing

/// The one rule for every click of the debug harness: "button", "confirmremove", "rowmenu", "modal", and "menuitem"
/// (merge gate of #486 and #497). Each title is English, as the command names it.
@Suite("Debug harness clicks")
struct HarnessClickTests {
	static let blocked: [HarnessRun.Surface] = [.bankDialog(.local), .bankDialog(.fints), .bankDialog(.realService), .startWindow, .startAlert, .passwordSheet]

	@Test("A save or open panel takes only Cancel, whatever the allow-list of the command holds")
	func filePanelOnlyCancel() {
		let allowed: Set = ["Save", "Open", "Cancel", "Back Up Anyway"]
		#expect(HarnessRun.mayClick("Cancel", allowed: allowed, on: .filePanel))
		#expect(HarnessRun.mayClick("Cancel", allowed: [], on: .filePanel))
		for title in ["Save", "Open", "Back Up Anyway", ""] {
			#expect(!HarnessRun.mayClick(title, allowed: allowed, on: .filePanel), "\(title)")
		}
	}

	@Test("A bank dialog and the surfaces before the unlock take no click")
	func blockedSurfaces() {
		for surface in Self.blocked {
			#expect(!HarnessRun.mayClick("Cancel", allowed: ["Cancel"], on: surface), "\(surface)")
			#expect(!HarnessRun.mayClick("OK", allowed: HarnessRun.modalTitles, on: surface), "\(surface)")
		}
	}

	@Test("Elsewhere a click needs a title of the allow-list in full, never by prefix")
	func allowListInFull() {
		let allowed: Set = ["Apply to all transactions.", "Remove"]
		#expect(HarnessRun.mayClick("Remove", allowed: allowed, on: .other))
		#expect(!HarnessRun.mayClick("Remove...", allowed: allowed, on: .other))
		#expect(!HarnessRun.mayClick("Apply to all", allowed: allowed, on: .other))
		#expect(!HarnessRun.mayClick("Cancel", allowed: allowed, on: .other))
	}

	@Test("modal clicks the buttons of the alerts of the app, and none that sets the database key")
	func modalTitles() {
		for title in ["OK", "Cancel", "Remove", "Delete", "Mark as Checked", "Back Up Anyway"] {
			#expect(HarnessRun.mayClick(title, allowed: HarnessRun.modalTitles, on: .other), "\(title)")
		}
		for title in ["Set Database Password...", "Show Database in Finder", "Save", ""] {
			#expect(!HarnessRun.mayClick(title, allowed: HarnessRun.modalTitles, on: .other), "\(title)")
		}
	}

	@Test("confirmremove answers Remove or Cancel, and button only the question whether to apply a changed rule")
	func questionTitles() {
		#expect(HarnessRun.removeQuestionTitles == ["Remove", "Cancel"])
		for title in ["Apply only to not yet categorized transactions.", "Apply to all transactions.", "Not now"] {
			#expect(HarnessRun.mayClick(title, allowed: HarnessRun.ruleQuestionTitles, on: .other), "\(title)")
		}
		#expect(!HarnessRun.mayClick("Remove", allowed: HarnessRun.ruleQuestionTitles, on: .other))
	}

	@Test("rowmenu chooses the local items of the context menu of a row, no export, and the search for a name of the selection")
	func rowMenuTitles() {
		let allowed = HarnessRun.rowMenuTitles(searching: ["Stadtwerke Musterstadt", ""])
		for item in ["Search for “Stadtwerke Musterstadt”", "Go to", "Assign Category", "Remove Transaction from Category",
			"Remove Transactions from Category", "Create Offsetting Entry", "Add Comment...", "Edit Comment...", "Mark as Checked",
			"Mark as Unchecked", "Edit Transaction...", "Split Transaction", "Delete Transaction...", "Delete Transactions..."] {
			#expect(HarnessRun.mayClick(item, allowed: allowed, on: .other), "\(item)")
		}
		for item in ["Export Transaction...", "Export Transactions...", "Search for “Laden Muster”", "Search for “”", "Search for", "Share...", ""] {
			#expect(!HarnessRun.mayClick(item, allowed: allowed, on: .other), "\(item)")
		}
	}

	@Test("A submenu of a row takes its local commands and the names of the data of the run, and nothing under another item")
	func rowSubmenuTitles() {
		let assign = HarnessRun.rowSubmenuTitles(of: "Assign Category", data: ["Living › Groceries"])
		#expect(HarnessRun.mayClick("Add category", allowed: assign, on: .other))
		#expect(HarnessRun.mayClick("Living › Groceries", allowed: assign, on: .other))
		#expect(!HarnessRun.mayClick("Split Amount...", allowed: assign, on: .other))
		let split = HarnessRun.rowSubmenuTitles(of: "Split Transaction", data: ["Split 19 % VAT"])
		for title in ["Split Amount...", "Undo Split Transaction...", "Split 19 % VAT"] {
			#expect(HarnessRun.mayClick(title, allowed: split, on: .other), "\(title)")
		}
		#expect(!HarnessRun.mayClick("Split from Batch Payment", allowed: split, on: .other))
		#expect(HarnessRun.rowSubmenuTitles(of: "Export Transaction...", data: ["Girokonto"]).isEmpty)
		#expect(HarnessRun.rowSubmenuTitles(of: "Go to", data: ["Girokonto"]) == ["Girokonto"])
	}

	@Test("menuitem chooses only the items of its list, by menu and item")
	func menuTitles() {
		#expect(HarnessRun.mayClick("View|Bar Chart", allowed: HarnessRun.menuTitles, on: .other))
		#expect(HarnessRun.mayClick("Account|Remove Category...", allowed: HarnessRun.menuTitles, on: .other))
		#expect(HarnessRun.mayClick("Account|Remove Category Group...", allowed: HarnessRun.menuTitles, on: .other))
		#expect(!HarnessRun.mayClick("View|Bar", allowed: HarnessRun.menuTitles, on: .other))
		#expect(!HarnessRun.mayClick("File|Backup Database...", allowed: HarnessRun.menuTitles, on: .other))
		#expect(!HarnessRun.mayClick("View|Bar Chart", allowed: HarnessRun.menuTitles, on: .startWindow))
	}
}
