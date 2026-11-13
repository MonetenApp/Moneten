import CryptoKit
import Domain
import ExtensionCatalog
import ExtensionConnector
import ExtensionHost
import Foundation
import Storage

/// The installed extensions and the catalog (ADR 0015): the accepted index, installs, updates, and
/// removals, and the connector of each refresh, built from files that passed their check just before.
@MainActor
@Observable
final class ExtensionLibrary {
	/// The address of the catalog and the keys of this build.
	struct Configuration {
		let source: CatalogSource
		let keys: CatalogKeys?

		/// The lowest index version that this build accepts while neither key has a floor (decision 23).
		static let lowestIndexVersion = 1

		static func standard() -> Configuration {
			#if PERF_HARNESS
			// The performance check shows a made-up index and never contacts the catalog.
			return Configuration(source: CatalogSource(base: URL(filePath: "/dev/null")), keys: nil)
			#else
			#if DEBUG
			let environment = ProcessInfo.processInfo.environment
			// Debug builds only: the live checks sign a local index with throwaway keys and serve it themselves.
			if let address = environment["MONETEN_CATALOG_URL"], let base = URL(string: address) {
				let paths = environment["MONETEN_CATALOG_KEYS"]?.components(separatedBy: ":") ?? []
				let pems = paths.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
				let keys = pems.count == 2 ? try? CatalogKeys(currentPEM: pems[0], nextPEM: pems[1], lowestVersion: lowestIndexVersion) : nil
				return Configuration(source: CatalogSource(base: base), keys: keys)
			}
			#endif
			let pems = ["current", "next"].compactMap { Bundle.main.url(forResource: $0, withExtension: "pub").flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
			let keys = pems.count == 2 ? try? CatalogKeys(currentPEM: pems[0], nextPEM: pems[1], lowestVersion: lowestIndexVersion) : nil
			return Configuration(source: CatalogSource(base: URL(string: "https://extensions.monetenapp.com/")!), keys: keys)
			#endif
		}
	}

	/// One row of the Extensions window.
	struct Item: Identifiable, Equatable {
		enum Section { case installed, available }
		enum Action: Equatable { case install, update, reviewUpdate, allow }

		let id: String
		let section: Section
		let name: String
		let description: String
		let version: String?
		let kinds: [String]
		/// "Installed 1.0", "Unverified", or "Blocked".
		let badge: String?
		/// What the user should know, such as a waiting update or the note of the catalog.
		let note: String?
		let action: Action?
		let manifest: Manifest?
		let isCatalog: Bool
	}

	/// What waits for the user's answer in the window.
	enum Question: Identifiable, Equatable {
		case fileWarning(url: URL, package: ExtensionPackage, name: String)
		case allow(name: String, package: ExtensionPackage)
		case review(id: String, name: String, version: String, hosts: [String], fields: [String])
		case remove(id: String, name: String, accounts: [String])

		var id: String {
			switch self {
			case let .fileWarning(_, _, name), let .allow(name, _): "file-\(name)"
			case let .review(id, _, _, _, _): "review-\(id)"
			case let .remove(id, _, _): "remove-\(id)"
			}
		}
	}

	private(set) var configuration = Configuration.standard()
	private(set) var index: CatalogIndex?
	/// Why the last download of the index was not used. The window shows it with the date of the index it keeps.
	private(set) var problem: String?
	/// False after a download of the index failed, which disables "Install".
	private(set) var reachable = true
	private(set) var items: [Item] = []
	private(set) var working: Set<String> = []
	var question: Question?
	/// The extension whose details the window shows.
	var selection: String?
	var failure: String?
	var automatic: Bool = UserDefaults.standard.object(forKey: Preference.updateExtensionsAutomatically) as? Bool ?? true {
		didSet {
			UserDefaults.standard.set(automatic, forKey: Preference.updateExtensionsAutomatically)
			Task { await applyUpdates() }
		}
	}

	@ObservationIgnored weak var model: AppModel?
	@ObservationIgnored var log: @MainActor @Sendable (String) -> Void = { _ in }
	/// The fixture that replaces the network for an installed extension, for the debug harness.
	@ObservationIgnored var fixtures: [String: Fixture] = [:]
	@ObservationIgnored private var indexData: Data?
	@ObservationIgnored private var floors = KeyFloors()
	@ObservationIgnored private var catalogInstalls: [String: InstalledPackage] = [:]
	@ObservationIgnored private var fileInstalls: [String: [String: String]] = [:]
	/// The updates that wait for the end of a session or for the user, by id.
	@ObservationIgnored private var updates: [String: UpdatePlan] = [:]
	/// Catalog packages whose files do not match, found by the last check.
	@ObservationIgnored private var changed: Set<String> = []
	@ObservationIgnored private var daily: Task<Void, Never>?

