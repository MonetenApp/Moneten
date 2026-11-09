import AppKit
import Domain
import Foundation
import SwiftUI

/// Lets a developer drive the app and capture its windows as images, for checks without a screen.
///
/// Active only when the environment variable `MONETENMONETEN_DEBUG_DIR` names a folder. Commands
/// arrive as distributed notifications named `io.github.monetenmoneten.debug` with the keys
/// `command` and `argument`. Snapshots are drawn by the app itself and need no screen recording.
@MainActor
final class DebugHarness {
	static var shared: DebugHarness?

	let folder: URL
	weak var model: AppModel?

	static func installIfRequested(model: AppModel) {
		guard shared == nil, let path = ProcessInfo.processInfo.environment["MONETENMONETEN_DEBUG_DIR"], !path.isEmpty else { return }
		let harness = DebugHarness(folder: URL(fileURLWithPath: path), model: model)
		shared = harness
		DistributedNotificationCenter.default().addObserver(forName: Notification.Name("io.github.monetenmoneten.debug"), object: nil, queue: .main) { note in
			let command = note.userInfo?["command"] as? String ?? ""
			let argument = note.userInfo?["argument"] as? String ?? ""
			MainActor.assumeIsolated { harness.run(command, argument) }
		}
	}

	init(folder: URL, model: AppModel) {
		self.folder = folder
		self.model = model
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	}

	private func log(_ text: String) {
		let url = folder.appendingPathComponent("debug.log")
		let line = Data((text + "\n").utf8)
		if let h = try? FileHandle(forWritingTo: url) {
			h.seekToEndOfFile()
			h.write(line)
			try? h.close()
		} else {
			try? line.write(to: url)
		}
	}

	func run(_ command: String, _ argument: String) {
		guard let model else { return }
		switch command {
		case "snapshot": snapshot(argument)
		case "sidebarsnapshot": sidebarSnapshot(argument)
		case "setpassword": model.setPassword(argument)
		case "create": model.createDatabase(password: argument.isEmpty ? nil : argument)
		case "unlock": log("unlock \(model.unlock(password: argument))")
		case "lock": model.lock()
		case "seed": DemoData.seed(model)
		case "select":
			if let a = model.ledger.accounts.first(where: { $0.name == argument }) { model.navigate(to: .account(a.id)) }
			else if let g = model.ledger.groups.first(where: { $0.name == argument }) { model.navigate(to: .group(g.id)) }
			else if let c = model.ledger.categories.first(where: { $0.name == argument }) { model.navigate(to: .category(c.id)) }
			else { log("select: not found \(argument)") }
		case "view": model.viewMode = ViewMode(rawValue: argument) ?? .list
		case "balance": model.balanceMode = BalanceMode(rawValue: argument) ?? .daily
		case "search": model.filter.searchText = argument
		case "period":
			switch argument {
			case "90": model.period = .days90
			case "12m": model.period = .months12
			case "year": model.period = .year(Day.today().firstOfYear)
			default: model.period = .all
			}
		case "sheet":
			switch argument {
			case "migration": model.sheet = .migration
			case "newAccount": model.sheet = .newAccount
			case "setPassword": model.sheet = .setPassword
			case "changePassword": model.sheet = .changePassword
			case "categorySettings": if case let .category(id) = model.selection { model.sheet = .categorySettings(id) }
			case "accountSettings": if case let .account(id) = model.selection { model.sheet = .accountSettings(id) }
			case "transaction": model.sheet = .transaction(model.visibleTransactions.first?.id)
			default: model.sheet = nil
			}
		case "selectRows": model.selectedTransactions = Set(model.visibleTransactions.prefix(Int(argument) ?? 1).map(\.id))
		case "state":
			log("phase=\(model.phase) accounts=\(model.ledger.accounts.count) transactions=\(model.ledger.transactions.count) visible=\(model.visibleTransactions.count) selection=\(String(describing: model.selection))")
		case "quit": NSApp.terminate(nil)
		default: log("unknown command \(command)")
		}
	}

