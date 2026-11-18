import Domain
import FinTS
import Sync
import SwiftUI

/// The "Add Account" assistant (add-account-setup): the bank, the login data, and the accounts.
/// Progress, cancel, and errors stay inside the assistant. A TAN that the bank asks for during the
/// login opens the dialog of the session broker on top of the assistant. "Look for New Accounts..." shows
/// only its account step, and "Edit Login Data..." only its login step.
@MainActor
@Observable
final class AccountSetup {
	enum Step: Equatable {
		case bank, login, accounts
		/// "Offline account / Cash" under "Other": the name and the currency, and no bank.
		case offline
	}

	enum Purpose: Equatable {
		case add
		/// "Look for New Accounts...": the accounts of the login that the app does not have yet.
		case newAccounts(Access)
		/// "Edit Login Data...": a new login with the login data of the step, which replaces the old one only
		/// after the bank accepted it.
		case editLogin(Access)
	}

	/// The entries of "Other": the services of the extensions that may run, which the library lists with the
	/// rows of the Extensions window, and the offline account.
	var otherServices: [SetupService] {
		SetupService.menu(extensionServices: model.extensions.setupServices)
	}

	/// Why the extension of the chosen service cannot run now.
	private(set) var serviceError: String?

	private unowned let model: AppModel
	let purpose: Purpose
	var groupID: UUID?
	private(set) var step = Step.bank
	/// The bank of the access of "Look for New Accounts..." and "Edit Login Data...", which need no search.
	private var fixedBank: BankDirectory.Entry?
	/// "Look for New Accounts..." waits for the bank.
	private(set) var isListing = false
	/// Why "Look for New Accounts..." found nothing to add, or the message of the bank when its login failed.
	private(set) var listingMessage: String?

