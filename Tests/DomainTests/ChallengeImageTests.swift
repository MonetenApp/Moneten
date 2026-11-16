import Domain
import Foundation
import Testing

/// tan-handling "Checked challenge images": only PNG and JPEG within the byte and pixel limits keep
/// their bytes, so no decoder of the app ever reads anything else.
@Suite("Challenge image")
struct ChallengeImageTests {
	@Test("A PNG keeps its bytes, its format, and the size from its header")
	func png() throws {
		let data = Self.png(width: 300, height: 200)
		let picture = try #require(ChallengeImage(data).picture)
		#expect(picture.data == data)
		#expect(picture.format == .png)
		#expect(picture.width == 300)
		#expect(picture.height == 200)
	}

	@Test("A JPEG keeps its bytes, and the size comes from the frame header after the other segments")
	func jpeg() throws {
		let data = Self.jpeg(width: 640, height: 480)
		let picture = try #require(ChallengeImage(data).picture)
		#expect(picture.data == data)
		#expect(picture.format == .jpeg)
		#expect(picture.width == 640)
		#expect(picture.height == 480)
	}

	@Test("An image of exactly 2048 by 2048 pixels passes")
	func largestSide() {
		#expect(ChallengeImage(Self.png(width: 2048, height: 2048)).picture != nil)
		#expect(ChallengeImage(Self.jpeg(width: 2048, height: 2048)).picture != nil)
	}

	@Test("TIFF, HEIC, GIF, JPEG 2000, and bytes without a signature are rejected", arguments: Self.foreignFormats)
	func otherFormats(name: String, data: Data) {
		#expect(ChallengeImage(data).picture == nil, "\(name)")
	}

	@Test("A file over 1 MB is rejected, even with a valid header")
	func oversizedFile() {
		let limit = ChallengeImage.maximumBytes
		#expect(limit == 1_048_576)
		let png = Self.png(width: 100, height: 100)
		#expect(ChallengeImage(png + Data(count: limit - png.count)).picture != nil)
		#expect(ChallengeImage(png + Data(count: limit - png.count + 1)).picture == nil)
	}

	@Test("A header that states more than 2048 pixels on a side is rejected", arguments: [
		(50000, 50000), (2049, 10), (10, 2049),
	])
	func hugeDimensions(width: Int, height: Int) {
		#expect(ChallengeImage(Self.png(width: width, height: height)).picture == nil)
		#expect(ChallengeImage(Self.jpeg(width: width, height: height)).picture == nil)
	}

	@Test("A PNG or JPEG with a broken header is rejected")
	func brokenHeaders() {
		#expect(ChallengeImage(Self.png(width: 0, height: 10)).picture == nil)
		#expect(ChallengeImage(Self.jpeg(width: 10, height: 0)).picture == nil)
		// The signature alone, without IHDR.
		#expect(ChallengeImage(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF])).picture == nil)
		// Another chunk where IHDR must be.
		var chunk = Self.png(width: 10, height: 10)
		chunk.replaceSubrange(12..<16, with: Data("tEXt".utf8))
		#expect(ChallengeImage(chunk).picture == nil)
		// A JPEG that ends before its frame header.
		#expect(ChallengeImage(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + Data(count: 4)).picture == nil)
		// A JPEG whose scan starts before any frame header.
		#expect(ChallengeImage(Data([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02])).picture == nil)
		// A segment length below two, which would never advance.
		#expect(ChallengeImage(Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0xFF, 0xC0])).picture == nil)
	}

	@Test("Two images with the same bytes are equal, and two rejected images are equal")
	func equality() {
		#expect(ChallengeImage(Self.png(width: 5, height: 5)) == ChallengeImage(Self.png(width: 5, height: 5)))
		#expect(ChallengeImage(Data("GIF89a".utf8)) == ChallengeImage(Data([0x49, 0x49, 0x2A, 0x00])))
	}

	static let foreignFormats: [(String, Data)] = {
		let tiff = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]) + Data(count: 64)
		let tiffBigEndian = Data([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]) + Data(count: 64)
		let heic = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypheic".utf8) + Data(count: 64)
		let gif = Data("GIF89a".utf8) + Data([0x2C, 0x01, 0xC8, 0x00]) + Data(count: 64)
		let jpeg2000 = Data([0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) + Data(count: 64)
		return [("TIFF", tiff), ("TIFF big endian", tiffBigEndian), ("HEIC", heic), ("GIF", gif), ("JPEG 2000", jpeg2000),
			("text", Data("not an image".utf8)), ("empty", Data())]
	}()

	/// The signature and the IHDR chunk of a PNG, with a made-up rest. The check reads no further.
	static func png(width: Int, height: Int) -> Data {
		var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]) + Data("IHDR".utf8)
		data += bigEndian(UInt32(width)) + bigEndian(UInt32(height))
		data += Data([0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
		return data + Data(count: 32)
	}

	/// The start of a JPEG with an APP0 segment, fill bytes, and a baseline frame header.
	static func jpeg(width: Int, height: Int) -> Data {
		var data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + Data("JFIF\0".utf8) + Data([0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
		data += Data([0xFF, 0xFF, 0xC0, 0x00, 0x11, 0x08]) + bigEndian(UInt16(height)) + bigEndian(UInt16(width))
		data += Data([0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01])
		return data + Data(count: 32)
	}

	private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
		withUnsafeBytes(of: value.bigEndian) { Data($0) }
	}
}
