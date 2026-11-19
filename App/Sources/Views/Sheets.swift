import Domain
import SwiftUI

/// The frame of every sheet: a title, grouped sections as in System Settings, and the buttons
/// at the bottom. A destructive action such as "Remove..." goes on the leading side.
struct SheetFrame<Content: View, Leading: View>: View {
	@Environment(\.dismiss) private var dismiss
	var title: LocalizedStringKey
	var confirmTitle: LocalizedStringKey?
	var cancelTitle: LocalizedStringKey?
	var canConfirm: Bool
	var canCancel: Bool
	var width: CGFloat
	var onCancel: () -> Void
	/// Decides whether "Cancel" closes the sheet. A cancel that comes too late to stop the work keeps it open.
	var closesOnCancel: () -> Bool
	var onConfirm: () -> Bool
	var leading: Leading
	var content: Content

	init(title: LocalizedStringKey, confirmTitle: LocalizedStringKey? = "OK", cancelTitle: LocalizedStringKey? = "Cancel", canConfirm: Bool = true, canCancel: Bool = true,
		width: CGFloat = 460, onCancel: @escaping () -> Void = {}, closesOnCancel: @escaping () -> Bool = { true }, onConfirm: @escaping () -> Bool,
		@ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
		self.title = title
		self.confirmTitle = confirmTitle
		self.cancelTitle = cancelTitle
		self.canConfirm = canConfirm
		self.canCancel = canCancel
		self.width = width
		self.onCancel = onCancel
		self.closesOnCancel = closesOnCancel
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
					Button(cancelTitle, role: .cancel) {
						guard closesOnCancel() else { return }
						onCancel()
						dismiss()
					}.keyboardShortcut(.cancelAction).disabled(!canCancel)
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
	init(title: LocalizedStringKey, confirmTitle: LocalizedStringKey? = "OK", cancelTitle: LocalizedStringKey? = "Cancel", canConfirm: Bool = true, width: CGFloat = 460,
		onCancel: @escaping () -> Void = {}, onConfirm: @escaping () -> Bool, @ViewBuilder content: () -> Content) {
		self.init(title: title, confirmTitle: confirmTitle, cancelTitle: cancelTitle, canConfirm: canConfirm, width: width,
			onCancel: onCancel, onConfirm: onConfirm, leading: { EmptyView() }, content: content)
	}
}

/// A grouped form that is as tall as its content, for sheets, popovers, and the settings window.
struct SheetForm<Content: View>: View {
	@Environment(\.sheetHasScrollAreas) private var hasScrollAreas
	@ViewBuilder var content: Content

	var body: some View {
		Form { content }
			.formStyle(.grouped)
			// A disabled form also disables the scroll views inside it.
			.scrollDisabled(!hasScrollAreas)
			.scrollContentBackground(.hidden)
			.fixedSize(horizontal: false, vertical: true)
	}
}

extension EnvironmentValues {
	/// A sheet whose content has scroll views of its own, such as the report of a migration. Its form stays as tall as its content.
	@Entry var sheetHasScrollAreas = false
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
	@Environment(AppModel.self) private var model
	let kind: SheetKind
	var title: LocalizedStringKey
	var placeholder: LocalizedStringKey
	/// The name the field starts with, such as the current name for a rename.
	@State var name = ""
	var onSave: (String) -> Void

	var body: some View {
		SheetFrame(title: title, canConfirm: !name.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: {
			onSave(name.trimmingCharacters(in: .whitespaces))
			return true
		}) {
			Section {
				TextField(placeholder, text: $name, prompt: Text("Required"))
			}
		}
		.keepsInput(name, of: kind)
		.onAppear { if let held: String = model.heldInput(for: kind) { name = held } }
	}
}

struct NewCategorySheet: View {
	@Environment(AppModel.self) private var model
	let isGroup: Bool
	/// The transactions to move into the new category.
	var assigning: Set<UUID> = []
	@State private var name = ""
	@State private var parentID: UUID?

	struct Input: Hashable, Sendable {
		var name: String
		var parentID: UUID?
	}

	private var kind: SheetKind { .newCategory(isGroup: isGroup, assigning: assigning) }

