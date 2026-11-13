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
	let clock: SessionClock
	let entropy: Entropy
	let log: (String) -> Void
	let status: (String) -> Void
	/// Tells the app that the host still works, for its watchdog, for example while `MM.sleep` waits.
	let alive: () -> Void
	var registration: Registration?
	/// The stored transactions that `isKnownTransactionId` finds during the current `RefreshAccount`.
	var knownTransactions: [String: LuaValue] = [:]
	/// The last name that a script read from `MM`, `io`, or a connection and that the app does not offer.
	var lastMiss: Miss?
	private let storedData: Data?

	struct Miss: Equatable {
		/// For example "MM.parseSwiftMt".
		let name: String
		/// For example "Demo.lua:12:", as Lua starts its messages.
		let position: String
	}

	/// A package with a list of hosts reaches only those. Without one, `ask` waits for the user's
	/// answer about a new host; `decisions` holds the answers the app stored for this extension.
	/// `capture` fixes the clock and the random values for `ext record` and `ext test`; `random` gets each value of a recording,
	/// and `keyUse` the index of each one that the script used as a key, or nil for a key from no recorded value.
	/// `keyFingerprint` gets the SHA-256 of each AES or HMAC key of `ext record` and `ext test`.
	init(package: ExtensionPackage, transport: any Transport, decisions: [String: HostDecision] = [:], testHosts: Set<String> = [], memory: Int = HostLimits().memory,
		environment: HostEnvironment = .standard, storage: Data? = nil, capture: Capture? = nil, ask: @escaping (String) throws -> HostDecision,
		log: @escaping (String) -> Void, status: @escaping (String) -> Void = { _ in }, alive: @escaping () -> Void = {},
		random: @escaping (RandomValue) -> Void = { _ in }, keyUse: @escaping (Int?) -> Void = { _ in },
		keyFingerprint: @escaping (Data) -> Void = { _ in }) {
		self.package = package
		lua = LuaState(memory: memory)
		let clock = SessionClock(capture)
		self.clock = clock
		entropy = Entropy(capture, report: random, keyUse: keyUse, fingerprint: keyFingerprint)
		let rule: HostPolicy.Rule = package.manifest?.hosts.map { .listed(Set($0)) } ?? .askUser
		network = Network(policy: HostPolicy(extensionName: package.name, rule: rule, decisions: decisions, testHosts: testHosts, ask: ask), transport: transport, now: clock.now)
		self.environment = environment
		self.log = log
		self.status = status
		self.alive = alive
		storedData = storage
		clua_setcontext(lua.stack.L, Unmanaged.passUnretained(self).toOpaque())
		Environment.install(lua.stack, extensionName: package.name, environment: environment)
	}

	/// Restores `LocalStorage`, runs every file of the package in order in the same state, and returns the registration.
	func load() throws(ScriptError) -> Registration {
		try LocalStorage.restore(storedData, into: lua.stack)
		if clock.isFixed { try lua.run(Self.fixedClock, file: "ext") }
		for file in package.files { try lua.run(file.text, file: file.name) }
		guard let registration else { throw ScriptError("\(package.name) does not call WebBanking{}.") }
		return registration
	}

	/// Lets `os.time()` and `os.date()` read the clock of the session, as `MM.time` does.
	private static let fixedClock = """
		local time, date, now, floor = os.time, os.date, MM.time, math.floor
		os.time = function(fields) if fields == nil then return floor(now()) end return time(fields) end
		os.date = function(format, moment) return date(format, moment or floor(now())) end
		"""

	/// The entry points that the script defines as global functions.
	var entryPoints: Set<EntryPoint> {
		Set(EntryPoint.allCases.filter { lua.isFunction($0.rawValue) })
	}

	func call(_ entry: EntryCall) throws(ScriptError) -> LuaValue {
		try EntryPoints.call(entry, in: self, lua: lua)
	}

	/// The content of `LocalStorage` for the next run of the access.
	func storage() throws(ScriptError) -> Data {
		try LocalStorage.save(from: lua.stack)
	}

	/// The session of a Lua thread, for the functions that Swift implements.
	static func current(_ L: OpaquePointer?) -> HostSession {
		Unmanaged<HostSession>.fromOpaque(clua_context(L)!).takeUnretainedValue()
	}
}