	private var folder: URL { DataFolder.standard().extensionsFolder }
	private var installer: Installer {
		Installer(folder: folder, staging: DataFolder.standard().root.appending(path: "Downloads"), fetch: configuration.source.fetcher)
	}

	// MARK: Opening

	/// Loads what the database knows, then downloads the index now and once a day while the database is open.
	func open(_ store: Store) {
		do {
			if let stored = try store.catalog() {
				indexData = stored.index
				index = try? CatalogIndex.parse(stored.index)
				floors = (try? JSONDecoder().decode(KeyFloors.self, from: stored.floors)) ?? KeyFloors()
				if let keys = configuration.keys { floors = floors.keeping(keys) }
			}
			for installed in try store.installedExtensions() {
				switch installed.origin {
				case .catalog: catalogInstalls[installed.id] = try? JSONDecoder().decode(InstalledPackage.self, from: installed.record)
				case .file: fileInstalls[installed.id] = try? JSONDecoder().decode([String: String].self, from: installed.record)
				}
			}
		} catch {
			failure = "The extensions could not be loaded. \(error)"
		}
		reload()
		daily = Task { [weak self] in
			while !Task.isCancelled {
				await self?.checkNow()
				try? await Task.sleep(for: .seconds(86_400))
			}
		}
	}

	func close() {
		daily?.cancel()
		daily = nil
		index = nil
		indexData = nil
		floors = KeyFloors()
		catalogInstalls = [:]
		fileInstalls = [:]
		updates = [:]
		changed = []
		items = []
		question = nil
		problem = nil
	}

	#if DEBUG
	/// Points the catalog at a local test index, for the live checks of the debug harness.
	func useCatalog(_ base: URL) {
		configuration = Configuration(source: CatalogSource(base: base), keys: configuration.keys)
	}
	#endif

	#if DEBUG || PERF_HARNESS
	/// Shows an index without a signature, for the performance check of the window.
	func show(_ index: CatalogIndex) {
		self.index = index
		reload()
	}
	#endif

	// MARK: The index

	/// Downloads the index and its signature, and uses the index only when it passes every check.
	func checkNow() async {
		guard let store = model?.store else { return }
		guard let keys = configuration.keys else {
			problem = "This build of Moneten has no catalog keys, so it cannot show the catalog."
			return reload()
		}
		let source = configuration.source
		let data: Data, signature: Data
		do {
			data = try await source.fetch("index.json")
			signature = try await source.fetch("index.json.sig")
		} catch {
			reachable = false
			problem = "The catalog cannot be reached."
			log("ext catalog unreachable")
			return reload()
		}
		reachable = true
		do {
			if let accepted = try IndexVerifier.check(index: data, signature: signature, keys: keys, floors: floors, accepted: indexData) {
				try store.saveCatalog(StoredCatalog(index: data, floors: try JSONEncoder().encode(accepted.floors)))
				indexData = data
				index = accepted.index
				floors = accepted.floors
				log("ext catalog accepted version=\(accepted.index.version)")
			} else {
				log("ext catalog unchanged version=\(index?.version ?? 0)")
			}
			problem = nil
		} catch let error as CatalogError {
			problem = error.description
			log("ext catalog rejected \(error.description) kept=\(index?.version ?? 0)")
		} catch {
			problem = "The list of extensions could not be saved. \(error)"
		}
		reload()
		await applyUpdates()
	}

	// MARK: Installing and updating

	func install(_ id: String) async {
		guard reachable, let entry = index?.entry(id), entry.status == .active || entry.status == .unmaintained else { return }
		await download(entry)
	}

	/// Installs every update that may install by itself now, and records the others for the window.
	func applyUpdates() async {
		guard let index else { return }
		for (id, installed) in catalogInstalls {
			guard let entry = index.entry(id), entry.status == .active || entry.status == .unmaintained, let available = try? entry.manifest.get(),
				let current = try? Installer.load(installed, from: folder).manifest else {
				updates[id] = nil
				continue
			}
			let plan = UpdatePlan(installed: current, available: available, automatic: automatic, sessionRuns: sessionRuns(id))
			updates[id] = plan == .upToDate || plan == .install ? nil : plan
			if plan == .install, !working.contains(id) { await download(entry) }
		}
		reload()
	}

