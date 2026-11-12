import Foundation
import Testing
@testable import Sync

/// tan-handling "Flicker code size": smaller and larger in steps, the size kept for the next flicker
/// code, and the seizure warning before the first enlargement only.
@MainActor
@Suite("Flicker code size")
struct FlickerCodeSizeTests {
	let suite = "MonetenTests-\(UUID().uuidString)"
	var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

	@Test("The first enlargement waits for the warning, and the code grows only after the user agrees")
	func warningFirst() {
		let size = FlickerCodeSize(defaults: defaults)
		#expect(size.width == 240)
		size.enlarge()
		#expect(size.showsWarning)
		#expect(size.width == 240)
		size.decline()
		#expect(!size.showsWarning)
		#expect(size.width == 240)
		size.enlarge()
		#expect(size.showsWarning)
		size.agree()
		#expect(!size.showsWarning)
		#expect(size.width == 280)
		size.enlarge()
		#expect(!size.showsWarning)
		#expect(size.width == 320)
	}

	@Test("The next flicker code has the size of the last one, and the warning does not come again")
	func sizeKept() {
		let first = FlickerCodeSize(defaults: defaults)
		first.enlarge()
		first.agree()
		first.enlarge()
		#expect(first.width == 320)

		let next = FlickerCodeSize(defaults: defaults)
		#expect(next.width == 320)
		next.shrink()
		next.shrink()
		next.shrink()
		#expect(next.width == 200)
		next.enlarge()
		#expect(!next.showsWarning)
		#expect(next.width == 240)
		#expect(FlickerCodeSize(defaults: defaults).width == 240)
	}

	@Test("The size stays between 160 and 400")
	func limits() {
		let size = FlickerCodeSize(defaults: defaults)
		for _ in 0..<5 { size.shrink() }
		#expect(size.width == 160)
		#expect(!size.canShrink)
		size.enlarge()
		size.agree()
		for _ in 0..<10 { size.enlarge() }
		#expect(size.width == 400)
		#expect(!size.canEnlarge)
	}
}
