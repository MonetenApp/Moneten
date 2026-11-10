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

	/// Where a reason is shown. The settings explain how to set a method up, the lock screen what is missing now.
	enum Place { case settings, lockScreen }

	/// Nil when macOS can use the method now, otherwise why it cannot.
	func unavailableReason(for place: Place) -> String? {
		let context = LAContext()
		var error: NSError?
		if context.canEvaluatePolicy(policy, error: &error) { return nil }
		let code = error.flatMap { LAError.Code(rawValue: $0.code) }
		switch (self, code) {
		case (.touchID, .biometryNotEnrolled):
			return "Touch ID is not set up. Add a fingerprint in System Settings → Touch ID & Password first."
		case (.touchID, .biometryLockout):
			return "macOS has locked Touch ID after too many failed attempts. Enter the database password."
		case (.touchID, .biometryDisconnected):
			return "Touch ID is not available while the lid is closed."
		case (.touchID, .biometryNotAvailable):
			// With the lid closed, a Mac with a sensor can report the sensor as missing.
			return context.biometryType == .touchID
				? "Touch ID is not available right now, for example while the lid is closed."
				: "This Mac has no Touch ID sensor."
		case (.appleWatch, .companionNotAvailable):
			return place == .settings
				? "No Apple Watch is set up to unlock this Mac. Turn it on in System Settings → Touch ID & Password first."
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
		LAContext().evaluatePolicy(policy, localizedReason: "open the MonetenMoneten database") { ok, _ in reply(ok) }
	}
}
