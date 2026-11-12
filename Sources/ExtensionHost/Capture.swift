import CryptoKit
import Foundation

/// How `ext record` and `ext test` fix what a script cannot repeat by itself, so that a replay gives
/// the result of the recording. The app runs without it.
public enum Capture: Sendable, Codable, Equatable {
	/// The clock starts at `start` and moves only with `MM.sleep`, which waits. The host reports each
	/// exchange and each random value.
	case record(start: Double)
	/// The clock starts at `start` and moves only with `MM.sleep`, which returns at once. The random
	/// values come from `random` in order.
	case replay(start: Double, random: [RandomValue])
}

/// One value of `MM.random`, `MM.uuid`, or the RSA padding, as a fixture holds it:
/// `{"bytes": "<Base64>"}` or `{"uuid": "<UUID>"}`.
public enum RandomValue: Sendable, Equatable, Codable {
	case bytes(Data)
	case uuid(String)

	private enum Key: String, CodingKey {
		case bytes, uuid
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: Key.self)
		if let uuid = try container.decodeIfPresent(String.self, forKey: .uuid) {
			self = .uuid(uuid)
		} else {
			self = .bytes(try container.decode(Data.self, forKey: .bytes))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: Key.self)
		switch self {
		case let .bytes(data): try container.encode(data, forKey: .bytes)
		case let .uuid(text): try container.encode(text, forKey: .uuid)
		}
	}
}

/// The clock of one session. Without a start it is the clock of the system.
final class SessionClock {
	private let start: Double?
	/// False in a replay, whose `MM.sleep` returns at once.
	let waits: Bool
	private var slept = 0.0

	init(_ capture: Capture?) {
		switch capture {
		case nil: (start, waits) = (nil, true)
		case let .record(start): (self.start, waits) = (start, true)
		case let .replay(start, _): (self.start, waits) = (start, false)
		}
	}

	var isFixed: Bool { start != nil }

	func now() -> Date {
		start.map { Date(timeIntervalSince1970: $0 + slept) } ?? Date()
	}

	func sleep(_ seconds: Double) {
		if waits { Thread.sleep(forTimeInterval: seconds) }
		slept += seconds
	}
}

/// The random values of one session: from the system, from the system with a report of each value,
/// or from a recording. A replay that needs more values than the recording has gets values from a
/// counter, so that the run still repeats.
final class Entropy {
	private var recorded: [RandomValue]?
	private let report: ((RandomValue) -> Void)?
	private var counter: UInt64 = 0

	init(_ capture: Capture?, report: @escaping (RandomValue) -> Void) {
		switch capture {
		case nil: (recorded, self.report) = (nil, nil)
		case .record: (recorded, self.report) = (nil, report)
		case let .replay(_, random): (recorded, self.report) = (random, nil)
		}
	}

	func bytes(_ count: Int) -> Data {
		if recorded != nil {
			if case let .bytes(data)? = recorded?.first, data.count == count {
				recorded?.removeFirst()
				return data
			}
			return counted(count)
		}
		let data = Self.system(count)
		report?(.bytes(data))
		return data
	}

	func uuid() -> String {
		if recorded != nil {
			if case let .uuid(text)? = recorded?.first {
				recorded?.removeFirst()
				return text
			}
			var bytes = [UInt8](counted(16))
			bytes[6] = bytes[6] & 0x0F | 0x40
			bytes[8] = bytes[8] & 0x3F | 0x80
			return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
				bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
		}
		let text = UUID().uuidString.lowercased()
		report?(.uuid(text))
		return text
	}

	/// The seed of an RSA padding. A recording leaves it out: with the seed, anyone who has the
	/// fixture could test each guess of a short secret, such as a PIN, against the encrypted block.
	func padding(_ count: Int) -> Data {
		recorded == nil ? Self.system(count) : counted(count)
	}

	private func counted(_ count: Int) -> Data {
		var data = Data()
		while data.count < count {
			counter += 1
			data += SHA256.hash(data: withUnsafeBytes(of: counter.bigEndian) { Data($0) })
		}
		return data.prefix(count)
	}

	static func system(_ count: Int) -> Data {
		var data = Data(count: count)
		let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
		precondition(status == errSecSuccess, "The system has no random numbers.")
		return data
	}
}
