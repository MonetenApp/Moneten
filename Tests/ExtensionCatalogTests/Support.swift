import CryptoKit
@testable import ExtensionCatalog
import Foundation

/// A made-up catalog: packages with their files, an index in the format of the catalog repository, and
/// signing keys that exist only in the tests.
struct TestCatalog {
	struct Package {
		var id = "example"
		var version = "1.0"
		var hosts = ["api.bank.example"]
		var login = [["label": "Username"], ["label": "Password", "secret": true] as [String: Any]]
		var script = "WebBanking { version = 1.0, services = {\"Example Bank\"} }\n"
		var status = "active"
		var note: String?
		var manifestFields: [String: Any] = [:]
		/// Fields in which the manifest of the index differs from the downloaded manifest.json.
		var indexManifestFields: [String: Any] = [:]

		var manifest: [String: Any] {
			[
				"id": id, "name": "Example Bank", "version": version, "description": "Fetches balances and transactions from the made-up Example Bank.",
				"files": ["Example.lua"], "hosts": hosts, "services": [["name": "Example Bank", "login": login]], "kinds": ["balances", "transactions"],
				"apiVersion": 1, "license": "MIT", "maintainer": ["name": "Moneten maintainers", "github": "example-maintainer"],
			].merging(manifestFields) { $1 }
		}

		var files: [String: Data] {
			[
				"Example.lua": Data(script.utf8), "LICENSE": Data("MIT License\n".utf8), "README.md": Data("# Example Bank\n".utf8),
				"manifest.json": try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
			]
		}

		var entry: [String: Any] {
			var entry: [String: Any] = ["id": id, "status": status, "manifest": manifest.merging(indexManifestFields) { $1 }, "files": files.keys.sorted().map { name in
				["path": name, "size": files[name]!.count, "sha256": sha256(files[name]!)] as [String: Any]
			}]
			if let note { entry["note"] = note }
			return entry
		}
	}

	static func index(version: Int, _ packages: [Package] = [Package()]) -> Data {
		let object: [String: Any] = ["formatVersion": 1, "version": version, "published": "2026-11-13T08:00:00Z", "extensions": packages.map(\.entry)]
		return try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
	}

	static func sha256(_ data: Data) -> String {
		sha256Hex(data)
	}
}

/// A key pair of the tests, with the public key in the PEM form that `openssl pkey -pubout` writes.
struct TestKey {
	let key = Curve25519.Signing.PrivateKey()

	var pem: String {
		// The DER prefix of an Ed25519 SubjectPublicKeyInfo, before the 32 bytes of the key.
		let der = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00]) + key.publicKey.rawRepresentation
		return "-----BEGIN PUBLIC KEY-----\n\(der.base64EncodedString())\n-----END PUBLIC KEY-----\n"
	}

	func sign(_ data: Data) -> Data {
		try! key.signature(for: data)
	}
}

/// The answers of a made-up catalog server, by path below the catalog address.
final class TestServer: @unchecked Sendable {
	private let lock = NSLock()
	private var files: [String: Data] = [:]
	private var failing: Set<String> = []
	private(set) var requested: [String] = []
	/// The most bytes that each request accepted.
	private(set) var limits: [String: Int] = [:]
	/// Runs before each answer, for example to remove a package during its download.
	var willAnswer: @Sendable (String) -> Void = { _ in }

	func publish(_ package: TestCatalog.Package) {
		lock.withLock {
			for (name, data) in package.files { files["\(package.id)/\(package.version)/\(name)"] = data }
		}
	}

	func replace(_ path: String, with data: Data) {
		lock.withLock { files[path] = data }
	}

	/// The request for this path fails as if the network were gone.
	func fail(_ path: String) {
		lock.withLock { _ = failing.insert(path) }
	}

	/// Answers as `CatalogSource` does: a body over the limit fails.
	var fetch: @Sendable (String, Int) async throws -> Data {
		{ [self] path, limit in
			willAnswer(path)
			return try lock.withLock {
				requested.append(path)
				limits[path] = limit
				guard !failing.contains(path), let data = files[path] else { throw URLError(.notConnectedToInternet) }
				guard data.count <= limit else { throw CatalogError.tooLarge(path) }
				return data
			}
		}
	}
}