	var body: some View {
		let check = model.ledger.checkCategoryName(name, in: parentID)
		SheetFrame(title: isGroup ? "Add Category Group" : "Add Category", canConfirm: check.acceptedName != nil, onConfirm: {
			// A taken name keeps the sheet open, and the footer says why.
			guard let accepted = check.acceptedName else { return false }
			Task { await model.addCategory(name: accepted, isGroup: isGroup, parentID: parentID, assigning: assigning) }
			return true
		}) {
			Section {
				TextField("Name", text: $name, prompt: Text("Required"))
				Picker("In group", selection: $parentID) {
					Text("None").tag(UUID?.none)
					ForEach(model.ledger.categoriesInSidebarOrder.filter(\.isGroup)) { Text(model.ledger.categoryPath($0.id)).tag(UUID?.some($0.id)) }
				}
			} footer: {
				if check == .taken { CategoryNameTaken(parentID: parentID) }
			}
		}
		.keepsInput(Input(name: name, parentID: parentID), of: kind)
		.onAppear {
			if case let .category(id) = model.selection, let c = model.ledger.category(id) { parentID = c.isGroup ? c.id : c.parentID }
			if let held: Input = model.heldInput(for: kind) {
				name = held.name
				parentID = held.parentID
			}
		}
	}
}

/// The note under the name field of a category whose name another category or category group in the same group has.
struct CategoryNameTaken: View {
	@Environment(AppModel.self) private var model
	let parentID: UUID?

	var body: some View {
		Group {
			if let group = parentID.flatMap(model.ledger.category) {
				Text("This name is taken in the group \(group.name).")
			} else {
				Text("This name is taken at the top level.")
			}
		}
		.foregroundStyle(Palette.red)
	}
}

struct AccountSettingsSheet: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let accountID: UUID
	@State private var account: Account?
	/// The account as the settings opened.
	@State private var opened: Account?
	@State private var initialBalance = ""
	@State private var confirmRemovePIN = false
	@State private var calibrating = false
	/// The balance typed in the calibration window on top of the settings, while it is open.
	@State private var calibrationBalance = ""
	@State private var color = Color.accentColor
	@State private var originalColor = Color.accentColor

	/// What the lock keeps of the settings: the edited account, the account as the settings opened, the fields, and
	/// whether the calibration window is open on top of them with its typed balance.
	private struct Input: Hashable, Sendable {
		var account: Account?
		var opened: Account?
		var initialBalance: String
		var color: Color
		var originalColor: Color
		var calibrating: Bool
		var calibrationBalance: String
	}

	private var input: Input {
		Input(account: account, opened: opened, initialBalance: initialBalance, color: color, originalColor: originalColor,
			calibrating: calibrating, calibrationBalance: calibrationBalance)
	}

	/// The typed initial balance, nil while it is empty, cannot be read, or is above `Money.maxMinorUnits`.
	private func typedInitialBalance(in currency: String) -> Money? {
		Money(typed: initialBalance, currency: currency)
	}

