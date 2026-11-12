import CLua
import Foundation
import libxml2

/// The `HTML` object of the Web Banking API. A document is a table, so that `LocalStorage` can keep
/// it as text; its metatable holds the box of its `HTMLTree`. An element list is a box of an
/// `ElementList`, which retains the tree, so libxml2 frees a tree only after Lua has collected the
/// document and every list of it.
enum HTMLDocument {
	private static let treeType = "Moneten.HTML"
	private static let listType = "Moneten.Elements"

	static func install(_ stack: LuaStack) {
		LuaObject.register(stack, treeType, misses: "html:", methods: [("xpath", xpath), ("html", html)])
		LuaObject.register(stack, listType, misses: "elements:", methods: [
			("length", length), ("get", get), ("reverse", reverse), ("children", children), ("xpath", xpath), ("text", text),
			("attr", attr), ("val", val), ("select", select), ("click", click), ("submit", submit), ("html", elementsHTML),
		], luaMethods: [("each", each)])
		clua_pushfunction(stack.L, create)
		stack.setGlobal("HTML")
	}

	/// The HTML text of the document at `index`, or nil when the value is not an `HTML` object.
	static func storedText(_ stack: LuaStack, at index: Int32) -> String? {
		tree(stack, at: index)?.html(formatted: false)
	}

	/// Pushes a new `HTML` object parsed from `html`.
	static func push(_ stack: LuaStack, html: String) {
		push(stack, HTMLTree(Data(html.utf8), charset: "UTF-8"))
	}

	private static func push(_ stack: LuaStack, _ tree: HTMLTree) {
		let L = stack.L
		lua_createtable(L, 0, 0)
		lua_createtable(L, 1, 2)
		LuaObject.push(stack, tree, treeType)
		lua_getmetatable(L, -1)
		lua_getfield(L, -1, "__index")
		lua_setfield(L, -4, "__index")
		lua_settop(L, -2)
		lua_rawseti(L, -2, 1)
		lua_pushboolean(L, 0)
		lua_setfield(L, -2, "__metatable")
		lua_setmetatable(L, -2)
	}

	private static func tree(_ stack: LuaStack, at index: Int32) -> HTMLTree? {
		guard lua_getmetatable(stack.L, index) != 0 else { return nil }
		defer { lua_settop(stack.L, -3) }
		lua_rawgeti(stack.L, -1, 1)
		return LuaObject.object(stack, at: -1, treeType)
	}

	private static func push(_ stack: LuaStack, _ tree: HTMLTree, _ nodes: [Node]) -> Int32 {
		LuaObject.push(stack, ElementList(tree: tree, nodes: nodes), listType)
		return 1
	}

	/// `HTML(content, charset)`.
	private static let create: clua_Function = { L in
		let stack = LuaStack(L!)
		guard lua_type(L, 1) == LUA_TSTRING else {
			stack.pushMessage("HTML needs the HTML text as a string.")
			return -1
		}
		let content = stack.bytes(at: 1)
		guard content.count < Int32.max else {
			stack.pushMessage("The HTML text is too large.")
			return -1
		}
		let charset = lua_type(L, 2) == LUA_TSTRING ? stack.string(at: 2) : nil
		push(stack, HTMLTree(content, charset: charset?.isEmpty == false ? charset : nil))
		return 1
	}

	/// `html:xpath(query)` from the document, or `elements:xpath(query)` from the first element of the list.
	private static let xpath: clua_Function = { L in
		let stack = LuaStack(L!)
		let context: (tree: HTMLTree, node: Node?)
		if let tree = tree(stack, at: 1) {
			context = (tree, tree.root)
		} else if let list: ElementList = LuaObject.object(stack, at: 1, listType) {
			context = (list.tree, list.nodes.first)
		} else {
			stack.pushMessage("xpath needs an HTML object or an element list. Call it with a colon.")
			return -1
		}
		guard lua_type(L, 2) == LUA_TSTRING else {
			stack.pushMessage("xpath needs an XPath expression.")
			return -1
		}
		let query = stack.string(at: 2)
		guard let node = context.node else { return push(stack, context.tree, []) }
		guard let nodes = context.tree.select(query, from: node) else {
			stack.pushMessage("The XPath expression \(query) is not valid.")
			return -1
		}
		return push(stack, context.tree, nodes)
	}

