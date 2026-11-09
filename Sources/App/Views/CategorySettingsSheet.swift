import Domain
import SwiftUI

struct CategorySettingsSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let categoryID: UUID
	@State private var category: Domain.Category?
	@State private var color = Color.accentColor
	@State private var ruleError: String?
	@State private var askApply = false
	@State private var showHelp = false
	@State private var confirmRemove = false

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			if let binding = Binding($category) {
				Text("Settings for \(binding.wrappedValue.name)").font(.headline)
				Form {
					TextField("Name:", text: binding.name).disabled(false)
					if !binding.wrappedValue.isDefault {
						ColorPicker("Color:", selection: $color, supportsOpacity: false)
					}
					Toggle("Show in diagrams", isOn: binding.showInDiagrams)
						.help("Turn this off for transfers between your own accounts.")
					Picker("Display in sidebar:", selection: binding.sidebarAmount) {
						ForEach(SidebarAmount.allCases, id: \.self) { Text($0.title).tag($0) }
					}
					if !binding.wrappedValue.isDefault && !binding.wrappedValue.isGroup {
						Picker("Restrict to:", selection: binding.restrictedToID) {
							Text("All accounts").tag(UUID?.none)
							ForEach(model.ledger.groups) { Text($0.name).tag(UUID?.some($0.id)) }
							ForEach(model.ledger.accounts) { Text($0.name).tag(UUID?.some($0.id)) }
						}
					}
				}
				if !binding.wrappedValue.isDefault && !binding.wrappedValue.isGroup {
					HStack {
						Text("Rules for automatic categorization:")
						Spacer()
						Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
							.buttonStyle(.borderless)
							.help("Help")
							.popover(isPresented: $showHelp) { RuleHelp() }
					}
					TextEditor(text: binding.rule)
						.font(.system(.body, design: .monospaced))
						.frame(height: 90)
						.border(Color.secondary.opacity(0.3))
						.onChange(of: binding.wrappedValue.rule) { _, text in validate(text) }
					if let ruleError {
						Text(ruleError).foregroundStyle(.red).font(.callout)
					} else if !binding.wrappedValue.rule.isEmpty {
						let count = matchCount(binding.wrappedValue)
						Text(count == 1 ? "The rule matches 1 transaction." : "The rule matches \(count) transactions.")
							.font(.callout).foregroundStyle(.secondary)
					}
				}
				HStack {
					if !binding.wrappedValue.isDefault {
						Button("Remove Category...", role: .destructive) { confirmRemove = true }
					}
					Spacer()
					Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
					Button("OK", action: save).keyboardShortcut(.defaultAction).disabled(ruleError != nil)
				}
			}
		}
		.padding(20)
		.frame(width: 540)
		.onAppear {
			category = model.ledger.category(categoryID)
			color = Color(hex: category?.color) ?? .accentColor
		}
		.confirmationDialog("Should this categorization rule be applied to the existing transactions now?", isPresented: $askApply) {
			Button("Apply only to not yet categorized transactions.") { apply(.uncategorizedOnly) }
			Button("Apply to all transactions.") { apply(.all) }
			Button("Not now", role: .cancel) { dismiss() }
		} message: {
			Text("\"Apply to all transactions\" also replaces categories that you assigned by hand, and transactions that no longer match leave this category.")
		}
		.confirmationDialog("Are you sure you want to remove the category \(category?.name ?? "")?", isPresented: $confirmRemove) {
			Button("Remove", role: .destructive) {
				model.remove(category: categoryID)
				dismiss()
			}
		} message: {
			Text("The transactions will be retained and become uncategorized.")
		}
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

	private func matchCount(_ c: Domain.Category) -> Int {
		guard let rule = try? Rule(parsing: c.rule) else { return 0 }
		return model.ledger.transactions.reduce(0) { $0 + (rule.matches(RuleSubject($1, account: model.ledger.account($1.accountID))) ? 1 : 0) }
	}

	private func save() {
		guard var c = category else { return }
		if !c.isDefault { c.color = color.hex }
		let ruleChanged = c.rule != model.ledger.category(categoryID)?.rule
		model.save(category: c)
		if ruleChanged, !c.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			askApply = true
		} else {
			dismiss()
		}
	}

	private func apply(_ mode: RuleApplication) {
		guard let c = category, let rule = try? Rule(parsing: c.rule) else { return }
		Task {
			await model.apply(rule: rule, of: c, mode: mode)
			dismiss()
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
				example(#""Bahn AG""#, "A phrase: the words next to each other, in this order")
				example(#""Blumen*""#, "Wildcards: * for any characters, ? for one character")
				example(#"name:"Bahn AG""#, "Only one field: name:, purpose:, local_account:, remote_account:, currency:, reference:, mandate:, creditor_id:, comment:, booking_text:")
				example("amount>0,00", "Amount: =, !=, <, >, <=, >=. No space after the operator.")
				example("/GA NR[0-9]{8}/", "A regular expression between slashes")
				Text("Case and umlauts do not matter. AND, OR, and NOT must be written in capitals.")
					.font(.callout).foregroundStyle(.secondary)
			}
			.padding()
		}
		.frame(width: 420, height: 420)
	}

	private func example(_ code: String, _ text: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
			Text(text).font(.callout).foregroundStyle(.secondary)
		}
	}
}
