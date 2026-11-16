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
import org.kapott.hbci.GV_Result.GVRWPDepotList;
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
import org.kapott.hbci.structures.BigDecimalValue;
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

		expect("plain HTTP refused", refusal(() -> FinTSHelper.https("http://bank.example/fints")), "unsupported: The bank offers no encrypted FinTS address.");
		expect("address without host refused", refusal(() -> FinTSHelper.https("https:///fints")), "unsupported: The bank offers no encrypted FinTS address.");
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

		HBCIUtils.init(new Properties(), new FinTSHelper.Callback(Map.of()));
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

			securities();

			expect("network error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle", new java.net.ConnectException("Connection refused")))),
				"{\"type\":\"failed\",\"kind\":\"network\",\"text\":\"Connection refused\"}");
			expect("other error", FinTSHelper.Json.write(FinTSHelper.failure(new HBCI_Exception("can not create HBCI handle"))),
				"{\"type\":\"failed\",\"text\":\"can not create HBCI handle\"}");
			List<?> directory = (List<?>) FinTSHelper.banks().get("banks");
			expect("bank directory with every bank", directory.size() > 4000, true);
			expect("bank in the directory", directory.stream().map(FinTSHelper.Json::write).filter(b -> b.contains("\"76030080\"")).toList(),
				List.of("{\"code\":\"76030080\",\"name\":\"Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank\",\"city\":\"Nürnberg, Mittelfr\",\"bic\":\"CSDBDE71XXX\",\"url\":\"https://brokerage-hbci.consorsbank.de/hbci\"}"));
			expect("bank without a FinTS address", directory.stream().map(FinTSHelper.Json::write).filter(b -> b.contains("\"10010424\"")).toList(),
				List.of("{\"code\":\"10010424\",\"name\":\"Aareal Bank\",\"city\":\"Berlin\",\"bic\":\"AARBDE5W100\"}"));
			FinTSHelper.Callback moved = new FinTSHelper.Callback(Map.of("bankCode", "76030080", "url", "https://hbci.old.example/hbci"));
			moved.connect();
			expect("address of the directory replaces the stored one", moved.host + " " + moved.port, "brokerage-hbci.consorsbank.de/hbci 443");
			expect("bank without a FinTS address in the directory refused", refusal(() -> new FinTSHelper.Callback(
				Map.of("bankCode", "10010424", "url", "https://fints.musterbank.example/fints")).connect()), "unsupported: The bank offers no FinTS address.");
			pinTan();
			historyDialog();
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

	/// The value of a securities account from the custody account balance (HKWPD), and what fails it.
	static void securities() {
		Konto depot = new Konto(), fund = new Konto(), giro = new Konto(), untyped = new Konto();
		depot.acctype = "30";
		fund.acctype = "69";
		giro.acctype = "1";
		expect("securities accounts by their type", FinTSHelper.securities(depot) + " " + FinTSHelper.securities(fund) + " "
			+ FinTSHelper.securities(giro) + " " + FinTSHelper.securities(untyped), "true true false false");
		expect("securities accounts by their jobs", FinTSHelper.securities(allowing(null, "HKWPD", "HKWDU")) + " " + FinTSHelper.securities(allowing("", "HKWDU"))
			+ " " + FinTSHelper.securities(allowing(null, "HKWPD", "HKSAL")) + " " + FinTSHelper.securities(allowing("1", "HKWPD", "HKKAZ"))
			+ " " + FinTSHelper.securities(allowing(null, "HKWPD", "HKCAZ")), "true true false false false");
		// The jobs decide also for an account with another type: an account that allows only depot jobs is a depot.
		expect("accounts of another type with depot jobs only are securities accounts", FinTSHelper.securities(allowing("1", "HKWPD")) + " "
			+ FinTSHelper.securities(allowing("50", "HKWDU")), "true true");
		Konto untypedDepot = allowing(null, "HKWPD", "HKWDU");
		untypedDepot.number = "7654326";
		untypedDepot.curr = "EUR";
		expect("depot without a type is listed as a securities account", FinTSHelper.Json.write(FinTSHelper.account(untypedDepot)),
			"{\"type\":\"account\",\"number\":\"7654326\",\"currency\":\"EUR\",\"securities\":true}");
		Konto listedGiro = allowing("1", "HKWPD", "HKSAL", "HKKAZ");
		listedGiro.number = "202051";
		listedGiro.curr = "EUR";
		expect("giro account is listed with its type only", FinTSHelper.Json.write(FinTSHelper.account(listedGiro)),
			"{\"type\":\"account\",\"number\":\"202051\",\"kind\":\"1\",\"currency\":\"EUR\"}");

		String valued = FinTSHelper.Json.write(FinTSHelper.alone("7654321", () -> FinTSHelper.value("7654321",
			holdings("2026-11-12", new BigDecimalValue(new BigDecimal("24518.37"), "EUR"), holding("10000.00", "EUR")), false, "EUR")));
		fixture.add(valued);
		expect("securities account with the total of the bank", valued,
			"{\"type\":\"result\",\"account\":\"7654321\",\"balance\":{\"type\":\"balance\",\"amount\":\"24518.37\",\"currency\":\"EUR\",\"date\":\"2026-11-12\"},\"errors\":[],\"securities\":true,"
				+ "\"holdings\":[{\"type\":\"holding\",\"isin\":\"DE0001234567\",\"quantity\":\"1\",\"value\":{\"type\":\"amount\",\"amount\":\"10000.00\",\"currency\":\"EUR\"}}]}");
		expect("securities account without a total is the sum of its holdings", FinTSHelper.Json.write(FinTSHelper.value("7654321",
			holdings("2026-11-12", null, holding("10000.00", "EUR"), holding("4518.37", "EUR")), false, "EUR")),
			"{\"type\":\"result\",\"account\":\"7654321\",\"balance\":{\"type\":\"balance\",\"amount\":\"14518.37\",\"currency\":\"EUR\",\"date\":\"2026-11-12\"},\"errors\":[],\"securities\":true,"
				+ "\"holdings\":[{\"type\":\"holding\",\"isin\":\"DE0001234567\",\"quantity\":\"1\",\"value\":{\"type\":\"amount\",\"amount\":\"10000.00\",\"currency\":\"EUR\"}},"
				+ "{\"type\":\"holding\",\"isin\":\"DE0001234567\",\"quantity\":\"1\",\"value\":{\"type\":\"amount\",\"amount\":\"4518.37\",\"currency\":\"EUR\"}}]}");

		// Every field of a position that hbci4java parses from MT535 and the app shows, with made-up values.
		GVRWPDepotList.Entry.Gattung share = holding("1000.00", "EUR");
		share.name = "Musterwerke AG";
		share.wkn = "123456";
		share.saldo = new BigDecimalValue(new BigDecimal("40.12345"), "");
		share.price = new BigDecimalValue(new BigDecimal("27.123456"), "USD");
		share.timestamp_price = FinTSHelper.date("2026-11-11");
		share.stueckzinsbetrag = new BigDecimalValue(new BigDecimal("0.10"), "EUR");
		share.einstandspreis = new BigDecimalValue(new BigDecimal("20.5"), "USD");
		share.kauf = FinTSHelper.date("2024-03-01");
		share.curr = "USD";
		share.xchg_cur1 = "EUR";
		share.xchg_cur2 = "USD";
		share.xchg_kurs = 1.0845;
		GVRWPDepotList.Entry.Gattung nominal = holding("4925.00", "EUR");
		nominal.isin = null;
		nominal.name = "Anleihe Musterland";
		nominal.saldo_type = GVRWPDepotList.Entry.SALDO_TYPE_WERT;
		nominal.saldo = new BigDecimalValue(new BigDecimal("5000"), "");
		nominal.price = new BigDecimalValue(new BigDecimal("98.5"), "%");
		nominal.einstandspreis = new BigDecimalValue(new BigDecimal("97"), "%");
		String positions = FinTSHelper.Json.write(FinTSHelper.alone("7654326", () -> FinTSHelper.value("7654326",
			holdings("2026-11-12", new BigDecimalValue(new BigDecimal("5925.10"), "EUR"), share, nominal), false, "EUR")));
		fixture.add(positions);
		expect("securities account with its positions", positions,
			"{\"type\":\"result\",\"account\":\"7654326\",\"balance\":{\"type\":\"balance\",\"amount\":\"5925.10\",\"currency\":\"EUR\",\"date\":\"2026-11-12\"},"
				+ "\"errors\":[],\"securities\":true,\"holdings\":[{\"type\":\"holding\",\"name\":\"Musterwerke AG\",\"isin\":\"DE0001234567\",\"wkn\":\"123456\","
				+ "\"quantity\":\"40.12345\",\"currency\":\"USD\",\"price\":{\"type\":\"amount\",\"amount\":\"27.123456\",\"currency\":\"USD\",\"day\":\"2026-11-11\"},"
				+ "\"value\":{\"type\":\"amount\",\"amount\":\"1000.00\",\"currency\":\"EUR\"},\"accrued\":{\"type\":\"amount\",\"amount\":\"0.10\",\"currency\":\"EUR\"},"
				+ "\"purchase\":{\"type\":\"amount\",\"amount\":\"20.5\",\"currency\":\"USD\",\"day\":\"2024-03-01\"},"
				+ "\"rate\":{\"type\":\"rate\",\"base\":\"EUR\",\"quoted\":\"USD\",\"rate\":\"1.0845\"}},"
				+ "{\"type\":\"holding\",\"name\":\"Anleihe Musterland\",\"quantity\":\"5000\",\"nominal\":true,\"price\":{\"type\":\"amount\",\"amount\":\"98.5\",\"currency\":\"%\"},"
				+ "\"value\":{\"type\":\"amount\",\"amount\":\"4925.00\",\"currency\":\"EUR\"},\"purchase\":{\"type\":\"amount\",\"amount\":\"97\",\"currency\":\"%\"}}]}");
		GVRWPDepotList.Entry.Gattung unnamed = holding("10.00", "EUR");
		unnamed.price = new BigDecimalValue(new BigDecimal("10"), "EUR");
		unnamed.xchg_kurs = 1.1;
		expect("a position without a name, a price day, and a pair of currencies sends no rate", FinTSHelper.Json.write(FinTSHelper.position(unnamed)),
			"{\"type\":\"holding\",\"isin\":\"DE0001234567\",\"quantity\":\"1\",\"price\":{\"type\":\"amount\",\"amount\":\"10\",\"currency\":\"EUR\"},"
				+ "\"value\":{\"type\":\"amount\",\"amount\":\"10.00\",\"currency\":\"EUR\"}}");

		GVRWPDepotList pages = holdings("2026-11-12", new BigDecimalValue(new BigDecimal("10000.00"), "EUR"), holding("10000.00", "EUR"));
		pages.addEntry(holdings("2026-11-12", null, holding("15000.50", "EUR")).getEntries()[0]);
		expect("securities account in two pages is the sum of both", FinTSHelper.value("7654321", pages, false, "EUR").get("balance").toString(),
			"{type=balance, amount=25000.50, currency=EUR, date=2026-11-12}");

		String noValue = FinTSHelper.Json.write(FinTSHelper.alone("7654322", () -> FinTSHelper.value("7654322",
			holdings("2026-11-12", null, holding("10000.00", "EUR"), holding("4518.37", "USD")), false, "EUR")));
		fixture.add(noValue);
		expect("securities account without a value fails", noValue,
			"{\"type\":\"accountFailed\",\"kind\":\"unsupported\",\"text\":\"The bank sent no value for this securities account.\",\"account\":\"7654322\"}");
		GVRWPDepotList.Entry.Gattung unvalued = holding("1.00", "EUR");
		unvalued.depotwert = null;
		expect("securities account with a holding without a value fails", FinTSHelper.alone("7654322", () -> FinTSHelper.value("7654322",
			holdings("2026-11-12", null, holding("10000.00", "EUR"), unvalued), false, "EUR")).get("text"), "The bank sent no value for this securities account.");
		String empty = FinTSHelper.Json.write(FinTSHelper.alone("7654325", () -> FinTSHelper.value("7654325", holdings("2026-11-13", null), false, "EUR")));
		fixture.add(empty);
		expect("empty securities account is worth 0", empty,
			"{\"type\":\"result\",\"account\":\"7654325\",\"balance\":{\"type\":\"balance\",\"amount\":\"0\",\"currency\":\"EUR\",\"date\":\"2026-11-13\"},\"errors\":[],\"securities\":true,\"holdings\":[]}");
		expect("empty securities account without a currency counts in euro", String.valueOf(FinTSHelper.alone("7654325", () -> FinTSHelper.value("7654325", holdings("2026-11-13", null), false, null))
			.get("balance")), "{type=balance, amount=0, currency=EUR, date=2026-11-13}");

		// The MT535 example of FinTS 4.1 Messages - Finanzdatenformate (20.01.2014), pages 172 to 174: the
		// first HOLD and ACRU of each holding, in the currency of HOLP, add up to its HOLP of EUR 17026,37.
		GVRWPDepotList.Entry.Gattung bond = holding("6294.65", "EUR");
		bond.stueckzinsbetrag = new BigDecimalValue(new BigDecimal("1.72"), "EUR");
		expect("a holding counts with its accrued interest", String.valueOf(FinTSHelper.alone("7654321", () -> FinTSHelper.value("7654321",
			holdings("2026-11-12", null, holding("5270", "EUR"), holding("5460", "EUR"), bond), false, "EUR")).get("balance")),
			"{type=balance, amount=17026.37, currency=EUR, date=2026-11-12}");
		GVRWPDepotList noted = holdings("2026-11-12", new BigDecimalValue(new BigDecimal("24518.37"), "EUR"), holding("24518.37", "EUR"));
		noted.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3010", "Keine Einträge vorhanden", null));
		expect("a statement with a note keeps its value", String.valueOf(FinTSHelper.alone("7654321", () -> FinTSHelper.value("7654321", noted, false, "EUR"))
			.get("balance")), "{type=balance, amount=24518.37, currency=EUR, date=2026-11-12}");
		GVRWPDepotList noEntries = new GVRWPDepotList();
		noEntries.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3010", "Keine Einträge vorhanden", null));
		expect("an answer with a note and without a statement shows the note", FinTSHelper.Json.write(FinTSHelper.alone("7654325", () -> FinTSHelper.value("7654325",
			noEntries, false, "EUR"))), "{\"type\":\"result\",\"account\":\"7654325\",\"errors\":[{\"type\":\"error\",\"code\":\"3010\",\"text\":\"Keine Einträge vorhanden\"}]}");
		GVRWPDepotList unexplained = new GVRWPDepotList();
		unexplained.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "Auftrag ausgeführt", null));
		expect("an answer without entries and without 3010 fails", FinTSHelper.alone("7654325", () -> FinTSHelper.value("7654325", unexplained, false, "EUR"))
			.get("text"), "The bank sent no value for this securities account.");

		GVRWPDepotList refused = new GVRWPDepotList();
		refused.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "9160", "Erforderliche Auftragsreferenz fehlt", null));
		String refusedLine = FinTSHelper.Json.write(FinTSHelper.alone("7654323", () -> FinTSHelper.value("7654323", refused, false, "EUR")));
		fixture.add(refusedLine);
		expect("securities account that the bank refuses", refusedLine,
			"{\"type\":\"result\",\"account\":\"7654323\",\"errors\":[{\"type\":\"error\",\"code\":\"9160\",\"text\":\"Erforderliche Auftragsreferenz fehlt\"}]}");

		expect("securities account in part fails", FinTSHelper.alone("7654321", () -> FinTSHelper.value("7654321",
			holdings("2026-11-12", null, holding("10000.00", "EUR")), true, "EUR")).get("code"), "3040");

		// With allowedGVs set, the choice never asks the handler.
		expect("jobs of a securities account with HKWPD", FinTSHelper.jobs(null, allowing("30", "HKWPD", "HKSAL")), "[WPDepotList]");
		expect("jobs of a securities account with the balance only", FinTSHelper.jobs(null, allowing("30", "HKSAL")), "[SaldoReq]");
		expect("jobs of a securities account with neither", FinTSHelper.jobs(null, allowing("30", "HKUEB")), "[]");
		expect("jobs of a giro account that lists HKWPD", FinTSHelper.jobs(null, allowing("1", "HKWPD", "HKSAL", "HKKAZ")), "[SaldoReq, KUmsAll]");
		expect("jobs of a giro account with CAMT", FinTSHelper.jobs(null, allowing("1", "HKSAL", "HKCAZ", "HKKAZ")), "[SaldoReq, KUmsAllCamt]");
		expect("jobs of a depot without a type", FinTSHelper.jobs(null, allowing(null, "HKWPD", "HKWDU")), "[WPDepotList]");
		expect("jobs of an account without a type that has the balance", FinTSHelper.jobs(null, allowing(null, "HKWPD", "HKSAL")), "[SaldoReq]");
		String unreadable = FinTSHelper.Json.write(FinTSHelper.nothingAllowed("7654324", allowing("30", "HKUEB")));
		fixture.add(unreadable);
		expect("securities account without HKWPD, HKSAL, and HKKAZ", unreadable,
			"{\"type\":\"accountFailed\",\"account\":\"7654324\",\"kind\":\"unsupported\",\"text\":\"Moneten can't read this securities account at this bank yet.\"}");
		expect("giro account without HKSAL and HKKAZ", FinTSHelper.nothingAllowed("1234567890", allowing("1", "HKUEB")).get("text"),
			"The FinTS server of the bank offers neither the balance nor the transactions of this account.");
		expect("depot without a type and without HKWPD", FinTSHelper.nothingAllowed("7654327", allowing(null, "HKWDU")).get("text"),
			"Moneten can't read this securities account at this bank yet.");
		Konto unreadableDepot = allowing(null, "HKWDU", "HKUEB");
		unreadableDepot.number = "7654327";
		unreadableDepot.iban = "DE02120300000000202051";
		unreadableDepot.name = "Erika Mustermann";
		expect("diagnostic of a depot without jobs holds only its type and its allowed jobs", Out.bank(FinTSHelper.withoutJobs(unreadableDepot)),
			"FinTSHelper: account without jobs: type=none allowed=HKWDU,HKUEB");
		expect("diagnostic of a giro account without jobs", Out.bank(FinTSHelper.withoutJobs(allowing(" 1 ", "HKUEB"))),
			"FinTSHelper: account without jobs: type=1 allowed=HKUEB");
		expect("diagnostic of an account whose bank lists no jobs", Out.bank(FinTSHelper.withoutJobs(new Konto())),
			"FinTSHelper: account without jobs: type=none allowed=none");

		Properties bpd = new Properties();
		String[] orders = {"HKSAL", "HKKAZ", "HKCAZ", "HKWPD", "HKTAN"};
		for (int i = 0; i < orders.length; i++) {
			bpd.setProperty("Params_" + (i + 1) + ".PinTanPar1.ParPinTan.PinTanGV_" + (i + 1) + ".segcode", orders[i]);
			bpd.setProperty("Params_" + (i + 1) + ".PinTanPar1.ParPinTan.PinTanGV_" + (i + 1) + ".needtan", orders[i].equals("HKWPD") ? "J" : "N");
		}
		Properties other = (Properties) bpd.clone();
		FinTSHelper.applyTanRules("76030080", bpd);
		FinTSHelper.applyTanRules("12030000", other);
		expect("Consorsbank: HKSAL and HKKAZ with HKTAN, HKWPD without", needtan(bpd, orders), "HKSAL=J HKKAZ=J HKCAZ=J HKWPD=N HKTAN=N");
		expect("other banks: HKTAN as their parameters say", needtan(other, orders), "HKSAL=N HKKAZ=N HKCAZ=N HKWPD=J HKTAN=N");
	}

	static String needtan(Properties bpd, String[] orders) {
		List<String> all = new ArrayList<>();
		for (int i = 0; i < orders.length; i++) all.add(orders[i] + "=" + bpd.getProperty("Params_" + (i + 1) + ".PinTanPar1.ParPinTan.PinTanGV_" + (i + 1) + ".needtan"));
		return String.join(" ", all);
	}

	/// A custody account balance as hbci4java parses it from MT535: the statement of one day, the total
	/// of the bank when it sends one, and the holdings with their values.
	static GVRWPDepotList holdings(String day, BigDecimalValue total, GVRWPDepotList.Entry.Gattung... positions) {
		GVRWPDepotList result = new GVRWPDepotList();
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "ok", null));
		GVRWPDepotList.Entry entry = new GVRWPDepotList.Entry();
		entry.timestamp = FinTSHelper.date(day);
		entry.total = total;
		for (GVRWPDepotList.Entry.Gattung g : positions) entry.addEntry(g);
		result.addEntry(entry);
		return result;
	}

	/// An account of the FinTS type `type` that the bank parameters allow `orders` for.
	static Konto allowing(String type, String... orders) {
		Konto k = new Konto();
		k.acctype = type;
		k.allowedGVs = new ArrayList<>(List.of(orders));
		return k;
	}

	static GVRWPDepotList.Entry.Gattung holding(String value, String currency) {
		GVRWPDepotList.Entry.Gattung g = new GVRWPDepotList.Entry.Gattung();
		g.isin = "DE0001234567";
		g.saldo_type = GVRWPDepotList.Entry.SALDO_TYPE_STCK;
		g.saldo = new BigDecimalValue(BigDecimal.ONE, "");
		g.depotwert = new BigDecimalValue(new BigDecimal(value), currency);
		return g;
	}

	/// A passport with made-up bank parameters: a PIN of 5 to 10 characters, and the methods pushTAN 2.0
	/// (an approval in the app), chipTAN QR, and mobileTAN with a TAN medium, all three allowed for the user.
	static FinTSHelper.Passport passport() {
		FinTSHelper.Passport.loaded = passportData();
		FinTSHelper.Passport passport = new FinTSHelper.Passport();
		FinTSHelper.Passport.loaded = null;
		return passport;
	}

	static PassportData passportData() {
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
		return d;
	}

	/// The requests of the callbacks for the PIN and the TAN, with made-up answers.
	static void pinTan() {
		FinTSHelper.Passport passport = passport();
		List<String> asked = new ArrayList<>();
		List<String> answers = new ArrayList<>(List.of("48151", "16234"));
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of()) {
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

		history(passport, callback, asked, answers);

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

	/// The purpose of a challenge, the mark of a challenge that may be for older transactions, and the 90 days
	/// after the user canceled it (task 1.9 of add-fints-banking).
	static void history(FinTSHelper.Passport passport, FinTSHelper.Callback callback, List<String> asked, List<String> answers) {
		FinTSHelper.Passport sending = passport();
		try {
			DialogContext dialog = DialogContext.create(null, sending);
			thrown(() -> sending.onDialogEvent(DialogEvent.JOBS_CREATED, dialog));
		} catch (RuntimeException e) {
			failures.add("dialog context: " + e);
		}
		expect("hbci4java sent the orders, so a challenge from then on is for the download", sending.jobsSent + " " + FinTSHelper.Callback.purpose(sending),
			"true download");
		callback.fullHistory = true;
		asked.clear();
		answers.add("482915");
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "pushTAN 2.0\n\nBitte TAN eingeben", 0, new StringBuffer());
		expect("a challenge before the orders is for the login, also in a refresh of the full history", asked.get(0).contains("\"purpose\":\"login\"")
			+ " " + asked.get(0).contains("history"), "true false");
		passport.jobsSent = true;
		asked.clear();
		answers.add("482915");
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "pushTAN 2.0\n\nBitte TAN eingeben", 0, new StringBuffer());
		expect("a challenge after the orders of a refresh of the full history may be for older transactions",
			asked.get(0).contains("\"purpose\":\"download\"") + " " + asked.get(0).contains("\"history\":true"), "true true");
		callback.fullHistory = false;
		asked.clear();
		answers.add("482915");
		callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN, "pushTAN 2.0\n\nBitte TAN eingeben", 0, new StringBuffer());
		expect("a challenge of a refresh of 90 days is not for older transactions", asked.get(0).contains("history"), false);
		passport.jobsSent = false;

		FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", "9", "skip", true)));
		expect("a skipped challenge ends the dialog", thrown(() -> FinTSHelper.Inbox.answer(9)) instanceof FinTSHelper.SkipHistory, true);
		FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", "10", "skip", true)));
		expect("an approval for older transactions that the user canceled", FinTSHelper.Inbox.skipped(10) + " " + FinTSHelper.Inbox.skipped(10)
			+ " " + FinTSHelper.Inbox.queue.size(), "true false 0");
		java.time.LocalDate today = java.time.LocalDate.of(2026, 11, 15);
		expect("after a canceled challenge for older transactions the full history becomes 90 days, and a first day stays",
			FinTSHelper.from(Map.of("id", "DE02120300000000202051"), true, today) + " " + FinTSHelper.from(Map.of("id", "1234567890", "from", "2026-11-01"), true, today)
				+ " " + FinTSHelper.from(Map.of("id", "DE02120300000000202051"), false, today), "2026-08-17 2026-11-01 null");
		FinTSHelper.Callback restarting = new FinTSHelper.Callback(Map.of());
		restarting.skipHistory = true;
		restarting.fullHistory = true;
		expect("the next dialog after a canceled challenge for older transactions", restarting.restarts() + " "
			+ (thrown(restarting::checkSwitch) instanceof FinTSHelper.SkipHistory), "true true");
		restarting.restart();
		expect("asks for 90 days and asks the user nothing more for the old dialog", restarting.narrowed + " " + restarting.restarts() + " "
			+ restarting.fullHistory, "true false false");
	}

	/// The TAN media that hbci4java gets for each list of media it offers, starting from the medium
	/// of the state. The user would choose "Karte 1".
	static String medium(String saved, String... offers) {
		int[] asked = {0};
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of()) {
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
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of()) {
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

	static String refusal(Runnable run) {
		try {
			run.run();
			return "accepted";
		} catch (FinTSHelper.Failure f) {
			return f.kind + ": " + f.getMessage();
		}
	}

	/// The lines that the helper sends to the app while `run` runs.
	static List<String> sent(Runnable run) {
		java.io.PrintStream app = FinTSHelper.out;
		ByteArrayOutputStream bytes = new ByteArrayOutputStream();
		FinTSHelper.out = new java.io.PrintStream(bytes, true, StandardCharsets.UTF_8);
		try {
			run.run();
		} finally {
			FinTSHelper.out = app;
		}
		String text = bytes.toString(StandardCharsets.UTF_8);
		return text.isEmpty() ? List.of() : List.of(text.split("\n"));
	}

	/// An order that records the first day it asks for.
	static org.kapott.hbci.GV.HBCIJob job(List<String> startdates) {
		return (org.kapott.hbci.GV.HBCIJob) java.lang.reflect.Proxy.newProxyInstance(SelfTest.class.getClassLoader(),
			new Class<?>[] {org.kapott.hbci.GV.HBCIJob.class}, (proxy, method, args) -> {
				if (method.getName().equals("setParam") && "startdate".equals(args[0])) startdates.add(FinTSHelper.day((java.util.Date) args[1]));
				return null;
			});
	}

	/// A made-up bank with the account "Girokonto" for a dialog without a network. `during` runs while the bank
	/// answers the orders.
	record MadeUpBank(FinTSHelper.Callback callback, List<String> startdates, List<Boolean> fullHistory, Runnable during) implements FinTSHelper.Orders {
		public Konto[] accounts() {
			Konto giro = new Konto();
			giro.iban = "DE02120300000000202051";
			giro.curr = "EUR";
			return new Konto[] {giro};
		}

		public List<String> jobs(Konto k) {
			return List.of("SaldoReq", "KUmsAll");
		}

		public org.kapott.hbci.GV.HBCIJob newJob(String name) {
			return job(startdates);
		}

		public HBCIExecStatus execute() {
			fullHistory.add(callback.fullHistory);
			during.run();
			return new HBCIExecStatus();
		}

		public void close() {
		}
	}

	/// A refresh of the full history in a dialog with a made-up bank: what it asks for, and how a cancel of the
	/// challenge for older transactions ends the dialog for one of 90 days (task 1.9 of add-fints-banking).
	static void historyDialog() {
		String ninety = java.time.LocalDate.now().minusDays(90).toString();
		List<Map<String, Object>> requested = List.of(Map.of("id", "DE02120300000000202051"));
		FinTSHelper.Passport passport = passport();

		FinTSHelper.Callback full = new FinTSHelper.Callback(Map.of());
		MadeUpBank bank = new MadeUpBank(full, new ArrayList<>(), new ArrayList<>(), () -> { });
		List<String> lines = sent(() -> FinTSHelper.refresh(bank, passport, bank.accounts(), requested, full));
		expect("a refresh of the full history marks its challenges, and asks from no first day", bank.fullHistory() + " " + bank.startdates(), "[true] []");
		expect("a refresh without a cancel ends with the result of the account", lines.get(lines.size() - 1).contains("\"account\":\"DE02120300000000202051\""), true);

		FinTSHelper.Callback narrowed = new FinTSHelper.Callback(Map.of());
		narrowed.narrowed = true;
		MadeUpBank ninetyDays = new MadeUpBank(narrowed, new ArrayList<>(), new ArrayList<>(), () -> { });
		sent(() -> FinTSHelper.refresh(ninetyDays, passport, ninetyDays.accounts(), requested, narrowed));
		expect("after a canceled challenge for older transactions the refresh asks for 90 days", ninetyDays.fullHistory() + " " + ninetyDays.startdates(),
			"[false] [" + ninety + "]");

		// The bank asks for an approval of older transactions. The user rejects it in the banking app and cancels it
		// in Moneten, and the answer of the bank arrives before hbci4java checks the approval again.
		for (boolean crossed : new boolean[] {false, true}) {
			FinTSHelper.Callback racing = new FinTSHelper.Callback(Map.of());
			MadeUpBank refused = new MadeUpBank(racing, new ArrayList<>(), new ArrayList<>(), () -> {
				passport.jobsSent = true;
				racing.callback(passport, FinTSHelper.Callback.NEED_PT_DECOUPLED, "pushTAN 2.0\n\nBitte bestätigen Sie den Abruf.", 0, new StringBuffer());
				// hbci4java went on and withdrew the approval before the cancel reached the helper.
				if (crossed) racing.withdrawApproval();
				FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", String.valueOf(racing.lastApproval), "skip", true)));
			});
			Throwable[] ended = new Throwable[1];
			List<String> racingLines = sent(() -> ended[0] = thrown(() -> FinTSHelper.refresh(refused, passport, refused.accounts(), requested, racing)));
			passport.jobsSent = false;
			FinTSHelper.Inbox.queue.clear();
			expect("a cancel for older transactions that " + (crossed ? "crossed the withdrawal" : "came before the answer of the bank")
				+ " ends the dialog before any result", (ended[0] instanceof FinTSHelper.SkipHistory) + " " + racingLines.stream().anyMatch(l -> l.contains("\"account\"")),
				"true false");
		}
		FinTSHelper.Callback unasked = new FinTSHelper.Callback(Map.of());
		MadeUpBank refusal = new MadeUpBank(unasked, new ArrayList<>(), new ArrayList<>(), () -> {
			passport.jobsSent = true;
			unasked.callback(passport, FinTSHelper.Callback.NEED_PT_DECOUPLED, "pushTAN 2.0\n\nBitte bestätigen Sie den Abruf.", 0, new StringBuffer());
		});
		Throwable[] refusedAlone = new Throwable[1];
		sent(() -> refusedAlone[0] = thrown(() -> FinTSHelper.refresh(refusal, passport, refusal.accounts(), requested, unasked)));
		passport.jobsSent = false;
		expect("a refusal of the bank without a cancel goes on to the results as before", refusedAlone[0] + " " + unasked.restarts(), "null false");

		Map<String, Object> command = Map.of("accounts", requested);
		FinTSHelper.Callback dialogs = new FinTSHelper.Callback(Map.of());
		List<Boolean> ended = new ArrayList<>();
		List<String> startdates = new ArrayList<>();
		java.util.function.Function<FinTSHelper.Passport, FinTSHelper.Orders> open = p -> new MadeUpBank(dialogs, startdates, new ArrayList<>(), () -> {
			if (dialogs.narrowed) return;
			p.jobsSent = true;
			dialogs.callback(p, FinTSHelper.Callback.NEED_PT_DECOUPLED, "pushTAN 2.0\n\nBitte bestätigen Sie den Abruf.", 0, new StringBuffer());
			FinTSHelper.Inbox.queue.add(new java.util.HashMap<>(Map.of("type", "answer", "id", String.valueOf(dialogs.lastApproval), "skip", true)));
			// hbci4java fails on the refusal of the bank, which the user caused with the cancel.
			throw new HBCI_Exception("the approval was refused");
		});
		FinTSHelper.Passport.loaded = passportData();
		List<String> dialogLines = sent(() -> {
			try {
				ended.add(FinTSHelper.dialog("refresh", command, dialogs, open));
				ended.add(FinTSHelper.dialog("refresh", command, dialogs, open));
			} catch (IOException | RuntimeException e) {
				failures.add("a dialog after a canceled approval for older transactions failed: " + e);
			}
		});
		FinTSHelper.Passport.loaded = null;
		expect("a dialog whose approval for older transactions the user canceled and the bank refused ends, and the next one asks for 90 days",
			ended + " " + startdates + " " + dialogLines.get(dialogLines.size() - 1).startsWith("{\"type\":\"state\""), "[false, true] [" + ninety + "] true");
	}
}
