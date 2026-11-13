"""A made-up bank on https://bank.localhost for the tests of ext record. It answers only the loopback address."""
import base64, hashlib, http.server, json, ssl, sys, urllib.parse

USER, PASSWORD = "erika", "geheim123"
SESSION, TOKEN = "abc123def456", "tok-9f8e7d6c5b4a"
# The OAuth login with PKCE of OAuth.lua: the challenge of each code, and the token that the code gives.
CODE, OAUTH_TOKEN, challenges = "auth-7f3a9c21e5", "oauth-5d4c3b2a1908", {}


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
		return self.headers.get("Authorization") in (f"Bearer {TOKEN}", f"Bearer {OAUTH_TOKEN}")

	def do_POST(self):
		form = urllib.parse.parse_qs(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
		if self.path == "/token":
			verifier = form.get("code_verifier", [""])[0]
			challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
			if form.get("code") == [CODE] and challenges.get(CODE) == challenge and form.get("password") == [PASSWORD]:
				self.reply(200, {"access_token": OAUTH_TOKEN, "token_type": "Bearer"})
			else:
				self.reply(400, {"error": "invalid_grant"})
		elif self.path == "/login" and form.get("username") == [USER] and form.get("password") == [PASSWORD]:
			echo = base64.b64encode(PASSWORD.encode()).decode()
			self.reply(200, {"ok": True, "access_token": TOKEN, "user": USER},
				[("Set-Cookie", f"SESSION={SESSION}; Path=/; Secure; HttpOnly"), ("X-Echo", echo)])
		else:
			self.reply(200, {"ok": False})

	def do_GET(self):
		url = urllib.parse.urlparse(self.path)
		if url.path == "/logout":
			self.reply(200, {})
		elif url.path == "/authorize":
			query = urllib.parse.parse_qs(url.query)
			if len(query.get("nonce", [""])[0]) != 36 or query.get("code_challenge_method") != ["S256"]:
				self.reply(400, {"error": "invalid_request"})
			else:
				challenges[CODE] = query["code_challenge"][0]
				self.reply(200, {"code": CODE})
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