	var body: some View {
		if let original = model.ledger.account(accountID) {
			// An initial balance above the limit, which an older version may have stored, keeps OK disabled even when the
			// user changes another field: saving would store the text of the field, and that amount must not pass again.
			// An empty name keeps OK disabled too, and the field asks for a name ("Account name").
			let canConfirm = account.flatMap { Account.acceptedName($0.name) } != nil
				&& (initialBalance.isEmpty || typedInitialBalance(in: original.currency) != nil)
			SheetFrame(title: "Settings for \(original.name)", canConfirm: canConfirm, width: 500, onConfirm: {
				guard var edited = account, let opened, var a = model.ledger.account(accountID) else { return true }
				if let typed = typedInitialBalance(in: a.currency) { edited.initialBalanceMinor = typed.minorUnits }
				// A refresh that ended while the settings were open may have set a new initial balance.
				if edited.initialBalanceMinor == account?.initialBalanceMinor { edited.initialBalanceMinor = a.initialBalanceMinor }
				// An account keeps the color of its bank or kind until the user picks one.
				if color.hex != originalColor.hex { edited.color = color.hex }
				a.takeSettings(from: edited, opened: opened)
				model.save(account: a)
				return true
			}, leading: {
				Button("Remove Account...", role: .destructive) { if model.confirmRemove(.account(accountID)) { dismiss() } }
			}) {
				if let binding = Binding($account) {
					Section {
						TextField("Name", text: binding.name, prompt: Text("Required"))
						if let choices = original.kind.choices {
							Picker("Account type", selection: binding.kind) {
								ForEach(choices, id: \.self) { Text($0.title).tag($0) }
							}
						} else {
							LabeledContent("Account type", value: original.kind.title)
						}
						LabeledContent("Color") { ColorSwatches(selection: $color) }
					}
					Section("Bank details") {
						LabeledContent("Currency", value: original.currency)
						if let iban = original.iban { LabeledContent("IBAN") { Text(iban.formatted).textSelection(.enabled) } }
						if let bic = original.bic { LabeledContent("BIC") { Text(bic).textSelection(.enabled) } }
						if let number = original.accountNumber, number != original.iban?.electronic { LabeledContent("Account number", value: number) }
						if let owner = original.owner { LabeledContent("Account owner", value: owner) }
					}
					Section {
						LabeledContent("Initial balance") {
							HStack(spacing: 8) {
								TextField("Initial balance", text: $initialBalance)
									.labelsHidden()
									.marksUnreadableAmount(initialBalance)
									.multilineTextAlignment(.trailing)
									.monospacedDigit()
								// A portfolio shows the values of its bank, so an initial balance would change none of them.
								if original.kind != .portfolio {
									Button("Calibrate...") { calibrating = true }
										.accessibilityIdentifier("calibrate")
										.help("Enter the correct balance at the end of today, and the initial balance changes by the difference")
								}
							}
						}
						Toggle("The account has been closed", isOn: binding.isClosed)
					}
					if let access = original.accessID.flatMap({ model.accesses[$0] }) {
						Section("Online banking") {
							LabeledContent("User ID", value: access.shownLoginName)
							Picker("Refresh", selection: binding.refreshInterval) {
								ForEach(RefreshInterval.allCases, id: \.self) { Text($0.title).tag($0) }
							}
							LabeledContent("PIN") {
								Button("Remove saved PIN") { confirmRemovePIN = true }
									.disabled(!model.sync.broker.savedPINs.contains(access.id))
							}
						}
						.alert("Remove the saved PIN of “\(access.bankName)”?", isPresented: $confirmRemovePIN) {
							Button("OK") { model.removeSavedPIN(of: access.id) }
							Button("Cancel", role: .cancel) {}
						} message: {
							Text("The PIN is removed for every account of this access. The next refresh asks for it.")
						}
					}
				}
			}
			.keepsInput(input, of: .accountSettings(accountID))
			// The calibration window opens on top of the settings, which keep what the user changed so far. An alert
			// that its save posts waits in `SheetAlerts` until the settings have slid out too. The settings keep the
			// typed balance of the window in their own input, so that a lock keeps both and the unlock brings both back.
			.sheet(isPresented: $calibrating, onDismiss: { calibrationBalance = "" }) {
				CalibrationSheet(accountID: accountID, onSaved: tookCalibration, keptBalance: $calibrationBalance).environment(model)
			}
			.onAppear {
				account = original
				opened = original
				initialBalance = Format.editableAmount(original.initialBalanceMinor, original.currency)
				color = AccountColors.color(of: original)
				originalColor = color
				// After the unlock, the settings show the input from before the lock. Saving merges it with the
				// account as it is now, as for a refresh that ended while the settings were open.
				if let held: Input = model.heldInput(for: .accountSettings(accountID)) {
					account = held.account
					opened = held.opened
					initialBalance = held.initialBalance
					color = held.color
					originalColor = held.originalColor
					calibrationBalance = held.calibrationBalance
					// The calibration window opens again one turn later, on top of the settings that are on screen then.
					if held.calibrating { DispatchQueue.main.async { calibrating = true } }
				}
			}
		}
	}

	/// The calibration window saved `saved`. The field shows its initial balance, and the settings take it as the
	/// value they opened with, so that OK neither enters it again nor brings back a value typed before, also when
	/// the calibration kept the value. Only a confirmed calibration calls this, never a refresh or Cancel.
	private func tookCalibration(_ saved: Account) {
		account?.initialBalanceMinor = saved.initialBalanceMinor
		opened?.initialBalanceMinor = saved.initialBalanceMinor
		initialBalance = Format.editableAmount(saved.initialBalanceMinor, saved.currency)
	}
}

/// Asks for the correct balance at the end of today and moves the initial balance by the difference, so that
/// every computed balance shifts by the same amount. It opens with the balance that the proposal fills in.
struct CalibrationSheet: View {
	@Environment(AppModel.self) private var model
	let accountID: UUID
	/// Called with the account after OK saved it, for the account settings under the window.
	var onSaved: (Account) -> Void = { _ in }
	/// The typed balance for the account settings under the window, which keep it in their input across a lock. Without
	/// it, the window is a sheet of its own and keeps its input as `SheetKind.calibration`.
	var keptBalance: Binding<String>? = nil
	@State private var balance = ""

