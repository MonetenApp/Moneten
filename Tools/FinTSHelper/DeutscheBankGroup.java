import java.util.Locale;

/// The rules of the dialog with the Deutsche Bank group: Deutsche Bank, Postbank with its business brand FYRST, and
/// norisbank (issue #231). Each bank group keeps its rules in a file of its own. A host is the one that hbci4java keeps,
/// with its path, such as "hbci.postbank.de/banking/hbci.do". The app decides its rules by the same host test, in
/// Sources/Domain/Sync/DeutscheBankGroup.swift.
final class DeutscheBankGroup {
	private DeutscheBankGroup() {
	}

	/// The booking text of a card payment at Postbank.
	static final String CARD_PAYMENT = "kartenzahlung";

	/// Whether the host is a server of Postbank: its name, as `SavingsBanks.name` reads it, ends in ".postbank.de".
	static boolean postbank(String host) {
		return SavingsBanks.name(host).endsWith(".postbank.de");
	}

	/// The name of a row. Postbank may send a pending card payment without a name, with the name in the purpose, as in
	/// "Kartenzahlung / Buchhandlung Beispiel". Such a row takes the text after the first " / " as its name, or the whole
	/// purpose when it is one word, such as "PayPal". A name lets the pending row pair with the booked row that follows it.
	/// Every other row keeps `name`.
	static String name(String host, boolean pending, String name, String bookingText, String purpose) {
		if (!pending || name != null || purpose == null || !postbank(host)) return name;
		if (bookingText == null || !bookingText.trim().toLowerCase(Locale.ROOT).equals(CARD_PAYMENT)) return name;
		String text = purpose.trim();
		int slash = text.indexOf(" / ");
		if (slash >= 0) {
			String after = text.substring(slash + 3).trim();
			return after.isEmpty() ? null : after;
		}
		boolean oneWord = !text.isEmpty() && text.codePoints().noneMatch(Character::isWhitespace);
		return oneWord && !text.toLowerCase(Locale.ROOT).equals(CARD_PAYMENT) ? text : null;
	}
}
