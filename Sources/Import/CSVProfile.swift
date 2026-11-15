import Foundation

/// The settings of the CSV preview under a name, for the later files of the same bank.
public struct CSVProfile: Hashable, Sendable, Codable {
	public var name: String
	/// The column titles of the file that the profile was saved for.
	public var header: [String]
	public var layout: CSVLayout

	public init(name: String, header: [String], layout: CSVLayout) {
		self.name = name
		self.header = header
		self.layout = layout
	}

	public enum Match: Hashable, Sendable {
		/// The file has the header row of the profile, so it imports without the preview.
		case same(CSVProfile)
		/// The header row changed, and the preview starts from the profile, with each field in the column
		/// of the title that the profile had for it.
		case changed(CSVProfile, CSVLayout)
		case none
	}

	/// The profile with the header row of the file, or else the one whose titles the file keeps for most of
	/// its fields. A profile that keeps fewer than half of its columns belongs to another bank, and one that
	/// misses a required field gives a worse start than `detected`. Columns that only `detected` assigns,
	/// such as a new "Kategorie", keep their field.
	public static func match(for file: CSVFile, in profiles: [CSVProfile], detected: CSVLayout) -> Match {
		// The newest profile of a header row wins, because the user saved it last.
		if let same = profiles.last(where: { $0.header == file.header }) { return .same(same) }
		let moved = profiles.compactMap { profile -> (profile: CSVProfile, layout: CSVLayout, kept: Int)? in
			let previous = Dictionary(grouping: profile.header.indices, by: { profile.header[$0] })
			let positions = Dictionary(grouping: file.header.indices, by: { file.header[$0] })
			guard previous.allSatisfy({ title, columns in
				let count = positions[title]?.count ?? 0
				return count == columns.count || max(count, columns.count) <= 1
			}) else { return nil }
			var layout = profile.previewLayout(for: file)
			layout.columns = profile.layout.columns.compactMapValues { column in
				guard profile.header.indices.contains(column),
					let occurrence = previous[profile.header[column]]?.firstIndex(of: column),
					let moved = positions[profile.header[column]], moved.indices.contains(occurrence) else { return nil }
				return moved[occurrence]
			}
			let kept = layout.columns.count
			guard kept * 2 >= profile.layout.columns.count else { return nil }
			for (field, column) in detected.columns where layout.columns[field] == nil && !layout.columns.values.contains(column) {
				layout.columns[field] = column
			}
			return layout.missing.isEmpty ? (profile, layout, kept) : nil
		}
		guard let best = moved.max(by: { $0.kept < $1.kept }) else { return .none }
		return .changed(best.profile, best.layout)
	}

	/// The settings a profile supplies to the preview of this file.
	public func previewLayout(for file: CSVFile) -> CSVLayout { layout }

	/// The transactions of a file with the header row of the profile, or nil when the file does not read in
	/// the profile, such as a month with an umlaut for a profile saved on a file in plain ASCII, so that the
	/// preview opens.
	/// A file in another encoding than the profile, such as UTF-8 after a profile in Windows-1252, would read
	/// with wrong letters, so it opens the preview too, unless both encodings give the same text, as for a
	/// file in ASCII or for "ä" in ISO-8859-1 and Windows-1252.
	public func read(_ file: CSVFile, currency: String) throws -> TransactionFileImporter.Parsed? {
		guard file.encoding == layout.encoding || layout.encoding.decode(file.data) == file.encoding.decode(file.data) else { return nil }
		let reread: CSVFile
		do { reread = try file.with(layout.encoding) } catch is TransactionFileImporter.Failure { return nil }
		let preview = try reread.preview(layout, currency: currency)
		return preview.problem == nil && !preview.transactions.isEmpty ? preview.parsed : nil
	}

	/// The stored profiles that still decode, so that one that a later version cannot read does not take the others with it.
	public static func list(from data: Data) -> [CSVProfile] {
		struct Lenient: Decodable {
			let profile: CSVProfile?
			init(from decoder: Decoder) throws { profile = try? CSVProfile(from: decoder) }
		}
		return ((try? JSONDecoder().decode([Lenient].self, from: data)) ?? []).compactMap(\.profile)
	}
}

extension [CSVProfile] {
	/// Saves the profile in place of the one with its name, and of `old` when the user renamed it.
	public mutating func save(_ profile: CSVProfile, replacing old: String?) {
		removeAll { $0.name == profile.name || $0.name == old }
		append(profile)
	}

	/// Saves the settings of the preview. A new name renames the profile that the file `matched` only while
	/// its settings are the `applied` ones; one that the user picked, or "None", is only a starting point.
	public mutating func save(_ profile: CSVProfile, matched: String?, applied: String?) {
		save(profile, replacing: applied == matched ? matched : nil)
	}
}
