import java.util.List;
import java.util.Map;
import java.util.Properties;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.status.HBCIMsgStatus;
import org.kapott.hbci.status.HBCIRetVal;

/// The checks of the rules of the savings banks and 1822direkt (issue #240), with made-up answers of the bank.
final class SavingsBanksSelfTest {
	static final String SPARKASSE = "banking-hs6.s-fints-pt-hs.de/fints30";
	static final String DIREKT = "fints.1822direkt.com/fints/hbci";
	static final String MUSTERBANK = "fints.musterbank.example/fints";
	static final String DEACTIVATED = "Kundenprodukt wurde vom Benutzer deaktiviert";

	static void run() {
		hosts();
		appBlocked();
		statements();
	}

	static void hosts() {
		SelfTest.expect("savings bank hosts", SavingsBanks.savingsBank(SPARKASSE) + " " + SavingsBanks.savingsBank("banking-by7.s-fints-pt-by.de/fints30") + " "
			+ SavingsBanks.savingsBank("hbci.s-hbci.de/fints30") + " " + SavingsBanks.savingsBank("BANKING-HH7.S-FINTS-PT-HH.DE/fints30") + " "
			+ SavingsBanks.savingsBank("banking-hs6.s-fints-pt-hs.de:443/fints30"), "true true true true true");
		SelfTest.expect("hosts that are not of the savings banks", SavingsBanks.savingsBank(DIREKT) + " " + SavingsBanks.savingsBank(MUSTERBANK) + " "
			+ SavingsBanks.savingsBank("banking.s-fints-pt-hs.de.example.com/fints30") + " " + SavingsBanks.savingsBank("banking.my-s-fints-pt-hs.de/fints30") + " "
			+ SavingsBanks.savingsBank("fints.example.com/s-fints-pt-hs.de") + " " + SavingsBanks.savingsBank(null), "false false false false false false");
		SelfTest.expect("hosts of 1822direkt", SavingsBanks.direkt1822(DIREKT) + " " + SavingsBanks.direkt1822("1822direkt.com/fints") + " "
			+ SavingsBanks.direkt1822("FINTS.1822DIREKT.COM/fints/hbci"), "true true true");
		SelfTest.expect("hosts that are not of 1822direkt", SavingsBanks.direkt1822("fints.my1822direkt.com/fints") + " "
			+ SavingsBanks.direkt1822("fints.1822direkt.com.example/fints") + " " + SavingsBanks.direkt1822(SPARKASSE) + " " + SavingsBanks.direkt1822(null),
			"false false false false");
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
			SelfTest.expect("other texts of a deactivation by the user", SavingsBanks.appBlocked(SPARKASSE, "Zugang wurde vom Kunden gesperrt") + " "
				+ SavingsBanks.appBlocked(SPARKASSE, "Die Anwendung wurde VOM NUTZER DEAKTIVIERT.") + " " + SavingsBanks.appBlocked(SPARKASSE, "Software vom Benutzer gesperrt"),
				"true true true");
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

	/// An MT940 statement of 1822direkt whose booking tag follows the purpose of the booking before it.
	static void statements() {
		String broken = String.join("\r\n", ":20:STARTUMS", ":25:50050222/0000202051", ":28C:00000/001", ":60F:C261114EUR1000,00",
			":61:2611141114C120,00NTRFNONREF", ":86:166?00GUTSCHRIFT?20Miete November:61:2611151115D12,50NTRFNONREF",
			":86:105?00LASTSCHRIFT?20Strom Oktober:62F:C261115EUR1107,50", "-") + "\r\n";
		SelfTest.expect("a tag inside a line starts a new line, and no character is lost", SavingsBanks.tagsOnOwnLines(broken),
			broken.replace("November:61:", "November\r\n:61:").replace("Oktober:62F:", "Oktober\r\n:62F:"));
		String whole = String.join("\r\n", ":20:STARTUMS", ":61:2611151115D12,50NTRFNONREF", ":86:105?20Strom", ":62F:C261115EUR1107,50", "-") + "\r\n";
		SelfTest.expect("a statement whose tags start their lines stays as it is", SavingsBanks.tagsOnOwnLines(whole), whole);
		SelfTest.expect("a tag at the very start, after a bare line feed, and a tag that only looks like one", SavingsBanks.tagsOnOwnLines(":61:x\n:62F:y z:610:w :62M:v"),
			":61:x\n:62F:y z:610:w :62M:v");
		SelfTest.expect("an empty statement", SavingsBanks.tagsOnOwnLines(""), "");

		HBCIMsgStatus answer = new HBCIMsgStatus();
		answer.getData().setProperty("GVRes.KUmsZeitRes7.booked", broken);
		answer.getData().setProperty("GVRes.KUmsZeitRes7.notbooked", ":20:STARTUMS\r\n:86:?20Kartenzahlung:61:2611161116D8,00NTRFNONREF\r\n-\r\n");
		answer.getData().setProperty("GVRes.KUmsZeitRes8.booked", broken);
		SavingsBanks.StatementJob.repair(answer.getData(), "GVRes.KUmsZeitRes7");
		SelfTest.expect("the job repairs the booked and the pending part of its own answer", answer.getData().getProperty("GVRes.KUmsZeitRes7.booked").contains("November\r\n:61:") + " "
			+ answer.getData().getProperty("GVRes.KUmsZeitRes7.notbooked").contains("Kartenzahlung\r\n:61:") + " "
			+ answer.getData().getProperty("GVRes.KUmsZeitRes8.booked").equals(broken), "true true true");
		Properties none = new Properties();
		SavingsBanks.StatementJob.repair(none, "GVRes.KUmsZeitRes7");
		SelfTest.expect("an answer without statements", none.isEmpty(), true);

		SelfTest.expect("1822direkt gets the statement job, and other banks the job of hbci4java", SavingsBanks.repairsStatements(DIREKT) + " "
			+ SavingsBanks.repairsStatements(SPARKASSE) + " " + SavingsBanks.repairsStatements(MUSTERBANK), "true false false");

		SelfTest.expect("the repaired statement of 1822direkt", rows(SavingsBanks.tagsOnOwnLines(broken)),
			"2026-11-14 120 Miete November | 2026-11-15 -12.5 Strom Oktober");
		SelfTest.expect("the same statement unrepaired loses the booking", rows(broken),
			"2026-11-14 120 Miete November:61:2611151115D12,50NTRFNONREF");
	}

	/// The booked rows that the helper sends for an MT940 statement, as day, amount, and purpose.
	static String rows(String mt940) {
		GVRKUms result = new GVRKUms();
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
		result.appendMT940Data(mt940);
		Map<String, Object> message = FinTSHelper.result("DE02500502220000202051", null, null, result, false);
		@SuppressWarnings("unchecked")
		List<Map<String, Object>> rows = (List<Map<String, Object>>) ((Map<String, Object>) message.get("transactions")).get("rows");
		return String.join(" | ", rows.stream().map(r -> r.get("booked") + " " + r.get("amount") + " " + r.get("purpose")).toList());
	}
}
