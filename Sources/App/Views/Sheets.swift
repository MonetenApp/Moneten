import Domain
import SwiftUI

/// The frame of every sheet: a title, the content, and Cancel and confirm buttons.
struct SheetFrame<Content: View>: View {
	@Environment(\.dismiss) private var dismiss
	var title: String
	var confirmTitle = "OK"
	var canConfirm = true
	var width: CGFloat = 440
	var onConfirm: () -> Bool
	@ViewBuilder var content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(title).font(.headline)
			content
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
				Button(confirmTitle) { if onConfirm() { dismiss() } }
					.keyboardShortcut(.defaultAction)
					.disabled(!canConfirm)
			}
		}
		.padding(20)
		.frame(width: width)
	}
}

struct NameSheet: View {
	var title: String
	var placeholder: String
	var onSave: (String) -> Void
	@State private var name = ""

	var body: some View {
		SheetFrame(title: title, canConfirm: !name.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: {
			onSave(name.trimmingCharacters(in: .whitespaces))
			return true
		}) {
			TextField(placeholder, text: $name).textFieldStyle(.roundedBorder)
		}
	}
}

struct NewAccountSheet: View {
	@Environment(AppModel.self) private var model
	@State private var name = ""
	@State private var kind = AccountKind.cash
	@State private var currency = "EUR"
	@State private var groupID: UUID?

	var body: some View {
		SheetFrame(title: "Add Account", canConfirm: !name.isEmpty, width: 480, onConfirm: {
			model.addOfflineAccount(name: name, kind: kind, currency: currency.uppercased(), groupID: groupID)
			return true
		}) {
			Text("Bank access through FinTS follows in a later version. Until then you can bring over your accounts from MoneyMoney, or keep an offline account where you enter or import the transactions yourself.")
				.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			Button("Import from MoneyMoney...") { model.sheet = .migration }
			Divider()
			Text("Offline account / Cash").font(.subheadline.bold())
			Form {
				TextField("Name:", text: $name)
				Picker("Account type:", selection: $kind) {
					ForEach(AccountKind.allCases.filter { $0 != .portfolio }, id: \.self) { Text($0.title).tag($0) }
				}
				TextField("Currency:", text: $currency)
				Picker("Account group:", selection: $groupID) {
					Text("None").tag(UUID?.none)
					ForEach(model.ledger.groups) { Text($0.name).tag(UUID?.some($0.id)) }
				}
			}
		}
	}
}

struct NewCategorySheet: View {
	@Environment(AppModel.self) private var model
	let isGroup: Bool
	@State private var name = ""
	@State private var parentID: UUID?

	var body: some View {
		SheetFrame(title: isGroup ? "Add Category Group" : "Add Category", canConfirm: !name.isEmpty, onConfirm: {
			model.addCategory(name: name, isGroup: isGroup, parentID: parentID)
			return true
		}) {
			Form {
				TextField("Name:", text: $name)
				Picker("In group:", selection: $parentID) {
					Text("None").tag(UUID?.none)
					ForEach(model.ledger.categoriesInSidebarOrder.filter(\.isGroup)) { Text(model.ledger.categoryPath($0.id)).tag(UUID?.some($0.id)) }
				}
			}
		}
		.onAppear {
			if case let .category(id) = model.selection, let c = model.ledger.category(id) { parentID = c.isGroup ? c.id : c.parentID }
		}
	}
}

