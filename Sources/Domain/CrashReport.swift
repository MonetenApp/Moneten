import Foundation

public struct CrashDiagnostic: Codable, Equatable, Sendable {
	public let appVersion: String
	public let macOSVersion: String
	public let exceptionType: Int?
	public let signal: Int?
	public let frames: [Frame]

	public struct Frame: Codable, Equatable, Sendable {
		public let binaryName: String
		public let binaryUUID: String
		public let offset: UInt64

		public init(binaryName: String, binaryUUID: String, offset: UInt64) {
			self.binaryName = binaryName
			self.binaryUUID = binaryUUID
			self.offset = offset
		}
	}

	public init(appVersion: String, macOSVersion: String, exceptionType: Int?, signal: Int?, frames: [Frame]) {
		self.appVersion = appVersion
		self.macOSVersion = macOSVersion
		self.exceptionType = exceptionType
		self.signal = signal
		self.frames = frames
	}

	public static func crashedFrames(in data: Data) throws -> [Frame] {
		let tree = try JSONDecoder().decode(StackEnvelope.self, from: data).callStackTree
		var pending = Array((tree.callStacks.first { $0.threadAttributed == true }?.callStackRootFrames ?? []).reversed())
		var frames: [Frame] = []
		while let frame = pending.popLast() {
			if let offset = frame.offsetIntoBinaryTextSegment {
				frames.append(.init(binaryName: frame.binaryName ?? "", binaryUUID: frame.binaryUUID ?? "", offset: offset))
			}
			pending.append(contentsOf: (frame.subFrames ?? []).reversed())
		}
		return frames
	}
}

private struct StackEnvelope: Decodable {
	let callStackTree: StackTree
}

private struct StackTree: Decodable {
	let callStacks: [Thread]
	struct Thread: Decodable {
		let threadAttributed: Bool?
		let callStackRootFrames: [Frame]
	}
	struct Frame: Decodable {
		let binaryName: String?
		let binaryUUID: String?
		let offsetIntoBinaryTextSegment: UInt64?
		let subFrames: [Frame]?
	}
}

public func crashReport(_ diagnostic: CrashDiagnostic, crashTime: Date? = nil) -> String {
	if let crashTime {
		return ["Moneten crash report", "App version: \(reportVersion(diagnostic.appVersion))", "macOS: \(reportMacOS(diagnostic.macOSVersion))",
			"Crash time: \(crashTime.formatted(.iso8601))", "No details were available."].joined(separator: "\n")
	}
	// Binary names are diagnostic text too. A character filter would still admit an IBAN or a name.
	let binaries: Set<String> = ["Moneten", "Moneten.debug.dylib", "SwiftUI", "SwiftUICore", "AppKit", "Foundation", "CoreFoundation",
		"AttributeGraph", "libswiftCore.dylib", "libsystem_kernel.dylib", "libsystem_c.dylib", "libsystem_pthread.dylib",
		"libdispatch.dylib", "libobjc.A.dylib", "dyld"]
	let header = ["Moneten crash report", "App version: \(reportVersion(diagnostic.appVersion))", "macOS: \(reportMacOS(diagnostic.macOSVersion))",
		"Exception type: \(diagnostic.exceptionType.map(String.init) ?? "Unknown")", "Signal: \(diagnostic.signal.map(String.init) ?? "Unknown")", "Crashed thread:"]
	let frames = diagnostic.frames.map { frame in
		let name = binaries.contains(frame.binaryName) ? frame.binaryName : "Other"
		let uuid = UUID(uuidString: frame.binaryUUID)?.uuidString ?? "Unknown"
		return "Frame: \(name) \(uuid) 0x\(String(frame.offset, radix: 16))"
	}
	return (header + frames).joined(separator: "\n")
}

public func bugReportURL(version: String, macOS: String, report: String? = nil) -> URL {
	func url(_ body: String?) -> URL {
		var components = URLComponents(string: "https://github.com/MonetenApp/Moneten/issues/new")!
		var fields = [URLQueryItem(name: "template", value: "bug-report.yml"),
			URLQueryItem(name: "version", value: reportVersion(version)), URLQueryItem(name: "macos", value: reportMacOS(macOS))]
		if let body {
			fields += [URLQueryItem(name: "body", value: body), URLQueryItem(name: "expected", value: body)]
		}
		components.queryItems = fields
		return components.url!
	}
	let full = url(report)
	guard let report, full.absoluteString.count >= 8_000 else { return full }
	let notice = "Report shortened for GitHub. Use Copy Report for the full text."
	let lines = report.components(separatedBy: "\n")
	var kept = Array(lines.prefix { !$0.hasPrefix("Frame:") })
	var shortened = url((kept + [notice]).joined(separator: "\n"))
	for frame in lines.dropFirst(kept.count) {
		let candidate = url((kept + [frame, notice]).joined(separator: "\n"))
		if candidate.absoluteString.count >= 8_000 { break }
		kept.append(frame)
		shortened = candidate
	}
	return shortened
}

private func reportVersion(_ value: String) -> String {
	value.range(of: #"\A[0-9]{1,4}(\.[0-9]{1,4}){0,3}(-(alpha|beta|rc)\.[0-9]{1,4})?\z"#, options: .regularExpression) == nil ? "Unknown" : value
}

private func reportMacOS(_ value: String) -> String {
	let pattern = #"\A(?:(?:macOS |Mac OS X )?(?:Version )?)?([0-9]{1,4}(\.[0-9]{1,4}){0,2})(?: \((?:Build )?[0-9]{1,2}[A-Z][0-9]{1,6}[a-z]?\))?\z"#
	let expression = try! NSRegularExpression(pattern: pattern)
	guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
		let range = Range(match.range(at: 1), in: value) else { return "Unknown" }
	return String(value[range])
}

public enum CrashReports {
	public static func macOSVersion(_ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> String {
		"\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}
}
