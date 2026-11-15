import Foundation
import Testing
@testable import Domain

@Suite("Private crash reports")
struct CrashReportTests {
	let binaryUUID = "70B89F27-1634-3580-A695-57CDB41D7743"

	@Test("Every diagnostic text field rejects personal data")
	func personalData() {
		let personal = "DE02120300000000202051 Erika Mustermann /Users/erika"
		let diagnostic = CrashDiagnostic(appVersion: personal, macOSVersion: personal, exceptionType: 1, signal: 11,
			frames: [.init(binaryName: personal, binaryUUID: personal, offset: 42)])
		let report = crashReport(diagnostic)
		for text in ["DE02120300000000202051", "Erika Mustermann", "/Users/erika"] {
			#expect(!report.contains(text))
		}
		#expect(report == "Moneten crash report\nApp version: Unknown\nmacOS: Unknown\nException type: 1\nSignal: 11\nCrashed thread:\nFrame: Other Unknown 0x2a")
	}

	@Test("Report holds versions, codes and whole crashed frames")
	func reportText() {
		let diagnostic = CrashDiagnostic(appVersion: "0.1.0", macOSVersion: "Version 15.2 (Build 24C101)", exceptionType: 6, signal: 6,
			frames: [.init(binaryName: "Moneten", binaryUUID: binaryUUID, offset: 4096)])
		#expect(crashReport(diagnostic) == "Moneten crash report\nApp version: 0.1.0\nmacOS: 15.2\nException type: 6\nSignal: 6\nCrashed thread:\nFrame: Moneten 70B89F27-1634-3580-A695-57CDB41D7743 0x1000")
	}

	@Test("Private-looking strings are rejected, even without spaces")
	func strictFields() {
		for value in ["DE02120300000000202051", "Erika", "/Users/erika", "0.1.0\nErika", "0.1.0-DE02120300000000202051"] {
			let report = crashReport(.init(appVersion: value, macOSVersion: value, exceptionType: nil, signal: nil,
				frames: [.init(binaryName: value, binaryUUID: value, offset: 0)]))
			#expect(!report.contains(value))
		}
	}

	@Test("Known macOS version formats retain only the numeric version")
	func macOSFormats() {
		for version in ["15.2", "Version 15.2 (Build 24C101)", "macOS 15.2 (24C101)", "Mac OS X 15.2 (24C101)"] {
			let report = crashReport(.init(appVersion: "0.1.0", macOSVersion: version, exceptionType: nil, signal: nil, frames: []))
			#expect(report.contains("macOS: 15.2\n"))
		}
	}

	@Test("Only the crashed thread is selected, including nested frames")
	func crashedThread() throws {
		let data = Data("""
		{"callStackTree":{"callStacks":[
		 {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"Erika Mustermann","binaryUUID":"\(binaryUUID)","offsetIntoBinaryTextSegment":1}]},
		 {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"Moneten","binaryUUID":"\(binaryUUID)","offsetIntoBinaryTextSegment":4096,
		 "subFrames":[{"binaryName":"SwiftUI","binaryUUID":"\(binaryUUID)","offsetIntoBinaryTextSegment":42}]}]}]}}
		""".utf8)
		#expect(try CrashDiagnostic.crashedFrames(in: data) == [
			.init(binaryName: "Moneten", binaryUUID: binaryUUID, offset: 4096),
			.init(binaryName: "SwiftUI", binaryUUID: binaryUUID, offset: 42),
		])
		#expect(try CrashDiagnostic.crashedFrames(in: Data("{\"callStackTree\":{\"callStacks\":[]}}".utf8)).isEmpty)
		#expect(throws: (any Error).self) { try CrashDiagnostic.crashedFrames(in: Data("{}".utf8)) }
	}

	@Test("Help and crash URLs fill the issue form ids")
	func prefilledForm() throws {
		let help = bugReportURL(version: "0.1.0", macOS: "15.2")
		let parts = try #require(URLComponents(url: help, resolvingAgainstBaseURL: false))
		#expect(parts.host == "github.com")
		#expect(parts.path == "/MonetenApp/Moneten/issues/new")
		let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
		#expect(query == ["template": "bug-report.yml", "version": "0.1.0", "macos": "15.2"])
		let report = crashReport(.init(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6, frames: []))
		let crash = bugReportURL(version: "0.1.0", macOS: "15.2", report: report)
		let fields = URLComponents(url: crash, resolvingAgainstBaseURL: false)!.queryItems!
		#expect(fields.first { $0.name == "body" }?.value == report)
		#expect(fields.first { $0.name == "expected" }?.value == report)
	}

	@Test("A long URL stops at a whole frame and retains the full copy text")
	func boundedURL() throws {
		let report = crashReport(.init(appVersion: "0.1.0", macOSVersion: "15.2", exceptionType: 6, signal: 6,
			frames: (0..<500).map { .init(binaryName: "Moneten", binaryUUID: binaryUUID, offset: UInt64($0)) }))
		let url = bugReportURL(version: "0.1.0", macOS: "15.2", report: report)
		#expect(url.absoluteString.count < 8_000)
		let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value)
		let lines = body.components(separatedBy: "\n")
		#expect(lines.last == "Report shortened for GitHub. Use Copy Report for the full text.")
		let frame = try #require(lines.dropLast().last)
		#expect(report.components(separatedBy: "\n").contains(frame))
		#expect(frame.hasPrefix("Frame: Moneten \(binaryUUID) 0x"))
		#expect(report.components(separatedBy: "\n").filter { $0.hasPrefix("Frame:") }.count == 500)
		#expect(!report.contains("shortened"))
	}
}
