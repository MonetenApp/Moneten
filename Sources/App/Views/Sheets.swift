import Domain
import SwiftUI

/// The frame of every sheet: a title, grouped sections as in System Settings, and the buttons
/// at the bottom. A destructive action such as "Remove..." goes on the leading side.
struct SheetFrame<Content: View, Leading: View>: View {
	@Environment(\.dismiss) private var dismiss
	var title: String
	var confirmTitle: String?
	var cancelTitle: String?
	var canConfirm: Bool
	var width: CGFloat
	var onCancel: () -> Void
	var onConfirm: () -> Bool
	var leading: Leading
	var content: Content

	init(title: String, confirmTitle: String? = "OK", cancelTitle: String? = "Cancel", canConfirm: Bool = true, width: CGFloat = 460,
		onCancel: @escaping () -> Void = {}, onConfirm: @escaping () -> Bool,
		@ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
		self.title = title
		self.confirmTitle = confirmTitle
		self.cancelTitle = cancelTitle
		self.canConfirm = canConfirm
		self.width = width
		self.onCancel = onCancel
		self.onConfirm = onConfirm
		self.leading = leading()
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(title)
				.font(.title3.weight(.semibold))
				.padding(.horizontal, 20)
				.padding(.top, 20)
			SheetForm { content }
			SheetButtons {
				leading
				Spacer(minLength: 16)
				if let cancelTitle {
					Button(cancelTitle, role: .cancel) { onCancel(); dismiss() }.keyboardShortcut(.cancelAction)
				}
				if let confirmTitle {
					Button(confirmTitle) { if onConfirm() { dismiss() } }
						.keyboardShortcut(.defaultAction)
						.disabled(!canConfirm)
				}
			}
		}
		.frame(width: width)
	}
}

extension SheetFrame where Leading == EmptyView {
	init(title: String, confirmTitle: String? = "OK", cancelTitle: String? = "Cancel", canConfirm: Bool = true, width: CGFloat = 460,
		onCancel: @escaping () -> Void = {}, onConfirm: @escaping () -> Bool, @ViewBuilder content: () -> Content) {
		self.init(title: title, confirmTitle: confirmTitle, cancelTitle: cancelTitle, canConfirm: canConfirm, width: width,
			onCancel: onCancel, onConfirm: onConfirm, leading: { EmptyView() }, content: content)
	}
}

/// A grouped form that is as tall as its content, for sheets and popovers.
struct SheetForm<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		Form { content }
			.formStyle(.grouped)
			.scrollDisabled(true)
			.scrollContentBackground(.hidden)
			.fixedSize(horizontal: false, vertical: true)
	}
}

/// The row of buttons at the bottom of a sheet, with the same insets everywhere.
struct SheetButtons<Content: View>: View {
	@ViewBuilder var content: Content