	/// Installs the waiting update after the user confirmed it or chose "Update".
	func update(_ id: String) async {
		guard let entry = index?.entry(id) else { return }
		if sessionRuns(id) {
			updates[id] = .afterSession
			return reload()
		}
		await download(entry)
	}

	/// Called when a refresh ended: an update that waited for the end of its session installs now.
	func sessionEnded() {
		guard updates.values.contains(.afterSession) else { return }
		Task { await applyUpdates() }
	}

	private func download(_ entry: CatalogIndex.Entry) async {
		guard let store = model?.store else { return }
		working.insert(entry.id)
		reload()
		defer {
			working.remove(entry.id)
			reload()
		}
		do {
			let installed = try await installer.install(entry)
			try store.saveInstalledExtension(InstalledExtension(id: installed.id, origin: .catalog, record: try JSONEncoder().encode(installed)))
			catalogInstalls[installed.id] = installed
			fileInstalls[installed.id] = nil
			updates[installed.id] = nil
			changed.remove(installed.id)
			log("ext installed \(installed.id) version=\(installed.version)")
		} catch {
			failure = "\(entry.name) could not be installed. \(error)"
			log("ext install failed \(entry.id) \(error)")
		}
	}

	// MARK: Files

	/// Reads a `.lua` file or a package folder that the user picked, and asks with the warning for files.
	func pickFile(_ url: URL) {
		do {
			let package = try ExtensionPackage.load(from: url)
			guard catalogInstalls[package.name] == nil else {
				failure = "A catalog extension with the name \(package.name) is installed. Remove it first."
				return
			}
			question = .fileWarning(url: url, package: package, name: package.name)
		} catch {
			failure = "\(url.lastPathComponent) is not an extension. \(error)"
		}
	}

	/// Copies the extension into the folder after the user agreed to the warning, and marks it "Unverified".
	func installFile(_ url: URL, name: String) {
		let fm = FileManager.default
		let target = folder.appending(path: url.pathExtension == "lua" ? "\(name).lua" : name)
		do {
			try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
			for source in Self.files(of: url) {
				let destination = url.pathExtension == "lua" ? folder.appending(path: source.lastPathComponent) : target.appending(path: source.lastPathComponent)
				try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
				if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
				try fm.copyItem(at: source, to: destination)
			}
			allow(name)
		} catch {
			failure = "\(name) could not be installed. \(error)"
		}
	}

	/// Records the files that the user saw in the warning. A later change asks again.
	func allow(_ name: String) {
		guard let store = model?.store, let digests = Self.digests(of: fileURL(name)) else { return }
		do {
			try store.saveInstalledExtension(InstalledExtension(id: name, origin: .file, record: try JSONEncoder().encode(digests)))
			fileInstalls[name] = digests
			log("ext allowed \(name) unverified")
		} catch {
			failure = "\(name) could not be allowed. \(error)"
		}
		reload()
	}

	// MARK: Questions

	/// Opens the confirmation of an update that adds hosts or login fields.
	func review(_ id: String) {
		guard case let .needsConfirmation(hosts, fields)? = updates[id], let item = items.first(where: { $0.id == id }), let version = index?.entry(id)?.version else { return }
		question = .review(id: id, name: item.name, version: version, hosts: hosts, fields: fields)
	}

	/// Shows the warning for files again before a copied or changed file install runs.
	func askAllow(_ name: String) {
		guard let url = existingFileURL(name) else { return }
		do {
			question = .allow(name: name, package: try ExtensionPackage.load(from: url))
		} catch {
			failure = "\(name) is not usable. \(error)"
		}
	}

	func confirm(_ question: Question) {
		switch question {
		case let .fileWarning(url, _, name): installFile(url, name: name)
		case let .allow(name, _): allow(name)
		case let .review(id, _, _, _, _): Task { await update(id) }
		case let .remove(id, _, _): remove(id)
		}
	}

	// MARK: Removing

	/// Asks before the removal and names the accounts that use the extension.
	func askRemove(_ id: String) {
		guard let item = items.first(where: { $0.id == id && $0.section == .installed }) else { return }
		question = .remove(id: id, name: item.name, accounts: accounts(using: id).map(\.name).sorted())
	}

