import Testing
@testable import Domain

@Suite("View modes")
struct ViewModesTests {
	@Test("A bar chart in the account views and a pie chart in the category views come back apart after a restart")
	func apartAfterRestart() {
		var defaults: [String: String] = ["viewMode": "list"]
		var modes = ViewModes(stored: { defaults[$0] })
		modes[.accounts] = .barChart
		modes[.categories] = .pieChart
		for kind in [ViewModes.Kind.accounts, .categories] { defaults[ViewModes.key(of: kind)] = modes[kind].rawValue }
		#expect(modes[.accounts] == .barChart)

		let restarted = ViewModes(stored: { defaults[$0] })
		#expect(restarted[.accounts] == .barChart)
		#expect(restarted[.categories] == .pieChart)
	}

	@Test("The one mode of an earlier version stays under its key and starts both kinds, and nothing stored starts the bar chart")
	func earlierVersion() {
		#expect(ViewModes.key(of: .accounts) == "viewMode")
		#expect(ViewModes.key(of: .categories) != "viewMode")
		let earlier = ViewModes(stored: { $0 == "viewMode" ? "pieChart" : nil })
		#expect(earlier[.accounts] == .pieChart)
		#expect(earlier[.categories] == .pieChart)
		let fresh = ViewModes(stored: { _ in nil })
		#expect(fresh[.accounts] == .barChart)
		#expect(fresh[.categories] == .barChart)
		let unreadable = ViewModes(stored: { _ in "dailyChart" })
		#expect(unreadable[.accounts] == .barChart)
		#expect(unreadable[.categories] == .barChart)
	}
}
