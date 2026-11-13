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
/// `{"bytes": "<Base64>"}` or `{"uuid": "<UUID>"}`. `ext record` withholds a value that no request
/// address needs, as `{"withheld": <number of bytes>}` or `{"withheld": "uuid"}`, and a replay gives
/// counter values in its place.
public enum RandomValue: Sendable, Equatable, Codable {
	case bytes(Data)
	case uuid(String)
	case withheldBytes(Int)
	case withheldUUID

	private enum Key: String, CodingKey {
		case bytes, uuid, withheld
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: Key.self)
		if let uuid = try container.decodeIfPresent(String.self, forKey: .uuid) {
			self = .uuid(uuid)
		} else if container.contains(.withheld) {
			if let count = try? container.decode(Int.self, forKey: .withheld) {
				self = .withheldBytes(count)
			} else if try container.decode(String.self, forKey: .withheld) == "uuid" {
				self = .withheldUUID
			} else {
				throw DecodingError.dataCorruptedError(forKey: .withheld, in: container, debugDescription: "A withheld value is a number of bytes or \"uuid\".")
			}
		} else {
			self = .bytes(try container.decode(Data.self, forKey: .bytes))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: Key.self)
		switch self {
		case let .bytes(data): try container.encode(data, forKey: .bytes)
		case let .uuid(text): try container.encode(text, forKey: .uuid)
		case let .withheldBytes(count): try container.encode(count, forKey: .withheld)
		case .withheldUUID: try container.encode("uuid", forKey: .withheld)
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
	/// Gets the index of a reported value that the script used as a key, for `ext record`, or nil for
	/// a key that comes from no reported value.
	private let keyUse: (Int?) -> Void
	/// Gets the SHA-256 of each AES or HMAC key during `ext record` and `ext test`, never the key.
	private let fingerprint: ((Data) -> Void)?
	/// The values of a recording in order, as `report` got them.
	private var produced: [RandomValue] = []
	private var counter: UInt64 = 0

	init(_ capture: Capture?, report: @escaping (RandomValue) -> Void, keyUse: @escaping (Int?) -> Void = { _ in },
		fingerprint: @escaping (Data) -> Void = { _ in }) {
		switch capture {
		case nil: (recorded, self.report) = (nil, nil)
		case .record: (recorded, self.report) = (nil, report)
		case let .replay(_, random): (recorded, self.report) = (random, nil)
		}
		self.keyUse = keyUse
		self.fingerprint = capture == nil ? nil : fingerprint
	}

	/// Reports the recorded value that the script passes as the key or the IV of an encryption or as
	/// the key of an HMAC, or that such a key comes from: as bytes or in a text form, its MD5, SHA, or
	/// SHA3-256 digest or a prefix of 16 bytes or more of one, raw or as hex, or a slice of 16 bytes or
	/// more. `ext record` never keeps such a value in a fixture. A key, not an IV, that comes from no
	/// recorded value is reported as nil. Each key, not an IV, also gives its fingerprint.
	func usedAsKey(_ key: Data, isIV: Bool = false) {
		if !isIV { fingerprint?(Data(SHA256.hash(data: key))) }
		guard report != nil else { return }
		if let index = produced.firstIndex(where: { Self.value($0, gives: key) }) {
			keyUse(index)
		} else if !isIV {
			keyUse(nil)
		}
	}

	private static func value(_ value: RandomValue, gives key: Data) -> Bool {
		let text = String(decoding: key, as: UTF8.self).lowercased()
		let inputs: [Data]
		switch value {
		case let .bytes(data):
			let base64 = data.base64EncodedString()
			let url = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
			let forms = [data.map { String(format: "%02x", $0) }.joined(), base64, url].flatMap { [$0, $0.trimmingCharacters(in: CharacterSet(charactersIn: "="))] }
			inputs = [data] + forms.map { Data($0.utf8) }
		case let .uuid(uuid):
			inputs = [uuid.lowercased(), uuid.lowercased().replacingOccurrences(of: "-", with: "")].map { Data($0.utf8) }
		case .withheldBytes, .withheldUUID:
			return false
		}
		let hex = { (data: Data) in data.map { String(format: "%02x", $0) }.joined() }
		for input in inputs {
			if input == key || String(decoding: input, as: UTF8.self).lowercased() == text { return true }
			if key.count >= 16, input.range(of: key) != nil || text.count >= 16 && String(decoding: input, as: UTF8.self).lowercased().contains(text) { return true }
			let digests = [Data(Insecure.MD5.hash(data: input)), Data(Insecure.SHA1.hash(data: input)), Data(SHA256.hash(data: input)),
				Data(SHA384.hash(data: input)), Data(SHA512.hash(data: input)), Keccak.sha3_256(input)]
			if digests.contains(where: { $0 == key || hex($0) == text || key.count >= 16 && ($0.starts(with: key) || text.count >= 16 && hex($0).hasPrefix(text)) }) {
				return true
			}
		}
		return false
	}

	func bytes(_ count: Int) -> Data {
		if recorded != nil {
			switch recorded?.first {
			case let .bytes(data)? where data.count == count:
				recorded?.removeFirst()
				return data
			case let .withheldBytes(length)? where length == count:
				recorded?.removeFirst()
				return counted(count)
			default:
				return counted(count)
			}
		}
		let data = Self.system(count)
		if let report {
			produced.append(.bytes(data))
			report(.bytes(data))
		}
		return data
	}

	func uuid() -> String {
		if recorded != nil {
			switch recorded?.first {
			case let .uuid(text)?:
				recorded?.removeFirst()
				return text
			case .withheldUUID?:
				recorded?.removeFirst()
			default:
				break
			}
			var bytes = [UInt8](counted(16))
			bytes[6] = bytes[6] & 0x0F | 0x40
			bytes[8] = bytes[8] & 0x3F | 0x80
			return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
				bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
		}
		let text = UUID().uuidString.lowercased()
		if let report {
			produced.append(.uuid(text))
			report(.uuid(text))
		}
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
