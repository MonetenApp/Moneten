import Domain
@testable import ExtensionHost
import Foundation
import CLua
import Synchronization
import Testing

/// Limits that hold inside the process of the tests, where the memory of each request can be followed.
/// They run one after the other.
@Suite(.serialized) struct LimitTests {
	/// Answers every request with a new body of 8 MB and a header of `header` bytes, which Swift pushes
	/// after the body, and counts the bodies that were freed.
	final class LargeBodies: Transport, Sendable {
		let header: Int
		let freed = Mutex(0)

		init(header: Int = 0) {
			self.header = header
		}

		func send(_ request: HTTPRequest) throws -> HTTPResponse {
			let count = 8 * 1_048_576
			let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
			bytes.initializeMemory(as: UInt8.self, repeating: 0x41, count: count)
			let body = Data(bytesNoCopy: bytes, count: count, deallocator: .custom { [self] pointer, _ in
				pointer.deallocate()
				freed.withLock { $0 += 1 }
			})
			return HTTPResponse(status: 200, headers: header > 0 ? ["X-Padding": String(repeating: "p", count: header)] : [:], body: body)
		}
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
		let bodies = LargeBodies()
		let session = HostSession(package: package, transport: bodies, memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function("Fill")) }
		#expect(result == .success(.object(["not enough memory": .integer(40)])))
		// A memory error that jumps over the Swift frames of a request leaks its body. The footprint of
		// the process would show it too, but the other tests of the process change the footprint.
		#expect(bodies.freed.withLock { $0 } == 40)
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
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function("Stress")) }
		#expect(result == .success(.string("done")))
		#expect(clua_nativedepth(session.lua.stack.L) == 1)
	}

	/// Objects that only Swift functions allocate, each with a finalizer, become garbage as fast as
	/// they come. The collector keeps up, so the loop never reaches the limit of the state.
	@Test func garbageOfSwiftFunctionsIsCollected() {
		let package = demo("""
			WebBanking{version = 1}
			function Churn()
				-- A JSON object of the API is a userdata whose finalizer Swift registers. A Connection
				-- protects its metatable, so the script cannot give it one.
				for i = 1, 1000000 do JSON("{}") end
				return "done"
			end
			""")
		let session = HostSession(package: package, transport: LargeBodies(), memory: 32 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function("Churn")) }
		#expect(result == .success(.string("done")))
	}

	/// A result of the API that a function pushes into a full Lua state fails the call as a memory
	/// error, which the script can catch, and the state is back at one level of Swift afterwards.
	@Test(arguments: [#"JSON(json):dictionary()"#, #"HTML(page):xpath("//p"):text()"#, #"MM.base64(big)"#])
	func resultIntoAFullStateIsAMemoryError(call: String) {
		let package = demo("""
			WebBanking{version = 1}
			big = string.rep("y", 4 * 1048576)
			json = '{"text": "' .. big .. '"}'
			page = "<p>" .. big .. "</p>"
			function Fill()
				-- Fills the state of 64 MB until less than 2 MB is free: enough for the Lua side of a call,
				-- too little for a result of 4 MB that Swift pushes.
				hog = {}
				collectgarbage()
				while collectgarbage("count") < 64 * 1024 - 2048 do
					hog[#hog + 1] = string.rep("x", 65536) .. #hog
					collectgarbage()
				end
				local failures = {}
				for i = 1, 10 do
					local ok, message = pcall(function() return \(call) end)
					if not ok then failures[message] = (failures[message] or 0) + 1 end
				end
				hog = nil
				return failures
			end
			""")
		let session = HostSession(package: package, transport: LargeBodies(), memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		let result = Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function("Fill")) }
		#expect(result == .success(.object(["not enough memory": .integer(10)])))
		#expect(clua_nativedepth(session.lua.stack.L) == 1)
	}

	/// The bytes that an object of the API holds outside the state, the copy of a JSON or PDF document or
	/// the tree of an HTML document, count against the memory of the session. Objects that the script
	/// keeps reach the limit, and objects that it drops do not.
	@Test(arguments: [#"JSON(big)"#, #"PDF(big)"#, #"HTML(page)"#])
	func memoryOfObjectsCountsAgainstTheLimit(create: String) {
		let package = demo("""
			WebBanking{version = 1}
			big = string.rep("x", 4 * 1048576)
			page = "<p>" .. big .. "</p>"
			function Hold()
				local held = {}
				for i = 1, 100 do
					local ok, message = pcall(function() held[#held + 1] = \(create) end)
					if not ok then return message end
				end
				return #held
			end
			function Drop()
				for i = 1, 100 do local object = \(create) end
				return "done"
			end
			""")
		let hold = HostSession(package: package, transport: LargeBodies(), memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		#expect(Result { () throws(ScriptError) -> LuaValue in _ = try hold.load(); return try hold.call(.function("Hold")) } == .success(.string("not enough memory")))
		let drop = HostSession(package: package, transport: LargeBodies(), memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		#expect(Result { () throws(ScriptError) -> LuaValue in _ = try drop.load(); return try drop.call(.function("Drop")) } == .success(.string("done")))
	}

	/// An element list keeps the tree of its document, so the tree stays charged after the document is
	/// collected, and each change of the tree adds to the charge.
	@Test(arguments: ["Lists", "Grow"])
	func treeOfAnHTMLDocumentStaysCharged(function: String) {
		let package = demo("""
			WebBanking{version = 1}
			big = string.rep("x", 4 * 1048576)
			page = "<p>" .. big .. "</p>"
			function Lists()
				local held = {}
				for i = 1, 100 do
					local ok, message = pcall(function() held[#held + 1] = HTML(page):xpath("//p") end)
					collectgarbage()
					if not ok then return message end
				end
				return #held
			end
			function Grow()
				local list = HTML("<p>a</p>"):xpath("//p")
				for i = 1, 100 do
					local ok, message = pcall(function() list:attr("data" .. i, big) end)
					if not ok then return (message:gsub("^Demo%.lua:%d+: ", "")) end
				end
				return 100
			end
			""")
		let session = HostSession(package: package, transport: LargeBodies(), memory: 64 * 1_048_576, ask: { _ in .denied }, log: { _ in })
		#expect(Result { () throws(ScriptError) -> LuaValue in _ = try session.load(); return try session.call(.function(function)) } == .success(.string("not enough memory")))
	}

	/// An error of a Swift function that quotes data of the script, such as a URL of 1 MB, keeps 1,000
	/// bytes of it, so that the error needs little memory.
	@Test(arguments: [
		#"Connection():request("GET", string.rep("x", 1048576))"#,
		#"Connection():request("GET", "https://" .. string.rep("x", 1048576) .. ".example/")"#,
		#"Connection():request("GET", "https://api.bank.example/", nil, nil, {["proxy-" .. string.rep("x", 1048576)] = "1"})"#,
		#"HTML("<p></p>"):xpath(string.rep("(", 1048576))"#,
	])
	func scriptDataIsClippedInErrors(call: String) {
		let run = Run(demo("""
			WebBanking{version = 1}
			function Huge()
				local ok, message = pcall(function() return \(call) end)
				return #(message:gsub("^Demo%.lua:%d+: ", ""))
			end
			""", hosts: ["api.bank.example"]))
		#expect(run.call("Huge") == .integer(Int64(LuaStack.maxMessage + "…".utf8.count)))
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
