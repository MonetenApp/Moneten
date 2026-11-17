import CoreGraphics
import Domain
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes a challenge image for the dialog. `ChallengeImage` already let only PNG and JPEG within the
/// limits through. This is the second guard right before the decoder: ImageIO gets the checked type as
/// a hint and, from macOS 27 on, as the only allowed type. It must detect the same type, must read a
/// size within the limit, and draws at most that many pixels on the long side. So a mislabeled or oversized image never reaches a general decoder.
public enum ChallengePicture {
	/// The bitmap of a checked image, or nil when it failed a check or does not decode.
	public static func decode(_ image: ChallengeImage) -> CGImage? {
		guard let picture = image.picture else { return nil }
		return decode(picture.data, as: picture.format, maximumSide: ChallengeImage.maximumSide)
	}

	static func decode(_ data: Data, as format: ChallengeImage.Format, maximumSide: Int) -> CGImage? {
		let type = switch format {
		case .png: UTType.png
		case .jpeg: UTType.jpeg
		}
		var options: [CFString: Any] = [kCGImageSourceTypeIdentifierHint: type.identifier, kCGImageSourceShouldCache: false]
		// The hint does not stop ImageIO from trying other readers. From macOS 27 on, this option does.
		// The SDK of an older Xcode lacks the key, so the compiler check keeps the build working there.
		#if compiler(>=6.4)
		if #available(macOS 27, *) { options[kCGImageSourceAllowableTypes] = [type.identifier] }
		#endif
		guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary), CGImageSourceGetType(source) as String? == type.identifier,
			CGImageSourceGetCount(source) >= 1,
			let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
			(1...maximumSide).contains(width), (1...maximumSide).contains(height) else { return nil }
		let thumbnail = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceThumbnailMaxPixelSize: max(width, height),
			kCGImageSourceShouldCacheImmediately: true,
		] as CFDictionary
		return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail)
	}
}
