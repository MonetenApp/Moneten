// swift-tools-version:6.1
import PackageDescription

let package = Package(
	name: "MonetenMoneten",
	platforms: [.macOS(.v15)],
	products: [
		.executable(name: "MonetenMoneten", targets: ["App"]),
	],
	dependencies: [
		// The fork of GRDB that Zetetic maintains links SQLCipher instead of the system SQLite.
		.package(url: "https://github.com/sqlcipher/GRDB.swift", exact: "7.12.0"),
	],
	targets: [
		.target(name: "Domain"),
		.target(name: "Storage", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
		.target(name: "Import", dependencies: ["Domain"]),
		.executableTarget(name: "App", dependencies: ["Domain", "Storage", "Import"]),
		.testTarget(name: "DomainTests", dependencies: ["Domain"]),
		.testTarget(name: "StorageTests", dependencies: ["Storage"]),
		.testTarget(name: "ImportTests", dependencies: ["Import"]),
	],
	swiftLanguageModes: [.v6]
)
