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

	/// The services under "Other": an offline account, and each service of an installed extension that
	/// may run, which goes on to the login dialog of the extension.
	enum Service: Hashable {
		case offline
		case extensionService(id: String, name: String)

		var title: String {
			switch self {
			case .offline: "Offline account / Cash"
			case let .extensionService(_, name): name
			}
		}
	}

	/// The services of the extensions that may run, as the library lists them with the rows of the Extensions window.
	var otherServices: [Service] {
		[.offline] + model.extensions.setupServices.map { Service.extensionService(id: $0.id, name: $0.service) }
	}

	/// Why the extension of the chosen service cannot run now.
	private(set) var serviceError: String?

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

	/// "IBAN or Bankleitzahl" and the bank that it names.
	let lookup: BankLookup
	var entry: String {
		get { lookup.entry }
		set {
			if newValue != lookup.entry, !newValue.isEmpty { service = nil }
			lookup.entry = newValue
		}
	}
	/// The choice under "Other" in place of a bank.
	var service: Service? {
		didSet { serviceError = nil }
	}
	var usesOther: Bool { service != nil }
	/// Entry errors show after the first "Next", so that half an IBAN is not an error while it is typed.
	private var showsEntryErrors = false

	var loginName = ""
	var pin = ""
	/// "Save PIN", off until the user turns it on. The PIN is saved when the setup finishes, after the bank accepted it.
	var savePIN = false
	private(set) var loginError: String?
	private(set) var isLoggingIn = false

	private(set) var candidates: [Candidate] = []
	var selected: Set<String> = []
	/// The account that a candidate with a choice connects, by the ID of the candidate's account. None adds a new account.
	var connecting: [UUID: UUID] = [:]
	private(set) var notices: [String] = []
	/// The error of the database when "Done" could not store the accounts. The assistant stays open, so
	/// that the login and its TAN are not lost.
	private(set) var saveError: String?
	private var access: Access?
	private var state: AccessState?

	var offlineName = ""
	var offlineKind = AccountKind.cash
	var offlineCurrency = "EUR"

	private var task: Task<Void, Never>?

	init(model: AppModel, groupID: UUID?) {
		self.model = model
		self.groupID = groupID
		lookup = BankLookup(find: model.fints.bankInfo(bankCode:))
	}

	var bank: FinTSBank? { lookup.bank?.bank }

	var canGoOn: Bool {
		switch step {
		case .bank: lookup.state != .searching
		case .login: !isLoggingIn && !loginName.trimmingCharacters(in: .whitespaces).isEmpty && !pin.isEmpty
		case .accounts: !selected.isEmpty
		case .offline: !offlineName.trimmingCharacters(in: .whitespaces).isEmpty
		}
	}

	/// Looks up the bank of the entry while the user types. The views run it after a short pause.
	func lookUp() async {
		guard !usesOther else { return }
		await lookup.lookUp(showingErrors: showsEntryErrors)
	}

	func next() {
		switch step {
		case .bank:
			switch service {
			case .offline?:
				step = .offline
				return
			case let .extensionService(id, name)?:
				startExtension(id, service: name)
				return
			case nil: break
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
		saveError = nil
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
	/// message of the bank shows here with an empty PIN field. A login that runs is never started again,
	/// so a second "Next" sends no second PIN. The login of an access that the app has waits for its
	/// refresh, and its refresh waits for the login.
	private func logIn() {
		guard !isLoggingIn, let (code, bank) = lookup.bank, let url = bank.url else { return }
		let access = Access(source: .fints(bankCode: code, url: url), bankName: bank.name, loginName: loginName.trimmingCharacters(in: .whitespaces))
		let known = model.accesses.values.first { $0.isSameLogin(as: access) }?.id ?? access.id
		let session = SetupSession(broker: model.sync.broker, access: access, pin: Secret(pin), replacing: known)
		loginError = nil
		isLoggingIn = true
		task = Task {
			do {
				let list = try await session.logIn { [model] session in
					try await model.sync.exclusively(for: known) {
						try await model.fints.listAccounts(of: access, state: nil, session: session)
					}
				}
				guard !Task.isCancelled else { return }
				isLoggingIn = false
				guard !list.accounts.isEmpty else {
					loginError = "The bank reported no accounts for this login. Enter your user ID in place of an alias, or ask the bank to activate the FinTS access."
					return
				}
				self.access = access
				state = list.state
				notices = list.notices.map(\.text)
				let listed = list.accounts.map { $0.account(access: access, bank: bank, group: groupID) }
				candidates = listed.map { Candidate(account: $0, match: model.ledger.setupMatch(for: $0, listed: listed)) }
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

	/// Checks the extension once more and hands over to its setup, which asks for the login data in the
	/// login dialog of the extension and adds the accounts that its script lists.
	private func startExtension(_ id: String, service: String) {
		do {
			let package = try model.extensions.verifiedPackage(id)
			serviceError = nil
			model.closeAccountSetup()
			model.addExtensionAccess(package: package, service: service, fixture: model.extensions.fixtures[id], groupID: groupID)
		} catch {
			serviceError = error.message
		}
	}

	private func finish() {
		guard let access else { return }
		let chosen = candidates.filter { selected.contains($0.id) && !$0.isPresent }.map(\.account)
		guard !chosen.isEmpty else { return }
		do {
			try model.add(access, state: state, accounts: chosen, listed: candidates.map(\.account), connecting: connecting, pin: Secret(pin), savePIN: savePIN)
		} catch {
			saveError = "Could not add the accounts. \(String(describing: error))"
			return
		}
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
				switch setup.lookup.state {
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
				ForEach(setup.otherServices, id: \.self) { Text($0.title).tag(AccountSetup.Service?.some($0)) }
			}
			.onChange(of: setup.otherServices) { _, services in
				// An extension that was blocked or removed while the assistant is open leaves the choice.
				if let service = setup.service, !services.contains(service) { setup.service = nil }
			}
			if let error = setup.serviceError {
				Label(error, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
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
			Toggle("Save PIN", isOn: $setup.savePIN)
				.toggleStyle(.checkbox)
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
		if let error = setup.saveError {
			Section {
				Label(error, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
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
			case let .choice(accounts) where accounts.count == 1:
				Text("“\(accounts[0].name)” in Moneten may be this account. Choose it to connect it, which keeps its transactions.").font(.callout).foregroundStyle(.secondary)
			case .choice:
				Text("Several accounts in Moneten match. Choose the one to connect, which keeps its transactions.").font(.callout).foregroundStyle(.secondary)
			}
		}
	}
}
