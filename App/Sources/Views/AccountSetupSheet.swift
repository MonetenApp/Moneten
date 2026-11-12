import Domain
import FinTS
import Sync
import SwiftUI

/// The "Add Account" assistant (add-account-setup): the bank, the login data, and the accounts.
/// Progress, cancel, and errors stay inside the assistant. A TAN that the bank asks for during the
/// login opens the dialog of the session broker on top of the assistant.
@MainActor
@Observable
final class AccountSetup {
	enum Step: Equatable {
		case bank, login, accounts
		/// "Offline account / Cash" under "Other": the name and the currency, and no bank.
		case offline
	}

	/// What the first step found for the entry.
	enum Lookup: Equatable {
		case none
		case searching
		case found(bankCode: String, FinTSBank)
		case failed(String)
	}

	/// The services under "Other". The services of installed web banking extensions join this list
	/// with E6 of the extension plan, each with its own login step.
	enum Service: Hashable, CaseIterable {
		case offline

		var title: String {
			switch self {
			case .offline: "Offline account / Cash"
			}
		}
	}

	/// An account that the bank listed, as the app would add it.
	struct Candidate: Identifiable {
		let account: Account
		let match: SetupMatch
		var id: String { account.remoteID ?? "" }
		var isPresent: Bool { if case .present = match { true } else { false } }
	}

	private unowned let model: AppModel
	var groupID: UUID?
	private(set) var step = Step.bank

	var entry = "" {
		didSet { if entry != oldValue, !entry.isEmpty { service = nil } }
	}
	/// The choice under "Other" in place of a bank.
	var service: Service?
	var usesOther: Bool { service != nil }
	private(set) var lookup = Lookup.none
	/// Entry errors show after the first "Next", so that half an IBAN is not an error while it is typed.
	private var showsEntryErrors = false

	var loginName = ""
	var pin = ""
	private(set) var loginError: String?
	private(set) var isLoggingIn = false

	private(set) var candidates: [Candidate] = []
	var selected: Set<String> = []
	/// The account that a candidate with a choice connects, by the ID of the candidate's account. None adds a new account.
	var connecting: [UUID: UUID] = [:]
	private(set) var notices: [String] = []
	private var access: Access?
	private var state: AccessState?

	var offlineName = ""
	var offlineKind = AccountKind.cash
	var offlineCurrency = "EUR"

	private var task: Task<Void, Never>?

	init(model: AppModel, groupID: UUID?) {
		self.model = model
		self.groupID = groupID
	}

	var bank: FinTSBank? {
		if case let .found(_, bank) = lookup { bank } else { nil }
	}

	var canGoOn: Bool {
		switch step {
		case .bank: lookup != .searching
		case .login: !isLoggingIn && !loginName.trimmingCharacters(in: .whitespaces).isEmpty && !pin.isEmpty
		case .accounts: !selected.isEmpty
		case .offline: !offlineName.trimmingCharacters(in: .whitespaces).isEmpty
		}
	}

	/// Looks up the bank of the entry while the user types. The views run it after a short pause.
	func lookUp() async {
		guard !usesOther else { return }
		let code: String
		do {
			code = try BankEntry.bankCode(of: entry)
		} catch {
			lookup = showsEntryErrors ? .failed(error.message) : .none
			return
		}
		lookup = .searching
		do {
			let bank = try await model.fints.bankInfo(bankCode: code)
			guard !Task.isCancelled else { return }
			if let bank, bank.url != nil {
				lookup = .found(bankCode: code, bank)
			} else if let bank {
				lookup = .failed("\(bank.name) does not provide a FinTS/HBCI server. An extension can add support for the bank.")
			} else {
				lookup = .failed("The Bankleitzahl is invalid.")
			}
		} catch {
			guard !Task.isCancelled else { return }
			lookup = .failed(Self.message(error))
		}
	}

	func next() {
		switch step {
		case .bank:
			if usesOther {
				// E6: an extension service goes on to its own login step here.
				step = .offline
				return
			}
			showsEntryErrors = true
			if bank != nil {
				step = .login
				return
			}
			task = Task {
				await lookUp()
				if bank != nil { step = .login }
			}
		case .login:
			logIn()
		case .accounts:
			finish()
		case .offline:
			model.addOfflineAccount(name: offlineName.trimmingCharacters(in: .whitespaces), kind: offlineKind, currency: offlineCurrency.uppercased(), groupID: groupID)
			model.closeAccountSetup()
		}
	}

