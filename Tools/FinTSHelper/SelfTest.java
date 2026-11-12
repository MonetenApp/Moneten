// The checks of FinTSHelper that need no bank: java -cp … FinTSHelper --self-test. CI runs them.

import java.io.ByteArrayOutputStream;
import java.io.ObjectOutputStream;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.TimeZone;

import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.exceptions.HBCI_Exception;
import org.kapott.hbci.manager.HBCIUtils;
import org.kapott.hbci.passport.storage.PassportData;
import org.kapott.hbci.structures.Konto;
import org.kapott.hbci.structures.Value;

final class SelfTest {
	static final List<String> failures = new ArrayList<>();
	static int checks;

	static void expect(String name, Object actual, Object expected) {
		checks++;
		if (!String.valueOf(expected).equals(String.valueOf(actual))) failures.add(name + "\n  expected " + expected + "\n  got      " + actual);
	}

	static UmsLine line(String booked, String value, String amount, String... usage) {
		UmsLine l = new UmsLine();
		l.bdate = FinTSHelper.date(booked);
		l.valuta = FinTSHelper.date(value);
		l.value = new Value(new BigDecimal(amount), "EUR");
		l.usage = new ArrayList<>(List.of(usage));
		l.other = new Konto();
		return l;
	}

	static void run() {
		expect("JSON round trip",
			FinTSHelper.Json.write(FinTSHelper.Json.parse("{\"a\":\"x\\\"y\\\\\\n\\u00fc\",\"b\":[1,true,null,-2.5],\"c\":{}}")),
			"{\"a\":\"x\\\"y\\\\\\nü\",\"b\":[1,true,null,-2.5],\"c\":{}}");

		UmsLine mt940 = line("2026-11-02", "2026-10-30", "-23.80", "EREF+RE-2026-1001 MREF+M-471", "1 CRED+DE98ZZZ09999999999 SVWZ", "+Rechnung 1001");
		mt940.other.name = "Stadtwerke Musterstadt";
		mt940.other.iban = "DE02120300000000202051";
		mt940.other.bic = "BYLADEM1001";
		mt940.text = "FOLGELASTSCHRIFT";
		expect("MT940 row with tagged purpose", FinTSHelper.Json.write(FinTSHelper.row(mt940, false)),
			"{\"type\":\"row\",\"booked\":\"2026-11-02\",\"value\":\"2026-10-30\",\"amount\":\"-23.8\",\"currency\":\"EUR\","
				+ "\"name\":\"Stadtwerke Musterstadt\",\"iban\":\"DE02120300000000202051\",\"bic\":\"BYLADEM1001\",\"purpose\":\"Rechnung 1001\","
				+ "\"endToEnd\":\"RE-2026-1001\",\"mandate\":\"M-4711\",\"creditor\":\"DE98ZZZ09999999999\",\"bookingText\":\"FOLGELASTSCHRIFT\",\"pending\":false}");

		UmsLine camt = line("2026-11-09", "2026-11-09", "-46.12", "Kartenzahlung", "New York");
		camt.isCamt = true;
		camt.endToEndId = "SW-778899";
		camt.mandateId = "M-1";
		camt.other.name = "Coffee Shop";
		camt.other.creditorid = "DE98ZZZ09999999998";
		expect("CAMT row, pending", FinTSHelper.Json.write(FinTSHelper.row(camt, true)),
			"{\"type\":\"row\",\"booked\":\"2026-11-09\",\"value\":\"2026-11-09\",\"amount\":\"-46.12\",\"currency\":\"EUR\",\"name\":\"Coffee Shop\","
				+ "\"purpose\":\"Kartenzahlung New York\",\"endToEnd\":\"SW-778899\",\"mandate\":\"M-1\",\"creditor\":\"DE98ZZZ09999999998\",\"pending\":true}");

		UmsLine referenceOnly = line("2026-11-03", "2026-11-03", "120", "EREF+INV-2026-0042");
		expect("end-to-end reference as purpose", FinTSHelper.row(referenceOnly, false).get("purpose"), "INV-2026-0042");
		UmsLine placeholder = line("2026-11-03", "2026-11-03", "120");
		placeholder.endToEndId = "NOTPROVIDED";
		expect("placeholder reference", FinTSHelper.row(placeholder, false).get("purpose") + "|" + FinTSHelper.row(placeholder, false).get("endToEnd"), "|null");

		Konto plain = new Konto(), sub = new Konto(), withIBAN = new Konto();
		plain.number = "9";
		sub.number = "9";
		sub.subnumber = "01";
		withIBAN.number = "202051";
		withIBAN.iban = "DE02120300000000202051";
		Konto[] accounts = {withIBAN, sub, plain};
		expect("account by number", FinTSHelper.find(accounts, "9") == plain, true);
		expect("account by number and subnumber", FinTSHelper.find(accounts, "9/01") == sub, true);
		expect("account by IBAN", FinTSHelper.find(accounts, "DE02 1203 0000 0000 2020 51") == withIBAN, true);
		expect("unknown subnumber", FinTSHelper.find(accounts, "9/02"), null);

		TimeZone zone = TimeZone.getDefault();
		for (String id : new String[] {"Pacific/Kiritimati", "Pacific/Pago_Pago", "Europe/Berlin"}) {
			TimeZone.setDefault(TimeZone.getTimeZone(id));
			expect("day in " + id, FinTSHelper.day(FinTSHelper.date("2026-11-09")), "2026-11-09");
		}
		TimeZone.setDefault(zone);

		expect("plain HTTP refused", refusal("http://bank.example/fints"), "unsupported: The bank offers no encrypted FinTS address.");
		expect("address without host refused", refusal("https:///fints"), "unsupported: The bank offers no encrypted FinTS address.");
		expect("HTTPS accepted", FinTSHelper.https("https://bank.example/fints").getHost(), "bank.example");

		FinTSHelper.Out.secret("geheim42");
		expect("PIN masked", FinTSHelper.Out.bank("PIN geheim42 sent"), "PIN ••• sent");
		expect("text of the bank left out", FinTSHelper.Out.bank("Fehler 9942:PIN falsch, Konto DE02120300000000202051"), "Fehler 9942 PIN wrong");

		PassportData data = new PassportData();
		data.blz = "12030000";
		data.sysId = "SYS-1";
		data.bpd = new Properties();
		data.bpd.setProperty("BPD.Params.KInfo", "x");
		data.twostepMechs = new ArrayList<>(List.of("921"));
		try {
			PassportData back = FinTSHelper.Passport.deserialize(FinTSHelper.Passport.serialize(data));
			expect("passport round trip", back.blz + " " + back.sysId + " " + back.bpd + " " + back.twostepMechs, "12030000 SYS-1 {BPD.Params.KInfo=x} [921]");
			ByteArrayOutputStream bytes = new ByteArrayOutputStream();
			try (ObjectOutputStream o = new ObjectOutputStream(bytes)) {
				o.writeObject(new java.util.Date(0));
			}
			expect("foreign class in the state refused", FinTSHelper.Passport.deserialize(bytes.toByteArray()), null);
		} catch (Exception e) {
			failures.add("passport: " + e);
		}

		HBCIUtils.init(new Properties(), new FinTSHelper.Callback(Map.of(), null));
		try {
			expect("network error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle", new java.net.ConnectException("Connection refused")))),
				"{\"type\":\"failed\",\"kind\":\"network\",\"text\":\"Connection refused\"}");
			expect("other error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle"))),
				"{\"type\":\"failed\",\"text\":\"can not create HBCI handle\"}");
			expect("bank directory", FinTSHelper.Json.write(FinTSHelper.bankInfo("76030080")),
				"{\"type\":\"bank\",\"name\":\"Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank\",\"bic\":\"CSDBDE71XXX\",\"url\":\"https://brokerage-hbci.consorsbank.de/hbci\"}");
			expect("unknown bank", FinTSHelper.Json.write(FinTSHelper.bankInfo("99999999")), "{\"type\":\"bank\"}");
		} finally {
			HBCIUtils.done();
		}

		for (String f : failures) System.out.println("FAILED " + f);
		System.out.println("FinTSHelper self-test: " + (checks - failures.size()) + " of " + checks + " checks passed");
		System.exit(failures.isEmpty() ? 0 : 1);
	}

	static String refusal(String url) {
		try {
			FinTSHelper.https(url);
			return "accepted";
		} catch (FinTSHelper.Failure f) {
			return f.kind + ": " + f.getMessage();
		}
	}
}
