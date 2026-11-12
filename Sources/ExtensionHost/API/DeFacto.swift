import CLua
import Foundation

/// Functions that the API page does not document but that published extensions call: `MM.derdecode`
/// in the signed Coinbase extension and `MM.base64urldecode` in an extension that checks for it first.
enum DeFacto {
	static let functions: [(String, clua_Function)] = [("derdecode", derdecode), ("base64urldecode", base64urldecode)]

	/// `MM.derdecode(der)` returns the elements at the top level of DER data, each as `{tag, content}`
	/// with the tag byte as a number. A script reads a nested element with another call on its content.
	private static let derdecode: clua_Function = { L in
		let stack = LuaStack(L!)
		let elements = stack.data(at: 1).flatMap(DER.elements)
		return stack.returning(elements.map { .array($0.map { .array([.integer(Int64($0.tag)), .bytes($0.content)]) }) })
	}

	private static let base64urldecode: clua_Function = { L in
		let stack = LuaStack(L!)
		return stack.returning(stack.text(at: 1).flatMap(MMLibrary.base64Decoded))
	}
}
