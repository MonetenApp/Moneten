import Domain
import SwiftUI

/// The category picker of ⌘K. Typing narrows the list, the arrow keys move the highlight, Return
/// assigns the highlighted category, and Escape closes. It leaves out the categories that the
/// selection cannot take, so that the highlight never rests on a choice that Return would refuse.
struct CategoryPickerSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let ids: Set<UUID>
	@State private var query = ""
	@State private var highlighted = 0
	@FocusState private var fieldFocused: Bool

	var body: some View {
		let ledger = model.ledger
		let transactions = ids.compactMap { ledger.transaction($0) }
		let matches = ledger.categories(matching: query).filter { ledger.canAssign($0, to: transactions) }
		SheetFrame(title: "Assign Category", confirmTitle: "Assign", canConfirm: matches.indices.contains(highlighted), width: 400, onConfirm: {
			model.assign(category: matches[highlighted].id, to: ids)
			return true
		}) {
			Section {
				TextField("Category", text: $query, prompt: Text("Type to find a category"))
					.labelsHidden()
					.focused($fieldFocused)
					.onKeyPress(.downArrow) { moveHighlight(1, of: matches.count) }
					.onKeyPress(.upArrow) { moveHighlight(-1, of: matches.count) }
			}
			Section {
				list(matches, in: ledger)
			}
		}
		.onChange(of: query) { highlighted = 0 }
		.onAppear { fieldFocused = true }
	}

	private func list(_ matches: [Domain.Category], in ledger: Ledger) -> some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(Array(matches.enumerated()), id: \.element.id) { index, c in
						Button {
							model.assign(category: c.id, to: ids)
							dismiss()
						} label: {
							Label {
								Text(ledger.categoryPath(c.id))
							} icon: {
								Image(systemName: CategorySymbols.name(of: c)).foregroundStyle(CategoryColors.color(of: c, in: ledger))
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 6)
							.padding(.vertical, 4)
							.background(index == highlighted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						.id(index)
					}
				}
			}
			// The sheet frame turns scrolling off for its form, and this list needs it.
			.scrollDisabled(false)
			.frame(height: 240)
			.overlay {
				if matches.isEmpty { Text("No category matches").foregroundStyle(.secondary) }
			}
			.onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
		}
	}

	private func moveHighlight(_ step: Int, of count: Int) -> KeyPress.Result {
		highlighted = max(0, min(highlighted + step, count - 1))
		return .handled
	}
}
