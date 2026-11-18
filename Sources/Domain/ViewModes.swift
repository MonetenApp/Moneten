/// What a view shows above its list: nothing, a bar chart, or a pie chart.
public enum ViewMode: String, CaseIterable, Sendable {
	case list, barChart, pieChart
}

/// The view mode of the account views and the view mode of the category views. The app remembers them apart and
/// keeps both in the user defaults for the next launch, so a pie chart in a category does not follow the user into
/// an account (issue #493).
public struct ViewModes: Equatable, Sendable {
	public enum Kind: Sendable {
		/// An account or an account group, which draws the balance.
		case accounts
		/// A category, a category group, or a saved search, which draws the categories.
		case categories
	}

	private var accounts: ViewMode
	private var categories: ViewMode

	/// The key of a kind in the user defaults. The account views keep "viewMode", the key of the one mode of
	/// earlier versions, so the mode the user chose there stays.
	public static func key(of kind: Kind) -> String {
		switch kind {
		case .accounts: "viewMode"
		case .categories: "categoryViewMode"
		}
	}

	/// The modes that `stored` reads by key. A kind without a readable mode starts with the one mode of earlier
	/// versions, or else with the bar chart. A category mode taken from the earlier mode goes to `store` at once,
	/// because that key holds the account mode from the next change on.
	public init(stored: (String) -> String?, store: (_ key: String, _ value: String) -> Void) {
		let earlier = stored(Self.key(of: .accounts)).flatMap(ViewMode.init) ?? .barChart
		accounts = earlier
		if let own = stored(Self.key(of: .categories)).flatMap(ViewMode.init) {
			categories = own
		} else {
			categories = earlier
			store(Self.key(of: .categories), earlier.rawValue)
		}
	}

	public subscript(kind: Kind) -> ViewMode {
		kind == .accounts ? accounts : categories
	}

	/// Sets the mode of `kind` and hands it to `store` for the next launch.
	public mutating func set(_ mode: ViewMode, for kind: Kind, store: (_ key: String, _ value: String) -> Void) {
		if kind == .accounts { accounts = mode } else { categories = mode }
		store(Self.key(of: kind), mode.rawValue)
	}
}
