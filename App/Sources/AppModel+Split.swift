import Domain
import Foundation

/// What became of a split. The split window stays open on `changed`, so that the user can try again with the
/// current values, and closes otherwise.
enum SplitOutcome {
	case done, changed, missing, failed
}

extension AppModel {
	func openSplit(row id: UUID) {
		guard let row = ledger.row(id) else { return }
		guard !row.isPending else { return refusePendingSplit() }
		sheet = .split(row)
	}

	func refusePendingSplit() {
		alert = AlertMessage(title: String(localized: "Only booked transactions can be split."), message: String(localized: "Wait until the bank has booked the transaction."))
	}

	/// `seen` is the row that the split window shows. The split refuses a row that changed since.
	@discardableResult
	func split(row id: UUID, off amounts: [Money], seen: Transaction? = nil) async -> SplitOutcome {
		do {
			let parts = try ledger.splitting(row: id, off: amounts, seen: seen)
			guard let original = parts.first?.transactionID else { return .failed }
			return await replacingParts(of: original, with: parts)
		} catch SplitError.changed {
			return .changed
		} catch SplitError.missing {
			return .missing
		} catch {
			if error as? SplitError == .pending { refusePendingSplit() }
			else { alert = AlertMessage(title: String(localized: "Could not split the transaction."), message: String(localized: "Enter a nonzero amount that leaves a nonzero remainder.")) }
			return .failed
		}
	}

	/// A VAT entry has no window to stay open, so a change of the row during the drawing wait shows a message.
	@discardableResult
	func splitVAT(row id: UUID, rate: VATRate) async -> Bool {
		do {
			let parts = try ledger.splittingVAT(row: id, rate: rate)
			guard let original = parts.first?.transactionID else { return false }
			let outcome = await replacingParts(of: original, with: parts)
			if outcome == .changed { alert = AlertMessage(title: String(localized: "Could not split the transaction."), message: String(localized: "The transaction changed. Try again.")) }
			return outcome == .done
		} catch SplitError.missing {
			return false
		} catch {
			if error as? SplitError == .pending { refusePendingSplit() }
			else { alert = AlertMessage(title: String(localized: "Could not split the transaction."), message: String(localized: "The VAT split would leave a part of zero.")) }
			return false
		}
	}

	func askUndoSplit(row id: UUID) {
		guard ledger.part(id) != nil else { return }
		sheet = .undoSplit(id)
	}

	func refusePartDeletion(in ids: Set<UUID>) -> Bool {
		guard ids.contains(where: { ledger.part($0) != nil }) else { return false }
		alert = AlertMessage(title: String(localized: "A part of a split cannot be deleted alone."),
			message: String(localized: "Use “Undo Split Transaction...” first."))
		return true
	}
}