	func back() {
		cancelTask()
		loginError = nil
		step = step == .accounts ? .login : .bank
	}

	func cancel() {
		cancelTask()
	}

	private func cancelTask() {
		task?.cancel()
		task = nil
		isLoggingIn = false
	}

	/// Logs in with the PIN of this step and lists the accounts. A rejected PIN ends the login, and the
	/// message of the bank shows here with an empty PIN field.
	private func logIn() {
		guard case let .found(code, bank) = lookup, let url = bank.url else { return }
		let access = Access(source: .fints(bankCode: code, url: url), bankName: bank.name, loginName: loginName.trimmingCharacters(in: .whitespaces))
		let session = SetupSession(broker: model.sync.broker, access: access, pin: Secret(pin))
		loginError = nil
		isLoggingIn = true
		task = Task {
			do {
				let list = try await model.fints.listAccounts(of: access, state: nil, session: session)
				guard !Task.isCancelled else { return }
				isLoggingIn = false
				guard !list.accounts.isEmpty else {
					loginError = "The bank reported no accounts for this login. Enter your user ID in place of an alias, or ask the bank to activate the FinTS access."
					return
				}
				self.access = access
				state = list.state
				notices = list.notices.map(\.text)
				candidates = list.accounts.map { listed in
					let account = Account(groupID: groupID, position: 0, name: listed.productName ?? listed.kind.title, kind: listed.kind, source: .bank,
						currency: listed.currency, iban: listed.iban, bic: listed.bic ?? bank.bic, accountNumber: listed.number, bankCode: code, bankName: bank.name,
						owner: listed.owner, accessID: access.id, remoteID: listed.remoteID)
					return Candidate(account: account, match: model.ledger.setupMatch(for: account))
				}
				selected = Set(candidates.filter { !$0.isPresent }.map(\.id))
				step = .accounts
			} catch {
				guard !Task.isCancelled else { return }
				isLoggingIn = false
				// The user canceled the TAN dialog: the login step stays as it was.
				if error is CancellationError { return }
				pin = ""
				loginError = Self.message(error)
			}
		}
	}

	private func finish() {
		guard let access else { return }
		let chosen = candidates.filter { selected.contains($0.id) && !$0.isPresent }.map(\.account)
		guard !chosen.isEmpty else { return }
		model.add(access, state: state, accounts: chosen, connecting: connecting, pin: Secret(pin))
		model.closeAccountSetup()
	}

	private static func message(_ error: Error) -> String {
		(error as? SyncFailure)?.message ?? error.localizedDescription
	}
}

