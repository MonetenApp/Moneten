// Probes for scripts/check-time-limits.py, run by scripts/test-check-time-limits.py. The check must report each line
// that ends with "probe: raw" and no other line. This file is not part of any target.

// Raw upper limits, in either direction, with a duration or a time on either side.
#expect(elapsed < .milliseconds(5)) // probe: raw
#expect(.milliseconds(5) > elapsed) // probe: raw
#expect(times[3] <= .milliseconds(50)) // probe: raw
#expect(.seconds(1) >= clock.now - start) // probe: raw
#expect(Duration.seconds(1) > ContinuousClock.now - start) // probe: raw
#expect(milliseconds < 5) // probe: raw
#expect(5 > milliseconds) // probe: raw
#expect(elapsed / .milliseconds(1) < 5) // probe: raw
#expect(5 >= elapsed / .milliseconds(1)) // probe: raw
#expect((clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000 < 1_000) // probe: raw
#expect(try #require(secondsToTermination(since: start)) < 30) // probe: raw
#expect(at - started.timeIntervalSince1970 < 10) // probe: raw
#expect(slept < 2) // probe: raw
try #require(elapsed < .seconds(1)) // probe: raw
try #require(.seconds(1) > elapsed, "too slow") // probe: raw
try #require(elapsed / .milliseconds(1) < 5) // probe: raw
#expect(rows.isEmpty && merge < .milliseconds(300)) // probe: raw
let fast = elapsed < .milliseconds(5) // probe: raw
#expect(elapsed < .seconds(1) + .milliseconds(500)) // probe: raw

// Limits through budget(_:), and limits that say why they keep their value.
#expect(elapsed < budget(.milliseconds(5))) // probe: pass
#expect(budget(.milliseconds(5)) > elapsed) // probe: pass
#expect(.nanoseconds(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) < budget(.milliseconds(1_000))) // probe: pass
try #require(times[18] <= budget(.milliseconds(300))) // probe: pass
#expect(ContinuousClock.now - canceled < .seconds(grace)) // time-ok: the grace holds 120 s (probe: pass)

// Waits on a deadline, lower bounds, relative limits, and comparisons that are not about time.
let deadline = ContinuousClock.now + .seconds(10) // probe: pass
while ContinuousClock.now < deadline { // probe: pass
try #require(ContinuousClock.now < deadline, "The writer did not reach file sync") // probe: pass
while !done, ContinuousClock.now - start < limit { // probe: pass
#expect(elapsed >= .milliseconds(300)) // probe: pass
#expect(.seconds(5) <= ContinuousClock.now - canceled) // probe: pass
#expect(spent < spentAlone * 1.5) // probe: pass
#expect(rows.count < 10) // probe: pass
#expect(times.count == runs.count) // probe: pass
try await Task.sleep(for: .milliseconds(100)) // probe: pass
func slowest<T: Comparable>(_ values: [T]) -> T? { values.max() } // probe: pass
let text = "elapsed < .seconds(1)" // probe: pass
// #expect(elapsed < .seconds(1)) probe: pass
let script = """
	local slept = MM.time() - start
	return slept < 2 and elapsed < 5
	"""
