#!/usr/bin/env python3
# Runs one login of the bundled FinTS helper in its sandbox against a made-up bank on 127.0.0.1, for
# the check of scripts/build-app.sh (ADR 0018). It never contacts a bank: the helper gets this script
# as its HTTPS proxy, and the proxy answers the CONNECT itself with a self-signed certificate for the
# FinTS host of the bank code and never opens a connection of its own. The script answers the trust
# request only for that certificate, so a helper that bypassed the proxy would send nothing to a
# bank. The made-up bank answers the dialog start with 9800, and the helper must report it.
#   scripts/fints-helper-smoke.py <app>/Contents/Resources/FinTSHelper
import base64, json, os, re, socket, ssl, subprocess, sys, tempfile, threading, urllib.parse, zipfile

BANK_CODE = "12030000"
helper = os.path.abspath(sys.argv[1])
events = []

def fail(reason, stderr=""):
	print("The FinTS helper failed its sandboxed login against the made-up bank: " + reason, file=sys.stderr)
	for e in events: print("  " + e, file=sys.stderr)
	if stderr: print("stderr of the helper:\n" + stderr.strip(), file=sys.stderr)
	sys.exit(1)

def fints_host():
	core = next(n for n in os.listdir(os.path.join(helper, "lib")) if n.startswith("hbci4j-core-"))
	with zipfile.ZipFile(os.path.join(helper, "lib", core)) as jar:
		for line in jar.read("blz.properties").decode("iso-8859-1").splitlines():
			if line.startswith(BANK_CODE + "="):
				return urllib.parse.urlparse(line.split("|")[5]).hostname
	fail("the bank directory has no FinTS address for " + BANK_CODE)

def message(dialog, number, segments):
	body = "".join(segments) + "HNHBS:%d:1+%s'" % (len(segments) + 2, number)
	head = "HNHBK:1:3+%012d+300+%s+%s+%s:1'"
	return head % (len(head % (0, dialog, number, dialog)) + len(body), dialog, number, dialog) + body

def bank(listener, context):
	while True:
		conn, _ = listener.accept()
		try:
			data = b""
			while b"\r\n\r\n" not in data:
				chunk = conn.recv(4096)
				if not chunk: break
				data += chunk
			events.append("proxy: " + data.split(b"\r\n")[0].decode("ascii", "replace"))
			if not data.startswith(b"CONNECT "):
				conn.close(); continue
			conn.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
			tls = context.wrap_socket(conn, server_side=True)
			buffer = b""
			while b"\r\n\r\n" not in buffer:
				buffer += tls.recv(4096)
			head, rest = buffer.split(b"\r\n\r\n", 1)
			length = int(re.search(rb"(?i)content-length:\s*(\d+)", head).group(1))
			while len(rest) < length:
				rest += tls.recv(4096)
			request = base64.b64decode(rest).decode("iso-8859-1")
			events.append("bank: " + ",".join(s.split(":")[0] for s in request.split("'") if s))
			answer = message("SMOKETEST", request.split("+")[4].split("'")[0], ["HIRMG:2:2+9800::Dialog abgebrochen'"])
			payload = base64.b64encode(answer.encode("iso-8859-1"))
			tls.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(payload) + payload)
			tls.close()
		except (OSError, ValueError, AttributeError) as e:
			events.append("bank: " + type(e).__name__)
			conn.close()

host = fints_host()
work = tempfile.mkdtemp()
cert, key = os.path.join(work, "cert.pem"), os.path.join(work, "key.pem")
subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "1",
	"-subj", "/CN=" + host, "-addext", "subjectAltName=DNS:" + host], check=True, capture_output=True)
leaf = base64.b64encode(ssl.PEM_cert_to_DER_cert(open(cert).read())).decode()
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen()
threading.Thread(target=bank, args=(listener, context), daemon=True).start()

# The arguments of FinTSConnector.Helper.bundled, with this script as the proxy in place of the one of macOS.
process = subprocess.Popen([os.path.join(helper, "java"), "-Djava.awt.headless=true",
	"-Dhttps.proxyHost=127.0.0.1", "-Dhttps.proxyPort=%d" % listener.getsockname()[1],
	"-XX:ErrorFile=/dev/null", "-XX:+DisableAttachMechanism", "-Xrs", "-cp", os.path.join(helper, "lib") + "/*", "FinTSHelper"],
	stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env={}, text=True)
timed_out = threading.Event()
def stop():
	timed_out.set(); process.kill()
timer = threading.Timer(60, stop)
timer.start()
def send(line):
	process.stdin.write(json.dumps(line) + "\n"); process.stdin.flush()
send({"type": "accounts", "bankCode": BANK_CODE, "url": "https://" + host + "/", "user": "smoketest", "product": "SMOKETEST", "version": "0.0.0"})
result = None
for line in process.stdout:
	m = json.loads(line)
	# The helper masks its texts, and the made-up bank gets no secret, so a failure may show them.
	events.append("helper: " + (json.dumps(m) if m.get("type") == "failed" else m.get("type", "?")))
	if m.get("type") == "ask" and m.get("kind") == "pin":
		send({"type": "answer", "id": str(m["id"]), "value": "12345"})
	elif m.get("type") == "trust":
		proxied = any(e.startswith("proxy: CONNECT ") for e in events)
		ours = m.get("host") == host and (m.get("chain") or [None])[0] == leaf
		send({"type": "answer", "id": str(m["id"]), "value": "trusted" if proxied and ours else "The check trusts only its made-up bank."})
	elif m.get("type") == "ask":
		send({"type": "cancel"})
	elif m.get("type") in ("failed", "accounts"):
		result = m
process.stdin.close()
status = process.wait()
timer.cancel()
stderr = process.stderr.read()
if timed_out.is_set():
	fail("it did not finish within 60 seconds. When a build with another signature used the container of the helper on "
		"this Mac, macOS asks once whether this one may use it, and the helper waits for the answer (ADR 0018).", stderr)
if status != 0: fail("it ended with status %d" % status, stderr)
if not any(e.startswith("bank: HNHBK") for e in events): fail("the made-up bank got no FinTS message", stderr)
if not result or result.get("code") != "9800": fail("it reported %s instead of the answer 9800" % json.dumps(result), stderr)