	/// "Bank, IBAN, or Bankleitzahl" and the bank that it names.
	let lookup: BankLookup
	var entry: String {
		get { lookup.entry }
		set {
			if newValue != lookup.entry, !newValue.isEmpty { service = nil }
			if newValue != lookup.entry { highlighted = 0 }
			lookup.entry = newValue
		}
	}
	/// The match that "Next" chooses, which the arrow keys move.
	var highlighted = 0
	/// The choice under "Other" in place of a bank.
	var service: SetupService? {
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

	/// The accounts that the bank listed. The account step shows its candidates.
	private(set) var listing: SetupListing?
	var candidates: [SetupListing.Candidate] { listing?.candidates ?? [] }
	var selected: Set<String> = []
	/// The account that a candidate with a choice connects, by the ID of the candidate's account. None adds a new account.
	var connecting: [UUID: UUID] = [:]
	private(set) var notices: [BankMessage] = []
	/// The error of the database when "Done" could not store the accounts. The assistant stays open, so
	/// that the login and its TAN are not lost.
	private(set) var saveError: String?
	private var access: Access?
	private var state: AccessState?

	var offlineName = ""
	var offlineKind = AccountKind.cash
	var offlineCurrency = "EUR"

	private var task: Task<Void, Never>?

	init(model: AppModel, groupID: UUID?, purpose: Purpose = .add) {
		self.model = model
		self.groupID = groupID
		self.purpose = purpose
		lookup = BankLookup { [fints = model.fints] in try await fints.bankDirectory() }
		switch purpose {
		case .add:
			fixedBank = nil
		case let .newAccounts(access):
			fixedBank = BankDirectory.Entry(access: access)
			step = .accounts
			listAccounts(of: access)
		case let .editLogin(access):
			fixedBank = BankDirectory.Entry(access: access)
			step = .login
			loginName = access.shownLoginName
			savePIN = model.sync.broker.savedPINs.contains(access.id)
			Task { await lookUpBank(of: access) }
		}
	}

	/// Takes the bank of the access from the bank directory, with its BIC and place, and returns it. Until the
	/// directory is there, and when the helper cannot send it, the bank stays as the access names it.
	@discardableResult
	private func lookUpBank(of access: Access) async -> FinTSBank? {
		if let entry = try? await model.fints.bankDirectory().bank(of: access) { fixedBank = entry }
		return fixedBank?.bank
	}

	/// The bank of the entry, or of the access that the assistant maintains.
	var chosenBank: BankDirectory.Entry? { fixedBank ?? lookup.bank }
	var bank: FinTSBank? { chosenBank?.bank }
	/// What the bank calls the login name, when Moneten knows it.
	var loginHint: LoginHint? { chosenBank?.loginHint }

	var canGoOn: Bool {
		switch step {
		case .bank: lookup.state != .searching
		case .login: !isLoggingIn && !loginName.trimmingCharacters(in: .whitespaces).isEmpty && !pin.isEmpty
		// Without a new account "Done" closes "Look for New Accounts...".
		case .accounts: !selected.isEmpty || (!isListing && candidates.isEmpty)
		case .offline: Account.acceptedName(offlineName) != nil
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
			if case let .matches(banks) = lookup.state {
				lookup.choose(banks[min(highlighted, banks.count - 1)])
				return
			}
			task = Task {
				await lookUp()
				if bank != nil { step = .login }
			}
		case .login:
			if case let .editLogin(access) = purpose { changeLogin(of: access) } else { logIn() }
		case .accounts:
			if candidates.isEmpty {
				// "Look for New Accounts..." found nothing to add. The notices of the bank that the step showed
				// count as shown, as at the end of a setup, so the window "Notice" does not show them again.
				if let access { model.bankNotices.markShown(notices, from: access.bankName) }
				model.closeAccountSetup()
			} else {
				finish()
			}
		case .offline:
			guard let name = Account.acceptedName(offlineName) else { return }
			let kind = offlineKind, currency = offlineCurrency.uppercased(), group = groupID
			Task { await model.addOfflineAccount(name: name, kind: kind, currency: currency, groupID: group) }
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
		guard !isLoggingIn, let chosenBank, let bank, let url = bank.url else { return }
		let userIDHelp = loginHint?.help
		let name = chosenBank.loginName(loginName)
		if let problem = chosenBank.loginNameProblem(name) {
			loginError = problem
			return
		}
		let access = Access(source: .fints(bankCode: chosenBank.code, url: url), bankName: bank.name, loginName: name)
		let knownAccess = model.accesses.values.first { $0.isSameLogin(as: access) }
		let known = knownAccess?.id ?? access.id
		// A refresh of the access that the app has names its notices with the bank name of that access.
		let bankName = knownAccess?.bankName ?? bank.name
		let session = SetupSession(broker: model.sync.broker, access: access, pin: Secret(pin), replacing: known)
		loginError = nil
		notices = []
		isLoggingIn = true
		task = Task {
			do {
				let list = try await session.logIn(holding: model.sync) { [model] session in
					try await model.fints.listAccounts(of: access, state: nil, session: session)
				}
				guard !Task.isCancelled else { return }
				isLoggingIn = false
				notices = list.notices
				model.bankNotices.markShown(list.notices, from: bankName)
				guard !list.accounts.isEmpty else {
					loginError = String(localized: "The bank reported no accounts for this login. Enter your user ID in place of an alias, or ask the bank to activate the FinTS access.")
					return
				}
				self.access = access
				state = list.state
				listing = SetupListing(list.accounts.map { $0.account(access: access, bank: bank, group: groupID) }, in: model.ledger)
				selected = Set(candidates.filter { !$0.isPresent }.map(\.id))
				step = .accounts
			} catch {
				loginFailed(error, userIDHelp: userIDHelp, bankName: bankName)
			}
		}
	}

	/// The login step stays with its entries and the message of the bank, and an empty PIN field. The
	/// notices of the bank before the error, such as a maintenance that makes the login fail, show under it.
	private func loginFailed(_ error: any Error, userIDHelp: String?, bankName: String) {
		guard !Task.isCancelled else { return }
		isLoggingIn = false
		let (error, shown) = model.bankNotices.setupFailed(error, from: bankName)
		// The user canceled the TAN dialog: the login step stays as it was. Its notices are dropped on
		// purpose, so the next refresh shows them in the window "Notice".
		if error is CancellationError { return }
		pin = ""
		notices = shown
		loginError = (error as? SyncFailure)?.messageAtFirstLogin(userIDHelp: userIDHelp) ?? error.localizedDescription
	}

	/// "Edit Login Data...": logs in with the login data of the step and without the stored state of the
	/// access, as a setup does, so the bank sends its parameters and TAN methods again. The bank must accept
	/// the login before the new login name and state replace the old ones ("Edit the login data of an
	/// access"). Unchanged values set the access up again ("Reinitialize an access"). The login waits for a
	/// refresh of the access, and a refresh waits for the login.
	private func changeLogin(of old: Access) {
		guard !isLoggingIn, let chosenBank else { return }
		let userIDHelp = loginHint?.help
		let name = chosenBank.loginName(loginName)
		if let problem = chosenBank.loginNameProblem(name) {
			loginError = problem
			return
		}
		let access = Access(id: old.id, source: old.source, bankName: old.bankName, loginName: name)
		guard !model.accesses.values.contains(where: { $0.id != old.id && $0.isSameLogin(as: access) }) else {
			loginError = String(localized: "Another bank access in Moneten uses this login already.")
			return
		}
		let session = SetupSession(broker: model.sync.broker, access: access, pin: Secret(pin))
		let pin = Secret(pin), savePIN = savePIN
		loginError = nil
		saveError = nil
		notices = []
		isLoggingIn = true
		task = Task {
			do {
				// The new login is stored while the login still holds the access, so a refresh that waits for it
				// runs with the new login.
				let notices = try await session.logIn(holding: model.sync) { [model] session in
					let list = try await model.fints.listAccounts(of: access, state: nil, session: session)
					try Task.checkCancellation()
					do {
						try model.updateLogin(access, state: list.state, pin: pin, savePIN: savePIN)
					} catch {
						throw LoginNotSaved(error: error)
					}
					return list.notices
				}
				model.bankNotices.add(notices, from: access.bankName)
				model.closeAccountSetup()
			} catch let failure as LoginNotSaved {
				isLoggingIn = false
				saveError = String(localized: "Could not save the login data. \(String(describing: failure.error))")
			} catch {
				loginFailed(error, userIDHelp: userIDHelp, bankName: access.bankName)
			}
		}
	}

	/// The bank accepted the edited login, but the database could not store it, so the old login stays.
	private struct LoginNotSaved: Error {
		let error: any Error
	}

	/// "Look for New Accounts...": logs in with the PIN of the access and the stored state, and lists the
	/// accounts of the login that the app does not have yet, all selected. The login waits for a refresh of
	/// the access, and a refresh asked for meanwhile waits for the login, which stores the new state of the
	/// access before it lets the refresh go.
	private func listAccounts(of access: Access) {
		guard fixedBank != nil else { return }
		let session = SetupSession(broker: model.sync.broker, access: access, pin: nil)
		isListing = true
		task = Task {
			// The new accounts get the BIC of the bank directory, which loads while the login runs.
			let directory = Task { await lookUpBank(of: access) }
			do {
				let list = try await session.logIn(holding: model.sync) { [model] session in
					let list = try await model.fints.listAccounts(of: access, state: try model.store?.state(of: access.id), session: session)
					try Task.checkCancellation()
					if let state = list.state {
						try model.store?.recordRefresh(of: access.id, state: state, accounts: [])
						model.sync.update(access, state: state)
					}
					return list
				}
				guard let bank = await directory.value, !Task.isCancelled else { return }
				isListing = false
				self.access = access
				// The account step shows the notices of the bank, as at the setup.
				notices = list.notices
				// The sheet shows only the new accounts, but each matches against all that the bank listed.
				listing = SetupListing(list.accounts.map { $0.account(access: access, bank: bank, group: groupID) }, in: model.ledger, onlyNew: true)
				selected = Set(candidates.map(\.id))
				if candidates.isEmpty { listingMessage = String(localized: "There are no new accounts.") }
			} catch {
				guard !Task.isCancelled else { return }
				isListing = false
				// The notices of the bank before the error show under it and count as shown, as at the setup.
				let (error, shown) = model.bankNotices.setupFailed(error, from: access.bankName)
				if error is CancellationError { return }
				notices = shown
				listingMessage = (error as? SyncFailure)?.message ?? String(describing: error)
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
		guard let access, let listing else { return }
		let chosen = candidates.filter { selected.contains($0.id) && !$0.isPresent }.map(\.account)
		guard !chosen.isEmpty else { return }
		do {
			// "Look for New Accounts..." logged in with the PIN of the access, not with one of the login step.
			let isNewLogin = purpose == .add
			try model.add(access, state: state, accounts: chosen, listed: listing.listed, connecting: connecting, notices: notices,
				pin: isNewLogin ? Secret(pin) : nil, savePIN: savePIN)
		} catch {
			saveError = String(localized: "Could not add the accounts. \(String(describing: error))")
			return
		}
		model.closeAccountSetup()
	}
}

struct AccountSetupSheet: View {
	@Environment(AppModel.self) private var model
	@Bindable var setup: AccountSetup
	@FocusState private var focus: Field?
	@State private var showsHelp = false

	private enum Field { case entry, loginName, pin }

	/// The bank step lists this many matches, so the sheet stays small. A longer list asks for more of the name.
	private static let shownMatches = 50

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.title3.weight(.semibold))
				Text(stepTitle)
					.foregroundStyle(.secondary)
			}
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
				if setup.purpose == .add, setup.step != .bank {
					Button("Back") { setup.back() }
				}
				if setup.purpose == .add, setup.step == .bank {
					Button { showsHelp = true } label: { Image(systemName: "questionmark.circle") }
						.buttonStyle(.borderless)
						.help("Help")
						.popover(isPresented: $showsHelp) { BankStepHelp() }
				}
				Spacer(minLength: 16)
				Button("Cancel", role: .cancel) { model.closeAccountSetup() }.keyboardShortcut(.cancelAction)
				Button(setup.step == .accounts || setup.step == .offline || setup.purpose != .add ? "Done" : "Next") { setup.next() }
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
		// The field of the step on screen takes the keyboard, so that nothing typed goes into the field of
		// another step. Back to a bank that is chosen, no field takes it: a login name typed after "Back"
		// would replace the bank.
		.task(id: setup.step) {
			// The fields of the new step are not on screen before the next turn of the run loop.
			try? await Task.sleep(for: .milliseconds(50))
			focus = switch setup.step {
			case .bank: setup.bank == nil ? .entry : nil
			case .login: setup.loginName.isEmpty ? .loginName : .pin
			case .accounts, .offline: nil
			}
		}
	}

	private var title: String {
		switch setup.purpose {
		case .add: String(localized: "Add Account")
		case .newAccounts: String(localized: "Look for New Accounts")
		case .editLogin: String(localized: "Edit Login Data")
		}
	}

	/// Which step is on screen, so that "Back" and "Next" say where the user is. The commands on an
	/// access have one step and name the bank.
	private var stepTitle: String {
		switch setup.purpose {
		case let .newAccounts(access), let .editLogin(access): return access.bankName
		case .add: break
		}
		return switch setup.step {
		case .bank: String(localized: "Step 1 of 3: Bank")
		case .login: String(localized: "Step 2 of 3: Login data")
		case .accounts: String(localized: "Step 3 of 3: Accounts")
		case .offline: String(localized: "Step 2 of 2: Offline account")
		}
	}

	@ViewBuilder private var bankStep: some View {
		Section {
			TextField("Bank, IBAN, or Bankleitzahl", text: $setup.entry, prompt: Text("Name, IBAN, or Bankleitzahl"))
				.focused($focus, equals: .entry)
				.onKeyPress(.downArrow) { moveHighlight(1) }
				.onKeyPress(.upArrow) { moveHighlight(-1) }
			if !setup.usesOther {
				switch setup.lookup.state {
				case .none:
					EmptyView()
				case .searching:
					HStack(spacing: 6) {
						ProgressView().controlSize(.small)
						Text("Looking up the bank...").foregroundStyle(.secondary)
					}
				case let .matches(banks):
					matchList(banks)
				case let .found(bank):
					Label {
						VStack(alignment: .leading, spacing: 2) {
							Text(bank.bank.name)
							Text(Self.place(of: bank)).font(.callout).foregroundStyle(.secondary)
						}
					} icon: {
						Image(systemName: "building.columns")
					}
					ForEach([bank.mergerNote, setup.lookup.note].compactMap(\.self), id: \.self) { note in
						Label(note, systemImage: "info.circle")
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				case let .failed(message):
					Label(message, systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		Section {
			Picker("Other", selection: $setup.service) {
				Text("None").tag(SetupService?.none)
				ForEach(setup.otherServices, id: \.self) { Text($0.title).tag(SetupService?.some($0)) }
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

	/// The banks that match the entry. Each row names the place and the Bankleitzahl, so that two banks
	/// of one name differ. Return chooses the highlighted row, and the arrow keys move it.
	private func matchList(_ banks: [BankDirectory.Entry]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(banks.count > Self.shownMatches
				? "\(banks.count) banks match. Type more of the name, or choose the bank. Its Bankleitzahl is digits 5 to 12 of your IBAN."
				: "Choose the bank. Its Bankleitzahl is digits 5 to 12 of your IBAN.")
				.font(.callout)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 0) {
						ForEach(Array(banks.prefix(Self.shownMatches).enumerated()), id: \.element.id) { index, bank in
							Button { setup.lookup.choose(bank) } label: {
								VStack(alignment: .leading, spacing: 1) {
									Text(bank.bank.name)
									Text(Self.place(of: bank)).font(.callout).foregroundStyle(.secondary)
								}
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.horizontal, 6)
								.padding(.vertical, 4)
								.background(index == setup.highlighted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							.id(index)
						}
					}
				}
				.frame(height: min(CGFloat(min(banks.count, Self.shownMatches)) * 42, 210))
				.onChange(of: setup.highlighted) { _, index in proxy.scrollTo(index) }
			}
		}
	}

	private func moveHighlight(_ step: Int) -> KeyPress.Result {
		guard case let .matches(banks) = setup.lookup.state else { return .ignored }
		setup.highlighted = max(0, min(setup.highlighted + step, min(banks.count, Self.shownMatches) - 1))
		return .handled
	}

	/// "Nürnberg · 76030080", and a note when the bank has no FinTS address.
	private static func place(of bank: BankDirectory.Entry) -> String {
		([bank.city, bank.code] + (bank.bank.url == nil ? [String(localized: "No FinTS")] : [])).filter { !$0.isEmpty }.joined(separator: " · ")
	}

	@ViewBuilder private var loginStep: some View {
		Section {
			LabeledContent("Bank") {
				VStack(alignment: .trailing, spacing: 2) {
					Text(setup.bank?.name ?? "")
					if let bank = setup.chosenBank {
						Text(Self.place(of: bank)).font(.callout)
					}
				}
			}
		}
		if let note = setup.loginHint?.note {
			Section {
				Label(note, systemImage: "info.circle")
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		Section {
			TextField(setup.loginHint?.label ?? String(localized: "User ID"), text: $setup.loginName, prompt: Text("Required"))
				.focused($focus, equals: .loginName)
			if let hint = setup.loginHint {
				VStack(alignment: .leading, spacing: 4) {
					Text(hint.help)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
					Link(hint.sourceTitle, destination: hint.source)
				}
				.font(.callout)
			}
			SecureField("PIN", text: $setup.pin, prompt: Text("Required"))
				.textContentType(nil)
				.focused($focus, equals: .pin)
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
			noticesSection
		}
		if let error = setup.saveError, setup.step == .login {
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
					Text(setup.purpose == .add ? "Setting up Accounts..." : "Checking the login data...").foregroundStyle(.secondary)
				}
			}
		}
	}

	@ViewBuilder private var accountsStep: some View {
		if setup.isListing {
			Section {
				HStack(spacing: 6) {
					ProgressView().controlSize(.small)
					Text("Looking for new Accounts...").foregroundStyle(.secondary)
				}
			}
		}
		if let message = setup.listingMessage {
			Section {
				Label(message, systemImage: "info.circle")
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		if !setup.candidates.isEmpty {
			accountRows
		}
		if let error = setup.saveError {
			Section {
				Label(error, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.orange)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		noticesSection
	}

	@ViewBuilder private var accountRows: some View {
		Section("Accounts of \(setup.bank?.name ?? String(localized: "the bank"))") {
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
	}

	@ViewBuilder private var noticesSection: some View {
		if !setup.notices.isEmpty {
			Section("Notices of the bank") {
				ForEach(setup.notices, id: \.text) { Text($0.text).fixedSize(horizontal: false, vertical: true) }
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

/// The help of the bank step: what it accepts, and how a credit card comes in.
struct BankStepHelp: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Enter the name of your bank, your IBAN, or the Bankleitzahl, which is digits 5 to 12 of the IBAN.")
			Text("A credit card is added with the Bankleitzahl of the bank that issued it, or with “Look for New Accounts...” on the giro account at that bank.")
		}
		.fixedSize(horizontal: false, vertical: true)
		.frame(width: 300, alignment: .leading)
		.padding(16)
	}
}

/// An account that the bank listed: its name, type, IBAN or number, and currency, and whether the app has it already.
private struct CandidateRow: View {
	let candidate: SetupListing.Candidate

	var body: some View {
		let a = candidate.account
		VStack(alignment: .leading, spacing: 2) {
			Text(a.name)
			Text([a.kind.title, a.iban?.formatted ?? a.accountNumber, a.currency].compactMap { $0 }.joined(separator: " · "))
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
