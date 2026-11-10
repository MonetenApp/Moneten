import Foundation
import Testing
@testable import Domain

@Suite("Chart axes")
struct ChartAxisTests {
	@Test("A small overdraft adds little room below zero, and the marks are round")
	func smallOverdraft() {
		let axis = AmountAxis(values: [-5_000, 200, 1_050_000])
		#expect(axis.marks == [0, 500_000, 1_000_000])
		#expect(axis.lower > -100_000 && axis.lower < -5_000)
		#expect(axis.upper > 1_050_000 && axis.upper < 1_100_000)
	}

	@Test("Positive balances start at zero")
	func positive() {
		let axis = AmountAxis(values: [1_200, 1_900])
		#expect(axis.lower == 0)
		#expect(axis.marks == [0, 500, 1_000, 1_500])
	}

	@Test("Deposits and withdrawals get marks on both sides of zero")
	func bothSides() {
		#expect(AmountAxis(values: [3_000, -2_000]).marks == [-2_000, 0, 2_000])
	}

	@Test("Marks are whole multiples of the smallest amount of the currency")
	func smallestAmount() {
		#expect(AmountAxis(values: [0, 0.01]).marks == [0, 0.01])
		#expect(AmountAxis(values: [0.09]).marks.allSatisfy { abs($0 * 100 - ($0 * 100).rounded()) < 1e-9 })
		#expect(AmountAxis(values: [0.003], unit: 0.001).marks == [0, 0.001, 0.002, 0.003])
		#expect(AmountAxis(values: [9.9]).marks == [0, 2.5, 5, 7.5])
	}

	@Test("No amounts show only zero")
	func empty() {
		#expect(AmountAxis(values: [0, 0]).marks == [0])
	}

	@Test("Ten years show year starts, and a mark too close to the end is left out")
	func years() {
		let axis = DateAxis(from: Day(year: 2016, month: 11, day: 20), to: Day(year: 2026, month: 11, day: 11), trailing: 0.05)
		#expect(axis.unit == .year)
		#expect(axis.marks.map(\.year) == [2018, 2020, 2022, 2024, 2026])
		let near = DateAxis(from: Day(year: 2016, month: 3, day: 1), to: Day(year: 2026, month: 2, day: 1), trailing: 0.05)
		#expect(near.marks.last?.year == 2024)
	}

	@Test("One year shows every second month start")
	func months() {
		let axis = DateAxis(from: Day(year: 2025, month: 11, day: 11), to: Day(year: 2026, month: 11, day: 11))
		#expect(axis.unit == .month)
		#expect(axis.marks.map(\.month) == [1, 3, 5, 7, 9, 11])
	}

	@Test("A month shows days")
	func days() {
		let axis = DateAxis(from: Day(year: 2026, month: 10, day: 1), to: Day(year: 2026, month: 11, day: 1))
		#expect(axis.unit == .day)
		#expect(axis.marks.first == Day(year: 2026, month: 10, day: 1))
		#expect(axis.marks.count <= 6)
	}
}
