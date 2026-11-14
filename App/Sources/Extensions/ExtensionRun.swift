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
			}, log: { [package, log, madeUp = fixture != nil] line in
				Task { @MainActor in log(line.debugLine(package.name, madeUp: madeUp)) }
			})
			await log("ext pid=\(client.processIdentifier) session_start_ms=\((ContinuousClock.now - started) / .milliseconds(1)) load_ms=\(loadTime)")
			let result: Result<LuaValue, any Error>
			do { result = .success(try await client.call(function)) } catch { result = .failure(error) }
			await client.end()
			await log("ext ended pid=\(client.processIdentifier)")
			let value = try result.get()
			if fixture == nil {
				await log("ext result \(Self.kind(of: value))")
			} else {
				let encoder = JSONEncoder()
				encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
				await log("ext result=\(String(decoding: try encoder.encode(value), as: UTF8.self))")
			}
			return ConnectorReport(outcomes: [:])
		} catch {
			await log("ext error=\(fixture == nil ? "\(type(of: error))" : "\(error)")")
			throw SyncFailure.unsupported("\(error)")
		}
	}

	/// The kind and the size of a value that came from a real service, without its content.
	private static func kind(of value: LuaValue) -> String {
		switch value {
		case let .string(text): "string count=\(text.count)"
		case let .bytes(data): "bytes count=\(data.count)"
		case let .array(items): "array count=\(items.count)"
		case let .object(fields): "object count=\(fields.count)"
		case .null: "null"
		case .boolean: "boolean"
		case .integer: "integer"
		case .number: "number"
		}
	}
}
