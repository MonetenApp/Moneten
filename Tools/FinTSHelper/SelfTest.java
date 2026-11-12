// The checks of FinTSHelper that need no bank: java -cp … FinTSHelper --self-test. CI runs them.

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectOutputStream;
import java.io.PrintStream;
import java.lang.reflect.Method;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.TimeZone;

import javax.net.ssl.SSLHandshakeException;

import org.kapott.hbci.GV.parsers.ISEPAParser;
import org.kapott.hbci.GV.parsers.SEPAParserFactory;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.GVRSaldoReq;
import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.dialog.DialogContext;
import org.kapott.hbci.dialog.DialogEvent;
import org.kapott.hbci.exceptions.HBCI_Exception;
import org.kapott.hbci.exceptions.ProcessException;
import org.kapott.hbci.manager.HBCIUtils;
import org.kapott.hbci.passport.storage.PassportData;
import org.kapott.hbci.sepa.SepaVersion;
import org.kapott.hbci.status.HBCIDialogStatus;
import org.kapott.hbci.status.HBCIExecStatus;
import org.kapott.hbci.status.HBCIMsgStatus;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.structures.Konto;
import org.kapott.hbci.structures.Saldo;
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

	/// The lines that Tests/FinTSTests/helper-lines.jsonl holds, which FinTSConnectorTests decodes.
	static final List<String> fixture = new ArrayList<>();

	/// `args` holds the path of the fixture. A difference writes the new lines there and fails, so
	/// that the change shows in git and the Swift tests read what the helper sends today.
	static void run(String... args) {
		// hbci4java logs to System.out; the report of the checks goes to stdout alone.
		PrintStream report = System.out;
		System.setOut(System.err);
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

		Out.secret("geheim42");
		expect("PIN masked", Out.bank("PIN geheim42 sent"), "PIN ••• sent");
		expect("text of the bank left out", Out.bank("Fehler 9942:PIN falsch, Konto DE02120300000000202051"), "Fehler 9942 PIN wrong");

		PassportData data = new PassportData();
		data.blz = "12030000";
		data.sysId = "SYS-1";
		data.bpd = new Properties();
		data.bpd.setProperty("BPD.Params.KInfo", "x");
		data.twostepMechs = new ArrayList<>(List.of("921"));
		try {
			FinTSHelper.Passport.State back = FinTSHelper.Passport.deserialize(FinTSHelper.Passport.serialize(data, "Karte 1"));
			expect("passport round trip", back.data().blz + " " + back.data().sysId + " " + back.data().bpd + " " + back.data().twostepMechs + " " + back.tanMedium(),
				"12030000 SYS-1 {BPD.Params.KInfo=x} [921] Karte 1");
			ByteArrayOutputStream earlier = new ByteArrayOutputStream();
			try (ObjectOutputStream o = new ObjectOutputStream(earlier)) {
				o.writeObject(data);
			}
			FinTSHelper.Passport.State withoutMedium = FinTSHelper.Passport.deserialize(earlier.toByteArray());
			expect("state without a TAN medium", withoutMedium.data().sysId + " " + withoutMedium.tanMedium(), "SYS-1 null");
			ByteArrayOutputStream bytes = new ByteArrayOutputStream();
			try (ObjectOutputStream o = new ObjectOutputStream(bytes)) {
				o.writeObject(new java.util.Date(0));
			}
			expect("foreign class in the state refused", FinTSHelper.Passport.deserialize(bytes.toByteArray()), null);
		} catch (Exception e) {
			failures.add("passport: " + e);
		}

		expect("TAN medium asked once in a run", medium(null, "Handy|Karte 1", "Handy|Karte 1"), "Karte 1 Karte 1, asked 1");
		expect("TAN medium of the last refresh", medium("Handy", "Handy|Karte 1"), "Handy, asked 0");
		expect("TAN medium that the bank no longer offers", medium("Alte Karte", "Handy|Karte 1"), "Karte 1, asked 1");

		try {
			X509Certificate selfSigned = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(Base64.getDecoder().decode(
				"MIIBbjCCARSgAwIBAgIUZLBNL2oHyVE4uWYcY2AsrJoRs1wwCgYIKoZIzj0EAwIwHDEaMBgGA1UEAwwRZmludHMuZXhhbXBsZS5jb20wIBcNMjYxMTEyMDkwNzA2WhgPMjEyNjEwMTkwOTA3MDZaMBwxGjAYBgNVBAMMEWZpbnRzLmV4YW1wbGUuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAECfzMwKS0EZ30jfANBH637mHSfMao4flhFhxcprnVgHJkuHJBfW/6Q5nvVInTBjBMBtn5u2i4nhB+T3q+kd6NbqMyMDAwHQYDVR0OBBYEFLqzKE6BcWLapiQh64hKhdTm+St0MA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIga6Dk0TBJmqVRQeTtLDsObTgchRXljI06HpI4NcEQBtYCIQDXlOpNDsxpw0I/cMyiVP2D7QH5XZDWiEzLCC/FhVMICQ==")));
			expect("certificate trusted by macOS", trust(selfSigned, "trusted"), "accepted; trust fints.example.com 1");
			expect("certificate refused by macOS", trust(selfSigned, "The certificate of the bank's server fints.example.com is not valid: expired"),
				"The certificate of the bank's server fints.example.com is not valid: expired; trust fints.example.com 1");
			SSLHandshakeException handshake = new SSLHandshakeException("PKIX path validation failed");
			handshake.initCause(new CertificateException("The certificate of the bank's server fints.example.com is not valid: expired"));
			expect("certificate failure", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not connect", handshake))),
				"{\"type\":\"failed\",\"kind\":\"certificate\",\"text\":\"The certificate of the bank's server fints.example.com is not valid: expired\"}");
			expect("handshake failure", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not connect", new SSLHandshakeException("no cipher suites in common")))),
				"{\"type\":\"failed\",\"kind\":\"certificate\",\"text\":\"The certificate of the bank's server is not valid: no cipher suites in common\"}");
		} catch (Exception e) {
			failures.add("certificate: " + e);
		}

		HBCIUtils.init(new Properties(), new FinTSHelper.Callback(Map.of(), null));
		try {
			fixture.add(FinTSHelper.Json.write(FinTSHelper.result("DE02120300000000202051", "2026-10-01", balance("1096.20", "2026-11-03"), mt940(), false)));
			fixture.add(FinTSHelper.Json.write(FinTSHelper.result("1234567890", null, null, camt(), false)));
			GVRKUms undated = new GVRKUms();
			undated.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
			GVRKUms.BTag day = new GVRKUms.BTag();
			UmsLine pending = line("2026-11-09", "2026-11-09", "-1");
			pending.bdate = null;
			pending.valuta = null;
			day.addLine(pending);
			undated.getDataPerDay().add(day);
			String undatedLine = FinTSHelper.Json.write(FinTSHelper.alone("4711", () -> FinTSHelper.result("4711", null, null, undated, false)));
			fixture.add(undatedLine);
			expect("account without booking date fails alone", undatedLine,
				"{\"type\":\"accountFailed\",\"kind\":\"unsupported\",\"text\":\"The bank sent a transaction without a booking date, so nothing of this account was stored.\",\"account\":\"4711\"}");

			HBCIMsgStatus rejected = new HBCIMsgStatus();
			rejected.globStatus.addRetVal(new HBCIRetVal(null, null, null, "9050", "Teilweise fehlerhaft", null));
			rejected.segStatus.addRetVal(new HBCIRetVal(null, null, null, "9800", "Dialog abgebrochen", null));
			rejected.segStatus.addRetVal(new HBCIRetVal(null, null, null, "9942", "PIN falsch", null));
			expect("the error that needs action", FinTSHelper.Json.write(FinTSHelper.failure(new ProcessException("init", rejected))),
				"{\"type\":\"failed\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");

			HBCIExecStatus loginFailed = new HBCIExecStatus();
			HBCIDialogStatus dialog = new HBCIDialogStatus();
			dialog.setInitStatus(rejected);
			loginFailed.addDialogStatus("erika77", dialog);
			expect("login error before any job", FinTSHelper.Json.write(FinTSHelper.failure(thrown(() -> FinTSHelper.requireLogin(loginFailed)))),
				"{\"type\":\"failed\",\"code\":\"9942\",\"text\":\"PIN falsch\"}");
			HBCIExecStatus noDialog = new HBCIExecStatus();
			noDialog.addException("erika77", new HBCI_Exception("can not create dialog", new java.net.SocketTimeoutException("Read timed out")));
			expect("dialog that did not start", FinTSHelper.Json.write(FinTSHelper.failure(thrown(() -> FinTSHelper.requireLogin(noDialog)))),
				"{\"type\":\"failed\",\"kind\":\"network\",\"text\":\"Read timed out\"}");
			HBCIMsgStatus fine = new HBCIMsgStatus();
			fine.globStatus.addRetVal(new HBCIRetVal(null, null, null, "0010", "ok", null));
			HBCIDialogStatus started = new HBCIDialogStatus();
			started.setInitStatus(fine);
			HBCIExecStatus loggedIn = new HBCIExecStatus();
			loggedIn.addDialogStatus("erika77", started);
			expect("dialog that started", thrown(() -> FinTSHelper.requireLogin(loggedIn)), null);

			GVRKUms partial = new GVRKUms();
			partial.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3040", "Weitere Daten folgen", new String[] {"4711"}));
			expect("transactions in part fail the account", FinTSHelper.Json.write(FinTSHelper.alone("DE02120300000000202051",
				() -> FinTSHelper.result("DE02120300000000202051", null, null, partial, true))),
				"{\"type\":\"accountFailed\",\"code\":\"3040\",\"text\":\"The bank sent only part of the transactions, so nothing of this account was stored.\",\"account\":\"DE02120300000000202051\"}");

			expect("network error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle", new java.net.ConnectException("Connection refused")))),
				"{\"type\":\"failed\",\"kind\":\"network\",\"text\":\"Connection refused\"}");
			expect("other error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle"))),
				"{\"type\":\"failed\",\"text\":\"can not create HBCI handle\"}");
			expect("bank directory", FinTSHelper.Json.write(FinTSHelper.bankInfo("76030080")),
				"{\"type\":\"bank\",\"name\":\"Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank\",\"bic\":\"CSDBDE71XXX\",\"url\":\"https://brokerage-hbci.consorsbank.de/hbci\"}");
			expect("unknown bank", FinTSHelper.Json.write(FinTSHelper.bankInfo("99999999")), "{\"type\":\"bank\"}");
			pinTan();
		} finally {
			HBCIUtils.done();
		}

		if (args.length > 0) compare(Path.of(args[0]));
		for (String f : failures) report.println("FAILED " + f);
		report.println("FinTSHelper self-test: " + (checks - failures.size()) + " of " + checks + " checks passed");
		System.exit(failures.isEmpty() ? 0 : 1);
	}

	static void compare(Path file) {
		String lines = String.join("\n", fixture) + "\n";
		try {
			String before = Files.exists(file) ? Files.readString(file) : "";
			if (lines.equals(before)) return;
			Files.writeString(file, lines);
			failures.add("the lines of the helper changed, see git diff " + file);
		} catch (IOException e) {
			failures.add("fixture: " + e);
		}
	}

	static GVRSaldoReq balance(String amount, String day) {
		GVRSaldoReq result = new GVRSaldoReq();
		GVRSaldoReq.Info info = new GVRSaldoReq.Info();
		info.ready = new Saldo();
		info.ready.value = new Value(new BigDecimal(amount), "EUR");
		info.ready.timestamp = FinTSHelper.date(day);
		result.store(info);
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
		return result;
	}

	/// A statement of two days with made-up data, as hbci4java parses it from MT940.
	static GVRKUms mt940() {
		GVRKUms result = new GVRKUms();
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
		result.appendMT940Data(String.join("\r\n",
			":20:STARTUMS",
			":25:12030000/0000202051",
			":28C:00000/001",
			":60F:C261101EUR1000,00",
			":61:2611021102D23,80NDDTNONREF",
			":86:105?00FOLGELASTSCHRIFT?20EREF+RE-2026-1001?21MREF+M-4711?22CRED+DE98ZZZ09999999999?23SVWZ+Rechnung 1001?30BYLADEM1001?31DE0212030000000020",
			"2051?32Stadtwerke Musterstadt",
			":62F:C261102EUR976,20",
			"-",
			":20:STARTUMS",
			":25:12030000/0000202051",
			":28C:00000/002",
			":60F:C261102EUR976,20",
			":61:2611031103C120,00NTRFNONREF",
			":86:166?00GUTSCHRIFT?20Miete November?32Erika Mustermann",
			":62F:C261103EUR1096,20",
			"-") + "\r\n");
		return result;
	}

	/// A camt.052 report with one booked and one pending entry and made-up data, as hbci4java
	/// parses it.
	static GVRKUms camt() {
		GVRKUms result = new GVRKUms();
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
		try {
			parseCamt(report("BOOK", "2026-11-09", "46.12", "DBIT", "Coffee Shop", "SW-778899", "Kartenzahlung"), result.getDataPerDay());
			parseCamt(report("PDNG", "2026-11-10", "8.50", "DBIT", "Bäckerei Muster", "NOTPROVIDED", "Kartenzahlung Bäckerei"), result.getDataPerDayUnbooked());
		} catch (Exception e) {
			failures.add("camt: " + e);
		}
		return result;
	}

	@SuppressWarnings("unchecked")
	static void parseCamt(String xml, List<GVRKUms.BTag> days) {
		ISEPAParser<List<GVRKUms.BTag>> parser = SEPAParserFactory.get(SepaVersion.CAMT_052_001_08);
		parser.parse(new ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8)), days);
	}

	static String report(String status, String day, String amount, String direction, String name, String endToEnd, String purpose) {
		return """
			<?xml version="1.0" encoding="UTF-8"?>
			<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08">
			<BkToCstmrAcctRpt>
			<GrpHdr><MsgId>M1</MsgId><CreDtTm>%2$sT10:00:00</CreDtTm></GrpHdr>
			<Rpt>
			<Id>R1</Id>
			<Acct><Id><IBAN>DE02120300000000202051</IBAN></Id><Ccy>EUR</Ccy></Acct>
			<Bal><Tp><CdOrPrtry><Cd>PRCD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-11-08</Dt></Dt></Bal>
			<Ntry>
			<Amt Ccy="EUR">%3$s</Amt><CdtDbtInd>%4$s</CdtDbtInd><Sts><Cd>%1$s</Cd></Sts>
			<BookgDt><Dt>%2$s</Dt></BookgDt><ValDt><Dt>%2$s</Dt></ValDt>
			<NtryDtls><TxDtls>
			<Refs><EndToEndId>%6$s</EndToEndId><MndtId>M-1</MndtId></Refs>
			<RltdPties><Cdtr><Pty><Nm>%5$s</Nm></Pty></Cdtr><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties>
			<RmtInf><Ustrd>%7$s</Ustrd></RmtInf>
			</TxDtls></NtryDtls>
			</Ntry>
			</Rpt>
			</BkToCstmrAcctRpt>
			</Document>
			""".formatted(status, day, amount, direction, name, endToEnd, purpose);
	}

	/// A passport with made-up bank parameters: a PIN of 5 to 10 characters, and the methods pushTAN 2.0
	/// (an approval in the app), chipTAN QR, and mobileTAN with a TAN medium, all three allowed for the user.
	static FinTSHelper.Passport passport() {
		Properties bpd = new Properties();
		bpd.setProperty("Params_1.PinTanPar1.ParPinTan.pinlen_min", "5");
		bpd.setProperty("Params_1.PinTanPar1.ParPinTan.pinlen_max", "10");
		String[][] methods = {{"922", "pushTAN 2.0", "Decoupled", "Decoupled", ""}, {"913", "chipTAN QR", "", "Q1S", ""}, {"901", "mobileTAN", "mobileTAN", "mTAN", "2"}};
		for (int i = 0; i < methods.length; i++) {
			String header = "Params_2.TAN2StepPar6.ParTAN2Step.TAN2StepParams" + (i + 1) + ".";
			bpd.setProperty(header + "secfunc", methods[i][0]);
			bpd.setProperty(header + "name", methods[i][1]);
			bpd.setProperty(header + "zkamethod_name", methods[i][2]);
			bpd.setProperty(header + "id", methods[i][3]);
			bpd.setProperty(header + "needtanmedia", methods[i][4]);
		}
		PassportData d = new PassportData();
		d.country = "DE";
		d.blz = "12030000";
		d.host = "fints.example.com/fints";
		d.port = 443;
		d.userId = "erika77";
		d.customerId = "erika77";
		d.filter = "Base64";
		d.hbciVersion = "300";
		d.bpd = bpd;
		d.twostepMechs = new ArrayList<>(List.of("901", "913", "922"));
		d.tanMethod = "922";
		FinTSHelper.Passport.loaded = d;
		FinTSHelper.Passport passport = new FinTSHelper.Passport();
		FinTSHelper.Passport.loaded = null;
		return passport;
	}

	/// The requests of the callbacks for the PIN and the TAN, with made-up answers.
	static void pinTan() {
		FinTSHelper.Passport passport = passport();
		List<String> asked = new ArrayList<>();
		List<String> answers = new ArrayList<>(List.of("48151", "16234"));
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of(), null) {
			@Override
			String ask(Map<String, Object> request) {
				asked.add(FinTSHelper.Json.write(request));
				return answers.isEmpty() ? "" : answers.remove(0);
			}
		};
		StringBuffer data = new StringBuffer();
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_PIN, "", 0, data);
		expect("PIN request with the rules of the bank", String.join(" ", asked) + " -> " + data,
			"{\"type\":\"ask\",\"kind\":\"pin\",\"rules\":{\"type\":\"rules\",\"minLength\":5,\"maxLength\":10}} -> 48151");
		expect("PIN of the request masked in diagnostics", Out.bank("Anmeldung mit 48151 fehlgeschlagen"), "Anmeldung mit ••• fehlgeschlagen");
		data = new StringBuffer();
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_PIN, "", 0, data);
		expect("the next dialog of the run uses the PIN again", asked.size() + " -> " + data, "1 -> 48151");
		callback.callback(passport, FinTSHelper.Callback.WRONG_PIN, "", 0, new StringBuffer());
		data = new StringBuffer();
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_PIN, "", 0, data);
		expect("a rejected PIN is asked for again", asked.get(asked.size() - 1) + " -> " + data,
			"{\"type\":\"ask\",\"kind\":\"pin\",\"rejected\":{\"type\":\"rejected\",\"text\":\"The bank did not accept the PIN.\"},"
				+ "\"rules\":{\"type\":\"rules\",\"minLength\":5,\"maxLength\":10}} -> 16234");

		asked.clear();
		answers.add("901");
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_SECMECH, "", 0, new StringBuffer("901:mobileTAN|913:chipTAN QR|922:pushTAN 2.0"));
		String methods = "[{\"type\":\"method\",\"id\":\"901\",\"name\":\"mobileTAN\",\"medium\":true,\"delivery\":\"sms\"},"
			+ "{\"type\":\"method\",\"id\":\"913\",\"name\":\"chipTAN QR\",\"delivery\":\"qr\"},"
			+ "{\"type\":\"method\",\"id\":\"922\",\"name\":\"pushTAN 2.0\",\"delivery\":\"push\"}]";
		expect("TAN methods with their medium and what the bank sends", asked.get(0),
			"{\"type\":\"ask\",\"kind\":\"tanMethod\",\"purpose\":\"login\",\"methods\":" + methods + "}");

		asked.clear();
		answers.add("482915");
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "pushTAN 2.0\nHinweis\n\nBitte TAN eingeben", 0, new StringBuffer());
		expect("a TAN request offers the methods to change to", asked.get(0),
			"{\"type\":\"ask\",\"kind\":\"tan\",\"purpose\":\"login\",\"prompt\":\"Bitte TAN eingeben\",\"current\":\"922\",\"methods\":" + methods + "}");

		passport.setPersistentData(FinTSHelper.Passport.KEY_PD_HHDUC, "0388A01239230520422");
		passport.setPersistentData(FinTSHelper.Passport.KEY_PD_HHDUC, null);
		expect("challenge data without a flicker code", FinTSHelper.Json.write(FinTSHelper.failure(thrown(() ->
			callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "chipTAN optisch\n\n\nBitte TAN erzeugen", 0, new StringBuffer())))),
			"{\"type\":\"failed\",\"kind\":\"invalidChallenge\",\"text\":\"The bank responded with an invalid challenge.\"}");

		FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", "7", "method", "913")));
		Throwable changed = thrown(() -> FinTSHelper.Inbox.answer(7));
		expect("an answer with a method changes the method", changed instanceof FinTSHelper.SwitchMethod s ? s.method : changed, "913");
		FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", "8", "method", "901")));
		expect("a method chosen while the approval waits", FinTSHelper.Inbox.switchFor(8) + " " + FinTSHelper.Inbox.switchFor(8) + " " + FinTSHelper.Inbox.queue.size(),
			"901 null 0");
		callback.switchTo = "913";
		expect("no request after a change of the method",
			thrown(() -> callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "", 0, new StringBuffer())) instanceof FinTSHelper.SwitchMethod, true);
		expect("a connection after a change of the method, for the end of the old dialog",
			thrown(() -> callback.callback(passport, FinTSHelper.Callback.NEED_CONNECTION, "", 0, new StringBuffer())), null);

		HBCIMsgStatus answer = new HBCIMsgStatus();
		answer.globStatus.addRetVal(new HBCIRetVal(null, null, null, "3955", "Sicherheitsfreigabe erfolgt über anderen Kanal", null));
		answer.getData().setProperty("MsgHead.dialogid", "D-4711");
		try {
			DialogContext login = DialogContext.create(null, passport);
			Method update = DialogContext.class.getDeclaredMethod("update", HBCIMsgStatus.class);
			update.setAccessible(true);
			update.invoke(login, answer);
			thrown(() -> passport.onDialogEvent(DialogEvent.MSG_SENT, login));
		} catch (ReflectiveOperationException e) {
			failures.add("dialog context: " + e);
		}
		expect("the dialog that the bank keeps open after a change of the method", passport.open == null ? null : passport.open.getDialogId(), "D-4711");
		callback.status(passport, FinTSHelper.Callback.STATUS_DIALOG_END_DONE, new Object[] {answer});
		expect("a dialog that hbci4java ended", passport.open, null);
	}

	/// The TAN media that hbci4java gets for each list of media it offers, starting from the medium
	/// of the state. The user would choose "Karte 1".
	static String medium(String saved, String... offers) {
		int[] asked = {0};
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of(), null) {
			@Override
			String ask(Map<String, Object> request) {
				asked[0]++;
				return "Karte 1";
			}
		};
		callback.tanMedium = saved;
		List<String> chosen = new ArrayList<>();
		for (String offer : offers) {
			StringBuffer data = new StringBuffer(offer);
			callback.callback(null, FinTSHelper.Callback.NEED_PT_TANMEDIA, "", 0, data);
			chosen.add(data.toString());
		}
		return String.join(" ", chosen) + ", asked " + asked[0];
	}

	/// What MacTrust makes of the verdict of the app for a server fints.example.com, and the request
	/// it sent.
	static String trust(X509Certificate certificate, String verdict) {
		List<String> sent = new ArrayList<>();
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of(), null) {
			@Override
			String ask(Map<String, Object> request) {
				sent.add(request.get("type") + " " + request.get("host") + " " + ((List<?>) request.get("chain")).size());
				return verdict;
			}
		};
		String outcome;
		try {
			new FinTSHelper.MacTrust(callback).check(new X509Certificate[] {certificate}, "fints.example.com");
			outcome = "accepted";
		} catch (CertificateException e) {
			outcome = e.getMessage();
		}
		return outcome + "; " + String.join(", ", sent);
	}

	static Throwable thrown(Runnable run) {
		try {
			run.run();
			return null;
		} catch (RuntimeException e) {
			return e;
		}
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
