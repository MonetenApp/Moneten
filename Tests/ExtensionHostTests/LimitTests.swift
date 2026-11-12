import Domain
@testable import ExtensionHost
import Foundation
import CLua
import Testing

/// Limits that hold inside the process of the tests, where the memory of the process can be measured.
/// They run one after the other, so that one test's memory does not count for another.
@Suite(.serialized) struct LimitTests {
	/// Answers every request with a new body of 8 MB and a header of `header` bytes, which Swift pushes
	/// after the body.
	struct LargeBodies: Transport {
		var header = 0

		func send(_ request: HTTPRequest) throws -> HTTPResponse {
			HTTPResponse(status: 200, headers: header > 0 ? ["X-Padding": String(repeating: "p", count: header)] : [:], body: Data(repeating: 0x41, count: 8 * 1_048_576))
		}
	}

	static func footprint() -> Int {
		var info = task_vm_info_data_t()
		var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
		let status = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
		}
		return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
	}

	/// A body that a request pushes into a full Lua state fails the request as a memory error, and the
	/// memory of the host process does not grow with each try.
	@Test func requestIntoAFullStateIsAMemoryError() {
		let package = demo("""
			WebBanking{version = 1}
			function Fill()
				local c = Connection()
				hog = {}
				while pcall(function() hog[#hog + 1] = string.rep("x", 1048000) .. #hog end) do end
				local failures = {}
				for i = 1, 40 do
					local ok, message = pcall(c.request, c, "GET", "https://api.bank.example/statement")
					if not ok then failures[message] = (failures[message] or 0) + 1 end
				end
				hog = nil
				return failures
			end
			""", hosts: ["api.bank.example"])
		let session = HostSession(package: package, transport: LargeBodies(), memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let before = Self.footprint()
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function("Fill")) }
		let growth = Self.footprint() - before
		#expect(result == .success(.object(["not enough memory": .integer(40)])))
		#expect(growth < 160 * 1_048_576, "the footprint grew by \(growth / 1_048_576) MB")
	}

	/// A finalizer that fills the memory runs while a request pushes its body. No memory error may
	/// skip the end of the Swift function, so the state is back at one level of Swift afterwards.
	@Test func finalizersDoNotLeaveTheHeadroomOn() {
		let package = demo("""
			WebBanking{version = 1}
			function Stress()
				-- Fills the memory to the last bytes and keeps it: large blocks first, then small tables.
				local mt = {__gc = function()
					junk = {}
					pcall(function() while true do junk[#junk + 1] = string.rep("y", 1048000) .. #junk end end)
					pcall(function() while true do junk.tail = {junk.tail} end end)
				end}
				local c = Connection()
				for i = 1, 40 do
					junk = nil
					setmetatable({}, mt)
					pcall(c.request, c, "GET", "https://api.bank.example/statement")
				end
				junk = nil
				return "done"
			end
			""", hosts: ["api.bank.example"])
		let session = HostSession(package: package, transport: LargeBodies(header: 1_048_576), memory: 32 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call("Stress") }
		#expect(result == .success(.string("done")))
		#expect(clua_nativedepth(session.lua.stack.L) == 1)
	}

	/// Objects that only Swift functions allocate, each with a finalizer, become garbage as fast as
	/// they come. The collector keeps up, so the loop never reaches the limit of the state.
	@Test func garbageOfSwiftFunctionsIsCollected() {
		let package = demo("""
			WebBanking{version = 1}
			function Churn()
				local mt = {__gc = function() end}
				for i = 1, 1000000 do setmetatable(Connection(), mt) end
				return "done"
			end
			""")
		let session = HostSession(package: package, transport: LargeBodies(), memory: 32 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call("Churn") }
		#expect(result == .success(.string("done")))
	}

	@Test func requestReportsItsStartAndEnd() throws {
		let reports = Reports()
		let transport = ReportingTransport(LargeBodies()) { reports.count += 1 }
		_ = try transport.send(HTTPRequest(method: "GET", url: URL(string: "https://api.bank.example/")!))
		#expect(reports.count == 2)
	}

	final class Reports: @unchecked Sendable {
		var count = 0
	}
}
