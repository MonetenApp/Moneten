// The masking rules for every text that FinTSHelper writes to stderr and FinTSProbeJava prints:
// return codes of the bank keep only a fixed description, PINs and TANs are removed, message
// segments are left out, and IBANs, runs of six or more digits, and amounts are masked.
// scripts/fints-probe-java.sh compiles this file into the probe too.

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class Out {
	/// The PIN and every TAN entered in this run.
	static final List<String> secrets = new ArrayList<>();
	/// Only the probe sets it, with --show-values. Without it, texts of the bank are masked.
	static boolean showValues;

	static final Pattern RETURN_CODE = Pattern.compile("\\b([0139]\\d{3}):(?:(?!\\s+[0139]\\d{3}:)[^\\n;])*");
	static final Pattern ORDER_REFERENCE = Pattern.compile("CustomMsg\\.[A-Za-z0-9_.]+");
	/// hbci4java logs the challenge of the bank, which is left out of the callbacks too.
	static final Pattern CHALLENGE = Pattern.compile("(?i)found challenge|hhduc");

	/// Return codes with a description that follows the FinTS specification.
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

	/// Message segments carry the PIN in the signature and the data of the accounts.
	static boolean hasSegments(String text) {
		return text != null && (text.contains("HNHBK") || text.contains("HNSHA") || text.contains("HNVSD") || text.contains("HNSHK"));
	}

	/// Masks IBANs, runs of six or more digits, and amounts, and removes the secrets.
	static String masked(String text) {
		if (showValues) return withoutSecrets(text);
		return withoutSecrets(text)
			.replaceAll("\\b[A-Z]{2}\\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\\b", "IBAN…")
			.replaceAll("\\d+(?:[.,]\\d+)*\\s?(?:EUR|€|USD|CHF)", "…")
			.replaceAll("\\b(?:\\d{1,3}(?:\\.\\d{3})+|\\d+),\\d{2}\\b", "…")
			.replaceAll("\\d{6,}", "…");
	}

	/// A text that may hold return codes of the bank. If it holds one, only the text before the
	/// first code, the codes with their fixed descriptions, and the references to the order
	/// segments remain. Everything else in the text can come from the bank and is left out.
	static String bank(String text) {
		if (text == null) return "";
		if (hasSegments(text)) return "(message content left out)";
		if (showValues) return withoutSecrets(text);
		if (CHALLENGE.matcher(text).find()) return "(challenge of the bank left out)";
		String clean = withoutSecrets(text);
		Matcher m = RETURN_CODE.matcher(clean);
		if (!m.find()) return masked(clean);
		String prefix = clean.substring(0, m.start());
		List<String> parts = new ArrayList<>();
		do parts.add(code(m.group(1))); while (m.find());
		Matcher r = ORDER_REFERENCE.matcher(clean);
		while (r.find()) parts.add("(" + r.group() + ")");
		return masked(prefix) + String.join("; ", new LinkedHashSet<>(parts));
	}

	/// A return code with its fixed description.
	static String code(String code) {
		return code + " " + KNOWN.getOrDefault(code, "(text of the bank left out)");
	}

	/// A text of the bank in a callback: shown only with --show-values.
	static String callbackText(String text, String fallback) {
		if (text == null || text.isBlank()) return fallback;
		if (hasSegments(text)) return fallback;
		return showValues ? withoutSecrets(text) : fallback + " (the text of the bank shows with --show-values)";
	}
}
