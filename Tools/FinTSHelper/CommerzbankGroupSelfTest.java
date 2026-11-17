import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.HBCIJobResult;
import org.kapott.hbci.passport.storage.PassportData;
import org.kapott.hbci.status.HBCIExecStatus;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.structures.Konto;

/// The checks of the rules of Commerzbank and comdirect (issue #229), with made-up answers of the bank.
@SuppressWarnings("unchecked")
final class CommerzbankGroupSelfTest {
	static final String COMMERZBANK = "fints.commerzbank.de/fints";
	static final String COMDIRECT = "fints.comdirect.de/fints";
	static final String MUSTERBANK = "fints.musterbank.example/fints";
	static final String RESEND = "Bitte senden Sie die Anfrage erneut.";

	static void run() {
		String before = FinTSHelper.Callback.server;
		try {
			hosts();
			pendingDate();
			tanLength();
			resend();
		} finally {
			FinTSHelper.Callback.server = before;
		}
	}

	static void hosts() {
		SelfTest.expect("hosts of Commerzbank and comdirect", CommerzbankGroup.commerzbank(COMMERZBANK) + " " + CommerzbankGroup.commerzbank("HBCI.commerzbank.de:443/")
			+ " " + CommerzbankGroup.comdirect(COMDIRECT) + " " + CommerzbankGroup.comdirect("FINTS.COMDIRECT.DE./fints"), "true true true true");
		SelfTest.expect("hosts that are not of Commerzbank or comdirect", CommerzbankGroup.commerzbank(COMDIRECT) + " " + CommerzbankGroup.comdirect(COMMERZBANK) + " "
			+ CommerzbankGroup.commerzbank("fints.commerzbank.de.example.com/fints") + " " + CommerzbankGroup.commerzbank("evilfints.commerzbank.de/fints") + " "
			+ CommerzbankGroup.comdirect("hbci.comdirect.de/fints") + " " + CommerzbankGroup.commerzbank(null) + " " + CommerzbankGroup.comdirect(MUSTERBANK),
			"false false false false false false false");
	}

