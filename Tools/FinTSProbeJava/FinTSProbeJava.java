// FinTSProbeJava fetches the accounts, balances, transactions, and depot holdings of one bank access
// through hbci4java and prints what arrived. It is the hbci4java counterpart of App/FinTSProbe for
// the comparison in issue #11. It only reads: it sends no payment.
//
// Build and run it with scripts/fints-probe-java.sh:
//
//   FINTS_PRODUCT_ID=<registered product ID> scripts/fints-probe-java.sh \
//     --bank-code 12345678 --url https://bank.example/fints --user <login name> [--customer <ID>]
//     [--tan-method <code>] [--days 90] [--show-values] [--verbose] [--trace-sca]
//
// --trace-sca prints the debug lines of hbci4java about TAN methods, HKTAN, and strong customer
// authentication, and the codes of the bank. Runs of six or more digits and IBANs are masked.
//
// --tan-for-orders marks balance and transactions (HKSAL, HKKAZ, HKCAZ) as "TAN required" in the
// bank parameters before the orders go out, so hbci4java adds HKTAN to them. Consorsbank marks them
// "N" in the synchronization but answers them with 9075 when they come without HKTAN. Holdings
// (HKWPD) work without HKTAN, and with it Consorsbank answers 9160.
//
// The PIN is read from the terminal without echo and is never printed. Without --show-values the
// output has no amounts, names, or full account numbers, so it can be shared. The passport file of
// hbci4java lives in a new temporary folder, is encrypted with a random passphrase, and is deleted
// at the end.

import java.io.Console;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Objects;
import java.util.Properties;
import java.util.TreeSet;
import java.util.function.Predicate;
import java.util.stream.Collectors;

import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.GV_Result.GVRSaldoReq;
import org.kapott.hbci.GV_Result.GVRWPDepotList;
import org.kapott.hbci.GV_Result.HBCIJobResult;
import org.kapott.hbci.callback.AbstractHBCICallback;
import org.kapott.hbci.manager.BankInfo;
import org.kapott.hbci.manager.HBCIHandler;
import org.kapott.hbci.manager.HBCIUtils;
import org.kapott.hbci.manager.HBCIVersion;
import org.kapott.hbci.passport.AbstractHBCIPassport;
import org.kapott.hbci.passport.HBCIPassport;
import org.kapott.hbci.status.HBCIExecStatus;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.structures.Konto;

public class FinTSProbeJava {
	static final class Options {
		String bankCode = "", url = "", user = "", customer, tanMethod;
		int days = 90;
		boolean showValues, verbose, traceSCA, tanForOrders;

		Options(String[] args) {
			for (int i = 0; i < args.length; i++) {
				String a = args[i];
				switch (a) {
					case "--bank-code" -> bankCode = value(args, ++i, a);
					case "--url" -> url = value(args, ++i, a);
					case "--user" -> user = value(args, ++i, a);
					case "--customer" -> customer = value(args, ++i, a);
					case "--tan-method" -> tanMethod = value(args, ++i, a);
					case "--days" -> days = Integer.parseInt(value(args, ++i, a));
					case "--show-values" -> showValues = true;
					case "--verbose" -> verbose = true;
					case "--trace-sca" -> traceSCA = true;
					case "--tan-for-orders" -> tanForOrders = true;
					default -> throw new IllegalArgumentException("unknown argument " + a);
				}
			}
			if (bankCode.isEmpty() || url.isEmpty() || user.isEmpty()) {
				throw new IllegalArgumentException("--bank-code, --url, and --user are required");
			}
		}

		static String value(String[] args, int i, String name) {
			if (i >= args.length) throw new IllegalArgumentException(name + " needs a value");
			return args[i];
		}
	}

	/// Answers the questions of hbci4java in the terminal. It never prints the PIN or a message
	/// segment, because a PIN/TAN message carries the PIN in its signature.
	static final class Callback extends AbstractHBCICallback {
		final Options options;
		final String pin;
		final String passphrase;
		final Console console;

		Callback(Options options, String pin, Console console) {
			this.options = options;
			this.pin = pin;
			this.console = console;
			byte[] random = new byte[32];
			new SecureRandom().nextBytes(random);
			this.passphrase = Base64.getEncoder().encodeToString(random);
		}

