import java.util.List;
import java.util.Map;

import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.status.HBCIRetVal;

/// The checks of the day of a pending MT942 row (issue #374), with made-up answers of the bank.
final class PendingDatesSelfTest {
	static final String MUSTERBANK = "fints.musterbank.example/fints";
	static final String HYPOVEREINSBANK = "hbci-01.hypovereinsbank.de/bank/hbci";
	static final String COMDIRECT = "fints.comdirect.de/fints";

	static void run() {
		String before = FinTSHelper.Callback.server;
		try {
			hosts();
			otherBank();
			hypoVereinsbank();
			otherRows();
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}

	static void hosts() {
		SelfTest.expect("hosts of HypoVereinsbank", HypoVereinsbank.hypoVereinsbank(HYPOVEREINSBANK) + " "
			+ HypoVereinsbank.hypoVereinsbank("HBCI-01.HypoVereinsbank.de:443/bank/hbci") + " " + HypoVereinsbank.hypoVereinsbank("fints.hypovereinsbank.de./"),
			"true true true");
		SelfTest.expect("hosts that are not of HypoVereinsbank", HypoVereinsbank.hypoVereinsbank("hypovereinsbank.de/bank/hbci") + " "
			+ HypoVereinsbank.hypoVereinsbank("hbci-01.hypovereinsbank.de.example.com/bank/hbci") + " " + HypoVereinsbank.hypoVereinsbank("hbci.evilhypovereinsbank.de/")
			+ " " + HypoVereinsbank.hypoVereinsbank(null) + " " + HypoVereinsbank.hypoVereinsbank(MUSTERBANK), "false false false false false");
		SelfTest.expect("servers that send the expected day as the entry date", PendingDates.expectedDayInEntryDate("fints.ing.de/fints/") + " "
			+ PendingDates.expectedDayInEntryDate("fints.commerzbank.de/fints") + " " + PendingDates.expectedDayInEntryDate("hbci.commerzbank.de/fints") + " "
			+ PendingDates.expectedDayInEntryDate(HYPOVEREINSBANK), "true true true true");
		SelfTest.expect("servers that do not", PendingDates.expectedDayInEntryDate(COMDIRECT) + " " + PendingDates.expectedDayInEntryDate(MUSTERBANK) + " "
			+ PendingDates.expectedDayInEntryDate("fints.ing.de.example.com/fints/") + " " + PendingDates.expectedDayInEntryDate(null), "false false false false");
	}

	/// The day of the first row of an MT942 answer with the ":61:" line `line61` from the server at `host`.
	static Object day(String host, String line61) {
		FinTSHelper.Callback.server = host;
		return ((Map<?, ?>) CommerzbankGroupSelfTest.intraday(line61).get(0)).get("booked");
	}

	/// Another bank sends the value date 14.11.2026 and the entry date 15.11, and the pending row takes the value date.
	static void otherBank() {
		FinTSHelper.Callback.server = MUSTERBANK;
		SelfTest.expect("pending MT942 row of another bank on its value date", FinTSHelper.Json.write(CommerzbankGroupSelfTest.intraday("2611141115D42,00NTRFNONREF")),
			"[{\"type\":\"row\",\"booked\":\"2026-11-14\",\"value\":\"2026-11-14\",\"amount\":\"-42\",\"currency\":\"EUR\",\"name\":\"Stadtwerke Musterstadt\","
				+ "\"purpose\":\"Abschlag November\",\"bookingText\":\"LASTSCHRIFT\",\"pending\":true}]");
		SelfTest.expect("pending MT942 row of another bank whose entry date is in the year before", day(MUSTERBANK, "2601021231D10,00NTRFNONREF"), "2026-01-02");
		SelfTest.expect("pending MT942 row of another bank without an entry date", day(MUSTERBANK, "261114D42,00NTRFNONREF"), "2026-11-14");
		SelfTest.expect("pending MT942 row of comdirect on its value date", day(COMDIRECT, "2611141115D42,00NTRFNONREF"), "2026-11-14");
	}

	/// HypoVereinsbank sends the day on which it expects to book a pending row as the entry date, as Commerzbank and ING do.
	static void hypoVereinsbank() {
		SelfTest.expect("pending MT942 row of HypoVereinsbank on its expected day", day(HYPOVEREINSBANK, "2611141115D120,50NTRFNONREF"), "2026-11-15");
		SelfTest.expect("pending MT942 row of HypoVereinsbank whose expected day is in the next year", day(HYPOVEREINSBANK, "2512310102C25,00NTRFNONREF"),
			"2026-01-02");
		SelfTest.expect("pending MT942 row of HypoVereinsbank without an expected day", day(HYPOVEREINSBANK, "261114D120,50NTRFNONREF"), "2026-11-14");
	}

	/// A booked MT940 row and a CAMT row of another bank keep the booking date that hbci4java reads.
	static void otherRows() {
		FinTSHelper.Callback.server = MUSTERBANK;
		GVRKUms answer = new GVRKUms();
		answer.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "Auftrag ausgeführt", null));
		answer.appendMT940Data("\r\n:20:STARTUMS\r\n:25:12030000/0000202051\r\n:28C:1/1\r\n:60F:C261113EUR100,00\r\n:61:2611141115D42,00NTRFNONREF"
			+ "\r\n:86:105?00LASTSCHRIFT?20SVWZ+Abschlag November?32Stadtwerke Musterstadt\r\n:62F:C261115EUR58,00\r\n-\r\n");
		Map<String, Object> result = FinTSHelper.result("DE02120300000000202051", null, null, answer, false);
		@SuppressWarnings("unchecked")
		List<Object> rows = (List<Object>) ((Map<String, Object>) result.get("transactions")).get("rows");
		SelfTest.expect("booked MT940 row of another bank on its entry date", ((Map<?, ?>) rows.get(0)).get("booked") + " " + ((Map<?, ?>) rows.get(0)).get("pending"),
			"2026-11-15 false");

		UmsLine camt = SelfTest.line("2026-11-15", "2026-11-14", "-8.50", "Kartenzahlung Bäckerei");
		camt.isCamt = true;
		SelfTest.expect("pending CAMT row of another bank on its booking date", FinTSHelper.day(PendingDates.booked(camt, true, MUSTERBANK)), "2026-11-15");
		UmsLine mt942 = SelfTest.line("2026-11-15", "2026-11-14", "-8.50", "Kartenzahlung Bäckerei");
		SelfTest.expect("pending MT942 row of another bank on its value date, booked row on its entry date",
			FinTSHelper.day(PendingDates.booked(mt942, true, MUSTERBANK)) + " " + FinTSHelper.day(PendingDates.booked(mt942, false, MUSTERBANK)), "2026-11-14 2026-11-15");
	}
}
