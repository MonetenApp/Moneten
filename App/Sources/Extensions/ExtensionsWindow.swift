import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window of the menu item "Extensions": the installed extensions and those of the catalog, with
/// their details. Its chrome keeps the system materials (ADR 0012).
struct ExtensionsWindow: View {
	@Environment(AppModel.self) private var model
	@State private var search = ""

	private var library: ExtensionLibrary { model.extensions }

	private var shown: [ExtensionLibrary.Item] {
		guard !search.isEmpty else { return library.items }
		return library.items.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
	}

	var body: some View {
		Group {
			if model.phase == .unlocked {
				content
			} else {
				ContentUnavailableView("Moneten is locked", systemImage: "lock", description: Text("Unlock Moneten to manage its extensions."))
			}
		}
		.frame(minWidth: 760, minHeight: 460)
	}

	private var content: some View {
		HSplitView {
			VStack(spacing: 0) {
				HStack {
					TextField("Search Extensions", text: $search)
						.textFieldStyle(.roundedBorder)
					Button("Check Now") { Task { await library.checkNow() } }
				}
				.padding(10)
				List(selection: Binding(get: { library.selection }, set: { model.extensions.selection = $0 })) {
					section("Installed", .installed)
					section("Available", .available)
				}
				status
				HStack {
					Toggle("Update extensions automatically", isOn: Binding(get: { library.automatic }, set: { library.automatic = $0 }))
						.toggleStyle(.checkbox)
					Spacer()
					Button("Install from File...", action: pickFile)
				}
				.padding(10)
			}
			.frame(minWidth: 340, idealWidth: 400)
			Group {
				if let item = library.items.first(where: { $0.id == library.selection }) {
					ExtensionDetails(item: item)
				} else {
					ContentUnavailableView("No Extension Selected", systemImage: "puzzlepiece.extension")
				}
			}
			.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
		}
		.sheet(item: Binding(get: { library.question }, set: { model.extensions.question = $0 })) { question in
			UpdateConfirmation(question: question)
		}
		.alert(library.failure ?? "", isPresented: Binding(get: { library.failure != nil }, set: { if !$0 { model.extensions.failure = nil } })) {
			Button("OK") {}
		}
	}

	@ViewBuilder
	private func section(_ title: String, _ kind: ExtensionLibrary.Item.Section) -> some View {
		let rows = shown.filter { $0.section == kind }
		Section(title) {
			if rows.isEmpty {
				Text(kind == .installed ? "No extension is installed." : "The catalog has no other extensions.")
					.foregroundStyle(.secondary)
			}
			ForEach(rows) { item in
				ExtensionRow(item: item).tag(item.id)
			}
		}
	}

	/// The date of the list that the window shows, and why a newer one was not used.
	private var status: some View {
		VStack(alignment: .leading, spacing: 2) {
			if let problem = library.problem {
				Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
			}
			if let index = library.index {
				Text("List of \(index.published.formatted(date: .abbreviated, time: .shortened)), version \(index.version)")
					.foregroundStyle(.secondary)
			}
			if !library.reachable {
				Text("Installing is not possible until the catalog can be reached.").foregroundStyle(.secondary)
			}
		}
		.font(.caption)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 10)
		.padding(.top, 6)
	}

	private func pickFile() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.allowedContentTypes = [UTType(filenameExtension: "lua") ?? .plainText, .folder]
		panel.message = "Choose a .lua file or a folder with a manifest."
		guard panel.runModal() == .OK, let url = panel.url else { return }
		library.pickFile(url)
	}
}