		static final java.util.regex.Pattern SCA_LINE = java.util.regex.Pattern.compile(
			"(?i)sca|hktan|hitan|3076|3920|3955|0030|9075|tan method|tanmethod|secmech|dialog init|template|decoupled|onestep|two-?step|process|Meldung der Bank");

		static String maskNumbers(String text) {
			return text.replaceAll("[A-Z]{2}\\d{2}[A-Z0-9]{10,30}", "IBAN…").replaceAll("\\d{6,}", "…");
		}

		@Override
		public void log(String msg, int level, Date date, StackTraceElement trace) {
			if (msg == null) return;
			boolean secret = msg.contains(pin) || msg.contains("HNSHA") || msg.contains("HNHBK") || msg.contains("HNVSD");
			if (options.traceSCA && level >= 3 && level <= 4) {
				if (!secret && SCA_LINE.matcher(msg).find()) System.out.println("[trace] " + maskNumbers(msg));
				return;
			}
			if (level > (options.verbose ? 3 : 2)) return;
			System.out.println("[" + (level <= 1 ? "error" : level == 2 ? "warning" : "info") + "] "
				+ (secret ? "(message content left out)" : msg));
		}

		@Override
		public void callback(HBCIPassport passport, int reason, String msg, int datatype, StringBuffer retData) {
			switch (reason) {
				case NEED_PASSPHRASE_LOAD, NEED_PASSPHRASE_SAVE -> set(retData, passphrase);
				case NEED_PT_PIN -> set(retData, pin);
				case NEED_BLZ -> set(retData, options.bankCode);
				case NEED_USERID -> set(retData, options.user);
				case NEED_CUSTOMERID -> set(retData, options.customer != null ? options.customer : options.user);
				case NEED_COUNTRY -> set(retData, "DE");
				case NEED_HOST -> set(retData, options.url);
				case NEED_PORT -> set(retData, "443");
				case NEED_FILTER -> set(retData, "Base64");
				case NEED_CONNECTION, CLOSE_CONNECTION -> { }
				case NEED_PT_SECMECH -> set(retData, chooseTanMethod(retData.toString()));
				case NEED_PT_TANMEDIA -> {
					String media = retData.toString();
					System.out.println("TAN media of the bank: " + (media.isEmpty() ? "-" : media.split("\\|").length));
					set(retData, media.isEmpty() ? "" : media.split("\\|")[0]);
				}
				case NEED_PT_DECOUPLED -> {
					System.out.println("Bank: " + (msg == null || msg.isBlank() ? "Confirm the request in your banking app." : msg));
					System.out.println("Waiting for the confirmation in the app …");
				}
				case NEED_PT_DECOUPLED_RETRY -> System.out.println("   still waiting (next check in " + retData + " s)");
				case NEED_PT_TAN -> {
					System.out.println("Bank: " + (msg == null ? "(no text)" : msg));
					String tan = console.readLine("TAN: ");
					if (tan == null || tan.isEmpty()) throw new IllegalStateException("no TAN entered");
					set(retData, tan);
				}
				case NEED_PT_PHOTOTAN, NEED_PT_QRTAN ->
					throw new IllegalStateException("the bank sent a photoTAN or QR code. This probe cannot show it. Use the app of the bank.");
				case HAVE_INST_MSG -> System.out.println("Bank message: " + msg);
				default -> {
					if (options.verbose) System.out.println("[info] callback " + reason + " not handled: " + msg);
				}
			}
		}

		@Override
		public void status(HBCIPassport passport, int statusTag, Object[] o) {
		}

		String chooseTanMethod(String offered) {
			System.out.println("TAN methods of the bank:");
			List<String> ids = new ArrayList<>();
			for (String token : offered.split("\\|")) {
				int colon = token.indexOf(':');
				String id = colon < 0 ? token : token.substring(0, colon);
				ids.add(id);
				System.out.println("  " + id + "  " + (colon < 0 ? "" : token.substring(colon + 1)));
			}
			if (options.tanMethod != null) return options.tanMethod;
			if (ids.size() == 1) return ids.get(0);
			String choice = console.readLine("TAN method: ");
			if (choice == null || choice.isEmpty()) throw new IllegalStateException("no TAN method chosen");
			return choice.trim();
		}

