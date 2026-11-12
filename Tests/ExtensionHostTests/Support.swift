import Domain
@testable import ExtensionHost
import Foundation

/// Writes `files` into a new folder and returns its URL.
func folder(_ files: [String: String]) -> URL {
	let url = FileManager.default.temporaryDirectory.appending(path: "ExtensionHostTests-\(UUID().uuidString)")
	try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	for (name, text) in files {
		let file = url.appending(path: name)
		try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try! Data(text.utf8).write(to: file)
	}
	return url
}

/// `Demo.lua` installed from a file, with `Demo.json` next to it when `hosts` is set.
func demo(_ source: String, hosts: [String]? = nil) -> ExtensionPackage {
	var files = ["Demo.lua": source]
	if let hosts { files["Demo.json"] = String(decoding: try! JSONSerialization.data(withJSONObject: ["hosts": hosts]), as: UTF8.self) }
	return try! ExtensionPackage.load(from: folder(files).appending(path: "Demo.lua"))
}

/// A session of `package` whose network is `exchanges`. It records what reached the transport and what the user was asked.
final class Run {
	private(set) var sent: [String] = []
	private(set) var asked: [String] = []
	private(set) var printed: [String] = []
	var answer: HostDecision = .allowed
	private(set) var session: HostSession!

	init(_ package: ExtensionPackage, exchanges: [(String, String, Int, [String: String], String)] = [], decisions: [String: HostDecision] = [:]) {
		let fixture = try! decode(Fixture.self, ["exchanges": exchanges.map { method, url, status, headers, body in
			["request": ["method": method, "url": url], "response": ["status": status, "headers": headers, "body": body]]
		}])
		let transport = FixtureTransport(fixture) { [unowned self] in sent.append("\($0.method) \($0.url.absoluteString)") }
		session = HostSession(package: package, transport: transport, decisions: decisions,
			ask: { [unowned self] host in asked.append(host); return answer },
			log: { [unowned self] in printed.append($0) })
	}

	/// Loads the package and calls `function`. A failure returns its message as `.string("error: ...")`.
	func call(_ function: String) -> LuaValue {
		do {
			_ = try session.load()
			return try session.call(function)
		} catch {
			return .string("error: \(error.message)")
		}
	}
}

func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
	try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
}

/// The folder `Fixtures/extension-host` of the repository.
let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Fixtures/extension-host").standardized

/// The host process that the package manager built next to the tests.
let hostExecutable = Bundle(for: Run.self).bundleURL.deletingLastPathComponent().appending(path: "MonetenExtensionHost")
