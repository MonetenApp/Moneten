import Foundation
import Synchronization

/// Sends real requests. It keeps no cookies and no cache, and it refuses every redirect, so that
/// `Network` checks the target first.
struct URLSessionTransport: Transport {
	private let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		return URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
	}()

	/// Blocks the script until the answer is there. Lua runs on one thread of the host process.
	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		var urlRequest = URLRequest(url: request.url)
		urlRequest.httpMethod = request.method
		urlRequest.httpBody = request.body
		for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
		let outcome = Outcome()
		let done = DispatchSemaphore(value: 0)
		session.dataTask(with: urlRequest) { data, response, error in
			let result: Result<HTTPResponse, any Error>
			if let response = response as? HTTPURLResponse {
				let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
				result = .success(HTTPResponse(status: response.statusCode, headers: headers, body: data ?? Data()))
			} else {
				result = .failure(ScriptError(error?.localizedDescription ?? "No answer from \(request.url.host() ?? "the server")."))
			}
			outcome.result.withLock { $0 = result }
			done.signal()
		}.resume()
		done.wait()
		return try outcome.result.withLock { $0! }.get()
	}

	private final class Outcome: Sendable {
		let result = Mutex<Result<HTTPResponse, any Error>?>(nil)
	}

	private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
		func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
			newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
			completionHandler(nil)
		}
	}
}
