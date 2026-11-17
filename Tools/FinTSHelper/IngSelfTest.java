import java.util.Map;

import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;

/// The checks of the rules of ING (issue #235), with made-up answers of the bank.
final class IngSelfTest {
	static final String ING = "fints.ing.de/fints/";
	static final String MUSTERBANK = "fints.musterbank.example/fints";
	/// The answer of ING to a login while it waits for a login on its website, as users recorded it.
	static final String RENEW = "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen.";

	static void run() {
		hosts();
		pendingDates();
		websiteLogin();
	}

	static void hosts() {
		SelfTest.expect("ING hosts", Ing.ing(ING) + " " + Ing.ing("FINTS.ING.DE/fints/") + " " + Ing.ing("fints.ing.de:443/fints/") + " "
			+ Ing.ing("fints.ing.de./fints/"), "true true true true");
		SelfTest.expect("hosts that are not of ING", Ing.ing(MUSTERBANK) + " " + Ing.ing("fints.ing.de.evil.example/fints/") + " "
			+ Ing.ing("fints.ing-diba.de/fints/") + " " + Ing.ing("my.fints.ing.de/fints/") + " " + Ing.ing("fints.example.com/fints.ing.de") + " "
			+ Ing.ing(null), "false false false false false false");
	}

	/// A pending MT942 row of ING with the value date 14.11.2026 and the entry date 15.11.2026, the day on which ING
	/// expects to book it.
	static UmsLine pending() {
		UmsLine l = SelfTest.line("2026-11-15", "2026-11-14", "-9.99", "Musterverlag Abo 11/2026");
		l.other.name = "Musterverlag";
		return l;
	}

