// swift-tools-version:6.1
import PackageDescription

let package = Package(
	name: "Moneten",
	platforms: [.macOS(.v15)],
	products: [
		.library(name: "Domain", targets: ["Domain"]),
		.library(name: "Storage", targets: ["Storage"]),
		.library(name: "Import", targets: ["Import"]),
		.library(name: "Sync", targets: ["Sync"]),
		.library(name: "SyncTesting", targets: ["SyncTesting"]),
		.library(name: "FinTS", targets: ["FinTS"]),
		.library(name: "ExtensionHost", targets: ["ExtensionHost"]),
	],
	dependencies: [
		// The fork of GRDB that Zetetic maintains links SQLCipher instead of the system SQLite.
		.package(url: "https://github.com/sqlcipher/GRDB.swift", exact: "7.12.0"),
	],
	targets: [
		.target(name: "Domain"),
		.target(name: "Storage", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
		.target(name: "Import", dependencies: ["Domain"]),
		.target(name: "Sync", dependencies: ["Domain"]),
		// ScriptedConnector, for the tests and for the previews and the debug harness of the app.
		.target(name: "SyncTesting", dependencies: ["Domain"]),
		// FinTSConnector, which runs the hbci4java helper of Tools/FinTSHelper (ADR 0014).
		.target(name: "FinTS", dependencies: ["Domain"]),
		// Lua from lua.org, unchanged, at the release of Sources/CLua/VERSION (scripts/vendor-lua.sh).
		.target(name: "CLua", exclude: ["VERSION", "VENDOR.sha256"], cSettings: [.define("LUA_USE_POSIX")]),
		// Runs web banking extensions, one host process per session (ADR 0015).
		.target(name: "ExtensionHost", dependencies: ["Domain", "CLua"]),
		// The host process. The app embeds it from its own Xcode target with the sandbox entitlements.
		.executableTarget(name: "MonetenExtensionHost", dependencies: ["ExtensionHost"]),
		.testTarget(name: "DomainTests", dependencies: ["Domain"]),
		.testTarget(name: "StorageTests", dependencies: ["Storage"]),
		.testTarget(name: "ImportTests", dependencies: ["Import"]),
		.testTarget(name: "SyncTests", dependencies: ["Sync", "SyncTesting"]),
		// The tests read helper-lines.jsonl at its path, as the self-test of the helper writes it.
		.testTarget(name: "ExtensionHostTests", dependencies: ["ExtensionHost", "MonetenExtensionHost"]),
		.testTarget(name: "FinTSTests", dependencies: ["FinTS"], exclude: ["helper-lines.jsonl"]),
	],
	swiftLanguageModes: [.v6]
)