	private static let html: clua_Function = { L in
		let stack = LuaStack(L!)
		guard let tree = tree(stack, at: 1) else {
			stack.pushMessage("html:html needs an HTML object. Call it with a colon.")
			return -1
		}
		stack.pushString(tree.html(formatted: true))
		return 1
	}

	/// `elements:html()`, which the API page does not document, returns the markup of each element in turn.
	private static let elementsHTML: clua_Function = { L in
		withList(L) { stack, list in
			stack.pushString(list.nodes.map(list.tree.html).joined())
			return 1
		}
	}

	/// Runs `body` with the element list that a method was called on.
	private static func withList(_ L: OpaquePointer?, _ body: (LuaStack, ElementList) -> Int32) -> Int32 {
		let stack = LuaStack(L!)
		guard let list: ElementList = LuaObject.object(stack, at: 1, listType) else {
			stack.pushMessage("This method needs an element list. Call it with a colon.")
			return -1
		}
		return body(stack, list)
	}

	private static let length: clua_Function = { L in
		withList(L) { _, list in
			lua_pushinteger(L, lua_Integer(list.nodes.count))
			return 1
		}
	}

	private static let get: clua_Function = { L in
		withList(L) { stack, list in
			var isInteger: Int32 = 0
			let n = lua_tointegerx(L, 2, &isInteger)
			return push(stack, list.tree, isInteger != 0 && n >= 1 && n <= list.nodes.count ? [list.nodes[Int(n) - 1]] : [])
		}
	}

	private static let reverse: clua_Function = { L in
		withList(L) { stack, list in push(stack, list.tree, list.nodes.reversed()) }
	}

	private static let children: clua_Function = { L in
		withList(L) { stack, list in push(stack, list.tree, list.nodes.flatMap(\.elementChildren)) }
	}

	private static let text: clua_Function = { L in
		withList(L) { stack, list in
			stack.pushString(list.nodes.map(\.text).joined())
			return 1
		}
	}

	/// `attr(name)` reads the attribute of the first element, "" when it lacks it; `attr(name, value)` sets it on all elements.
	private static let attr: clua_Function = { L in
		withList(L) { stack, list in
			guard lua_type(L, 2) == LUA_TSTRING else {
				stack.pushMessage("elements:attr needs the name of an attribute.")
				return -1
			}
			let name = stack.string(at: 2).lowercased()
			if lua_type(L, 3) == LUA_TNONE || lua_type(L, 3) == LUA_TNIL {
				stack.pushString(list.nodes.first?.attribute(name) ?? "")
				return 1
			}
			let value = stack.string(at: 3)
			for node in list.nodes { node.setAttribute(name, value) }
			return 0
		}
	}

	private static let val: clua_Function = { L in
		withList(L) { stack, list in
			stack.push(list.nodes.first.flatMap(Form.value).map(LuaValue.string) ?? .null)
			return 1
		}
	}

	private static let select: clua_Function = { L in
		withList(L) { stack, list in
			if let node = list.nodes.first, lua_type(L, 2) == LUA_TSTRING || lua_type(L, 2) == LUA_TNUMBER {
				Form.choose(stack.string(at: 2), in: node, of: list.tree)
			}
			return 0
		}
	}