	func remove(_ id: String) {
		guard let store = model?.store else { return }
		do {
			let url = fileURL(id)
			if catalogInstalls[id] != nil {
				try installer.remove(id)
			} else {
				// A file install goes to the Trash, so the user can get a self-written script back.
				for file in url.pathExtension == "lua" ? Self.files(of: url) : [url] { try FileManager.default.trashItem(at: file, resultingItemURL: nil) }
			}
			try store.removeInstalledExtension(id)
			model?.extensionConnectors[id] = nil
			catalogInstalls[id] = nil
			fileInstalls[id] = nil
			updates[id] = nil
			changed.remove(id)
			log("ext removed \(id)")
		} catch {
			failure = "\(id) could not be removed. \(error)"
		}
		reload()
	}

	// MARK: Sessions

	/// A connector for the next session of an installed extension, from files checked just now, or one
	/// that fails each account with the reason the extension does not run. Nil when nothing with this id is installed.
	func connector(for id: String) -> (any BankConnector)? {
		guard let model else { return nil }
		do {
			let package = try verifiedPackage(id)
			let log = log
			return model.makeExtensionConnector(package, fixture: fixtures[id]) { line in
				if case let .print(text) = line { Task { @MainActor in log("ext print \(id): \(text)") } }
			}
		} catch let stop as StoppedExtension {
			return stop
		} catch {
			return nil
		}
	}

	/// The package of an installed extension, checked against the index or against what the user allowed.
	func verifiedPackage(_ id: String) throws -> ExtensionPackage {
		if let installed = catalogInstalls[id] {
			if let index, case let .stopped(reason) = Standing(of: installed, in: index) {
				log("ext stopped \(id) \(reason)")
				throw StoppedExtension(message: reason)
			}
			do {
				let package = try Installer.load(installed, from: folder)
				if changed.remove(id) != nil { reload() }
				log("ext run \(id) version=\(installed.version)")
				return package
			} catch {
				changed.insert(id)
				reload()
				log("ext stopped \(id) \(error)")
				throw StoppedExtension(message: "\(error)")
			}
		}
		guard let url = existingFileURL(id) else { throw CocoaError(.fileNoSuchFile) }
		guard let allowed = fileInstalls[id], Self.digests(of: url) == allowed else {
			reload()
			throw StoppedExtension(message: "\(id) is not allowed to run. Allow it in the Extensions window.")
		}
		let package = try ExtensionPackage.load(from: url)
		log("ext run \(id) unverified")
		return package
	}

	private func sessionRuns(_ id: String) -> Bool {
		guard let model else { return false }
		return model.accesses.values.contains { $0.source == .extension(id: id) && model.sync.states[$0.id]?.isRunning == true }
	}

	private func accounts(using id: String) -> [Account] {
		guard let model else { return [] }
		return model.ledger.accounts.filter { account in account.accessID.flatMap { model.accesses[$0] }?.source == .extension(id: id) }
	}

	// MARK: The rows

