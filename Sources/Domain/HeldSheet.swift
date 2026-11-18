/// The input of the open sheet, kept in memory across a lock. A locked app shows no data, so the lock closes every
/// sheet. The sheet writes its input here at each change, the lock keeps the input of the sheet that it closes, and
/// after the unlock the same sheet shows again with that input (add-app-lock, "A locked app shows no data"). The input
/// never goes into the database or the preferences, so it ends with the app.
///
/// The input belongs to the database that was open at the lock, which `Database` names. It comes back only when the
/// unlock opens that same database, so a backup that took its place while the app was locked never gets it.
public struct HeldSheet<Sheet: Equatable, Input, Database: Equatable> {
	/// The last input that a sheet wrote. It belongs to the sheet on screen only while that sheet is the same one.
	private var current: (sheet: Sheet, input: Input)?
	/// The sheet that the lock closed and the database that was open, until the unlock asks for it.
	private var held: (sheet: Sheet, input: Input, database: Database)?
	/// The sheet that the unlock gave back, until it closes.
	private var returning: (sheet: Sheet, input: Input)?

	public init() {}

	/// The sheet on screen wrote its input, when it opened or after a change.
	public mutating func record(_ input: Input, of sheet: Sheet) {
		current = (sheet, input)
	}

	/// The lock closes `open` in `database`. The input stays only when it is the input that this sheet wrote, so a
	/// sheet without input of its own, or one that the user closed before, never comes back. A database that the app
	/// cannot name keeps nothing.
	public mutating func lock(closing open: Sheet?, database: Database?) {
		held = nil
		if let current, current.sheet == open, let database { held = (current.sheet, current.input, database) }
		current = nil
		returning = nil
	}

	/// The sheet to show again after the unlock of `database`, once. Any other opening, such as one of a database that
	/// took the place of the locked one, or a launch, which names no database, drops the held input.
	public mutating func unlock(database: Database?) -> Sheet? {
		returning = nil
		if let held, let database, held.database == database { returning = (held.sheet, held.input) }
		held = nil
		return returning?.sheet
	}

	/// The input that the unlock gave back, before its sheet shows, without taking it.
	public var returningInput: Input? { returning?.input }

	/// The input of a sheet that shows again after the unlock, until that sheet closes. SwiftUI can show the sheet more
	/// than once after the unlock, the last time with new state, so each appearance gets the input. Any other opening of
	/// a sheet gets nil and starts from the stored values.
	public func input(for sheet: Sheet) -> Input? {
		guard let returning, returning.sheet == sheet else { return nil }
		return returning.input
	}

	/// `sheet` closed, so a later opening of it starts from the stored values.
	public mutating func close(_ sheet: Sheet) {
		if returning?.sheet == sheet { returning = nil }
	}

	/// The input of a sheet as the type that the sheet wrote. A sheet whose input is optional gets nil when nothing
	/// returns, never an input of nil, which would replace the values that it loaded.
	public func input<Wanted>(for sheet: Sheet, as type: Wanted.Type) -> Wanted? {
		guard let input = input(for: sheet) else { return nil }
		return input as? Wanted
	}

	/// The database closes for good, as after a change on disk, so no input of it may show again.
	public mutating func drop() {
		current = nil
		held = nil
		returning = nil
	}
}

extension HeldSheet: Sendable where Sheet: Sendable, Input: Sendable, Database: Sendable {}
