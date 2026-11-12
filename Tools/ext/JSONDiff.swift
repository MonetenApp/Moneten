import ExtensionHost
import Foundation

/// The differences between the expected and the actual result, each with its JSON Pointer. Numbers
/// are equal when their values are, so -89, -89.0, and -89.00 are the same.
enum JSONDiff {
	static func differences(expected: LuaValue, actual: LuaValue, path: String = "") -> [String] {
		switch (expected, actual) {
		case let (.object(left), .object(right)):
			return Set(left.keys).union(right.keys).sorted().flatMap { key in
				let child = path + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
				switch (left[key], right[key]) {
				case let (l?, r?): return differences(expected: l, actual: r, path: child)
				case let (l?, nil): return ["\(child): expected \(text(l)), got nothing"]
				case let (nil, r?): return ["\(child): expected nothing, got \(text(r))"]
				case (nil, nil): return []
				}
			}
		case let (.array(left), .array(right)):
			return (0..<max(left.count, right.count)).flatMap { index in
				let child = "\(path)/\(index)"
				if index >= right.count { return ["\(child): expected \(text(left[index])), got nothing"] }
				if index >= left.count { return ["\(child): expected nothing, got \(text(right[index]))"] }
				return differences(expected: left[index], actual: right[index], path: child)
			}
		default:
			return same(expected, actual) ? [] : ["\(path.isEmpty ? "/" : path): expected \(text(expected)), got \(text(actual))"]
		}
	}

	private static func same(_ left: LuaValue, _ right: LuaValue) -> Bool {
		switch (left, right) {
		case let (.integer(l), .number(r)), let (.number(r), .integer(l)): Double(l) == r
		default: left == right
		}
	}

	/// The value as compact JSON, such as -89 or "Rent".
	static func text(_ value: LuaValue) -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
	}
}