	/// Lists the folder again and builds the rows of the window.
	func reload() {
		let names = installedNames()
		var installed: [Item] = []
		for name in names {
			if let record = catalogInstalls[name] {
				installed.append(catalogItem(record))
			} else {
				installed.append(fileItem(name))
			}
		}
		let available = (index?.entries ?? []).filter { !names.contains($0.id) }.map(availableItem)
		items = installed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
			+ available.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	private func catalogItem(_ record: InstalledPackage) -> Item {
		let entry = index?.entry(record.id)
		let manifest = try? Installer.load(record, from: folder).manifest
		var note: String?
		var action: Item.Action?
		var badge = "Installed \(record.version)"
		if working.contains(record.id) {
			badge = "Installing..."
		} else if changed.contains(record.id) || manifest == nil {
			badge = "Changed"
			note = CatalogError.changed(record.name).description
		} else if let index, case let .stopped(reason) = Standing(of: record, in: index) {
			badge = entry?.status == .blocked ? "Blocked" : entry?.status == .withdrawn ? "Withdrawn" : "Stopped"
			note = reason
		} else {
			if let index, case let .runs(unmaintained?) = Standing(of: record, in: index) { note = unmaintained }
			let version = entry?.version ?? ""
			switch updates[record.id] {
			case let .needsConfirmation(hosts, fields)?:
				note = Self.newRights(version: version, hosts: hosts, fields: fields)
				action = .reviewUpdate
			case .waitsForUser?:
				note = "Version \(version) is available."
				action = .update
			case .afterSession?:
				note = "Version \(version) installs when the running refresh ends."
			default: break
			}
		}
		return Item(id: record.id, section: .installed, name: record.name, description: manifest?.description ?? "", version: record.version,
			kinds: manifest?.kinds?.map(\.rawValue) ?? [], badge: badge, note: note, action: action, manifest: manifest, isCatalog: true)
	}

	private func fileItem(_ name: String) -> Item {
		let package = existingFileURL(name).flatMap { try? ExtensionPackage.load(from: $0) }
		let allowed = existingFileURL(name).flatMap(Self.digests) == fileInstalls[name] && fileInstalls[name] != nil
		return Item(id: name, section: .installed, name: package?.manifest?.name ?? name, description: package?.manifest?.description ?? "",
			version: package?.manifest?.version, kinds: package?.manifest?.kinds?.map(\.rawValue) ?? [], badge: "Unverified",
			note: allowed ? nil : "Moneten runs \(name) only after you allow it.", action: allowed ? nil : .allow, manifest: package?.manifest, isCatalog: false)
	}

	private func availableItem(_ entry: CatalogIndex.Entry) -> Item {
		let manifest = try? entry.manifest.get()
		var note: String?
		switch entry.manifest {
		case let .failure(problem): note = "Not installable, because its manifest is incomplete. \(problem.message)"
		case .success: if let text = entry.note { note = text }
		}
		let installable = manifest != nil && (entry.status == .active || entry.status == .unmaintained)
		return Item(id: entry.id, section: .available, name: entry.name, description: manifest?.description ?? "", version: entry.version,
			kinds: manifest?.kinds?.map(\.rawValue) ?? [], badge: working.contains(entry.id) ? "Installing..." : entry.status == .active ? nil : entry.status.rawValue.capitalized,
			note: note, action: installable ? .install : nil, manifest: manifest, isCatalog: true)
	}

	static func newRights(version: String, hosts: [String], fields: [String]) -> String {
		var parts: [String] = []
		if !hosts.isEmpty { parts.append("also contacts \(hosts.formatted(.list(type: .and)))") }
		if !fields.isEmpty { parts.append("asks also for \(fields.formatted(.list(type: .and)))") }
		return "Version \(version) \(parts.joined(separator: " and "))"
	}

	/// The names of the extensions in the folder: each `.lua` file by its base name and each folder.
	private func installedNames() -> [String] {
		let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
		return urls.compactMap { url in
			if url.pathExtension == "lua" { return url.deletingPathExtension().lastPathComponent }
			return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url.lastPathComponent : nil
		}
	}

	private func fileURL(_ name: String) -> URL {
		existingFileURL(name) ?? folder.appending(path: "\(name).lua")
	}

	private func existingFileURL(_ name: String) -> URL? {
		[folder.appending(path: "\(name).lua"), folder.appending(path: name)].first { FileManager.default.fileExists(atPath: $0.path) }
	}

	/// The files of a file install: the `.lua` file and its manifest next to it, or every file of the folder.
	static func files(of url: URL) -> [URL] {
		if url.pathExtension == "lua" {
			let manifest = url.deletingPathExtension().appendingPathExtension("json")
			return [url] + (FileManager.default.fileExists(atPath: manifest.path) ? [manifest] : [])
		}
		return ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []).sorted { $0.path < $1.path }
	}

	/// The SHA-256 of each file of a file install by its name. A change of any of them asks the user again.
	static func digests(of url: URL) -> [String: String]? {
		var digests: [String: String] = [:]
		for file in files(of: url) {
			guard let data = try? Data(contentsOf: file) else { return nil }
			digests[file.lastPathComponent] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		}
		return digests.isEmpty ? nil : digests
	}
}

/// A connector for an installed extension that may not run. Each account of the refresh shows the reason.
struct StoppedExtension: BankConnector, Error {
	let message: String

	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		throw SyncFailure.unsupported(message)
	}
}

/// Gets the files of the catalog. A request carries no query, no cookie, and nothing that names the
/// user or the Mac, and the app asks for the whole index, so the catalog cannot tell which extensions are installed.
struct CatalogSource: Sendable {
	let base: URL

	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
		configuration.httpAdditionalHeaders = ["User-Agent": "Moneten"]
		return URLSession(configuration: configuration)
	}()

	var fetcher: @Sendable (String) async throws -> Data {
		{ [base] path in
			let url = base.appending(path: path)
			if url.isFileURL { return try Data(contentsOf: url) }
			let (data, response) = try await Self.session.data(from: url)
			guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
			return data
		}
	}

	func fetch(_ path: String) async throws -> Data {
		try await fetcher(path)
	}
}
