import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import org.kapott.hbci.exceptions.AbortedException;
import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV_Result.HBCIJobResult;
import org.kapott.hbci.passport.HBCIPassport;
import org.kapott.hbci.status.HBCIExecStatus;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.status.HBCIStatus;
import org.kapott.hbci.structures.Konto;

/// The rules of the dialog with Commerzbank and comdirect (issue #229). Each bank group keeps its rules in a file of its
/// own. A host is the one that hbci4java keeps, with its path, such as "fints.commerzbank.de/fints". The app decides its
/// rules by the same hosts, in Sources/Domain/Sync/CommerzbankServers.swift and Sources/FinTS/CommerzbankGroup.swift.
final class CommerzbankGroup {
	private CommerzbankGroup() {
	}

	/// The FinTS server of Commerzbank: the host "fints.commerzbank.de" or "hbci.commerzbank.de".
	static boolean commerzbank(String host) {
		String name = SavingsBanks.name(host);
		return name.equals("fints.commerzbank.de") || name.equals("hbci.commerzbank.de");
	}

	/// The FinTS server of comdirect: the host "fints.comdirect.de".
	static boolean comdirect(String host) {
		return SavingsBanks.name(host).equals("fints.comdirect.de");
	}

	/// The text with which comdirect asks to send a request again. Its return code is not known, so the text decides.
	static final String RESEND = "bitte senden sie die anfrage erneut";

	/// The answer of the bank in `result` that asks to send the request again, in an error or a warning of the job or
	/// of the message, or null.
	static HBCIRetVal resend(HBCIJobResult result) {
		if (result == null) return null;
		for (HBCIStatus status : new HBCIStatus[] {result.getJobStatus(), result.getGlobStatus()}) {
			if (status == null) continue;
			for (HBCIRetVal[] values : new HBCIRetVal[][] {status.getErrors(), status.getWarnings()}) {
				for (HBCIRetVal r : values) {
					if (r.text != null && r.text.toLowerCase(Locale.ROOT).replaceAll("\\s+", " ").contains(RESEND)) return r;
				}
			}
		}
		return null;
	}

	/// The segment of each job that a refresh sends, by which the bank parameters say whether it needs a TAN.
	static final Map<String, String> SEGMENTS = Map.of("SaldoReq", "HKSAL", "KUmsAll", "HKKAZ", "KUmsAllCamt", "HKCAZ",
		"KreditkartenUmsatz", "DKKKU", "WPDepotList", "HKWPD");

	/// Whether the job `name` needs no TAN in a dialog of its own: the PIN/TAN parameters of the bank (HIPINS) list its
	/// segment with "N", and it asks for no full history, for which a bank asks a TAN for transactions older than 90
	/// days. A job that the parameters do not list counts as one that needs a TAN.
	static boolean tanFree(Properties bpd, String name, String from) {
		String segment = SEGMENTS.get(name);
		if (segment == null || bpd == null || (from == null && !name.equals("SaldoReq") && !name.equals("WPDepotList"))) return false;
		for (String key : bpd.stringPropertyNames()) {
			if (!key.contains(".ParPinTan.PinTanGV") || !key.endsWith(".segcode") || !segment.equals(bpd.getProperty(key))) continue;
			return "N".equals(bpd.getProperty(key.substring(0, key.length() - "segcode".length()) + "needtan"));
		}
		return false;
	}

