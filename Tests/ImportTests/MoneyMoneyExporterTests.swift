import AppKit
import CoreServices
import Foundation
import Synchronization
import Testing
@testable import Import

/// The suite launches a real app process, so its tests run one after another.
@Suite("Migration source lifecycle", .serialized)
struct MoneyMoneyExporterTests {
	@Test("Export addresses a renamed running source by PID and never sends after it quits")
	func lifecycle() async throws {
		let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let folder = root.appending(path: ".build/source-lifecycle-\(UUID())")
		let app = folder.appending(path: "Renamed Source.app")
		let executable = app.appending(path: "Contents/MacOS/Source")
		try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let identifier = "io.github.moneten.synthetic-source.\(UUID().uuidString.lowercased())"
		let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Source", "CFBundlePackageType": "APPL", "LSUIElement": true]
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
		let source = folder.appending(path: "Source.swift")
		try """
			import AppKit
			let app = NSApplication.shared
			app.setActivationPolicy(.prohibited)
			app.run()
			""".write(to: source, atomically: true, encoding: .utf8)
		let compiler = Process()
		compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
		compiler.arguments = ["swiftc", source.path, "-o", executable.path]
		try compiler.run()
		compiler.waitUntilExit()
		#expect(compiler.terminationStatus == 0)
		let calls = Mutex<[UInt32]>([])
		let replyText = "<?xml version=\"1.0\"?><plist version=\"1.0\"><array/></plist>"
		let send: @Sendable (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = { event in
			calls.withLock { $0.append(event.eventID) }
			let reply = NSAppleEventDescriptor.record()
			reply.setParam(NSAppleEventDescriptor(string: replyText), forKeyword: keyDirectObject)
			return reply
		}
		// On a loaded Mac, Launch Services leaves a running app out of about one lookup in a thousand, for a few
		// milliseconds. The exporter then fails with notRunning before it sends. An export that must reach the
		// running source tries again only after such a miss, so the test still fails if the source is never found.
		func exportReachingSource(_ command: MoneyMoneyExporter.Command,
			send: @escaping @Sendable (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor) async throws -> Data {
			let deadline = ContinuousClock.now + .seconds(60)
			while true {
				let sent = Atomic(false)
				do {
					return try await MoneyMoneyExporter.run(command, bundleIdentifier: identifier, applicationURL: app) { event in
						sent.store(true, ordering: .sequentiallyConsistent)
						return try send(event)
					}
				} catch MoneyMoneyExporter.Failure.notRunning where !sent.load(ordering: .sequentiallyConsistent) && .now < deadline {
					try await Task.sleep(for: .milliseconds(20))
				}
			}
		}
		do {
			_ = try await MoneyMoneyExporter.run(.accounts, bundleIdentifier: identifier, applicationURL: app, send: send)
			Issue.record("A stopped source exported accounts")
		} catch {
			#expect(error as? MoneyMoneyExporter.Failure == .notRunning)
		}
		#expect(calls.withLock { $0.isEmpty })
		let process = Process()
		process.executableURL = executable
		try process.run()
		defer {
			if process.isRunning { process.terminate(); process.waitUntilExit() }
		}
		let pid = process.processIdentifier
		let running = try #require(await eventually {
			NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { $0.processIdentifier == pid }
		})
		for command in [MoneyMoneyExporter.Command.accounts, .categories, .transactions] {
			let data = try await exportReachingSource(command) { event in
				#expect(event.eventClass == 0x4d4f4e59)
				#expect(event.attributeDescriptor(forKeyword: keyAddressAttr)?.descriptorType == typeKernelProcessID)
				#expect(event.attributeDescriptor(forKeyword: keyAddressAttr)?.data == withUnsafeBytes(of: pid) { Data($0) })
				if event.eventID == 0x65787074 {
					#expect(event.paramDescriptor(forKeyword: 0x66726474)?.stringValue == "1990-01-01")
					#expect(event.paramDescriptor(forKeyword: 0x66726d74)?.stringValue == "plist")
				}
				return try send(event)
			}
			#expect(String(decoding: data, as: UTF8.self) == replyText)
		}
		#expect(calls.withLock { $0 } == [0x65787061, 0x65787063, 0x65787074])
		do {
			_ = try await exportReachingSource(.accounts) { _ in
				let reply = NSAppleEventDescriptor.record()
				reply.setParam(NSAppleEventDescriptor(int32: -1743), forKeyword: 0x6572726e)
				return reply
			}
			Issue.record("An export error was ignored")
		} catch {
			#expect(error as? MoneyMoneyExporter.Failure == .notAllowed)
		}
		do {
			_ = try await exportReachingSource(.accounts) { event in
				process.terminate()
				process.waitUntilExit()
				return try event.sendEvent(options: .waitForReply, timeout: 2)
			}
			Issue.record("An export succeeded after the target quit before delivery")
		} catch {
			#expect(error as? MoneyMoneyExporter.Failure == .notRunning)
		}
		#expect(!process.isRunning)
		// Wait until AppKit marks the instance found at launch as ended, so the next lookup reflects the quit.
		#expect(try await eventually { running.isTerminated ? true : nil } == true)
		do {
			_ = try await MoneyMoneyExporter.run(.accounts, bundleIdentifier: identifier, applicationURL: app, send: send)
			Issue.record("The source was exported after it quit")
		} catch {
			#expect(error as? MoneyMoneyExporter.Failure == .notRunning)
		}
		#expect(calls.withLock { $0 } == [0x65787061, 0x65787063, 0x65787074])
		#expect(NSRunningApplication.runningApplications(withBundleIdentifier: identifier).allSatisfy { $0.isTerminated })
	}
}

/// Returns the first value that `probe` finds, or nil when a deadline that holds on a loaded Mac passes first.
/// The probe runs on the main actor because AppKit refreshes an `NSRunningApplication` only on the main thread.
private func eventually<Value: Sendable>(_ probe: @MainActor () -> Value?) async throws -> Value? {
	let deadline = ContinuousClock.now + .seconds(60)
	while true {
		if let value = await probe() { return value }
		guard .now < deadline else { return nil }
		try await Task.sleep(for: .milliseconds(20))
	}
}
