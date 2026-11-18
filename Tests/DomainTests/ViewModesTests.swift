import Testing
@testable import Domain

@Suite("View modes")
struct ViewModesTests {
	@Test("A bar chart in the account views and a pie chart in the category views come back apart after a restart")
	func apartAfterRestart() {
		var defaults: [String: String] = ["viewMode": "list"]
		var modes = ViewModes(stored: { defaults[$0] }, store: { defaults[$0] = $1 })
		modes.set(.barChart, for: .accounts) { defaults[$0] = $1 }
		modes.set(.pieChart, for: .categories) { defaults[$0] = $1 }
		#expect(modes[.accounts] == .barChart)

		let restarted = ViewModes(stored: { defaults[$0] }, store: { defaults[$0] = $1 })
		#expect(restarted[.accounts] == .barChart)
		#expect(restarted[.categories] == .pieChart)
	}

	@Test("The one mode of an earlier version stays under its key and starts both kinds, and nothing stored starts the bar chart")
	func earlierVersion() {
		#expect(ViewModes.key(of: .accounts) == "viewMode")
		#expect(ViewModes.key(of: .categories) != "viewMode")
		let earlier = ViewModes(stored: { $0 == "viewMode" ? "pieChart" : nil }, store: { _, _ in })
		#expect(earlier[.accounts] == .pieChart)
		#expect(earlier[.categories] == .pieChart)
		let fresh = ViewModes(stored: { _ in nil }, store: { _, _ in })
		#expect(fresh[.accounts] == .barChart)
		#expect(fresh[.categories] == .barChart)
		let unreadable = ViewModes(stored: { _ in "dailyChart" }, store: { _, _ in })
		#expect(unreadable[.accounts] == .barChart)
		#expect(unreadable[.categories] == .barChart)
	}

	@Test("With only the one mode of an earlier version stored, a change of the account mode keeps the category mode, also when read again")
	func changeAccountsThenReadAgain() {
		var defaults: [String: String] = ["viewMode": "pieChart"]
		var modes = ViewModes(stored: { defaults[$0] }, store: { defaults[$0] = $1 })
		modes.set(.barChart, for: .accounts) { defaults[$0] = $1 }
		#expect(modes[.categories] == .pieChart)
		let again = ViewModes(stored: { defaults[$0] }, store: { defaults[$0] = $1 })
		#expect(again[.accounts] == .barChart)
		#expect(again[.categories] == .pieChart)
	}
}
