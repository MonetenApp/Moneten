import Foundation

/// The API version that this app offers to extensions as `MM.apiVersion`.
public let extensionAPIVersion = 1

/// A host name as a manifest lists it: exact, in lower case, without a wildcard, a scheme, a port, or a path.
public struct HostName: Hashable, Sendable, Codable, CustomStringConvertible {
	public let value: String

	public init?(exactly text: String) {
		let labels = text.split(separator: ".", omittingEmptySubsequences: false)
		let valid = labels.count >= 2 && labels.allSatisfy { label in
			!label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
				&& label.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
		}
		guard valid else { return nil }
		value = text
	}

	public var description: String { value }

	public init(from decoder: Decoder) throws {
		let text = try decoder.singleValueContainer().decode(String.self)
		guard let host = HostName(exactly: text) else {
			throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\(text) is not an exact host name"))
		}
		self = host
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(value)
	}
}

/// The manifest of an extension (ADR 0015): its Lua files, the hosts it contacts, the labels of the
/// login fields of each service, the kinds of data, the lowest API version, and the license.
public struct Manifest: Sendable, Equatable, Codable {
	/// The Lua files of a package folder in load order. A single file ignores it.
	public let files: [String]?
	/// Nil lets a file install ask the user before each new host. An empty list allows no host.
	public let hosts: [HostName]?
	/// The labels of the login fields by service name.
	public let services: [String: [String]]?
	public let kinds: [Kind]?
	public let apiVersion: Int?
	/// The SPDX identifier, for example "MIT".
	public let license: String?

	public enum Kind: String, Sendable, Codable {
		case balances, transactions, securities, statements
	}

	/// A catalog package must list everything the user sees before the install. A file install may omit any field.
	public enum Mode: Sendable {
		case file, catalog
	}

	/// Parses and checks a manifest. The messages are those that the list of extensions shows.
	public static func parse(_ data: Data, mode: Mode) throws(PackageProblem) -> Manifest {
		guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
			throw .invalidManifest("The manifest is not valid JSON of the expected form.")
		}
		var hosts: [HostName]?
		if let names = raw.hosts {
			hosts = try names.map { name throws(PackageProblem) in
				guard let host = HostName(exactly: name) else { throw .invalidManifest("A host name must be exact: \(name).") }
				return host
			}
		}
		var kinds: [Kind]?
		if let names = raw.kinds {
			kinds = try names.map { name throws(PackageProblem) in
				guard let kind = Kind(rawValue: name) else { throw .invalidManifest("Unknown kind of data: \(name).") }
				return kind
			}
		}
		if let needed = raw.apiVersion, needed > extensionAPIVersion {
			throw .needsNewerApp(apiVersion: needed)
		}
		let manifest = Manifest(files: raw.files, hosts: hosts, services: raw.services, kinds: kinds, apiVersion: raw.apiVersion, license: raw.license)
		if mode == .catalog {
			let missing = [("hosts", hosts == nil), ("services", raw.services == nil), ("kinds", kinds == nil),
				("apiVersion", raw.apiVersion == nil), ("license", raw.license == nil)].filter(\.1).map(\.0)
			if !missing.isEmpty { throw .invalidManifest("The manifest needs \(missing.joined(separator: ", ")).") }
		}
		return manifest
	}

	/// The manifest as the JSON has it, before the checks.
	private struct Raw: Decodable {
		let files: [String]?
		let hosts: [String]?
		let services: [String: [String]]?
		let kinds: [String]?
		let apiVersion: Int?
		let license: String?
	}
}