	/// `click()` on a link gives "GET" and its URL; on a submit or image button, the request of its form.
	private static let click: clua_Function = { L in
		withList(L) { stack, list in
			guard let node = list.nodes.first else {
				stack.pushMessage("elements:click needs a link or a button, but the list is empty.")
				return -1
			}
			if node.tag == "a", let href = node.attribute("href") {
				stack.pushString("GET")
				stack.pushString(href)
				return 2
			}
			guard case .button(_, submits: true, _) = Field(node), let form = node.ancestor("form") else {
				stack.pushMessage("elements:click needs a link, or a submit or image button in a form.")
				return -1
			}
			return push(stack, Form.request(form, submitter: node, encoding: list.tree.encoding))
		}
	}

	private static let submit: clua_Function = { L in
		withList(L) { stack, list in
			guard let form = list.nodes.first, form.tag == "form" else {
				stack.pushMessage("elements:submit needs a form.")
				return -1
			}
			return push(stack, Form.request(form, submitter: nil, encoding: list.tree.encoding))
		}
	}

	/// Pushes `method, url, postContent, postContentType` in the order of `connection:request`.
	private static func push(_ stack: LuaStack, _ request: Form.Request) -> Int32 {
		stack.pushString(request.method)
		stack.pushString(request.url)
		guard let body = request.body else { return 2 }
		stack.pushBytes(body)
		stack.pushString("application/x-www-form-urlencoded")
		return 4
	}

	/// `elements:each(function (index, element))` is Lua, so that an error or a yield in the function
	/// passes through as in any other Lua call, without a jump over Swift frames.
	private static let each = """
		return function(self, f)
			for i = 1, self:length() do
				if f(i, self:get(i)) == false then return end
			end
		end
		"""
}

fileprivate typealias Node = UnsafeMutablePointer<xmlNode>

/// A parsed document. libxml2 keeps the text in UTF-8, whatever the character set of the source.
private final class HTMLTree {
	private let document: htmlDocPtr

	private static let parser: Void = xmlInitParser()

	/// Without `charset`, libxml2 reads the character set from the `<meta>` tags.
	init(_ content: Data, charset: String?) {
		_ = Self.parser
		let options = Int32(HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue | HTML_PARSE_NONET.rawValue)
		let parsed = content.withUnsafeBytes { htmlReadMemory($0.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(content.count), nil, charset, options) }
		document = parsed ?? htmlNewDocNoDtD(nil, nil)
	}

	/// Attributes that a script removed. An element list may still hold one, so they live as long as the document.
	private var removed: [xmlAttrPtr] = []

	deinit {
		for attribute in removed { xmlFreeProp(attribute) }
		xmlFreeDoc(document)
	}

	/// Takes the attribute out of its element and keeps it until the document goes.
	func remove(_ name: String, from node: Node) {
		guard node.pointee.type == XML_ELEMENT_NODE, let attribute = xmlHasProp(node, name) else { return }
		xmlUnlinkNode(UnsafeMutableRawPointer(attribute).assumingMemoryBound(to: xmlNode.self))
		removed.append(attribute)
	}

	var root: Node {
		UnsafeMutableRawPointer(document).assumingMemoryBound(to: xmlNode.self)
	}

	/// The character set that the document was read in, in which a browser sends its forms.
	var encoding: String.Encoding {
		let name = document.pointee.encoding.map { String(cString: $0) } ?? "UTF-8"
		let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
		return encoding == kCFStringEncodingInvalidId ? .utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
	}

	/// The nodes that `query` selects from `node`, or nil when the expression is not valid.
	func select(_ query: String, from node: Node) -> [Node]? {
		guard let context = xmlXPathNewContext(document) else { return nil }
		defer { xmlXPathFreeContext(context) }
		// Without a handler of its own, libxml2 writes the error to stderr.
		context.pointee.error = { _, _ in }
		context.pointee.node = node
		guard let result = xmlXPathEvalExpression(query, context) else { return nil }
		defer { xmlXPathFreeObject(result) }
		guard let set = result.pointee.nodesetval, set.pointee.nodeNr > 0 else { return [] }
		// A namespace node is a copy that dies with the result, so the list leaves it out.
		return (0..<Int(set.pointee.nodeNr)).compactMap { set.pointee.nodeTab[$0] }.filter { $0.pointee.type != XML_NAMESPACE_DECL }
	}

