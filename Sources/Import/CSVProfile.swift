import Foundation

/// The settings of the CSV preview under a name, for the later files of the same bank.
public struct CSVProfile: Hashable, Sendable, Codable {
	public var name: String
	/// The column titles of the file that the profile was saved for.
	public var header: [String]
	public var layout: CSVLayout
	public var delimiter: String?
	/// The date order that the user chose in the question for a file whose dates fit both orders, with the
	/// columns that it answered. It is nil for a profile whose order came from the dates or from the date format
	/// control, and for every profile that a version without the question saved.
	public var dateOrderAnswer: DateOrderAnswer?

	public init(name: String, header: [String], layout: CSVLayout, delimiter: String? = nil, dateOrderAnswer: DateOrderAnswer? = nil) {
		self.name = name
		self.header = header
		self.layout = layout
		self.delimiter = delimiter
		self.dateOrderAnswer = dateOrderAnswer
	}

	/// Whether the order and the date columns of the layout are those that the user answered. An older version
	/// that changes either keeps the stored answer as an unknown field, and the answer then no longer counts.
	public var answersDateOrder: Bool { dateOrderAnswer?.answers(layout, header: header) == true }

	public enum Match: Hashable, Sendable {
		/// The header, delimiter and detected date order match, so the file imports without the preview.
		case same(CSVProfile)
		/// The header row changed, and the preview starts from the profile, with each field in the column
		/// of the title that the profile had for it.
		case changed(CSVProfile, CSVLayout)
		case none

		/// The date order that the user chose in the question, when the profile answers it for the date columns
		/// and the order that the start of the preview uses in `file`. A booking date in a column of another
		/// title, such as "Booking date" after "Date", asks again.
		public func answeredDateOrder(in file: CSVFile) -> DateOrder? {
			switch self {
			case let .same(profile): profile.dateOrderAnswer?.answers(profile.layout, header: file.header) == true ? profile.layout.dateOrder : nil
			case let .changed(profile, layout): profile.dateOrderAnswer?.answers(layout, header: file.header) == true ? layout.dateOrder : nil
			case .none: nil
			}
		}
	}

