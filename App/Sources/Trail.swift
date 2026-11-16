import Darwin
import Domain
import Foundation

/// A trail of the events that can replace the transaction table or change its rows, one line per event on
/// stderr (issue #151). When AttributeGraph stops the app in a table update, the crash report has no frame
/// of the app, and the last lines of the trail show what changed just before.
///
/// Each line goes out at once, so that it survives the crash. A line holds kinds and counts only: no
/// names, IBANs, amounts, purposes, account numbers, or search texts.
enum Trail {
	private static let time = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

	static func log(_ event: String) {
		let line = "\(Date.now.formatted(time)) trail \(event)\n"
		_ = line.withCString { write(STDERR_FILENO, $0, strlen($0)) }
	}
}

extension AppModel.Phase {
	var trailName: String {
		switch self {
		case .starting: "starting"
		case .firstLaunch: "firstLaunch"
		case .locked: "locked"
		case .unlocked: "unlocked"
		case .failed: "failed"
		case .changedOnDisk: "changedOnDisk"
		}
	}
}

extension SidebarSelection {
	var trailName: String {
		switch self {
		case .account: "account"
		case .group: "group"
		case .category: "category"
		case .search: "search"
		}
	}
}

extension SheetKind {
	/// The case without its values, which can hold the IDs of transactions.
	var trailName: String { String(String(describing: self).prefix { $0 != "(" }) }
}

extension PeriodChoice {
	/// The choice without its days.
	var trailName: String { String(String(describing: self).prefix { $0 != "(" }) }
}

extension TableKey {
	/// What the view shows: transactions, positions, or nothing ("empty", no view chosen).
	var trailKind: String { selection == nil ? "empty" : portfolios == nil ? "transactions" : "positions" }
}

extension TransactionFilter {
	/// The kinds of the active filters, without their values. The trail and `debug.log` both use them.
	var activeKinds: [StaticString] {
		let kinds: [(Bool, StaticString)] = [(!searchText.isEmpty, "search"), (period != .all, "period"), (status != .all, "status"), (amount != .all, "amount"),
			(categoryID != nil, "category"), (account != nil, "account")]
		return kinds.filter(\.0).map(\.1)
	}

	var trailName: String {
		activeKinds.isEmpty ? "none" : activeKinds.map { "\($0)" }.joined(separator: ",")
	}
}

extension Reconciliation {
	/// The kind of a merge and the number of its rows.
	func trailName(_ kind: String) -> String {
		"\(kind) added=\(added.count) dropped=\(dropped.count) booked=\(booked.count) updated=\(updated.count)"
	}
}