	/// The document as HTML in UTF-8. `LocalStorage` keeps it unformatted, so that the text nodes stay as they are.
	func html(formatted: Bool) -> String {
		written { htmlDocContentDumpFormatOutput($0, document, nil, formatted ? 1 : 0) }
	}

	/// The markup of `node` and its descendants as the document holds it, unformatted.
	func html(of node: Node) -> String {
		written { htmlNodeDumpFormatOutput($0, document, node, nil, 0) }
	}

	private func written(_ write: (xmlOutputBufferPtr) -> Void) -> String {
		guard let buffer = xmlAllocOutputBuffer(nil) else { return "" }
		write(buffer)
		xmlOutputBufferFlush(buffer)
		let text = xmlOutputBufferGetContent(buffer).map { String(cString: $0) } ?? ""
		xmlOutputBufferClose(buffer)
		return text
	}
}

/// The result of `xpath`: nodes of one tree, which the list keeps alive.
private final class ElementList {
	let tree: HTMLTree
	let nodes: [Node]

	init(tree: HTMLTree, nodes: [Node]) {
		self.tree = tree
		self.nodes = nodes
	}
}

private extension UnsafeMutablePointer where Pointee == xmlNode {
	/// The lower-case name of an element, or "" for any other node.
	var tag: String {
		pointee.type == XML_ELEMENT_NODE ? String(cString: pointee.name) : ""
	}

	/// Only an element has attributes. An attribute node in a list has a shorter struct than an element.
	func attribute(_ name: String) -> String? {
		guard pointee.type == XML_ELEMENT_NODE else { return nil }
		return xmlHasProp(self, name).map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: xmlNode.self).text }
	}

	func has(_ name: String) -> Bool {
		pointee.type == XML_ELEMENT_NODE && xmlHasProp(self, name) != nil
	}

	/// Changes the value in the same attribute node, so a list that holds the attribute keeps a valid node.
	func setAttribute(_ name: String, _ value: String) {
		guard pointee.type == XML_ELEMENT_NODE else { return }
		xmlSetProp(self, name, value)
	}

	/// The text of the node and all its descendants, or the value of an attribute node.
	var text: String {
		guard let buffer = xmlBufferCreate() else { return "" }
		defer { xmlBufferFree(buffer) }
		xmlNodeBufGetContent(buffer, self)
		return xmlBufferContent(buffer).map { String(cString: $0) } ?? ""
	}

	var elementChildren: [Node] {
		guard pointee.type == XML_ELEMENT_NODE || pointee.type == XML_HTML_DOCUMENT_NODE else { return [] }
		return Array(sequence(first: pointee.children) { $0?.pointee.next }.prefix { $0 != nil }.compactMap { $0 }.filter { $0.pointee.type == XML_ELEMENT_NODE })
	}

	/// The elements below the node, in document order.
	var descendants: [Node] {
		var result: [Node] = []
		var pending = Array(elementChildren.reversed())
		while let node = pending.popLast() {
			result.append(node)
			pending += node.elementChildren.reversed()
		}
		return result
	}

	func ancestor(_ tag: String) -> Node? {
		sequence(first: self) { $0.pointee.parent }.dropFirst().first { $0.tag == tag }
	}
}

/// How an enabled form field takes part in what its form sends, as browsers decide it.
private enum Field {
	/// A checkbox or radio button sends its value when it is checked.
	case checkable(value: String, checked: Bool)
	/// Only the button that submits the form sends its value; an image button sends where it was clicked.
	case button(value: String, submits: Bool, image: Bool)
	/// The values of the selected options of a `<select>` list.
	case options([String])
	case text(String)

