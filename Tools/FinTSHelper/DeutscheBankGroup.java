import java.util.Locale;
import java.util.Set;

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

	/// Whether the host is a server of Deutsche Bank, Postbank, or norisbank, as `FinTSServer.isDeutscheBankGroup` decides.
	static boolean group(String host) {
		String name = SavingsBanks.name(host);
		return name.endsWith(".deutsche-bank.de") || name.endsWith(".postbank.de") || name.endsWith(".norisbank.de");
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

	/// The login name as the group expects it: without any Unicode white space, as Character.isWhitespace in
	/// FinTSServer.loginName of the app removes it.
	static String withoutSpaces(String name) {
		return name.replaceAll("(?U)\\s", "");
	}

	/// The codes with which the group answers a login that a new login replaced, such as the old branch and account
	/// number after the user chose a Deutsche Bank ID of their own.
	static final Set<String> REPLACED_LOGIN_CODES = Set.of("9940", "3960");
	/// The request of that answer to log in to the online banking or to contact the support, in lower case.
	static final String REPLACED_LOGIN_TEXT = "melden sie sich im online-banking an oder kontaktieren den support";

	/// Whether the answer of the bank at `host` says that a new login replaced the login of the access. Only the code with
	/// that request counts, because the codes alone also mean other things. 3960 is a warning, which ends the dialog as
	/// an error, because no order works with the old login.
	static boolean loginReplaced(String host, String code, String text) {
		return code != null && text != null && REPLACED_LOGIN_CODES.contains(code) && group(host)
			&& text.toLowerCase(Locale.ROOT).contains(REPLACED_LOGIN_TEXT);
	}
}
