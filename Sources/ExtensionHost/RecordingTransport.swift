import Foundation

/// Sends each request through another transport and reports the request and its response as an
/// exchange of a fixture, for `ext record`. The exchange holds the secrets of the run; `ext` removes
/// them before it writes the file.
struct RecordingTransport: Transport {
	let base: any Transport
	let record: (Fixture.Exchange) -> Void

	func send(_ request: HTTPRequest) throws -> HTTPResponse {
		let response = try base.send(request)
		record(Fixture.Exchange(request: Fixture.Request(method: request.method, url: request.url, headers: request.headers, body: request.body),
			response: Fixture.Response(status: response.status, headers: response.headers, body: response.body)))
		return response
	}
}
