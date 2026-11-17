import Foundation

/// The processor time that the regex calls of one search, or of one run of a rule, share. A search stops after 300 ms
/// in all. A rule carries what it spent before into `spent`, so its limit holds for the whole run.
final class RegexBudget {
	let limit: UInt64
	var spent: UInt64
	var gaveUp = false

	init(limit: UInt64 = 300_000_000, spent: UInt64 = 0) {
		self.limit = limit
		self.spent = spent
	}

	func check(_ elapsed: UInt64) {
		if spent + elapsed >= limit { gaveUp = true }
	}
}

/// Stops a regex call after `callLimit`, about 100 ms of processor time, because ICU never finishes some patterns, such
/// as `^+?49`. Counts only the calling thread's processor time inside regex calls. Scheduling delays on a busy Mac must
/// not discard a normal search or rule. The search and the rules share it. A virtual machine still charges a pause of
/// its host to the call, so a rule checks a slow call once more with `Rule.counted`.
final class RegexWatch {
	let budget: RegexBudget
	/// The processor time after which one call stops.
	let callLimit: UInt64
	/// The number of progress reports of ICU between two looks at the clock, because a look costs about as much as a
	/// short call.
	let interval: Int
	private(set) var gaveUp = false

	init(budget: RegexBudget = RegexBudget(), callLimit: UInt64 = 100_000_000, interval: Int = 256) {
		self.budget = budget
		self.callLimit = callLimit
		self.interval = interval
	}

	func firstMatch(_ regex: NSRegularExpression, _ text: String) -> NSRange? {
		if gaveUp || budget.gaveUp { return nil }
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		var found: NSRange?
		var reports = 0
		regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(text.startIndex..., in: text)) { result, _, stop in
			if let result {
				found = result.range
				stop.pointee = true
				return
			}
			reports += 1
			guard reports % interval == 0 else { return }
			let elapsed = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
			budget.check(elapsed)
			if elapsed >= callLimit { gaveUp = true }
			if gaveUp || budget.gaveUp { stop.pointee = true }
		}
		budget.spent += clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
		budget.check(0)
		return gaveUp || budget.gaveUp ? nil : found
	}
}
