import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;

/// The checks of the rules of the Deutsche Bank group (issue #231), with made-up rows.
final class DeutscheBankGroupSelfTest {
	static final String POSTBANK = "hbci.postbank.de/banking/hbci.do";
	static final String DEUTSCHE_BANK = "fints.deutsche-bank.de/";
	static final String MUSTERBANK = "fints.musterbank.example/fints";

	static void run() {
		hosts();
		pendingCardPayment();
		loginReplaced();
		restoredLogin();
	}

	/// A state of the group whose IDs differ in their spaces only names one login, so the customer ID follows the login
	/// name of the command, which the app sends without spaces.
	static void restoredLogin() {
		SelfTest.expect("a customer ID with spaces follows a user ID without", SelfTest.restoredLogin(DEUTSCHE_BANK, "1234567890", "123 4567890", "1234567890"),
			"1234567890 1234567890");
		SelfTest.expect("a customer ID without spaces follows a user ID with", SelfTest.restoredLogin(POSTBANK, "123 4567890", "1234567890", "1234567890"),
			"1234567890 1234567890");
		SelfTest.expect("other white space counts as a space", SelfTest.restoredLogin("fints.norisbank.de/", "123\u00A04567890", "123\u2003 4567890", "1234567890"),
			"1234567890 1234567890");
		SelfTest.expect("a customer ID of its own stays", SelfTest.restoredLogin(DEUTSCHE_BANK, "1234567890", "987 6543210", "1234567890"),
			"1234567890 987 6543210");
		SelfTest.expect("another bank keeps a customer ID that differs in spaces", SelfTest.restoredLogin(MUSTERBANK, "1234567890", "123 4567890", "1234567890"),
			"1234567890 123 4567890");
	}

	static void hosts() {
		SelfTest.expect("Postbank hosts", DeutscheBankGroup.postbank(POSTBANK) + " " + DeutscheBankGroup.postbank("HBCI.POSTBANK.DE.:443/banking/hbci.do"),
			"true true");
		SelfTest.expect("hosts that are not of Postbank", DeutscheBankGroup.postbank(DEUTSCHE_BANK) + " " + DeutscheBankGroup.postbank(MUSTERBANK) + " "
			+ DeutscheBankGroup.postbank("hbci.postbank.de.example.com/banking") + " " + DeutscheBankGroup.postbank("hbci.my-postbank.de/banking") + " "
			+ DeutscheBankGroup.postbank(null), "false false false false false");
	}

	static UmsLine card(String purpose) {
		UmsLine l = SelfTest.line("2026-11-09", "2026-11-09", "-23.80", purpose);
		l.text = "Kartenzahlung";
		return l;
	}

	static Object name(UmsLine l, boolean pending) {
		return FinTSHelper.row(l, pending).get("name");
	}

