/// The kind of asset that a position holds. The raw values are stored in the database and in the complete export,
/// so they never change, and they are never shown: the app shows its own localized name of a class.
public enum AssetClass: String, CaseIterable, Codable, Sendable {
	case stocks
	case funds
	case bonds
	case realEstate
	case commodities
	case etfs
	case cryptocurrencies
	case others
}
