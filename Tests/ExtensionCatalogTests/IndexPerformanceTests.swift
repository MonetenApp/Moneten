@testable import ExtensionCatalog
import Foundation
import Testing

/// The budget holds only in a release build: `scripts/test.sh -c release -Xswiftc -enable-testing --filter IndexPerformanceTests`.
@Suite struct IndexPerformanceTests {
	@Test func verifyAndParseA200EntryIndex() throws {
		let key = TestKey()
		let packages = (0..<200).map { i in TestCatalog.Package(id: "package-\(i)") }
		let data = TestCatalog.index(version: 2, packages)
		let signature = key.sign(data)
		let keys = try CatalogKeys(currentPEM: key.pem, nextPEM: TestKey().pem, lowestVersion: 1)
		func check() throws -> IndexVerifier.Accepted? {
			try IndexVerifier.check(index: data, signature: signature, keys: keys, floors: KeyFloors(), accepted: nil)
		}
		// The first run also sets up CryptoKit and the JSON decoder, and one run alone measures the
		// load of the runner too, so the budget holds for the median of 7 runs after it.
		#expect(try check()?.index.entries.count == 200)
		let clock = ContinuousClock()
		let times = try (0..<7).map { _ in try clock.measure { _ = try check() } }.sorted()
		print("index_verify_parse_ms=\(times[3] / .milliseconds(1)) samples_ms=\(times.map { $0 / .milliseconds(1) }) entries=200 bytes=\(data.count)")
		#if !DEBUG
		#expect(times[3] < .milliseconds(50))
		#endif
	}
}
