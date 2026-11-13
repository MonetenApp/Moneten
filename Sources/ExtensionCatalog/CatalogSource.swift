import Domain
import Foundation

/// Gets the files of the catalog. A request carries no query, no cookie, and nothing that names the
/// user or the Mac, and the app asks for the whole index, so the catalog cannot tell which extensions are
/// installed. Redirects are refused, so no request reaches another host. A body may not be larger than
/// the limit of its request, so a compromised host cannot fill the memory of the app.
public struct CatalogSource: Sendable {
	public let base: URL
	private let session: URLSession
	/// The timeouts of the transport of extensions.
	let timeouts = (request: TimeInterval(60), resource: TimeInterval(120))

	/// The largest index the app accepts. The index of 200 packages has about 330 KB.
	public static let indexLimit = 4 << 20
	/// An Ed25519 signature.
	public static let signatureSize = 64

	public init(base: URL, protocolClasses: [AnyClass]? = nil) {
		self.base = base
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpAdditionalHeaders = ["User-Agent": "Moneten"]
		configuration.timeoutIntervalForRequest = timeouts.request
		configuration.timeoutIntervalForResource = timeouts.resource
		if let protocolClasses { configuration.protocolClasses = protocolClasses }
		session = URLSession(configuration: configuration)
	}

	/// The file at `path` below the catalog address, with at most `limit` bytes.
	public func fetch(_ path: String, limit: Int) async throws -> Data {
		let url = base.appending(path: path)
		if url.isFileURL {
			let data = try Data(contentsOf: url)
			guard data.count <= limit else { throw CatalogError.tooLarge(path) }
			return data
		}
		let (bytes, response) = try await session.bytes(from: url, delegate: NoRedirects())
		defer { bytes.task.cancel() }
		guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
		guard response.expectedContentLength <= Int64(limit) else { throw CatalogError.tooLarge(path) }
		var data = Data()
		data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
		for try await byte in bytes {
			guard data.count < limit else { throw CatalogError.tooLarge(path) }
			data.append(byte)
		}
		return data
	}
}

/// Refuses every redirect, so that no catalog request reaches another host than the catalog address.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest) async -> URLRequest? {
		nil
	}
}

/// Builds the connector of a session when the session starts, not when the refresh is asked for. A
/// refresh that waited behind others then runs only an extension that is still installed and allowed.
public struct CheckedAtStart: BankConnector {
	let resolve: @Sendable () async throws -> any BankConnector

	public init(_ resolve: @escaping @Sendable () async throws -> any BankConnector) {
		self.resolve = resolve
	}

	public func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		try await resolve().refresh(request, session)
	}
}