	var body: some View {
		HStack(spacing: 8) { content }
			.padding(.horizontal, 20)
			.padding(.bottom, 20)
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
			Section {
				TextField(placeholder, text: $name, prompt: Text("Required"))
			}
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
			Section {
				LabeledContent {
					Button("Import from MoneyMoney...") { model.sheet = .migration }
				} label: {
					Text("Accounts from MoneyMoney")
					Text("Bank access through FinTS follows in a later version.")
				}
			}
			Section("Offline account / Cash") {
				TextField("Name", text: $name, prompt: Text("Required"))
				Picker("Account type", selection: $kind) {
					ForEach(AccountKind.allCases.filter { $0 != .portfolio }, id: \.self) { Text($0.title).tag($0) }
				}
				TextField("Currency", text: $currency)
				Picker("Account group", selection: $groupID) {
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
			Section {
				TextField("Name", text: $name, prompt: Text("Required"))
				Picker("In group", selection: $parentID) {
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
			SheetFrame(title: "Settings for \(original.name)", width: 500, onConfirm: {
				guard var a = account else { return true }
				if let d = AmountParser.decimal(from: initialBalance) { a.initialBalanceMinor = Money(d, currency: a.currency).minorUnits }
				model.save(account: a)
				return true
			}, leading: {
				Button("Remove Account...", role: .destructive) { confirmRemove = true }
			}) {
				if let binding = Binding($account) {
					Section {
						TextField("Name", text: binding.name)
						Picker("Account type", selection: binding.kind) {
							ForEach(AccountKind.allCases, id: \.self) { Text($0.title).tag($0) }
						}
					}
					Section("Bank details") {
						LabeledContent("Currency", value: original.currency)
						if let iban = original.iban { LabeledContent("IBAN") { Text(Format.iban(iban)).textSelection(.enabled) } }
						if let bic = original.bic { LabeledContent("BIC") { Text(bic).textSelection(.enabled) } }
						if let number = original.accountNumber, number != original.iban { LabeledContent("Account number", value: number) }
						if let owner = original.owner { LabeledContent("Account owner", value: owner) }
					}
					Section {
						LabeledContent("Initial balance") {
							HStack(spacing: 8) {
								TextField("Initial balance", text: $initialBalance)
									.labelsHidden()
									.multilineTextAlignment(.trailing)
									.monospacedDigit()
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
						}
						Toggle("The account has been closed", isOn: binding.isClosed)
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
				Section {
					TextField("Name", text: binding.name)
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
			Section {
				TextField("Comment", text: $text, prompt: Text("Comment"), axis: .vertical)
					.labelsHidden()
					.lineLimit(5...10)
			}
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
		SheetFrame(title: existing == nil ? "New Transaction" : "Edit Transaction", canConfirm: !editable || AmountParser.decimal(from: amount) != nil, width: 500, onConfirm: save) {
			if editable {
				Section {
					DatePicker("Date", selection: $date, displayedComponents: .date)
					TextField("Name", text: $name)
					Picker("Type", selection: $isDeposit) {
						Text("Withdrawal").tag(false)
						Text("Deposit").tag(true)
					}
					.pickerStyle(.segmented)
					TextField("Amount", text: $amount, prompt: Text("0,00"))
						.multilineTextAlignment(.trailing)
						.monospacedDigit()
					TextField("Purpose", text: $purpose, prompt: Text("Optional"), axis: .vertical).lineLimit(1...4)
				}
			} else if let t = existing {
				Section {
					LabeledContent("Date", value: Format.day(t.bookingDate))
					LabeledContent("Name", value: t.name)
					LabeledContent("Amount") { AmountText(money: t.amount) }
					LabeledContent("Purpose") { Text(t.purpose).textSelection(.enabled).multilineTextAlignment(.trailing) }
				}
				if t.counterpartyIBAN != nil || t.bookingText != nil || t.endToEndReference != nil || t.mandateReference != nil || t.creditorID != nil || t.valueDate != nil {
					Section("Details") {
						if let iban = t.counterpartyIBAN { LabeledContent("IBAN") { Text(Format.iban(iban)).textSelection(.enabled) } }
						if let bic = t.counterpartyBIC { LabeledContent("BIC", value: bic) }
						if let text = t.bookingText { LabeledContent("Transaction type", value: text) }
						if let e = t.endToEndReference { LabeledContent("End-to-end reference") { Text(e).textSelection(.enabled) } }
						if let m = t.mandateReference { LabeledContent("Mandate reference") { Text(m).textSelection(.enabled) } }
						if let c = t.creditorID { LabeledContent("Creditor ID") { Text(c).textSelection(.enabled) } }
						if let v = t.valueDate { LabeledContent("Value date", value: Format.day(v)) }
					}
				}
			}
			Section {
				Picker("Category", selection: $categoryID) {
					Text(model.ledger.defaultCategory?.name ?? "Uncategorized").tag(UUID?.none)
					ForEach(model.ledger.categoriesInSidebarOrder.filter { !$0.isGroup && !$0.isDefault }) { Text(model.ledger.categoryPath($0.id)).tag(UUID?.some($0.id)) }
				}
				TextField("Comment", text: $comment, prompt: Text("Optional"), axis: .vertical).lineLimit(1...4)
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
		VStack(alignment: .leading, spacing: 0) {
			Text("Set Database Password")
				.font(.title3.weight(.semibold))
				.padding(.horizontal, 20)
				.padding(.top, 20)
			PasswordForm(confirmTitle: "Set Password", requireWarning: true, onCancel: { dismiss() }) { pw in
				model.setPassword(pw)
				dismiss()
			}
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
			Section {
				SecureField("Current password", text: $current, prompt: Text("Required"))
			} footer: {
				if let error { Text(error).foregroundStyle(.red) }
			}
			Section {
				SecureField("New password", text: $new, prompt: Text("Required"))
				SecureField("Repeat new password", text: $repeated, prompt: Text("Required"))
				if !new.isEmpty {
					LabeledContent("Strength") { Text(PasswordStrength.grade(new)).foregroundStyle(PasswordStrength.color(new)) }
				}
			} footer: {
				if !repeated.isEmpty, repeated != new {
					Text("The new passwords differ.").foregroundStyle(.red)
				} else {
					Text("Nobody can recover a forgotten database password.").foregroundStyle(.secondary)
				}
			}
		}
	}
}
