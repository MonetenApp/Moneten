@testable import ExtensionHost
import Foundation
import Testing

/// The real transport against a server on the loopback address that answers each connection with
/// `reply`, which writes raw bytes after the request arrived.
@Suite struct TransportTests {
	final class Server: Sendable {
		let port: UInt16
		private let socket: Int32

		init(_ reply: @escaping @Sendable (Int32) -> Void) throws {
			let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
			self.socket = socket
			var address = sockaddr_in()
			address.sin_family = sa_family_t(AF_INET)
			address.sin_addr.s_addr = inet_addr("127.0.0.1")
			var length = socklen_t(MemoryLayout<sockaddr_in>.size)
			try withUnsafeMutablePointer(to: &address) { [socket] pointer in
				try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
					guard bind(socket, $0, length) == 0, listen(socket, 4) == 0, getsockname(socket, $0, &length) == 0 else { throw POSIXError(.EADDRINUSE) }
				}
			}
			port = UInt16(bigEndian: address.sin_port)
			Thread.detachNewThread { [socket] in
				while case let connection = accept(socket, nil, nil), connection >= 0 {
					var request: [UInt8] = []
					var byte: UInt8 = 0
					while !request.suffix(4).elementsEqual("\r\n\r\n".utf8), read(connection, &byte, 1) == 1 { request.append(byte) }
					var on: Int32 = 1
					setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
					reply(connection)
					close(connection)
				}
			}
		}

		deinit { close(socket) }

		var url: URL { URL(string: "http://127.0.0.1:\(port)/statement")! }

		static func write(_ text: String, to connection: Int32) {
			_ = Array(text.utf8).withUnsafeBytes { Darwin.write(connection, $0.baseAddress, $0.count) }
		}
	}

	@Test func answerIsReturnedAsTheServerSentIt() throws {
		let server = try Server { Server.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nHello", to: $0) }
		let response = try URLSessionTransport().send(HTTPRequest(method: "GET", url: server.url))
		#expect(response.status == 200 && response.header("content-type") == "text/plain" && response.body == Data("Hello".utf8))
	}

	@Test func redirectIsNotFollowed() throws {
		let server = try Server { Server.write("HTTP/1.1 302 Found\r\nLocation: https://evil.example/\r\nContent-Length: 0\r\n\r\n", to: $0) }
		let response = try URLSessionTransport().send(HTTPRequest(method: "GET", url: server.url))
		#expect(response.status == 302 && response.header("Location") == "https://evil.example/")
	}

	/// CFNetwork hands over the headers once a part of the body arrived, so the server sends 200 KB of 1 MB.
	@Test func transferThatBreaksAfterTheHeadersFails() throws {
		let server = try Server { Server.write("HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\n\r\n" + String(repeating: "x", count: 200_000), to: $0) }
		#expect(throws: ScriptError.self) { try URLSessionTransport().send(HTTPRequest(method: "GET", url: server.url)) }
	}

	@Test func bodyLargerThanTheLimitFails() throws {
		let server = try Server { connection in
			Server.write("HTTP/1.1 200 OK\r\nContent-Type: application/pdf\r\n\r\n", to: connection)
			let chunk = [UInt8](repeating: 0x25, count: 1_048_576)
			while chunk.withUnsafeBytes({ Darwin.write(connection, $0.baseAddress, $0.count) }) > 0 {}
		}
		#expect(throws: ScriptError("The answer of 127.0.0.1 is larger than 32 MB.")) {
			try URLSessionTransport().send(HTTPRequest(method: "GET", url: server.url))
		}
	}
}
