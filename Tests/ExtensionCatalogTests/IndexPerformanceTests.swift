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
		let clock = ContinuousClock()
		var accepted: IndexVerifier.Accepted?
		let elapsed = try clock.measure {
			accepted = try IndexVerifier.check(index: data, signature: signature, keys: keys, floors: KeyFloors(), accepted: nil)
		}
		#expect(accepted?.index.entries.count == 200)
		print("index_verify_parse_ms=\(elapsed / .milliseconds(1)) entries=200 bytes=\(data.count)")
		#if !DEBUG
		#expect(elapsed < .milliseconds(50))
		#endif
	}
}
