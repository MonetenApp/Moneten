import CoreGraphics
import Domain
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Sync

/// tan-handling "Checked challenge images": the dialog decodes only the type that `ChallengeImage`
/// checked, and never more pixels than the limit.
@Suite("Challenge picture")
struct ChallengePictureTests {
	@Test("A checked PNG and a checked JPEG decode at their size", arguments: [UTType.png, .jpeg])
	func decodes(type: UTType) throws {
		let image = ChallengeImage(try Self.encode(width: 120, height: 80, as: type))
		#expect(image.picture != nil)
		let picture = try #require(ChallengePicture.decode(image))
		#expect(picture.width == 120)
		#expect(picture.height == 80)
	}

	@Test("An image that failed the check decodes to nothing")
	func rejected() throws {
		#expect(ChallengePicture.decode(ChallengeImage(try Self.encode(width: 10, height: 10, as: .tiff))) == nil)
		#expect(ChallengePicture.decode(ChallengeImage(try Self.encode(width: 10, height: 10, as: .gif))) == nil)
	}

	@Test("Bytes of another type than the checked one do not decode")
	func otherType() throws {
		let gif = try Self.encode(width: 10, height: 10, as: .gif)
		#expect(ChallengePicture.decode(gif, as: .png, maximumSide: 2048) == nil)
		let png = try Self.encode(width: 10, height: 10, as: .png)
		#expect(ChallengePicture.decode(png, as: .jpeg, maximumSide: 2048) == nil)
		#expect(ChallengePicture.decode(png, as: .png, maximumSide: 2048) != nil)
	}

	@Test("An image larger than the limit does not decode, also when its header passed the first check")
	func largerThanLimit() throws {
		let png = try Self.encode(width: 64, height: 32, as: .png)
		#expect(ChallengePicture.decode(png, as: .png, maximumSide: 63) == nil)
		let picture = try #require(ChallengePicture.decode(png, as: .png, maximumSide: 64))
		#expect(picture.width == 64)
	}

	@Test("Bytes that end in the middle of the image do not decode")
	func truncated() throws {
		let png = try Self.encode(width: 200, height: 200, as: .png)
		#expect(ChallengePicture.decode(png.prefix(60), as: .png, maximumSide: 2048) == nil)
	}

	/// A gray image in the given format, as ImageIO writes it.
	static func encode(width: Int, height: Int, as type: UTType) throws -> Data {
		let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.setFillColor(gray: 0.5, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
		CGImageDestinationAddImage(destination, image, nil)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}
}
