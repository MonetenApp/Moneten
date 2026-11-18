import Domain
import FinTS
import SwiftUI

/// The window of "Supported Banks..." in the Help menu: the services of the installed extensions and the
/// banks that the app reaches through FinTS, each with its access method and its note
/// (add-account-setup, "List of supported banks"). The bank directory comes from the FinTS helper once
/// per opening. Its chrome keeps the system materials (ADR 0012).
struct SupportedBanksWindow: View {
	@Environment(AppModel.self) private var model
	@State private var directory: Result<BankDirectory, any Error>?

	var body: some View {
		SupportedBanksList(directory: directory)
			.task {
				do {
					directory = .success(try await model.fints.bankDirectory())
				} catch {
					directory = .failure(error)
				}
			}
	}
}

/// The search field and the rows of "Supported Banks" for a bank directory that is loaded, failed, or nil
/// while it loads. The rows are a lazy stack, not a `List`: the table behind a `List` reported a reentrant
/// operation of its delegate when a search changed a whole section and hundreds of rows. So the stack does
/// what the table did: Down Arrow in the search field and Tab lead into the rows, the arrow and page keys
/// move the selection and scroll it into view, and each row is one element for VoiceOver.
struct SupportedBanksList: View {
	@Environment(AppModel.self) private var model
	let directory: Result<BankDirectory, any Error>?
	@State private var search = ""
	@FocusState private var focus: Focus?
	/// The rows for `search`, which a search of the whole directory computes off the main thread. Nil until
	/// the first search ends, so that the list does not say "No Results" while it loads. It also ends when the
	/// bank directory fails to load, with the services alone.
	@State private var shown: Shown?
	@State private var selected: Row.ID?
	/// Counts the results of `match()`, so that each new result shows from the top.
	@State private var result = 0
	/// The rows that Page Down moves, one less than the scroll view shows.
	@State private var page = 10

	#if DEBUG || PERF_HARNESS
	/// The rows of the last search, which the perf check compares with the rows it expects.
	static var lastShown: Shown?
	#endif

	private enum Focus: Hashable {
		case search, rows
	}

	/// The list shows this many banks, so that the window stays quick. A longer list asks for more of the name.
	private static let shownBanks = 500
	nonisolated private static let rowHeight: CGFloat = 40

	/// One row: a service of an extension or a bank of the directory.
	struct Row: Identifiable, Sendable {
		let id: String
		let name: String
		let detail: String?
		let method: String
		let note: String?

		init(_ service: SupportedBanks.Service) {
			id = "service \(service.id)"
			name = service.name
			detail = nil
			method = service.extensionName
			note = nil
		}

		init(_ bank: BankDirectory.Entry) {
			id = bank.code
			name = bank.bank.name
			detail = [bank.city, bank.code].filter { !$0.isEmpty }.joined(separator: " · ")
			method = SupportedBanks.fintsMethod
			note = SupportedBanks.note(of: bank)
		}
	}

	struct Shown: Sendable {
		let services: [Row]
		/// At most `shownBanks`.
		let banks: [Row]
		let bankCount: Int
	}

