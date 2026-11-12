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
			// The thread owns the socket and closes it when `accept` fails. If `deinit` closed it, a new
			// server could get the same number while this thread still loops on it, and answer its requests.
			Thread.detachNewThread { [socket] in
				defer { close(socket) }
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

		/// Wakes `accept` with an error, so that the thread ends and closes the socket.
		deinit { shutdown(socket, SHUT_RDWR) }

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

	/// A server whose thread still answers a connection when the test drops it never answers the
	/// connections of a server that comes after it.
	@Test func droppedServerNeverAnswersANewOne() throws {
		let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
		var old: Server? = try Server { connection in
			entered.signal()
			gate.wait()
			gate.signal()
			Server.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nold", to: connection)
		}
		let client = Darwin.socket(AF_INET, SOCK_STREAM, 0)
		defer { close(client) }
		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		address.sin_port = old!.port.bigEndian
		_ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
		Server.write("GET /statement HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", to: client)
		entered.wait()
		old = nil
		let new = try Server { Server.write("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nnew", to: $0) }
		gate.signal()
		for _ in 0..<4 {
			#expect(try URLSessionTransport().send(HTTPRequest(method: "GET", url: new.url)).body == Data("new".utf8))
		}
	}

	@Test func bodyLargerThanTheLimitFails() throws {
		let server = try Server { connection in
			Server.write("HTTP/1.1 200 OK\r\nContent-Type: application/pdf\r\n\r\n", to: connection)
			// 40 MB, above the limit, and less once the client is gone.
			let chunk = [UInt8](repeating: 0x25, count: 1_048_576)
			for _ in 0..<40 {
				guard chunk.withUnsafeBytes({ Darwin.write(connection, $0.baseAddress, $0.count) }) > 0 else { break }
			}
		}
		#expect(throws: ScriptError("The answer of 127.0.0.1 is larger than 32 MB.")) {
			try URLSessionTransport().send(HTTPRequest(method: "GET", url: server.url))
		}
	}
}
