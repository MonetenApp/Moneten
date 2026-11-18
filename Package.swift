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
		.library(name: "ExtensionConnector", targets: ["ExtensionConnector"]),
		.executable(name: "ext", targets: ["ext"]),
		.library(name: "ExtensionCatalog", targets: ["ExtensionCatalog"]),
	],
	dependencies: [
		// The fork of GRDB that Zetetic maintains links SQLCipher instead of the system SQLite.
		.package(url: "https://github.com/sqlcipher/GRDB.swift", exact: "7.12.0"),
	],
	targets: [
		.target(name: "Domain"),
		.target(name: "Storage", dependencies: ["Domain", "Import", .product(name: "GRDB", package: "GRDB.swift")]),
		.target(name: "Import", dependencies: ["Domain"]),
		.target(name: "Sync", dependencies: ["Domain"]),
		// ScriptedConnector, for the tests and for the previews and the debug harness of the app.
		.target(name: "SyncTesting", dependencies: ["Domain"]),
		// FinTSConnector, which runs the hbci4java helper of Tools/FinTSHelper (ADR 0014).
		.target(name: "FinTS", dependencies: ["Domain"]),
		// Lua from lua.org, unchanged, at the release of Sources/CLua/VERSION (scripts/vendor-lua.sh).
		.target(name: "CLua", exclude: ["VERSION", "VENDOR.sha256"], cSettings: [.define("LUA_USE_POSIX")]),
		// Runs web banking extensions, one host process per session (ADR 0015).
		// PublicSuffix/VERSION names the commit, SHA-256, and license of the Public Suffix List (scripts/vendor-public-suffix.sh).
		.target(name: "ExtensionHost", dependencies: ["Domain", "CLua"], exclude: ["PublicSuffix/VERSION"]),
		// The host process. The app embeds it from its own Xcode target with the sandbox entitlements.
		.executableTarget(name: "MonetenExtensionHost", dependencies: ["ExtensionHost"]),
		// Maps the entry points and tables of an extension to the sync model of the app.
		.target(name: "ExtensionConnector", dependencies: ["Domain", "ExtensionHost"]),
		// The command line tool for extension authors: run, record, and test (add-extension-developer-tools).
		.executableTarget(name: "ext", dependencies: ["Domain", "ExtensionHost", "ExtensionConnector"], path: "Tools/ext"),
		// Verifies the signed catalog index, installs its packages, and plans updates (ADR 0015).
		.target(name: "ExtensionCatalog", dependencies: ["Domain", "ExtensionHost", "Storage"]),
		// The time budget of the tests, which grows on a runner that GitHub hosts (issue #372), and IBAN literals.
		.target(name: "TestSupport", dependencies: ["Domain"], path: "Tests/TestSupport"),
		// A keychain file for the tests of the vault, so that no test writes the login Keychain (issue #399).
		.target(name: "StorageTestSupport", dependencies: ["Storage"], path: "Tests/StorageTestSupport"),
		.testTarget(name: "DomainTests", dependencies: ["Domain", "TestSupport"]),
		.testTarget(name: "StorageTests", dependencies: ["Storage", "StorageTestSupport", "TestSupport"]),
		.executableTarget(name: "ExportFileProbe", dependencies: ["Storage"], path: "Tests/ExportFileProbe", exclude: ["sync.c"]),
		.testTarget(name: "ImportTests", dependencies: ["Import", "TestSupport"]),
		.testTarget(name: "SyncTests", dependencies: ["Sync", "SyncTesting", "Storage", "StorageTestSupport", "TestSupport"]),
		// The tests read helper-lines.jsonl at its path, as the self-test of the helper writes it.
		.testTarget(name: "ExtensionHostTests", dependencies: ["ExtensionHost", "MonetenExtensionHost", "TestSupport"]),
		.testTarget(name: "ExtensionConnectorTests", dependencies: ["ExtensionConnector", "MonetenExtensionHost", "Storage", "StorageTestSupport", "TestSupport"]),
		// LocalBank holds the made-up bank on https://localhost that the tests of ext record start.
		.testTarget(name: "ExtToolTests", dependencies: ["ext", "ExtensionHost"], exclude: ["LocalBank"]),
		.testTarget(name: "ExtensionCatalogTests", dependencies: ["ExtensionCatalog", "Domain", "Storage", "StorageTestSupport", "TestSupport"]),
		.testTarget(name: "FinTSTests", dependencies: ["FinTS", "TestSupport"], exclude: ["helper-lines.jsonl"]),
	],
	swiftLanguageModes: [.v6]
)
