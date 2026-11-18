import Foundation

/// The rules of the assistant "Add Account" for flatexDEGIRO Bank and its brands flatex, DEGIRO, and ViTrade (#234). The bank
/// belongs to them by its three Bankleitzahlen. Their FinTS address is a correction of the bank list in
/// `BankData/corrections.properties`, because the bank list of hbci4java has an older address or none.
enum FlatexDegiro {
	static let bankCodes: Set<String> = ["10130800", "30330800", "76030800"]

	/// The name that the app shows for the three Bankleitzahlen, with the brands that customers search for.
	static let brandNames = Dictionary(uniqueKeysWithValues: bankCodes.map { ($0, "flatexDEGIRO Bank (flatex, DEGIRO, ViTrade)") })

	/// The FinTS server of the bank serves only flatex accounts, so a customer of DEGIRO or ViTrade gets a failed login there.
	static var note: String {
		String(localized: "The FinTS access of flatexDEGIRO Bank serves flatex accounts. DEGIRO and ViTrade offer no FinTS access, so their accounts cannot be added with FinTS and need an extension.")
	}
}

extension BankDirectory.Entry {
	/// What the bank requires or offers before the first login, which the login step shows above the fields: the note of the
	/// login hint, or the note of flatexDEGIRO Bank on the brands that its FinTS access serves.
	public var loginNote: String? {
		loginHint?.note ?? (FlatexDegiro.bankCodes.contains(code) ? FlatexDegiro.note : nil)
	}
}
