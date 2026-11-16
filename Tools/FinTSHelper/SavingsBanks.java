import java.util.Locale;
import java.util.Properties;
import java.util.regex.Pattern;
import org.kapott.hbci.GV.GVKUmsAll;
import org.kapott.hbci.manager.HBCIHandler;
import org.kapott.hbci.status.HBCIMsgStatus;

/// The rules of the dialog with the savings banks on the FinTS servers of Finanz Informatik and with 1822direkt
/// (issue #240). Each bank group keeps its rules in a file of its own. A host is the one that hbci4java keeps, with
/// its path, such as "banking-hs6.s-fints-pt-hs.de/fints30". The assistant of the app decides its rules by the same
/// host test, in Sources/FinTS/SavingsBanks.swift.
final class SavingsBanks {
	private SavingsBanks() {
	}

	/// The name of the server in `host`, without the path and the port, in lower case, or "" for null.
	static String name(String host) {
		if (host == null) return "";
		String name = host.trim().toLowerCase(Locale.ROOT);
		int end = name.length();
		for (char c : new char[] {'/', '?', ':'}) {
			int i = name.indexOf(c);
			if (i >= 0 && i < end) end = i;
		}
		return name.substring(0, end);
	}

	/// Whether the host is a server of the savings banks: its label before ".de" starts with "s-fints-pt-" or is "s-hbci".
	static boolean savingsBank(String host) {
		String[] labels = name(host).split("\\.");
		if (labels.length < 2 || !labels[labels.length - 1].equals("de")) return false;
		String label = labels[labels.length - 2];
		return label.startsWith("s-fints-pt-") || label.equals("s-hbci");
	}

	/// Whether the host is a server of 1822direkt: "1822direkt.com" or a name that ends with ".1822direkt.com".
	static boolean direkt1822(String host) {
		String name = name(host);
		return name.equals("1822direkt.com") || name.endsWith(".1822direkt.com");
	}

	/// The text with which a Sparkasse answers when the user blocked the software under "Service > Persönliche
	/// Einstellungen > Kontozugriffe" in its online banking: "Kundenprodukt wurde vom Benutzer deaktiviert". The code
	/// of the answer is not known, so the text decides. Only a block by the user counts, because only the user can lift
	/// it there.
	static final Pattern DEACTIVATED_BY_USER = Pattern.compile("\\bvom\\s+(benutzer|kunden|nutzer)\\s+(deaktiviert|gesperrt)\\b",
		Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

	/// Whether the answer of the bank at `host` says that the user blocked the app in the online banking of a Sparkasse.
	static boolean appBlocked(String host, String text) {
		return text != null && savingsBank(host) && DEACTIVATED_BY_USER.matcher(text).find();
	}

	/// Whether the transactions of the server at `host` go through `StatementJob`.
	static boolean repairsStatements(String host) {
		return direkt1822(host);
	}

	/// The tags of a booking (":61:") and of the closing balance (":62F:") that follow other text on the same line,
	/// as 1822direkt sends them. hbci4java finds a tag only at the start of a line.
	static final Pattern TAG_INSIDE_LINE = Pattern.compile("(?<=[^\\n])(?=:61:|:62F:)");

	/// The MT940 statement with a line break before each booking and closing balance tag that starts inside a line. The
	/// break is inserted, so no character of the purpose before the tag is lost.
	static String tagsOnOwnLines(String mt940) {
		return TAG_INSIDE_LINE.matcher(mt940).replaceAll("\r\n");
	}

	/// The transactions in MT940 of a server whose statements need `tagsOnOwnLines`. hbci4java gives the answer of an
	/// order no dialog event, so the job is the only place that sees the statement before hbci4java reads it.
	static final class StatementJob extends GVKUmsAll {
		StatementJob(HBCIHandler handle) {
			super(handle);
		}

		@Override
		protected void extractResults(HBCIMsgStatus msgstatus, String header, int idx) {
			repair(msgstatus.getData(), header);
			super.extractResults(msgstatus, header, idx);
		}

		/// Repairs the booked and the pending part of the answer under `header`, the part of this job.
		static void repair(Properties data, String header) {
			for (String part : new String[] {".booked", ".notbooked"}) {
				String raw = data.getProperty(header + part);
				if (raw != null) data.setProperty(header + part, tagsOnOwnLines(raw));
			}
		}
	}
}