		static void set(StringBuffer buffer, String value) {
			buffer.replace(0, buffer.length(), value);
		}
	}

	/// "DE89370400440532013000" becomes "DE89…00".
	static String masked(String text) {
		if (text == null) return "-";
		if (text.length() <= 6) return "…";
		return text.substring(0, 4) + "…" + text.substring(text.length() - 2);
	}

	static String day(Date date) {
		return date == null ? "-" : new SimpleDateFormat("yyyy-MM-dd").format(date);
	}

	static boolean present(String s) {
		return s != null && !s.isBlank();
	}

	static void summarize(List<UmsLine> lines, boolean showValues) {
		java.util.function.Function<Predicate<UmsLine>, Long> count = p -> lines.stream().filter(p).count();
		List<Date> dates = lines.stream().map(l -> l.bdate).filter(Objects::nonNull).sorted().toList();
		System.out.println("    transactions: " + lines.size() + ", " + day(dates.isEmpty() ? null : dates.get(0)) + " to "
			+ day(dates.isEmpty() ? null : dates.get(dates.size() - 1)));
		System.out.println("    with name " + count.apply(l -> l.other != null && present(l.other.name))
			+ ", IBAN " + count.apply(l -> l.other != null && present(l.other.iban))
			+ ", BIC " + count.apply(l -> l.other != null && present(l.other.bic))
			+ ", purpose " + count.apply(l -> l.usage != null && l.usage.stream().anyMatch(FinTSProbeJava::present))
			+ ", value date " + count.apply(l -> l.valuta != null));
		System.out.println("    with booking text " + count.apply(l -> present(l.text))
			+ ", end-to-end ID " + count.apply(l -> present(l.endToEndId) && !"NOTPROVIDED".equals(l.endToEndId))
			+ ", mandate " + count.apply(l -> present(l.mandateId))
			+ ", creditor ID " + count.apply(l -> l.other != null && present(l.other.creditorid))
			+ ", cancellations " + count.apply(l -> l.isStorno));
		System.out.println("    currencies: " + lines.stream().map(l -> l.value == null ? null : l.value.getCurr())
			.filter(Objects::nonNull).collect(Collectors.toCollection(TreeSet::new)));
		if (!showValues) return;
		for (UmsLine l : lines.subList(0, Math.min(5, lines.size()))) {
			System.out.println("      " + day(l.bdate) + "  " + l.value + "  " + (l.other == null ? "" : l.other.name)
				+ "  " + (l.usage == null ? "" : String.join(" ", l.usage)));
		}
	}

	static final List<String> ORDER_CODES = List.of("HKSAL", "HKKAZ", "HKCAZ", "HKWPD");
	static final List<String> FORCED_CODES = List.of("HKSAL", "HKKAZ", "HKCAZ");

	/// The "needtan" flags of the PIN/TAN parameters for the orders of the probe. With `force`, sets
	/// the flags of balance and transactions to "J".
	static String needTan(HBCIPassport passport, boolean force) {
		Properties bpd = passport.getBPD();
		List<String> flags = new ArrayList<>();
		for (String key : bpd.stringPropertyNames()) {
			if (!key.contains(".ParPinTan.PinTanGV") || !key.endsWith(".segcode")) continue;
			String code = bpd.getProperty(key);
			if (!ORDER_CODES.contains(code)) continue;
			String flagKey = key.substring(0, key.length() - "segcode".length()) + "needtan";
			if (force && FORCED_CODES.contains(code)) bpd.setProperty(flagKey, "J");
			flags.add(code + "=" + bpd.getProperty(flagKey));
		}
		flags = new ArrayList<>(new TreeSet<>(flags));
		return flags.isEmpty() ? "none listed" : String.join(", ", flags);
	}

