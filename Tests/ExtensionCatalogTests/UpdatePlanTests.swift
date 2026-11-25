@testable import ExtensionCatalog
import ExtensionHost
import Foundation
import Testing

@Suite struct UpdatePlanTests {
	func manifest(_ package: TestCatalog.Package) throws -> Manifest {
		try Manifest.parse(package.files["manifest.json"]!, mode: .catalog)
	}

	func plan(to change: (inout TestCatalog.Package) -> Void, automatic: Bool = true, sessionRuns: Bool = false, confirmed: UpdatePlan.Approval? = nil) throws -> UpdatePlan {
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
		let plan = try plan { $0.login.append(["label": "One-time code"]) }
		#expect(plan == .needsConfirmation(hosts: [], fields: [.init(service: "Example Bank", label: "One-time code")]))
		if case let .needsConfirmation(_, fields) = plan { #expect(fields.map(\.description) == ["One-time code (Example Bank)"]) }
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
		var new = TestCatalog.Package(version: "1.1")
		new.hosts.append("login.example.org")
		let reviewed = UpdatePlan.Approval(version: "1.1", reviewed: try manifest(new))
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, confirmed: reviewed) == .install)
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, sessionRuns: true, confirmed: reviewed) == .afterSession)
	}

	@Test func aNewerVersionNeedsItsOwnConfirmation() throws {
		#expect(try plan(to: { $0.version = "1.3"; $0.hosts.append("login.example.org") }, confirmed: .init(version: "1.2"))
			== .needsConfirmation(hosts: ["login.example.org"], fields: []))
	}

	/// A login field counts with its service. The user approved "Password" for Example Card. Version 1.1 listed
	/// again asks for "Password" of Example Depot instead.
	@Test func approvedFieldOfOneServiceDoesNotCoverAnother() throws {
		let old = TestCatalog.Package()
		func adding(_ service: String) throws -> Manifest {
			var new = old
			new.version = "1.1"
			new.manifestFields = ["services": [["name": "Example Bank", "login": old.login], ["name": service, "login": [["label": "Password", "secret": true]]]]]
			return try manifest(new)
		}
		let approval = UpdatePlan.Approval(version: "1.1", reviewed: try adding("Example Card"))
		#expect(UpdatePlan(installed: try manifest(old), available: try adding("Example Depot"), automatic: true, sessionRuns: false, confirmed: approval)
			== .needsConfirmation(hosts: [], fields: [.init(service: "Example Depot", label: "Password")]))
	}

	/// A null character in a service or a label must not let one login field pass for another.
	@Test func approvedFieldDoesNotCoverAFieldWithTheSameTextSplitElsewhere() throws {
		let old = TestCatalog.Package()
		func adding(service: String, label: String) throws -> Manifest {
			var new = old
			new.version = "1.1"
			new.manifestFields = ["services": [["name": "Example Bank", "login": old.login], ["name": service, "login": [["label": label, "secret": true]]]]]
			return try manifest(new)
		}
		let approval = UpdatePlan.Approval(version: "1.1", reviewed: try adding(service: "Example Card\u{0}Card", label: "Password"))
		#expect(UpdatePlan(installed: try manifest(old), available: try adding(service: "Example Card", label: "Card\u{0}Password"), automatic: true,
			sessionRuns: false, confirmed: approval) == .needsConfirmation(hosts: [], fields: [.init(service: "Example Card", label: "Card\u{0}Password")]))
	}

	/// The same split on the path without an approval: a field of the installed version does not hide a new one.
	@Test func installedFieldDoesNotHideAFieldWithTheSameTextSplitElsewhere() throws {
		func manifest(version: String, service: String, label: String) throws -> Manifest {
			var package = TestCatalog.Package(version: version)
			package.manifestFields = ["services": [["name": service, "login": [["label": label, "secret": true]]]]]
			return try self.manifest(package)
		}
		#expect(UpdatePlan(installed: try manifest(version: "1.0", service: "Example Card\u{0}Card", label: "Password"),
			available: try manifest(version: "1.1", service: "Example Card", label: "Card\u{0}Password"), automatic: true, sessionRuns: false, confirmed: nil)
			== .needsConfirmation(hosts: [], fields: [.init(service: "Example Card", label: "Card\u{0}Password")]))
	}

	/// The user confirmed 1.1, which dropped `api.bank.example` and added `login.example.org`. The catalog lists 1.1
	/// again with both hosts: the user saw one in the review and runs the other today, so nothing asks again.
	@Test func approvalAndInstalledRightsCoverARelistedVersion() throws {
		var reviewed = TestCatalog.Package(version: "1.1")
		reviewed.hosts = ["login.example.org"]
		let approval = UpdatePlan.Approval(version: "1.1", reviewed: try manifest(reviewed))
		#expect(try plan(to: { $0.hosts.append("login.example.org") }, confirmed: approval) == .install)
		#expect(try plan(to: { $0.hosts += ["login.example.org", "data.example.net"] }, confirmed: approval)
			== .needsConfirmation(hosts: ["login.example.org", "data.example.net"], fields: []))
	}

	@Test func confirmedVersionInstallsWithAutomaticUpdatesOff() throws {
		#expect(try plan(to: { _ in }, automatic: false, confirmed: .init(version: "1.1")) == .install)
		#expect(try plan(to: { _ in }, automatic: false, confirmed: .init(version: "1.0")) == .waitsForUser)
	}

	@Test func versionsCompareByNumber() throws {
		#expect(try plan { $0.version = "1.10" } == .install)
		#expect(try plan { $0.version = "2" } == .install)
	}

	/// The record that an install of `package` writes, with the files that its index entry lists.
	func installed(_ package: TestCatalog.Package = TestCatalog.Package()) throws -> InstalledPackage {
		let entry = try #require(try CatalogIndex.parse(TestCatalog.index(version: 1, [package])).entry(package.id))
		return InstalledPackage(id: package.id, name: "Example Bank", version: package.version, files: entry.files)
	}

	func standing(status: String, note: String? = nil, listed: Bool = true) throws -> Standing {
		var package = TestCatalog.Package()
		package.status = status
		package.note = note
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, listed ? [package] : []))
		return Standing(of: try installed(), in: index)
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

	/// Without an index that this build accepts, no catalog package runs (issue #563).
	@Test func noAcceptedIndexStopsEveryCatalogPackage() {
		let installed = InstalledPackage(id: "example", name: "Example Bank", version: "1.0", files: [])
		#expect(Standing(of: installed, in: nil)
			== .stopped("Moneten has no list of extensions that this version accepts, so Example Bank does not run."))
	}

	/// The catalog can go back to an older version. There is nothing to install then, so the text offers no update (issue #186).
	@Test func olderVersionInTheIndexOffersNoUpdate() throws {
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, [TestCatalog.Package()]))
		let installed = InstalledPackage(id: "example", name: "Example Bank", version: "1.1", files: [])
		#expect(Standing(of: installed, in: index)
			== .stopped("The catalog lists version 1.0 of Example Bank, which is older than the installed version 1.1. There is no update to install."))
		var newer = TestCatalog.Package()
		newer.version = "1.1"
		#expect(UpdateState().plan(of: installed, manifest: try manifest(newer), in: index) == nil)
	}

	@Test func activePackageRuns() throws {
		#expect(try standing(status: "active") == .runs(note: nil))
	}

	/// The catalog lists the installed version again with another script. The installed files are not the ones
	/// that the accepted index signs, so they do not run.
	@Test func installedVersionListedWithOtherDigestsStops() throws {
		var relisted = TestCatalog.Package()
		relisted.script += "-- fixed\n"
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, [relisted]))
		#expect(Standing(of: try installed(), in: index) == .changed("Example Bank was changed and does not match the catalog."))
		relisted.status = "unmaintained"
		#expect(Standing(of: try installed(), in: try CatalogIndex.parse(TestCatalog.index(version: 3, [relisted])))
			== .changed("Example Bank was changed and does not match the catalog."))
	}

	@Test func installedVersionListedWithTheSameDigestsInAnotherOrderRuns() throws {
		let record = try installed()
		let reordered = InstalledPackage(id: record.id, name: record.name, version: record.version, files: record.files.reversed())
		#expect(Standing(of: reordered, in: try CatalogIndex.parse(TestCatalog.index(version: 2))) == .runs(note: nil))
	}

	/// The record of the install differs from the index entry of the same version by one file, as when the
	/// catalog lists the version again with a file more or a file less.
	@Test(arguments: ["added", "dropped"]) func installedVersionListedWithAnotherSetOfFilesStops(change: String) throws {
		let record = try installed()
		let extra = PackageFile(path: "Helper.lua", size: 12, sha256: String(repeating: "a", count: 64))
		let files = change == "added" ? Array(record.files.dropFirst()) : record.files + [extra]
		let other = InstalledPackage(id: record.id, name: record.name, version: record.version, files: files)
		#expect(Standing(of: other, in: try CatalogIndex.parse(TestCatalog.index(version: 2)))
			== .changed("Example Bank was changed and does not match the catalog."))
	}

	@Test func blockedStateComesBeforeOtherDigests() throws {
		var relisted = TestCatalog.Package()
		relisted.script += "-- fixed\n"
		relisted.status = "blocked"
		let index = try CatalogIndex.parse(TestCatalog.index(version: 2, [relisted]))
		#expect(Standing(of: try installed(), in: index) == .stopped("Example Bank is blocked."))
	}

	@Test func packageMissingFromTheIndexStops() throws {
		#expect(try standing(status: "active", listed: false) == .stopped("Example Bank is no longer in the catalog."))
	}
}