	/// Draws the sidebar in a plain window that is off screen, because the sidebar of the main
	/// window uses a material that only the window server draws.
	private func sidebarSnapshot(_ name: String) {
		guard let model else { return }
		let host = NSHostingView(rootView: SidebarView().environment(model).frame(width: 340, height: 900))
		let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 340, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
		window.contentView = host
		window.orderFrontRegardless()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			host.layoutSubtreeIfNeeded()
			if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
				host.cacheDisplay(in: host.bounds, to: rep)
				try? rep.representation(using: .png, properties: [:])?.write(to: self.folder.appendingPathComponent("\(name)-sidebar.png"))
			}
			window.orderOut(nil)
			self.log("sidebarsnapshot \(name)")
		}
	}

	private func snapshot(_ name: String) {
		let windows = NSApp.windows.filter { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.frame.width > 50 }
		for (i, window) in windows.enumerated() {
			for (j, w) in ([window] + (window.attachedSheet.map { [$0] } ?? [])).enumerated() {
				guard let view = w.contentView?.superview ?? w.contentView,
					let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
				view.cacheDisplay(in: view.bounds, to: rep)
				let file = folder.appendingPathComponent("\(name)-\(i)\(j == 0 ? "" : "-sheet").png")
				try? rep.representation(using: .png, properties: [:])?.write(to: file)
				log("snapshot \(file.lastPathComponent) \(w.title) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
			}
		}
	}
}

/// Made-up accounts and transactions for development and screenshots.
enum DemoData {
	@MainActor
	static func seed(_ model: AppModel) {
		model.addGroup(name: "Private")
		guard let group = model.ledger.groups.first(where: { $0.name == "Private" }) else { return }
		model.addOfflineAccount(name: "Girokonto", kind: .giro, currency: "EUR", groupID: group.id)
		model.addOfflineAccount(name: "Tagesgeld", kind: .savings, currency: "EUR", groupID: group.id)
		guard let giro = model.ledger.accounts.first(where: { $0.name == "Girokonto" }),
			let savings = model.ledger.accounts.first(where: { $0.name == "Tagesgeld" }) else { return }
		var g = giro
		g.initialBalanceMinor = 250_000
		g.iban = "DE02120300000000202051"
		model.save(account: g)
		var s = savings
		s.initialBalanceMinor = 1_000_000
		model.save(account: s)
		var ts: [Transaction] = []
		let today = Day.today()
		for m in 0..<14 {
			let month = today.firstOfMonth.adding(months: -m)
			func day(_ d: Int) -> Day { Day(year: month.year, month: month.month, day: d) }
			if day(1) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(1), amountMinor: -95_000, name: "Wohnbau Musterstadt eG", purpose: "Miete \(month.month)/\(month.year)"))
			}
			if day(28) <= today || m > 0 {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(28), amountMinor: 320_000, name: "Beispiel GmbH", purpose: "Gehalt \(month.month)/\(month.year)"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(15), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag Strom",
					mandateReference: "M-4711", creditorID: "DE98ZZZ09999999999"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(20), amountMinor: -1_299, name: "Streaming Dienst", purpose: "Abo"))
				ts.append(Transaction(accountID: giro.id, bookingDate: day(26), amountMinor: -50_000, name: "Max Mustermann", purpose: "Sparen", counterpartyIBAN: "DE02120300000000202051"))
				ts.append(Transaction(accountID: savings.id, bookingDate: day(26), amountMinor: 50_000, name: "Max Mustermann", purpose: "Sparen"))
			}
			for (i, d) in [3, 7, 10, 14, 17, 21, 24].enumerated() where day(d) <= today {
				ts.append(Transaction(accountID: giro.id, bookingDate: day(d), amountMinor: -Int64(2_000 + (i * 1_337 + m * 911) % 9_000),
					name: i % 2 == 0 ? "REWE Markt" : "Bäckerei Gutbrot", purpose: "KARTENZAHLUNG"))
			}
		}
		ts.append(Transaction(accountID: giro.id, bookingDate: today, amountMinor: -4_250, name: "Tankstelle", purpose: "KARTENZAHLUNG", isPending: true, isNew: true))
		let imported = model.importTransactions(ts.filter { $0.accountID == giro.id }, into: giro)
		_ = model.importTransactions(ts.filter { $0.accountID == savings.id }, into: savings)
		_ = imported
		if var groceries = model.ledger.categories.first(where: { $0.name == "Groceries" }) {
			groceries.rule = #""REWE" OR "Bäckerei*""#
			model.save(category: groceries)
		}
		if var rent = model.ledger.categories.first(where: { $0.name == "Rent" }) {
			rent.rule = #"name:"Wohnbau*" AND amount<0"#
			model.save(category: rent)
		}
	}
}
