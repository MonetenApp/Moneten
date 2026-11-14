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
			NSLog("Catalog keys %@", keys == nil ? "missing" : "loaded")
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
		/// The version that "Update" or "Install" installs.
		let available: String?
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
	/// Nil when neither the stored floors nor the accepted index can be read. The app then accepts no index.
	@ObservationIgnored private var floors: KeyFloors? = KeyFloors()
	/// The origin of each installed extension, by name.
	@ObservationIgnored private var records: [String: InstalledOrigin] = [:]
	/// The waiting updates, the confirmed versions, and the changed packages.
	@ObservationIgnored private var updateState = UpdateState()
	/// What waited for a package while its new version is placed, for a placement that fails.
	@ObservationIgnored private var savedUpdates: [String: UpdateState.Saved] = [:]
	/// The downloads that run, so that a removal can stop them.
	@ObservationIgnored private var downloads: [String: InstallCancellation] = [:]
	@ObservationIgnored private var daily: Task<Void, Never>?

	private var folder: URL { DataFolder.standard().extensionsFolder }
	private var staging: URL { DataFolder.standard().root.appending(path: "Downloads") }
	private var installer: Installer {
		let source = configuration.source
		return Installer(folder: folder, staging: staging) { path, limit in try await source.fetch(path, limit: limit) }
	}

	// MARK: Opening

	/// Loads what the database knows, then downloads the index now and once a day while the database is open.
	func open(_ store: Store) {
		do {
			if let stored = try store.catalog() {
				indexData = stored.index
				index = try? CatalogIndex.parse(stored.index)
				if let keys = configuration.keys {
					floors = KeyFloors.restored(stored.floors, index: stored.index, signature: stored.signature, keys: keys)
				}
			}
			for installed in try store.installedExtensions() {
				records[installed.id] = InstalledOrigin(catalog: installed.origin == .catalog, record: installed.record)
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
		for download in downloads.values { download.cancel() }
		downloads = [:]
		index = nil
		indexData = nil
		floors = KeyFloors()
		records = [:]
		updateState = UpdateState()
		savedUpdates = [:]
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
		guard let floors else {
			problem = "Moneten cannot read the versions of the catalog that it accepted before, so it accepts no new list of extensions."
			return reload()
		}
		let source = configuration.source
		let data: Data, signature: Data
		do {
			data = try await source.fetch("index.json", limit: CatalogSource.indexLimit)
			signature = try await source.fetch("index.json.sig", limit: CatalogSource.signatureSize)
		} catch {
			reachable = false
			problem = (error as? CatalogError)?.description ?? "The catalog cannot be reached."
			log("ext catalog unreachable \(error)")
			return reload()
		}
		reachable = true
		do {
			if let accepted = try IndexVerifier.check(index: data, signature: signature, keys: keys, floors: floors, accepted: indexData) {
				try store.saveCatalog(StoredCatalog(index: data, signature: signature, floors: try JSONEncoder().encode(accepted.floors)))
				indexData = data
				index = accepted.index
				self.floors = accepted.floors
				log("ext catalog accepted version=\(accepted.index.version)")
				stopSessionsOfStoppedPackages()
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

	/// A blocked or withdrawn package stops at once: its running and waiting refreshes end.
	private func stopSessionsOfStoppedPackages() {
		guard let index else { return }
		for case let (id, .catalog(installed)) in records {
			if case .stopped = Standing(of: installed, in: index) { cancelSessions(of: id) }
		}
	}

	// MARK: Installing and updating

	func install(_ id: String) async {
		guard reachable, let entry = index?.entry(id), entry.status == .active || entry.status == .unmaintained else { return }
		if records[id] == nil, FileInstall.url(of: id, in: folder) != nil {
			failure = "The Extensions folder holds a file install named \(id). Remove it before you install \(entry.name) from the catalog."
			return
		}
		await download(entry)
	}

	/// Installs every update that may install by itself now, and records the others for the window.
	func applyUpdates() async {
		guard let index else { return }
		for case let (id, .catalog(installed)) in records {
			guard let entry = index.entry(id), entry.status == .active || entry.status == .unmaintained, let available = try? entry.manifest.get(),
				let current = try? Installer.load(installed, from: folder).manifest else {
				updateState.plans[id] = nil
				continue
			}
			let plan = UpdatePlan(installed: current, available: available, automatic: automatic, sessionRuns: sessionRuns(id), confirmed: updateState.confirmed[id])
			updateState.plans[id] = plan == .upToDate || plan == .install ? nil : plan
			if plan == .install, !working.contains(id) { await download(entry) }
		}
		reload()
	}

	/// Installs `version` after the user confirmed it or chose "Update". A version that is not the one of
	/// the index, or that asks for rights the user did not confirm, goes to the confirmation instead.
	func update(_ id: String, to version: String) async {
		guard let entry = index?.entry(id), let available = try? entry.manifest.get(), case let .catalog(installed)? = records[id],
			let current = try? Installer.load(installed, from: folder).manifest else { return reload() }
		let plan = UpdatePlan(installed: current, available: available, automatic: automatic, sessionRuns: sessionRuns(id), confirmed: version)
		updateState.plans[id] = plan == .upToDate || plan == .install ? nil : plan
		switch plan {
		case .install:
			updateState.confirmed[id] = version
			await download(entry)
		case .afterSession:
			updateState.confirmed[id] = version
			reload()
		case .needsConfirmation, .waitsForUser:
			failure = "Version \(entry.version ?? "") of \(entry.name) is not the version you chose. Review it again."
			reload()
			review(id)
		case .upToDate:
			reload()
		}
	}

	/// Called when a refresh ended: an update that waited for the end of its session installs now.
	func sessionEnded() {
		guard updateState.plans.values.contains(.afterSession) else { return }
		Task { await applyUpdates() }
	}

	private func download(_ entry: CatalogIndex.Entry) async {
		guard let store = model?.store else { return }
		let id = entry.id
		let canceled = InstallCancellation()
		downloads[id] = canceled
		working.insert(id)
		reload()
		defer {
			if downloads[id] === canceled { downloads[id] = nil }
			working.remove(id)
			reload()
		}
		let records = CatalogRecords(store: store)
		let previous: InstalledExtension?
		do {
			previous = try records.row(of: id)
		} catch {
			failure = "\(entry.name) could not be installed, because Moneten cannot read its record. \(error)"
			return
		}
		do {
			// The commit runs on the main actor with the move, so a Remove comes before or after all of it.
			let installed = try await installer.install(entry, canceled: canceled, commit: { [weak self] installed in
				try records.save(installed)
				guard let self else { return }
				self.records[id] = .catalog(installed)
				self.savedUpdates[id] = self.updateState.clear(id)
			}, restore: { [weak self] in
				try records.restore(previous, of: id)
				guard let self else { return }
				self.records[id] = previous.map { InstalledOrigin(catalog: $0.origin == .catalog, record: $0.record) }
				if let saved = self.savedUpdates.removeValue(forKey: id) { self.updateState.restore(saved, of: id) }
			})
			savedUpdates[id] = nil
			log("ext installed \(id) version=\(installed.version)")
		} catch {
			if case .removed = error { return log("ext install stopped \(id) \(error)") }
			failure = "\(error)"
			log("ext install failed \(id) \(error)")
		}
	}

	// MARK: Files

	/// Reads a `.lua` file or a package folder that the user picked, and asks with the warning for files.
	func pickFile(_ url: URL) {
		do {
			let package = try FileInstall.load(url).package
			guard !isCatalog(package.name) else {
				failure = "A catalog extension with the name \(package.name) is installed. Remove it first."
				return
			}
			question = .fileWarning(url: url, package: package, name: package.name)
		} catch {
			failure = "\(url.lastPathComponent) is not an extension. \(error)"
		}
	}

	/// Copies the extension into the folder after the user agreed to the warning, and marks it "Unverified".
	/// An installed file of the same name stays until every file of the new one is in place.
	func installFile(_ url: URL, name: String, shown: ExtensionPackage) {
		guard !isCatalog(name) else {
			failure = "A catalog extension with the name \(name) is installed. Remove it first."
			return
		}
		do {
			_ = try FileInstall.install(url, into: folder, staging: staging)
		} catch {
			failure = "\(name) could not be installed. \(error)"
			return reload()
		}
		allow(name, shown: shown)
	}

	/// Records the bytes of the files that the user saw in the warning. A session runs only those bytes,
	/// and a later change asks again.
	func allow(_ name: String, shown: ExtensionPackage) {
		guard let store = model?.store else { return }
		guard !isCatalog(name) else {
			failure = "\(name) is a catalog extension. It runs only with the files of the catalog."
			return reload()
		}
		guard let url = FileInstall.url(of: name, in: folder) else { return reload() }
		let loaded: FileInstall.Loaded
		do {
			loaded = try FileInstall.load(url)
		} catch {
			failure = "\(name) cannot be allowed. \(error)"
			return reload()
		}
		guard loaded.package == shown else {
			failure = "\(name) changed after the warning. Allow it again."
			return reload()
		}
		do {
			try store.saveInstalledExtension(InstalledExtension(id: name, origin: .file, record: try JSONEncoder().encode(loaded.digests)))
			records[name] = .file(allowed: loaded.digests)
			log("ext allowed \(name) unverified")
		} catch {
			failure = "\(name) could not be allowed. \(error)"
		}
		reload()
	}

	func isInstalled(_ id: String) -> Bool {
		records[id] != nil
	}

	private func isCatalog(_ name: String) -> Bool {
		switch records[name] {
		case .catalog?, .unreadableCatalog?: true
		case .file?, nil: false
		}
	}

	// MARK: Questions

	/// Opens the confirmation of an update that adds hosts or login fields.
	func review(_ id: String) {
		guard case let .catalog(installed)? = records[id], let item = items.first(where: { $0.id == id }), let manifest = item.manifest,
			case let .needsConfirmation(hosts, fields)? = updateState.plan(of: installed, manifest: manifest, in: index), let version = index?.entry(id)?.version else { return }
		question = .review(id: id, name: item.name, version: version, hosts: hosts, fields: fields)
	}

	/// Shows the warning for files again before a copied or changed file install runs.
	func askAllow(_ name: String) {
		guard let url = FileInstall.url(of: name, in: folder) else { return }
		do {
			question = .allow(name: name, package: try FileInstall.load(url).package)
		} catch {
			failure = "\(name) is not usable. \(error)"
		}
	}

	func confirm(_ question: Question) {
		switch question {
		case let .fileWarning(url, package, name): installFile(url, name: name, shown: package)
		case let .allow(name, package): allow(name, shown: package)
		case let .review(id, _, version, _, _): Task { await update(id, to: version) }
		case let .remove(id, _, _): remove(id)
		}
	}

	// MARK: Removing

	/// Asks before the removal and names the accounts that use the extension.
	func askRemove(_ id: String) {
		guard !working.contains(id), let item = items.first(where: { $0.id == id && $0.section == .installed }) else { return }
		question = .remove(id: id, name: item.name, accounts: accounts(using: id).map(\.name).sorted())
	}

	/// Removes an extension. It waits for no install: an extension that is being installed or updated
	/// cannot be removed until the install ends, also when the dialog opened before the install started.
	func remove(_ id: String) {
		guard let store = model?.store else { return }
		guard !working.contains(id) else {
			failure = "\(id) is being installed. Remove it after the install."
			return reload()
		}
		downloads[id]?.cancel()
		cancelSessions(of: id)
		do {
			if isCatalog(id) {
				try installer.remove(id)
			} else if let url = FileInstall.url(of: id, in: folder) {
				// A file install goes to the Trash, so the user can get a self-written script back.
				let manifest = url.deletingPathExtension().appendingPathExtension("json")
				for file in url.pathExtension == "lua" && FileManager.default.fileExists(atPath: manifest.path) ? [url, manifest] : [url] {
					try FileManager.default.trashItem(at: file, resultingItemURL: nil)
				}
			}
			try store.removeInstalledExtension(id)
			model?.extensionConnectors[id] = nil
			records[id] = nil
			_ = updateState.clear(id)
			log("ext removed \(id)")
		} catch {
			failure = "\(id) could not be removed. \(error)"
		}
		reload()
	}

	// MARK: Sessions

	/// A connector for the sessions of an installed extension. It checks the files and the state in the
	/// index when each session starts, so a refresh that waited behind others does not run an extension
	/// that was blocked or removed meanwhile. Nil when nothing with this id is installed.
	func connector(for id: String) -> (any BankConnector)? {
		guard records[id] != nil || FileInstall.url(of: id, in: folder) != nil else { return nil }
		return CheckedAtStart { [weak self] in
			try await MainActor.run {
				guard let self, let model = self.model else { throw CancellationError() }
				let package = try self.verifiedPackage(id)
				let log = self.log
				guard let connector = model.makeExtensionConnector(package, fixture: self.fixtures[id], log: { line in
					if case let .print(text) = line { Task { @MainActor in log("ext print \(id): \(text)") } }
				}) else { throw CancellationError() }
				return connector
			}
		}
	}

	/// The package of an installed extension, checked against the index or against what the user
	/// allowed. Throws the reason that the accounts of the extension show.
	func verifiedPackage(_ id: String) throws(SyncFailure) -> ExtensionPackage {
		switch records[id] {
		case let .catalog(installed)?:
			if let index {
				switch Standing(of: installed, in: index) {
				case let .stopped(reason), let .outdated(reason):
					log("ext stopped \(id) \(reason)")
					throw .unsupported(reason)
				case .runs: break
				}
			}
			do {
				let package = try Installer.load(installed, from: folder)
				if updateState.changed.remove(id) != nil { reload() }
				log("ext run \(id) version=\(installed.version)")
				return package
			} catch {
				updateState.changed.insert(id)
				reload()
				log("ext stopped \(id) \(error)")
				throw .unsupported(error.description)
			}
		case .unreadableCatalog?:
			throw .unsupported("Moneten cannot read the record of \(id). Remove it and install it again from the catalog.")
		case let .file(allowed)?:
			guard let url = FileInstall.url(of: id, in: folder) else { throw .unsupported("The extension \(id) is not installed.") }
			do {
				let package = try FileInstall.load(url, allowed: allowed)
				log("ext run \(id) unverified")
				return package
			} catch {
				reload()
				throw .unsupported(error.description)
			}
		case nil:
			guard FileInstall.url(of: id, in: folder) != nil else { throw .unsupported("The extension \(id) is not installed.") }
			throw .unsupported(CatalogError.notAllowed(id).description)
		}
	}

	/// The services that the add account assistant offers under "Other": those of catalog packages that
	/// may run, and of file installs that the user allowed.
	/// Kept with the rows, so the assistant reads it without checking files on each render.
	private(set) var setupServices: [(id: String, service: String)] = []

	private func listSetupServices() -> [(id: String, service: String)] {
		FileInstall.names(in: folder).flatMap { id -> [(id: String, service: String)] in
			guard let package = mayRun(id) else { return [] }
			return FileInstall.services(of: package).map { (id, $0) }
		}
	}

	/// The package when the extension may run now, without logging a run.
	private func mayRun(_ id: String) -> ExtensionPackage? {
		switch records[id] {
		case let .catalog(installed)?:
			if let index { guard case .runs = Standing(of: installed, in: index) else { return nil } }
			return try? Installer.load(installed, from: folder)
		case let .file(allowed)?:
			return FileInstall.url(of: id, in: folder).flatMap { try? FileInstall.load($0, allowed: allowed) }
		case .unreadableCatalog?, nil:
			return nil
		}
	}

	/// Cancels every running and waiting refresh and setup of the extension, also a setup whose access the app does not have yet.
	private func cancelSessions(of id: String) {
		model?.sync.cancelRefreshes(of: .extension(id: id))
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

	/// Lists the folder again and builds the rows of the window, one for each name.
	func reload() {
		setupServices = listSetupServices()
		let names = FileInstall.names(in: folder)
		let installed = names.map { name -> Item in
			switch records[name] {
			case let .catalog(record)?: catalogItem(record)
			case .unreadableCatalog?: unreadableItem(name)
			case .file?, nil: fileItem(name)
			}
		}
		let available = (index?.entries ?? []).filter { !names.contains($0.id) }.map(availableItem)
		items = installed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
			+ available.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	private func catalogItem(_ record: InstalledPackage) -> Item {
		let entry = index?.entry(record.id)
		let manifest = try? Installer.load(record, from: folder).manifest
		let standing = index.map { Standing(of: record, in: $0) } ?? .runs(note: nil)
		var note: String?
		var action: Item.Action?
		var badge = "Installed \(record.version)"
		if working.contains(record.id) {
			badge = "Installing..."
		} else if updateState.changed.contains(record.id) || manifest == nil {
			badge = "Changed"
			note = CatalogError.changed(record.name).description
		} else if case let .stopped(reason) = standing {
			badge = entry?.status == .blocked ? "Blocked" : entry?.status == .withdrawn ? "Withdrawn" : "Stopped"
			note = reason
		} else {
			if case let .runs(unmaintained?) = standing { note = unmaintained }
			if case let .outdated(reason) = standing {
				badge = "Update Needed"
				note = reason
			}
			let version = entry?.version ?? ""
			switch manifest.flatMap({ updateState.plan(of: record, manifest: $0, in: index) }) {
			case let .needsConfirmation(hosts, fields)?:
				note = [note, Self.newRights(version: version, hosts: hosts, fields: fields)].compactMap { $0 }.joined(separator: " ")
				action = .reviewUpdate
			case .waitsForUser?:
				note = [note, "Version \(version) is available."].compactMap { $0 }.joined(separator: " ")
				action = .update
			case .afterSession?:
				note = [note, "Version \(version) installs when the running refresh ends."].compactMap { $0 }.joined(separator: " ")
			default: break
			}
		}
		return Item(id: record.id, section: .installed, name: record.name, description: manifest?.description ?? "", version: record.version,
			available: entry?.version, kinds: manifest?.kinds?.map(\.rawValue) ?? [], badge: badge, note: note, action: action, manifest: manifest, isCatalog: true)
	}

	private func unreadableItem(_ name: String) -> Item {
		Item(id: name, section: .installed, name: name, description: "", version: nil, available: nil, kinds: [], badge: "Changed",
			note: "Moneten cannot read the record of \(name). Remove it and install it again from the catalog.", action: nil, manifest: nil, isCatalog: true)
	}

	private func fileItem(_ name: String) -> Item {
		let url = FileInstall.url(of: name, in: folder)
		let loaded = url.flatMap { try? FileInstall.load($0) }
		var allowed = false
		if case let .file(digests)? = records[name], let loaded, !digests.isEmpty, loaded.digests == digests { allowed = true }
		let manifest = loaded?.package.manifest
		let note = loaded == nil ? "\(name) cannot be read as an extension." : allowed ? nil : "Moneten runs \(name) only after you allow it."
		return Item(id: name, section: .installed, name: manifest?.name ?? name, description: manifest?.description ?? "", version: manifest?.version, available: nil,
			kinds: manifest?.kinds?.map(\.rawValue) ?? [], badge: "Unverified", note: note, action: allowed || loaded == nil ? nil : .allow, manifest: manifest, isCatalog: false)
	}

	private func availableItem(_ entry: CatalogIndex.Entry) -> Item {
		let manifest = try? entry.manifest.get()
		var note: String?
		switch entry.manifest {
		case let .failure(problem): note = "Not installable, because its manifest is incomplete. \(problem.message)"
		case .success: if let text = entry.note { note = text }
		}
		let installable = manifest != nil && (entry.status == .active || entry.status == .unmaintained)
		return Item(id: entry.id, section: .available, name: entry.name, description: manifest?.description ?? "", version: entry.version, available: entry.version,
			kinds: manifest?.kinds?.map(\.rawValue) ?? [], badge: working.contains(entry.id) ? "Installing..." : entry.status == .active ? nil : entry.status.rawValue.capitalized,
			note: note, action: installable ? .install : nil, manifest: manifest, isCatalog: true)
	}

	static func newRights(version: String, hosts: [String], fields: [String]) -> String {
		var parts: [String] = []
		if !hosts.isEmpty { parts.append("also contacts \(hosts.formatted(.list(type: .and)))") }
		if !fields.isEmpty { parts.append("asks also for \(fields.formatted(.list(type: .and)))") }
		return "Version \(version) \(parts.joined(separator: " and "))"
	}
}
