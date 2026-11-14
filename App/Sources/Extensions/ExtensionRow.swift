import SwiftUI

/// One extension in the list: its name, version, state, description, and a note such as a waiting update.
struct ExtensionRow: View {
	let item: ExtensionLibrary.Item

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack(alignment: .firstTextBaseline) {
				Text(item.name).font(.headline)
				if let version = item.version, item.section == .available { Text(version).foregroundStyle(.secondary) }
				Spacer()
				if let badge = item.badge { Text(badge).font(.caption).foregroundStyle(item.isCatalog ? Color.secondary : Color.orange) }
			}
			if !item.description.isEmpty {
				Text(item.description).foregroundStyle(.secondary).lineLimit(2)
			}
			if !item.kinds.isEmpty {
				Text(item.kinds.map(\.capitalized).formatted(.list(type: .and))).font(.caption).foregroundStyle(.tertiary)
			}
			if let note = item.note {
				Text(note).font(.callout).foregroundStyle(.orange)
			}
			if let action = item.action {
				ExtensionActionButton(item: item, action: action)
			}
		}
		.padding(.vertical, 3)
	}
}

/// The button of the next step for an extension: "Install", "Update", "Review Update", or "Allow...".
struct ExtensionActionButton: View {
	@Environment(AppModel.self) private var model
	let item: ExtensionLibrary.Item
	let action: ExtensionLibrary.Item.Action

	var body: some View {
		let library = model.extensions
		switch action {
		case .install:
			Button("Install") { Task { await library.install(item.id) } }
				.disabled(!library.reachable || library.working.contains(item.id))
		case .update:
			Button("Update") { Task { await library.update(item.id, approving: .init(version: item.available ?? "")) } }
				.disabled(!library.reachable || library.working.contains(item.id))
		case .reviewUpdate:
			Button("Review Update") { library.review(item.id) }
				.disabled(!library.reachable || library.working.contains(item.id))
		case .allow:
			Button("Allow...") { library.askAllow(item.id) }
		}
	}
}