	/// Nil for a disabled field and for an element that is no field.
	init?(_ node: Node) {
		guard !node.has("disabled") else { return nil }
		let value = node.attribute("value")
		switch (node.tag, node.attribute("type")?.lowercased()) {
		case ("select", _): self = .options(Form.selectedOptions(of: node).map(Form.optionValue))
		case ("textarea", _): self = .text(node.text)
		case ("button", let type): self = .button(value: value ?? "", submits: type == nil || type == "submit", image: false)
		case ("input", "checkbox"), ("input", "radio"): self = .checkable(value: value ?? "on", checked: node.has("checked"))
		case ("input", "submit"): self = .button(value: value ?? "", submits: true, image: false)
		case ("input", "image"): self = .button(value: "", submits: true, image: true)
		case ("input", "reset"), ("input", "button"): self = .button(value: value ?? "", submits: false, image: false)
		case ("input", "file"): self = .text("")
		case ("input", _): self = .text(value ?? "")
		default: return nil
		}
	}
}

/// What a browser sends for a form.
private enum Form {
	struct Request {
		let method: String
		/// The action as the document writes it; `connection:request` resolves it against the last URL.
		let url: String
		/// The URL-encoded fields of a POST. A GET carries them in the query of `url`.
		let body: Data?
	}

	static func request(_ form: Node, submitter: Node?, encoding: String.Encoding) -> Request {
		let method = (submitter?.attribute("formmethod") ?? form.attribute("method"))?.lowercased() == "post" ? "POST" : "GET"
		let action = submitter?.attribute("formaction") ?? form.attribute("action") ?? ""
		let query = entries(of: form, submitter: submitter).map { encode($0, encoding) + "=" + encode($1, encoding) }.joined(separator: "&")
		guard method == "GET" else { return Request(method: method, url: action, body: Data(query.utf8)) }
		let fragment = action.firstIndex(of: "#").map { String(action[$0...]) } ?? ""
		return Request(method: method, url: action.prefix { $0 != "?" && $0 != "#" } + "?" + query + fragment, body: nil)
	}

	/// The name-value pairs of the fields of `form`, in document order.
	private static func entries(of form: Node, submitter: Node?) -> [(String, String)] {
		form.descendants.flatMap { node -> [(String, String)] in
			guard let field = Field(node) else { return [] }
			let name = node.attribute("name") ?? ""
			switch field {
			case .button(_, submits: true, image: true) where node == submitter:
				return name.isEmpty ? [("x", "0"), ("y", "0")] : [(name + ".x", "0"), (name + ".y", "0")]
			case _ where name.isEmpty: return []
			case let .checkable(value, checked): return checked ? [(name, value)] : []
			case let .button(value, submits, _): return submits && node == submitter ? [(name, value)] : []
			case let .options(values): return values.map { (name, $0) }
			case let .text(value): return [(name, value)]
			}
		}
	}

	/// `val()`: the value of an enabled field, whether or not it is checked, and the first selected option of a list.
	static func value(of node: Node) -> String? {
		switch Field(node) {
		case let .checkable(value, _), let .button(value, _, _), let .text(value): value
		case let .options(values): values.first
		case nil: nil
		}
	}

	/// The options that a browser sends: a list without a selected option shows its first enabled one.
	static func selectedOptions(of select: Node) -> [Node] {
		let options = select.descendants.filter { $0.tag == "option" }
		let multiple = select.has("multiple")
		var selected = options.filter { $0.has("selected") }
		if !multiple { selected = Array(selected.suffix(1)) }
		if selected.isEmpty, !multiple, Int(select.attribute("size") ?? "") ?? 1 <= 1, let first = options.first(where: { !$0.has("disabled") }) {
			selected = [first]
		}
		return selected.filter { !$0.has("disabled") }
	}

	static func optionValue(_ option: Node) -> String {
		option.attribute("value") ?? option.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
	}