	/// The typed balance, nil while it cannot be read or is above `Money.maxMinorUnits`.
	private func typedBalance(in currency: String) -> Money? {
		Money(typed: balance, currency: currency)
	}

	/// The account with the initial balance that the typed balance gives, nil while there is none or it is above
	/// `Money.maxMinorUnits`. Then OK stays disabled, the sheet says why, and nothing is written.
	private func calibrated(_ account: Account) -> Account? {
		typedBalance(in: account.currency).flatMap { try? model.ledger.calibrated(account, balanceToday: $0.minorUnits, today: .today()) }
	}

	var body: some View {
		if let account = model.ledger.account(accountID) {
			SheetFrame(title: "Calibrate \(account.name)", canConfirm: calibrated(account) != nil, onConfirm: {
				guard let current = model.ledger.account(accountID), let a = calibrated(current) else { return true }
				model.save(account: a)
				// A failed write leaves the ledger as it was and posts an alert, and the settings keep what was typed.
				if let saved = model.ledger.account(accountID), saved.initialBalanceMinor == a.initialBalanceMinor { onSaved(saved) }
				return true
			}) {
				Section {
					Text("Balances are computed from the initial balance and the transactions. Add missing transactions and remove duplicates first. Then enter the correct balance at the end of today, and the initial balance changes by the difference.")
						.fixedSize(horizontal: false, vertical: true)
					LabeledContent("Balance at the end of today") {
						TextField("Balance at the end of today", text: $balance)
							.labelsHidden()
							.marksUnreadableAmount(balance)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
					}
					// The transactions add up to so much that no initial balance within the limit meets the typed balance.
					if typedBalance(in: account.currency) != nil, calibrated(account) == nil {
						Text(InitialBalanceTooLarge(accountName: account.name).description)
							.foregroundStyle(Palette.red)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
			}
			.keepsInput(balance, of: keptBalance == nil ? .calibration(accountID) : nil)
			.onChange(of: balance) { if let keptBalance, keptBalance.wrappedValue != balance { keptBalance.wrappedValue = balance } }
			.onAppear {
				let today = Day.today()
				let value = model.proposedCalibration(of: account)?.balanceToday ?? model.ledger.computedBalance(of: account, through: today)
				balance = Format.editableAmount(value.minorUnits, value.currency)
				if let keptBalance {
					// The settings under the window brought its balance back after the unlock.
					if !keptBalance.wrappedValue.isEmpty { balance = keptBalance.wrappedValue }
				} else if let held: String = model.heldInput(for: .calibration(accountID)) {
					balance = held
				}
			}
		}
	}
}

struct GroupSettingsSheet: View {
	@Environment(AppModel.self) private var model
	let groupID: UUID
	@State private var group: AccountGroup?
	/// The group as the settings opened, so that a name the user did not change stays as it is stored.
	@State private var opened: AccountGroup?

	var body: some View {
		// An empty name keeps OK disabled, and the field asks for a name ("Create and rename account groups"). This holds
		// also for a name that a migration or an import stored empty, so OK never saves it again.
		let canConfirm = group.map { Account.acceptedName($0.name) != nil } ?? true
		SheetFrame(title: "Account Group Settings", canConfirm: canConfirm, onConfirm: {
			// A move or a collapse while the settings were open keeps its parent, position, and state.
			guard let group, let opened, var current = model.ledger.group(groupID) else { return true }
			current.takeSettings(from: group, opened: opened)
			model.save(group: current)
			return true
		}) {
			if let binding = Binding($group) {
				Section {
					TextField("Name", text: binding.name, prompt: Text("Required"))
					Toggle("Display balance in sidebar", isOn: binding.showSum)
					Toggle("Group transactions by account", isOn: binding.groupsByAccount)
				}
			}
		}
		.keepsInput(group, of: .groupSettings(groupID))
		.onAppear {
			group = model.ledger.group(groupID)
			// The stored group, also after the unlock: nothing writes it while the app is locked, so it is the group as
			// the settings opened before the lock.
			opened = group
			// The input is optional: nil from `heldInput` means that nothing returns, and the group stays as loaded.
			if let held: AccountGroup? = model.heldInput(for: .groupSettings(groupID)), let held { group = held }
		}
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
		.keepsInput(text, of: .comment(ids))
		.onAppear {
			text = ids.first.flatMap { model.ledger.row($0)?.comment } ?? ""
			if let held: String = model.heldInput(for: .comment(ids)) { text = held }
		}
	}
}

struct TransactionSheet: View {
	@Environment(AppModel.self) private var model
	let transactionID: UUID?
	/// The booking date, nil while its field holds a text that is not a date.
	@State private var date: Day? = .today()
	/// Whether an existing row has a value date.
	@State private var hasValueDate = false
	/// The value date, nil while its field holds a text that is not a date.
	@State private var valueDate: Day?
	@State private var draft = TransactionDraft()
	@State private var comment = ""
	@State private var problem: AmountProblem?
	/// The suggestions for the name as it stands. Only a change of the name searches again, never a redraw.
	@State private var suggestions: [Transaction] = []
	@FocusState private var nameHasFocus: Bool

	/// The text of the date fields as the user typed it, also while it is not a date yet.
	@State private var dateText = ""
	@State private var valueDateText = ""

	/// What the lock keeps of the fields, and the account that a new transaction goes into.
	struct Input: Hashable, Sendable {
		var accountID: UUID?
		var date: Day?
		var dateText: String
		var hasValueDate: Bool
		var valueDate: Day?
		var valueDateText: String
		var draft: TransactionDraft
		var comment: String
	}

	private var input: Input {
		Input(accountID: account?.id, date: date, dateText: dateText, hasValueDate: hasValueDate, valueDate: valueDate,
			valueDateText: valueDateText, draft: draft, comment: comment)
	}

	private var existing: Transaction? { transactionID.flatMap { model.ledger.row($0) } }
	private var account: Account? { existing.flatMap { model.ledger.account($0.accountID) } ?? model.selectedAccount }
	/// "Add Transaction..." adds a row to every account but a portfolio, also to one with bank access (add-offline-accounts,
	/// task 1.13). "Edit Transaction..." changes every row but a part of a split (add-transaction-list, task 1.16).
	private var editable: Bool { transactionID.map(model.ledger.editsFields) ?? true }
	/// A marked or impossible date refuses the sheet, as in the custom period.
	private var datesAreValid: Bool { !editable || (date != nil && (!hasValueDate || valueDate != nil)) }

	/// The name field of a new transaction offers earlier names. A chosen one fills the purpose and the category
	/// while they are empty.
	private var name: Binding<String> {
		Binding(get: { draft.name }, set: { typed in
			guard transactionID == nil, let account else { return draft.name = typed }
			draft.enterName(typed, offered: suggestions, for: account.id, in: model.ledger)
			suggestions = model.ledger.nameSuggestions(for: typed).filter { $0.name != typed }
		})
	}

	var body: some View {
		SheetFrame(title: transactionID == nil ? "New Transaction" : "Edit Transaction", canConfirm: datesAreValid, width: 500, onConfirm: save) {
			if let review = existing?.review {
				Section { Label(review.note, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
			}
			if editable {
				Section {
					DateField(title: "Date", day: $date, typed: $dateText)
					if existing != nil {
						LabeledContent("Value date") {
							HStack {
								Toggle("Value date", isOn: Binding(get: { hasValueDate }, set: { on in
									hasValueDate = on
									if on, valueDate == nil { valueDate = date }
								}))
								.labelsHidden()
								.accessibilityIdentifier("valuedate-switch")
								if hasValueDate {
									DateField(title: "Value date", day: $valueDate, identifier: "valuedate", typed: $valueDateText)
										.labelsHidden()
								}
							}
						}
					}
					TextField("Name", text: name)
						.focused($nameHasFocus)
						.textInputSuggestions(suggestions) { t in
							Text(t.name).textInputCompletion(t.name)
						}
					TextField("Amount", text: $draft.amount, prompt: Text("-0,00"))
						.multilineTextAlignment(.trailing)
						.marksUnreadableAmount(draft.amount)
						.monospacedDigit()
					if let problem {
						Text(problem.message).foregroundStyle(Palette.red)
					}
					TextField("Purpose", text: $draft.purpose, prompt: Text("Optional"), axis: .vertical).lineLimit(1...4)
				}
			} else if let t = existing {
				// A part of a split shows its values, because the parts must add up to the amount of the split transaction.
				Section {
					LabeledContent("Date", value: Format.day(t.bookingDate))
					if let v = t.valueDate { LabeledContent("Value date", value: Format.day(v)) }
					LabeledContent("Name", value: t.name)
					LabeledContent("Amount") { AmountText(money: t.amount) }
					LabeledContent("Purpose") { Text(t.purpose).textSelection(.enabled).multilineTextAlignment(.trailing) }
				}
			}
			// The details from the bank, in the order of the help tag of the row. The value date is a field above.
			if let details = existing?.details.filter({ if case .valueDate = $0 { false } else { true } }), !details.isEmpty {
				Section("Details") {
					ForEach(details, id: \.self) { d in
						LabeledContent(d.label) { Text(d.shownValue).textSelection(.enabled) }
					}
				}
			}
			Section {
				Picker("Category", selection: $draft.categoryID) {
					Text(model.ledger.defaultCategory?.name ?? String(localized: "Uncategorized")).tag(UUID?.none)
					ForEach(model.ledger.categoriesInSidebarOrder.filter { !$0.isGroup && !$0.isDefault }) { Text(model.ledger.categoryPath($0.id)).tag(UUID?.some($0.id)) }
				}
				TextField("Comment", text: $comment, prompt: Text("Optional"), axis: .vertical).lineLimit(1...4)
			}
		}
		.onChange(of: draft.amount) { problem = nil }
		.keepsInput(input, of: .transaction(transactionID))
		.onAppear {
			load()
			// A new transaction takes its input only in the account that it was started in.
			if let held: Input = model.heldInput(for: .transaction(transactionID)), transactionID != nil || held.accountID == account?.id {
				date = held.date
				dateText = held.dateText
				hasValueDate = held.hasValueDate
				valueDate = held.valueDate
				valueDateText = held.valueDateText
				draft = held.draft
				comment = held.comment
			}
			nameHasFocus = editable
		}
	}

	/// An existing row shows its values. A new one starts from the one selected row of the account, with today's date.
	private func load() {
		if let t = existing {
			date = t.bookingDate
			hasValueDate = t.valueDate != nil
			valueDate = t.valueDate
			draft = TransactionDraft(template: t)
			comment = t.comment ?? ""
		} else if let account {
			draft = model.ledger.newTransactionDraft(in: account, selection: model.visibleSelection)
		}
	}

	private func save() -> Bool {
		if let transactionID, model.ledger.row(transactionID) == nil { return true }
		guard let account else { return true }
		var t = existing ?? Transaction(accountID: account.id, bookingDate: date ?? .today(), amountMinor: 0, currency: account.currency, name: "", isManual: true)
		if editable {
			guard let date, !hasValueDate || valueDate != nil else { return false }
			switch draft.amountMinor(in: t.currency, region: DecimalMark(region: .current), allowsZero: existing.map { !$0.isManual } ?? false) {
			case let .failure(p):
				problem = p
				return false
			case let .success(minor):
				// `edit` keeps the values of a source, so that a refresh or a file does not add the row again. A manual
				// row has no source and takes the values.
				t.edit(OriginalValues(bookingDate: date, valueDate: hasValueDate ? valueDate : nil, amountMinor: minor, name: draft.name, purpose: draft.purpose))
			}
		}
		if draft.categoryID != t.categoryID {
			t.categoryID = draft.categoryID
			t.categorizedBy = draft.categoryID == nil ? .none : .manual
		}
		t.comment = comment.isEmpty ? nil : comment
		model.save(transaction: t, adding: transactionID == nil)
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
	@State private var current = ""
	@State private var new = ""
	@State private var repeated = ""
	@State private var error: String?

	var body: some View {
		SheetFrame(title: "Change Database Password", canConfirm: !current.isEmpty && !new.isEmpty && new == repeated, onConfirm: {
			if new == current {
				error = String(localized: "The new password must not be identical to the old password.")
				return false
			}
			error = model.changePassword(current: current, new: new)
			return error == nil
		}) {
			Section {
				SecureField("Current password", text: $current, prompt: Text("Required"))
			} footer: {
				if let error { Text(error).foregroundStyle(Palette.red) }
			}
			Section {
				SecureField("New password", text: $new, prompt: Text("Required"))
				SecureField("Repeat new password", text: $repeated, prompt: Text("Required"))
				if !new.isEmpty {
					LabeledContent("Strength") { Text(PasswordStrength.grade(new)).foregroundStyle(PasswordStrength.color(new)) }
				}
			} footer: {
				if !repeated.isEmpty, repeated != new {
					Text("The new passwords differ.").foregroundStyle(Palette.red)
				} else {
					Text("Nobody can recover a forgotten database password.").foregroundStyle(.secondary)
				}
			}
		}
	}
}
