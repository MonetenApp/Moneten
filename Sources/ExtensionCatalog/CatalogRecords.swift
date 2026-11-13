import Foundation
import Storage

/// The records of catalog packages in the database, as an install writes them and as a failed install
/// puts back the record it replaced.
public struct CatalogRecords: Sendable {
	public let store: Store

	public init(store: Store) {
		self.store = store
	}

	public func save(_ installed: InstalledPackage) throws {
		try store.saveInstalledExtension(InstalledExtension(id: installed.id, origin: .catalog, record: try JSONEncoder().encode(installed)))
	}

	/// Puts back the row that an install replaced, exactly as it was, or removes the row of a first install.
	public func restore(_ previous: InstalledExtension?, of id: String) throws {
		if let previous { try store.saveInstalledExtension(previous) } else { try store.removeInstalledExtension(id) }
	}
}