	static void printProblem(HBCIJobResult result) {
		List<String> messages = new ArrayList<>();
		for (HBCIRetVal r : result.getJobStatus().getRetVals()) messages.add(r.code + " " + r.text);
		for (HBCIRetVal r : result.getGlobStatus().getRetVals()) messages.add(r.code + " " + r.text);
		System.out.println("      bank: " + (messages.isEmpty() ? "no message" : String.join("; ", messages)));
	}

	static void run(Options options) throws Exception {
		String product = System.getenv("FINTS_PRODUCT_ID");
		if (product == null || product.isEmpty()) {
			throw new IllegalArgumentException("set FINTS_PRODUCT_ID to the product ID from the FinTS registration");
		}
		Console console = System.console();
		if (console == null) throw new IllegalStateException("run the probe in a terminal");
		char[] pinChars = console.readPassword("PIN: ");
		if (pinChars == null || pinChars.length == 0) throw new IllegalStateException("no PIN entered");
		String pin = new String(pinChars);

		Path folder = Files.createTempDirectory("moneten-fints-");
		File passportFile = folder.resolve("passport.dat").toFile();
		Properties props = new Properties();
		// Our registration. Without it hbci4java would send its own test number.
		props.setProperty("client.product.name", product);
		props.setProperty("client.product.version", "0.0.1");
		props.setProperty("client.passport.default", "PinTan");
		props.setProperty("client.passport.PinTan.init", "1");
		props.setProperty("log.loglevel.default", options.traceSCA ? "4" : options.verbose ? "3" : "2");
		HBCIUtils.init(props, new Callback(options, pin, console));

		HBCIPassport passport = null;
		HBCIHandler handle = null;
		try {
			System.out.println("1. Opening the dialog (TAN methods, synchronization, account information)");
			passport = AbstractHBCIPassport.getInstance(passportFile);
			passport.setCountry("DE");
			// hbci4java takes the host with the path, and the port on its own.
			java.net.URI uri = java.net.URI.create(options.url);
			passport.setHost(uri.getHost() + (uri.getRawPath() == null ? "" : uri.getRawPath()));
			passport.setPort(uri.getPort() > 0 ? uri.getPort() : 443);
			passport.setFilterType("Base64");
			handle = new HBCIHandler(HBCIVersion.HBCI_300.getId(), passport);
			System.out.println("   bank: " + passport.getInstName() + ", BPD " + passport.getBPDVersion() + ", UPD " + passport.getUPDVersion());

			Konto[] accounts = passport.getAccounts();
			System.out.println("2. " + (accounts == null ? 0 : accounts.length) + " accounts");
			if (accounts == null) return;
			Date from = new Date(System.currentTimeMillis() - options.days * 24L * 3600 * 1000);
			BankInfo bank = HBCIUtils.getBankInfo(options.bankCode);

			record Jobs(Konto account, HBCIJob balance, HBCIJob statements, boolean camt, HBCIJob depot) { }
			List<Jobs> all = new ArrayList<>();
			for (Konto account : accounts) {
				List<String> allowed = account.allowedGVs == null ? List.of() : new ArrayList<String>(account.allowedGVs);
				Collections.sort(allowed);
				System.out.println("  " + masked(account.iban != null ? account.iban : account.number) + "  " + account.curr
					+ "  type " + (account.acctype == null ? "-" : account.acctype) + "  orders " + allowed.size());
				System.out.println("    allowed: " + String.join(", ", allowed));
				boolean bicFromDirectory = account.bic == null && bank != null && present(bank.getBic());
				System.out.println("    IBAN " + (account.iban == null ? "missing" : "yes") + ", BIC "
					+ (account.bic != null ? "yes" : bicFromDirectory ? "missing, taken from the bank directory of hbci4java" : "missing"));
				if (bicFromDirectory) account.bic = bank.getBic();

				HBCIJob balance = null, statements = null, depot = null;
				boolean camt = allowed.contains("HKCAZ");
				if (allowed.contains("HKSAL")) {
					balance = handle.newJob("SaldoReq");
					balance.setParam("my", account);
					balance.addToQueue();
				}
				if (camt || allowed.contains("HKKAZ")) {
					statements = handle.newJob(camt ? "KUmsAllCamt" : "KUmsAll");
					statements.setParam("my", account);
					statements.setParam("startdate", from);
					statements.addToQueue();
				}
				if (allowed.contains("HKWPD")) {
					depot = handle.newJob("WPDepotList");
					depot.setParam("my", account);
					depot.addToQueue();
				}
				all.add(new Jobs(account, balance, statements, camt, depot));
			}

			System.out.println("   TAN required per bank parameters: " + needTan(passport, false));
			if (options.tanForOrders) System.out.println("   after --tan-for-orders: " + needTan(passport, true));
			System.out.println("3. Fetching balances, transactions, and holdings");
			HBCIExecStatus status = handle.execute();
			if (!status.isOK()) System.out.println("   the dialog reported problems: " + status.getErrorString());

			for (Jobs jobs : all) {
				Konto account = jobs.account();
				System.out.println("  " + masked(account.iban != null ? account.iban : account.number));
				if (jobs.balance() != null) {
					GVRSaldoReq result = (GVRSaldoReq) jobs.balance().getJobResult();
					if (result.isOK() && result.getEntries().length > 0) {
						GVRSaldoReq.Info info = result.getEntries()[0];
						System.out.println("    balance: " + (options.showValues ? info.ready.value.toString() : info.ready.value.getCurr())
							+ ", " + day(info.ready.timestamp));
					} else {
						System.out.println("    balance: not available");
						printProblem(result);
					}
				}
				if (jobs.statements() != null) {
					GVRKUms result = (GVRKUms) jobs.statements().getJobResult();
					if (result.isOK()) {
						System.out.println("    format: " + (jobs.camt() ? "CAMT" : "MT940"));
						summarize(result.getFlatData(), options.showValues);
					} else {
						System.out.println("    transactions: not available (" + (jobs.camt() ? "CAMT" : "MT940") + ")");
						printProblem(result);
					}
				}
				if (jobs.depot() != null) {
					GVRWPDepotList result = (GVRWPDepotList) jobs.depot().getJobResult();
					if (result.isOK()) {
						List<GVRWPDepotList.Entry.Gattung> positions = new ArrayList<>();
						for (GVRWPDepotList.Entry e : result.getEntries()) Collections.addAll(positions, e.getEntries());
						System.out.println("    holdings: " + positions.size() + " positions, with ISIN "
							+ positions.stream().filter(p -> present(p.isin)).count() + ", WKN "
							+ positions.stream().filter(p -> present(p.wkn)).count() + ", name "
							+ positions.stream().filter(p -> present(p.name)).count() + ", price "
							+ positions.stream().filter(p -> p.price != null).count() + ", quantity "
							+ positions.stream().filter(p -> p.saldo != null).count() + ", value "
							+ positions.stream().filter(p -> p.depotwert != null).count());
						if (options.showValues) {
							for (GVRWPDepotList.Entry.Gattung p : positions) {
								System.out.println("      " + p.isin + "  " + p.name + "  " + p.saldo + "  " + p.depotwert);
							}
						}
					} else {
						System.out.println("    holdings: not available");
						printProblem(result);
					}
				}
				if (jobs.balance() == null && jobs.statements() == null && jobs.depot() == null) {
					System.out.println("    no balance, transaction, or holdings order allowed for this account");
				}
			}
		} finally {
			if (handle != null) handle.close();
			else if (passport != null) passport.close();
			HBCIUtils.done();
			File[] files = folder.toFile().listFiles();
			if (files != null) for (File f : files) f.delete();
			folder.toFile().delete();
		}
	}

	public static void main(String[] args) {
		try {
			run(new Options(args));
		} catch (IllegalArgumentException e) {
			System.out.println("FinTSProbeJava: " + e.getMessage() + "\nSee the comment at the top of Tools/FinTSProbeJava/FinTSProbeJava.java.");
			System.exit(2);
		} catch (Exception e) {
			Throwable root = e;
			while (root.getCause() != null && root.getCause() != root) root = root.getCause();
			System.out.println("FinTSProbeJava: " + e.getMessage() + (root != e ? " (" + root.getMessage() + ")" : ""));
			System.exit(1);
		}
	}
}
