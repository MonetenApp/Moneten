import CLua
import Domain
import Foundation

/// One session of an extension in the host process: its own Lua state, its package, and its network.
/// Nothing is shared between sessions, and the process ends with the session.
final class HostSession {
	let lua: LuaState
	private let package: ExtensionPackage
	let network: Network
	let environment: HostEnvironment
	let log: (String) -> Void
	let status: (String) -> Void
	var registration: Registration?
	/// The stored transactions that `isKnownTransactionId` finds during the current `RefreshAccount`.
	var knownTransactions: [String: LuaValue] = [:]
	/// The last name that a script read from `MM`, `io`, or a connection and that the app does not offer.
	var lastMiss: Miss?
	private let storedData: Data?
	private var objects: [ObjectIdentifier: AnyObject] = [:]

	struct Miss: Equatable {
		/// For example "MM.parseSwiftMt".
		let name: String
		/// For example "Demo.lua:12:", as Lua starts its messages.
		let position: String
	}

	/// A package with a list of hosts reaches only those. Without one, `ask` waits for the user's
	/// answer about a new host; `decisions` holds the answers the app stored for this extension.
	init(package: ExtensionPackage, transport: any Transport, decisions: [String: HostDecision] = [:], memory: Int = HostLimits().memory,
		environment: HostEnvironment = .standard, storage: Data? = nil, ask: @escaping (String) throws -> HostDecision, log: @escaping (String) -> Void,
		status: @escaping (String) -> Void = { _ in }) {
		self.package = package
		lua = LuaState(memory: memory)
		let rule: HostPolicy.Rule = package.manifest?.hosts.map { .listed(Set($0)) } ?? .askUser
		network = Network(policy: HostPolicy(extensionName: package.name, rule: rule, decisions: decisions, ask: ask), transport: transport)
		self.environment = environment
		self.log = log
		self.status = status
		storedData = storage
		clua_setcontext(lua.stack.L, Unmanaged.passUnretained(self).toOpaque())
		Environment.install(lua.stack, extensionName: package.name, environment: environment)
	}

	/// Restores `LocalStorage`, runs every file of the package in order in the same state, and returns the registration.
	func load() throws(ScriptError) -> Registration {
		try LocalStorage.restore(storedData, into: lua.stack)
		for file in package.files { try lua.run(file.text, file: file.name) }
		guard let registration else { throw ScriptError("\(package.name) does not call WebBanking{}.") }
		return registration
	}

	/// The entry points that the script defines as global functions.
	var entryPoints: Set<EntryPoint> {
		Set(EntryPoint.allCases.filter { lua.isFunction($0.rawValue) })
	}

	func call(_ function: String) throws(ScriptError) -> LuaValue {
		try lua.call(function)
	}

	func call(_ entry: EntryCall) throws(ScriptError) -> LuaValue {
		try EntryPoints.call(entry, in: self, lua: lua)
	}

	/// The content of `LocalStorage` for the next run of the access.
	func storage() throws(ScriptError) -> Data {
		try LocalStorage.save(from: lua.stack)
	}

	/// The state of one part of the API for this session, made on first use, for example the cookies of the run.
	func object<T: AnyObject>(_ make: () -> T) -> T {
		if let object = objects[ObjectIdentifier(T.self)] as? T { return object }
		let object = make()
		objects[ObjectIdentifier(T.self)] = object
		return object
	}

	/// The session of a Lua thread, for the functions that Swift implements.
	static func current(_ L: OpaquePointer?) -> HostSession {
		Unmanaged<HostSession>.fromOpaque(clua_context(L)!).takeUnretainedValue()
	}
}
