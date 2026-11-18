/// The input of the open sheet, kept in memory across a lock. A locked app shows no data, so the lock closes every
/// sheet. The sheet writes its input here at each change, the lock keeps the input of the sheet that it closes, and
/// after the unlock the same sheet shows again with that input (add-app-lock, "A locked app shows no data"). The input
/// never goes into the database or the preferences, so it ends with the app, and closing the database for good drops it.
public struct HeldSheet<Sheet: Equatable, Input> {
	/// The last input that a sheet wrote. It belongs to the sheet on screen only while that sheet is the same one.
	private var current: (sheet: Sheet, input: Input)?
	/// The sheet that the lock closed, until the unlock asks for it.
	private var held: (sheet: Sheet, input: Input)?
	/// The sheet that the unlock gave back, until it shows and takes its input.
	private var returning: (sheet: Sheet, input: Input)?

	public init() {}

	/// The sheet on screen wrote its input, when it opened or after a change.
	public mutating func record(_ input: Input, of sheet: Sheet) {
		current = (sheet, input)
	}

	/// The lock closes `open`. Its input stays only when it is the input that this sheet wrote, so a sheet without
	/// input of its own, or one that the user closed before, never comes back.
	public mutating func lock(closing open: Sheet?) {
		held = current.flatMap { $0.sheet == open ? $0 : nil }
		current = nil
		returning = nil
	}

	/// The sheet to show again after the unlock, once.
	public mutating func unlock() -> Sheet? {
		returning = held
		held = nil
		return returning?.sheet
	}

	/// The input of a sheet that shows again after the unlock, once. Any other opening of a sheet gets nil and starts
	/// from the stored values.
	public mutating func input(for sheet: Sheet) -> Input? {
		guard let returning, returning.sheet == sheet else { return nil }
		self.returning = nil
		return returning.input
	}

	/// The database closes for good, as after a change on disk, so no input of it may show again.
	public mutating func drop() {
		current = nil
		held = nil
		returning = nil
	}
}

extension HeldSheet: Sendable where Sheet: Sendable, Input: Sendable {}
