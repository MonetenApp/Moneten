import Domain
import FinTS
import SwiftUI

/// The window of "Supported Banks..." in the Help menu: the services of the installed extensions and the
/// banks that the app reaches through FinTS, each with its access method and its note
/// (add-account-setup, "List of supported banks"). The bank directory comes from the FinTS helper once
/// per opening. Its chrome keeps the system materials (ADR 0012).
struct SupportedBanksWindow: View {
	@Environment(AppModel.self) private var model
	@State private var search = ""
	@FocusState private var searching: Bool
	@State private var directory: Result<BankDirectory, any Error>?
	/// The rows for `search`, which a search of the whole directory computes off the main thread.
	@State private var shown: (services: [SupportedBanks.Service], banks: [BankDirectory.Entry]) = ([], [])

	/// The list shows this many banks, so that the window stays quick. A longer list asks for more of the name.
	private static let shownBanks = 500

	var body: some View {
		VStack(spacing: 0) {
			TextField("Search Banks", text: $search, prompt: Text("Name, place, or Bankleitzahl"))
				.textFieldStyle(.roundedBorder)
				.focused($searching)
				.padding(10)
			content
		}
		.frame(minWidth: 520, minHeight: 420)
		.task {
			searching = true
			await load()
		}
		// The rows change with the search, the services, and the directory once it is loaded.
		.task(id: [search, directory == nil ? "" : "loaded"] + services.map(\.id)) { await match() }
	}

	@ViewBuilder private var content: some View {
		switch directory {
		case nil:
			ProgressView("Loading the bank directory...")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		case let .failure(error)?:
			ContentUnavailableView("Could not load the bank directory", systemImage: "exclamationmark.triangle",
				description: Text((error as? SyncFailure)?.message ?? error.localizedDescription))
		case .success?:
			if shown.services.isEmpty, shown.banks.isEmpty {
				ContentUnavailableView.search(text: search)
			} else {
				List {
					if !shown.services.isEmpty {
						Section("Extensions") {
							ForEach(shown.services) { row(name: $0.name, detail: nil, method: $0.extensionName, note: nil) }
						}
					}
					if !shown.banks.isEmpty {
						Section(shown.banks.count > Self.shownBanks ? "Banks (\(shown.banks.count), type more to narrow the list)" : "Banks") {
							ForEach(shown.banks.prefix(Self.shownBanks)) { bank in
								row(name: bank.bank.name, detail: [bank.city, bank.code].filter { !$0.isEmpty }.joined(separator: " · "),
									method: SupportedBanks.fintsMethod, note: bank.loginHint?.help)
							}
						}
					}
				}
			}
		}
	}

	private func row(name: String, detail: String?, method: String, note: String?) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack(alignment: .firstTextBaseline) {
				Text(name)
				Spacer()
				Text(method).font(.callout).foregroundStyle(.secondary)
			}
			if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
			if let note { Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
		}
		.padding(.vertical, 2)
	}

	/// The services of the extensions that may run, named after their extension.
	private var services: [SupportedBanks.Service] {
		model.extensions.setupServices.map { service in
			.init(name: service.service, extensionName: model.extensions.items.first { $0.id == service.id }?.name ?? service.id)
		}
	}

	private func load() async {
		do {
			directory = .success(try await model.fints.bankDirectory())
		} catch {
			directory = .failure(error)
		}
	}

	/// A search of the whole directory takes about 10 ms, too long for the main thread.
	private func match() async {
		guard case let .success(directory)? = directory else { return }
		let list = SupportedBanks(directory: directory, services: services), query = search
		let found = await Task.detached(priority: .userInitiated) { list.matching(query) }.value
		guard !Task.isCancelled else { return }
		shown = found
	}
}
