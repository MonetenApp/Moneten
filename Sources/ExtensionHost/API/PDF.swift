import CLua
import Foundation
import PDFKit

/// The `PDF` object of the Web Banking API, for the text of a statement.
enum PDFDocument {
	private static let type = "Moneten.PDF"

	static func install(_ stack: LuaStack) {
		LuaObject.register(stack, type, misses: "pdf:", methods: [("text", text)])
		clua_pushfunction(stack.L, create)
		stack.setGlobal("PDF")
	}

	private static let create: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 1) == LUA_TSTRING else {
			stack.pushMessage("PDF needs the PDF document as a string.")
			return -1
		}
		let document = stack.bytes(at: 1)
		LuaObject.push(stack, LuaObject.Box(document), type, bytes: document.count)
		return 1
	}

	/// The plain text of all pages, as far as the document has text and not only images.
	private static let text: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let pdf: LuaObject.Box<Data> = LuaObject.object(stack, at: 1, type) else {
			stack.pushMessage("pdf:text needs a PDF object. Call it with a colon.")
			return -1
		}
		guard let document = PDFKit.PDFDocument(data: pdf.value) else {
			stack.pushMessage("The PDF document could not be read.")
			return -1
		}
		stack.pushString(document.string ?? "")
		return 1
	}
}
