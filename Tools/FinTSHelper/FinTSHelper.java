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
//   which requests a new challenge.
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
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.status.HBCIStatus;
import org.kapott.hbci.structures.BigDecimalValue;
import org.kapott.hbci.structures.Konto;
import org.kapott.hbci.structures.Value;

public class FinTSHelper {
	static final PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8);
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

		static void check() {
			if (canceled) throw new AbortedException("canceled");
		}
	}

	/// A PIN/TAN passport that hbci4java never writes to a file. It starts from the data of the last
	/// state, which hbci4java reads in its constructor, before the fields of a subclass exist.
	static final class Passport extends HBCIPassportPinTan {
		static PassportData loaded;

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
			setUserId(d.userId);
			setSysId(d.sysId);
			setBPD(d.bpd);
			setUPD(d.upd);
			setHBCIVersion(d.hbciVersion);
			setCustomerId(d.customerId);
			setFilterType(d.filter);
			setAllowedTwostepMechanisms(d.twostepMechs);
			setCurrentTANMethod(d.tanMethod);
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

		/// The dialog whose last message the bank answered, until it ends. After a change of the TAN
		/// method hbci4java leaves it open at the bank, where a challenge of the login may still wait.
		DialogContext open;

		@Override
		public void onDialogEvent(DialogEvent event, DialogContext ctx) {
			// Recorded before hbci4java handles the answer, because a change of the method throws there.
			if (event == DialogEvent.MSG_SENT && present(ctx.getDialogId()) && !"0".equals(ctx.getDialogId())) open = ctx;
			super.onDialogEvent(event, ctx);
		}

		/// Ends the open dialog at the bank after a change of the TAN method, so that its challenge does
		/// not wait there while the next dialog requests the challenge of the new method.
		void endOpenDialog() {
			DialogContext dialog = open;
			open = null;
			if (dialog == null) return;
			try {
				new HBCIDialogEnd(HBCIDialogEnd.Flag.ACCEPT_ERROR).execute(dialog);
			} catch (RuntimeException e) {
				diagnostic("FinTSHelper: ending the dialog after the change of the TAN method failed: " + e.getMessage());
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
		/// the bank then registers a new system ID.
		static State deserialize(byte[] bytes) {
			try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes))) {
				in.setObjectInputFilter(ObjectInputFilter.Config.createFilter(
					"org.kapott.hbci.passport.storage.PassportData;java.util.Properties;java.util.Hashtable;java.util.Map$Entry;java.util.ArrayList;java.lang.*;!*"));
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
		static final Pattern PIN_ERROR = Pattern.compile("Meldung der Bank: (\\d{4}): (.*)");
		final Map<?, ?> command;
		final String host;
		final int port;
		boolean login = true;
		int lastID;
		Integer approval;
		Map<String, Object> rejectedPIN;
		Map<String, Object> pinError;
		/// The PIN of this run. A new dialog after a change of the TAN method uses it again, unless the
		/// bank rejected it.
		String pin;
		/// The method that the user changed to. Every request after it ends the dialog.
		String switchTo;
		/// The TAN medium of the state, or the one the user chose in this run. hbci4java asks for it
		/// before every order that needs a TAN.
		String tanMedium;
		final Map<HBCIJob, Integer> jobs = new IdentityHashMap<>();
		int jobCount, lastProgress = -1;

		/// hbci4java takes the host with the path and the query, and the port on its own.
		Callback(Map<?, ?> command, URI url) {
			this.command = command;
			if (url == null) {
				host = null;
				port = 0;
				return;
			}
			String path = url.getRawPath() == null || url.getRawPath().isEmpty() ? "/" : url.getRawPath();
			host = url.getHost() + path + (url.getRawQuery() == null ? "" : "?" + url.getRawQuery());
			port = url.getPort() > 0 ? url.getPort() : 443;
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
			}
		}

		/// Ends the dialog when the user changed the TAN method, also when hbci4java kept the exception
		/// of the callback in a status instead of throwing it.
		void checkSwitch() {
			if (switchTo != null) throw new SwitchMethod(switchTo);
		}

		/// Prepares the next dialog after a change of the TAN method.
		void restart() {
			switchTo = null;
			login = true;
			jobs.clear();
			jobCount = 0;
			lastProgress = -1;
			withdrawApproval();
		}

		/// hbci4java went on after a decoupled approval, so the bank has it.
		void withdrawApproval() {
			if (approval == null) return;
			send(message("withdraw", "id", approval));
			approval = null;
		}

		String purpose() {
			return login ? "login" : "download";
		}

		@Override
		public void log(String msg, int level, Date date, StackTraceElement trace) {
			if (msg == null) return;
			Matcher m = PIN_ERROR.matcher(msg);
			if (m.find()) pinError = message("rejected", "code", m.group(1), "text", Out.withoutSecrets(m.group(2)));
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
					set(retData, ask(message("ask", "kind", "tanMethod", "purpose", purpose(), "methods", methods)));
				}
				case NEED_PT_TANMEDIA -> {
					List<Object> media = new ArrayList<>();
					for (String name : retData.toString().split("\\|")) if (present(name)) media.add(name);
					if (tanMedium == null || !media.contains(tanMedium)) tanMedium = ask(message("ask", "kind", "tanMedium", "purpose", purpose(), "media", media));
					set(retData, tanMedium);
				}
				case NEED_PT_TAN, NEED_PT_PHOTOTAN, NEED_PT_QRTAN -> {
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
					Map<String, Object> request = message("ask", "kind", "tan", "purpose", purpose(), "prompt", challenge(msg), "image", image, "flicker", flicker);
					String tan = ask(choices(passport, request));
					Out.secret(tan);
					set(retData, tan);
				}
				case NEED_PT_DECOUPLED -> {
					if (passport instanceof Passport p) p.takeHHDuc();
					approval = ++lastID;
					send(choices(passport, message("ask", "id", approval, "kind", "approve", "purpose", purpose(), "prompt", challenge(msg), "method", firstLine(msg))));
				}
				case NEED_PT_DECOUPLED_RETRY -> {
					String method = Inbox.switchFor(approval);
					if (method != null) {
						switchTo = method;
						throw new SwitchMethod(method);
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
			if (statusTag != STATUS_SEND_TASK || o == null || o.length == 0) return;
			Integer index = jobs.get(o[0]);
			if (index == null || index <= lastProgress) return;
			withdrawApproval();
			lastProgress = index;
			send(message("progress", "done", index, "of", jobCount));
		}

		/// The requests that end the dialog once the user changed the TAN method, so that the old dialog
		/// asks the user nothing more. A new connection is allowed, because the end of the old dialog
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
			"product", text(k.type), "kind", text(k.acctype), "owner", text(owner), "currency", text(k.curr));
	}

	static final Pattern SEPA_TAG = Pattern.compile("(EREF|KREF|MREF|CRED|DEBT|COAM|OAMT|SVWZ|ABWA|ABWE|IBAN|BIC)\\+");

	/// One transaction for the app. MT940 statements carry the end-to-end reference, the mandate,
	/// the creditor ID, and the purpose as tagged text in the purpose lines, which the bank cuts every
	/// 27 characters, also inside words. Tagged lines therefore join without a space.
	static Map<String, Object> row(UmsLine l, boolean pending) {
		List<String> lines = l.usage == null ? List.of() : l.usage.stream().filter(FinTSHelper::present).toList();
		String joined = String.join("", lines);
		Map<String, String> tags = new LinkedHashMap<>();
		Matcher m = SEPA_TAG.matcher(joined);
		int start = -1;
		String tag = null;
		while (m.find()) {
			if (tag != null) tags.putIfAbsent(tag, joined.substring(start, m.start()).trim());
			tag = m.group(1);
			start = m.end();
		}
		if (tag != null) tags.putIfAbsent(tag, joined.substring(start).trim());
		String purpose = tags.isEmpty() ? String.join(" ", lines.stream().map(String::trim).toList()) : tags.getOrDefault("SVWZ", "");
		String endToEnd = text(present(l.endToEndId) ? l.endToEndId : tags.get("EREF"));
		if ("NOTPROVIDED".equals(endToEnd)) endToEnd = null;
		if (!present(purpose) && endToEnd != null) purpose = endToEnd;
		Konto other = l.other;
		// hbci4java reads no date from a CAMT entry that has a date and time only.
		if (l.bdate == null && l.valuta == null) throw new Failure("unsupported", null, "The bank sent a transaction without a booking date, so nothing of this account was stored.");
		return message("row",
			"booked", day(l.bdate != null ? l.bdate : l.valuta), "value", day(l.valuta),
			"amount", l.value.getBigDecimalValue().toPlainString(), "currency", text(l.value.getCurr()),
			"name", other == null ? null : text(other.name), "iban", other == null ? null : text(other.iban), "bic", other == null ? null : text(other.bic),
			"purpose", purpose, "endToEnd", endToEnd, "mandate", text(present(l.mandateId) ? l.mandateId : tags.get("MREF")),
			"creditor", text(other != null && present(other.creditorid) ? other.creditorid : tags.get("CRED")),
			"bookingText", text(l.text), "pending", pending);
	}

	/// The errors that the user must act on: a wrong PIN, a blocked access, and an app that the
	/// bank does not know. They come first, whatever their place in the answer.
	static final List<String> URGENT = List.of("9930", "9931", "9942", "9340", "9078");

	/// The error of the bank that the app shows: the first urgent one, or else the first one.
	static HBCIRetVal relevant(List<HBCIRetVal> errors) {
		for (String code : URGENT) {
			for (HBCIRetVal r : errors) if (code.equals(r.code)) return r;
		}
		return errors.isEmpty() ? null : errors.get(0);
	}

	static List<HBCIRetVal> errors(HBCIStatus... statuses) {
		List<HBCIRetVal> all = new ArrayList<>();
		for (HBCIStatus status : statuses) all.addAll(List.of(status.getErrors()));
		return all;
	}

	/// The error of a job, or of the message when the job has none.
	static Map<String, Object> problem(HBCIJobResult result) {
		HBCIRetVal r = relevant(errors(result.getJobStatus(), result.getGlobStatus()));
		if (r != null) return message("error", "code", r.code, "text", Out.withoutSecrets(r.text));
		return message("error", "text", "The bank did not answer the request.");
	}

	/// hbci4java reports a failed dialog start, for example a wrong PIN, in the status of execute and
	/// runs no job. The refresh then fails as a whole.
	static void requireLogin(HBCIExecStatus status) {
		for (String customer : status.getCustomerIds()) {
			HBCIDialogStatus dialog = status.getDialogStatus(customer);
			if (dialog != null && dialog.initStatus != null && !dialog.initStatus.isOK()) throw new ProcessException("dialog start failed", dialog.initStatus);
			List<Exception> exceptions = status.getExceptions(customer);
			if (dialog == null && exceptions != null && !exceptions.isEmpty()) throw new HBCI_Exception("dialog failed", exceptions.get(0));
		}
	}

	/// Whether an order goes with HKTAN ("J") or without ("N"), by bank code, for banks whose bank
	/// parameters say otherwise. Consorsbank answers HKSAL and HKKAZ without HKTAN with 9075, although
	/// its parameters say that they need no TAN, and HKWPD with HKTAN with 9160 (hbci4j/hbci4java#155).
	static final Map<String, Map<String, String>> TAN_RULES = Map.of("76030080", Map.of("HKSAL", "J", "HKKAZ", "J", "HKCAZ", "J", "HKWPD", "N"));

	static void applyTanRules(String bankCode, Properties bpd) {
		Map<String, String> rules = TAN_RULES.get(bankCode);
		if (rules == null) return;
		for (String key : bpd.stringPropertyNames()) {
			if (!key.contains(".ParPinTan.PinTanGV") || !key.endsWith(".segcode")) continue;
			String needtan = rules.get(bpd.getProperty(key));
			if (needtan != null) bpd.setProperty(key.substring(0, key.length() - "segcode".length()) + "needtan", needtan);
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
	/// FinTSAccount.kind(of:) of the app.
	static boolean securities(Konto k) {
		return k.acctype != null && k.acctype.trim().matches("[36][0-9]");
	}

	/// A securities account whose value the bank does not offer through FinTS.
	static Map<String, Object> unreadable(String id) {
		return message("accountFailed", "account", id, "kind", "unsupported", "text", "Moneten can't read this securities account at this bank yet.");
	}

	/// The jobs of one account: the balance and the transactions, or the holdings of a securities account.
	record Jobs(String id, String from, HBCIJob balance, HBCIJob statements, HBCIJob holdings) { }

	static void refresh(HBCIHandler handle, HBCIPassport passport, Konto[] accounts, List<?> requested, Callback callback) {
		applyTanRules(passport.getBLZ(), passport.getBPD());
		List<Jobs> all = new ArrayList<>();
		for (Object o : requested) {
			Map<?, ?> request = (Map<?, ?>) o;
			String id = string(request, "id"), from = string(request, "from");
			Konto k = find(accounts, id);
			if (k == null) {
				send(message("accountFailed", "account", id, "kind", "unsupported", "text", "The bank does not list this account for the login."));
				continue;
			}
			if (securities(k)) {
				if (!allows(handle, k, "HKWPD", "WPDepotList")) {
					send(unreadable(id));
					continue;
				}
				HBCIJob holdings = handle.newJob("WPDepotList");
				holdings.setParam("my", k);
				holdings.addToQueue();
				callback.jobs.put(holdings, all.size());
				all.add(new Jobs(id, from, null, null, holdings));
				continue;
			}
			HBCIJob balance = null, statements = null;
			if (allows(handle, k, "HKSAL", "SaldoReq")) {
				balance = handle.newJob("SaldoReq");
				balance.setParam("my", k);
				balance.addToQueue();
				callback.jobs.put(balance, all.size());
			}
			boolean camt = allows(handle, k, "HKCAZ", "KUmsAllCamt");
			if (camt || allows(handle, k, "HKKAZ", "KUmsAll")) {
				statements = handle.newJob(camt ? "KUmsAllCamt" : "KUmsAll");
				statements.setParam("my", k);
				if (from != null) statements.setParam("startdate", date(from));
				statements.addToQueue();
				callback.jobs.put(statements, all.size());
			}
			if (balance == null && statements == null) {
				send(message("accountFailed", "account", id, "kind", "unsupported",
					"text", "The FinTS server of the bank offers neither the balance nor the transactions of this account."));
				continue;
			}
			all.add(new Jobs(id, from, balance, statements, null));
		}
		callback.jobCount = all.size();
		callback.login = false;
		if (all.isEmpty()) return;
		callback.lastProgress = 0;
		send(message("progress", "done", 0, "of", all.size()));
		HBCIExecStatus status = handle.execute();
		callback.withdrawApproval();
		callback.checkSwitch();
		requireLogin(status);
		for (Jobs jobs : all) {
			HBCIJob statements = jobs.statements(), holdings = jobs.holdings();
			if (holdings != null) {
				send(alone(jobs.id(), () -> value(jobs.id(), (GVRWPDepotList) holdings.getJobResult(), ((HBCIJobImpl) holdings).redo() != null)));
				continue;
			}
			send(alone(jobs.id(), () -> result(jobs.id(), jobs.from(), jobs.balance() == null ? null : (GVRSaldoReq) jobs.balance().getJobResult(),
				statements == null ? null : (GVRKUms) statements.getJobResult(), statements != null && ((HBCIJobImpl) statements).redo() != null)));
		}
	}

	/// The value of a securities account as its balance, on the day of the statement: the total that the
	/// bank sends, or else the sum of the values of its holdings, because MT535 makes the total optional.
	/// `incomplete` says that the dialog ended before the bank sent the last part (3040) of the holdings.
	static Map<String, Object> value(String id, GVRWPDepotList list, boolean incomplete) {
		if (incomplete) throw new Failure(null, "3040", "The bank sent only part of the securities account, so nothing of this account was stored.");
		if (!list.isOK()) return message("result", "account", id, "errors", List.of(problem(list)));
		GVRWPDepotList.Entry statement = list.getEntries().length == 0 ? null : list.getEntries()[0];
		BigDecimalValue total = statement == null ? null : statement.total != null ? statement.total : sum(statement.getEntries());
		if (total == null) throw new Failure("unsupported", null, "The bank sent no value for this securities account.");
		return message("result", "account", id, "balance", message("balance", "amount", total.getValue().toPlainString(), "currency", text(total.getCurr()),
			"date", day(statement.timestamp)), "errors", List.of());
	}

	/// The sum of the values of the holdings, or null when there are none, or one has no value or another currency.
	static BigDecimalValue sum(GVRWPDepotList.Entry.Gattung[] holdings) {
		if (holdings.length == 0 || holdings[0].depotwert == null) return null;
		String currency = holdings[0].depotwert.getCurr();
		BigDecimal sum = BigDecimal.ZERO;
		for (GVRWPDepotList.Entry.Gattung g : holdings) {
			if (g.depotwert == null || !java.util.Objects.equals(currency, g.depotwert.getCurr())) return null;
			sum = sum.add(g.depotwert.getValue());
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
				for (UmsLine l : statementsResult.getFlatData()) rows.add(row(l, false));
				for (UmsLine l : statementsResult.getFlatDataUnbooked()) rows.add(row(l, true));
				transactions = message("transactions", "from", from, "rows", rows);
			} else {
				errors.add(problem(statementsResult));
			}
		}
		return message("result", "account", id, "balance", balance, "transactions", transactions, "errors", errors);
	}

	static void run(Map<?, ?> command) throws IOException {
		String type = string(command, "type");
		Properties props = new Properties();
		props.setProperty("log.loglevel.default", "3");
		if ("banks".equals(type)) {
			HBCIUtils.init(props, new Callback(command, null));
			try {
				send(banks());
			} finally {
				HBCIUtils.done();
			}
			return;
		}
		if (!"accounts".equals(type) && !"refresh".equals(type)) throw new IllegalArgumentException("unknown command " + type);
		URI url = https(string(command, "url"));
		props.setProperty("client.product.name", string(command, "product"));
		props.setProperty("client.product.version", string(command, "version"));
		props.setProperty("client.passport.PinTan.init", "1");
		props.setProperty("client.passport.PinTan.checkcert", "1");
		Callback callback = new Callback(command, url);
		try {
			SSLContext tls = SSLContext.getInstance("TLS");
			tls.init(null, new TrustManager[] {new MacTrust(callback)}, null);
			HttpsURLConnection.setDefaultSSLSocketFactory(tls.getSocketFactory());
		} catch (GeneralSecurityException e) {
			throw new IllegalStateException(e);
		}
		HBCIUtils.init(props, callback);
		try {
			String state = string(command, "state");
			Passport.State loaded = state == null ? null : Passport.deserialize(Base64.getDecoder().decode(state));
			Passport.loaded = loaded == null ? null : loaded.data();
			callback.tanMedium = loaded == null ? null : loaded.tanMedium();
			while (!dialog(type, command, callback)) {
				diagnostic("FinTSHelper: the user changed the TAN method, starting a new dialog");
			}
		} finally {
			HBCIUtils.done();
		}
	}

	/// One dialog with the bank. It returns false when the user changed the TAN method during it. The
	/// passport then keeps its data with the new method for the next dialog, which requests a new challenge.
	static boolean dialog(String type, Map<?, ?> command, Callback callback) throws IOException {
		HBCIHandler handle = null;
		Passport passport = new Passport();
		try {
			passport.setHost(callback.host);
			passport.setPort(callback.port);
			handle = new HBCIHandler(HBCIVersion.HBCI_300.getId(), passport);
			callback.withdrawApproval();
			callback.checkSwitch();
			Konto[] accounts = passport.getAccounts() == null ? new Konto[0] : passport.getAccounts();
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
			return true;
		} catch (RuntimeException e) {
			if (callback.switchTo == null) throw e;
			passport.endOpenDialog();
			Passport.loaded = passport.data();
			Passport.loaded.tanMethod = callback.switchTo;
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
			if (r != null) return message("failed", "code", r.code, "text", Out.withoutSecrets(r.text));
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