	/// The profile with the header row of the file, or else the one whose titles the file keeps for most of
	/// its fields. A profile that keeps fewer than half of its columns belongs to another bank, and one that
	/// misses a required field gives a worse start than `detected`. Columns that only `detected` assigns,
	/// such as a new "Kategorie", keep their field.
	/// A profile fits the dates of the file with the detected order, or with the order that the user chose in the
	/// question when the dates fit both orders. A date that the chosen order cannot read, such as "13/11/2026" for
	/// month first, makes the file fit only the other order, so the profile does not apply.
	public static func match(for file: CSVFile, in profiles: [CSVProfile], detected: CSVLayout) -> Match {
		// The orders of the file are read only for a profile with an answer, because a large file takes a while.
		var orders: [DateOrder]?
		func fits(_ profile: CSVProfile) -> Bool {
			if profile.layout.dateOrder == detected.dateOrder { return true }
			guard profile.answersDateOrder else { return false }
			if orders == nil { orders = (try? file.dateOrders(detected)) ?? [detected.dateOrder] }
			return orders!.contains(profile.layout.dateOrder)
		}
		// The newest profile of a header row wins, because the user saved it last.
		if let same = profiles.last(where: { $0.header == file.header && $0.delimiter == file.delimiter && fits($0) }) { return .same(same) }
		let moved = profiles.compactMap { profile -> (profile: CSVProfile, layout: CSVLayout, kept: Int)? in
			let previous = Dictionary(grouping: profile.header.indices, by: { profile.header[$0] })
			let positions = Dictionary(grouping: file.header.indices, by: { file.header[$0] })
			guard previous.allSatisfy({ title, columns in
				let count = positions[title]?.count ?? 0
				return title.isEmpty || count == columns.count || max(count, columns.count) <= 1
			}) else { return nil }
			var layout = profile.previewLayout(for: file)
			if profile.delimiter != file.delimiter || !fits(profile) { layout.dateOrder = detected.dateOrder }
			layout.columns = profile.layout.columns.compactMapValues { column in
				guard profile.header.indices.contains(column), !profile.header[column].isEmpty,
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

	/// The profile mappings and formats with the detected encoding of this file.
	public func previewLayout(for file: CSVFile) -> CSVLayout {
		var next = layout
		next.encoding = file.encoding
		return next
	}

	/// The transactions of a file with the header row of the profile, or nil when the file does not read in
	/// the profile, such as a month with an umlaut for a profile saved on a file in plain ASCII, or when every
	/// date fits day first and month first and the profile holds no order that the user chose, so that the preview opens.
	/// A file in another encoding than the profile, such as UTF-8 after a profile in Windows-1252, would read
	/// with wrong letters, so it opens the preview too, unless both encodings give the same text, as for a
	/// file in ASCII or for "ä" in ISO-8859-1 and Windows-1252.
	public func read(_ file: CSVFile, currency: String) throws -> TransactionFileImporter.Parsed? {
		guard file.encoding == layout.encoding || layout.encoding.decode(file.data) == file.encoding.decode(file.data) else { return nil }
		let reread: CSVFile
		do { reread = try file.with(layout.encoding) } catch is TransactionFileImporter.Failure { return nil }
		let preview = try reread.preview(layout, currency: currency)
		// A file whose dates fit both orders needs the answer of the user, which only a profile with a chosen order gives.
		return preview.problem == nil && (preview.ambiguousDate == nil || answersDateOrder) && !preview.transactions.isEmpty ? preview.parsed : nil
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

/// The date order that the user chose in the question of the preview, with the titles of the date columns that
/// it was for, so that a profile answers only for those columns.
public struct DateOrderAnswer: Hashable, Sendable, Codable {
	public var order: DateOrder
	/// The title of the booking date column.
	public var bookingDate: String
	/// The title of the value date column, or nil when none was mapped.
	public var valueDate: String?
}

extension DateOrderAnswer {
	/// The answer for the date columns of `layout` in a file with the titles `header`, or nil without a booking
	/// date column.
	public init?(order: DateOrder, layout: CSVLayout, header: [String]) {
		guard let booking = Self.title(layout.columns[.bookingDate], in: header) else { return nil }
		self.order = order
		bookingDate = booking
		valueDate = Self.title(layout.columns[.valueDate], in: header)
	}

	/// Whether the answer holds for `layout` in a file with the titles `header`: the same order, and date columns
	/// with the same titles.
	public func answers(_ layout: CSVLayout, header: [String]) -> Bool {
		order == layout.dateOrder && bookingDate == Self.title(layout.columns[.bookingDate], in: header)
			&& valueDate == Self.title(layout.columns[.valueDate], in: header)
	}

	private static func title(_ column: Int?, in header: [String]) -> String? {
		column.flatMap { header.indices.contains($0) ? header[$0] : nil }
	}
}

/// The question for the date order in the CSV preview. "Import" waits while every booking date fits both orders
/// and the user has not chosen one. A new date column asks again, because the answer was for the old one.
public struct DateOrderQuestion: Sendable {
	/// The date of the last preview that fits both orders. It stays while the file is read again, so that the
	/// question does not flicker.
	public private(set) var ambiguousDate: AmbiguousDate?
	/// The order that the user chose, or that a profile with an answer for these date columns gives.
	public var answer: DateOrder?

	public init(answer: DateOrder? = nil) {
		self.answer = answer
	}

	public mutating func read(_ preview: CSVPreview) {
		ambiguousDate = preview.ambiguousDate
	}

	/// Forgets the answer when `layout` maps another booking date or value date column than `previous`.
	public mutating func change(from previous: CSVLayout, to layout: CSVLayout) {
		if [CSVField.bookingDate, .valueDate].contains(where: { previous.columns[$0] != layout.columns[$0] }) { answer = nil }
	}

	/// Whether the order of `layout` is the answer. A change in the date format control after the answer is none.
	public func isAnswered(_ layout: CSVLayout) -> Bool { answer == layout.dateOrder }

	public func asks(_ layout: CSVLayout) -> Bool { ambiguousDate != nil && !isAnswered(layout) }

	public func allowsImport(_ preview: CSVPreview) -> Bool { preview.ambiguousDate == nil || isAnswered(preview.layout) }

	/// The answer that a profile saved from `layout` stores, or nil when the user did not choose its order in the question.
	public func profileAnswer(_ layout: CSVLayout, header: [String]) -> DateOrderAnswer? {
		isAnswered(layout) ? DateOrderAnswer(order: layout.dateOrder, layout: layout, header: header) : nil
	}
}
