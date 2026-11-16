import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Properties;
import java.util.regex.Matcher;
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

	/// The name of the server in `host`, without the path, the port, and one trailing dot, in lower case, or "" for null
	/// and for a name that is not one, such as an empty label or a port that is not a number.
	/// "FINTS.1822DIREKT.COM.:443/fints" is "fints.1822direkt.com". Sources/FinTS/SavingsBanks.swift does the same.
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
			if (!name.substring(colon + 1).matches("\\d+")) return "";
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

	/// Whether the host is a server of 1822direkt: "1822direkt.com" or a name that ends with ".1822direkt.com". Its MT940
	/// transactions go through `StatementJob`.
	static boolean direkt1822(String host) {
		String name = name(host);
		return name.equals("1822direkt.com") || name.endsWith(".1822direkt.com");
	}

	/// The text with which a Sparkasse answers when the user blocked the software under "Service > Persönliche
	/// Einstellungen > Kontozugriffe" in its online banking: "Kundenprodukt wurde vom Benutzer deaktiviert". The code
	/// of the answer is not known, so the text decides, and only the reported text counts: the product, or the account
	/// access, deactivated by the user. A card, a TAN method, or an access that the user blocked is no app that the user
	/// can unblock under "Kontozugriffe", so its text keeps the meaning of its code. The bank test of issue #11 may widen it.
	static final Pattern DEACTIVATED_BY_USER = Pattern.compile("\\b(kunden)?produkt\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b"
		+ "|\\bkontozugriff\\w*\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b", Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

	/// Whether the answer of the bank at `host` says that the user blocked the app in the online banking of a Sparkasse.
	static boolean appBlocked(String host, String text) {
		return text != null && savingsBank(host) && DEACTIVATED_BY_USER.matcher(text).find();
	}

	/// A booking tag (":61:" with its day, an optional entry day, and C, D, RC, or RD) or a closing balance tag (":62F:"
	/// with C or D, its day, and its currency) that follows other text on the same line. hbci4java finds a tag only at
	/// the start of a line. A text such as "Ref :61: xyz" in a purpose has no such shape.
	static final Pattern TAG_INSIDE_LINE = Pattern.compile("(?<=[^\\n])(?=:61:\\d{6}(\\d{4})?R?[CD]|:62F:[CD]\\d{6}[A-Z]{3})");
	static final Pattern OPENING = Pattern.compile("^:60[FM]:([CD])\\d{6}[A-Z]{3}(\\d+(,\\d*)?)");
	static final Pattern BOOKING = Pattern.compile("^:61:\\d{6}(\\d{4})?(R?)([CD])[A-Z]?(\\d+(,\\d*)?)");
	static final Pattern CLOSING = Pattern.compile("^:62[FM]:([CD])\\d{6}[A-Z]{3}(\\d+(,\\d*)?)");
	/// More places than this in one statement are not tried, because each set of them is a try.
	static final int MOST_PLACES = 10;

	/// The MT940 statement with a line break before the tags of `TAG_INSIDE_LINE` where the bank left it out, as
	/// 1822direkt does. A purpose may hold the same text, such as "Ref :61:2611151115D12,50NTRFNONREF", and a break
	/// there would add a booking that does not exist. So each statement of a day, up to its "-" line, keeps its text
	/// when its opening balance and its bookings add up to its closing balance. Otherwise the breaks go in at the one set
	/// of places with which they add up. With no such set, or with more than one, the statement stays as the bank sent
	/// it. The break is inserted, so no character of the purpose before the tag is lost.
	static String tagsOnOwnLines(String mt940) {
		StringBuilder out = new StringBuilder();
		Matcher end = Pattern.compile("\\r?\\n-(\\r?\\n|$)").matcher(mt940);
		int from = 0;
		while (end.find()) {
			out.append(repairedDay(mt940.substring(from, end.start()))).append(end.group());
			from = end.end();
		}
		return out.append(repairedDay(mt940.substring(from))).toString();
	}

	/// One statement of a day, with the breaks of the one set of places that makes it add up.
	static String repairedDay(String day) {
		if (balanced(day)) return day;
		List<Integer> places = new ArrayList<>();
		Matcher m = TAG_INSIDE_LINE.matcher(day);
		while (m.find()) places.add(m.start());
		if (places.isEmpty() || places.size() > MOST_PLACES) return day;
		String found = null;
		for (int set = 1; set < 1 << places.size(); set++) {
			StringBuilder candidate = new StringBuilder(day);
			for (int i = places.size() - 1; i >= 0; i--) if ((set & 1 << i) != 0) candidate.insert(places.get(i), "\r\n");
			if (!balanced(candidate.toString())) continue;
			if (found != null) return day;
			found = candidate.toString();
		}
		return found != null ? found : day;
	}

	/// Whether the opening balance and the bookings of the statement of a day add up to its closing balance, as
	/// hbci4java reads its lines. A statement without both balances does not add up.
	static boolean balanced(String day) {
		BigDecimal opening = null, closing = null, sum = BigDecimal.ZERO;
		for (String line : day.split("\\r?\\n")) {
			Matcher m;
			if ((m = OPENING.matcher(line)).find()) opening = signed(m.group(1), m.group(2));
			else if ((m = BOOKING.matcher(line)).find()) {
				BigDecimal amount = signed(m.group(3), m.group(4));
				sum = sum.add(m.group(2).isEmpty() ? amount : amount.negate());
			}
			else if ((m = CLOSING.matcher(line)).find()) closing = signed(m.group(1), m.group(2));
		}
		return opening != null && closing != null && opening.add(sum).compareTo(closing) == 0;
	}

	/// C is a credit and D a debit. A reversal of a booking (RC, RD) turns its sign, which `balanced` does.
	static BigDecimal signed(String mark, String amount) {
		BigDecimal value = new BigDecimal(amount.replace(',', '.').replaceAll("\\.$", ""));
		return mark.equals("D") ? value.negate() : value;
	}

	/// The transactions in MT940 of 1822direkt, whose statements need `tagsOnOwnLines`. hbci4java gives the answer of an
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

		/// Repairs the booked part of the answer under `header`, the part of this job. The pending part (MT942) has no
		/// balances that could confirm a break, so it stays as the bank sent it.
		static void repair(Properties data, String header) {
			String raw = data.getProperty(header + ".booked");
			if (raw != null) data.setProperty(header + ".booked", tagsOnOwnLines(raw));
		}
	}
}
