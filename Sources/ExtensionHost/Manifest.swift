import Foundation

/// The API version that this app offers to extensions as `MM.apiVersion`.
public let extensionAPIVersion = 1

/// A host name as a manifest lists it, by the pattern of `schema/manifest.schema.json` in the catalog
/// repository: exact and in lower case, without a wildcard, a scheme, a port, a path, or an IP address.
/// It is never a name under a special-use domain.
public struct HostName: Hashable, Sendable, Codable, CustomStringConvertible {
	public let value: String

	/// The special-use domains of RFC 6761 and RFC 8375, and `internal`, which ICANN keeps for private
	/// networks. A name under them reaches the Mac, the local network, or nowhere, and a person who reads
	/// it in the host dialog would not see that. `example` stays allowed, because the examples and
	/// fixtures use it, and no common tool points it at a local service, as tools for web developers do with `test`.
	static let specialUseDomains = ["localhost", "local", "home.arpa", "internal", "test", "invalid"]

	public init?(exactly text: String) {
		guard text.utf8.count <= 253, Pattern.isHostName(text), !Self.specialUseDomains.contains(where: { text == $0 || text.hasSuffix("." + $0) }) else { return nil }
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

/// The manifest of an extension (ADR 0015), in the shape of `schema/manifest.schema.json` of the
/// catalog repository. A catalog package needs every field. A file install may leave out any field,
/// and an extension without `hosts` asks the user before each new host.
public struct Manifest: Sendable, Equatable, Codable {
	public let id: String?
	public let name: String?
	public let version: String?
	public let description: String?
	/// The Lua files of a package folder in load order. A single file ignores it.
	public let files: [String]?
	public let hosts: [HostName]?
	public let services: [Service]?
	public let kinds: [Kind]?
	public let apiVersion: Int?
	/// The SPDX identifier, for example "MIT".
	public let license: String?
	public let maintainer: Maintainer?

	/// A service that the script registers, with the labels of its login fields in the order the script gets them.
	public struct Service: Sendable, Equatable, Codable {
		public let name: String
		public let login: [LoginField]
	}

	public struct LoginField: Sendable, Equatable, Codable {
		public let label: String
		/// The field hides what the user types.
		public let secret: Bool?
	}

	public struct Maintainer: Sendable, Equatable, Codable {
		public let name: String
		public let github: String
	}

	public enum Kind: String, Sendable, Codable {
		case balances, transactions, securities, statements
	}

	/// A catalog package must list everything the user sees before the install. A file install may omit any field.
	public enum Mode: Sendable {
		case file, catalog
	}

	static let licenses: Set = ["MIT", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Apache-2.0", "MPL-2.0", "LGPL-2.1-or-later", "LGPL-3.0-or-later", "GPL-3.0-or-later"]

	/// Parses and checks a manifest against the rules of the schema. The messages are those that the list of extensions shows.
	public static func parse(_ data: Data, mode: Mode) throws(PackageProblem) -> Manifest {
		guard String(data: data, encoding: .utf8) != nil, !data.contains(0), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw .invalidManifest("The manifest is not a JSON object in UTF-8.")
		}
		if let key = repeatedKey(in: data) {
			throw .invalidManifest("The manifest names the key \(key) twice.")
		}
		if let unknown = Set(object.keys).subtracting(CodingKeys.allNames).sorted().first {
			throw .invalidManifest("The manifest has the unknown field \(unknown).")
		}
		guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
			throw .invalidManifest("A field of the manifest has the wrong type.")
		}
		let manifest = try raw.checked()
		if let needed = manifest.apiVersion, needed > extensionAPIVersion {
			throw .needsNewerApp(apiVersion: needed)
		}
		if mode == .catalog, let missing = CodingKeys.allCases.first(where: { object[$0.rawValue] == nil || object[$0.rawValue] is NSNull }) {
			throw .invalidManifest("The manifest needs \(missing.rawValue).")
		}
		return manifest
	}

	/// The first key that one object of valid UTF-8 JSON names twice. `JSONSerialization` silently
	/// keeps one of the values, and the catalog checks refuse such a manifest, so the app refuses it too.
	static func repeatedKey(in data: Data) -> String? {
		let bytes = [UInt8](data)
		var objects: [Set<String>?] = []
		var expectsKey = false
		var index = 0
		while index < bytes.count {
			switch bytes[index] {
			case UInt8(ascii: "{"):
				objects.append([])
				expectsKey = true
			case UInt8(ascii: "["):
				objects.append(nil)
			case UInt8(ascii: "}"), UInt8(ascii: "]"):
				objects.removeLast()
			case UInt8(ascii: ","):
				expectsKey = objects.last.flatMap { $0 } != nil
			case UInt8(ascii: "\""):
				var end = index + 1
				while bytes[end] != UInt8(ascii: "\"") { end += bytes[end] == UInt8(ascii: "\\") ? 2 : 1 }
				if expectsKey {
					let key = (try? JSONSerialization.jsonObject(with: Data(bytes[index...end]), options: .fragmentsAllowed)) as? String ?? ""
					if objects[objects.count - 1]?.insert(key).inserted == false { return key }
					expectsKey = false
				}
				index = end
			default:
				break
			}
			index += 1
		}
		return nil
	}

	enum CodingKeys: String, CodingKey, CaseIterable {
		case id, name, version, description, files, hosts, services, kinds, apiVersion, license, maintainer

		static let allNames = Set(allCases.map(\.rawValue))
	}

	/// The manifest as the JSON has it, before the checks.
	private struct Raw: Decodable {
		let id, name, version, description, license: String?
		let files, hosts, kinds: [String]?
		let services: [Service]?
		let apiVersion: Int?
		let maintainer: Maintainer?

		func checked() throws(PackageProblem) -> Manifest {
			func require(_ ok: Bool, _ message: String) throws(PackageProblem) {
				if !ok { throw .invalidManifest(message) }
			}
			if let id { try require(id.count <= 64 && Pattern.isPackageID(id), "The id \(id) is not lower-case words joined by hyphens.") }
			if let name { try require((1...60).contains(name.count), "The name must have 1 to 60 characters.") }
			if let version { try require(Pattern.isVersion(version), "The version \(version) is not a number such as 2.31.") }
			if let description { try require((1...200).contains(description.count), "The description must have 1 to 200 characters.") }
			if let files {
				try require(!files.isEmpty && Set(files).count == files.count, "The manifest must list each Lua file once.")
				for file in files { try require(Pattern.isLuaFile(file), "\(file) is not a Lua file of the folder.") }
			}
			var hostNames: [HostName]?
			if let hosts {
				try require(!hosts.isEmpty && Set(hosts).count == hosts.count, "The manifest must list each host once, and at least one.")
				hostNames = try hosts.map { host throws(PackageProblem) in
					guard let name = HostName(exactly: host) else { throw .invalidManifest("A host name must be exact: \(host).") }
					return name
				}
			}
			if let services {
				try require(!services.isEmpty, "The manifest must list at least one service.")
				for service in services {
					try require((1...60).contains(service.name.count), "A service name must have 1 to 60 characters.")
					try require(service.login.count <= 4, "The service \(service.name) has more than four login fields.")
					for field in service.login { try require((1...40).contains(field.label.count), "A login label must have 1 to 40 characters.") }
				}
			}
			var kindValues: [Kind]?
			if let kinds {
				try require(!kinds.isEmpty && Set(kinds).count == kinds.count, "The manifest must list each kind of data once, and at least one.")
				kindValues = try kinds.map { kind throws(PackageProblem) in
					guard let value = Kind(rawValue: kind) else { throw .invalidManifest("Unknown kind of data: \(kind).") }
					return value
				}
			}
			if let apiVersion { try require(apiVersion >= 1, "The apiVersion must be 1 or higher.") }
			if let license { try require(Manifest.licenses.contains(license), "The license \(license) is not on the list of allowed licenses.") }
			if let maintainer {
				try require((1...100).contains(maintainer.name.count), "The maintainer needs a name.")
				try require(Pattern.isGitHubLogin(maintainer.github), "\(maintainer.github) is not a GitHub login.")
			}
			return Manifest(id: id, name: name, version: version, description: description, files: files, hosts: hostNames, services: services,
				kinds: kindValues, apiVersion: apiVersion, license: license, maintainer: maintainer)
		}
	}
}

/// The patterns of `schema/manifest.schema.json` as checks on bytes. A Swift `Regex` took about 60 µs for
/// a host name, so a catalog index of 200 packages missed its parse budget. `PatternTests` compares
/// each check with the regular expression of the schema.
public enum Pattern {
	private static let lowerDigits = Set("abcdefghijklmnopqrstuvwxyz0123456789".utf8)
	private static let letterDigits = lowerDigits.union("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
	private static let digits = Set("0123456789".utf8)
	private static let hyphen = UInt8(ascii: "-")

	/// `([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?`
	static func isHostName(_ text: String) -> Bool {
		let labels = text.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
		guard labels.count >= 2, let last = labels.last?.first, last >= UInt8(ascii: "a"), last <= UInt8(ascii: "z") else { return false }
		return labels.allSatisfy { label in
			(1...63).contains(label.count) && label.first != hyphen && label.last != hyphen && label.allSatisfy { lowerDigits.contains($0) || $0 == hyphen }
		}
	}

	/// `[a-z0-9]+(-[a-z0-9]+)*`
	public static func isPackageID(_ text: String) -> Bool {
		text.utf8.split(separator: hyphen, omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.allSatisfy(lowerDigits.contains) }
	}

	/// `[0-9]+(\.[0-9]+){0,2}`
	static func isVersion(_ text: String) -> Bool {
		let parts = text.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
		return parts.count <= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(digits.contains) }
	}

	/// `[A-Za-z0-9_-]+\.lua`
	static func isLuaFile(_ text: String) -> Bool {
		let bytes = Array(text.utf8)
		guard bytes.count > 4, bytes.suffix(4).elementsEqual(".lua".utf8) else { return false }
		return bytes.dropLast(4).allSatisfy { letterDigits.contains($0) || $0 == hyphen || $0 == UInt8(ascii: "_") }
	}

	/// `[A-Za-z0-9](-?[A-Za-z0-9]){0,38}`
	static func isGitHubLogin(_ text: String) -> Bool {
		let parts = text.utf8.split(separator: hyphen, omittingEmptySubsequences: false)
		let letters = parts.reduce(0) { $0 + $1.count }
		return (1...39).contains(letters) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(letterDigits.contains) }
	}
}
