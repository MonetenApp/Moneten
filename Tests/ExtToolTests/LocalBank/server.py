"""A made-up bank on https://bank.localhost for the tests of ext record. It answers only the loopback address."""
import base64, http.server, json, ssl, sys, urllib.parse

USER, PASSWORD = "erika", "geheim123"
SESSION, TOKEN = "abc123def456", "tok-9f8e7d6c5b4a"


class Bank(http.server.BaseHTTPRequestHandler):
	def reply(self, status, body, headers=()):
		data = json.dumps(body).encode()
		self.send_response(status)
		self.send_header("Content-Type", "application/json")
		self.send_header("Content-Length", str(len(data)))
		for name, value in headers:
			self.send_header(name, value)
		self.end_headers()
		self.wfile.write(data)

	# The session cookie also travels in the address of the next page, so a recording holds it there too.
	def signed_in(self):
		return self.headers.get("Authorization") == f"Bearer {TOKEN}"

	def do_POST(self):
		form = urllib.parse.parse_qs(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
		if self.path == "/login" and form.get("username") == [USER] and form.get("password") == [PASSWORD]:
			echo = base64.b64encode(PASSWORD.encode()).decode()
			self.reply(200, {"ok": True, "access_token": TOKEN, "user": USER},
				[("Set-Cookie", f"SESSION={SESSION}; Path=/; Secure; HttpOnly"), ("X-Echo", echo)])
		else:
			self.reply(200, {"ok": False})

	def do_GET(self):
		url = urllib.parse.urlparse(self.path)
		if url.path == "/logout":
			self.reply(200, {})
		elif not self.signed_in():
			self.reply(401, {"error": "not signed in"})
		elif url.path == "/api/accounts":
			self.reply(200, {"name": "Giro", "number": "0202051"})
		elif url.path == "/api/transactions" and "page=2" in url.query:
			self.reply(200, {"rows": [{"name": "Max Mustermann", "amount": 25.5, "bookingDate": 1793703600, "purpose": "Dinner"}]})
		elif url.path == "/api/transactions":
			self.reply(200, {"rows": [{"name": "Stadtwerke Musterstadt", "amount": -89, "bookingDate": 1793876400, "purpose": "Electricity"}],
				"next": f"/api/transactions?page=2&sid={SESSION}"})
		else:
			self.reply(404, {})

	def log_message(self, *arguments):
		pass


class LoopbackServer(http.server.HTTPServer):
	def verify_request(self, request, address):
		return address[0] in ("127.0.0.1", "::1")


server = LoopbackServer(("0.0.0.0", 443), Bank)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[1], sys.argv[2])
server.socket = context.wrap_socket(server.socket, server_side=True)
print("ready", flush=True)
server.serve_forever()