	/// The jobs of the refresh after comdirect asked to send some of them again (#229). A job whose answer asks for it
	/// and that needs no TAN (`tanFree`) goes to the bank once more in a second dialog, so the refresh asks for no second
	/// TAN for an order. The second dialog starts with a login of its own, for which comdirect may still ask for a TAN.
	/// Every other job keeps its first answer, which the result reports as it reports any answer: a job that the bank
	/// did not carry out fails its account with the text and code of the bank, and a job that it carried out with that
	/// text as a warning keeps its data. A second answer counts the same way, and no job goes a third time. When the second
	/// dialog fails, only the accounts with a job in it fail, with that error, and the other accounts keep their answers.
	/// The second dialog starts as a new one: its challenges before its orders are for the login, and none is for the
	/// full history, because no job of it asks for one. So a cancel of the challenge for older transactions cannot
	/// come from it, and if it comes anyway, it counts as a failure of the second dialog and never restarts the run. A
	/// cancel of the approval of the first dialog for older transactions that arrives only now belongs to the first
	/// dialog, which the bank answered, so the second dialog ignores it. A cancel and a change of the TAN method end or
	/// restart the run, as in the first dialog. Another bank, and a dialog in which comdirect asked nothing again, keep
	/// `all` as it is. A refresh sends no transfer, so no transfer takes this path.
	static List<FinTSHelper.Jobs> again(FinTSHelper.Orders handle, HBCIPassport passport, Konto[] accounts, List<FinTSHelper.Jobs> all,
		FinTSHelper.Callback callback) {
		if (!comdirect(FinTSHelper.Callback.server)) return all;
		Properties bpd = passport == null ? null : passport.getBPD();
		List<FinTSHelper.Jobs> result = new ArrayList<>(all);
		boolean[] sent = new boolean[all.size()];
		boolean any = false;
		for (int i = 0; i < all.size(); i++) {
			FinTSHelper.Jobs jobs = all.get(i);
			Konto k = FinTSHelper.find(accounts, jobs.id());
			if (k == null) continue;
			HBCIJob[] slots = {jobs.balance(), jobs.statements(), jobs.card(), jobs.holdings()};
			for (int slot = 0; slot < slots.length; slot++) {
				String name = name(handle, k, slot);
				if (slots[slot] == null || name == null || resend(slots[slot].getJobResult()) == null || !tanFree(bpd, name, jobs.from())) continue;
				HBCIJob job = handle.newJob(name);
				FinTSHelper.prepare(job, name, k, jobs.from());
				job.addToQueue();
				callback.jobs.put(job, i);
				slots[slot] = job;
				sent[i] = true;
				any = true;
			}
			if (sent[i]) result.set(i, new FinTSHelper.Jobs(jobs.id(), jobs.from(), jobs.currency(), slots[0], slots[1], slots[2], slots[3]));
		}
		if (!any) return all;
		FinTSHelper.diagnostic("FinTSHelper: comdirect asked to send the request again");
		if (passport instanceof FinTSHelper.Passport p) p.jobsSent = false;
		callback.fullHistory = false;
		callback.lastApproval = null;
		try {
			HBCIExecStatus status = handle.execute();
			callback.withdrawApproval();
			callback.checkSwitch();
			FinTSHelper.requireLogin(status);
		} catch (RuntimeException e) {
			for (Throwable t : FinTSHelper.causes(e)) {
				if (t instanceof FinTSHelper.SwitchMethod || t instanceof AbortedException) throw e;
			}
			callback.skipHistory = false;
			List<FinTSHelper.Jobs> answered = new ArrayList<>();
			for (int i = 0; i < all.size(); i++) {
				if (!sent[i]) {
					answered.add(all.get(i));
					continue;
				}
				Map<String, Object> failed = FinTSHelper.failure(e);
				failed.put("type", "accountFailed");
				failed.put("account", all.get(i).id());
				FinTSHelper.send(failed);
			}
			return answered;
		}
		return result;
	}

	/// The name of the job in `slot` of FinTSHelper.Jobs (the balance, the transactions, the card statement, the holdings)
	/// for the account `k`.
	static String name(FinTSHelper.Orders handle, Konto k, int slot) {
		return switch (slot) {
			case 0 -> "SaldoReq";
			case 1 -> handle.jobs(k).stream().filter(n -> n.startsWith("KUmsAll")).findFirst().orElse(null);
			case 2 -> "KreditkartenUmsatz";
			default -> "WPDepotList";
		};
	}
}
