import GRDB

extension EncodableRecord where Self: TableRecord {
	/// Inserts the record as a database of an older version stores it, with only the columns that its table has
	/// then. The record type of today writes every column, also one that a later migration adds.
	func insertOld(_ db: Database) throws {
		let columns = Set(try db.columns(in: Self.databaseTableName).map(\.name))
		let values = try databaseDictionary.filter { columns.contains($0.key) }
		let names = values.keys.map { "\"\($0)\"" }.joined(separator: ", ")
		let marks = Array(repeating: "?", count: values.count).joined(separator: ", ")
		try db.execute(sql: "INSERT INTO \"\(Self.databaseTableName)\" (\(names)) VALUES (\(marks))", arguments: StatementArguments(Array(values.values)))
	}
}
