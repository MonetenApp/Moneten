import Foundation
import GRDB
import Import

extension Store {
	public func csvProfiles() throws -> [CSVProfile] {
		return try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT payload FROM csvProfile WHERE version = 1 ORDER BY rowid").compactMap { row in
				try? JSONDecoder().decode(CSVProfile.self, from: row["payload"])
			}
		}
	}

	public func saveCSVProfile(_ profile: CSVProfile, replacing old: String?) throws {
		let encoded = try JSONEncoder().encode(profile)
		try write { db in
			let previous = try Data.fetchOne(db, sql: "SELECT payload FROM csvProfile WHERE name = ? AND version = 1", arguments: [old ?? profile.name])
			let payload = try Self.profilePayload(encoded, preserving: previous)
			try db.execute(sql: "DELETE FROM csvProfile WHERE name = ? OR name = ?", arguments: [profile.name, old])
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
		saved.merge(current) { _, new in new }
		saved["layout"] = layout
		return try JSONSerialization.data(withJSONObject: saved, options: .sortedKeys)
	}

	public func deleteCSVProfile(named name: String) throws {
		_ = try write { db in try db.execute(sql: "DELETE FROM csvProfile WHERE name = ?", arguments: [name]) }
	}
}
