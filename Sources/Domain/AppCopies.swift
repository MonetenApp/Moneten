/// How a copy of the app is signed, as far as the warning about several copies needs it.
public enum AppSignature: Sendable, Equatable {
	/// A Developer ID Application certificate of `team`, which only a release carries.
	case developerID(team: String)
	/// Another certificate of `team`, such as Apple Development.
	case otherCertificate(team: String)
	/// Signed ad hoc, not signed, or a signature that cannot be read.
	case local
}

/// A copy of the app that Launch Services knows, as the app found it on the disk.
public struct AppCopy: Sendable, Equatable {
	/// The path of the application file with resolved symbolic links.
	public var path: String
	/// The copy lies on a read-only volume, such as a CD or a volume that macOS mounts read-only.
	public var isOnReadOnlyVolume: Bool
	/// The copy lies on a mounted disk image, also a writable one.
	public var isOnDiskImage: Bool
	/// Only a copy with a Developer ID can update itself, so only such a copy can fall behind.
	public var signature: AppSignature

	public init(path: String, isOnReadOnlyVolume: Bool, isOnDiskImage: Bool, signature: AppSignature) {
		self.path = path
		self.isOnReadOnlyVolume = isOnReadOnlyVolume
		self.isOnDiskImage = isOnDiskImage
		self.signature = signature
	}
}

/// The warning about several copies at launch (spec: "Warn about several copies").
public enum AppCopies {
	/// The places to name when more than one copy counts, sorted, else nil. A place is the folder of
	/// a copy, or the copy itself when its folder holds another copy. Sparkle updates only a release,
	/// so only a `running` copy with a Developer ID warns, and only copies with the same Developer ID
	/// count. Copies on a disk image, on a read-only volume, and in the Trash do not count either.
	public static func folders(of copies: [AppCopy], running: AppCopy) -> [String]? {
		guard case .developerID = running.signature else { return nil }
		let counted = Set((copies + [running]).filter {
			$0.signature == running.signature && !$0.isOnDiskImage && !$0.isOnReadOnlyVolume && !isInTrash($0.path)
		}.map(\.path))
		guard counted.count > 1 else { return nil }
		let byFolder = Dictionary(grouping: counted, by: folder)
		return byFolder.flatMap { folder, paths in paths.count == 1 ? [folder] : paths }.sorted()
	}

	/// The Trash of the home folder is `~/.Trash`, the Trash of another volume `.Trashes/<user id>`.
	private static func isInTrash(_ path: String) -> Bool {
		path.split(separator: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
	}

	private static func folder(of path: String) -> String {
		guard let slash = path.lastIndex(of: "/") else { return path }
		return slash == path.startIndex ? "/" : String(path[..<slash])
	}
}
