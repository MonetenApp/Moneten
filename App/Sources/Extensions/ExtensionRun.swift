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
	let log: @MainActor (String) -> Void

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
				Task { @MainActor in
					switch line {
					case let .print(text): log("ext print \(package.name): \(text)")
					case let .sent(request): log("ext sent \(request)")
					}
				}
			})
			await log("ext pid=\(client.processIdentifier) session_start_ms=\((ContinuousClock.now - started) / .milliseconds(1)) load_ms=\(loadTime)")
			let result: Result<LuaValue, any Error>
			do { result = .success(try await client.call(function)) } catch { result = .failure(error) }
			await client.end()
			await log("ext ended pid=\(client.processIdentifier)")
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
			await log("ext result=\(String(decoding: try encoder.encode(result.get()), as: UTF8.self))")
			return ConnectorReport(outcomes: [:])
		} catch {
			await log("ext error=\(error)")
			throw SyncFailure.unsupported("\(error)")
		}
	}
}
