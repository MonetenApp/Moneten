import Foundation
import Observation

/// The width of the flicker code, which the user fits to the TAN generator ("Flicker code size"). It
/// is kept in the settings, so the next flicker code has the same size. The first enlargement waits
/// until the user agrees to the warning that flicker codes might cause epileptic seizures.
@MainActor
@Observable
public final class FlickerCodeSize {
	public static let widths: [Double] = [160, 200, 240, 280, 320, 360, 400]
	static let widthKey = "flickerCodeWidth"
	static let agreedKey = "flickerCodeWarningAgreed"

	public private(set) var width: Double
	/// The warning is on screen.
	public private(set) var showsWarning = false
	@ObservationIgnored private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		let saved = defaults.double(forKey: Self.widthKey)
		width = Self.widths.contains(saved) ? saved : 240
	}

	public var canShrink: Bool { width > Self.widths[0] }
	public var canEnlarge: Bool { width < Self.widths[Self.widths.count - 1] }

	public func shrink() {
		guard let smaller = Self.widths.last(where: { $0 < width }) else { return }
		set(smaller)
	}

	/// Enlarges the code, or shows the warning first when the user never agreed to it.
	public func enlarge() {
		guard defaults.bool(forKey: Self.agreedKey) else {
			showsWarning = true
			return
		}
		guard let larger = Self.widths.first(where: { $0 > width }) else { return }
		set(larger)
	}

	public func agree() {
		showsWarning = false
		defaults.set(true, forKey: Self.agreedKey)
		enlarge()
	}

	public func decline() {
		showsWarning = false
	}

	private func set(_ width: Double) {
		self.width = width
		defaults.set(width, forKey: Self.widthKey)
	}
}
