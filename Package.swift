// swift-tools-version:6.1
import PackageDescription

let package = Package(
	name: "Moneten",
	platforms: [.macOS(.v15)],
	products: [
		.library(name: "Domain", targets: ["Domain"]),
		.library(name: "Storage", targets: ["Storage"]),
		.library(name: "Import", targets: ["Import"]),
	],
	dependencies: [
		// The fork of GRDB that Zetetic maintains links SQLCipher instead of the system SQLite.
		.package(url: "https://github.com/sqlcipher/GRDB.swift", exact: "7.12.0"),
	],
	targets: [
		.target(name: "Domain"),
		.target(name: "Storage", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
		.target(name: "Import", dependencies: ["Domain"]),
		.testTarget(name: "DomainTests", dependencies: ["Domain"]),
		.testTarget(name: "StorageTests", dependencies: ["Storage"]),
		.testTarget(name: "ImportTests", dependencies: ["Import"]),
	],
	swiftLanguageModes: [.v6]
)
