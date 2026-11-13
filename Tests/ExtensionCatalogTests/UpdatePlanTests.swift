@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import Testing

@Suite struct UpdatePlanTests {
	func manifest(_ package: TestCatalog.Package) throws -> Manifest {
		try Manifest.parse(package.files["manifest.json"]!, mode: .catalog)
	}

	func plan(to change: (inout TestCatalog.Package) -> Void, automatic: Bool = true, sessionRuns: Bool = false, confirmed: String? = nil) throws -> UpdatePlan {
		let old = TestCatalog.Package()
		var new = old
		new.version = "1.1"
		change(&new)
		return UpdatePlan(installed: try manifest(old), available: try manifest(new), automatic: automatic, sessionRuns: sessionRuns, confirmed: confirmed)
	}

	@Test func newHostWaitsForTheUser() throws {
		#expect(try plan { $0.hosts.append("login.example.org") } == .needsConfirmation(hosts: ["login.example.org"], fields: []))
	}

	@Test func newLoginFieldWaitsForTheUser() throws {
		#expect(try plan { $0.login.append(["label": "One-time code"]) } == .needsConfirmation(hosts: [], fields: ["One-time code"]))
	}

	@Test func removedHostInstallsByItself() throws {
		let old = TestCatalog.Package(hosts: ["api.bank.example", "old.bank.example"])
		var new = old
		new.version = "1.1"
		new.hosts = ["api.bank.example"]
		#expect(UpdatePlan(installed: try manifest(old), available: try manifest(new), automatic: true, sessionRuns: false, confirmed: nil) == .install)
	}

	@Test func updateDuringARunningSessionWaitsForItsEnd() throws {
		#expect(try plan(to: { _ in }, sessionRuns: true) == .afterSession)
	}

	@Test func newRightsWaitAlsoWhileASessionRuns() throws {
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, sessionRuns: true) == .needsConfirmation(hosts: ["login.example.org"], fields: []))
	}

	@Test func everyUpdateWaitsWithAutomaticUpdatesOff() throws {
		#expect(try plan(to: { _ in }, automatic: false) == .waitsForUser)
	}

	@Test func sameOrOlderVersionIsUpToDate() throws {
		#expect(try plan { $0.version = "1.0" } == .upToDate)
		#expect(try plan { $0.version = "0.9" } == .upToDate)
	}

	/// The order of tools/check_package.py and tools/build_index.py of the catalog: tuples of numbers, not padded.
	@Test(arguments: [("1.0", "1.0.0"), ("1.0.0", "1.0.1"), ("1.0.1", "1.1"), ("1.9", "1.10"), ("1", "1.0")])
	func versionsOrderLikeThePublisher(older: String, newer: String) {
		#expect(UpdatePlan.isNewer(newer, than: older))
		#expect(!UpdatePlan.isNewer(older, than: newer))
	}

	@Test func confirmedVersionInstallsWithItsNewHost() throws {
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, confirmed: "1.1") == .install)
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, sessionRuns: true, confirmed: "1.1") == .afterSession)
	}

	@Test func aNewerVersionNeedsItsOwnConfirmation() throws {
		#expect(try plan(to: { $0.version = "1.3"; $0.hosts.append("login.example.org") }, confirmed: "1.2")
			== .needsConfirmation(hosts: ["login.example.org"], fields: []))
	}

	@Test func confirmedVersionInstallsWithAutomaticUpdatesOff() throws {
		#expect(try plan(to: { _ in }, automatic: false, confirmed: "1.1") == .install)
		#expect(try plan(to: { _ in }, automatic: false, confirmed: "1.0") == .waitsForUser)
	}

	@Test func versionsCompareByNumber() throws {
		#expect(try plan { $0.version = "1.10" } == .install)
		#expect(try plan { $0.version = "2" } == .install)
	}

	func standing(status: String, note: String? = nil, listed: Bool = true) throws -> Standing {
		var package = TestCatalog.Package()
		package.status = status
		package.note = note
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, listed ? [package] : []))
		return Standing(of: InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: []), in: index)
	}

	@Test func blockedPackageStopsWithTheNote() throws {
		#expect(try standing(status: "blocked", note: "Sends the password to another host.")
			== .stopped("Example Bank is blocked. Sends the password to another host."))
	}

	@Test func withdrawnPackageStops() throws {
		#expect(try standing(status: "withdrawn", note: "The service closed its API.") == .stopped("Example Bank was withdrawn. The service closed its API."))
	}

	@Test func unmaintainedPackageRunsWithTheNote() throws {
		#expect(try standing(status: "unmaintained", note: "No answer since August.") == .runs(note: "Nobody maintains Example Bank. No answer since August."))
	}

	@Test func versionThatTheIndexNoLongerListsStops() throws {
		var package = TestCatalog.Package()
		package.version = "1.1"
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, [package]))
		#expect(Standing(of: InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: []), in: index)
			== .outdated("Version 1.0 of Example Bank is no longer in the catalog. Open Extensions and install the update."))
	}

	@Test func activePackageRuns() throws {
		#expect(try standing(status: "active") == .runs(note: nil))
	}

	@Test func packageMissingFromTheIndexStops() throws {
		#expect(try standing(status: "active", listed: false) == .stopped("Example Bank is no longer in the catalog."))
	}
}
