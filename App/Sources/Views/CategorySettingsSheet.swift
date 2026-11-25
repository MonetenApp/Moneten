import Domain
import SwiftUI

/// The text for a rule whose regular expression ran too long (`Rule.stoppedRegexPosition`).
enum RuleStop {
	static func message(position: Int) -> String {
		String(localized: "The regular expression at position \(position + 1) stopped because it is too slow.")
	}
}

struct CategorySettingsSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let categoryID: UUID
	@State private var category: Domain.Category?
	@State private var color = Color.accentColor
	@State private var originalColor = Color.accentColor
	@State private var ruleError: String?
	@State private var showHelp = false
	/// The last count of matches and the rule that it counted.
	@State private var matches: (key: MatchKey, count: MatchCount)?

	/// What the lock keeps of the settings, the rule included.
	private struct Input: Hashable, Sendable {
		var category: Domain.Category?
		var color: Color
		var originalColor: Color
	}

	var body: some View {
		SheetFrame(title: "Settings for \(category?.name ?? "")", canConfirm: ruleError == nil && currencyIsValid && nameCheck?.acceptedName != nil && !isApplying, canCancel: !isApplying, width: 520, onConfirm: save, leading: {
			if category?.isDefault == false {
				Button("Remove Category...", role: .destructive) { if model.confirmRemove(.category(categoryID)) { dismiss() } }
					.disabled(isApplying)
			}
		}) {
			if let binding = Binding($category) {
				let c = binding.wrappedValue
				Section {
					TextField("Name", text: binding.name, prompt: Text("Required"))
					TextField("Currency", text: binding.currency)
				} footer: {
					if nameCheck == .taken { CategoryNameTaken(parentID: c.parentID) }
					if !currencyIsValid {
						Text("Enter a currency code such as EUR.").foregroundStyle(Palette.red)
					}
				}
				.disabled(isApplying)
				Section {
					if !c.isDefault {
						LabeledContent("Color") { ColorSwatches(selection: $color) }
						LabeledContent("Icon") { SymbolPicker(selection: binding.symbol, color: color, isGroup: c.isGroup) }
					}
					Toggle("Show in diagrams", isOn: binding.showInDiagrams)
						.help("Turn this off for transfers between your own accounts.")
					Picker("Display in sidebar", selection: binding.sidebarAmount) {
						ForEach(SidebarAmount.allCases, id: \.self) { Text($0.title).tag($0) }
					}
					if !c.isDefault && !c.isGroup {
						Picker("Restrict to", selection: binding.restrictedToID) {
							Text("All accounts").tag(UUID?.none)
							ForEach(model.ledger.groups) { Text($0.name).tag(UUID?.some($0.id)) }
							ForEach(model.ledger.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
						}
					}
				}
				.disabled(isApplying)
				if !c.isDefault && !c.isGroup {
					Section {
						TextEditor(text: binding.rule)
							.font(.system(.body, design: .monospaced))
							.scrollContentBackground(.hidden)
							.frame(height: 88)
							.onChange(of: c.rule) { _, text in validate(text) }
							.disabled(isApplying)
					} header: {
						HStack {
							Text("Rules for automatic categorization")
							Spacer()
							Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
								.buttonStyle(.borderless)
								.help("Help")
								.accessibilityIdentifier("rule-help")
								.popover(isPresented: $showHelp) { RuleHelp() }
						}
					} footer: {
						if let p = model.ruleProgress {
							HStack(spacing: 8) {
								ProgressView().controlSize(.small)
								Text("Applying rule to transaction \(p.done.formatted()) of \(p.total.formatted())...")
							}
							.foregroundStyle(.secondary)
						} else if let ruleError {
							Text(ruleError).foregroundStyle(Palette.red)
						} else if !c.rule.isEmpty, let matches, matches.key == matchKey {
							switch matches.count {
							case let .stopped(position):
								Text(RuleStop.message(position: position)).foregroundStyle(Palette.red)
							case let .count(count):
								Text(count == 1 ? "The rule matches 1 transaction." : "The rule matches \(count) transactions.")
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			}
		}
		.interactiveDismissDisabled(isApplying)
		.task(id: matchKey) { await countMatches(matchKey) }
		.keepsInput(Input(category: category, color: color, originalColor: originalColor), of: .categorySettings(categoryID))
		.onAppear {
			category = model.ledger.category(categoryID)
			color = category.map { CategoryColors.color(of: $0, in: model.ledger) } ?? .accentColor
			originalColor = color
			// A saved rule such as "amount>1,000" may no longer read, so its error shows before the first edit.
			ruleError = category?.ruleError?.description
			if let draft = model.ruleDraft, draft.categoryID == categoryID, category != nil {
				category?.rule = draft.rule
				validate(draft.rule)
			}
			model.ruleDraft = nil
			if let held: Input = model.heldInput(for: .categorySettings(categoryID)), held.category != nil {
				category = held.category
				color = held.color
				originalColor = held.originalColor
				validate(held.category?.rule ?? "")
			}
		}
		// A dialog of the bank that comes while the question shows waits until the user answered it, and a question asked
		// while a dialog shows waits for the dialog (`AlertGate`).
		.confirmationDialog("Should this categorization rule be applied to the existing transactions now?", isPresented: model.presents(.applyRule)) {
			Button("Apply only to not yet categorized transactions.") { apply(.uncategorizedOnly) }
			Button("Apply to all transactions.") { apply(.all) }
			Button("Not now", role: .cancel) { dismiss() }
		} message: {
			Text("\"Apply to all transactions\" also replaces categories that you assigned by hand, and transactions that no longer match leave this category.")
		}
	}

	/// The code in the currency field by the rule of every currency that the app stores, so a category can be in a token
	/// such as BTC, as an offline account can. Nil for other text, which the complete export would refuse.
	private var currencyCode: String? { category.flatMap { Money.currencyCode($0.currency) } }

	private var currencyIsValid: Bool { currencyCode != nil }

	private var isApplying: Bool { model.isApplyingRule }

	/// The check of a changed name in the group of the category. A name that the user did not change is accepted as it is
	/// stored, also when an earlier version or a migration left two categories with that name in one group.
	private var nameCheck: CategoryNameCheck? {
		guard let c = category else { return nil }
		guard let stored = model.ledger.category(categoryID), c.name != stored.name else { return .accepted(c.name) }
		return model.ledger.checkCategoryName(c.name, in: stored.parentID, renaming: categoryID)
	}

	private func validate(_ text: String) {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { ruleError = nil; return }
		do {
			_ = try Rule(parsing: text)
			ruleError = nil
		} catch {
			ruleError = error.description
		}
	}

	private enum MatchCount: Sendable {
		case count(Int)
		/// The position of the regular expression that ran too long, counted from 0.
		case stopped(Int)
	}

	/// What the count of matches depends on.
	private struct MatchKey: Hashable {
		let rule: String
		// The synthesized Hashable conformance reads these, which Periphery cannot see.
		// periphery:ignore
		let restriction: UUID?
		/// A refresh while the sheet is open changes the ledger, and the count follows it.
		// periphery:ignore
		let ledgerRevision: Int
	}

	// The body reads the ledger for the pickers, so a change of the ledger evaluates this again.
	private var matchKey: MatchKey? {
		category.map { MatchKey(rule: $0.rule, restriction: $0.restrictedToID, ledgerRevision: model.ledgerRevision) }
	}

	/// Counts the matches away from the main actor, because a slow rule may take up to its limit of processor time.
	/// Typing changes the rule on every key, so the count waits for a pause first.
	private func countMatches(_ key: MatchKey?) async {
		guard let key, let c = category, !key.rule.isEmpty, let rule = try? Rule(parsing: key.rule) else { return }
		try? await Task.sleep(for: .milliseconds(250))
		guard !Task.isCancelled else { return }
		let ledger = model.ledger
		let worker = Task.detached(priority: .userInitiated) {
			let count = RuleApplier.matchCount(category: c, rule: rule, ledger: ledger)
			return rule.stoppedRegexPosition.map(MatchCount.stopped) ?? .count(count)
		}
		// A new key cancels this task, and the count it no longer needs stops too.
		let count = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
		guard !Task.isCancelled else { return }
		matches = (key, count)
	}

	/// Saves and closes, or keeps the sheet open to ask whether a changed rule applies to existing transactions.
	private func save() -> Bool {
		guard var c = category else { return true }
		guard let name = nameCheck?.acceptedName else { return false }
		c.name = name
		guard let code = currencyCode else { return false }
		c.currency = code
		// A category keeps the inherited palette color until the user picks one.
		if !c.isDefault, color.hex != originalColor.hex { c.color = color.hex }
		let ruleChanged = c.rule != model.ledger.category(categoryID)?.rule
		model.save(category: c)
		if ruleChanged, !c.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			model.ask(.applyRule)
			return false
		}
		return true
	}

	private func apply(_ mode: RuleApplication) {
		guard let c = category, let rule = try? Rule(parsing: c.rule) else { return }
		Task {
			await model.apply(rule: rule, of: c, mode: mode)
			if model.sheet == .categorySettings(categoryID) { dismiss() }
		}
	}
}

struct RuleHelp: View {
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 10) {
				Text("Rule language").font(.headline)
				example(#""Lohn" OR "Gehalt""#, "Either word")
				example(#""Lohn" AND "Gehalt""#, "Both words. Two terms without an operator also need both.")
				example(#""EC-Karte" AND (NOT "Barauszahlung")"#, "Negation and parentheses")
				example(#""Netflix" + !"Gutschrift""#, "Short forms: + is AND, ! is NOT.")
				example(#""Amazon" -"Erstattung""#, "A minus before a term is NOT.")
				example(#""Telekom" -"1&1""#, #"A plus or minus sign before a digit is part of the term, so -1&1 searches for "-1&1". To exclude 1&1, write -"1&1"."#)
				example(#""Bahn AG""#, "A phrase: the words next to each other, in this order")
				example(#""Blumen*""#, #"Wildcards: * for any characters, ? for one character. A term matches whole words, so "REWE" does not find REWE-Markt, and "REWE*" does."#)
				example(#"name:"Bahn AG""#, "Only one field: name:, purpose:, local_account:, remote_account:, currency:, reference:, mandate:, creditor_id:, comment:, booking_text:")
				example("currency:=EUR", "The field matches. :, =, and == do the same.")
				example(#""Abschlag" AND name<>"Stadtwerke""#, "The field does not match. != does the same.")
				example(#"remote_account:"DE02 1203 0000 0000 2020 51""#, "A word without a field does not search account numbers or IBANs. local_account: and remote_account: do.")
				example("amount>0,00", "Amount: =, ==, :=, !=, <>, <, >, <=, >=. No space after the operator.")
				example("true", "Every transaction. Restricted to one account, the category takes what no category above it takes.")
				example("false", "No transaction")
				example("/GA NR[0-9]{8}/", "A regular expression between slashes")
				Text(#"Case and umlauts do not matter. The operators work in any letter case. A word in quotation marks, such as "or", is always a search word."#)
					.font(.callout).foregroundStyle(.secondary)
			}
			.padding()
		}
		.frame(width: 420, height: 640)
	}

	private func example(_ code: String, _ text: LocalizedStringKey) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
			Text(text).font(.callout).foregroundStyle(.secondary)
		}
	}
}

/// The palette of category colors as swatches, with the system color panel for any other color.
struct ColorSwatches: View {
	@Binding var selection: Color

	var body: some View {
		HStack(spacing: 6) {
			ForEach(Array(CategoryColors.palette.enumerated()), id: \.offset) { _, color in
				let selected = color.hex == selection.hex
				Button { selection = color } label: {
					Circle()
						.fill(color)
						.frame(width: 16, height: 16)
						.padding(3)
						.overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.help(selected ? "Selected color" : "Choose this color")
				.accessibilityIdentifier("color-swatch")
			}
			OtherColorButton(selection: $selection)
				.help("Other color")
		}
	}
}

/// The icon of a category: a button with the current icon that opens a grid of SF Symbols. The
/// first choice is the bookmark, or the folder of a group, which a category shows without a symbol.
struct SymbolPicker: View {
	@Binding var selection: String?
	let color: Color
	let isGroup: Bool
	@State private var isOpen = false

	private var plain: String { isGroup ? "folder" : "bookmark.fill" }

	var body: some View {
		Button { isOpen = true } label: {
			HStack(spacing: 6) {
				Image(systemName: selection ?? plain)
					.foregroundStyle(color)
					.frame(width: 18, height: 16)
				// The same mark as the pop-up menus of the other rows.
				Image(systemName: "chevron.up.chevron.down")
					.font(.system(size: 9, weight: .bold))
					.foregroundStyle(.secondary)
					.frame(width: 20, height: 20)
					.background(.quaternary, in: Circle())
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Icon")
		.accessibilityValue(CategorySymbols.label(selection, isGroup: isGroup))
		.help(CategorySymbols.label(selection, isGroup: isGroup))
		.popover(isPresented: $isOpen, arrowEdge: .bottom) {
			SymbolGrid(selection: selection, color: color, isGroup: isGroup) {
				selection = $0
				isOpen = false
			}
		}
	}
}

/// The choices of `SymbolPicker`: the bookmark or folder first, then the symbols by topic.
struct SymbolGrid: View {
	let selection: String?
	let color: Color
	let isGroup: Bool
	let pick: (String?) -> Void

	var body: some View {
		LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
			cell(nil)
			ForEach(CategorySymbols.choices, id: \.symbol) { cell($0.symbol) }
		}
		.padding(10)
	}

	private func cell(_ symbol: String?) -> some View {
		SymbolCell(symbol: symbol ?? (isGroup ? "folder" : "bookmark.fill"), color: color, selected: symbol == selection,
			name: CategorySymbols.label(symbol, isGroup: isGroup)) {
			pick(symbol)
		}
	}
}

/// One choice of `SymbolPicker`: the symbol in the color of the category, white on that color when
/// it is the current one, and on a light background under the pointer.
private struct SymbolCell: View {
	let symbol: String
	let color: Color
	let selected: Bool
	let name: String
	let action: () -> Void
	@State private var hovered = false

	var body: some View {
		Button(action: action) {
			Image(systemName: symbol)
				.font(.system(size: 15))
				.foregroundStyle(selected ? Color.white : color)
				.frame(width: 30, height: 30)
				.background(RoundedRectangle(cornerRadius: 6).fill(selected ? AnyShapeStyle(color) : AnyShapeStyle(.primary.opacity(hovered ? 0.08 : 0))))
				.contentShape(RoundedRectangle(cornerRadius: 6))
		}
		.buttonStyle(.plain)
		.onHover { hovered = $0 }
		.help(name)
		.accessibilityLabel(name)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}
}

/// The last swatch: a color wheel that opens the system color panel for any other color.
/// It shows the chosen color when that color is not in the palette.
struct OtherColorButton: View {
	@Binding var selection: Color
	@State private var relay = ColorPanelRelay()

	var body: some View {
		let custom = !CategoryColors.palette.contains { $0.hex == selection.hex }
		Button {
			relay.open(selection) { selection = $0 }
		} label: {
			Circle()
				.fill(custom ? AnyShapeStyle(selection) : AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)))
				.frame(width: 16, height: 16)
				.padding(3)
				.overlay(Circle().strokeBorder(custom ? Color.primary : .clear, lineWidth: 2))
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
	}
}

/// Receives the changes of the shared color panel and passes them on.
@MainActor
final class ColorPanelRelay: NSObject {
	private var onChange: ((Color) -> Void)?

	func open(_ color: Color, onChange: @escaping (Color) -> Void) {
		self.onChange = onChange
		let panel = NSColorPanel.shared
		panel.showsAlpha = false
		panel.color = NSColor(color)
		panel.setTarget(self)
		panel.setAction(#selector(changed(_:)))
		panel.orderFront(nil)
	}

	@objc func changed(_ panel: NSColorPanel) {
		onChange?(Color(nsColor: panel.color))
	}
}
