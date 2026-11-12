// FinTSHelper runs hbci4java for FinTSConnector (ADR 0014). The app starts it once per command and
// talks to it with one JSON object per line. stderr carries only masked diagnostics.
//
// The app sends one command first: bankInfo, accounts, or refresh. Then it sends only answers
// ({"type":"answer","id":1,"value":"…"}) and cancel. A closed stdin counts as cancel.
//
// The helper sends:
// - ask: a request for the user, with id and kind pin, tanMethod, tanMedium, tan, or approve. An
//   approval gets no answer. The helper sends withdraw with its id when hbci4java goes on.
// - alive, when hbci4java sends a message to the bank and when the answer arrives, so that the app
//   can tell a silent bank from a long answer in many parts.
// - progress, notice, bank, accounts, result, accountFailed, state, and failed.
// It ends with status 0 after its last message, also after failed.
//
// The passport of hbci4java stays in memory. The command brings it as the bytes of the last state,
// and the helper returns the new bytes in the state message.

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.ObjectInputFilter;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.PrintStream;
import java.math.BigDecimal;
import java.net.URI;
import java.nio.charset.StandardCharsets;
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
import java.util.concurrent.LinkedBlockingQueue;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.kapott.hbci.GV.HBCIJob;
import org.kapott.hbci.GV_Result.GVRKUms;
import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;
import org.kapott.hbci.GV_Result.GVRSaldoReq;
import org.kapott.hbci.GV_Result.HBCIJobResult;
import org.kapott.hbci.callback.AbstractHBCICallback;
import org.kapott.hbci.exceptions.AbortedException;
import org.kapott.hbci.exceptions.ProcessException;
import org.kapott.hbci.manager.BankInfo;
import org.kapott.hbci.manager.HBCIHandler;
import org.kapott.hbci.manager.HBCIUtils;
import org.kapott.hbci.manager.HBCIVersion;
import org.kapott.hbci.manager.MatrixCode;
import org.kapott.hbci.manager.QRCode;
import org.kapott.hbci.passport.HBCIPassport;
import org.kapott.hbci.passport.HBCIPassportPinTan;
import org.kapott.hbci.passport.storage.PassportData;
import org.kapott.hbci.status.HBCIRetVal;
import org.kapott.hbci.status.HBCIStatus;
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

	/// The masking rules of FinTSProbeJava for stderr: return codes with a fixed description, PINs and
	/// TANs removed, message segments left out, and IBANs, long numbers, and amounts masked.
	static final class Out {
		static final List<String> secrets = new ArrayList<>();
		static final Pattern RETURN_CODE = Pattern.compile("\\b([0139]\\d{3}):(?:(?!\\s+[0139]\\d{3}:)[^\\n;])*");
		static final Pattern CHALLENGE = Pattern.compile("(?i)found challenge|hhduc");
		static final Map<String, String> KNOWN = Map.ofEntries(
			Map.entry("0010", "message received"), Map.entry("0020", "order executed"),
			Map.entry("0030", "order received, TAN required"), Map.entry("3040", "more data available"),
			Map.entry("3076", "no strong customer authentication required"), Map.entry("3920", "allowed TAN methods for the user"),
			Map.entry("3955", "approval in the app"), Map.entry("3956", "approval still pending"),
			Map.entry("9010", "error in the message"), Map.entry("9050", "message partly faulty"),
			Map.entry("9075", "strong customer authentication required"), Map.entry("9078", "FinTS product not registered"),
			Map.entry("9120", "dialog already ended"), Map.entry("9160", "required field missing"),
			Map.entry("9800", "dialog aborted"), Map.entry("9930", "PIN blocked"),
			Map.entry("9931", "access locked or PIN wrong"), Map.entry("9942", "PIN wrong"));

		static synchronized String withoutSecrets(String text) {
			if (text == null) return "";
			for (String secret : secrets) if (!secret.isEmpty()) text = text.replace(secret, "•••");
			return text;
		}

		static synchronized void secret(String value) {
			secrets.add(value);
		}

		static boolean hasSegments(String text) {
			return text.contains("HNHBK") || text.contains("HNSHA") || text.contains("HNVSD") || text.contains("HNSHK");
		}

		static String masked(String text) {
			return withoutSecrets(text)
				.replaceAll("\\b[A-Z]{2}\\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\\b", "IBAN…")
				.replaceAll("\\d+(?:[.,]\\d+)*\\s?(?:EUR|€|USD|CHF)", "…")
				.replaceAll("\\b(?:\\d{1,3}(?:\\.\\d{3})+|\\d+),\\d{2}\\b", "…")
				.replaceAll("\\d{6,}", "…");
		}

		static String bank(String text) {
			if (text == null) return "";
			if (hasSegments(text)) return "(message content left out)";
			if (CHALLENGE.matcher(text).find()) return "(challenge of the bank left out)";
			String clean = withoutSecrets(text);
			Matcher m = RETURN_CODE.matcher(clean);
			if (!m.find()) return masked(clean);
			String prefix = clean.substring(0, m.start());
			List<String> codes = new ArrayList<>();
			do codes.add(m.group(1) + " " + KNOWN.getOrDefault(m.group(1), "(text of the bank left out)")); while (m.find());
			return masked(prefix) + String.join("; ", new java.util.LinkedHashSet<>(codes));
		}

		static void diagnostic(String text) {
			err.println(bank(text));
		}
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
					Out.diagnostic("FinTSHelper: unreadable input from the app, canceling");
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
				if (Integer.valueOf(id).toString().equals(string(m, "id"))) return string(m, "value");
			}
		}

		static void check() {
			if (canceled) throw new AbortedException("canceled");
		}
	}

	/// A PIN/TAN passport that hbci4java never writes to a file. It starts from the data of the last
	/// state, which hbci4java reads in its constructor, before the fields of a subclass exist.
	static final class Passport extends HBCIPassportPinTan {
		static PassportData loaded;

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

		@Override
		public void saveChanges() {
		}

		byte[] state() throws IOException {
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
				Out.diagnostic("FinTSHelper: the TAN method was not saved: " + e.getMessage());
			}
			return serialize(d);
		}

		static byte[] serialize(PassportData d) throws IOException {
			ByteArrayOutputStream bytes = new ByteArrayOutputStream();
			try (ObjectOutputStream o = new ObjectOutputStream(bytes)) {
				o.writeObject(d);
			}
			return bytes.toByteArray();
		}

		/// Reads a state of an earlier run. A state that does not read starts a new passport, and
		/// the bank then registers a new system ID.
		static PassportData deserialize(byte[] bytes) {
			try (ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes))) {
				in.setObjectInputFilter(ObjectInputFilter.Config.createFilter(
					"org.kapott.hbci.passport.storage.PassportData;java.util.Properties;java.util.Hashtable;java.util.Map$Entry;java.util.ArrayList;java.lang.*;!*"));
				return (PassportData) in.readObject();
			} catch (IOException | ClassNotFoundException | ClassCastException e) {
				Out.diagnostic("FinTSHelper: the saved state does not read, starting without it");
				return null;
			}
		}
	}

	/// Answers the callbacks of hbci4java through the app.
	static final class Callback extends AbstractHBCICallback {
		static final Pattern PIN_ERROR = Pattern.compile("Meldung der Bank: (\\d{4}): (.*)");
		final Map<?, ?> command;
		final String host;
		final int port;
		boolean login = true;
		int lastID;
		Integer approval;
		Map<String, Object> rejectedPIN;
		Map<String, Object> pinError;
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
			return Inbox.answer(id);
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
			if (level <= 2) Out.diagnostic("[" + (level <= 1 ? "error" : "warning") + "] " + msg);
		}

		@Override
		public void callback(HBCIPassport passport, int reason, String msg, int datatype, StringBuffer retData) {
			if (reason != NEED_PT_DECOUPLED_RETRY) withdrawApproval();
			switch (reason) {
				case NEED_PASSPHRASE_LOAD, NEED_PASSPHRASE_SAVE, NEED_CONNECTION, CLOSE_CONNECTION -> { }
				case NEED_COUNTRY -> set(retData, "DE");
				case NEED_BLZ -> set(retData, string(command, "bankCode"));
				case NEED_USERID -> set(retData, string(command, "user"));
				case NEED_CUSTOMERID -> set(retData, present(string(command, "customer")) ? string(command, "customer") : string(command, "user"));
				case NEED_HOST -> set(retData, host);
				case NEED_PORT -> set(retData, String.valueOf(port));
				case NEED_FILTER -> set(retData, "Base64");
				case WRONG_PIN -> rejectedPIN = pinError != null ? pinError : message("rejected", "text", "The bank did not accept the PIN.");
				case NEED_PT_PIN -> {
					String pin = ask(message("ask", "kind", "pin", "rejected", rejectedPIN));
					rejectedPIN = null;
					Out.secret(pin);
					set(retData, pin);
				}
				case NEED_PT_SECMECH -> {
					List<Object> methods = new ArrayList<>();
					for (String token : retData.toString().split("\\|")) {
						int colon = token.indexOf(':');
						methods.add(message("method", "id", colon < 0 ? token : token.substring(0, colon), "name", colon < 0 ? token : token.substring(colon + 1)));
					}
					set(retData, ask(message("ask", "kind", "tanMethod", "purpose", purpose(), "methods", methods)));
				}
				case NEED_PT_TANMEDIA -> {
					List<Object> media = new ArrayList<>();
					for (String name : retData.toString().split("\\|")) if (present(name)) media.add(name);
					set(retData, ask(message("ask", "kind", "tanMedium", "purpose", purpose(), "media", media)));
				}
				case NEED_PT_TAN, NEED_PT_PHOTOTAN, NEED_PT_QRTAN -> {
					String image = null, flicker = null;
					try {
						if (reason == NEED_PT_PHOTOTAN) image = Base64.getEncoder().encodeToString(new MatrixCode(retData.toString()).getImage());
						if (reason == NEED_PT_QRTAN) image = Base64.getEncoder().encodeToString(new QRCode(retData.toString(), msg).getImage());
					} catch (Exception e) {
						throw new Failure(null, null, "The bank sent an image that Moneten cannot read.");
					}
					if (reason == NEED_PT_TAN && retData.length() > 0) flicker = retData.toString();
					String tan = ask(message("ask", "kind", "tan", "purpose", purpose(), "prompt", challenge(msg), "image", image, "flicker", flicker));
					Out.secret(tan);
					set(retData, tan);
				}
				case NEED_PT_DECOUPLED -> {
					approval = ++lastID;
					send(message("ask", "id", approval, "kind", "approve", "purpose", purpose(), "prompt", challenge(msg), "method", firstLine(msg)));
				}
				case NEED_PT_DECOUPLED_RETRY -> Inbox.check();
				case HAVE_INST_MSG -> send(message("notice", "text", Out.withoutSecrets(msg)));
				default -> Out.diagnostic("FinTSHelper: callback " + reason + " not handled");
			}
		}

		@Override
		public void status(HBCIPassport passport, int statusTag, Object[] o) {
			if (statusTag == STATUS_MSG_SEND || statusTag == STATUS_MSG_RAW_RECV_ENCRYPTED) send(message("alive"));
			if (statusTag != STATUS_SEND_TASK || o == null || o.length == 0) return;
			Integer index = jobs.get(o[0]);
			if (index == null || index <= lastProgress) return;
			withdrawApproval();
			lastProgress = index;
			send(message("progress", "done", index, "of", jobCount));
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

	static Map<String, Object> bankInfo(String bankCode) {
		BankInfo info = bankCode == null ? null : HBCIUtils.getBankInfo(bankCode);
		if (info == null) return message("bank");
		return message("bank", "name", text(info.getName()), "bic", text(info.getBic()), "url", text(info.getPinTanAddress()));
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
		return message("row",
			"booked", day(l.bdate != null ? l.bdate : l.valuta), "value", day(l.valuta),
			"amount", l.value.getBigDecimalValue().toPlainString(), "currency", text(l.value.getCurr()),
			"name", other == null ? null : text(other.name), "iban", other == null ? null : text(other.iban), "bic", other == null ? null : text(other.bic),
			"purpose", purpose, "endToEnd", endToEnd, "mandate", text(present(l.mandateId) ? l.mandateId : tags.get("MREF")),
			"creditor", text(other != null && present(other.creditorid) ? other.creditorid : tags.get("CRED")),
			"bookingText", text(l.text), "pending", pending);
	}

	/// The first error of a job, or of the message when the job has none.
	static Map<String, Object> problem(HBCIJobResult result) {
		for (HBCIStatus status : new HBCIStatus[] {result.getJobStatus(), result.getGlobStatus()}) {
			for (HBCIRetVal r : status.getErrors()) return message("error", "code", r.code, "text", Out.withoutSecrets(r.text));
		}
		return message("error", "text", "The bank did not answer the request.");
	}

	/// Consorsbank answers HKSAL and HKKAZ without HKTAN with 9075, although its bank parameters
	/// say that they need no TAN (hbci4j/hbci4java#155).
	static final Set<String> TAN_FOR_ORDERS = Set.of("76030080");

	static void requireTanForOrders(HBCIPassport passport) {
		Properties bpd = passport.getBPD();
		for (String key : bpd.stringPropertyNames()) {
			if (!key.contains(".ParPinTan.PinTanGV") || !key.endsWith(".segcode")) continue;
			if (!List.of("HKSAL", "HKKAZ", "HKCAZ").contains(bpd.getProperty(key))) continue;
			bpd.setProperty(key.substring(0, key.length() - "segcode".length()) + "needtan", "J");
		}
	}

	static boolean allows(HBCIHandler handle, Konto k, String code, String job) {
		if (k.allowedGVs != null && !k.allowedGVs.isEmpty()) return k.allowedGVs.contains(code);
		return handle.isSupported(job);
	}

	static Konto find(Konto[] accounts, String id) {
		String wanted = id.replace(" ", "");
		for (Konto k : accounts) {
			if (wanted.equalsIgnoreCase(k.iban) || wanted.equals(k.number)) return k;
		}
		return null;
	}

	record Jobs(String id, String from, HBCIJob balance, HBCIJob statements) { }

	static void refresh(HBCIHandler handle, HBCIPassport passport, Konto[] accounts, List<?> requested, Callback callback) {
		if (TAN_FOR_ORDERS.contains(passport.getBLZ())) requireTanForOrders(passport);
		List<Jobs> all = new ArrayList<>();
		for (Object o : requested) {
			Map<?, ?> request = (Map<?, ?>) o;
			String id = string(request, "id"), from = string(request, "from");
			Konto k = find(accounts, id);
			if (k == null) {
				send(message("accountFailed", "account", id, "kind", "unsupported", "text", "The bank does not list this account for the login."));
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
			all.add(new Jobs(id, from, balance, statements));
		}
		callback.jobCount = all.size();
		callback.login = false;
		if (all.isEmpty()) return;
		callback.lastProgress = 0;
		send(message("progress", "done", 0, "of", all.size()));
		handle.execute();
		callback.withdrawApproval();
		for (Jobs jobs : all) {
			List<Object> errors = new ArrayList<>();
			Map<String, Object> balance = null, transactions = null;
			if (jobs.balance() != null) {
				GVRSaldoReq result = (GVRSaldoReq) jobs.balance().getJobResult();
				if (result.isOK() && result.getEntries().length > 0 && result.getEntries()[0].ready != null) {
					GVRSaldoReq.Info info = result.getEntries()[0];
					Value v = info.ready.value;
					balance = message("balance", "amount", v.getBigDecimalValue().toPlainString(), "currency", text(v.getCurr()), "date", day(info.ready.timestamp));
				} else {
					errors.add(problem(result));
				}
			}
			if (jobs.statements() != null) {
				GVRKUms result = (GVRKUms) jobs.statements().getJobResult();
				if (result.isOK()) {
					List<Object> rows = new ArrayList<>();
					for (UmsLine l : result.getFlatData()) rows.add(row(l, false));
					for (UmsLine l : result.getFlatDataUnbooked()) rows.add(row(l, true));
					transactions = message("transactions", "from", jobs.from(), "rows", rows);
				} else {
					errors.add(problem(result));
				}
			}
			send(message("result", "account", jobs.id(), "balance", balance, "transactions", transactions, "errors", errors));
		}
	}

	static void run(Map<?, ?> command) throws IOException {
		String type = string(command, "type");
		Properties props = new Properties();
		props.setProperty("log.loglevel.default", "3");
		if ("bankInfo".equals(type)) {
			HBCIUtils.init(props, new Callback(command, null));
			try {
				send(bankInfo(string(command, "bankCode")));
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
		HBCIUtils.init(props, callback);
		HBCIHandler handle = null;
		try {
			String state = string(command, "state");
			Passport.loaded = state == null ? null : Passport.deserialize(Base64.getDecoder().decode(state));
			Passport passport = new Passport();
			passport.setHost(callback.host);
			passport.setPort(callback.port);
			handle = new HBCIHandler(HBCIVersion.HBCI_300.getId(), passport);
			callback.withdrawApproval();
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
			send(message("state", "data", Base64.getEncoder().encodeToString(passport.state())));
		} finally {
			try {
				if (handle != null) handle.close();
			} catch (RuntimeException e) {
				Out.diagnostic("FinTSHelper: closing the dialog failed: " + e.getMessage());
			}
			HBCIUtils.done();
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
			List<HBCIRetVal> errors = new ArrayList<>(List.of(p.getMsgStatus().globStatus.getErrors()));
			errors.addAll(List.of(p.getMsgStatus().segStatus.getErrors()));
			if (!errors.isEmpty()) return message("failed", "code", errors.get(0).code, "text", Out.withoutSecrets(errors.get(0).text));
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
		if (args.length == 1 && args[0].equals("--self-test")) {
			SelfTest.run();
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
				Out.diagnostic("FinTSHelper: " + e.getClass().getSimpleName() + ": " + e.getMessage());
				send(failure(e));
			}
		}
		out.flush();
		System.exit(0);
	}
}
