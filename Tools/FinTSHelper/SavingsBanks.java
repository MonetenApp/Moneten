import java.util.Locale;
import java.util.regex.Pattern;

/// The rules of the dialog with the savings banks on the FinTS servers of Finanz Informatik (issue #240). Each bank
/// group keeps its rules in a file of its own. A host is the one that hbci4java keeps, with its path, such as
/// "banking-hs6.s-fints-pt-hs.de/fints30". The assistant of the app decides its rules by the same host test, in
/// Sources/FinTS/SavingsBanks.swift.
final class SavingsBanks {
	private SavingsBanks() {
	}

	/// The name of the server in `host`, without the path, the port, and one trailing dot, in lower case, or "" for null
	/// and for a name that is not one, such as an empty label or a port that is not a number. An empty port, as in
	/// "host:/fints", is no port, as for `URL` in Swift. "BANKING-HS6.S-FINTS-PT-HS.DE.:443/fints30" is
	/// "banking-hs6.s-fints-pt-hs.de". Sources/FinTS/SavingsBanks.swift does the same.
	static String name(String host) {
		if (host == null) return "";
		String name = host.trim().toLowerCase(Locale.ROOT);
		int end = name.length();
		for (char c : new char[] {'/', '?'}) {
			int i = name.indexOf(c);
			if (i >= 0 && i < end) end = i;
		}
		name = name.substring(0, end);
		int colon = name.indexOf(':');
		if (colon >= 0) {
			if (!name.substring(colon + 1).matches("\\d*")) return "";
			name = name.substring(0, colon);
		}
		if (name.endsWith(".")) name = name.substring(0, name.length() - 1);
		return name.isEmpty() || name.startsWith(".") || name.endsWith(".") || name.contains("..") ? "" : name;
	}

	/// Whether the host is a server of the savings banks: its label before ".de" starts with "s-fints-pt-" or is "s-hbci".
	static boolean savingsBank(String host) {
		String[] labels = name(host).split("\\.");
		if (labels.length < 2 || !labels[labels.length - 1].equals("de")) return false;
		String label = labels[labels.length - 2];
		return label.startsWith("s-fints-pt-") || label.equals("s-hbci");
	}

	/// The text with which a Sparkasse answers when the user blocked the software under "Service > Persönliche
	/// Einstellungen > Kontozugriffe" in its online banking: "Kundenprodukt wurde vom Benutzer deaktiviert". The code
	/// of the answer is not known, so the text decides, and only the reported text counts: the "Kundenprodukt", or the
	/// account access, deactivated by the user. A card, a TAN method, or an access that the user blocked is nothing that
	/// the user can unblock under "Kontozugriffe", so its text keeps the meaning of its code. The bank test of issue #11
	/// may widen it.
	static final Pattern DEACTIVATED_BY_USER = Pattern.compile("\\bkundenprodukt\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b"
		+ "|\\bkontozugriff\\w*\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b", Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

	/// Whether the answer of the bank at `host` says that the user blocked the app in the online banking of a Sparkasse.
	static boolean appBlocked(String host, String text) {
		return text != null && savingsBank(host) && DEACTIVATED_BY_USER.matcher(text).find();
	}
}
