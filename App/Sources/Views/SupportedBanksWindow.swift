import Domain
import FinTS
import SwiftUI

/// The window of "Supported Banks..." in the Help menu: the services of the installed extensions and the
/// banks that the app reaches through FinTS, each with its access method and its note
/// (add-account-setup, "List of supported banks"). The bank directory comes from the FinTS helper once
/// per opening. Its chrome keeps the system materials (ADR 0012). The rows are a lazy stack, not a `List`:
/// the table behind a `List` reported a reentrant operation of its delegate when a search changed a whole
/// section and hundreds of rows.
struct SupportedBanksWindow: View {
	@Environment(AppModel.self) private var model
	@State private var search = ""
	@FocusState private var searching: Bool
	@State private var directory: Result<BankDirectory, any Error>?
	/// The rows for `search`, which a search of the whole directory computes off the main thread. Nil until
	/// the first search ends, so that the list does not say "No Results" while it loads. It also ends when the
	/// bank directory fails to load, with the services alone.
	@State private var shown: (services: [SupportedBanks.Service], banks: [BankDirectory.Entry])?
	/// Counts the results of `match()`, so that each new result shows from the top.
	@State private var result = 0

	/// The list shows this many banks, so that the window stays quick. A longer list asks for more of the name.
	private static let shownBanks = 500

	var body: some View {
		VStack(spacing: 0) {
			TextField("Search Banks", text: $search, prompt: Text("Name, place, or Bankleitzahl"))
				.textFieldStyle(.roundedBorder)
				.focused($searching)
				.padding(10)
			content
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.frame(minWidth: 520, minHeight: 420)
		.task {
			searching = true
			await load()
		}
		// The rows change with the search, the services, and the directory once it is loaded or failed.
		.task(id: [search, directory == nil ? "" : "loaded"] + services.map(\.id)) { await match() }
	}

	@ViewBuilder private var content: some View {
		if let shown {
			let failure: String? = if case let .failure(error)? = directory { (error as? SyncFailure)?.message ?? error.localizedDescription } else { nil }
			if shown.services.isEmpty, shown.banks.isEmpty {
				if let failure {
					ContentUnavailableView("Could not load the bank directory", systemImage: "exclamationmark.triangle", description: Text(failure))
				} else {
					ContentUnavailableView.search(text: search)
				}
			} else {
				VStack(spacing: 0) {
					if let failure {
						// The services of the extensions do not need the bank directory, so the list keeps them.
						Label("Could not load the bank directory. \(failure)", systemImage: "exclamationmark.triangle")
							.foregroundStyle(.orange)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 10)
							.padding(.bottom, 6)
					}
					ScrollView {
						LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
							if !shown.services.isEmpty {
								Section {
									ForEach(shown.services) { row(name: $0.name, detail: nil, method: $0.extensionName, note: nil) }
								} header: {
									header("Extensions")
								}
							}
							if !shown.banks.isEmpty {
								Section {
									ForEach(shown.banks.prefix(Self.shownBanks)) { bank in
										row(name: bank.bank.name, detail: [bank.city, bank.code].filter { !$0.isEmpty }.joined(separator: " · "),
											method: SupportedBanks.fintsMethod, note: bank.mergerNote ?? bank.loginHint?.help)
									}
								} header: {
									header(shown.banks.count > Self.shownBanks ? "Banks (\(shown.banks.count), type more to narrow the list)" : "Banks")
								}
							}
						}
						.padding(.horizontal, 16)
						.padding(.bottom, 10)
					}
					// A new result starts at the top.
					.id(result)
				}
			}
		} else {
			ProgressView("Loading the bank directory...")
		}
	}

	private func header(_ title: String) -> some View {
		Text(title)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.top, 10)
			.padding(.bottom, 4)
			.background(.background)
	}

	/// Every row has the same height, with lines that are cut at the end and the whole note in the tooltip, so
	/// that the height of a row does not depend on the width of the window.
	private func row(name: String, detail: String?, method: String, note: String?) -> some View {
		let second = [detail, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
		return VStack(alignment: .leading, spacing: 2) {
			HStack(alignment: .firstTextBaseline) {
				Text(name).lineLimit(1)
				Spacer()
				Text(method).font(.callout).foregroundStyle(.secondary).lineLimit(1)
			}
			if !second.isEmpty { Text(second).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
		}
		.frame(height: 40)
		.overlay(alignment: .bottom) { Divider() }
		.help(note ?? "")
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

	/// A search of the whole directory takes about 10 ms, too long for the main thread. Without the bank
	/// directory the list has only the services.
	private func match() async {
		guard let directory else { return }
		let list = SupportedBanks(directory: try? directory.get(), services: services), query = search
		let found = await Task.detached(priority: .userInitiated) { list.matching(query) }.value
		guard !Task.isCancelled else { return }
		shown = found
		result += 1
	}
}