	/// The rows of an MT942 answer of Commerzbank with one ":61:" line, as the helper sends them.
	static List<Object> intraday(String line61) {
		GVRKUms answer = new GVRKUms();
		answer.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "0020", "Auftrag ausgeführt", null));
		answer.appendMT942Data("\r\n:20:STARTUMS\r\n:25:12030000/0000202051\r\n:28C:1/1\r\n:34F:EURD0,\r\n:13D:2611141200+0100\r\n:61:" + line61
			+ "\r\n:86:105?00LASTSCHRIFT?20SVWZ+Abschlag November?32Stadtwerke Musterstadt\r\n:90D:1EUR42,00\r\n:90C:0EUR0,\r\n-\r\n");
		Map<String, Object> result = FinTSHelper.result("DE02120300000000202051", null, null, answer, false);
		return (List<Object>) ((Map<String, Object>) result.get("transactions")).get("rows");
	}

	/// The server of Commerzbank gives a pending MT942 row the day of the request as its value date, and the day on which
	/// it expects to book the row as the entry date (MMDD) of the ":61:" line. hbci4java reads the entry date as the
	/// booking date, so the row is pending on the expected day.
	static void pendingDate() {
		FinTSHelper.Callback.server = COMMERZBANK;
		SelfTest.expect("pending MT942 row of Commerzbank on its expected day", FinTSHelper.Json.write(intraday("2611141115D42,00NTRFNONREF")),
			"[{\"type\":\"row\",\"booked\":\"2026-11-15\",\"value\":\"2026-11-14\",\"amount\":\"-42\",\"currency\":\"EUR\",\"name\":\"Stadtwerke Musterstadt\","
				+ "\"purpose\":\"Abschlag November\",\"bookingText\":\"LASTSCHRIFT\",\"pending\":true}]");
		SelfTest.expect("pending MT942 row of Commerzbank whose expected day is in the year before", ((Map<?, ?>) intraday("2601021231D10,00NTRFNONREF").get(0)).get("booked"),
			"2025-12-31");
		SelfTest.expect("pending MT942 row of Commerzbank whose expected day is in the next year", ((Map<?, ?>) intraday("2512310102C25,00NTRFNONREF").get(0)).get("booked"),
			"2026-01-02");
		SelfTest.expect("pending MT942 row of Commerzbank without an expected day", ((Map<?, ?>) intraday("261114D42,00NTRFNONREF").get(0)).get("booked"), "2026-11-14");
	}

	/// The method of a typed TAN and the length that the bank parameters announce for it.
	static String tanRequest(String method, String maxLength) {
		PassportData d = SelfTest.passportData();
		d.bpd.setProperty("Params_2.TAN2StepPar6.ParTAN2Step.TAN2StepParams4.secfunc", "900");
		d.bpd.setProperty("Params_2.TAN2StepPar6.ParTAN2Step.TAN2StepParams4.name", "photoTAN");
		d.bpd.setProperty("Params_2.TAN2StepPar6.ParTAN2Step.TAN2StepParams4.id", "photoTAN");
		if (maxLength != null) d.bpd.setProperty("Params_2.TAN2StepPar6.ParTAN2Step.TAN2StepParams4.maxlentan2step", maxLength);
		d.twostepMechs = new ArrayList<>(List.of("900"));
		d.tanMethod = method;
		FinTSHelper.Passport.loaded = d;
		FinTSHelper.Passport passport = new FinTSHelper.Passport();
		FinTSHelper.Passport.loaded = null;
		Map<String, Object> request = FinTSHelper.message("ask", "kind", "tan");
		FinTSHelper.Callback.tanMethod(passport, request);
		return FinTSHelper.Json.write(request);
	}

	static void tanLength() {
		SelfTest.expect("typed TAN with its method and the length of the bank parameters", tanRequest("900", "10"),
			"{\"type\":\"ask\",\"kind\":\"tan\",\"current\":\"900\",\"maxLength\":10}");
		SelfTest.expect("typed TAN of a method without a length", tanRequest("900", null), "{\"type\":\"ask\",\"kind\":\"tan\",\"current\":\"900\"}");
		SelfTest.expect("typed TAN of a method with a length that is no number", tanRequest("900", "zehn"), "{\"type\":\"ask\",\"kind\":\"tan\",\"current\":\"900\"}");
	}

	/// A made-up bank with the account "Girokonto" and the transactions only. Each dialog answers the transactions with
	/// the next of `answers`, and `dialogs` counts the dialogs.
	static final class Answers implements FinTSHelper.Orders {
		final List<HBCIJobResult> answers;
		int dialogs;

		Answers(HBCIJobResult... answers) {
			this.answers = List.of(answers);
		}

		public Konto[] accounts() {
			Konto giro = new Konto();
			giro.iban = "DE02120300000000202051";
			giro.curr = "EUR";
			return new Konto[] {giro};
		}

		public List<String> jobs(Konto k) {
			return List.of("KUmsAll");
		}

		public HBCIJob newJob(String name) {
			HBCIJobResult answer = answers.get(Math.min(dialogs, answers.size() - 1));
			return (HBCIJob) java.lang.reflect.Proxy.newProxyInstance(CommerzbankGroupSelfTest.class.getClassLoader(), new Class<?>[] {HBCIJob.class},
				(proxy, method, args) -> method.getName().equals("getJobResult") ? answer : null);
		}

		public HBCIExecStatus execute() {
			dialogs++;
			return new HBCIExecStatus();
		}

		public void close() {
		}
	}

	static GVRKUms answer(String code, String text) {
		GVRKUms result = new GVRKUms();
		result.jobStatus.addRetVal(new HBCIRetVal(null, null, null, code, text, null));
		return result;
	}

	/// What comes of a refresh at `host` whose dialogs answer with `answers`: the number of dialogs, whether the jobs of the
	/// account carry the last answer, and the lines that the helper sent before the results.
	static String again(String host, HBCIJobResult... answers) {
		FinTSHelper.Callback.server = host;
		Answers bank = new Answers(answers);
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
		Konto[] accounts = bank.accounts();
		List<FinTSHelper.Jobs> all = new ArrayList<>(List.of(FinTSHelper.queue(bank, accounts[0], "DE02120300000000202051", null, callback, 0)));
		bank.execute();
		List<FinTSHelper.Jobs> after = new ArrayList<>();
		List<String> lines = SelfTest.sent(() -> after.addAll(CommerzbankGroup.again(bank, accounts, all, callback)));
		String answered = after.isEmpty() ? "none" : after.get(0).statements().getJobResult() == answers[answers.length - 1] ? "last" : "first";
		return bank.dialogs + " " + answered + " " + lines;
	}

	static void resend() {
		GVRKUms resend = answer("9010", RESEND), resendAgain = answer("9010", RESEND), ok = answer("0020", "Auftrag ausgeführt");
		SelfTest.expect("comdirect asks to send the request again, and the second answer counts", again(COMDIRECT, resend, ok), "2 last []");
		SelfTest.expect("comdirect asks again in the second answer, and the account fails without a third request", again(COMDIRECT, resend, resendAgain),
			"2 none [{\"type\":\"result\",\"account\":\"DE02120300000000202051\",\"errors\":[{\"type\":\"error\",\"code\":\"9010\",\"text\":\"" + RESEND + "\"}]}]");
		SelfTest.expect("comdirect answers without asking again", again(COMDIRECT, ok), "1 last []");
		SelfTest.expect("another bank with the same text gets no second request", again(MUSTERBANK, resend, ok), "1 first []");
		SelfTest.expect("Commerzbank with the same text gets no second request", again(COMMERZBANK, resend, ok), "1 first []");
		GVRKUms warning = new GVRKUms();
		warning.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3905", "BITTE senden  Sie die Anfrage erneut", null));
		SelfTest.expect("comdirect asks in a warning in other letters", CommerzbankGroup.resend(warning) != null, true);
		GVRKUms global = new GVRKUms();
		global.globStatus.addRetVal(new HBCIRetVal(null, null, null, "9010", RESEND, null));
		SelfTest.expect("comdirect asks in the status of the message", CommerzbankGroup.resend(global) != null, true);
		SelfTest.expect("an answer without the text", CommerzbankGroup.resend(answer("9010", "Bitte senden Sie die Anfrage nicht erneut.")), null);

		FinTSHelper.Callback.server = COMDIRECT;
		Answers bank = new Answers(resend, ok);
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
		SelfTest.sent(() -> FinTSHelper.refresh(bank, SelfTest.passport(), bank.accounts(), List.of(Map.of("id", "DE02120300000000202051")), callback));
		SelfTest.expect("a refresh of comdirect runs the second dialog", bank.dialogs, 2);
	}
}