	static void pendingDates() {
		String before = FinTSHelper.Callback.server;
		try {
			FinTSHelper.Callback.server = ING;
			SelfTest.expect("a pending MT942 row of ING has the day on which ING expects to book it", FinTSHelper.Json.write(FinTSHelper.row(pending(), true)),
				"{\"type\":\"row\",\"booked\":\"2026-11-15\",\"value\":\"2026-11-14\",\"amount\":\"-9.99\",\"currency\":\"EUR\",\"name\":\"Musterverlag\","
					+ "\"purpose\":\"Musterverlag Abo 11/2026\",\"pending\":true}");
			UmsLine withoutEntryDate = pending();
			withoutEntryDate.bdate = null;
			SelfTest.expect("a pending MT942 row of ING without an entry date has its value date", FinTSHelper.row(withoutEntryDate, true).get("booked"),
				"2026-11-14");
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}

	static final String WEBSITE = "{\"type\":\"rejected\",\"kind\":\"websiteLogin\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}";

	/// The rejection of the PIN after hbci4java logged each of `lines` as messages of the bank.
	static String rejected(String... lines) {
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
		for (String line : lines) callback.log("HBCI4Java: Meldung der Bank: " + line, 1, null, null);
		return FinTSHelper.Json.write(callback.pinError);
	}

	/// The FinTS login that ING refuses until the user logged in to its online banking.
	static void websiteLogin() {
		String before = FinTSHelper.Callback.server;
		try {
			FinTSHelper.Callback.server = ING;
			SelfTest.expect("ING asks for a login on its website", SelfTest.failed(SelfTest.status("9800", "Der Dialog wurde abgebrochen.", "9942", RENEW)),
				"{\"type\":\"failed\",\"kind\":\"websiteLogin\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}");
			SelfTest.expect("the request of ING comes before another 9942, after a blocked access", SelfTest.failed(SelfTest.status("9942", "PIN falsch", "9942", RENEW)) + " "
				+ SelfTest.failed(SelfTest.status("9942", RENEW, "9930", "PIN gesperrt")),
				"{\"type\":\"failed\",\"kind\":\"websiteLogin\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"} {\"type\":\"failed\",\"code\":\"9930\",\"text\":\"PIN gesperrt\"}");
			SelfTest.expect("the sentence of ING with another code keeps the meaning of its code", SelfTest.failed(SelfTest.status("9010", RENEW)) + " "
				+ Ing.websiteLoginNeeded(ING, "9931", RENEW) + " " + Ing.websiteLoginNeeded(ING, null, RENEW),
				"{\"type\":\"failed\",\"code\":\"9010\",\"text\":\"" + RENEW + "\"} false false");
			SelfTest.expect("other spellings of the request of ING", Ing.websiteLoginNeeded(ING, "9942", "BITTE ERNEUERN SIE IHRE AUTHENTIFIZIERUNG.") + " "
				+ Ing.websiteLoginNeeded(ING, "9942", "Bitte erneuern  Sie ihre Authentifizierung") + " "
				+ Ing.websiteLoginNeeded(ING, "9942", "Zugang: Bitte erneuern Sie ihre Authentifizierung."), "true true true");
			SelfTest.expect("texts of ING that are no request for a login on its website", Ing.websiteLoginNeeded(ING, "9942", "PIN falsch") + " "
				+ Ing.websiteLoginNeeded(ING, "9942", "Authentifizierung fehlgeschlagen") + " " + Ing.websiteLoginNeeded(ING, "9942", "Einfach unter ING.de einloggen.") + " "
				+ Ing.websiteLoginNeeded(ING, "9942", "Bitte erneuern Sie Ihre PIN") + " " + Ing.websiteLoginNeeded(ING, "9942", "Starke Kundenauthentifizierung noch ausstehend") + " "
				+ Ing.websiteLoginNeeded(ING, "9942", "Erneuern Sie ihre Authentifizierung") + " " + Ing.websiteLoginNeeded(ING, "9942", null),
				"false false false false false false false");
			SelfTest.expect("a wrong PIN of ING keeps its code", SelfTest.failed(SelfTest.status("9800", "Der Dialog wurde abgebrochen.", "9942", "PIN falsch")),
				"{\"type\":\"failed\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");
			SelfTest.expect("an order of ING that needs a login on its website", FinTSHelper.Json.write(FinTSHelper.problem(SelfTest.refusedJob("9942", RENEW))),
				"{\"type\":\"error\",\"kind\":\"websiteLogin\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}");
			FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
			callback.log("HBCI4Java: Meldung der Bank: 9942: " + RENEW, 1, null, null);
			SelfTest.expect("a rejected PIN with the request of ING", FinTSHelper.Json.write(callback.pinError),
				"{\"type\":\"rejected\",\"kind\":\"websiteLogin\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}");

			FinTSHelper.Callback borrowed = new FinTSHelper.Callback(Map.of());
			borrowed.log("HBCI4Java: Meldung der Bank: 9942: PIN falsch; Meldung der Bank: 9010: " + RENEW, 1, null, null);
			SelfTest.expect("a wrong PIN does not borrow the sentence of ING from another message of the same line", FinTSHelper.Json.write(borrowed.pinError),
				"{\"type\":\"rejected\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");
			SelfTest.expect("the request of ING and a wrong PIN in one line, in either order", rejected("9942: PIN falsch; Meldung der Bank: 9942: " + RENEW) + " "
				+ rejected("9942: " + RENEW + "; Meldung der Bank: 9942: PIN falsch"), WEBSITE + " " + WEBSITE);
			SelfTest.expect("the request of ING before or after a wrong PIN in another line", rejected("9942: " + RENEW, "9942: PIN falsch") + " "
				+ rejected("9942: PIN falsch", "9942: " + RENEW), WEBSITE + " " + WEBSITE);
			String blocked = "{\"type\":\"rejected\",\"code\":\"9930\",\"text\":\"PIN gesperrt\"}";
			SelfTest.expect("a block before or after the request of ING", rejected("9930: PIN gesperrt", "9942: " + RENEW) + " "
				+ rejected("9942: " + RENEW, "9930: PIN gesperrt"), blocked + " " + blocked);

			FinTSHelper.Callback earlier = new FinTSHelper.Callback(Map.of());
			earlier.log("HBCI4Java: Meldung der Bank: 9942: " + RENEW, 1, null, null);
			earlier.status(null, org.kapott.hbci.callback.HBCICallback.STATUS_DIALOG_INIT, (Object[]) null);
			earlier.log("HBCI4Java: Meldung der Bank: 9942: PIN falsch", 1, null, null);
			SelfTest.expect("a new dialog forgets the messages of the dialogs before it", FinTSHelper.Json.write(earlier.pinError),
				"{\"type\":\"rejected\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");

			FinTSHelper.Callback.server = MUSTERBANK;
			SelfTest.expect("another bank with the same text keeps its codes", SelfTest.failed(SelfTest.status("9942", RENEW)),
				"{\"type\":\"failed\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}");
			callback.log("HBCI4Java: Meldung der Bank: 9942: " + RENEW, 1, null, null);
			SelfTest.expect("another bank with a rejected PIN of the same text", FinTSHelper.Json.write(callback.pinError),
				"{\"type\":\"rejected\",\"code\":\"9942\",\"text\":\"" + RENEW + "\"}");
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}
}
