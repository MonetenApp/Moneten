import Foundation
import Synchronization

/// Sends real requests. It keeps no cookies and no cache, and it refuses every redirect, so that
/// `Network` checks the target first.
struct URLSessionTransport: Transport {
	/// The largest body of one answer. A larger one fails the request, so a server cannot fill the
	/// memory of the host process.
	static let maxBody = 32 * 1_048_576

	/// Runs after each request, also a failed one.
	private let finished: @Sendable () -> Void

	init(finished: @escaping @Sendable () -> Void = {}) {
		self.finished = finished
	}

	private let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		// A server that stops sending for a minute, or takes two minutes for one answer, fails the request.
		configuration.timeoutIntervalForRequest = 60
		configuration.timeoutIntervalForResource = 120
		return URLSession(configuration: configuration)
	}()

	/// Blocks the script until the answer is there. Lua runs on one thread of the host process.
	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		defer { finished() }
		var urlRequest = URLRequest(url: request.url)
		urlRequest.httpMethod = request.method
		urlRequest.httpBody = request.body
		for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
		let exchange = Exchange(host: request.url.host() ?? "the server")
		let task = session.dataTask(with: urlRequest)
		task.delegate = exchange
		task.resume()
		exchange.done.wait()
		return try exchange.result.withLock { $0! }.get()
	}

	/// Collects the answer of one task. A transfer that fails after the headers fails the request,
	/// so that a broken download never reads as an empty page.
	private final class Exchange: NSObject, URLSessionDataDelegate, Sendable {
		let host: String
		let body = Mutex(Data())
		let result = Mutex<Result<HTTPResponse, any Error>?>(nil)
		let done = DispatchSemaphore(value: 0)

		init(host: String) {
			self.host = host
		}

		func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
			newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
			completionHandler(nil)
		}

		func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
			if body.withLock({ $0.append(data); return $0.count > URLSessionTransport.maxBody }) { dataTask.cancel() }
		}

		func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
			let body = self.body.withLock { $0 }
			let outcome: Result<HTTPResponse, any Error> = if body.count > URLSessionTransport.maxBody {
				.failure(ScriptError("The answer of \(host) is larger than \(URLSessionTransport.maxBody / 1_048_576) MB."))
			} else if let error {
				.failure(ScriptError(error.localizedDescription))
			} else if let response = task.response as? HTTPURLResponse {
				.success(HTTPResponse(status: response.statusCode, headers: response.allHeaderFields.reduce(into: [:]) { $0["\($1.key)"] = "\($1.value)" }, body: body))
			} else {
				.failure(ScriptError("No answer from \(host)."))
			}
			result.withLock { $0 = outcome }
			done.signal()
		}
	}
}