struct AccountSettingsSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let accountID: UUID
	@State private var account: Account?
	@State private var initialBalance = ""
	@State private var confirmRemove = false

	var body: some View {
		if let original = model.ledger.account(accountID) {
			SheetFrame(title: "Settings for \(original.name)", width: 520, onConfirm: {
				guard var a = account else { return true }
				if let d = AmountParser.decimal(from: initialBalance) { a.initialBalanceMinor = Money(d, currency: a.currency).minorUnits }
				model.save(account: a)
				return true
			}) {
				if let binding = Binding($account) {
					Form {
						TextField("Name:", text: binding.name)
						Picker("Account type:", selection: binding.kind) {
							ForEach(AccountKind.allCases, id: \.self) { Text($0.title).tag($0) }
						}
						LabeledContent("Currency:", value: original.currency)
						if let iban = original.iban { LabeledContent("IBAN:", value: Format.iban(iban)).textSelection(.enabled) }
						if let bic = original.bic { LabeledContent("BIC:", value: bic) }
						if let number = original.accountNumber { LabeledContent("Account number:", value: number) }
						if let owner = original.owner { LabeledContent("Account owner:", value: owner) }
						HStack {
							TextField("Initial balance:", text: $initialBalance)
							Button("Calibrate") {
								// Sets the initial balance so that the computed balance meets the balance of the bank.
								if let bank = original.bankBalanceMinor {
									let booked = model.ledger.computedBalance(of: original).minorUnits - original.initialBalanceMinor
									initialBalance = Format.money(bank - booked, original.currency)
								}
							}
							.disabled(original.bankBalanceMinor == nil)
							.help("Make the computed balance end at the balance of the bank")
						}
						Toggle("The account has been closed", isOn: binding.isClosed)
					}
					HStack {
						Button("Remove Account...", role: .destructive) { confirmRemove = true }
						Spacer()
					}
				}
			}
			.onAppear {
				account = original
				initialBalance = Format.money(original.initialBalanceMinor, original.currency)
			}
			.confirmationDialog("Are you sure you want to remove the account \(original.name)?", isPresented: $confirmRemove) {
				Button("Remove", role: .destructive) {
					model.remove(account: original.id)
					dismiss()
				}
			} message: {
				Text("All transactions of this account will be removed as well. You could alternatively mark the account as closed in the account settings.")
			}
		}
	}
}

struct GroupSettingsSheet: View {
	@Environment(AppModel.self) private var model
	let groupID: UUID
	@State private var group: AccountGroup?

	var body: some View {
		SheetFrame(title: "Account Group Settings", onConfirm: {
			if let group { model.save(group: group) }
			return true
		}) {
			if let binding = Binding($group) {
				Form {
					TextField("Name:", text: binding.name)
					Toggle("Display balance in sidebar", isOn: binding.showSum)
				}
			}
		}
		.onAppear { group = model.ledger.group(groupID) }
	}
}

struct CommentSheet: View {
	@Environment(AppModel.self) private var model
	let ids: Set<UUID>
	@State private var text = ""

	var body: some View {
		SheetFrame(title: ids.count == 1 ? "Comment" : "Comment for \(ids.count) transactions", onConfirm: {
			model.setComment(text, for: ids)
			return true
		}) {
			TextEditor(text: $text)
				.font(.body)
				.frame(height: 120)
				.border(Color.secondary.opacity(0.3))
		}
		.onAppear { text = ids.first.flatMap { model.ledger.transaction($0)?.comment } ?? "" }
	}
}

struct TransactionSheet: View {
	@Environment(AppModel.self) private var model
	let transactionID: UUID?
	@State private var date = Date()
	@State private var name = ""
	@State private var purpose = ""
	@State private var amount = ""
	@State private var isDeposit = false
	@State private var categoryID: UUID?
	@State private var comment = ""

	private var existing: Transaction? { transactionID.flatMap { model.ledger.transaction($0) } }
	private var account: Account? { existing.flatMap { model.ledger.account($0.accountID) } ?? model.selectedAccount }
	private var editable: Bool { account?.isOffline ?? false }

