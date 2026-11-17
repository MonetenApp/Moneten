import java.util.regex.Pattern;

/// The rules of the dialog with the FinTS server of ING, fints.ing.de (issue #235). Each bank group keeps its rules
/// in a file of its own. A host is the one that hbci4java keeps, with its path, such as "fints.ing.de/fints/".
///
/// ING sends the day on which it expects to book a pending MT942 row as the entry date of the ":61:" line, so
/// `PendingDates` takes the entry date of its pending rows, and the value date only without one. IngSelfTest checks it.
final class Ing {
	private Ing() {
	}

	/// Whether the host is the FinTS server of ING. The name must match in full, read as `SavingsBanks.name` reads it.
	static boolean ing(String host) {
		return SavingsBanks.name(host).equals("fints.ing.de");
	}

	/// The sentence with which ING refuses the FinTS login until the user logged in to its online banking, as two users
	/// of homebanking-hilfe.de recorded it in 2022: "9942: Bitte erneuern Sie ihre Authentifizierung. Einfach unter
	/// ING.de einloggen." ING asks for a login on its website at least every 90 days
	/// (https://www.ing.de/hilfe/log-in/fints/).
	static final Pattern RENEW_AUTHENTICATION = Pattern.compile("\\bbitte\\s+erneuern\\s+sie\\s+ihre\\s+authentifizierung\\b",
		Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

	/// Whether the answer of the bank at `host` says that ING locked the FinTS login until a login on its website: the
	/// code 9942 with that sentence. Any other text of 9942 is a wrong PIN, and the sentence with another code keeps the
	/// meaning of its code.
	static boolean websiteLoginNeeded(String host, String code, String text) {
		return "9942".equals(code) && text != null && ing(host) && RENEW_AUTHENTICATION.matcher(text).find();
	}
}
