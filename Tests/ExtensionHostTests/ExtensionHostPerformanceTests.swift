@testable import ExtensionHost
import Foundation
import Testing

@Suite("Performance of the extension host", .serialized)
struct ExtensionHostPerformanceTests {
	/// A script of about `lines` lines in the style of a web banking extension: small parsing functions over tables and patterns.
	static func script(lines: Int) -> String {
		var text = "WebBanking{version = 1.00, services = {\"Demo\"}, description = \"Generated\"}\n"
		for i in 0..<(lines / 6) {
			text += """
				function Parsers.parse\(i)(text)
					local fields = {}
					for key, value in string.gmatch(text, "(%w+)=(%w+)") do fields[key] = value .. "\(i)" end
					return {name = fields.name, amount = tonumber(fields.amount) or \(i), booked = fields.date ~= nil}
				end
				Parsers[\(i % 50)] = Parsers.parse\(i)

				"""
		}
		return "Parsers = {}\n" + text
	}

	@Test("Loading a script of 600 and of 8,600 lines takes under 30 ms", arguments: [600, 8_600])
	func load(lines: Int) throws {
		let package = demo(Self.script(lines: lines))
		let clock = ContinuousClock()
		let times = try (0..<5).map { _ in try clock.measure { _ = try Run(package).session.load() } }.sorted()
		print("ext load_ms=\(times[2] / .milliseconds(1)) for \(lines) lines")
		#if !DEBUG
		#expect(times[2] < .milliseconds(30))
		#endif
	}

	@Test("Starting a session in its own process takes under 150 ms at the median and 300 ms at p95")
	func sessionStart() async throws {
		let package = try ExtensionPackage.load(from: fixtures.appending(path: "hello.lua"))
		let clock = ContinuousClock()
		var times: [Duration] = []
		for _ in 0..<20 {
			let started = clock.now
			let client = try await ExtensionHostClient.start(HostSetup(package: package), executable: hostExecutable, ask: { _ in .denied }).client
			times.append(clock.now - started)
			await client.end()
		}
		times.sort()
		print("ext session_start_ms p50=\(times[10] / .milliseconds(1)) p95=\(times[18] / .milliseconds(1))")
		#if !DEBUG
		#expect(times[10] < .milliseconds(150))
		#expect(times[18] < .milliseconds(300))
		#endif
	}
}
