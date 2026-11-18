import Domain
import SwiftUI

/// The lock closes the open sheet, because a locked app shows no data, and the unlock shows it again with the input
/// from before the lock (`HeldSheet`). The input stays in memory only.
extension AppModel {
	/// The main view appeared, after the unlock or when its window opened. The sheet that the unlock gave back opens
	/// one turn later, so that it never comes in the same update as the main view that replaces the lock screen. Until
	/// then `returningSheet` holds the alerts back, so that no alert takes the window before the sheet.
	func showHeldSheet() {
		guard let kind = returningSheet else { return }
		Task { @MainActor in
			guard returningSheet == kind else { return }
			returningSheet = nil
			// A sheet whose subject is gone stays closed, and its input goes.
			guard phase == .unlocked, sheet == nil, stillShows(kind) else { return heldSheet.close(kind) }
			sheet = kind
		}
	}

	/// The input of a sheet that shows again after the unlock, for each appearance until it closes. Any other opening
	/// gets nil.
	func heldInput<Input>(for kind: SheetKind) -> Input? {
		heldSheet.input(for: kind, as: Input.self)
	}

	/// Forgets the held sheet and its input, for every close and open that is not a lock and the unlock after it.
	func dropHeldSheet() {
		heldSheet.drop()
		returningSheet = nil
		#if DEBUG || PERF_HARNESS
		debugSheetInput = nil
		debugSheetInputMark = nil
		#endif
	}

	/// Whether the subject of a sheet still exists, so that the sheet can show again.
	private func stillShows(_ kind: SheetKind) -> Bool {
		switch kind {
		case let .accountSettings(id), let .calibration(id): ledger.account(id) != nil
		case let .groupSettings(id): ledger.group(id) != nil
		case let .categorySettings(id): ledger.category(id) != nil
		case let .transaction(id?): ledger.row(id) != nil
		// A new transaction goes only into the account that it was started in. A click on a notification of another
		// account selects that account before the unlock, and the input then goes.
		case .transaction(nil):
			(heldSheet.returningInput as? TransactionSheet.Input).map { $0.accountID != nil && $0.accountID == selectedAccount?.id } ?? false
		// The group that a new category goes into must still be a group.
		case .newCategory:
			(heldSheet.returningInput as? NewCategorySheet.Input).map { held in
				held.parentID.map { ledger.category($0)?.isGroup == true } ?? true
			} ?? false
		case let .split(row): ledger.row(row.id) != nil
		case let .comment(ids): ids.contains { ledger.row($0) != nil }
		case let .renameSearch(id): savedSearches.contains { $0.id == id }
		default: true
		}
	}
}

/// Writes the input of a sheet to the model when it opens and at each change, so that a lock can keep it.
private struct KeepsInput<Input: Hashable & Sendable>: ViewModifier {
	@Environment(AppModel.self) private var model
	let input: Input
	let sheet: SheetKind

	func body(content: Content) -> some View {
		content.onChange(of: input, initial: true) { _, new in
			model.heldSheet.record(new, of: sheet)
			#if DEBUG || PERF_HARNESS
			if model.phase == .unlocked { model.debugSheetInput = AnyHashable(new) }
			#endif
		}
	}
}

extension View {
	/// The sheet keeps `input` across a lock. It takes it back with `AppModel.heldInput(for:)` when it appears.
	func keepsInput<Input: Hashable & Sendable>(_ input: Input, of sheet: SheetKind) -> some View {
		modifier(KeepsInput(input: input, sheet: sheet))
	}
}
