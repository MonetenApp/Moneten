import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Storage
import Testing

/// The time of a whole extension refresh, from the start of the host process to the merge into a
/// long history, and the start of a session up to its first entry call.
@Suite("Performance of an extension refresh", .serialized)
struct ExtensionRefreshPerformanceTests {
	static let script = """
		WebBanking{version = 1}
		function SupportsBank() return true end
		function InitializeSession() end
		function RefreshAccount(account, since, isKnownTransactionId)
			local answer = JSON(Connection():request("GET", "https://api.bank.example/transactions", nil, nil, {Accept = "application/json"})):dictionary()
			local transactions, known = {}, 0
			for _, item in ipairs(answer.items) do
				if isKnownTransactionId(item.id) then known = known + 1 end
				table.insert(transactions, {transactionId = item.id, bookingDate = item.date, name = item.name, purpose = item.purpose, amount = item.amount})
			end
			print("known " .. known)
			return {balance = 1500, transactions = transactions}
		end
		function EndSession() end

		"""

	@Test("300 replayed rows into one account of a 50,000-row history, end to end, within 1 second")
	func refreshIntoLongHistory() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let store = try Vault(folder: folder).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
		let accounts = (0..<20).map { Account(position: $0, name: "Konto \($0)", kind: .giro, source: .bank) }
		let today = Day(year: 2026, month: 11, day: 12)
		let history = accounts.flatMap { a in
			(0..<2_500).map { i in
				Transaction(accountID: a.id, bookingDate: today.adding(days: -(i / 8)), amountMinor: -Int64(100 + i), name: "Haendler\(i % 70) Musterstadt",
					purpose: "Rechnung \(i)", isFetched: true, sourceID: "T-\(i)")
			}
		}
		try store.save(accounts: accounts, transactions: history)
		let target = accounts[0]
		let stored = history.filter { $0.accountID == target.id }
		let items = (0..<300).map { i -> [String: Any] in
			let known = i < 250
			let row = stored[i]
			return ["id": known ? row.sourceID! : "N-\(i)", "date": Int(row.bookingDate.date(in: berlin).timeIntervalSince1970) + 43_200,
				"name": known ? row.name : "Online Shop", "purpose": known ? row.purpose : "Bestellung \(i)", "amount": known ? Double(row.amountMinor) / 100 : -50.0 - Double(i)]
		}
		let body = String(decoding: try JSONSerialization.data(withJSONObject: ["items": items]), as: UTF8.self)
		let session = TestSession()
		let connector = session.connector(demo(Self.script, hosts: ["api.bank.example"]), fixture: network([("GET", "https://api.bank.example/transactions", body)]),
			known: stored)
		var state = ExtensionState(nil)
		state.accounts = ["1": .object(["accountNumber": .string("1")])]
		let clock = ContinuousClock()
		var added = -1
		let elapsed = try await clock.measure {
			let report = try await connector.refresh(RefreshRequest(access: Access(source: .extension(id: "Demo"), bankName: "Demo", loginName: "erika"),
				state: state.accessState, accounts: [AccountRequest(accountID: target.id, name: target.name, remoteID: "1", since: today.adding(days: -89))]), session)
			guard case let .fetched(result) = report.outcomes[target.id] else { throw MappingError("not fetched") }
			added = try store.merge(.refresh(result), into: target.id).added.count
		}
		print("ext refresh_ms=\(elapsed / .milliseconds(1)) of 300 rows into 50,000")
		#expect(session.printed == ["known 250"])
		#expect(added == 50)
		#if !DEBUG
		#expect(elapsed < .seconds(1))
		#endif
	}

	@Test("A session starts and reaches its first entry call within 300 ms at p95")
	func sessionStart() async throws {
		let package = demo(Self.script)
		let clock = ContinuousClock()
		var times: [Duration] = []
		for _ in 0..<20 {
			let start = clock.now
			let (client, _, _) = try await ExtensionHostClient.start(HostSetup(package: package), executable: hostExecutable, ask: { _ in .denied })
			_ = try await client.call(.supportsBank(.webBanking, bankCode: "Demo"))
			times.append(clock.now - start)
			await client.end()
		}
		times.sort()
		let p50 = times[9] / .milliseconds(1), p95 = times[18] / .milliseconds(1)
		print("ext session_start_ms p50=\(p50) p95=\(p95)")
		#if !DEBUG
		#expect(times[18] < .milliseconds(300))
		#endif
	}
}
