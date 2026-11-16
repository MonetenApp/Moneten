import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.function.IntPredicate;
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
	/// and for a name that is not one, such as an empty label or a port that is not a number. An empty port, as in
	/// "host:/fints", is no port, as for `URL` in Swift.
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

	/// Whether the host is a server of 1822direkt: "1822direkt.com" or a name that ends with ".1822direkt.com". Its MT940
	/// transactions go through `StatementJob`.
	static boolean direkt1822(String host) {
		String name = name(host);
		return name.equals("1822direkt.com") || name.endsWith(".1822direkt.com");
	}

	/// The text with which a Sparkasse answers when the user blocked the software under "Service > Persönliche
	/// Einstellungen > Kontozugriffe" in its online banking: "Kundenprodukt wurde vom Benutzer deaktiviert". The code
	/// of the answer is not known, so the text decides, and only the reported text counts: the "Kundenprodukt", or the
	/// account access, deactivated by the user. A card, a TAN method, or an access that the user blocked is no app that the user
	/// can unblock under "Kontozugriffe", so its text keeps the meaning of its code. The bank test of issue #11 may widen it.
	static final Pattern DEACTIVATED_BY_USER = Pattern.compile("\\bkundenprodukt\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b"
		+ "|\\bkontozugriff\\w*\\b[^.!?]*\\bvom\\s+benutzer\\s+deaktiviert\\b", Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

	/// Whether the answer of the bank at `host` says that the user blocked the app in the online banking of a Sparkasse.
	static boolean appBlocked(String host, String text) {
		return text != null && savingsBank(host) && DEACTIVATED_BY_USER.matcher(text).find();
	}

	/// A booking tag (":61:" with its day, an optional entry day, and C, D, RC, or RD) or a closing balance tag (":62F:"
	/// with C or D, its day, and its currency) that follows other text on the same line. hbci4java finds a tag only at
	/// the start of a line. A text such as "Ref :61: xyz" in a purpose has no such shape.
	static final Pattern TAG_INSIDE_LINE = Pattern.compile("(?<=[^\\n])(?=:61:\\d{6}(\\d{4})?R?[CD]|:62F:[CD]\\d{6}[A-Z]{3})");
	/// A whole balance line: C or D, the day, the currency, and an amount of digits with one comma and nothing after.
	static final Pattern BALANCE = Pattern.compile(":6([02])[FM]:([CD])\\d{6}([A-Z]{3})(\\d{1,15},\\d{0,2})");
	/// The start of a booking line: the day, an optional entry day, C, D, RC, or RD, an optional funds code, and an amount
	/// of digits with one comma, which the code of the transaction type (N, F, or S and three characters) ends.
	static final Pattern BOOKING = Pattern.compile(":61:\\d{6}(\\d{4})?(R?)([CD])([A-Z])?(\\d{1,15},\\d{0,2})[NFS][A-Z0-9]{3}");
	/// More places than this are only tried all together, because each set of them is a try.
	static final int MOST_PLACES = 10;
	/// A statement of a day longer than this stays as the bank sent it, so that a hostile answer costs no time.
	static final int MOST_CHARACTERS = 1 << 20;

	/// The MT940 statement with a line break before the tags of `TAG_INSIDE_LINE` where the bank left it out, as
	/// 1822direkt does. A purpose may hold the same text, such as "Ref :61:2611151115D12,50NTRFNONREF", and a break
	/// there would add a booking that does not exist. So each statement of a day, up to its "-" line, decides with its
	/// balances (`repairedDay`). The break is inserted, so no character of the purpose before the tag is lost.
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

	/// A balance or a booking of a statement, at `place` in the text, with its signed amount. A place inside a line is
	/// where a break would go.
	record Entry(int place, boolean balance, boolean closing, String currency, BigDecimal amount) {
	}

	/// One statement of a day. It stays as the bank sent it when its opening balance and the bookings at the start of
	/// a line add up to its closing balance. Otherwise the breaks go in at all places when that adds up, or else at the
	/// one set of at most `MOST_PLACES` places that adds up. Every balance and booking must read in full, in the
	/// currency of the opening balance. A statement that stays as sent although it has places gets one line in the
	/// diagnostics with the count of its places and the reason, without amounts or text.
	static String repairedDay(String day) {
		Matcher m = TAG_INSIDE_LINE.matcher(day);
		if (!m.find()) return day;
		if (day.length() > MOST_CHARACTERS) return kept(day, -1, "is longer than " + MOST_CHARACTERS + " characters");
		List<Entry> lines = new ArrayList<>(), places = new ArrayList<>();
		int lineStart = 0;
		while (lineStart <= day.length()) {
			int lineEnd = day.indexOf('\n', lineStart);
			if (lineEnd < 0) lineEnd = day.length();
			String line = day.substring(lineStart, lineEnd > lineStart && day.charAt(lineEnd - 1) == '\r' ? lineEnd - 1 : lineEnd);
			if (line.startsWith(":60") || line.startsWith(":61:") || line.startsWith(":62")) {
				Entry e = entry(line, lineStart);
				if (e == null) return kept(day, -1, "has a balance or a booking that does not read");
				lines.add(e);
			}
			lineStart = lineEnd + 1;
		}
		do {
			int lineEnd = day.indexOf('\n', m.start());
			String rest = day.substring(m.start(), lineEnd < 0 ? day.length() : lineEnd).replaceAll("\r$", "");
			// A text in the shape of a tag whose amount does not read is a purpose.
			Entry e = entry(rest, m.start());
			if (e != null) places.add(e);
		} while (m.find());
		if (places.isEmpty()) return day;
		Entry opening = null, closing = null;
		BigDecimal sum = BigDecimal.ZERO;
		int lastBooking = -1;
		for (Entry e : lines) {
			if (e.balance() && !e.closing()) {
				if (opening != null || !lines.isEmpty() && lines.get(0) != e) return kept(day, places.size(), "has no single opening balance before its bookings");
				opening = e;
			} else if (e.closing()) {
				if (closing != null) return kept(day, places.size(), "has two closing balances");
				closing = e;
			} else {
				if (closing != null) return kept(day, places.size(), "has a booking after its closing balance");
				sum = sum.add(e.amount());
				lastBooking = e.place();
			}
		}
		if (opening == null) return kept(day, places.size(), "has no opening balance");
		int openingPlace = opening.place();
		places.removeIf(e -> e.place() < openingPlace);
		if (places.isEmpty()) return day;
		String currency = opening.currency();
		for (Entry e : lines) {
			if (!fits(e, currency)) return kept(day, places.size(), "has a balance or a booking in another currency");
		}
		if (closing != null && opening.amount().add(sum).compareTo(closing.amount()) == 0) return day;
		for (Entry e : places) {
			if (!fits(e, currency)) return kept(day, places.size(), "has a place in another currency");
		}
		BigDecimal start = opening.amount().add(sum);
		// A bank that leaves out every break, also in a statement of many days, gets all of them in one try.
		if (adds(places, i -> true, start, closing, lastBooking)) return withBreaks(day, places, i -> true);
		if (places.size() > MOST_PLACES) return kept(day, places.size(), "has more than " + MOST_PLACES + " places, and not all of them add up");
		int found = -1;
		for (int set = 1; set < (1 << places.size()) - 1; set++) {
			int chosen = set;
			if (!adds(places, i -> (chosen & 1 << i) != 0, start, closing, lastBooking)) continue;
			if (found >= 0) return kept(day, places.size(), "adds up with more than one set of places");
			found = set;
		}
		int chosen = found;
		return found >= 0 ? withBreaks(day, places, i -> (chosen & 1 << i) != 0) : kept(day, places.size(), "adds up with no set of places");
	}

	/// Whether the places of `set` make the statement add up: the opening balance and the bookings at the start of a
	/// line give `start`, the bookings of the set add to it, and the result is the closing balance, which is the one at
	/// the start of a line or else the one place of the set that is a closing balance, after every booking.
	static boolean adds(List<Entry> places, IntPredicate set, BigDecimal start, Entry closing, int lastBooking) {
		BigDecimal sum = start;
		Entry end = closing;
		int last = lastBooking;
		for (int i = 0; i < places.size(); i++) {
			if (!set.test(i)) continue;
			Entry e = places.get(i);
			if (e.closing()) {
				if (end != null) return false;
				end = e;
			} else {
				sum = sum.add(e.amount());
				last = Math.max(last, e.place());
			}
		}
		return end != null && last < end.place() && sum.compareTo(end.amount()) == 0;
	}

	/// The balance or the booking at the start of `text`, or null when it does not read in full.
	static Entry entry(String text, int place) {
		Matcher b = BALANCE.matcher(text);
		if (b.matches()) return new Entry(place, true, b.group(1).equals("2"), b.group(3), signed(b.group(2), b.group(4)));
		Matcher k = BOOKING.matcher(text);
		if (!k.lookingAt()) return null;
		BigDecimal amount = signed(k.group(3), k.group(5));
		return new Entry(place, false, false, k.group(4), k.group(2).isEmpty() ? amount : amount.negate());
	}

	/// Whether a balance has the currency, or a booking the funds code of the currency, its third letter, or none.
	static boolean fits(Entry e, String currency) {
		return e.balance() ? e.currency().equals(currency) : e.currency() == null || e.currency().equals(currency.substring(2));
	}

	/// The statement with a break at each place of `set`, built once from its parts.
	static String withBreaks(String day, List<Entry> places, IntPredicate set) {
		StringBuilder out = new StringBuilder(day.length() + 2 * places.size());
		int from = 0;
		for (int i = 0; i < places.size(); i++) {
			if (!set.test(i)) continue;
			out.append(day, from, places.get(i).place()).append("\r\n");
			from = places.get(i).place();
		}
		return out.append(day, from, day.length()).toString();
	}

	/// The last line of `kept`, for the self-test.
	static volatile String lastKept;

	/// The statement of a day as the bank sent it, with one line in the diagnostics. `places` is -1 when not counted.
	static String kept(String day, int places, String reason) {
		lastKept = "FinTSHelper: a statement of 1822direkt" + (places >= 0 ? " with " + places + " places for a line break" : "")
			+ " stays as sent, because it " + reason;
		FinTSHelper.diagnostic(lastKept);
		return day;
	}

	/// C is a credit and D a debit. A reversal of a booking (RC, RD) turns its sign, which `entry` does.
	static BigDecimal signed(String mark, String amount) {
		BigDecimal value = new BigDecimal(amount.endsWith(",") ? amount.substring(0, amount.length() - 1) : amount.replace(',', '.'));
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
