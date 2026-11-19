import Foundation
import GRDB
import Import

extension Store {
	/// A profile name that a stored record holds which this build cannot read, such as one with a newer
	/// payload version. Saving under it would replace that record and lose its settings.
	public struct CSVProfileNameTaken: Error, Equatable, CustomStringConvertible {
		public let name: String

		public init(name: String) { self.name = name }

		public var description: String {
			String(localized: "A saved profile named “\(name)” cannot be read by this version of Moneten. Choose another name.")
		}
	}

	public func csvProfiles() throws -> [CSVProfile] {
		return try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT version, payload FROM csvProfile ORDER BY rowid").compactMap(Self.readableProfile)
		}
	}

	/// The names of the stored profiles that `csvProfiles()` leaves out, which no save may take.
	public func unreadableCSVProfileNames() throws -> Set<String> {
		return try queue.read { db in
			Set(try Row.fetchAll(db, sql: "SELECT name, version, payload FROM csvProfile").filter { Self.readableProfile($0) == nil }.map { $0["name"] })
		}
	}

	private static func readableProfile(_ row: Row) -> CSVProfile? {
		guard row["version"] as Int == 1 else { return nil }
		return try? JSONDecoder().decode(CSVProfile.self, from: row["payload"])
	}

	public func saveCSVProfile(_ profile: CSVProfile, replacing old: String?) throws {
		let encoded = try JSONEncoder().encode(profile)
		try write { db in
			if let taken = try Row.fetchOne(db, sql: "SELECT version, payload FROM csvProfile WHERE name = ?", arguments: [profile.name]),
				Self.readableProfile(taken) == nil {
				throw CSVProfileNameTaken(name: profile.name)
			}
			// Only a readable record gives its unknown fields to the new one, and only such a record is replaced.
			let previous: Data? = try Row.fetchOne(db, sql: "SELECT version, payload FROM csvProfile WHERE name = ?", arguments: [old ?? profile.name])
				.flatMap { Self.readableProfile($0) == nil ? nil : $0["payload"] }
			let payload = try Self.profilePayload(encoded, preserving: previous)
			try db.execute(sql: "DELETE FROM csvProfile WHERE name = ? OR name = ?", arguments: [profile.name, previous == nil ? nil : old])
			try db.execute(sql: "INSERT INTO csvProfile(name, version, payload) VALUES (?, 1, ?)", arguments: [profile.name, payload])
		}
	}

	private static func profilePayload(_ encoded: Data, preserving previous: Data?) throws -> Data {
		guard let previous, var saved = (try? JSONSerialization.jsonObject(with: previous)) as? [String: Any] else { return encoded }
		let current = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
		var layout = saved["layout"] as? [String: Any] ?? [:]
		let nextLayout = current["layout"] as! [String: Any]
		var columns = layout["columns"] as? [String: Any] ?? [:]
		columns = columns.filter { CSVField(rawValue: $0.key) == nil }
		columns.merge(nextLayout["columns"] as! [String: Any]) { _, new in new }
		layout.removeValue(forKey: "decimalMark")
		layout.merge(nextLayout) { _, new in new }
		layout["columns"] = columns
		saved.removeValue(forKey: "delimiter")
		// A profile saved without a chosen date order must not keep the answer of the record that it replaces.
		saved.removeValue(forKey: "dateOrderAnswer")
		saved.merge(current) { _, new in new }
		saved["layout"] = layout
		return try JSONSerialization.data(withJSONObject: saved, options: .sortedKeys)
	}

	public func deleteCSVProfile(named name: String) throws {
		_ = try write { db in try db.execute(sql: "DELETE FROM csvProfile WHERE name = ?", arguments: [name]) }
	}
}
