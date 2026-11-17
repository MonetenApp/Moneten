import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV_Result.HBCIJobResult;
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

	/// The answer of the jobs of one account that asks to send them again, or null.
	static HBCIRetVal resend(FinTSHelper.Jobs jobs) {
		for (HBCIJob job : new HBCIJob[] {jobs.balance(), jobs.statements(), jobs.card(), jobs.holdings()}) {
			HBCIRetVal r = job == null ? null : resend(job.getJobResult());
			if (r != null) return r;
		}
		return null;
	}

	/// The jobs of the refresh after comdirect asked to send the requests of some accounts again. Those accounts get
	/// their jobs once more in a second dialog, and the other accounts keep their answers. An account whose second
	/// answer asks again fails with that answer, and its jobs leave the list. Another bank, and a dialog in which
	/// comdirect asked nothing again, keep `all` as it is.
	static List<FinTSHelper.Jobs> again(FinTSHelper.Orders handle, Konto[] accounts, List<FinTSHelper.Jobs> all, FinTSHelper.Callback callback) {
		if (!comdirect(FinTSHelper.Callback.server)) return all;
		List<FinTSHelper.Jobs> result = new ArrayList<>(all);
		boolean[] queued = new boolean[result.size()];
		boolean any = false;
		for (int i = 0; i < result.size(); i++) {
			FinTSHelper.Jobs jobs = result.get(i);
			Konto k = resend(jobs) == null ? null : FinTSHelper.find(accounts, jobs.id());
			if (k == null) continue;
			result.set(i, FinTSHelper.queue(handle, k, jobs.id(), jobs.from(), callback, i));
			queued[i] = true;
			any = true;
		}
		if (!any) return all;
		FinTSHelper.diagnostic("FinTSHelper: comdirect asked to send the request again");
		HBCIExecStatus status = handle.execute();
		callback.withdrawApproval();
		callback.checkSwitch();
		FinTSHelper.requireLogin(status);
		List<FinTSHelper.Jobs> answered = new ArrayList<>();
		for (int i = 0; i < result.size(); i++) {
			HBCIRetVal r = queued[i] ? resend(result.get(i)) : null;
			if (r == null) {
				answered.add(result.get(i));
				continue;
			}
			FinTSHelper.send(FinTSHelper.message("result", "account", result.get(i).id(), "errors",
				List.of(FinTSHelper.message("error", "code", r.code, "text", Out.withoutSecrets(r.text)))));
		}
		return answered;
	}
}
