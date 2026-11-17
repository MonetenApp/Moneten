// FinTSHelper runs hbci4java for FinTSConnector (ADR 0014). The app starts it once per command and
// talks to it with one JSON object per line. stderr carries only masked diagnostics.
//
// The app sends one command first: banks, accounts, or refresh. Then it sends only answers
// ({"type":"answer","id":1,"value":"…"}) and cancel. A closed stdin counts as cancel.
//
// The helper sends:
// - ask: a request for the user, with id and kind pin, tanMethod, tanMedium, tan, or approve. An
//   approval gets no answer. The helper sends withdraw with its id when hbci4java goes on. A pin
//   request carries the PIN rules of the bank parameters, and a tan or approve request the methods
//   that the user can change to. An answer with "method" in place of "value" to a tan or approve
//   request changes the TAN method: the helper ends the dialog and starts a new one with that method,
//   which requests a new challenge. A tan or approve request with "history" comes while the refresh asks
//   for the full history of an account. An answer with "skip" to it ends the dialog, and the helper starts a
//   new one that asks for the last 90 days of those accounts.
// - trust: the certificates of a server, leaf first, in Base64, with the host and an id. The app
//   answers "trusted" or the reason why macOS does not trust them.
// - alive, when hbci4java sends a message to the bank and when the answer arrives, so that the app
//   can tell a silent bank from a long answer in many parts.
// - progress, notice, banks, accounts, result, accountFailed, state, and failed.
// It ends with status 0 after its last message, also after failed.
//
// The passport of hbci4java stays in memory. The command brings it as the bytes of the last state,
// and the helper returns the new bytes in the state message. The state also holds the TAN medium
// that the user chose, so that the next refresh uses it while the bank offers it.

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.ObjectInputFilter;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.OptionalDataException;
import java.io.PrintStream;
import java.io.UncheckedIOException;
import java.math.BigDecimal;
import java.net.Socket;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Date;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509ExtendedTrustManager;

import org.kapott.hbci.GV.GVKreditkartenUmsatz;
import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV.HBCIJobImpl;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.GV_Result.GVRSaldoReq;
import org.kapott.hbci.GV_Result.GVRWPDepotList;
import org.kapott.hbci.GV_Result.HBCIJobResult;
import org.kapott.hbci.callback.AbstractHBCICallback;
import org.kapott.hbci.dialog.DialogContext;
import org.kapott.hbci.dialog.DialogEvent;
import org.kapott.hbci.dialog.HBCIDialogEnd;
import org.kapott.hbci.exceptions.AbortedException;
import org.kapott.hbci.exceptions.HBCI_Exception;
import org.kapott.hbci.exceptions.ProcessException;
import org.kapott.hbci.manager.BankInfo;
import org.kapott.hbci.manager.HBCIHandler;
import org.kapott.hbci.manager.HBCIUtils;
import org.kapott.hbci.manager.HBCIUtilsInternal;
import org.kapott.hbci.manager.HBCIVersion;
import org.kapott.hbci.manager.HHDVersion;
import org.kapott.hbci.manager.MatrixCode;
import org.kapott.hbci.manager.QRCode;
import org.kapott.hbci.passport.HBCIPassport;
import org.kapott.hbci.passport.AbstractPinTanPassport;
import org.kapott.hbci.passport.HBCIPassportPinTan;
import org.kapott.hbci.passport.storage.PassportData;
import org.kapott.hbci.status.HBCIDialogStatus;
import org.kapott.hbci.status.HBCIExecStatus;
import org.kapott.hbci.status.HBCIMsgStatus;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.status.HBCIStatus;
import org.kapott.hbci.structures.BigDecimalValue;
import org.kapott.hbci.structures.Konto;
import org.kapott.hbci.structures.Value;
import org.kapott.hbci.tools.StringUtil;