	/// A pending card payment of Postbank without a name takes it from the purpose.
	static void pendingCardPayment() {
		String before = FinTSHelper.Callback.server;
		try {
			FinTSHelper.Callback.server = POSTBANK;
			SelfTest.expect("a pending Postbank card payment takes the name after the slash", FinTSHelper.Json.write(FinTSHelper.row(card("Kartenzahlung / Buchhandlung Beispiel"), true)),
				"{\"type\":\"row\",\"booked\":\"2026-11-09\",\"value\":\"2026-11-09\",\"amount\":\"-23.8\",\"currency\":\"EUR\",\"name\":\"Buchhandlung Beispiel\","
					+ "\"purpose\":\"Kartenzahlung / Buchhandlung Beispiel\",\"bookingText\":\"Kartenzahlung\",\"pending\":true}");
			SelfTest.expect("a pending Postbank card payment of one word takes the word", name(card("PayPal"), true), "PayPal");
			SelfTest.expect("a pending Postbank card payment with words and no slash, an empty part after it, or only the booking text keeps no name",
				name(card("Buchhandlung Beispiel"), true) + " " + name(card("Kartenzahlung / "), true) + " " + name(card("Kartenzahlung"), true), "null null null");
			UmsLine named = card("Kartenzahlung / Buchhandlung Beispiel");
			named.other.name = "Buchhandlung Muster";
			SelfTest.expect("a name of the bank stays", name(named, true), "Buchhandlung Muster");
			SelfTest.expect("a booked card payment keeps no name", name(card("Kartenzahlung / Buchhandlung Beispiel"), false), "null");
			UmsLine transfer = card("Miete / November");
			transfer.text = "Überweisung";
			SelfTest.expect("a pending row of another kind keeps no name", name(transfer, true), "null");

			FinTSHelper.Callback.server = DEUTSCHE_BANK;
			SelfTest.expect("a pending card payment of another bank keeps no name", name(card("Kartenzahlung / Buchhandlung Beispiel"), true), "null");
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}

	static final String REPLACED = "Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support.";

	/// The answer of the group to a login that a new login replaced: 9940 or 3960 with the request to log in to the online
	/// banking or to contact the support.
	static void loginReplaced() {
		String before = FinTSHelper.Callback.server;
		try {
			FinTSHelper.Callback.server = DEUTSCHE_BANK;
			SelfTest.expect("a replaced login of Deutsche Bank", SelfTest.failed(SelfTest.status("9800", "Dialog abgebrochen", "9940", REPLACED)),
				"{\"type\":\"failed\",\"kind\":\"loginReplaced\",\"code\":\"9940\",\"text\":\"" + REPLACED + "\"}");
			SelfTest.expect("the warning 3960 of a replaced login ends the dialog as an error", SelfTest.failed(SelfTest.status("3960", REPLACED)) + " "
				+ (FinTSHelper.blocking(SelfTest.status("3960", REPLACED)) != null) + " " + (FinTSHelper.blocking(SelfTest.status("3960", "Hinweis")) != null),
				"{\"type\":\"failed\",\"kind\":\"loginReplaced\",\"code\":\"3960\",\"text\":\"" + REPLACED + "\"} true false");
			SelfTest.expect("the codes and the text of a replaced login", DeutscheBankGroup.loginReplaced(DEUTSCHE_BANK, "3960", REPLACED) + " "
				+ DeutscheBankGroup.loginReplaced(POSTBANK, "9940", "MELDEN SIE SICH IM ONLINE-BANKING AN ODER KONTAKTIEREN DEN SUPPORT") + " "
				+ DeutscheBankGroup.loginReplaced("fints.norisbank.de/", "9940", REPLACED), "true true true");
			SelfTest.expect("another code, another text, or another bank is no replaced login", DeutscheBankGroup.loginReplaced(DEUTSCHE_BANK, "9942", REPLACED) + " "
				+ DeutscheBankGroup.loginReplaced(DEUTSCHE_BANK, "9940", "Bitte im Online-Banking anmelden") + " "
				+ DeutscheBankGroup.loginReplaced(MUSTERBANK, "9940", REPLACED) + " " + DeutscheBankGroup.loginReplaced("deutsche-bank.de/", "9940", REPLACED) + " "
				+ DeutscheBankGroup.loginReplaced(DEUTSCHE_BANK, "9940", null) + " " + DeutscheBankGroup.loginReplaced(DEUTSCHE_BANK, null, REPLACED),
				"false false false false false false");
			FinTSHelper.Callback callback = new FinTSHelper.Callback(java.util.Map.of());
			callback.log("HBCI4Java: Meldung der Bank: 9940: " + REPLACED, 1, null, null);
			SelfTest.expect("a rejected PIN with the answer of a replaced login", FinTSHelper.Json.write(callback.pinError),
				"{\"type\":\"rejected\",\"kind\":\"loginReplaced\",\"code\":\"9940\",\"text\":\"" + REPLACED + "\"}");

			FinTSHelper.Callback.server = MUSTERBANK;
			SelfTest.expect("another bank with the same answer keeps its code", SelfTest.failed(SelfTest.status("9940", REPLACED)),
				"{\"type\":\"failed\",\"code\":\"9940\",\"text\":\"" + REPLACED + "\"}");
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}
}
