import Domain
import Foundation

extension AppModel {
	func openSplit(row id: UUID) {
		guard let row = ledger.row(id) else { return }
		guard !row.isPending else { return refusePendingSplit() }
		sheet = .split(row)
	}

	func refusePendingSplit() {
		alert = AlertMessage(title: "Only booked transactions can be split.", message: "Wait until the bank has booked the transaction.")
	}

	@discardableResult
	func split(row id: UUID, off amounts: [Money]) async -> Bool {
		do {
			let parts = try ledger.splitting(row: id, off: amounts)
			guard let original = parts.first?.transactionID else { return false }
			return await replaceParts(of: original, with: parts)
		} catch {
			if error as? SplitError == .pending { refusePendingSplit() }
			else { alert = AlertMessage(title: "Could not split the transaction.", message: "Enter a nonzero amount that leaves a nonzero remainder.") }
			return false
		}
	}

	@discardableResult
	func splitVAT(row id: UUID, rate: VATRate) async -> Bool {
		do {
			let parts = try ledger.splittingVAT(row: id, rate: rate)
			guard let original = parts.first?.transactionID else { return false }
			return await replaceParts(of: original, with: parts)
		} catch {
			if error as? SplitError == .pending { refusePendingSplit() }
			else { alert = AlertMessage(title: "Could not split the transaction.", message: "The VAT split would leave a part of zero.") }
			return false
		}
	}

	func askUndoSplit(row id: UUID) {
		guard ledger.part(id) != nil else { return }
		sheet = .undoSplit(id)
	}

	func refusePartDeletion(in ids: Set<UUID>) -> Bool {
		guard ids.contains(where: { ledger.part($0) != nil }) else { return false }
		alert = AlertMessage(title: "A part of a split cannot be deleted alone.",
			message: "Use “Undo Split Transaction...” first.")
		return true
	}
}