struct AccountSetupSheet: View {
	@Environment(AppModel.self) private var model
	@Bindable var setup: AccountSetup

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text("Add Account")
				.font(.title3.weight(.semibold))
				.padding(.horizontal, 20)
				.padding(.top, 20)
			SheetForm {
				switch setup.step {
				case .bank: bankStep
				case .login: loginStep
				case .accounts: accountsStep
				case .offline: offlineStep
				}
			}
			SheetButtons {
				if setup.step != .bank {
					Button("Back") { setup.back() }
				}
				Spacer(minLength: 16)
				Button("Cancel", role: .cancel) { model.closeAccountSetup() }.keyboardShortcut(.cancelAction)
				Button(setup.step == .accounts || setup.step == .offline ? "Done" : "Next") { setup.next() }
					.keyboardShortcut(.defaultAction)
					.disabled(!setup.canGoOn)
			}
		}
		.frame(width: 480)
		.task(id: setup.usesOther ? "" : setup.entry) {
			guard setup.step == .bank else { return }
			try? await Task.sleep(for: .milliseconds(400))
			guard !Task.isCancelled else { return }
			await setup.lookUp()
		}
	}

	@ViewBuilder private var bankStep: some View {
		Section {
			TextField("IBAN or Bankleitzahl", text: $setup.entry, prompt: Text("DE02 1203 0000 0000 2020 51"))
			if !setup.usesOther {
				switch setup.lookup {
				case .none:
					EmptyView()
				case .searching:
					HStack(spacing: 6) {
						ProgressView().controlSize(.small)
						Text("Looking up the bank...").foregroundStyle(.secondary)
					}
				case let .found(_, bank):
					Label(bank.name, systemImage: "building.columns")
				case let .failed(message):
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		Section {
			Picker("Other", selection: $setup.service) {
				Text("None").tag(AccountSetup.Service?.none)
				ForEach(AccountSetup.Service.allCases, id: \.self) { Text($0.title).tag(AccountSetup.Service?.some($0)) }
			}
		}
	}

	@ViewBuilder private var loginStep: some View {
		Section {
			LabeledContent("Bank", value: setup.bank?.name ?? "")
		}
		Section {
			TextField("User ID", text: $setup.loginName, prompt: Text("Required"))
			SecureField("PIN", text: $setup.pin, prompt: Text("Required"))
				.textContentType(nil)
		}
		.disabled(setup.isLoggingIn)
		if let error = setup.loginError {
			Section {
				Label(error, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		if setup.isLoggingIn {
			Section {
				HStack(spacing: 6) {
					ProgressView().controlSize(.small)
					Text("Setting up Accounts...").foregroundStyle(.secondary)
				}
			}
		}
	}

	@ViewBuilder private var accountsStep: some View {
		Section("Accounts of \(setup.bank?.name ?? "the bank")") {
			ForEach(setup.candidates) { candidate in
				Toggle(isOn: Binding(get: { setup.selected.contains(candidate.id) },
					set: { if $0 { setup.selected.insert(candidate.id) } else { setup.selected.remove(candidate.id) } })) {
					CandidateRow(candidate: candidate)
				}
				.toggleStyle(.checkbox)
				.disabled(candidate.isPresent)
				if case let .choice(accounts) = candidate.match {
					Picker("Connect to", selection: Binding(get: { setup.connecting[candidate.account.id] },
						set: { setup.connecting[candidate.account.id] = $0 })) {
						Text("New account").tag(UUID?.none)
						ForEach(accounts) { Text($0.name).tag(UUID?.some($0.id)) }
					}
					.padding(.leading, 20)
					.disabled(!setup.selected.contains(candidate.id))
				}
			}
		}
		if !setup.notices.isEmpty {
			Section("Notices of the bank") {
				ForEach(setup.notices, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
			}
		}
	}

	@ViewBuilder private var offlineStep: some View {
		Section("Offline account / Cash") {
			TextField("Name", text: $setup.offlineName, prompt: Text("Required"))
			Picker("Account type", selection: $setup.offlineKind) {
				ForEach(AccountKind.allCases.filter { $0 != .portfolio }, id: \.self) { Text($0.title).tag($0) }
			}
			TextField("Currency", text: $setup.offlineCurrency)
			Picker("Account group", selection: $setup.groupID) {
				Text("None").tag(UUID?.none)
				ForEach(model.ledger.groups) { Text($0.name).tag(UUID?.some($0.id)) }
			}
		}
	}
}

/// An account that the bank listed: its name, type, IBAN or number, and currency, and whether the app has it already.
private struct CandidateRow: View {
	let candidate: AccountSetup.Candidate

	var body: some View {
		let a = candidate.account
		VStack(alignment: .leading, spacing: 2) {
			Text(a.name)
			Text([a.kind.title, a.iban.map(Format.iban) ?? a.accountNumber, a.currency].compactMap { $0 }.joined(separator: " · "))
				.font(.callout)
				.foregroundStyle(.secondary)
			switch candidate.match {
			case .new:
				EmptyView()
			case let .present(existing):
				Text("Already in Moneten as “\(existing.name)”").font(.callout).foregroundStyle(.secondary)
			case let .connects(existing):
				Text("Connects “\(existing.name)”, which keeps its transactions").font(.callout).foregroundStyle(.secondary)
			case .choice:
				Text("Several accounts in Moneten match. Choose the one to connect, which keeps its transactions.").font(.callout).foregroundStyle(.secondary)
			}
		}
	}
}
