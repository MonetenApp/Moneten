import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Synchronization

/// The folder `Fixtures/extensions` of the repository.
let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Fixtures/extensions").standardized

/// The host process that the package manager built next to the tests.
let hostExecutable = Bundle(for: TestSession.self).bundleURL.deletingLastPathComponent().appending(path: "MonetenExtensionHost")

func fixture(_ path: String) throws -> Fixture {
	try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtures.appending(path: path)))
}

/// `Demo.lua` installed from a file, with `Demo.json` next to it when `hosts` is set.
func demo(_ source: String, hosts: [String]? = nil) -> ExtensionPackage {
	let folder = FileManager.default.temporaryDirectory.appending(path: "ExtensionConnectorTests-\(UUID().uuidString)")
	try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
	try! Data(source.utf8).write(to: folder.appending(path: "Demo.lua"))
	if let hosts { try! JSONSerialization.data(withJSONObject: ["hosts": hosts]).write(to: folder.appending(path: "Demo.json")) }
	return try! ExtensionPackage.load(from: folder.appending(path: "Demo.lua"))
}

/// A user who answers each dialog with the next answer of the list, and the record of what the
/// connector asked, printed, and sent. A waiting notice stays open until the connector closes it.
final class TestSession: SyncSession, Sendable {
	private let answers: Mutex<[UserAnswer]>
	let asked = Mutex<[UserRequest]>([])
	let log = Mutex<[HostLog]>([])
	let attended: Bool
	/// Every two-factor dialog stays open until the task is canceled, or fails after 5 seconds.
	let hold: Bool
	/// A waiting notice closes at the validity of its challenge, as the broker closes it.
	let expires: Bool

	init(_ answers: [UserAnswer] = [.login([Secret("erika"), Secret("geheim")])], attended: Bool = true, hold: Bool = false, expires: Bool = false) {
		self.answers = Mutex(answers)
		self.attended = attended
		self.hold = hold
		self.expires = expires
	}

	var isAttended: Bool { attended }

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		asked.withLock { $0.append(request) }
		if hold, case .secondFactor = request {
			try await Task.sleep(for: .seconds(5))
			throw CancellationError()
		}
		if case let .secondFactor(factor) = request, case .approveInApp = factor.challenge {
			try await Task.sleep(for: expires ? factor.validity : .seconds(3600))
			throw SyncFailure.challengeExpired
		}
		if !attended, request.kind != .login { throw SyncFailure.needsUser(request.kind) }
		guard let answer = answers.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else { throw CancellationError() }
		return answer
	}

	func report(_ progress: SyncProgress) async {}

	/// What the connector reported as rejected, at the moment it did.
	let rejections = Mutex<[SyncFailure]>([])

	func rejected(_ failure: SyncFailure) async {
		rejections.withLock { $0.append(failure) }
	}

	var printed: [String] {
		log.withLock { $0.compactMap { if case let .print(line) = $0 { line } else { nil } } }
	}

	var sent: [String] {
		log.withLock { $0.compactMap { if case let .sent(line) = $0 { line } else { nil } } }
	}

	func connector(_ package: ExtensionPackage, fixture: Fixture = network([]), known: [Transaction] = []) -> ExtensionConnector {
		let services = ExtensionConnector.Services(hostDecisions: { [:] }, saveDecision: { _, _ in }, transactions: { _ in known },
			log: { line in self.log.withLock { $0.append(line) } })
		var connector = ExtensionConnector(package: package, environment: .standard, fixture: fixture, executable: hostExecutable, services: services)
		connector.pollInterval = .milliseconds(1)
		connector.timeZone = TimeZone(identifier: "Europe/Berlin")!
		return connector
	}
}

let berlin: Calendar = {
	var calendar = Calendar(identifier: .gregorian)
	calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
	return calendar
}()

/// A network of JSON answers by method and URL, in the order the script sends the requests.
func network(_ exchanges: [(String, String, String)]) -> Fixture {
	let object = ["exchanges": exchanges.map { method, url, body in
		["request": ["method": method, "url": url], "response": ["status": 200, "headers": ["Content-Type": "application/json"], "body": body]]
	}]
	return try! JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: object))
}

/// The fetched rows of an outcome, without the identifiers that each run makes new.
struct Row: Equatable {
	let day: Day
	let amountMinor: Int64
	let name: String
	let purpose: String
	let sourceID: String?
	let isPending: Bool

	init(_ t: Transaction) {
		day = t.bookingDate
		amountMinor = t.amountMinor
		name = t.name
		purpose = t.purpose
		sourceID = t.sourceID
		isPending = t.isPending
	}

	init(_ day: Day, _ amountMinor: Int64, _ name: String, _ purpose: String, _ sourceID: String?, pending: Bool = false) {
		self.day = day
		self.amountMinor = amountMinor
		self.name = name
		self.purpose = purpose
		self.sourceID = sourceID
		isPending = pending
	}
}

extension AccountOutcome {
	var rows: [Row]? {
		guard case let .fetched(result) = self else { return nil }
		return result.transactions?.rows.map(Row.init)
	}

	var balance: Int64? {
		guard case let .fetched(result) = self else { return nil }
		return result.balance?.minorUnits
	}

	var failure: String? {
		guard case let .failed(failure) = self else { return nil }
		return failure.message
	}
}