	/// `select(value)`: selects the enabled option with the value and deselects the others.
	static func choose(_ value: String, in select: Node, of tree: HTMLTree) {
		guard select.tag == "select", !select.has("disabled") else { return }
		let options = select.descendants.filter { $0.tag == "option" }
		guard let chosen = options.first(where: { !$0.has("disabled") && optionValue($0) == value }) else { return }
		for option in options { tree.remove("selected", from: option) }
		chosen.setAttribute("selected", "selected")
	}

	/// URL-encodes `text` in the character set of the document as browsers do: a character that the
	/// set lacks becomes a numeric character reference, and line breaks become CR LF.
	static func encode(_ text: String, _ encoding: String.Encoding) -> String {
		var bytes: [UInt8] = []
		var previous: Unicode.Scalar?
		for scalar in text.unicodeScalars {
			defer { previous = scalar }
			switch scalar {
			case "\n" where previous == "\r": continue
			case "\r", "\n": bytes += [13, 10]
			default: bytes += String(scalar).data(using: encoding).map(Array.init) ?? Array("&#\(scalar.value);".utf8)
			}
		}
		return bytes.map { byte in
			switch byte {
			case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
				UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"): String(UnicodeScalar(byte))
			case UInt8(ascii: " "): "+"
			default: String(format: "%%%02X", byte)
			}
		}.joined()
	}
}

/// A Lua object whose state is a Swift object: a full userdata that holds a retained reference,
/// which its `__gc` releases when Lua collects it.
enum LuaObject {
	/// Registers the metatable `type`. Its `__index` is the table of `methods`, which records a read of
	/// any other name as a miss of `misses` and the name, such as "elements:foo". `__metatable` hides
	/// the metatable from the script, so that it cannot call `__gc` itself.
	/// `luaMethods` are Lua source that returns the function.
	static func register(_ stack: LuaStack, _ type: String, misses: String, methods: [(String, clua_Function)], luaMethods: [(String, String)] = []) {
		let L = stack.L
		luaL_newmetatable(L, type)
		clua_pushfunction(L, release)
		lua_setfield(L, -2, "__gc")
		lua_pushboolean(L, 0)
		lua_setfield(L, -2, "__metatable")
		lua_createtable(L, 0, Int32(methods.count))
		for (name, function) in methods {
			clua_pushfunction(L, function)
			lua_setfield(L, -2, name)
		}
		for (name, source) in luaMethods {
			luaL_loadbufferx(L, source, source.utf8.count, "=" + misses + name, "t")
			_ = clua_pcall(L, 0, 1)
			lua_setfield(L, -2, name)
		}
		Environment.reportMisses(stack, of: misses)
		lua_setfield(L, -2, "__index")
		lua_settop(L, -2)
	}

	static func push(_ stack: LuaStack, _ object: AnyObject, _ type: String) {
		let slot = lua_newuserdatauv(stack.L, MemoryLayout<UnsafeRawPointer>.size, 0)!
		slot.storeBytes(of: Unmanaged.passRetained(object).toOpaque(), as: UnsafeRawPointer?.self)
		luaL_setmetatable(stack.L, type)
	}

	/// The object of the userdata at `index`, or nil when it is no object of `type` or Lua has already collected it.
	static func object<T: AnyObject>(_ stack: LuaStack, at index: Int32, _ type: String) -> T? {
		guard let slot = luaL_testudata(stack.L, index, type), let pointer = slot.load(as: UnsafeRawPointer?.self) else { return nil }
		return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
	}

	/// `__gc`. A finalizer of the script may still reach the userdata afterwards, so the slot is cleared.
	private static let release: clua_Function = { L in
		guard let slot = lua_touserdata(L, 1), let pointer = slot.load(as: UnsafeRawPointer?.self) else { return 0 }
		slot.storeBytes(of: nil, as: UnsafeRawPointer?.self)
		Unmanaged<AnyObject>.fromOpaque(pointer).release()
		return 0
	}

	/// The state of an object that is one value, such as the text of a JSON object.
	final class Box<Value> {
		var value: Value

		init(_ value: Value) {
			self.value = value
		}
	}
}
