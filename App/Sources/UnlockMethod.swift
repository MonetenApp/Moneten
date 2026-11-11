import LocalAuthentication

/// Touch ID and the Apple Watch unlock the app with the database password from the Keychain.
/// Each method has its own setting. With both on, one request of macOS offers both.
enum UnlockMethod: CaseIterable {
	case touchID
	case appleWatch

	var preference: String {
		switch self {
		case .touchID: Preference.unlockWithTouchID
		case .appleWatch: Preference.unlockWithAppleWatch
		}
	}

	private var policy: LAPolicy {
		switch self {
		case .touchID: .deviceOwnerAuthenticationWithBiometrics
		case .appleWatch: .deviceOwnerAuthenticationWithCompanion
		}
	}

	/// Where a reason is shown. The settings refuse a method only while it is not set up, and the
	/// lock screen also names what is missing right now, such as a closed lid.
	enum Place { case settings, lockScreen }

	/// Nil when the method can be used at this place, otherwise why it cannot.
	func unavailableReason(for place: Place) -> String? {
		let context = LAContext()
		var error: NSError?
		if context.canEvaluatePolicy(policy, error: &error) { return nil }
		let code = error.flatMap { LAError.Code(rawValue: $0.code) }
		switch (self, code) {
		case (.touchID, .biometryNotEnrolled):
			return "Touch ID is not set up. Add a fingerprint in System Settings → Touch ID & Password first."
		case (.touchID, .biometryLockout):
			return place == .settings ? nil : "macOS has locked Touch ID after too many failed attempts. Enter the database password."
		case (.touchID, .biometryDisconnected):
			return place == .settings ? nil : "Touch ID is not available while the lid is closed."
		case (.touchID, .biometryNotAvailable):
			// With the lid closed, a Mac with a sensor can report the sensor as missing.
			if context.biometryType != .touchID { return "This Mac has no Touch ID sensor." }
			return place == .settings ? nil : "Touch ID is not available right now, for example while the lid is closed."
		case (.appleWatch, .companionNotAvailable):
			// macOS reports a watch that is not set up and one that is out of range the same way.
			return place == .settings
				? "No Apple Watch can unlock this Mac right now. Turn it on in System Settings → Touch ID & Password, and keep the watch nearby."
				: "No Apple Watch was detected nearby."
		case (_, .passcodeNotSet):
			return "Your Mac user account has no login password."
		default:
			return "\(name) is not available. \(error?.localizedDescription ?? "")"
		}
	}

	var name: String {
		switch self {
		case .touchID: "Touch ID"
		case .appleWatch: "Apple Watch"
		}
	}

	/// "Touch ID", "Apple Watch", or "Touch ID or Apple Watch".
	static func names(_ methods: [UnlockMethod]) -> String {
		methods.map(\.name).joined(separator: " or ")
	}

	/// Asks macOS to confirm with the given methods and reports whether the user did.
	static func authenticate(_ methods: [UnlockMethod], reply: @escaping @Sendable (Bool) -> Void) {
		let policy: LAPolicy
		switch (methods.contains(.touchID), methods.contains(.appleWatch)) {
		case (true, true): policy = .deviceOwnerAuthenticationWithBiometricsOrCompanion
		case (true, false): policy = .deviceOwnerAuthenticationWithBiometrics
		case (false, true): policy = .deviceOwnerAuthenticationWithCompanion
		case (false, false): return
		}
		LAContext().evaluatePolicy(policy, localizedReason: "open the Moneten database") { ok, _ in reply(ok) }
	}
}
