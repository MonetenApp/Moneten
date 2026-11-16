import java.util.Map;

/// The checks of the rules of the savings banks (issue #240), with made-up answers of the bank.
final class SavingsBanksSelfTest {
	static final String SPARKASSE = "banking-hs6.s-fints-pt-hs.de/fints30";
	/// A server of another bank group, which is no server of the savings banks.
	static final String DIREKT = "fints.1822direkt.com/fints/hbci";
	static final String MUSTERBANK = "fints.musterbank.example/fints";
	static final String DEACTIVATED = "Kundenprodukt wurde vom Benutzer deaktiviert";

	static void run() {
		hosts();
		appBlocked();
	}

	static void hosts() {
		SelfTest.expect("savings bank hosts", SavingsBanks.savingsBank(SPARKASSE) + " " + SavingsBanks.savingsBank("banking-by7.s-fints-pt-by.de/fints30") + " "
			+ SavingsBanks.savingsBank("hbci.s-hbci.de/fints30") + " " + SavingsBanks.savingsBank("BANKING-HH7.S-FINTS-PT-HH.DE/fints30") + " "
			+ SavingsBanks.savingsBank("banking-hs6.s-fints-pt-hs.de:443/fints30") + " " + SavingsBanks.savingsBank("banking-hs6.s-fints-pt-hs.de./fints30") + " "
			+ SavingsBanks.savingsBank("BANKING-HS6.S-FINTS-PT-HS.DE.:443/fints30") + " " + SavingsBanks.savingsBank("banking-hs6.s-fints-pt-hs.de:/fints30"),
			"true true true true true true true true");
		SelfTest.expect("hosts that are not of the savings banks", SavingsBanks.savingsBank(DIREKT) + " " + SavingsBanks.savingsBank(MUSTERBANK) + " "
			+ SavingsBanks.savingsBank("banking.s-fints-pt-hs.de.example.com/fints30") + " " + SavingsBanks.savingsBank("banking.my-s-fints-pt-hs.de/fints30") + " "
			+ SavingsBanks.savingsBank("fints.example.com/s-fints-pt-hs.de") + " " + SavingsBanks.savingsBank(null) + " "
			+ SavingsBanks.savingsBank("banking.s-fints-pt-hs.de.evil.example./fints30") + " " + SavingsBanks.savingsBank("banking.s-fints-pt-hs.de../fints30"),
			"false false false false false false false false");
	}

	/// The app that the user blocked under "Kontozugriffe" in the online banking of a Sparkasse.
	static void appBlocked() {
		String before = FinTSHelper.Callback.server;
		try {
			FinTSHelper.Callback.server = SPARKASSE;
			SelfTest.expect("a savings bank that answers that the user deactivated the app", SelfTest.failed(SelfTest.status("9800", "Dialog abgebrochen", "9010", DEACTIVATED)),
				"{\"type\":\"failed\",\"kind\":\"appBlocked\",\"code\":\"9010\",\"text\":\"" + DEACTIVATED + "\"}");
			SelfTest.expect("the app blocked by the user comes before a wrong PIN and a blocked access", SelfTest.failed(SelfTest.status("9942", "PIN falsch",
				"9930", "PIN gesperrt", "9931", DEACTIVATED)), "{\"type\":\"failed\",\"kind\":\"appBlocked\",\"code\":\"9931\",\"text\":\"" + DEACTIVATED + "\"}");
			SelfTest.expect("other spellings of the product or the account access deactivated by the user",
				SavingsBanks.appBlocked(SPARKASSE, "KUNDENPRODUKT WURDE VOM BENUTZER DEAKTIVIERT") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Das Kundenprodukt wurde  vom  Benutzer deaktiviert.") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Der Kontozugriff für Moneten wurde vom Benutzer deaktiviert"), "true true true");
			SelfTest.expect("a card, a TAN method, or an access that the user blocked is no app blocked under Kontozugriffe",
				SavingsBanks.appBlocked(SPARKASSE, "Die Kreditkarte wurde vom Benutzer gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "pushTAN wurde vom Kunden deaktiviert") + " " + SavingsBanks.appBlocked(SPARKASSE, "Zugang wurde vom Kunden gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Die Anwendung wurde VOM NUTZER DEAKTIVIERT.") + " " + SavingsBanks.appBlocked(SPARKASSE, "Software vom Benutzer gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Kundenprodukt gesperrt. Zugang vom Benutzer deaktiviert") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Das Produkt wurde vom Benutzer deaktiviert"), "false false false false false false false");
			SelfTest.expect("a blocked access and a wrong PIN keep their codes beside a card that the user blocked", SelfTest.failed(SelfTest.status("9942", "PIN falsch",
				"9930", "PIN gesperrt", "9010", "Die Kreditkarte wurde vom Benutzer gesperrt")) + " " + SelfTest.failed(SelfTest.status("9942", "PIN falsch",
				"9010", "pushTAN wurde vom Kunden deaktiviert")), "{\"type\":\"failed\",\"code\":\"9930\",\"text\":\"PIN gesperrt\"} "
				+ "{\"type\":\"failed\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");
			SelfTest.expect("texts of a block that the user did not cause", SavingsBanks.appBlocked(SPARKASSE, "PIN gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "FinTS-Produkt ist nicht registriert") + " " + SavingsBanks.appBlocked(SPARKASSE, "Kundenprodukt gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut") + " " + SavingsBanks.appBlocked(SPARKASSE, null),
				"false false false false false");
			SelfTest.expect("an order of a savings bank that the user deactivated", FinTSHelper.Json.write(FinTSHelper.problem(SelfTest.refusedJob("9010", DEACTIVATED))),
				"{\"type\":\"error\",\"kind\":\"appBlocked\",\"code\":\"9010\",\"text\":\"" + DEACTIVATED + "\"}");
			FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
			callback.log("HBCI4Java: Meldung der Bank: 9931: " + DEACTIVATED, 1, null, null);
			SelfTest.expect("a rejected PIN with the text of the app blocked by the user", FinTSHelper.Json.write(callback.pinError),
				"{\"type\":\"rejected\",\"kind\":\"appBlocked\",\"code\":\"9931\",\"text\":\"" + DEACTIVATED + "\"}");

			FinTSHelper.Callback.server = MUSTERBANK;
			SelfTest.expect("another bank with the same text keeps its codes", SelfTest.failed(SelfTest.status("9800", "Dialog abgebrochen", "9010", DEACTIVATED)) + " "
				+ SelfTest.failed(SelfTest.status("9010", DEACTIVATED)), "{\"type\":\"failed\",\"code\":\"9800\",\"text\":\"Dialog abgebrochen\"} "
				+ "{\"type\":\"failed\",\"code\":\"9010\",\"text\":\"" + DEACTIVATED + "\"}");
			callback.log("HBCI4Java: Meldung der Bank: 9931: " + DEACTIVATED, 1, null, null);
			SelfTest.expect("another bank with a rejected PIN of the same text", FinTSHelper.Json.write(callback.pinError),
				"{\"type\":\"rejected\",\"code\":\"9931\",\"text\":\"" + DEACTIVATED + "\"}");
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}
}
