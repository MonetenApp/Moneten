import Foundation
import GRDB
import Import

extension Store {
	public func csvProfiles(movingLegacyFrom defaults: UserDefaults? = nil) throws -> [CSVProfile] {
		if let defaults, let data = defaults.data(forKey: "csvProfiles") {
			let entries = try JSONSerialization.jsonObject(with: data) as? [Any]
			guard let entries else { throw CocoaError(.coderReadCorrupt) }
			let records = try entries.map { entry in
				let name = (entry as? [String: Any])?["name"] as? String ?? UUID().uuidString
				return (name, try JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed))
			}
			try queue.write { db in
				for (name, payload) in records {
					try db.execute(sql: "INSERT OR IGNORE INTO csvProfile(name, version, payload) VALUES (?, 1, ?)", arguments: [name, payload])
				}
			}
			defaults.removeObject(forKey: "csvProfiles")
		}
		return try queue.read { db in
			try Row.fetchAll(db, sql: "SELECT payload FROM csvProfile WHERE version = 1 ORDER BY rowid").compactMap { row in
				try? JSONDecoder().decode(CSVProfile.self, from: row["payload"])
			}
		}
	}

	public func saveCSVProfile(_ profile: CSVProfile, replacing old: String?) throws {
		let payload = try JSONEncoder().encode(profile)
		try queue.write { db in
			try db.execute(sql: "DELETE FROM csvProfile WHERE name = ? OR name = ?", arguments: [profile.name, old])
			try db.execute(sql: "INSERT INTO csvProfile(name, version, payload) VALUES (?, 1, ?)", arguments: [profile.name, payload])
		}
	}

	public func deleteCSVProfile(named name: String) throws {
		_ = try queue.write { db in try db.execute(sql: "DELETE FROM csvProfile WHERE name = ?", arguments: [name]) }
	}
}
