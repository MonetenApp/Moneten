import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;

/// The checks of the rules of the Deutsche Bank group (issue #231), with made-up rows.
final class DeutscheBankGroupSelfTest {
	static final String POSTBANK = "hbci.postbank.de/banking/hbci.do";
	static final String DEUTSCHE_BANK = "fints.deutsche-bank.de/";
	static final String MUSTERBANK = "fints.musterbank.example/fints";

	static void run() {
		hosts();
		pendingCardPayment();
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
}