	var body: some View {
		SheetFrame(title: existing == nil ? "New transaction" : "Edit Transaction", canConfirm: !editable || AmountParser.decimal(from: amount) != nil, width: 500, onConfirm: save) {
			Form {
				if editable {
					DatePicker("Date:", selection: $date, displayedComponents: .date)
					TextField("Name:", text: $name)
					HStack {
						Picker("", selection: $isDeposit) {
							Text("Withdrawal").tag(false)
							Text("Deposit").tag(true)
						}
						.labelsHidden()
						.fixedSize()
						TextField("Amount:", text: $amount)
					}
					TextField("Purpose:", text: $purpose)
				} else if let t = existing {
					LabeledContent("Date:", value: Format.day(t.bookingDate))
					LabeledContent("Name:", value: t.name)
					LabeledContent("Amount:") { AmountText(money: t.amount) }
					LabeledContent("Purpose:") { Text(t.purpose).textSelection(.enabled) }
					if let iban = t.counterpartyIBAN { LabeledContent("IBAN:", value: Format.iban(iban)) }
					if let bic = t.counterpartyBIC { LabeledContent("BIC:", value: bic) }
					if let text = t.bookingText { LabeledContent("Transaction type:", value: text) }
					if let e = t.endToEndReference { LabeledContent("End-to-end reference:", value: e) }
					if let m = t.mandateReference { LabeledContent("Mandate reference:", value: m) }
					if let c = t.creditorID { LabeledContent("Creditor ID:", value: c) }
					if let v = t.valueDate { LabeledContent("Value date:", value: Format.day(v)) }
				}
				Picker("Category:", selection: $categoryID) {
					Text(model.ledger.defaultCategory?.name ?? "Uncategorized").tag(UUID?.none)
					ForEach(model.ledger.categoriesInSidebarOrder.filter { !$0.isGroup && !$0.isDefault }) { Text(model.ledger.categoryPath($0.id)).tag(UUID?.some($0.id)) }
				}
				TextField("Comment:", text: $comment)
			}
		}
		.onAppear(perform: load)
	}

	private func load() {
		guard let t = existing else { return }
		date = t.bookingDate.date()
		name = t.name
		purpose = t.purpose
		isDeposit = t.amountMinor > 0
		amount = Format.money(Money(minorUnits: abs(t.amountMinor), currency: t.currency)).replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
		categoryID = t.categoryID
		comment = t.comment ?? ""
	}

	private func save() -> Bool {
		guard let account else { return true }
		var t = existing ?? Transaction(accountID: account.id, bookingDate: Day(date), amountMinor: 0, currency: account.currency, name: "")
		if editable {
			guard let value = AmountParser.decimal(from: amount) else { return false }
			t.bookingDate = Day(date)
			t.name = name
			t.purpose = purpose
			t.amountMinor = Money(abs(value), currency: account.currency).minorUnits * (isDeposit ? 1 : -1)
		}
		if categoryID != t.categoryID {
			t.categoryID = categoryID
			t.categorizedBy = categoryID == nil ? .none : .manual
		}
		t.comment = comment.isEmpty ? nil : comment
		model.save(transaction: t)
		return true
	}
}

struct SetPasswordSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading) {
			Text("Set Database Password").font(.headline).padding([.top, .horizontal])
			PasswordForm(confirmTitle: "Set Password", requireWarning: true) { pw in
				model.setPassword(pw)
				dismiss()
			}
			HStack {
				Spacer()
				Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
			}
			.padding([.bottom, .horizontal])
		}
		.frame(width: 460)
	}
}

struct ChangePasswordSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	@State private var current = ""
	@State private var new = ""
	@State private var repeated = ""
	@State private var error: String?
	@State private var done = false

	var body: some View {
		SheetFrame(title: "Change Database Password", canConfirm: !current.isEmpty && !new.isEmpty && new == repeated, onConfirm: {
			if new == current {
				error = "The new password must not be identical to the old password."
				return false
			}
			error = model.changePassword(current: current, new: new)
			if error == nil { model.alert = AlertMessage(title: "The password has been changed.", message: "") }
			return error == nil
		}) {
			Form {
				SecureField("Current password:", text: $current)
				SecureField("New password:", text: $new)
				SecureField("Repeat new password:", text: $repeated)
				if !new.isEmpty { LabeledContent("Strength:") { Text(PasswordStrength.grade(new)).foregroundStyle(PasswordStrength.color(new)) } }
				if !repeated.isEmpty, repeated != new { Text("The new passwords differ.").foregroundStyle(.red) }
				if let error { Text(error).foregroundStyle(.red) }
			}
			Text("Nobody can recover a forgotten database password.").font(.callout).foregroundStyle(.secondary)
		}
	}
}