	var body: some View {
		ScrollViewReader { proxy in
			VStack(spacing: 0) {
				TextField("Search Banks", text: $search, prompt: Text("Name, place, or Bankleitzahl"))
					.textFieldStyle(.roundedBorder)
					.focused($focus, equals: .search)
					.accessibilityLabel("Search Banks")
					.onKeyPress(keys: [.downArrow]) { move($0, proxy) }
					.padding(10)
				content(proxy)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.frame(minWidth: 520, minHeight: 420)
		.onAppear { focus = .search }
		// The rows change with the search, the services, and the directory once it is loaded or failed.
		.task(id: [search, directory == nil ? "" : "loaded"] + services.map(\.id)) { await match() }
	}

	@ViewBuilder private func content(_ proxy: ScrollViewProxy) -> some View {
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
						LazyVStack(alignment: .leading, spacing: 0) {
							if !shown.services.isEmpty {
								header("Extensions")
								ForEach(shown.services) { row($0) }
							}
							if !shown.banks.isEmpty {
								header(shown.bankCount > Self.shownBanks ? "Banks (\(shown.bankCount), type more to narrow the list)" : "Banks")
								ForEach(shown.banks) { row($0) }
							}
						}
						.padding(.horizontal, 10)
						.padding(.bottom, 10)
					}
					// A new result starts at the top.
					.id(result)
					.onGeometryChange(for: Int.self) { max(1, Int($0.size.height / Self.rowHeight) - 1) } action: { page = $0 }
					// Tab leads here from the search field, also without keyboard navigation in the settings of macOS.
					.focusable(interactions: .edit)
					.focused($focus, equals: .rows)
					.onKeyPress(keys: [.downArrow, .upArrow, .pageDown, .pageUp, .home, .end]) { move($0, proxy) }
					.accessibilityElement(children: .contain)
					.accessibilityLabel("Supported Banks")
				}
			}
		} else {
			ProgressView("Loading the bank directory...")
		}
	}

	private func header(_ title: LocalizedStringKey) -> some View {
		Text(title)
			.font(.subheadline.weight(.semibold))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 6)
			.padding(.top, 10)
			.padding(.bottom, 4)
			.accessibilityAddTraits(.isHeader)
	}

	/// Every row has the same height, with lines that are cut at the end, so that the height of a row does not
	/// depend on the width of the window. The whole note is in the tooltip and in what VoiceOver reads.
	private func row(_ row: Row) -> some View {
		let second = [row.detail, row.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
		let isSelected = row.id == selected
		let emphasized = isSelected && focus == .rows
		return VStack(alignment: .leading, spacing: 2) {
			HStack(alignment: .firstTextBaseline) {
				Text(row.name).lineLimit(1)
				Spacer()
				Text(row.method).font(.callout).foregroundStyle(.secondary).lineLimit(1)
			}
			if !second.isEmpty { Text(second).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
		}
		.foregroundStyle(emphasized ? Color.white : Color.primary)
		.padding(.horizontal, 6)
		.frame(height: Self.rowHeight)
		.background {
			if isSelected { RoundedRectangle(cornerRadius: 5).fill(emphasized ? Color.accentColor : Color.secondary.opacity(0.2)) }
		}
		.overlay(alignment: .bottom) { if !isSelected { Divider() } }
		.contentShape(Rectangle())
		.onTapGesture {
			selected = row.id
			focus = .rows
		}
		.help(row.note ?? "")
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(row.name)
		.accessibilityValue([row.detail, row.method, row.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
		.accessibilityAddTraits(isSelected ? [.isStaticText, .isSelected] : .isStaticText)
	}

	/// Moves the selection by the key and scrolls it into view, as `SupportedBanksKeys` decides. A key with
	/// Command, Option, Control, or Shift goes to the system, so Command-Down moves the text cursor.
	private func move(_ press: KeyPress, _ proxy: ScrollViewProxy) -> KeyPress.Result {
		guard let shown, let key = Self.key(press.key) else { return .ignored }
		let ids = shown.services.map(\.id) + shown.banks.map(\.id)
		var modifiers = SupportedBanksKeys.Modifiers()
		if press.modifiers.contains(.command) { modifiers.insert(.command) }
		if press.modifiers.contains(.option) { modifiers.insert(.option) }
		if press.modifiers.contains(.control) { modifiers.insert(.control) }
		if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
		let place: SupportedBanksKeys.Focus = focus == .rows ? .rows(selected: selected.flatMap(ids.firstIndex)) : .search
		switch SupportedBanksKeys.action(for: key, modifiers: modifiers, focus: place, count: ids.count, page: page) {
		case .ignore:
			return .ignored
		case .focusSearch:
			focus = .search
		case let .select(position):
			selected = ids[position]
			focus = .rows
			proxy.scrollTo(ids[position])
		}
		return .handled
	}

	private static func key(_ key: KeyEquivalent) -> SupportedBanksKeys.Key? {
		switch key {
		case .upArrow: .up
		case .downArrow: .down
		case .pageUp: .pageUp
		case .pageDown: .pageDown
		case .home: .home
		case .end: .end
		default: nil
		}
	}

	/// The services of the extensions that may run, named after their extension.
	private var services: [SupportedBanks.Service] {
		model.extensions.setupServices.map { service in
			.init(name: service.service, extensionName: model.extensions.items.first { $0.id == service.id }?.name ?? service.id)
		}
	}

	/// A search of the whole directory takes about 10 ms, too long for the main thread. Without the bank
	/// directory the list has only the services.
	private func match() async {
		guard let directory else { return }
		let list = SupportedBanks(directory: try? directory.get(), services: services), query = search, limit = Self.shownBanks
		let found = await Task.detached(priority: .userInitiated) {
			let found = list.matching(query)
			return Shown(services: found.services.map(Row.init), banks: found.banks.prefix(limit).map(Row.init), bankCount: found.banks.count)
		}.value
		guard !Task.isCancelled else { return }
		shown = found
		#if DEBUG || PERF_HARNESS
		Self.lastShown = found
		#endif
		selected = nil
		result += 1
	}
}
