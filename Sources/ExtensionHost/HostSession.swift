import CLua
import Domain
import Foundation

/// One session of an extension in the host process: its own Lua state, its package, and its network.
/// Nothing is shared between sessions, and the process ends with the session.
final class HostSession {
	private let lua: LuaState
	private let package: ExtensionPackage
	let network: Network
	let log: (String) -> Void
	var registration: Registration?
	/// The last URL of each connection, by the address of its table, for relative URLs.
	var lastURLs: [UnsafeRawPointer: URL] = [:]

	/// A package with a list of hosts reaches only those. Without one, `ask` waits for the user's
	/// answer about a new host; `decisions` holds the answers the app stored for this extension.
	init(package: ExtensionPackage, transport: any Transport, decisions: [String: HostDecision] = [:], memory: Int = HostLimits().memory,
		ask: @escaping (String) throws -> HostDecision, log: @escaping (String) -> Void) {
		self.package = package
		lua = LuaState(memory: memory)
		let rule: HostPolicy.Rule = package.manifest?.hosts.map { .listed(Set($0)) } ?? .askUser
		network = Network(policy: HostPolicy(extensionName: package.name, rule: rule, decisions: decisions, ask: ask), transport: transport)
		self.log = log
		clua_setcontext(lua.stack.L, Unmanaged.passUnretained(self).toOpaque())
		Environment.install(lua.stack, extensionName: package.name)
	}

	/// Runs every file of the package in order in the same state and returns the registration.
	func load() throws(ScriptError) -> Registration {
		for file in package.files { try lua.run(file.text, file: file.name) }
		guard let registration else { throw ScriptError("\(package.name) does not call WebBanking{}.") }
		return registration
	}

	func call(_ function: String) throws(ScriptError) -> LuaValue {
		try lua.call(function)
	}

	/// The session of a Lua thread, for the functions that Swift implements.
	static func current(_ L: OpaquePointer?) -> HostSession {
		Unmanaged<HostSession>.fromOpaque(clua_context(L)!).takeUnretainedValue()
	}
}
