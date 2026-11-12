import CLua
import Foundation

/// The table `MM` of the Web Banking API.
enum MMLibrary {
	static func install(_ stack: LuaStack, environment: HostEnvironment) {
		lua_createtable(stack.L, 0, 0)
		Environment.reportMisses(stack, of: "MM")
		stack.setGlobal("MM")
	}
}
