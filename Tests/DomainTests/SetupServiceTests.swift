import Testing
@testable import Domain

/// The entries under "Other" in the first step of "Add Account" (add-account-setup, "Other services").
@Suite("Setup services")
struct SetupServiceTests {
	@Test("\"Other\" lists the services of the extensions by name and \"Offline account / Cash\" last")
	func order() {
		let menu = SetupService.menu(extensionServices: [(id: "zahl", service: "Zahlbank"), (id: "muster", service: "Musterbroker"),
			(id: "beispiel", service: "beispielbank"), (id: "muster", service: "Musterbroker Depot")])
		#expect(menu.map(\.title) == ["beispielbank", "Musterbroker", "Musterbroker Depot", "Zahlbank", "Offline account / Cash"])
		#expect(menu.first == .extensionService(id: "beispiel", name: "beispielbank"))
	}

	@Test("Without extensions, \"Other\" lists only \"Offline account / Cash\"")
	func offlineOnly() {
		#expect(SetupService.menu(extensionServices: []) == [.offline])
	}
}
