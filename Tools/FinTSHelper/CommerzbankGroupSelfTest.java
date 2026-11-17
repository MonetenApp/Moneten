import java.util.ArrayList;
import java.util.Properties;
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
			restoredLogin();
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

	static final String GIRO = "DE02120300000000202051", SAVINGS = "1234567890";

	/// A made-up bank with "Girokonto" (by its IBAN) and "Tagesgeld" (by its number), each with the balance and the
	/// transactions. Each dialog answers a job with the next answer for its account and its name, or with the last one,
	/// and "ok" for a job without answers. `dialogs` counts the dialogs, and `failing` is thrown by the dialog of that
	/// number.
	static final class Answers implements FinTSHelper.Orders {
		final Map<String, List<HBCIJobResult>> answers = new java.util.HashMap<>();
		final GVRKUms ok = answer("0020", "Auftrag ausgeführt");
		int dialogs;
		int failingDialog;
		RuntimeException failing;
		/// Runs while the bank answers the dialog of the number that it gets, as hbci4java calls the callback there.
		java.util.function.IntConsumer during = dialog -> { };

		Answers on(String account, String name, HBCIJobResult... answers) {
			this.answers.put(account + " " + name, List.of(answers));
			return this;
		}

		public Konto[] accounts() {
			Konto giro = new Konto(), savings = new Konto();
			giro.iban = GIRO;
			giro.curr = "EUR";
			savings.number = SAVINGS;
			savings.curr = "EUR";
			return new Konto[] {giro, savings};
		}

		public List<String> jobs(Konto k) {
			return List.of("SaldoReq", "KUmsAll");
		}

		public HBCIJob newJob(String name) {
			int dialog = dialogs;
			Konto[] account = new Konto[1];
			return (HBCIJob) java.lang.reflect.Proxy.newProxyInstance(CommerzbankGroupSelfTest.class.getClassLoader(), new Class<?>[] {HBCIJob.class},
				(proxy, method, args) -> {
					if (method.getName().equals("setParam") && "my".equals(args[0])) account[0] = (Konto) args[1];
					if (!method.getName().equals("getJobResult")) return null;
					String id = account[0].iban != null ? account[0].iban : account[0].number;
					List<HBCIJobResult> list = answers.get(id + " " + name);
					return list == null ? ok : list.get(Math.min(dialog, list.size() - 1));
				});
		}

		public HBCIExecStatus execute() {
			dialogs++;
			during.accept(dialogs);
			if (failing != null && dialogs == failingDialog) throw failing;
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

	/// Bank parameters that list the balance and the transactions with `needtan`.
	static Properties bpd(String balance, String transactions) {
		Properties bpd = new Properties();
		String[][] segments = {{"HKSAL", balance}, {"HKKAZ", transactions}};
		for (int i = 0; i < segments.length; i++) {
			String header = "Params_1.PinTanPar1.ParPinTan.PinTanGV" + (i == 0 ? "" : "_" + (i + 1)) + ".";
			bpd.setProperty(header + "segcode", segments[i][0]);
			bpd.setProperty(header + "needtan", segments[i][1]);
		}
		return bpd;
	}

	/// A passport of the made-up bank with the bank parameters `bpd` in addition, after the orders of a first dialog.
	static FinTSHelper.Passport passport(Properties bpd) {
		FinTSHelper.Passport passport = SelfTest.passport();
		passport.getBPD().putAll(bpd);
		passport.jobsSent = true;
		return passport;
	}

	/// What comes of a refresh of both accounts from `from` at `host`, whose bank parameters are `bpd`: the number of
	/// dialogs, the lines that the helper sent before the results, and then the result of each account that is left.
	static String again(String host, Properties bpd, String from, Answers bank) {
		return again(host, passport(bpd), from, from, bank, new FinTSHelper.Callback(Map.of()));
	}

	/// The same with the first day of each account, the passport, and the callback of the run.
	static String again(String host, FinTSHelper.Passport passport, String giroFrom, String savingsFrom, Answers bank, FinTSHelper.Callback callback) {
		FinTSHelper.Callback.server = host;
		Konto[] accounts = bank.accounts();
		List<FinTSHelper.Jobs> all = new ArrayList<>();
		all.add(FinTSHelper.queue(bank, accounts[0], GIRO, giroFrom, callback, 0));
		all.add(FinTSHelper.queue(bank, accounts[1], SAVINGS, savingsFrom, callback, 1));
		callback.fullHistory = all.stream().anyMatch(j -> j.statements() != null && j.from() == null);
		bank.execute();
		List<FinTSHelper.Jobs> after = new ArrayList<>();
		List<String> lines = SelfTest.sent(() -> after.addAll(CommerzbankGroup.again(bank, passport, accounts, all, callback)));
		StringBuilder results = new StringBuilder();
		for (FinTSHelper.Jobs jobs : after) {
			Map<String, Object> result = FinTSHelper.result(jobs.id(), jobs.from(), null, (GVRKUms) jobs.statements().getJobResult(), false);
			results.append(" ").append(jobs.id()).append("=").append(FinTSHelper.Json.write(result.get("errors")));
		}
		return bank.dialogs + " " + lines + results;
	}

	static void resend() {
		Properties free = bpd("N", "N");
		GVRKUms resend = answer("9010", RESEND), ok = answer("0020", "Auftrag ausgeführt");
		String failedGiro = "[{\"type\":\"error\",\"code\":\"9010\",\"text\":\"" + RESEND + "\"}]";
		SelfTest.expect("comdirect asks to send the transactions again, and the second answer counts",
			again(COMDIRECT, free, "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, ok)), "2 [] " + GIRO + "=[] " + SAVINGS + "=[]");
		SelfTest.expect("comdirect asks again in the second answer, and the account fails without a third request",
			again(COMDIRECT, free, "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, resend)), "2 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		SelfTest.expect("comdirect answers without asking again", again(COMDIRECT, free, "2026-10-01", new Answers()), "1 [] " + GIRO + "=[] " + SAVINGS + "=[]");
		SelfTest.expect("another bank with the same text gets no second request",
			again(MUSTERBANK, free, "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, ok)), "1 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		SelfTest.expect("Commerzbank with the same text gets no second request",
			again(COMMERZBANK, free, "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, ok)), "1 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		SelfTest.expect("transactions that need a TAN go no second time and fail with the text of the bank",
			again(COMDIRECT, bpd("N", "J"), "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, ok)), "1 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		SelfTest.expect("transactions that the parameters do not list go no second time",
			again(COMDIRECT, new Properties(), "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, ok)), "1 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		SelfTest.expect("the full history goes no second time, because the bank asks a TAN for it",
			again(COMDIRECT, free, null, new Answers().on(GIRO, "KUmsAll", resend, ok)), "1 [] " + GIRO + "=" + failedGiro + " " + SAVINGS + "=[]");
		GVRKUms warned = new GVRKUms();
		warned.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3905", RESEND, null));
		SelfTest.expect("a second answer that has the text as a warning beside a job that the bank carried out keeps its data",
			again(COMDIRECT, free, "2026-10-01", new Answers().on(GIRO, "KUmsAll", resend, warned)), "2 [] " + GIRO + "=[] " + SAVINGS + "=[]");

		// Only the job that asked goes again: the balance of the first dialog stays.
		FinTSHelper.Callback.server = COMDIRECT;
		Answers balances = new Answers().on(GIRO, "KUmsAll", resend, ok);
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
		Konto[] accounts = balances.accounts();
		FinTSHelper.Jobs first = FinTSHelper.queue(balances, accounts[0], GIRO, "2026-10-01", callback, 0);
		balances.execute();
		List<FinTSHelper.Jobs> after = new ArrayList<>();
		SelfTest.sent(() -> after.addAll(CommerzbankGroup.again(balances, passport(free), accounts, List.of(first), callback)));
		SelfTest.expect("only the job that asked goes again", (after.get(0).balance() == first.balance()) + " " + (after.get(0).statements() != first.statements()),
			"true true");

		Answers failing = new Answers().on(GIRO, "KUmsAll", resend, ok);
		failing.failingDialog = 2;
		failing.failing = new FinTSHelper.Failure(null, "9800", "Dialog abgebrochen");
		{
			FinTSHelper.Callback.server = COMDIRECT;
			FinTSHelper.Callback kept = new FinTSHelper.Callback(Map.of());
			Konto[] both = failing.accounts();
			Answers twice = new Answers().on(GIRO, "KUmsAll", resend, ok);
			twice.failingDialog = 2;
			twice.failing = failing.failing;
			List<FinTSHelper.Jobs> all = List.of(FinTSHelper.queue(twice, both[0], GIRO, "2026-10-01", kept, 0),
				FinTSHelper.queue(twice, both[1], SAVINGS, "2026-10-01", kept, 1));
			twice.execute();
			List<FinTSHelper.Jobs> left = new ArrayList<>();
			SelfTest.sent(() -> left.addAll(CommerzbankGroup.again(twice, passport(free), both, all, kept)));
			SelfTest.expect("the account that a failed second dialog did not carry keeps the jobs of the first dialog",
				left.size() + " " + (left.get(0).statements() == all.get(1).statements()), "1 true");
		}
		SelfTest.expect("a second dialog that fails fails only the account that it carried, and the other keeps its answer",
			again(COMDIRECT, free, "2026-10-01", failing),
			"2 [{\"type\":\"accountFailed\",\"code\":\"9800\",\"text\":\"Dialog abgebrochen\",\"account\":\"" + GIRO + "\"}] " + SAVINGS + "=[]");
		Answers canceled = new Answers().on(GIRO, "KUmsAll", resend, ok);
		canceled.failingDialog = 2;
		canceled.failing = new org.kapott.hbci.exceptions.AbortedException("canceled");
		SelfTest.expect("a cancel in the second dialog ends the run", SelfTest.thrown(() -> again(COMDIRECT, free, "2026-10-01", canceled)) instanceof org.kapott.hbci.exceptions.AbortedException, true);

		secondLogin(free, resend, ok);

		GVRKUms warning = new GVRKUms();
		warning.jobStatus.addRetVal(new HBCIRetVal(null, null, null, "3905", "BITTE senden  Sie die Anfrage erneut", null));
		SelfTest.expect("comdirect asks in a warning in other letters", CommerzbankGroup.resend(warning) != null, true);
		GVRKUms global = new GVRKUms();
		global.globStatus.addRetVal(new HBCIRetVal(null, null, null, "9010", RESEND, null));
		SelfTest.expect("comdirect asks in the status of the message", CommerzbankGroup.resend(global) != null, true);
		SelfTest.expect("an answer without the text", CommerzbankGroup.resend(answer("9010", "Bitte senden Sie die Anfrage nicht erneut.")), null);

		FinTSHelper.Callback.server = COMDIRECT;
		Answers bank = new Answers().on(GIRO, "KUmsAll", resend, ok);
		FinTSHelper.Callback refresh = new FinTSHelper.Callback(Map.of());
		FinTSHelper.Passport passport = SelfTest.passport();
		passport.getBPD().putAll(free);
		SelfTest.sent(() -> FinTSHelper.refresh(bank, passport, bank.accounts(), List.of(Map.of("id", GIRO, "from", "2026-10-01")), refresh));
		SelfTest.expect("a refresh of comdirect runs the second dialog", bank.dialogs, 2);
	}

	/// The second dialog logs in again, and comdirect may ask for a photoTAN for that login. The refresh asks for the full
	/// history of "Girokonto" and the transactions of "Tagesgeld" from a day, and only those of "Tagesgeld" go again.
	/// `answer` is what the user does with the TAN of that login, as the app sends it, or null for a cancel of the run.
	/// The result: the request of that TAN, whether the run ended, and then what again() sent and kept.
	static String secondLogin(Properties bpd, GVRKUms resend, GVRKUms ok, Map<String, Object> answer) {
		FinTSHelper.Passport passport = passport(bpd);
		FinTSHelper.Callback callback = new FinTSHelper.Callback(Map.of());
		List<String> asked = new ArrayList<>();
		Answers bank = new Answers().on(SAVINGS, "KUmsAll", resend, ok);
		bank.during = dialog -> {
			if (dialog != 2) return;
			java.util.HashMap<String, Object> reply = answer == null ? null : new java.util.HashMap<>(answer);
			if (reply == null) FinTSHelper.Inbox.queue.add(FinTSHelper.Inbox.CANCEL);
			else {
				reply.put("id", String.valueOf(callback.lastID + 1));
				FinTSHelper.Inbox.queue.add(reply);
			}
			RuntimeException[] thrown = new RuntimeException[1];
			asked.addAll(SelfTest.sent(() -> thrown[0] = SelfTest.thrown(() -> callback.callback(passport, FinTSHelper.Callback.NEED_PT_TAN,
				"photoTAN\n\nBitte scannen Sie die Grafik mit Ihrer photoTAN-App.", 0, new StringBuffer())) instanceof RuntimeException r ? r : null));
			if (thrown[0] != null) throw thrown[0];
		};
		String outcome;
		try {
			outcome = again(COMDIRECT, passport, null, "2026-10-01", bank, callback);
		} catch (org.kapott.hbci.exceptions.AbortedException e) {
			outcome = "ended";
		} finally {
			FinTSHelper.Inbox.queue.clear();
		}
		String request = asked.isEmpty() ? "none" : asked.get(0);
		return (request.contains("\"purpose\":\"login\"") ? "login" : "download") + " " + (request.contains("\"history\"") ? "history" : "-") + " "
			+ (callback.restarts() ? "restarts" : "-") + " " + outcome;
	}

	static void secondLogin(Properties free, GVRKUms resend, GVRKUms ok) {
		SelfTest.expect("the photoTAN of the login of the second dialog is for the login and not for older transactions",
			secondLogin(free, resend, ok, Map.of("type", "answer", "value", "1234567")), "login - - 2 [] " + GIRO + "=[] " + SAVINGS + "=[]");
		SelfTest.expect("a cancel of the photoTAN of the login of the second dialog ends the run and restarts nothing",
			secondLogin(free, resend, ok, null), "login - - ended");
		SelfTest.expect("a cancel for older transactions in the second dialog fails only the account that it carried and restarts nothing",
			secondLogin(free, resend, ok, Map.of("type", "answer", "skip", true)), "login - - 2 [{\"type\":\"accountFailed\",\"text\":\"the user canceled the challenge for older transactions\",\"account\":\"" + SAVINGS + "\"}] " + GIRO + "=[]");
	}

	/// A state of Commerzbank stores the 8 digits as the user ID and the customer ID, and the command sends the 10 digits.
	static void restoredLogin() {
		SelfTest.expect("participant number of Commerzbank replaces the stored 8 digits, and the customer ID that was the user ID follows",
			SelfTest.restoredLogin("fints.commerzbank.de/fints", "12345678", "12345678", "0012345678"), "0012345678 0012345678");
		SelfTest.expect("customer ID of its own at Commerzbank stays",
			SelfTest.restoredLogin("fints.commerzbank.de/fints", "12345678", "87654321", "0012345678"), "0012345678 87654321");
	}
}