public class FinTSHelper {
	/// The lines to the app. The self-test reads them here in place of the pipe.
	static PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8);
	static final PrintStream err = new PrintStream(new FileOutputStream(FileDescriptor.err), true, StandardCharsets.UTF_8);

	/// A failure that the helper reports as it is: kind "network", "unsupported", or null for the bank.
	static final class Failure extends RuntimeException {
		final String kind, code;

		Failure(String kind, String code, String text) {
			super(text);
			this.kind = kind;
			this.code = code;
		}
	}

	/// The user changed the TAN method of the challenge on screen. The run ends the dialog and starts a
	/// new one with that method.
	static final class SwitchMethod extends RuntimeException {
		final String method;

		SwitchMethod(String method) {
			super("the user changed the TAN method");
			this.method = method;
		}
	}

	/// The user canceled the challenge for older transactions. The run ends the dialog and starts a new one
	/// that asks for the last 90 days in place of the full history.
	static final class SkipHistory extends RuntimeException {
		SkipHistory() {
			super("the user canceled the challenge for older transactions");
		}
	}

	/// A masked diagnostic on stderr.
	static void diagnostic(String text) {
		err.println(Out.bank(text));
	}

	/// The commands of the app and the messages of the helper: objects, arrays, strings, numbers,
	/// booleans, and null.
	static final class Json {
		final String s;
		int i;

		Json(String s) {
			this.s = s;
		}

		static Object parse(String text) {
			Json j = new Json(text);
			Object value = j.value();
			j.space();
			if (j.i != text.length()) throw new IllegalArgumentException("unexpected text after the JSON value");
			return value;
		}

		void space() {
			while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
		}

		char next() {
			space();
			if (i >= s.length()) throw new IllegalArgumentException("unexpected end of the line");
			return s.charAt(i);
		}

		void expect(char c) {
			if (next() != c) throw new IllegalArgumentException("expected " + c + " at " + i);
			i++;
		}

		Object value() {
			char c = next();
			if (c == '{') {
				i++;
				Map<String, Object> map = new LinkedHashMap<>();
				if (next() == '}') { i++; return map; }
				do {
					String key = string();
					expect(':');
					map.put(key, value());
				} while (comma());
				expect('}');
				return map;
			}
			if (c == '[') {
				i++;
				List<Object> list = new ArrayList<>();
				if (next() == ']') { i++; return list; }
				do list.add(value()); while (comma());
				expect(']');
				return list;
			}
			if (c == '"') return string();
			for (String word : new String[] {"true", "false", "null"}) {
				if (s.startsWith(word, i)) {
					i += word.length();
					return word.equals("null") ? null : Boolean.valueOf(word);
				}
			}
			int start = i;
			while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
			if (start == i) throw new IllegalArgumentException("unexpected character at " + i);
			return new BigDecimal(s.substring(start, i));
		}

		boolean comma() {
			if (next() != ',') return false;
			i++;
			return true;
		}

		String string() {
			expect('"');
			StringBuilder b = new StringBuilder();
			while (true) {
				if (i >= s.length()) throw new IllegalArgumentException("unterminated string");
				char c = s.charAt(i++);
				if (c == '"') return b.toString();
				if (c != '\\') { b.append(c); continue; }
				char e = s.charAt(i++);
				switch (e) {
					case 'n' -> b.append('\n');
					case 't' -> b.append('\t');
					case 'r' -> b.append('\r');
					case 'b' -> b.append('\b');
					case 'f' -> b.append('\f');
					case 'u' -> { b.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; }
					default -> b.append(e);
				}
			}
		}

		static String write(Object v) {
			StringBuilder b = new StringBuilder();
			write(v, b);
			return b.toString();
		}

		static void write(Object v, StringBuilder b) {
			if (v == null) b.append("null");
			else if (v instanceof Boolean || v instanceof Number) b.append(v);
			else if (v instanceof Map<?, ?> map) {
				b.append('{');
				boolean first = true;
				for (Map.Entry<?, ?> e : map.entrySet()) {
					if (e.getValue() == null) continue;
					if (!first) b.append(',');
					first = false;
					write(e.getKey().toString(), b);
					b.append(':');
					write(e.getValue(), b);
				}
				b.append('}');
			} else if (v instanceof List<?> list) {
				b.append('[');
				for (int k = 0; k < list.size(); k++) {
					if (k > 0) b.append(',');
					write(list.get(k), b);
				}
				b.append(']');
			} else {
				b.append('"');
				for (char c : v.toString().toCharArray()) {
					switch (c) {
						case '"' -> b.append("\\\"");
						case '\\' -> b.append("\\\\");
						case '\n' -> b.append("\\n");
						case '\r' -> b.append("\\r");
						case '\t' -> b.append("\\t");
						default -> {
							if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
							else b.append(c);
						}
					}
				}
				b.append('"');
			}
		}
	}

	static Map<String, Object> message(String type, Object... keysAndValues) {
		Map<String, Object> m = new LinkedHashMap<>();
		m.put("type", type);
		for (int k = 0; k < keysAndValues.length; k += 2) m.put((String) keysAndValues[k], keysAndValues[k + 1]);
		return m;
	}

	static synchronized void send(Map<String, Object> message) {
		out.println(Json.write(message));
	}

	static String string(Map<?, ?> map, String key) {
		Object v = map.get(key);
		return v == null ? null : v.toString();
	}

	/// Days are calendar days in the time zone in which hbci4java parsed them, so a booking on
	/// 9 November stays on 9 November.
	static String day(Date date) {
		return date == null ? null : new SimpleDateFormat("yyyy-MM-dd").format(date);
	}

	static Date date(String day) {
		try {
			SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd");
			format.setLenient(false);
			return day == null ? null : format.parse(day);
		} catch (ParseException e) {
			throw new IllegalArgumentException("not a day: " + day);
		}
	}

	static boolean present(String s) {
		return s != null && !s.isBlank();
	}

	static String text(String s) {
		return present(s) ? s.trim() : null;
	}

	/// The answers of the app, read on their own thread while hbci4java waits in a callback.
	static final class Inbox {
		static final Map<String, Object> CANCEL = Map.of();
		static final LinkedBlockingQueue<Map<String, Object>> queue = new LinkedBlockingQueue<>();
		static volatile boolean canceled;

		static void start(BufferedReader in) {
			Thread reader = new Thread(() -> {
				try {
					for (String line; (line = in.readLine()) != null; ) {
						Map<?, ?> m = (Map<?, ?>) Json.parse(line);
						if ("cancel".equals(m.get("type"))) break;
						@SuppressWarnings("unchecked") Map<String, Object> answer = (Map<String, Object>) m;
						queue.add(answer);
					}
				} catch (IOException | RuntimeException e) {
					diagnostic("FinTSHelper: unreadable input from the app, canceling");
				}
				canceled = true;
				queue.add(CANCEL);
			}, "inbox");
			reader.setDaemon(true);
			reader.start();
		}

		static String answer(int id) {
			while (true) {
				Map<String, Object> m;
				try {
					m = queue.take();
				} catch (InterruptedException e) {
					throw new AbortedException("interrupted");
				}
				if (m == CANCEL) {
					queue.add(CANCEL);
					throw new AbortedException("canceled");
				}
				if (!Integer.valueOf(id).toString().equals(string(m, "id"))) continue;
				if (m.get("method") != null) throw new SwitchMethod(string(m, "method"));
				if (Boolean.TRUE.equals(m.get("skip"))) throw new SkipHistory();
				return string(m, "value");
			}
		}

		/// The method that the user changed to while the dialog of the approval `id` waits, or null.
		static String switchFor(Integer id) {
			if (id == null) return null;
			for (Map<String, Object> m : queue) {
				if (m == CANCEL || !id.toString().equals(string(m, "id")) || m.get("method") == null) continue;
				queue.remove(m);
				return string(m, "method");
			}
			return null;
		}

		/// Whether the user canceled the approval `id` because it was for older transactions.
		static boolean skipped(Integer id) {
			if (id == null) return false;
			for (Map<String, Object> m : queue) {
				if (m == CANCEL || !id.toString().equals(string(m, "id")) || !Boolean.TRUE.equals(m.get("skip"))) continue;
				queue.remove(m);
				return true;
			}
			return false;
		}

		static void check() {
			if (canceled) throw new AbortedException("canceled");
		}
	}

	/// A PIN/TAN passport that hbci4java never writes to a file. It starts from the data of the last
	/// state, which hbci4java reads in its constructor, before the fields of a subclass exist.
	static final class Passport extends HBCIPassportPinTan {
		static PassportData loaded;
		/// The login name of the command, which replaces the user ID of the state, so that a login name that
		/// the app sends in another form reaches the bank: a VR-Kennung in capitals, the first 16 digits of a
		/// login name of 17 digits that an older access of a savings bank stored, or a login name without the
		/// spaces that an older access of the Deutsche Bank group stored. A customer ID that was the user ID
		/// follows it.
		static String user;

		record State(PassportData data, String tanMedium) { }

		Passport() {
			super("PinTan");
		}

		@Override
		protected void create() {
		}

		@Override
		protected void read() {
			PassportData d = loaded;
			if (d == null) return;
			setCountry(d.country);
			setBLZ(d.blz);
			setHost(d.host);
			setPort(d.port);
			// A passport that a self-test builds without a command keeps the user ID of its state.
			boolean replaced = present(user);
			setUserId(replaced ? user : d.userId);
			setSysId(d.sysId);
			setBPD(d.bpd);
			setUPD(d.upd);
			setHBCIVersion(d.hbciVersion);
			setCustomerId(replaced && sameLogin(d.customerId, d.userId, d.host) ? user : d.customerId);
			setFilterType(d.filter);
			setAllowedTwostepMechanisms(d.twostepMechs);
			setCurrentTANMethod(d.tanMethod);
		}

		/// Whether the customer ID of a state names the login of its user ID: the same text, on a server of the
		/// cooperative banks the same VR-Kennung, which FinTSServer.loginName of the app sends in capitals, or on a
		/// server of the Deutsche Bank group the same text without white space, which the app sends without spaces.
		/// A customer ID that differs in case only is one of its own, because a bank may tell them apart. A
		/// savings bank needs no rule here: the state stores the 17 digits as both IDs, which are the same text,
		/// and the customer ID follows the 16 digits of the command.
		/// Commerzbank needs none either: the state stores the 8 digits of a participant number as both IDs, and the
		/// customer ID follows the 10 digits of the command.
		static boolean sameLogin(String customerId, String userId, String host) {
			if (customerId == null || userId == null) return false;
			if (customerId.equals(userId)) return true;
			if (DeutscheBankGroup.group(host) && DeutscheBankGroup.withoutSpaces(customerId).equals(DeutscheBankGroup.withoutSpaces(userId))) return true;
			String vrk = vrKennung(customerId);
			return cooperative(host) && vrk != null && vrk.equals(vrKennung(userId));
		}

		/// A VR-Kennung, "VRK" and digits, in capitals and without spaces, or null for any other login name. It removes
		/// every Unicode white space, as Character.isWhitespace in FinTSServer.loginName of the app does.
		static String vrKennung(String name) {
			String joined = name.replaceAll("(?U)\\s", "").toUpperCase(java.util.Locale.ROOT);
			return joined.matches("VRK[0-9]+") ? joined : null;
		}

		/// The FinTS servers of Atruvia and of apoBank, by the host of the address that hbci4java keeps with its path.
		static boolean cooperative(String address) {
			if (address == null) return false;
			String host = address.trim().toLowerCase(java.util.Locale.ROOT);
			int end = host.indexOf('/');
			if (end >= 0) host = host.substring(0, end);
			return host.endsWith(".atruvia.de") || host.endsWith(".bankenit.de") || host.equals("fints.apobank.de");
		}

		/// The challenge data of the last challenge, which hbci4java removes before the callback. A
		/// flicker code without it cannot tell a manual method from data that does not read.
		String hhduc;

		@Override
		public void setPersistentData(String id, Object o) {
			if (KEY_PD_HHDUC.equals(id) && o != null) hhduc = o.toString();
			super.setPersistentData(id, o);
		}

		String takeHHDuc() {
			String taken = hhduc;
			hhduc = null;
			return taken;
		}

		/// hbci4java ended the login of the dialog and sends the orders. Every challenge from then on is for
		/// the download.
		boolean jobsSent;

		/// The dialog whose last message the bank answered, until it ends. After a change of the TAN
		/// method or a canceled challenge for older transactions hbci4java leaves it open at the bank, where a
		/// challenge may still wait.
		DialogContext open;

		/// The answer of a dialog initialization after which no order succeeds (`blocking`): the warning 3938, or the
		/// answer of the Deutsche Bank group to a replaced login. hbci4java counts a warning as a successful login and
		/// would send the orders and further dialogs, so every later message and order fails with it.
		Failure block;

		@Override
		public void onDialogEvent(DialogEvent event, DialogContext ctx) {
			// Recorded before hbci4java handles the answer, because a change of the method throws there.
			if (event == DialogEvent.MSG_SENT && present(ctx.getDialogId()) && !"0".equals(ctx.getDialogId())) open = ctx;
			if (event == DialogEvent.JOBS_CREATED) jobsSent = true;
			if (event == DialogEvent.MSG_SENT && block == null) {
				HBCIRetVal w = blocking(ctx.getMsgStatus());
				if (w != null) block = new Failure(kind(w.code, w.text), w.code, Out.withoutSecrets(w.text));
			}
			if (block != null) throw block;
			super.onDialogEvent(event, ctx);
		}

		/// Fails the setup login when a dialog of it carried the warning 3938, also when hbci4java kept the failure
		/// to itself, as it does for the request of the TAN media.
		void requireUnblocked() {
			if (block != null) throw block;
		}

		/// Ends the open dialog at the bank after a change of the TAN method or a canceled challenge for older
		/// transactions, so that its challenge does not wait there while the next dialog requests the challenge
		/// of the new method or asks for 90 days.
		void endOpenDialog() {
			DialogContext dialog = open;
			open = null;
			if (dialog == null) return;
			try {
				new HBCIDialogEnd(HBCIDialogEnd.Flag.ACCEPT_ERROR).execute(dialog);
			} catch (RuntimeException e) {
				diagnostic("FinTSHelper: ending the dialog after a change of the TAN method or a canceled challenge for older transactions failed: "
					+ e.getMessage());
			}
		}

		@Override
		public void saveChanges() {
		}

		byte[] state(String tanMedium) throws IOException {
			return serialize(data(), tanMedium);
		}

		PassportData data() {
			PassportData d = new PassportData();
			d.country = getCountry();
			d.blz = getBLZ();
			d.host = getHost();
			d.port = getPort();
			d.userId = getUserId();
			d.sysId = getSysId();
			d.bpd = getBPD();
			d.upd = getUPD();
			d.hbciVersion = getHBCIVersion();
			d.customerId = getCustomerId();
			d.filter = getFilterType();
			d.twostepMechs = new ArrayList<>(getAllowedTwostepMechanisms());
			try {
				d.tanMethod = getCurrentTANMethod(false);
			} catch (RuntimeException e) {
				diagnostic("FinTSHelper: the TAN method was not saved: " + e.getMessage());
			}
			return d;
		}

		static byte[] serialize(PassportData d, String tanMedium) throws IOException {
			ByteArrayOutputStream bytes = new ByteArrayOutputStream();
			try (ObjectOutputStream o = new ObjectOutputStream(bytes)) {
				o.writeObject(d);
				o.writeObject(tanMedium);
			}
			return bytes.toByteArray();
		}

		/// Reads a state of an earlier run. A state that does not read starts a new passport, and
		/// the bank then registers a new system ID. The limits keep a crafted state from exhausting
		/// the stack or the memory of the helper (issue #327).
		static State deserialize(byte[] bytes) {
			try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes))) {
				in.setObjectInputFilter(ObjectInputFilter.Config.createFilter(
					"org.kapott.hbci.passport.storage.PassportData;java.util.Properties;java.util.Hashtable;java.util.Map$Entry;java.util.ArrayList;java.lang.*;!*;"
					+ "maxdepth=20;maxarray=100000;maxrefs=100000"));
				PassportData data = (PassportData) in.readObject();
				String tanMedium = null;
				try {
					tanMedium = (String) in.readObject();
				} catch (EOFException | OptionalDataException e) {
					// A state of an earlier build ends after the passport.
				}
				return new State(data, tanMedium);
			} catch (IOException | ClassNotFoundException | ClassCastException e) {
				diagnostic("FinTSHelper: the saved state does not read, starting without it");
				return null;
			}
		}
	}

	/// Answers the callbacks of hbci4java through the app.
	static class Callback extends AbstractHBCICallback {
		/// One message of the bank in a log line of hbci4java. A line can hold several, so the text of each ends where
		/// the next message starts, and a rule that reads the text sees only its own message.
		static final Pattern PIN_ERROR = Pattern.compile("Meldung der Bank: (\\d{4}): (.*?)(?=[;,]?\\s*Meldung der Bank: \\d{4}:|$)", Pattern.MULTILINE);
		final Map<?, ?> command;
		String host;
		int port;
		/// The refresh asks for the full history of an account, so a challenge of the download may be for
		/// transactions older than 90 days.
		boolean fullHistory;
		/// The user canceled the challenge for older transactions. Every request after it ends the dialog.
		boolean skipHistory;
		/// The next dialog asks for the last 90 days in place of the full history.
		boolean narrowed;
		int lastID;
		/// The decoupled approval that waits for the bank, until hbci4java goes on.
		Integer approval;
		/// The last decoupled approval of the dialog, also after hbci4java went on: the user may cancel it for
		/// older transactions while the answer of the bank is on its way.
		Integer lastApproval;
		Map<String, Object> rejectedPIN;
		Map<String, Object> pinError;
		/// The messages of the bank since the start of the dialog or the last rejected PIN, the newest first. `pinError` is the one that
		/// `relevant` picks, so a later wrong PIN does not hide a block or the request of ING before it.
		final List<HBCIRetVal> pinErrors = new ArrayList<>();
		/// The PIN of this run. A new dialog after a change of the TAN method uses it again, unless the
		/// bank rejected it.
		String pin;
		/// The method that the user changed to. Every request after it ends the dialog.
		String switchTo;
		/// The last challenge of the run was an approval in the app, so a refused TAN means that the approval
		/// did not happen. One helper runs one command, so the field can be static for `failure`.
		static volatile boolean approvalAsked;
		/// The host of the bank with its path, as `connect` sets it, for the rules of a bank group in `failure`.
		static volatile String server;
		/// The TAN medium of the state, or the one the user chose in this run. hbci4java asks for it
		/// before every order that needs a TAN.
		String tanMedium;
		final Map<HBCIJob, Integer> jobs = new IdentityHashMap<>();
		int jobCount, lastProgress = -1;

		Callback(Map<?, ?> command) {
			this.command = command;
		}

		/// The FinTS address of a dialog is the one that the bank directory of hbci4java holds now, so that an
		/// update of the directory reaches every access without a new setup. hbci4java takes the host with
		/// the path and the query, and the port on its own.
		void connect() {
			String bankCode = string(command, "bankCode");
			BankInfo bank = present(bankCode) ? HBCIUtils.getBankInfo(bankCode) : null;
			if (bank == null || !present(bank.getPinTanAddress())) throw new Failure("unsupported", null, "The bank offers no FinTS address.");
			URI url = https(bank.getPinTanAddress());
			String path = url.getRawPath() == null || url.getRawPath().isEmpty() ? "/" : url.getRawPath();
			host = url.getHost() + path + (url.getRawQuery() == null ? "" : "?" + url.getRawQuery());
			port = url.getPort() > 0 ? url.getPort() : 443;
			server = host;
		}

		String ask(Map<String, Object> request) {
			int id = ++lastID;
			request.put("id", id);
			send(request);
			try {
				return Inbox.answer(id);
			} catch (SwitchMethod e) {
				switchTo = e.method;
				throw e;
			} catch (SkipHistory e) {
				skipHistory = true;
				throw e;
			}
		}

		/// Ends the dialog when the user changed the TAN method or canceled the challenge for older transactions,
		/// also when hbci4java kept the exception of the callback in a status instead of throwing it.
		void checkSwitch() {
			if (switchTo != null) throw new SwitchMethod(switchTo);
			if (skipHistory) throw new SkipHistory();
		}

		/// The dialog ends for a new one: the user changed the TAN method or canceled the challenge for older
		/// transactions.
		boolean restarts() {
			return switchTo != null || skipHistory;
		}

		/// Prepares the next dialog after a change of the TAN method or a canceled challenge for older
		/// transactions. After the cancel the next dialog asks for 90 days, and nothing of the old dialog asks the
		/// user again.
		void restart() {
			withdrawApproval();
			switchTo = null;
			if (skipHistory) narrowed = true;
			skipHistory = false;
			fullHistory = false;
			lastApproval = null;
			approvalAsked = false;
			jobs.clear();
			jobCount = 0;
			lastProgress = -1;
		}

		/// hbci4java went on after a decoupled approval, so the bank has it. A cancel of the user for older
		/// transactions that came before counts, also when the bank answered first, as when the user rejected
		/// the approval in the banking app and canceled it in Moneten before the next check.
		void withdrawApproval() {
			takeSkip();
			if (approval == null) return;
			send(message("withdraw", "id", approval));
			approval = null;
		}

		/// Takes a cancel of the user for the last approval from the inbox: the dialog then ends for a new one
		/// that asks for 90 days. A refusal of the bank without that cancel fails as before.
		void takeSkip() {
			if (Inbox.skipped(lastApproval)) skipHistory = true;
		}

		/// A challenge before hbci4java sends the orders is for the login, also the one of the dialog start
		/// in `execute`, and every later one is for the download.
		static String purpose(HBCIPassport passport) {
			return passport instanceof Passport p && p.jobsSent ? "download" : "login";
		}

		/// Whether the bank may ask for the challenge because of transactions older than 90 days.
		Boolean history(HBCIPassport passport) {
			return fullHistory && "download".equals(purpose(passport)) ? true : null;
		}

		@Override
		public void log(String msg, int level, Date date, StackTraceElement trace) {
			if (msg == null) return;
			Matcher m = PIN_ERROR.matcher(msg);
			boolean found = false;
			while (m.find()) {
				pinErrors.add(0, new HBCIRetVal(null, null, null, m.group(1), m.group(2).trim(), null));
				found = true;
			}
			if (found) {
				HBCIRetVal r = relevant(pinErrors);
				pinError = message("rejected", "kind", kind(r.code, r.text), "code", r.code, "text", Out.withoutSecrets(r.text));
			}
			if (level <= 2) diagnostic("[" + (level <= 1 ? "error" : "warning") + "] " + msg);
		}

		@Override
		public void callback(HBCIPassport passport, int reason, String msg, int datatype, StringBuffer retData) {
			if (reason != NEED_PT_DECOUPLED_RETRY) withdrawApproval();
			if (AFTER_SWITCH.contains(reason)) checkSwitch();
			switch (reason) {
				case NEED_PASSPHRASE_LOAD, NEED_PASSPHRASE_SAVE, NEED_CONNECTION, CLOSE_CONNECTION -> { }
				case NEED_COUNTRY -> set(retData, "DE");
				case NEED_BLZ -> set(retData, string(command, "bankCode"));
				case NEED_USERID -> set(retData, string(command, "user"));
				case NEED_CUSTOMERID -> set(retData, string(command, "user"));
				case NEED_HOST -> set(retData, host);
				case NEED_PORT -> set(retData, String.valueOf(port));
				case NEED_FILTER -> set(retData, "Base64");
				case WRONG_PIN -> {
					rejectedPIN = pinError != null ? pinError : message("rejected", "text", "The bank did not accept the PIN.");
					pinErrors.clear();
					pin = null;
				}
				case NEED_PT_PIN -> {
					if (pin == null || rejectedPIN != null) {
						pin = ask(message("ask", "kind", "pin", "rejected", rejectedPIN, "rules", rules(passport)));
						rejectedPIN = null;
						Out.secret(pin);
					}
					set(retData, pin);
				}
				case NEED_PT_SECMECH -> {
					List<Object> methods = new ArrayList<>();
					for (String token : retData.toString().split("\\|")) {
						int colon = token.indexOf(':');
						String id = colon < 0 ? token : token.substring(0, colon);
						methods.add(method(passport, id, colon < 0 ? token : token.substring(colon + 1)));
					}
					set(retData, ask(message("ask", "kind", "tanMethod", "purpose", purpose(passport), "methods", methods)));
				}
				case NEED_PT_TANMEDIA -> {
					List<Object> media = new ArrayList<>();
					for (String name : retData.toString().split("\\|")) if (present(name)) media.add(name);
					// A bank that lists no media, as apoBank for apoTAN, keeps the name that the user typed, also an empty one.
					if (tanMedium == null || (!media.isEmpty() && !media.contains(tanMedium))) {
						tanMedium = ask(message("ask", "kind", "tanMedium", "purpose", purpose(passport), "media", media));
					}
					set(retData, tanMedium);
				}
				case NEED_PT_TAN, NEED_PT_PHOTOTAN, NEED_PT_QRTAN -> {
					approvalAsked = false;
					String image = null, flicker = null;
					String hhduc = passport instanceof Passport p ? p.takeHHDuc() : null;
					try {
						if (reason == NEED_PT_PHOTOTAN) image = Base64.getEncoder().encodeToString(new MatrixCode(retData.toString()).getImage());
						if (reason == NEED_PT_QRTAN) image = Base64.getEncoder().encodeToString(new QRCode(retData.toString(), msg).getImage());
					} catch (Exception e) {
						throw new Failure(null, null, "The bank sent an image that Moneten cannot read.");
					}
					if (reason == NEED_PT_TAN && retData.length() > 0) flicker = retData.toString();
					// hbci4java leaves out the flicker code, or an image it could not read, when the challenge data does not read.
					if (reason == NEED_PT_TAN && flicker == null && present(hhduc)) {
						throw new Failure("invalidChallenge", null, "The bank responded with an invalid challenge.");
					}
					Map<String, Object> request = message("ask", "kind", "tan", "purpose", purpose(passport), "prompt", challenge(msg), "image", image, "flicker", flicker,
						"history", history(passport));
					tanMethod(passport, request);
					String tan = ask(choices(passport, request));
					Out.secret(tan);
					set(retData, tan);
				}
				case NEED_PT_DECOUPLED -> {
					if (passport instanceof Passport p) p.takeHHDuc();
					approvalAsked = true;
					approval = ++lastID;
					lastApproval = approval;
					send(choices(passport, message("ask", "id", approval, "kind", "approve", "purpose", purpose(passport), "prompt", challenge(msg), "method", firstLine(msg),
						"history", history(passport))));
				}
				case NEED_PT_DECOUPLED_RETRY -> {
					String method = Inbox.switchFor(approval);
					if (method != null) {
						switchTo = method;
						throw new SwitchMethod(method);
					}
					if (Inbox.skipped(approval)) {
						skipHistory = true;
						throw new SkipHistory();
					}
					Inbox.check();
				}
				case HAVE_INST_MSG -> send(message("notice", "text", Out.withoutSecrets(msg)));
				default -> diagnostic("FinTSHelper: callback " + reason + " not handled");
			}
		}

		@Override
		public void status(HBCIPassport passport, int statusTag, Object[] o) {
			if (statusTag == STATUS_MSG_SEND || statusTag == STATUS_MSG_RAW_RECV_ENCRYPTED) send(message("alive"));
			if (statusTag == STATUS_DIALOG_END_DONE && passport instanceof Passport p) p.open = null;
			// A new dialog: the messages of the dialogs before it say nothing about its PIN.
			if (statusTag == STATUS_DIALOG_INIT) {
				pinErrors.clear();
				pinError = null;
			}
			if (statusTag != STATUS_SEND_TASK || o == null || o.length == 0) return;
			Integer index = jobs.get(o[0]);
			if (index == null || index <= lastProgress) return;
			withdrawApproval();
			lastProgress = index;
			send(message("progress", "done", index, "of", jobCount));
		}

		/// The requests that end the dialog once the user changed the TAN method or canceled the challenge for
		/// older transactions, so that the old dialog asks the user nothing more. A new connection is allowed, because the end of the old dialog
		/// (`Passport.endOpenDialog`) may need one.
		static final Set<Integer> AFTER_SWITCH = Set.of(NEED_PT_PIN, NEED_PT_SECMECH, NEED_PT_TANMEDIA, NEED_PT_TAN, NEED_PT_PHOTOTAN, NEED_PT_QRTAN,
			NEED_PT_DECOUPLED, NEED_PT_DECOUPLED_RETRY);

		/// The PIN rules of the bank parameters, or null when the bank states none.
		static Map<String, Object> rules(HBCIPassport passport) {
			if (!(passport instanceof AbstractPinTanPassport p) || p.getBPD() == null) return null;
			Integer min = p.getPinLengthMin(), max = p.getPinLengthMax();
			return min == null && max == null ? null : message("rules", "minLength", min, "maxLength", max);
		}

		/// A TAN method with what the app needs for its progress text: whether it needs a TAN medium,
		/// and what the bank sends, read from the type and the names of the method.
		static Map<String, Object> method(HBCIPassport passport, String id, String name) {
			Properties info = passport instanceof AbstractPinTanPassport p && p.getTwostepMechanisms() != null ? p.getTwostepMechanisms().get(id) : null;
			if (info == null) return message("method", "id", id, "name", name);
			String names = (info.getProperty("name", "") + " " + info.getProperty("zkamethod_name", "")).toLowerCase();
			HHDVersion.Type type = HHDVersion.find(info).getType();
			String delivery = type == HHDVersion.Type.DECOUPLED || names.contains("push") ? "push"
				: type == HHDVersion.Type.QRCODE || type == HHDVersion.Type.PHOTOTAN ? "qr"
				: names.contains("sms") || names.contains("mobile") ? "sms" : null;
			return message("method", "id", id, "name", name, "medium", "2".equals(info.getProperty("needtanmedia")) ? true : null, "delivery", delivery);
		}

		/// Adds the method of a typed TAN and the longest TAN that the bank parameters announce for it (HITANS), from which
		/// the app takes the length of the TAN field of some banks (Sources/FinTS/CommerzbankGroup.swift).
		static void tanMethod(HBCIPassport passport, Map<String, Object> request) {
			if (!(passport instanceof AbstractPinTanPassport p)) return;
			String current = p.getCurrentTANMethod(false);
			if (!present(current)) return;
			request.put("current", current);
			Properties info = p.getTwostepMechanisms() == null ? null : p.getTwostepMechanisms().get(current);
			String length = info == null ? null : StringUtil.normalize(info.getProperty("maxlentan2step"));
			if (length != null && length.matches("\\d{1,3}")) request.put("maxLength", Integer.parseInt(length));
		}

		/// Adds the method of a challenge and the methods that the user can change to, when there are two or more.
		static Map<String, Object> choices(HBCIPassport passport, Map<String, Object> request) {
			if (!(passport instanceof AbstractPinTanPassport p) || p.getTwostepMechanisms() == null) return request;
			List<Object> methods = new ArrayList<>();
			for (String id : new TreeSet<>(p.getTwostepMechanisms().keySet())) {
				if (p.getAllowedTwostepMechanisms().contains(id)) methods.add(method(p, id, p.getTwostepMechanisms().get(id).getProperty("name", id)));
			}
			if (methods.size() < 2) return request;
			request.put("current", p.getCurrentTANMethod(false));
			request.put("methods", methods);
			return request;
		}

		/// hbci4java passes the name of the method, its input hint, and then the challenge of the bank.
		static String challenge(String msg) {
			if (msg == null) return "";
			int split = msg.indexOf("\n\n");
			return Out.withoutSecrets(split < 0 ? msg : msg.substring(split + 2)).trim();
		}

		static String firstLine(String msg) {
			if (msg == null) return null;
			int end = msg.indexOf('\n');
			return text(end < 0 ? msg : msg.substring(0, end));
		}

		static void set(StringBuffer buffer, String value) {
			buffer.replace(0, buffer.length(), value == null ? "" : value);
		}
	}

	/// Leaves the trust in the server of the bank to macOS (add-connection-security "Certificate
	/// validation"): the app evaluates the chain with the SSL policy for the host. The root
	/// certificates of the Java runtime play no part, and nothing turns the check off.
	static final class MacTrust extends X509ExtendedTrustManager {
		final Callback callback;

		MacTrust(Callback callback) {
			this.callback = callback;
		}

		void check(X509Certificate[] chain, String host) throws CertificateException {
			if (!present(host) || chain == null || chain.length == 0) throw new CertificateException("The server sent no certificate for a known host.");
			List<Object> certificates = new ArrayList<>();
			for (X509Certificate c : chain) certificates.add(Base64.getEncoder().encodeToString(c.getEncoded()));
			String verdict = callback.ask(message("trust", "host", host, "chain", certificates));
			if (!"trusted".equals(verdict)) throw new CertificateException(verdict);
		}

		@Override
		public void checkServerTrusted(X509Certificate[] chain, String authType, Socket socket) throws CertificateException {
			SSLSession session = socket instanceof SSLSocket s ? s.getHandshakeSession() : null;
			check(chain, session == null ? null : session.getPeerHost());
		}

		@Override
		public void checkServerTrusted(X509Certificate[] chain, String authType, SSLEngine engine) throws CertificateException {
			check(chain, engine == null ? null : engine.getPeerHost());
		}

		@Override
		public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
			check(chain, null);
		}

		@Override
		public void checkClientTrusted(X509Certificate[] chain, String authType, Socket socket) throws CertificateException {
			throw new CertificateException("The helper accepts no clients.");
		}

		@Override
		public void checkClientTrusted(X509Certificate[] chain, String authType, SSLEngine engine) throws CertificateException {
			throw new CertificateException("The helper accepts no clients.");
		}

		@Override
		public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {
			throw new CertificateException("The helper accepts no clients.");
		}

		@Override
		public X509Certificate[] getAcceptedIssuers() {
			return new X509Certificate[0];
		}
	}

	/// The FinTS address of a bank must be https with a host.
	static URI https(String url) {
		URI uri;
		try {
			uri = url == null ? null : URI.create(url);
		} catch (IllegalArgumentException e) {
			uri = null;
		}
		if (uri == null || !"https".equalsIgnoreCase(uri.getScheme()) || !present(uri.getHost())) {
			throw new Failure("unsupported", null, "The bank offers no encrypted FinTS address.");
		}
		return uri;
	}

	/// The bank directory of hbci4java with every Bankleitzahl, which the app searches by name.
	static Map<String, Object> banks() {
		Properties directory = new Properties();
		try (InputStream in = HBCIUtils.class.getClassLoader().getResourceAsStream("blz.properties")) {
			if (in == null) throw new IllegalStateException("hbci4java has no bank directory");
			directory.load(new InputStreamReader(in, StandardCharsets.UTF_8));
		} catch (IOException e) {
			throw new UncheckedIOException(e);
		}
		List<Map<String, Object>> banks = new ArrayList<>();
		for (String code : new TreeSet<>(directory.stringPropertyNames())) {
			BankInfo info = HBCIUtils.getBankInfo(code);
			if (info == null || !present(info.getName())) continue;
			Map<String, Object> bank = new LinkedHashMap<>();
			bank.put("code", code);
			bank.put("name", text(info.getName()));
			bank.put("city", text(info.getLocation()));
			bank.put("bic", text(info.getBic()));
			bank.put("url", text(info.getPinTanAddress()));
			banks.add(bank);
		}
		return message("banks", "banks", banks);
	}

	static Map<String, Object> account(Konto k) {
		String owner = String.join(" ", present(k.name) ? k.name.trim() : "", present(k.name2) ? k.name2.trim() : "").trim();
		return message("account", "number", text(k.number), "subnumber", text(k.subnumber), "iban", text(k.iban), "bic", text(k.bic),
			"product", text(k.type), "kind", text(k.acctype), "owner", text(owner), "currency", text(k.curr), "securities", securities(k) ? true : null);
	}

	static final Pattern SEPA_TAG = Pattern.compile("(EREF|KREF|MREF|CRED|DEBT|COAM|OAMT|SVWZ|ABWA|ABWE|IBAN|BIC)\\+");

	/// A purpose line of MT940 that holds only the slash tags of the original amount, the charges, and the exchange rate.
	static final Pattern SLASH_TAGS = Pattern.compile("(/(OCMT|CHGS|EXCH)/[^/]*/*)+");
	static final Pattern ORIGINAL_AMOUNT = Pattern.compile("([A-Za-z]{3})(-?[0-9]+(?:,[0-9]*)?)");

	/// The lines of a purpose: joined without a character for the tags, as every earlier version read them, so that a
	/// reference or a tag that a line end cuts reads as before and the identity of a stored transaction stays, and with the
	/// spaces of the joining rule of add-fints-banking where the purpose shows them. MT940: a line of 27 or 35 characters
	/// is full, so the bank cut the text there, also inside a word, and it joins the next line without a character. A
	/// shorter line, a full line that ends with a lowercase letter before a line that starts with an uppercase letter, and
	/// a line before one that starts with a tag join with a space. CAMT: only a line of 140 characters, the most that a line
	/// holds, joins without a character, and white space folds into one space. Lengths count code points, as
	/// TransactionFileImporter counts Unicode scalars, and it reads the lines of a file by the same rule.
	static final class Purpose {
		final String joined;
		final boolean camt;
		/// The positions in `joined` before which the purpose shows a space.
		final java.util.Set<Integer> spaces = new java.util.HashSet<>();
		/// Where each line starts in `joined`, and the end of the text last.
		final List<Integer> starts = new ArrayList<>();
		/// The lines of white space only, which count for the tags, as before, and not for the purpose.
		final java.util.Set<Integer> hidden = new java.util.HashSet<>();

		Purpose(List<String> lines, boolean camt) {
			this.camt = camt;
			StringBuilder text = new StringBuilder();
			String previous = null;
			for (String line : lines) {
				starts.add(text.length());
				text.append(line);
				if (line.codePoints().allMatch(Purpose::white)) {
					hidden.add(starts.size() - 1);
					continue;
				}
				if (previous != null) {
					boolean space;
					if (camt) {
						String shown = folded(previous);
						space = shown.codePointCount(0, shown.length()) != 140;
					} else {
						int length = previous.codePointCount(0, previous.length());
						boolean full = length == 27 || length == 35;
						int last = previous.codePointBefore(previous.length());
						int first = line.codePointAt(0);
						boolean newWord = Character.isLowerCase(last) && Character.isUpperCase(first);
						boolean tag = SEPA_TAG.matcher(line).lookingAt();
						space = (!full || newWord || tag) && !white(last) && !white(first);
					}
					if (space) spaces.add(starts.get(starts.size() - 1));
				}
				previous = line;
			}
			joined = text.toString();
			starts.add(joined.length());
		}

		/// The text from `start` to `end` with its spaces, without white space at both ends. A CAMT line also loses the white
		/// space at its own ends, and white space in it folds into one space.
		String shown(int start, int end) {
			StringBuilder text = new StringBuilder();
			for (int line = 0; line + 1 < starts.size(); line++) {
				if (hidden.contains(line)) continue;
				int from = Math.max(start, starts.get(line)), to = Math.min(end, starts.get(line + 1));
				if (from >= to) continue;
				String part = joined.substring(from, to);
				if (camt) part = folded(part);
				if (part.isEmpty()) continue;
				if (text.length() > 0 && from == starts.get(line) && spaces.contains(from)) text.append(' ');
				text.append(part);
			}
			return trimmed(text.toString());
		}

		/// White space as Unicode defines it, as Swift's `isWhitespace` reads it. `Character.isWhitespace` leaves out the
		/// space that does not break.
		static boolean white(int c) {
			return Character.isWhitespace(c) || Character.isSpaceChar(c);
		}

		/// The text without white space at both ends, as Swift trims it.
		static String trimmed(String text) {
			return UNICODE_ENDS.matcher(text).replaceAll("");
		}

		/// A CAMT line without white space at both ends, and with each run of white space inside as one space.
		static String folded(String text) {
			return trimmed(UNICODE_SPACES.matcher(text).replaceAll(" "));
		}

		static final Pattern UNICODE_SPACES = Pattern.compile("(?U)\\s+"), UNICODE_ENDS = Pattern.compile("(?U)^\\s+|\\s+$");
	}

	/// The MT940 lines of a purpose as the purpose shows them. Blank lines are left out, as `row` leaves them out.
	static String joinMt940(List<String> lines) {
		Purpose p = new Purpose(lines.stream().filter(FinTSHelper::present).toList(), false);
		return p.shown(0, p.joined.length());
	}

	/// The CAMT lines of a purpose as the purpose shows them.
	static String joinCamt(List<String> lines) {
		Purpose p = new Purpose(lines.stream().filter(FinTSHelper::present).toList(), true);
		return p.shown(0, p.joined.length());
	}

	/// The original amount of a slash tag "/OCMT/USD50,00/" as plain decimal text with every decimal place, and its currency:
	/// three letters and the amount with a decimal comma, up to the next slash or the end. Null when any of it does not read,
	/// because a wrong original amount is worse than none. `Value` of hbci4java keeps two decimals and throws on three, so the
	/// helper keeps the amount as it is.
	static String[] originalAmount(String line) {
		int tag = line.indexOf("/OCMT/");
		if (tag < 0) return null;
		int end = line.indexOf('/', tag + 6);
		Matcher m = ORIGINAL_AMOUNT.matcher(line.substring(tag + 6, end < 0 ? line.length() : end));
		if (!m.matches()) return null;
		String amount = m.group(2).replace(',', '.');
		if (amount.endsWith(".")) amount = amount.substring(0, amount.length() - 1);
		return new String[] { new BigDecimal(amount).toPlainString(), m.group(1).toUpperCase(java.util.Locale.ROOT) };
	}

	/// The keys under which `StatementJob` keeps the raw MT940 and MT942 text of its answers.
	static final String RAW_BOOKED = "moneten.booked", RAW_UNBOOKED = "moneten.notbooked";

	/// The transactions in MT940 that also keep the raw text of each answer, because hbci4java reads the original amount
	/// of `:61:` only when the line has no bank reference after "//", and then also from a token that reads only in part,
	/// such as "USD50.99". `mt940Originals` reads it from the raw text.
	static final class StatementJob extends org.kapott.hbci.GV.GVKUmsAll {
		StatementJob(HBCIHandler handle) {
			super(handle);
		}

		@Override
		protected void extractResults(HBCIMsgStatus status, String header, int index) {
			super.extractResults(status, header, index);
			keep(jobResult, RAW_BOOKED, status.getData().getProperty(header + ".booked"));
			keep(jobResult, RAW_UNBOOKED, status.getData().getProperty(header + ".notbooked"));
		}

		/// Appends one answer to the raw text of `key`, as hbci4java appends it to the statements it parses.
		static void keep(HBCIJobResult result, String key, String raw) {
			if (raw == null) return;
			String before = result.getResultData().getProperty(key, "");
			((org.kapott.hbci.GV_Result.HBCIJobResultImpl) result).storeResult(key, before + org.kapott.hbci.swift.Swift.decodeUmlauts(raw));
		}
	}

	/// A field `:61:` of raw MT940 text, up to the next field or the end of the statement.
	static final Pattern MT940_ROW = Pattern.compile("(?m)^:61:(.*?)(?=\\r?\\n(?::[0-9]{2}[A-Z]?:|-))", Pattern.DOTALL);

	/// A row of a raw statement: the original amount that it gives, or null, and what pairs it with a row of hbci4java,
	/// its booked amount with its sign, and in MT940 its value date (yyMMdd) and its entry date (MMdd) when it has one.
	record RawRow(String[] original, BigDecimal amount, String value, String entry) {
		/// Whether `l` is the row that hbci4java made from this one.
		boolean pairs(UmsLine l) {
			return amount != null && l.value != null && amount.compareTo(l.value.getBigDecimalValue()) == 0
				&& (value == null || (l.valuta != null && value.equals(new SimpleDateFormat("yyMMdd").format(l.valuta))))
				&& (entry == null || (l.bdate != null && entry.equals(new SimpleDateFormat("MMdd").format(l.bdate))));
		}
	}

	/// The first line of a field `:61:`: the value date, the entry date, the mark of a reversal and of debit or credit, the
	/// last letter of the currency, and the amount up to the code of the booking.
	static final Pattern MT940_LINE = Pattern.compile("([0-9]{6})([0-9]{4})?(R?)([CD])[A-Z]?([0-9]+(?:,[0-9]*)?)N.*");

	/// Each field `:61:` of raw MT940 text, in the order of the text, with the original amount of its supplementary details,
	/// or null for a field without one or with one that does not read in full. A reversal of a credit (RC) books a debit and
	/// a reversal of a debit (RD) a credit, as hbci4java signs them.
	static List<RawRow> mt940Originals(String raw) {
		List<RawRow> rows = new ArrayList<>();
		if (raw == null) return rows;
		Matcher m = MT940_ROW.matcher(raw);
		while (m.find()) {
			String field = m.group(1);
			int lineBreak = field.indexOf('\n');
			String[] original = lineBreak < 0 ? null : originalAmount(field.substring(lineBreak + 1));
			Matcher line = MT940_LINE.matcher((lineBreak < 0 ? field : field.substring(0, lineBreak)).strip());
			if (!line.matches()) {
				rows.add(new RawRow(original, null, null, null));
				continue;
			}
			boolean negative = line.group(3).isEmpty() ? line.group(4).equals("D") : line.group(4).equals("C");
			String amount = line.group(5).replace(',', '.');
			if (amount.endsWith(".")) amount = amount.substring(0, amount.length() - 1);
			BigDecimal value = new BigDecimal(amount);
			rows.add(new RawRow(original, negative ? value.negate() : value, line.group(1), line.group(2)));
		}
		return rows;
	}

	/// The original amount of each entry of raw CAMT documents, which hold the bytes of the answer as hbci4java keeps them,
	/// so they become bytes again in its encoding, as it parses them. In the order in which hbci4java makes its rows: an entry
	/// whose first transaction details hold no transaction makes none. hbci4java reads the instructed amount only for a
	/// return. The amount of the entry wins, or else the sum of its transactions when each has one in the same currency.
	/// Null for an entry without one or with one that does not read in full, and null for the whole list when a document
	/// does not read.
	static List<RawRow> camtOriginals(List<String> documents) {
		List<RawRow> originals = new ArrayList<>();
		try {
			javax.xml.parsers.DocumentBuilderFactory factory = javax.xml.parsers.DocumentBuilderFactory.newInstance();
			factory.setNamespaceAware(true);
			factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
			factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
			factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
			factory.setXIncludeAware(false);
			factory.setExpandEntityReferences(false);
			for (String document : documents) {
				org.w3c.dom.NodeList entries = factory.newDocumentBuilder().parse(new ByteArrayInputStream(document.getBytes(org.kapott.hbci.comm.Comm.ENCODING)))
					.getElementsByTagNameNS("*", "Ntry");
				for (int i = 0; i < entries.getLength(); i++) {
					org.w3c.dom.Element entry = (org.w3c.dom.Element) entries.item(i);
					List<org.w3c.dom.Element> details = children(entry, "NtryDtls");
					if (!details.isEmpty() && children(details.get(0), "TxDtls").isEmpty()) continue;
					originals.add(new RawRow(instructed(entry, details), bookedAmount(entry), null, null));
				}
			}
		} catch (Exception e) {
			return null;
		}
		return originals;
	}

	/// The amount of a CAMT entry with the sign of its `CdtDbtInd`, as hbci4java signs it, or null when it does not read.
	static BigDecimal bookedAmount(org.w3c.dom.Element entry) {
		org.w3c.dom.Element amount = path(entry, "Amt"), mark = path(entry, "CdtDbtInd");
		if (amount == null) return null;
		String value = amount.getTextContent().strip();
		if (!value.matches("[0-9]+(\\.[0-9]+)?")) return null;
		BigDecimal booked = new BigDecimal(value);
		return mark != null && mark.getTextContent().strip().equals("DBIT") ? booked.negate() : booked;
	}

	static String[] instructed(org.w3c.dom.Element entry, List<org.w3c.dom.Element> details) {
		org.w3c.dom.Element own = path(entry, "AmtDtls", "InstdAmt", "Amt");
		if (own != null) return instructedAmount(own);
		BigDecimal sum = BigDecimal.ZERO;
		String currency = null;
		int count = 0;
		for (org.w3c.dom.Element detail : details) {
			for (org.w3c.dom.Element transaction : children(detail, "TxDtls")) {
				String[] amount = instructedAmount(path(transaction, "AmtDtls", "InstdAmt", "Amt"));
				if (amount == null || (currency != null && !currency.equals(amount[1]))) return null;
				currency = amount[1];
				sum = sum.add(new BigDecimal(amount[0]));
				count++;
			}
		}
		return count == 0 ? null : new String[] { sum.toPlainString(), currency };
	}

	/// An instructed amount `Amt` with its attribute `Ccy`, both read in full, or null.
	static String[] instructedAmount(org.w3c.dom.Element amount) {
		if (amount == null) return null;
		String value = amount.getTextContent().strip(), currency = amount.getAttribute("Ccy").strip().toUpperCase(java.util.Locale.ROOT);
		return value.matches("[0-9]+(\\.[0-9]+)?") && currency.matches("[A-Z]{3}") ? new String[] { new BigDecimal(value).toPlainString(), currency } : null;
	}

	static List<org.w3c.dom.Element> children(org.w3c.dom.Element parent, String name) {
		List<org.w3c.dom.Element> found = new ArrayList<>();
		for (org.w3c.dom.Node n = parent.getFirstChild(); n != null; n = n.getNextSibling()) {
			if (n instanceof org.w3c.dom.Element e && name.equals(e.getLocalName())) found.add(e);
		}
		return found;
	}

	static org.w3c.dom.Element path(org.w3c.dom.Element from, String... names) {
		org.w3c.dom.Element e = from;
		for (String name : names) {
			List<org.w3c.dom.Element> next = children(e, name);
			if (next.size() != 1) return null;
			e = next.get(0);
		}
		return e;
	}

	/// MT940 statements carry the end-to-end reference, the mandate, the creditor ID, the deviating party, and the purpose
	/// as tagged text in the purpose lines, which the bank cuts every 27 characters, also inside words. `Purpose` joins them.
	/// The original amount comes from the raw statement, `mt940Originals` and `camtOriginals`, never from hbci4java.
	static Map<String, Object> row(UmsLine l, boolean pending, String[] fromStatement) {
		List<String> lines = new ArrayList<>();
		String[] original = fromStatement;
		for (String line : l.usage == null ? List.<String>of() : l.usage) {
			if (!present(line)) continue;
			// A line of slash tags holds the original amount, and the one of :61: wins over it. The line stays in the purpose,
			// as an earlier version sent it, so that the identity of a stored transaction does not change.
			if (!l.isCamt && original == null && SLASH_TAGS.matcher(line.strip()).matches()) original = originalAmount(line);
			lines.add(line);
		}
		Purpose text = new Purpose(lines, l.isCamt);
		String joined = text.joined;
		Map<String, String> tags = new LinkedHashMap<>();
		int[] svwz = null;
		Matcher m = SEPA_TAG.matcher(joined);
		int start = -1;
		String tag = null;
		while (true) {
			boolean found = m.find();
			int end = found ? m.start() : joined.length();
			if (tag != null && !tags.containsKey(tag)) {
				tags.put(tag, joined.substring(start, end).trim());
				if (tag.equals("SVWZ")) svwz = new int[] { start, end };
			}
			if (!found) break;
			tag = m.group(1);
			start = m.end();
		}
		String purpose = tags.isEmpty() ? text.shown(0, joined.length()) : svwz == null ? "" : text.shown(svwz[0], svwz[1]);
		String endToEnd = text(present(l.endToEndId) ? l.endToEndId : tags.get("EREF"));
		if ("NOTPROVIDED".equals(endToEnd)) endToEnd = null;
		if (!present(purpose) && endToEnd != null) purpose = endToEnd;
		Konto other = l.other;
		// hbci4java reads no date from a CAMT entry that has a date and time only.
		if (l.bdate == null && l.valuta == null) throw new Failure("unsupported", null, "The bank sent a transaction without a booking date, so nothing of this account was stored.");
		// The deviating party of the counterparty: hbci4java keeps the ultimate debtor of a CAMT credit or the ultimate creditor
		// of a debit as name2. In MT940 it is ABWE+ for a debit and ABWA+ for a credit.
		boolean debit = l.value.getBigDecimalValue().signum() < 0;
		String deviating = l.isCamt ? (other == null ? null : text(other.name2)) : text(tags.get(debit ? "ABWE" : "ABWA"));
		return message("row",
			"booked", day(l.bdate != null ? l.bdate : l.valuta), "value", day(l.valuta),
			"amount", l.value.getBigDecimalValue().toPlainString(), "currency", text(l.value.getCurr()),
			"name", DeutscheBankGroup.name(Callback.server, pending, other == null ? null : text(other.name), text(l.text), purpose),
			"iban", other == null ? null : text(other.iban), "bic", other == null ? null : text(other.bic),
			"purpose", purpose, "endToEnd", endToEnd, "mandate", text(present(l.mandateId) ? l.mandateId : tags.get("MREF")),
			"creditor", text(other != null && present(other.creditorid) ? other.creditorid : tags.get("CRED")),
			"bookingText", text(l.text),
			"originalAmount", original == null ? null : original[0], "originalCurrency", original == null ? null : original[1],
			"deviatingParty", deviating, "pending", pending);
	}

	/// The errors that the user must act on, in this order: a blocked access, a wrong PIN, an app that
	/// the bank does not know, no TAN method, and a TAN that the bank refused. They come first, whatever
	/// their place in the answer. HelperError in Sources/FinTS/HelperProtocol.swift names the meaning of each code.
	static final List<String> URGENT = List.of("9930", "9933", "3938", "9931", "9942", "9340", "9078", "9955", "9941", "9943", "9948", "9951");

	/// The warning that blocks the access until the PIN block is lifted, which the helper treats as an error.
	/// 3931 stays a warning, because it also names a TAN generator that needs a synchronization.
	static final Set<String> BLOCKING_WARNINGS = Set.of("3938");

	/// The codes of a TAN that the bank refused. After an approval in the app they mean that the approval
	/// did not happen.
	static final Set<String> TAN_REFUSED = Set.of("9941", "9943", "9948", "9951");

	/// The error of the bank that the app shows: an app that the user blocked at a savings bank, a login of the Deutsche
	/// Bank group that a new login replaced, the first urgent one, or else the first one.
	static HBCIRetVal relevant(List<HBCIRetVal> errors) {
		for (HBCIRetVal r : errors) if (SavingsBanks.appBlocked(Callback.server, r.text)) return r;
		for (HBCIRetVal r : errors) if (DeutscheBankGroup.loginReplaced(Callback.server, r.code, r.text)) return r;
		for (String code : URGENT) {
			// The request of ING for a login on its website comes before a wrong PIN of the same code.
			if (code.equals("9942")) for (HBCIRetVal r : errors) if (Ing.websiteLoginNeeded(Callback.server, r.code, r.text)) return r;
			for (HBCIRetVal r : errors) if (code.equals(r.code)) return r;
		}
		return errors.isEmpty() ? null : errors.get(0);
	}

	/// The errors of the statuses, and the warnings among them that block the access.
	static List<HBCIRetVal> errors(HBCIStatus... statuses) {
		List<HBCIRetVal> all = new ArrayList<>();
		for (HBCIStatus status : statuses) {
			all.addAll(List.of(status.getErrors()));
			for (HBCIRetVal w : status.getWarnings()) if (blocking(w)) all.add(w);
		}
		return all;
	}

	/// The error of a job, or of the message when the job has none.
	static Map<String, Object> problem(HBCIJobResult result) {
		HBCIRetVal r = relevant(errors(result.getJobStatus(), result.getGlobStatus()));
		if (r != null) return message("error", "kind", kind(r.code, r.text), "code", r.code, "text", Out.withoutSecrets(r.text));
		return message("error", "text", "The bank did not answer the request.");
	}

	/// The meaning of an error that only the helper knows: an app that the user blocked in the online banking of a
	/// savings bank, a login of the Deutsche Bank group that a new login replaced, a login that ING refuses until the user
	/// logged in to its website, or a refused TAN after an approval in the app, which means that the approval did not happen.
	static String kind(String code, String text) {
		if (SavingsBanks.appBlocked(Callback.server, text)) return "appBlocked";
		if (DeutscheBankGroup.loginReplaced(Callback.server, code, text)) return "loginReplaced";
		if (Ing.websiteLoginNeeded(Callback.server, code, text)) return "websiteLogin";
		return Callback.approvalAsked && TAN_REFUSED.contains(code) ? "approvalDeclined" : null;
	}

	/// hbci4java reports a failed dialog start, for example a wrong PIN, in the status of execute and
	/// runs no job. The refresh then fails as a whole.
	static void requireLogin(HBCIExecStatus status) {
		for (String customer : status.getCustomerIds()) {
			HBCIDialogStatus dialog = status.getDialogStatus(customer);
			if (dialog != null && dialog.initStatus != null && (!dialog.initStatus.isOK() || blocking(dialog.initStatus) != null)) {
				throw new ProcessException("dialog start failed", dialog.initStatus);
			}
			List<Exception> exceptions = status.getExceptions(customer);
			if (dialog == null && exceptions != null && !exceptions.isEmpty()) throw new HBCI_Exception("dialog failed", exceptions.get(0));
		}
	}

	/// The return value of an answer after which no order succeeds (`blocking(HBCIRetVal)`), or null.
	static HBCIRetVal blocking(HBCIMsgStatus status) {
		if (status == null) return null;
		for (HBCIRetVal r : errors(status.globStatus, status.segStatus)) if (blocking(r)) return r;
		return null;
	}

	/// A return value after which no order succeeds: the warning 3938 "Zugang vorläufig gesperrt", or the answer of the
	/// Deutsche Bank group that a new login replaced the login of the access, the error 9940 or the warning 3960.
	static boolean blocking(HBCIRetVal r) {
		return BLOCKING_WARNINGS.contains(r.code) || DeutscheBankGroup.loginReplaced(Callback.server, r.code, r.text);
	}

	/// The user has no TAN method for the FinTS server: the bank allowed only the one-step method 999
	/// (code 3920), which no bank accepts for a login since PSD2.
	static boolean withoutTanMethod(HBCIPassport passport) {
		if (!(passport instanceof AbstractPinTanPassport p)) return false;
		List<String> allowed = p.getAllowedTwostepMechanisms();
		return allowed != null && !allowed.isEmpty() && allowed.stream().allMatch("999"::equals);
	}

	/// Whether an order goes with HKTAN ("J") or without ("N") on the FinTS server of Consorsbank, whose bank
	/// parameters say otherwise. The server answers HKSAL and HKKAZ without HKTAN with 9075, although its
	/// parameters say that they need no TAN, and HKWPD with HKTAN with 9160 (hbci4j/hbci4java#155).
	static final Map<String, String> CONSORSBANK_TAN_RULES = Map.of("HKSAL", "J", "HKKAZ", "J", "HKCAZ", "J", "HKWPD", "N");

	/// The FinTS server of Consorsbank. DAB BNP Paribas uses it too.
	static final String CONSORSBANK_SERVER = "brokerage-hbci.consorsbank.de";

	/// The rules of the server at `host`, as hbci4java keeps it with its path, or null. Consorsbank and DAB BNP
	/// Paribas share one server, so the server decides and not the Bankleitzahl. Only that server gets the rules,
	/// so the name must match in full: another server of the same domain keeps the parameters of its bank.
	static Map<String, String> tanRules(String host) {
		if (host == null) return null;
		String name = host.trim().toLowerCase(java.util.Locale.ROOT);
		for (char end : new char[] { '/', '?', ':' }) {
			int at = name.indexOf(end);
			if (at >= 0) name = name.substring(0, at);
		}
		return name.equals(CONSORSBANK_SERVER) ? CONSORSBANK_TAN_RULES : null;
	}

	static void applyTanRules(String host, Properties bpd) {
		Map<String, String> rules = tanRules(host);
		if (rules == null) return;
		for (String key : bpd.stringPropertyNames()) {
			if (!key.contains(".ParPinTan.PinTanGV") || !key.endsWith(".segcode")) continue;
			String needtan = rules.get(bpd.getProperty(key));
			if (needtan != null) bpd.setProperty(key.substring(0, key.length() - "segcode".length()) + "needtan", needtan);
		}
	}

	/// The bank side of one dialog: the accounts of the login, the jobs that the bank allows for an account, and
	/// the run of the orders. `Bank` is hbci4java, and the self-test runs a dialog against a made-up one.
	interface Orders {
		Konto[] accounts();
		List<String> jobs(Konto k);
		HBCIJob newJob(String name);
		HBCIExecStatus execute();
		void close();
	}

	/// The orders of a dialog through hbci4java. Its handler starts the dialog with the bank.
	record Bank(HBCIHandler handle, HBCIPassport passport) implements Orders {
		Bank(HBCIPassport passport) {
			this(new HBCIHandler(HBCIVersion.HBCI_300.getId(), passport), passport);
		}

		public Konto[] accounts() {
			return passport.getAccounts() == null ? new Konto[0] : passport.getAccounts();
		}

		public List<String> jobs(Konto k) {
			return FinTSHelper.jobs(handle, k);
		}

		public HBCIJob newJob(String name) {
			// The card statement reads its rows itself (cardRows), so hbci4java must not, and the MT940 statement keeps its
			// raw text for the original amounts (mt940Originals).
			return switch (name) {
				case "KreditkartenUmsatz" -> new CardJob(handle);
				case "KUmsAll" -> new StatementJob(handle);
				default -> handle.newJob(name);
			};
		}

		public HBCIExecStatus execute() {
			return handle.execute();
		}

		public void close() {
			handle.close();
		}
	}

	static boolean allows(HBCIHandler handle, Konto k, String code, String job) {
		if (k.allowedGVs != null && !k.allowedGVs.isEmpty()) return k.allowedGVs.contains(code);
		return handle.isSupported(job);
	}

	/// The account of an ID of FinTSAccount.remoteID: the IBAN, or the number and the subnumber
	/// as "number/subnumber", or the number alone.
	static Konto find(Konto[] accounts, String id) {
		String wanted = id.replace(" ", "");
		int slash = wanted.indexOf('/');
		String number = slash < 0 ? wanted : wanted.substring(0, slash), subnumber = slash < 0 ? null : wanted.substring(slash + 1);
		for (Konto k : accounts) {
			if (wanted.equalsIgnoreCase(k.iban)) return k;
			if (number.equals(text(k.number)) && java.util.Objects.equals(subnumber, text(k.subnumber))) return k;
		}
		return null;
	}

	/// FinTS account types 30 to 39 are securities accounts and 60 to 69 funds accounts, as in
	/// FinTSAccount.kind(of:) of the app. An account without a type or with another type is a securities
	/// account too when the bank allows the holdings (HKWPD) or the turnover of the holdings (HKWDU) for
	/// it, and neither the balance nor the transactions.
	static boolean securities(Konto k) {
		if (k.acctype != null && k.acctype.trim().matches("[36][0-9]")) return true;
		List<?> allowed = k.allowedGVs == null ? List.of() : k.allowedGVs;
		return (allowed.contains("HKWPD") || allowed.contains("HKWDU"))
			&& !allowed.contains("HKSAL") && !allowed.contains("HKKAZ") && !allowed.contains("HKCAZ");
	}

	/// The jobs that a refresh sends for an account: the custody account balance of a securities account
	/// that allows it, or else the balance and the transactions, in CAMT when the account allows it. A credit
	/// card that allows no transaction list but the card statement DKKKU, which DKB and other banks offer for
	/// their cards, gets only the card statement, which brings the balance and the transactions in one answer.
	static List<String> jobs(HBCIHandler handle, Konto k) {
		if (securities(k) && allows(handle, k, "HKWPD", "WPDepotList")) return List.of("WPDepotList");
		String statements = allows(handle, k, "HKCAZ", "KUmsAllCamt") ? "KUmsAllCamt" : allows(handle, k, "HKKAZ", "KUmsAll") ? "KUmsAll" : null;
		if (statements == null && allows(handle, k, "DKKKU", "KreditkartenUmsatz")) return List.of("KreditkartenUmsatz");
		List<String> jobs = new ArrayList<>();
		if (allows(handle, k, "HKSAL", "SaldoReq")) jobs.add("SaldoReq");
		if (statements != null) jobs.add(statements);
		return jobs;
	}

	/// Sets the parameters of the job `name` for the account `k`: the account, the start day `from` of the
	/// transactions, and the card number of a card statement, which is the account number of the card.
	static void prepare(HBCIJob job, String name, Konto k, String from) {
		job.setParam("my", k);
		if (name.equals("KreditkartenUmsatz")) job.setParam("cardnumber", k.number);
		if (from != null && List.of("KUmsAll", "KUmsAllCamt", "KreditkartenUmsatz").contains(name)) job.setParam("startdate", date(from));
	}

	/// The card statement DKKKU without the rows that hbci4java reads from its answer. hbci4java 4.1.17 drops the
	/// field "finalized" of each row, and fails the whole dialog on a row that it cannot read, as on an original
	/// amount with three decimals, so `cardRows` reads the rows from the raw data of the job.
	static final class CardJob extends GVKreditkartenUmsatz {
		CardJob(HBCIHandler handle) {
			super(handle);
		}

		@Override
		protected void extractResults(HBCIMsgStatus status, String header, int index) {
		}
	}

	/// The diagnostic of an account that allows none of the jobs: its account type and the jobs that the
	/// bank allows for it, and nothing else of the account.
	static String withoutJobs(Konto k) {
		List<?> codes = k.allowedGVs == null ? List.of() : k.allowedGVs;
		String allowed = codes.isEmpty() ? "none" : String.join(",", codes.stream().map(String::valueOf).toList());
		return "FinTSHelper: account without jobs: type=" + (present(k.acctype) ? k.acctype.trim() : "none") + " allowed=" + allowed;
	}

	/// The failure of an account that allows none of the jobs.
	static Map<String, Object> nothingAllowed(String id, Konto k) {
		return message("accountFailed", "account", id, "kind", "unsupported", "text", securities(k) ? "Moneten can't read this securities account at this bank yet."
			: "The FinTS server of the bank offers neither the balance nor the transactions of this account.");
	}

	/// The jobs of one account: the balance and the transactions, the card statement, or the holdings of a
	/// securities account in the currency of the account.
	record Jobs(String id, String from, String currency, HBCIJob balance, HBCIJob statements, HBCIJob card, HBCIJob holdings) { }

	/// The first day of the transactions of an account, or null for the full history. After the user canceled the
	/// challenge for older transactions, the full history becomes the last 90 days, as a normal refresh asks.
	static String from(Map<?, ?> request, boolean narrowed, LocalDate today) {
		String from = string(request, "from");
		return from == null && narrowed ? today.minusDays(90).toString() : from;
	}

	/// Queues the jobs of the account `k` for the next dialog, as the account at `index` of the refresh.
	static Jobs queue(Orders handle, Konto k, String id, String from, Callback callback, int index) {
		HBCIJob balance = null, statements = null, card = null, holdings = null;
		for (String name : handle.jobs(k)) {
			HBCIJob job = handle.newJob(name);
			prepare(job, name, k, from);
			switch (name) {
				case "SaldoReq" -> balance = job;
				case "WPDepotList" -> holdings = job;
				case "KreditkartenUmsatz" -> card = job;
				default -> statements = job;
			}
			job.addToQueue();
			callback.jobs.put(job, index);
		}
		return new Jobs(id, from, text(k.curr), balance, statements, card, holdings);
	}

	static void refresh(Orders handle, HBCIPassport passport, Konto[] accounts, List<?> requested, Callback callback) {
		applyTanRules(passport.getHost(), passport.getBPD());
		List<Jobs> all = new ArrayList<>();
		for (Object o : requested) {
			Map<?, ?> request = (Map<?, ?>) o;
			String id = string(request, "id"), from = from(request, callback.narrowed, LocalDate.now());
			Konto k = find(accounts, id);
			if (k == null) {
				send(message("accountFailed", "account", id, "kind", "unsupported", "text", "The bank does not list this account for the login."));
				continue;
			}
			if (handle.jobs(k).isEmpty()) {
				diagnostic(withoutJobs(k));
				send(nothingAllowed(id, k));
				continue;
			}
			all.add(queue(handle, k, id, from, callback, all.size()));
		}
		callback.jobCount = all.size();
		callback.fullHistory = all.stream().anyMatch(j -> j.statements() != null && j.from() == null);
		if (all.isEmpty()) return;
		callback.lastProgress = 0;
		send(message("progress", "done", 0, "of", all.size()));
		HBCIExecStatus status = handle.execute();
		// Also takes a cancel for older transactions that crossed the answer of the bank, before any result counts.
		callback.withdrawApproval();
		callback.checkSwitch();
		requireLogin(status);
		all = CommerzbankGroup.again(handle, passport, accounts, all, callback);
		for (Jobs jobs : all) {
			HBCIJob statements = jobs.statements(), card = jobs.card(), holdings = jobs.holdings();
			if (card != null) {
				send(alone(jobs.id(), () -> card(jobs.id(), jobs.from(), card.getJobResult(), ((HBCIJobImpl) card).redo() != null, jobs.currency())));
				continue;
			}
			if (holdings != null) {
				send(alone(jobs.id(), () -> value(jobs.id(), (GVRWPDepotList) holdings.getJobResult(), ((HBCIJobImpl) holdings).redo() != null, jobs.currency())));
				continue;
			}
			send(alone(jobs.id(), () -> result(jobs.id(), jobs.from(), jobs.balance() == null ? null : (GVRSaldoReq) jobs.balance().getJobResult(),
				statements == null ? null : (GVRKUms) statements.getJobResult(), statements != null && ((HBCIJobImpl) statements).redo() != null)));
		}
	}

	/// The value of a securities account as its balance, on the day of the statement. hbci4java adds an
	/// entry for each page of the statement, and the total of a page (HOLP) is optional in MT535, so the
	/// value is the sum over the pages of their total, or else of the values of their holdings with their
	/// accrued interest. FinTS 4.1 Messages - Finanzdatenformate (20.01.2014), MT 535, page 171, defines
	/// C:19A HOLP "Gesamtwert der Depotbestände der Nachricht" as "Summe der Beträge aus B:19A: (d.h. sowohl
	/// Kurswerte als auch Stückzinsen)", and hbci4java keeps of each holding the first HOLD and ACRU, which
	/// that page puts in the currency of HOLP. A page without holdings and without a total, as of an empty
	/// account, is worth 0 in `currency`, or in euro when the bank names no currency of the account. An answer
	/// without a statement shows the note of the bank, such as 3010, which can also mean that the bank does
	/// not offer the data now, so the earlier value stays.
	/// `incomplete` says that the dialog ended before the bank sent the last part (3040) of the holdings.
	static Map<String, Object> value(String id, GVRWPDepotList list, boolean incomplete, String currency) {
		if (incomplete) throw new Failure(null, "3040", "The bank sent only part of the securities account, so nothing of this account was stored.");
		if (!list.isOK()) return message("result", "account", id, "errors", List.of(problem(list)));
		BigDecimalValue zero = new BigDecimalValue(BigDecimal.ZERO, present(currency) ? currency.trim() : "EUR");
		GVRWPDepotList.Entry[] statement = list.getEntries();
		HBCIRetVal[] notes = list.getJobStatus().getWarnings();
		if (statement.length == 0 && notes.length > 0) {
			return message("result", "account", id, "errors", List.of(message("error", "code", notes[0].code, "text", Out.withoutSecrets(notes[0].text))));
		}
		List<BigDecimalValue> pages = new ArrayList<>();
		List<Object> positions = new ArrayList<>();
		for (GVRWPDepotList.Entry page : statement) {
			for (GVRWPDepotList.Entry.Gattung g : page.getEntries()) positions.add(position(g));
			if (page.total != null) pages.add(page.total);
			else if (page.getEntries().length == 0) pages.add(zero);
			else pages.add(sum(java.util.Arrays.stream(page.getEntries())
				.flatMap(g -> g.stueckzinsbetrag == null ? java.util.stream.Stream.of(g.depotwert) : java.util.stream.Stream.of(g.depotwert, g.stueckzinsbetrag)).toList()));
		}
		BigDecimalValue total = sum(pages);
		if (total == null) throw new Failure("unsupported", null, "The bank sent no value for this securities account.");
		return message("result", "account", id, "balance", message("balance", "amount", total.getValue().toPlainString(), "currency", text(total.getCurr()),
			"date", statement.length == 0 ? null : day(statement[0].timestamp)), "errors", List.of(), "securities", true, "holdings", positions);
	}

	/// One position of a custody account balance, with the fields of MT535 that hbci4java keeps and the app
	/// shows: the security, the quantity as units or as a nominal amount (FAMT), the currency of the security
	/// (70E), the quote with its day, a currency or "%" (PRCT), the market value (HOLD), the accrued interest
	/// (ACRU), the purchase price with its currency or "%" and the purchase day (70E), and the exchange rate
	/// (92B), in which one unit of the base costs the rate in the quoted currency. hbci4java keeps the rate as a
	/// double, and `BigDecimal.valueOf` writes its shortest decimal text. Nothing of a position goes to stderr.
	static Map<String, Object> position(GVRWPDepotList.Entry.Gattung g) {
		Map<String, Object> rate = present(g.xchg_cur1) && present(g.xchg_cur2) && g.xchg_kurs > 0
			? message("rate", "base", g.xchg_cur1.trim(), "quoted", g.xchg_cur2.trim(), "rate", BigDecimal.valueOf(g.xchg_kurs).toPlainString()) : null;
		return message("holding", "name", text(g.name), "isin", text(g.isin), "wkn", text(g.wkn),
			"quantity", g.saldo == null ? null : g.saldo.getValue().toPlainString(),
			"nominal", g.saldo_type == GVRWPDepotList.Entry.SALDO_TYPE_WERT ? true : null, "currency", text(g.curr),
			"price", amount(g.price, g.timestamp_price), "value", amount(g.depotwert, null), "accrued", amount(g.stueckzinsbetrag, null),
			"purchase", amount(g.einstandspreis, g.kauf), "rate", rate);
	}

	static Map<String, Object> amount(BigDecimalValue value, Date day) {
		if (value == null || value.getValue() == null) return null;
		return message("amount", "amount", value.getValue().toPlainString(), "currency", text(value.getCurr()), "day", day(day));
	}


	/// The sum of the values, or null when there are none, or one is missing or has another currency.
	static BigDecimalValue sum(List<BigDecimalValue> values) {
		if (values.isEmpty() || values.get(0) == null) return null;
		String currency = values.get(0).getCurr();
		BigDecimal sum = BigDecimal.ZERO;
		for (BigDecimalValue v : values) {
			if (v == null || !java.util.Objects.equals(currency, v.getCurr())) return null;
			sum = sum.add(v.getValue());
		}
		return new BigDecimalValue(sum, currency);
	}

	/// The message of one account, or accountFailed when it throws, so that one account that does
	/// not read leaves the others.
	static Map<String, Object> alone(String id, java.util.function.Supplier<Map<String, Object>> message) {
		try {
			return message.get();
		} catch (RuntimeException e) {
			Map<String, Object> failed = failure(e);
			failed.put("type", "accountFailed");
			failed.put("account", id);
			return failed;
		}
	}

	/// `incomplete` says that the dialog ended before the bank sent the last part (3040) of the
	/// transactions. Such an account fails, so that no merge treats a part as the whole.
	static Map<String, Object> result(String id, String from, GVRSaldoReq balanceResult, GVRKUms statementsResult, boolean incomplete) {
		if (incomplete) throw new Failure(null, "3040", "The bank sent only part of the transactions, so nothing of this account was stored.");
		List<Object> errors = new ArrayList<>();
		Map<String, Object> balance = null, transactions = null;
		if (balanceResult != null) {
			if (balanceResult.isOK() && balanceResult.getEntries().length > 0 && balanceResult.getEntries()[0].ready != null) {
				GVRSaldoReq.Info info = balanceResult.getEntries()[0];
				Value v = info.ready.value;
				balance = message("balance", "amount", v.getBigDecimalValue().toPlainString(), "currency", text(v.getCurr()), "date", day(info.ready.timestamp));
			} else {
				errors.add(problem(balanceResult));
			}
		}
		if (statementsResult != null) {
			if (statementsResult.isOK()) {
				List<Object> rows = new ArrayList<>();
				addRows(rows, statementsResult.getFlatData(), false, originals(statementsResult, false));
				addRows(rows, statementsResult.getFlatDataUnbooked(), true, originals(statementsResult, true));
				transactions = message("transactions", "from", from, "rows", rows);
			} else {
				errors.add(problem(statementsResult));
			}
		}
		return message("result", "account", id, "balance", balance, "transactions", transactions, "errors", errors);
	}

	/// The original amounts that the raw statements give for the booked or the pending rows: from the CAMT documents of
	/// the answer, or from the MT940 text that `StatementJob` keeps.
	static List<RawRow> originals(GVRKUms result, boolean pending) {
		List<String> camt = pending ? result.camtNotBooked : result.camtBooked;
		if (!camt.isEmpty()) return camtOriginals(camt);
		return mt940Originals(result.getResultData().getProperty(pending ? RAW_UNBOOKED : RAW_BOOKED));
	}

	/// The rows of `lines`, each with its original amount. The raw statement pairs with the rows of hbci4java by their
	/// order, and each pair must agree on the booked amount and, in MT940, on the value date and the entry date. When the
	/// count differs or one pair does not agree, no row gets an original amount from the statement, because a wrong one is
	/// worse than none.
	static void addRows(List<Object> rows, List<UmsLine> lines, boolean pending, List<RawRow> originals) {
		boolean paired = originals != null && originals.size() == lines.size();
		for (int i = 0; paired && i < lines.size(); i++) paired = originals.get(i).pairs(lines.get(i));
		for (int i = 0; i < lines.size(); i++) rows.add(row(lines.get(i), pending, paired ? originals.get(i).original() : null));
	}

	/// The result of the card statement DKKKU from its answer DIKKU, which hbci4java keeps as raw data: the
	/// transactions of the card and its balance. A row that does not read fails this card and leaves the other
	/// accounts of the login.
	static Map<String, Object> card(String id, String from, HBCIJobResult statement, boolean incomplete, String currency) {
		if (incomplete) throw new Failure(null, "3040", "The bank sent only part of the transactions, so nothing of this account was stored.");
		if (!statement.isOK()) return message("result", "account", id, "errors", List.of(problem(statement)));
		Properties data = statement.getResultData();
		Map<String, Object> result = message("result", "account", id, "balance", cardBalance(data, currency),
			"transactions", message("transactions", "from", from, "rows", cardRows(data)), "errors", List.of());
		diagnostic(cardSummary(data));
		return result;
	}

	/// What the bank test of the card statement records, as counts without any data of a row: the values of
	/// "finalized", and whether the references of the rows are unique, which decides whether a reference can
	/// identify a row.
	static String cardSummary(Properties data) {
		Map<String, Integer> finalized = new java.util.TreeMap<>();
		List<String> references = new ArrayList<>();
		for (String row : cardRowKeys(data)) {
			String value = StringUtil.normalize(data.getProperty(row + ".finalized"));
			finalized.merge(value == null ? "none" : value.length() == 1 ? value.toUpperCase(java.util.Locale.ROOT) : "other", 1, Integer::sum);
			String reference = StringUtil.normalize(data.getProperty(row + ".reference"));
			if (reference != null) references.add(reference);
		}
		return "FinTSHelper: card statement finalized " + finalized + " references=" + references.size() + " distinct=" + new java.util.HashSet<>(references).size();
	}

	static final String CARD_ROW_UNREADABLE = "The bank sent a card transaction that does not read, so nothing of this card was stored.";

	/// The parts of the answer in their order. hbci4java keeps the first part as "content" and part n as "content_n".
	static List<String> cardParts(Properties data) {
		java.util.SortedSet<Integer> parts = new java.util.TreeSet<>();
		for (String key : data.stringPropertyNames()) {
			Matcher m = CARD_PART.matcher(key);
			if (m.matches()) parts.add(m.group(1) == null ? 1 : Integer.parseInt(m.group(1)));
		}
		return parts.stream().map(n -> n == 1 ? "content" : "content_" + n).toList();
	}

	static final Pattern CARD_PART = Pattern.compile("content(?:_([0-9]+))?\\..*");

	/// The rows of all parts, in the order of the answer. The merchant text of a row is also its name, because the
	/// card statement has no other field for the other party, and a pending row pairs with its booked version only
	/// by a name or an IBAN. A row that the bank marks with "finalized" N is not final,
	/// such as the reservation of a hotel, so it is pending. The original amount of a converted row keeps every decimal
	/// place, and one that does not read is left out, so it cannot fail the row.
	static List<Object> cardRows(Properties data) {
		return cardRowKeys(data).stream().map(row -> (Object) cardRow(data, row)).toList();
	}

	/// The key of each row, such as "content_2.transactions_3", in the order of the answer.
	static List<String> cardRowKeys(Properties data) {
		List<String> rows = new ArrayList<>();
		for (String part : cardParts(data)) {
			for (int i = 0; data.getProperty(HBCIUtilsInternal.withCounter(part + ".transactions", i) + ".cardnumber") != null; i++) {
				rows.add(HBCIUtilsInternal.withCounter(part + ".transactions", i));
			}
		}
		return rows;
	}

	static Map<String, Object> cardRow(Properties data, String row) {
		String booked = cardDay(data.getProperty(row + ".bookingdate")), value = cardDay(data.getProperty(row + ".valuedate"));
		BigDecimal amount = signed(data.getProperty(row + ".value"), data.getProperty(row + ".creditdebit"));
		if (amount == null || (booked == null && value == null)) throw new Failure("unsupported", null, CARD_ROW_UNREADABLE);
		// An original amount that does not read, or whose currency is no code of three letters, is left out.
		String originalCurrency = StringUtil.normalize(data.getProperty(row + ".originalcurrency"));
		if (originalCurrency != null) originalCurrency = originalCurrency.toUpperCase(java.util.Locale.ROOT);
		BigDecimal original = originalCurrency == null || !originalCurrency.matches("[A-Z]{3}") ? null
			: signed(data.getProperty(row + ".originalvalue"), data.getProperty(row + ".originalcreditdebit"));
		return message("row", "booked", booked != null ? booked : value, "value", value, "amount", amount.toPlainString(),
			"currency", StringUtil.normalize(data.getProperty(row + ".currency")), "name", StringUtil.normalize(data.getProperty(row + ".purpose")),
			"purpose", StringUtil.joinDescription(data.getProperty(row + ".purpose"), data.getProperty(row + ".location")),
			"bookingText", "Kreditkartenzahlung",
			"originalAmount", original == null ? null : original.toPlainString(), "originalCurrency", original == null ? null : originalCurrency,
			"pending", "N".equalsIgnoreCase(StringUtil.normalize(data.getProperty(row + ".finalized"))));
	}

	/// A day of a row, null when the bank sent none. A day that does not read fails the row.
	static String cardDay(String text) {
		String day = day(text);
		if (day == null && StringUtil.normalize(text) != null) throw new Failure("unsupported", null, CARD_ROW_UNREADABLE);
		return day;
	}

	/// A day of the raw data of hbci4java, which keeps dates as yyyy-mm-dd, or as the bank sent it, yyyymmdd. Null
	/// when it does not read.
	static String day(String text) {
		String day = StringUtil.normalize(text);
		if (day == null) return null;
		if (day.matches("[0-9]{8}")) day = day.substring(0, 4) + "-" + day.substring(4, 6) + "-" + day.substring(6);
		try {
			return java.time.LocalDate.parse(day).toString();
		} catch (java.time.format.DateTimeParseException e) {
			return null;
		}
	}

	/// An amount of the card statement, which may come with a sign and with a decimal comma, with the sign of its
	/// mark C or D. Null when it is missing or does not read. It keeps every decimal place.
	static BigDecimal signed(String value, String creditDebit) {
		String text = StringUtil.normalize(value);
		if (text == null) return null;
		BigDecimal amount;
		try {
			amount = new BigDecimal(StringUtil.normalizeDecimal(text));
		} catch (NumberFormatException e) {
			return null;
		}
		String mark = StringUtil.normalize(creditDebit);
		if ("D".equalsIgnoreCase(mark)) return amount.abs().negate();
		if ("C".equalsIgnoreCase(mark)) return amount.abs();
		return amount;
	}

	/// The balance of the first part of the answer that has one, which is the amount that the user owes on the card
	/// when it is negative.
	static Map<String, Object> cardBalance(Properties data, String currency) {
		for (String part : cardParts(data)) {
			String prefix = part + ".balance.";
			if (data.getProperty(prefix + "value") == null) continue;
			BigDecimal amount = signed(data.getProperty(prefix + "value"), data.getProperty(prefix + "CreditDebit"));
			if (amount == null) {
				diagnostic("FinTSHelper: the balance of a card statement does not read, keeping its transactions");
				return null;
			}
			String curr = text(data.getProperty(prefix + "curr"));
			return message("balance", "amount", amount.toPlainString(), "currency", curr != null ? curr : present(currency) ? currency.trim() : "EUR",
				"date", day(data.getProperty(prefix + "date")));
		}
		return null;
	}

	static void run(Map<?, ?> command) throws IOException {
		String type = string(command, "type");
		Properties props = new Properties();
		props.setProperty("log.loglevel.default", "3");
		if ("banks".equals(type)) {
			HBCIUtils.init(props, new Callback(command));
			try {
				send(banks());
			} finally {
				HBCIUtils.done();
			}
			return;
		}
		if (!"accounts".equals(type) && !"refresh".equals(type)) throw new IllegalArgumentException("unknown command " + type);
		props.setProperty("client.product.name", string(command, "product"));
		props.setProperty("client.product.version", string(command, "version"));
		props.setProperty("client.passport.PinTan.init", "1");
		props.setProperty("client.passport.PinTan.checkcert", "1");
		Callback callback = new Callback(command);
		try {
			SSLContext tls = SSLContext.getInstance("TLS");
			tls.init(null, new TrustManager[] {new MacTrust(callback)}, null);
			HttpsURLConnection.setDefaultSSLSocketFactory(tls.getSocketFactory());
		} catch (GeneralSecurityException e) {
			throw new IllegalStateException(e);
		}
		HBCIUtils.init(props, callback);
		try {
			callback.connect();
			String state = string(command, "state");
			Passport.State loaded = state == null ? null : Passport.deserialize(Base64.getDecoder().decode(state));
			Passport.loaded = loaded == null ? null : loaded.data();
			Passport.user = string(command, "user");
			callback.tanMedium = loaded == null ? null : loaded.tanMedium();
			while (!dialog(type, command, callback, Bank::new)) {
				diagnostic("FinTSHelper: starting a new dialog after a change of the TAN method or a canceled challenge for older transactions");
			}
		} finally {
			HBCIUtils.done();
		}
	}

	/// One dialog with the bank. It returns false when the user changed the TAN method during it, or canceled
	/// the challenge for older transactions, also when the bank answered the approval before the cancel came.
	/// The passport then keeps its data, with the new method, for the next dialog, which requests a new
	/// challenge, or asks for the last 90 days in place of the full history. `open` starts the dialog.
	static boolean dialog(String type, Map<?, ?> command, Callback callback, java.util.function.Function<Passport, Orders> open) throws IOException {
		Orders handle = null;
		Passport passport = new Passport();
		try {
			passport.setHost(callback.host);
			passport.setPort(callback.port);
			handle = open.apply(passport);
			loggedIn(type, command, callback, handle, passport);
			return true;
		} catch (RuntimeException e) {
			// A cancel for older transactions that crossed a refusal of the bank ends the dialog for one of 90 days.
			callback.takeSkip();
			if (!callback.restarts()) {
				HBCIRetVal refusal = oneStepRefusal(passport, e);
				throw refusal != null ? noTanMethod(refusal, e) : e;
			}
			passport.endOpenDialog();
			Passport.loaded = passport.data();
			if (callback.switchTo != null) Passport.loaded.tanMethod = callback.switchTo;
			callback.restart();
			return false;
		} finally {
			try {
				if (handle != null) handle.close();
			} catch (RuntimeException e) {
				diagnostic("FinTSHelper: closing the dialog failed: " + e.getMessage());
			}
		}
	}

	/// The rest of a dialog after `HBCIHandler` logged in: the accounts of the setup, or the refresh, and then
	/// the state. It fails at once when a dialog of the login carried the warning 3938, which hbci4java keeps to
	/// itself for the request of the TAN media, so that the setup lists no accounts of a blocked access.
	static void loggedIn(String type, Map<?, ?> command, Callback callback, Orders handle, Passport passport) throws IOException {
		passport.requireUnblocked();
		callback.withdrawApproval();
		callback.checkSwitch();
		Konto[] accounts = handle.accounts();
		BankInfo bank = HBCIUtils.getBankInfo(passport.getBLZ());
		for (Konto k : accounts) {
			if (!present(k.bic) && bank != null && present(bank.getBic())) k.bic = bank.getBic();
		}
		if ("accounts".equals(type)) {
			List<Object> list = new ArrayList<>();
			for (Konto k : accounts) list.add(account(k));
			send(message("accounts", "accounts", list));
		} else {
			refresh(handle, passport, accounts, (List<?>) command.get("accounts"), callback);
		}
		send(message("state", "data", Base64.getEncoder().encodeToString(passport.state(callback.tanMedium))));
	}

	/// The codes with which a bank refuses the one-step method 999 for a login: 9075 "Starke Kundenauthentifizierung
	/// notwendig" and 9955 "Ein-Schritt-TAN-Verfahren nicht zugelassen".
	static final Set<String> ONE_STEP_REFUSED = Set.of("9075", "9955");

	/// The answer with which the bank refused the one-step method for the login of a user whom it allows no other
	/// method, or null. Only such an answer means a missing TAN method: an error of another cause, such as a wrong
	/// PIN, a block, or a server that is not available, keeps its own code and text.
	static HBCIRetVal oneStepRefusal(HBCIPassport passport, Throwable e) {
		if (!withoutTanMethod(passport)) return null;
		Map<String, Object> failed = failure(e);
		String code = string(failed, "code");
		if (failed.get("kind") != null || code == null || URGENT.contains(code) && !"9955".equals(code)) return null;
		for (Throwable t : causes(e)) {
			if (!(t instanceof ProcessException p) || p.getMsgStatus() == null) continue;
			for (HBCIRetVal r : errors(p.getMsgStatus().globStatus, p.getMsgStatus().segStatus)) if (r.code != null && ONE_STEP_REFUSED.contains(r.code)) return r;
		}
		return null;
	}

	/// The failure of a run that the bank refused because the user has no TAN method, with the code and the text of
	/// the refusal, also when another error such as 9800 "Dialog abgebrochen" came first in the answer.
	static Failure noTanMethod(HBCIRetVal refusal, RuntimeException e) {
		Failure f = new Failure("noTANMethod", refusal.code, Out.withoutSecrets(refusal.text));
		f.initCause(e);
		return f;
	}

	/// The failed message for an error of the whole run: the first error code of the bank, a
	/// network error, or the message of the exception.
	static Map<String, Object> failure(Throwable e) {
		List<Throwable> all = causes(e);
		for (Throwable t : all) {
			if (t instanceof Failure f) return message("failed", "kind", f.kind, "code", f.code, "text", f.getMessage());
		}
		for (Throwable t : all) {
			if (!(t instanceof ProcessException p) || p.getMsgStatus() == null) continue;
			HBCIRetVal r = relevant(errors(p.getMsgStatus().globStatus, p.getMsgStatus().segStatus));
			if (r != null) return message("failed", "kind", kind(r.code, r.text), "code", r.code, "text", Out.withoutSecrets(r.text));
		}
		for (Throwable t : all) {
			if (t instanceof CertificateException c) return message("failed", "kind", "certificate", "text", Out.withoutSecrets(String.valueOf(c.getMessage())));
		}
		for (Throwable t : all) {
			if (t instanceof SSLHandshakeException) {
				return message("failed", "kind", "certificate", "text", "The certificate of the bank's server is not valid: " + Out.withoutSecrets(String.valueOf(t.getMessage())));
			}
		}
		for (Throwable t : all) {
			if (t instanceof IOException) return message("failed", "kind", "network", "text", Out.withoutSecrets(String.valueOf(t.getMessage())));
		}
		return message("failed", "text", Out.withoutSecrets(String.valueOf(e.getMessage())));
	}

	/// The exception, its causes, and the exceptions that hbci4java keeps in the status of a message.
	static List<Throwable> causes(Throwable e) {
		List<Throwable> all = new ArrayList<>();
		for (Throwable t = e; t != null && !all.contains(t); t = t.getCause()) {
			all.add(t);
			if (t instanceof ProcessException p && p.getMsgStatus() != null) {
				for (Exception x : p.getMsgStatus().getExceptions()) all.addAll(causes(x));
			}
		}
		return all;
	}

	static boolean canceled(Throwable e) {
		return Inbox.canceled && causes(e).stream().anyMatch(t -> t instanceof AbortedException);
	}

	public static void main(String[] args) {
		if (args.length > 0 && args[0].equals("--self-test")) {
			SelfTest.run(java.util.Arrays.copyOfRange(args, 1, args.length));
			return;
		}
		// stdout carries only the protocol. hbci4java prints to System.out when it logs before its init.
		System.setOut(err);
		try {
			BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
			String line = in.readLine();
			if (line == null) return;
			Inbox.start(in);
			run((Map<?, ?>) Json.parse(line));
		} catch (Throwable e) {
			if (!canceled(e)) {
				diagnostic("FinTSHelper: " + e.getClass().getSimpleName() + ": " + e.getMessage());
				send(failure(e));
			}
		}
		out.flush();
		System.exit(0);
	}
}
