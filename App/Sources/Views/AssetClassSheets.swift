import Domain
import SwiftUI

/// The asset class settings, which only "Asset Class Settings..." at the end of the submenu "Asset Class" opens: one row
/// for each of the eight classes with its ribbon and the color control of the category settings, and "Restore Default
/// Colors". A chosen color is one color for light and dark mode, as the color of a category. The choices apply on "OK".
struct AssetClassSettingsSheet: View {
	@Environment(AppModel.self) private var model
	/// The color of each class in the sheet, chosen or default.
	@State private var colors: [AssetClass: Color] = [:]
	@State private var loaded = false

	var body: some View {
		SheetFrame(title: "Asset Class Settings", width: 560, onConfirm: {
			model.setAssetClassColors(chosen)
			return true
		}, leading: {
			Button("Restore Default Colors") {
				for c in AssetClass.allCases { colors[c] = AssetClassColors.defaultColor(of: c) }
			}
		}) {
			Section {
				ForEach(AssetClass.allCases, id: \.self) { c in
					LabeledContent {
						ColorSwatches(selection: binding(c))
					} label: {
						Ribbon(text: c.name, color: colors[c] ?? AssetClassColors.defaultColor(of: c)).accessibilityLabel(c.name)
					}
				}
			}
		}
		.keepsInput(colors, of: .assetClassSettings)
		.onAppear {
			guard !loaded else { return }
			loaded = true
			if let held: [AssetClass: Color] = model.heldInput(for: .assetClassSettings) {
				colors = held
			} else {
				for c in AssetClass.allCases { colors[c] = AssetClassColors.color(of: c, chosen: model.ledger.assetClassColors) }
			}
		}
	}

	/// The colors that differ from the defaults, as hex text. A class at its default stores nothing, so a later change of a
	/// default reaches it.
	private var chosen: [AssetClass: String] {
		var chosen: [AssetClass: String] = [:]
		for c in AssetClass.allCases {
			if let hex = colors[c]?.hex, hex != AssetClassColors.defaultColor(of: c).hex { chosen[c] = hex }
		}
		return chosen
	}

	private func binding(_ c: AssetClass) -> Binding<Color> {
		Binding(get: { colors[c] ?? AssetClassColors.defaultColor(of: c) }, set: { colors[c] = $0 })
	}
}

/// The picker of ⌘K in a portfolio view: "Automatic" and the eight classes. Typing narrows the list, the arrow keys move
/// the highlight, Return assigns the highlighted entry, and Escape closes, as in the category picker. A choice works as the
/// same entry of the submenu "Asset Class".
struct AssetClassPickerSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let ids: Set<UUID>
	@State private var query = ""
	@State private var highlighted = 0
	@FocusState private var fieldFocused: Bool

	/// "Automatic" as nil, then the classes in the order of the menu.
	private var matches: [AssetClass?] {
		let all: [AssetClass?] = [nil] + AssetClass.allCases.map(Optional.some)
		let text = query.trimmingCharacters(in: .whitespaces)
		guard !text.isEmpty else { return all }
		return all.filter { title(of: $0).localizedStandardContains(text) }
	}

	var body: some View {
		let matches = self.matches
		SheetFrame(title: "Assign Asset Class", confirmTitle: "Assign", canConfirm: matches.indices.contains(highlighted), width: 360, onConfirm: {
			let matches = self.matches
			guard matches.indices.contains(highlighted) else { return false }
			model.setAssetClass(matches[highlighted], of: ids)
			return true
		}) {
			Section {
				TextField("Asset class", text: $query, prompt: Text("Type to find an asset class"))
					.labelsHidden()
					.focused($fieldFocused)
					.onKeyPress(.downArrow) { moveHighlight(1) }
					.onKeyPress(.upArrow) { moveHighlight(-1) }
			}
			Section {
				VStack(alignment: .leading, spacing: 0) {
					ForEach(Array(matches.enumerated()), id: \.offset) { index, c in
						Button {
							model.setAssetClass(c, of: ids)
							dismiss()
						} label: {
							Label {
								Text(title(of: c))
							} icon: {
								Circle()
									.fill(c.map { AnyShapeStyle(RibbonFill(color: AssetClassColors.color(of: $0, chosen: model.ledger.assetClassColors))) } ?? AnyShapeStyle(Color.clear))
									.overlay(Circle().strokeBorder(c == nil ? Palette.secondaryText : .clear, lineWidth: 1))
									.frame(width: 10, height: 10)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal, 6)
							.padding(.vertical, 4)
							.background(index == highlighted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				}
				.overlay {
					if matches.isEmpty { Text("No asset class matches").foregroundStyle(.secondary) }
				}
				.frame(minHeight: 40)
			}
		}
		.onChange(of: query) { highlighted = 0 }
		// The focus stays in the search field, so VoiceOver hears the highlight only through an announcement.
		.onChange(of: highlighted) { _, index in
			if matches.indices.contains(index) { AccessibilityNotification.Announcement(title(of: matches[index])).post() }
		}
		.onAppear { fieldFocused = true }
	}

	private func title(of c: AssetClass?) -> String {
		c?.name ?? String(localized: "Automatic")
	}

	private func moveHighlight(_ step: Int) -> KeyPress.Result {
		highlighted = max(0, min(highlighted + step, matches.count - 1))
		return .handled
	}
}
