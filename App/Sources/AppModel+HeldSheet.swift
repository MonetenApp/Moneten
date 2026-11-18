import Domain
import SwiftUI

/// The lock closes the open sheet, because a locked app shows no data, and the unlock shows it again with the input
/// from before the lock (`HeldSheet`). The input stays in memory only.
extension AppModel {
	/// The main view appeared, after the unlock or when its window opened. The sheet that the lock closed shows again
	/// one turn later, so that it never comes in the same update as the main view that replaces the lock screen.
	func showHeldSheet() {
		guard let kind = heldSheet.unlock() else { return }
		Task { @MainActor in
			// A sheet whose subject is gone, such as an account of a database that a backup replaced while the app was
			// locked, stays closed, and its input goes.
			guard phase == .unlocked, sheet == nil, stillShows(kind) else { return heldSheet.drop() }
			sheet = kind
		}
	}

	/// The input of a sheet that shows again after the unlock, once. Any other opening gets nil.
	func heldInput<Input>(for kind: SheetKind) -> Input? {
		heldSheet.input(for: kind) as? Input
	}

	/// Whether the subject of a sheet still exists, so that the sheet can show again.
	private func stillShows(_ kind: SheetKind) -> Bool {
		switch kind {
		case let .accountSettings(id), let .calibration(id): ledger.account(id) != nil
		case let .groupSettings(id): ledger.group(id) != nil
		case let .categorySettings(id): ledger.category(id) != nil
		case let .transaction(id): id.map { ledger.row($0) != nil } ?? true
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
			model.debugSheetInput = AnyHashable(new)
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
