import CLua
import Foundation

/// The `HTML` object of the Web Banking API.
enum HTMLDocument {
	static func install(_ stack: LuaStack) {}

	/// The HTML text of the document at `index`, or nil when the value is not an `HTML` object.
	static func storedText(_ stack: LuaStack, at index: Int32) -> String? { nil }

	/// Pushes a new `HTML` object parsed from `html`.
	static func push(_ stack: LuaStack, html: String) {
		lua_pushnil(stack.L)
	}
}
