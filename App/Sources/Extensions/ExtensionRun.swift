import Domain
import ExtensionHost
import Foundation
import Storage

/// Runs one global function of an extension in its own host session, for the debug harness command
/// `extrun`. It runs as a refresh of the sync coordinator, so the question about a new host reaches
/// the user through the dialog queue, and the app stores the answer for the extension.
struct ExtensionRun: BankConnector {
	let package: ExtensionPackage
	let function: String
	let fixture: Fixture?
	let store: Store
	let log: @MainActor (LogLine) -> Void

	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		do {
			let started = ContinuousClock.now
			let setup = HostSetup(package: package, decisions: try store.hostDecisions(of: package.name), fixture: fixture)
			let (client, _, loadTime) = try await ExtensionHostClient.start(setup, ask: { [package, store] host in
				guard case let .host(decision) = try await session.ask(.allowHost(HostPermissionRequest(extensionName: package.name, host: host))) else {
					throw CancellationError()
				}
				try store.save(decision, host: host, of: package.name)
				return decision
			}, log: { [package, log] line in
				Task { @MainActor in log(line.debugLine(package.name)) }
			})
			await log(LogLine("ext", ("pid", .count(Int(client.processIdentifier))), ("session_start_ms", .count(Int((ContinuousClock.now - started) / .milliseconds(1)))),
				("load_ms", .count(Int(loadTime.rounded())))))
			let result: Result<LuaValue, any Error>
			do { result = .success(try await client.call(function)) } catch { result = .failure(error) }
			await client.end()
			await log(LogLine("ext ended", ("pid", .count(Int(client.processIdentifier)))))
			let value = try result.get()
			await log(Self.line(of: value))
			return ConnectorReport(outcomes: [:])
		} catch {
			await log(LogLine("ext", ("error", .type(of: error))))
			throw SyncFailure.unsupported("\(error)")
		}
	}

	/// The kind and the size of the result, without its content, which comes from the extension.
	private static func line(of value: LuaValue) -> LogLine {
		switch value {
		case let .string(text): LogLine("ext result string", ("count", .count(text.count)))
		case let .bytes(data): LogLine("ext result bytes", ("count", .count(data.count)))
		case let .array(items): LogLine("ext result array", ("count", .count(items.count)))
		case let .object(fields): LogLine("ext result object", ("count", .count(fields.count)))
		case .null, .boolean, .integer, .number: LogLine("ext result", ("", .state(value)))
		}
	}
}
