# Design

This design covers issue #6: the protocols that every bank source implements, the requests that a source sends to the user, and the states of a refresh. The connectors themselves come later: FinTS in issue #13 ([ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md)), extensions in issue #15, finAPI in issue #36. The last decision covers the merge of fetched transactions into the history, issue #7.

## Context

The first FinTS tests on 11 November 2026 ([bank-access.md](../../../docs/research/bank-access.md)) showed four things that the model must allow:

- A bank asks for a second factor not only at the login. Consorsbank waived it at the login (3076) and then required it for the balance and the transactions (9075). A request for the user can therefore come while accounts are fetched.
- With decoupled methods the user approves in the app of the bank, and the client checks the result by itself. hbci4java does this check and calls back before each one. The dialog shows a waiting state, and the user can only cancel.
- hbci4java asks through synchronous callbacks: PIN, TAN method, TAN medium, TAN with or without an image, the start and each retry of a decoupled approval, and notices of the bank. Each callback blocks until it gets an answer.
- A FinTS access keeps data between refreshes: bank parameters, user parameters, the system ID, and the chosen TAN method and medium. Without the system ID the bank registers a new device at every refresh.

The specs of this change, `add-tan-handling`, `add-login-credentials`, and `add-fints-banking` describe the behavior. This design decides the types and the flow that carry it.

## Goals and non-goals

Goals:

- One protocol for every source, and one set of dialogs for every request that a source sends to the user.
- A refresh is one state value per access. The UI reads it and keeps no flags of its own.
- The whole flow runs in tests with a fake connector, with no bank and no network.

Non-goals:

- Payments. `PaymentConnector`, Verification of Payee, and the payment states come with v0.2. The request types below leave room for them.
- The FinTS helper process (issue #13). The schedule of the automatic refresh came later with issue #40, see its decision below.

## Decisions

### An access is the unit of a refresh

An access is one login at one source: a FinTS user ID at one bank, an extension with its credentials, or one finAPI connection. All accounts of an access are refreshed in one session, as the requirement "One session for the accounts of one login" says, and FinTS keeps them in one dialog. A failure stays inside its access ("A failure affects only its own access").

```swift
public struct Access: Identifiable, Sendable {
	public let id: UUID
	public let source: AccessSource    // fints(bankCode:url:), extension(id:), finAPI(connection:)
	public let bankName: String        // "Musterbank", shown in dialogs and errors
	public let loginName: String       // "erika77"
}
```

The connector gets the accounts of one access at once. This replaces the per-account `refresh` that [architecture.md](../../../docs/architecture.md) planned before:

```swift
public protocol BankConnector: Sendable {
	/// Fetches balances and transactions of the given accounts of one access.
	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport
}

public struct RefreshRequest: Sendable {
	public let access: Access
	public let state: AccessState?           // what the connector returned last time
	public let accounts: [AccountRequest]    // account in the app, name, number at the bank, first day
	public let enforced: Bool                // "Enforced refresh": ask for the full history
}

public struct ConnectorReport: Sendable {
	public let outcomes: [UUID: AccountOutcome]  // by the ID of the account in the app
	public let state: AccessState?           // new state to store, also after a failure of single accounts
	public let notices: [BankMessage]        // notices of the bank for the error popover
}

public enum AccountOutcome: Sendable {
	case fetched(RefreshResult)
	case failed(SyncFailure)
}
```

A requested account without an outcome was not fetched because an earlier request of the session failed. The coordinator marks it with `SyncFailure.notFetched` ("A failure affects only its own access"). Listing the accounts of a new access comes with the FinTS connector of issue #13, which is the first code that needs it.

`AccessState` is opaque `Data` that only its connector reads, for example the passport data of hbci4java. `Storage` keeps it in the encrypted database, never in a file. It holds no PIN.

`RefreshResult` holds the balance of one account with the date the bank gave for it, the transactions, and the flag "the bank has no older transactions". The transactions are `FetchedTransactions?`: the rows and `from`, the first day that the answer covers, which can be later than the day the app asked for. Nil means the connector fetched only the balance. Holdings of a portfolio follow when a connector fetches them. Booking and value dates are `Day` values, calendar days without a time zone. The Swift probe printed FinTS dates one day early because it converted midnight in Germany to UTC.

### Requests to the user go through one asynchronous call

A connector asks the user through the session and waits for the answer:

```swift
public protocol SyncSession: Sendable {
	/// Asks the user. Throws `SyncFailure.needsUser` in an automatic refresh, `SyncFailure.challengeExpired`
	/// when the user does not answer in time, and `CancellationError` when the user cancels the dialog
	/// or the refresh is canceled.
	func ask(_ request: UserRequest) async throws -> UserAnswer

	/// Reports progress for the UI. It returns when the UI has it, so progress and requests stay in order.
	func report(_ progress: SyncProgress) async
	/// The bank rejected the PIN or blocked the access. Reported when the answer arrives, so that the
	/// PIN is forgotten before a cancel can end the refresh (add-login-credentials).
	func rejected(_ failure: SyncFailure) async
}

public enum UserRequest: Sendable {
	case pin(PINRequest)                    // the PIN sheet of add-login-credentials
	case secondFactor(SecondFactorRequest)  // the dialog "Two-Factor Authentication" of add-tan-handling
}

public struct PINRequest: Sendable {
	public let secretName: String       // "PIN" or "password"
	public let rejected: BankMessage?   // the answer of the bank to the previous PIN of this session
}

public struct SecondFactorRequest: Sendable {
	public let purpose: Purpose        // login, download, order(description)
	public let system: System          // FinTS server, website, API server
	public let loginOnly: Bool         // "Mark a TAN that covers only the login"
	public let challenge: Challenge
	public let validity: Duration      // the validity of the bank, or 5 minutes ("Expired challenge")
}

public enum Challenge: Sendable {
	case chooseTANMethod([TANMethod], current: TANMethod.ID?)
	case chooseTANMedium([String])      // empty: the bank did not deliver the list, the user types the name
	case enterTAN(prompt: String, image: ChallengeImage?)          // manual TAN, photoTAN, QR with TAN
	case flickerCode(prompt: String, code: FlickerCode)            // optical chipTAN
	case approveInApp(prompt: String, app: String?, image: ChallengeImage?, step: Step?)
	case openBrowser(URL)                                          // web forms of extensions and finAPI
}

public enum UserAnswer: Sendable {
	case pin(Secret)
	case tanMethod(TANMethod.ID)
	case tanMedium(String)
	case tan(Secret)
}
```

The request carries no access: the session belongs to one access, and the broker adds it to the dialog. `Secret` wraps a PIN or a TAN. Its `description`, `debugDescription`, and mirror show "•••", so the value can't end up in a log by accident. A TAN is never stored ("TANs are never saved"). The answer `.pin` carries the option to save the PIN, which the [design of add-login-credentials](../add-login-credentials/design.md) describes.

A canceled dialog has no answer: `ask` throws `CancellationError`, and the coordinator cancels the refresh of that access. One path then handles "Cancel" in the dialog and "Cancel Refresh".

An approval in an app has no answer from the user either. The connector starts the question and its own check at the same time. When the bank reports the approval, the connector cancels its `ask`, and the dialog closes by itself. When the user cancels, `ask` throws, and the connector stops checking:

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
	group.addTask { _ = try await session.ask(.secondFactor(approval)) }   // throws when the user cancels
	group.addTask { try await bank.waitForApproval() }                    // waits 3 s first, then the interval of the bank
	try await group.next()
	group.cancelAll()                                                     // withdraws the request, and the dialog closes
}
```

This needs no separate API for "close the dialog", and every connector handles cancellation the same way.

### The app serializes the dialogs

`SessionBroker` hands each running access a `SyncSession`. It keeps one queue for all accesses: one dialog at a time ("One dialog at a time", "One PIN sheet at a time"), in the order of the requests. A request from another access waits, and its access shows "waiting for your input" in the sidebar. For an automatic refresh the broker creates the session as unattended. Every `ask` that the PIN in memory can't answer then throws `SyncFailure.needsUser` at once, and the account shows "Refresh Account to authorize" ("An automatic refresh never asks the user").

The PIN comes from the broker as well. It answers a `.pin` request with the PIN that the user entered earlier in this run, also in an automatic refresh, and it shows the sheet only when it has none ("An unsaved PIN stays in memory until the app locks or quits", "Automatic refresh skips an access without a PIN"). It keeps the PIN only when the refresh with it finishes, so a typo is never sent again without asking, and it forgets every PIN when the app locks. The saved PINs of add-login-credentials join the memory when the database opens.

When the bank rejects a PIN, the connector asks for the PIN again, with the message of the bank in `PINRequest.rejected` ("No automatic retry after a wrong PIN"). The broker never answers this request from memory. It forgets the PIN of the access first. Then:

- In a manual refresh, it shows the PIN sheet again, with an empty field, the message of the bank, and the warning that more wrong attempts can block the access ("Typing error"). The connector sends only the PIN that the user types into this sheet. The broker keeps that PIN when the refresh finishes. When the user cancels the sheet, the refresh of the access ends as canceled.
- In an automatic refresh, `ask` throws `SyncFailure.pinRejected` with the message of the bank. No sheet opens, no second login follows, and the account shows the message ("Saved PIN no longer valid"). The next manual refresh asks for the PIN, because the broker forgot it.

A connector that can't ask again in the same session throws `SyncFailure.pinRejected` itself. The coordinator forgets the PIN, because the refresh did not finish.

The validity of a challenge starts when its dialog opens, not while it waits behind another one. When it runs out, the dialog closes and `ask` throws `SyncFailure.challengeExpired`.

### A refresh is a state machine per access

```
idle ─▶ connecting ─▶ fetching ─▶ finished
          │  ▲          │  ▲
          ▼  │          ▼  │
        needsUser     needsUser       connecting, fetching, needsUser ─▶ failed / cancelled
```

```swift
public enum SyncState: Sendable, Equatable {
	case idle
	case connecting
	case fetching(done: Int, of: Int)
	case needsUser(UserRequest.Kind, waiting: Bool, during: Activity)  // waiting: the dialog of another access is open
	case finished(SyncSummary)                                          // time, fetched accounts, failure per account
	case failed(SyncFailure)                                            // failure of the whole access
	case cancelled
}
```

`Domain` has the transitions as a pure function, `SyncState.next(_ event: SyncEvent) -> SyncState?`, which returns nil for a refused event. Tests cover each allowed transition and refuse the others. `needsUser` can follow `connecting` and `fetching`, because of the Consorsbank case above, and `during` says where the refresh continues after the answer. `finished`, `failed`, and `cancelled` allow a new start. `finished` holds the result of each account, so an access can finish while single accounts failed, for example an account without a balance order.

The app keeps one `SyncState` per access in an `@Observable` `SyncCoordinator`. The sidebar shows each account from the state of its access and the outcome of the account.

### Failures name what the user can do

```swift
public enum SyncFailure: Error, Sendable, Equatable {
	case needsUser                      // automatic refresh needed a PIN or a second factor
	case pinRejected(BankMessage)       // never sent again; a manual refresh asks again first
	case accessBlocked(BankMessage)
	case tanRejected(BankMessage)       // "Wrong TAN"
	case approvalDeclined(BankMessage?) // declined, or not answered in time
	case challengeExpired
	case notRegistered                  // FinTS 9078: the bank does not know the product number yet
	case notFetched                     // an earlier request of the same session failed
	case bank(BankMessage)              // any other answer of the bank, in its own words
	case offline                        // no Internet connection: shown only for a manual refresh
	case network(String)
	case unsupported(String)            // the bank does not offer what the account needs
}
```

`SyncFailure.message` is the text that the app shows for each case. `BankMessage` keeps the code and the text of the bank. The app shows the text to the user ("Show errors in the words of the bank"). Only the logs and diagnostics mask it, as the probes do. `notRegistered` gets its own message, because the user can't fix it: the bank has not yet taken over the registration of Moneten.

### Cancel

"Cancel Refresh" in the File menu cancels the task of each running access and drops the accesses that wait for their turn. It is enabled only while a refresh runs. When the app locks, it cancels every refresh too. A connector ends its dialog with the bank when it can, within 5 seconds, and then stops. The FinTS helper ends the dialog with HKEND. When hbci4java waits for an approval, the helper stops at the next check, and when it does not answer in time the app ends the helper process. A canceled access ends in `cancelled`, without an error on its accounts.

### Several accesses at once

The coordinator refreshes up to three accesses at the same time and starts the rest when one finishes. FinTS servers often take seconds per answer, so one access after the other makes "Refresh All Accounts" slow. Dialogs stay serialized by the broker.

### How FinTS fits

The FinTS connector of issue #13 talks to the hbci4java helper process. Each blocking callback of hbci4java becomes one `ask`:

| hbci4java callback | Request |
|---|---|
| `NEED_PT_PIN` | `.pin`, with `rejected` when the bank rejected the previous PIN of the session |
| `NEED_PT_SECMECH` | `.chooseTANMethod`, unless the access remembers a method the bank still offers |
| `NEED_PT_TANMEDIA` | `.chooseTANMedium`, unless the access remembers one |
| `NEED_PT_TAN` | `.enterTAN`, or `.flickerCode` when the bank sends an HHDuc for chipTAN |
| `NEED_PT_PHOTOTAN`, `NEED_PT_QRTAN` | `.enterTAN` with the image |
| `NEED_PT_DECOUPLED`, `NEED_PT_DECOUPLED_RETRY` | `.approveInApp`; the retry only checks for cancellation |
| `HAVE_INST_MSG` | a notice in `ConnectorReport.notices` |

The connector keeps the passport data of hbci4java as its `AccessState`.

### Where the code lives

`SessionBroker` and `SyncCoordinator` are in a library `Sync` and not in the app target, because the app target has no tests and `scripts/test.sh` runs only the libraries. `ScriptedConnector` is in a second library `SyncTesting`, which the tests, the previews, and the debug harness use. The app owns one `SyncCoordinator` in `AppModel` and shows the dialog of `SessionBroker.current` as a sheet.

### A fake connector drives tests and previews

`ScriptedConnector` plays a list of steps: ask and record the answer, ask and withdraw the request like an approval, report progress, wait, fetch an account, fail an account, and fail the access. Tests drive it through every state, through cancellation in each state, through an automatic refresh that meets a request, and through two accesses that ask at the same time. SwiftUI previews and the debug command `syncdemo` use it to show each dialog.

### Fetched transactions reach the history through one merge (issue #7)

The coordinator calls `deliver` once for each requested account that the connector fetched, on the main actor, and never for a failed, missing, or canceled one. The app merges there: `Store.merge(.refresh(result), into:)` and `Ledger.apply`. A file import calls the same merge with `.file(rows)`. When the write throws, the account fails with `SyncFailure.notSaved`, the access still finishes, and the PIN stays in memory, because the bank accepted the login. Nothing of the account changed, so the next refresh delivers the same rows again and clears the error.

[architecture.md](../../../docs/architecture.md#transactions-need-an-identity-the-bank-does-not-give) describes the rules of `reconcile`. The spec leaves these points open, and MoneyMoney's behavior is not observed for any of them:

- "Within a few days" is 7 calendar days between the booking days. The counterparty is the IBAN when both rows have one, otherwise the name, where the words of one name must lead the other.
- A row marked for review shows an orange mark. Checking the row clears the mark and the new mark, and so does "Mark All Transactions as Checked". A pending row with the mark is never dropped. Once the user checks it, a later refresh may drop it.
- A pending row with `needsReview` counts in no sum. `Ledger.computedBalance`, the data of `Sources/Domain/Charts.swift`, the sidebar amount of a category, the "Pending" sum of the header, the sum of the status line, and `Account.deriveInitialBalance` leave it out. The booked row of the review counts. So a review never counts one payment twice, whatever the rule for pending rows is. Once the user checks the pending row or deletes it, the review of that row ends, and a checked pending row counts like any other pending row.
- Only rows that a merge adds are new. A booked row keeps the new mark of its pending row.
- A pending row is dropped only when the answer covers its day, so a balance-only refresh or a short answer drops nothing.
- Source IDs belong to one account. A known ID wins over any fingerprint, and a delivered ID never takes a stored row that has another ID.
- A balance without a date from the bank gets the time of the merge. A balance in another currency than the account's is not stored.
- A deleted row stays deleted for every refresh, also an enforced one. A file import brings it back only when no refresh had delivered it.

### The schedule of the automatic refresh (issue #40)

Three parts decide an automatic refresh, each in the module that owns its data:

- `Domain`: each `Account` has a `RefreshInterval`. `Ledger.dueAccounts(at:)` returns the accounts whose interval passed since their last refresh, or since the failure of the last one, grouped by access like a refresh command. An account whose `RefreshError.waitsForUser` is true is never due. `SyncFailure.waitsForUser` sets it for a needed PIN, TAN, or login, a rejected PIN or login, and a blocked access, so the automatic refresh does not ask the bank again for something only the user can give.
- `Sync`: `AutoRefresh` holds the conditions: the setting, the unlock, the presence of the user (the display is awake), and the network. The timer of the app calls `tick()` once a minute. A condition that turns true calls it at once, which covers the launch, the unlock, the wake, and the return of the connection. The clock is injected, so the tests set the time.
- `App`: `AppModel` feeds the conditions from the lock, `NSWorkspace`, and `NWPathMonitor`, and starts the due accounts with `attended: false`. The coordinator never starts a second session for an access that runs, so a tick during a long refresh adds nothing.

The coordinator also reports the end of a run: `runEnded` runs when the last refresh ended that started while others ran. The notification of add-notifications-and-menu-bar comes once per run.

## Risks / Trade-offs

- An opaque `AccessState` is simple, but the app can't show or repair what is inside. When a connector can't read its state, it starts fresh, and the bank registers a new system ID.
- Three accesses at once can make one bank's dialog wait for another bank's. The sidebar says so, and the timeout of a challenge starts only when its dialog opens.
- Canceling `ask` to close an approval dialog depends on structured concurrency. A connector that keeps the task alive by mistake leaves the dialog open. The tests of the fake connector check that the dialog closes.
- The model has no request for the PIN change that a bank can require ("Handle a PIN change that the bank requires"). The access fails with a `bank` message until that change is built.

- The dialogs don't yet build every requirement of add-tan-handling. Changing the TAN method inside an open dialog needs an answer like `.changeTANMethod` and the list of methods in the request. The progress text while a challenge is requested ("Getting list of TAN media...") needs a progress value for the dialog. Both extend `Challenge`, `UserAnswer`, or `SyncProgress` when the FinTS connector of issue #13 can produce them. Tasks 4.1 to 4.6 list these and the other open parts.

- A delivered ID never takes a stored row with another ID. A `moneymoney:` ID of the migration only says where a row came from, so the first answer of an extension with IDs links the migrated rows by their fingerprint and gives them its own IDs. A second MoneyMoney migration still finds those rows, because it runs `reconcile` too, with `Delivery.migration`: the fingerprint matches where the ID does not. It honors every deleted row. Verified by MoneyMoneyMigrationTests "A second run adds nothing after an extension took over the ID of a migrated transaction".
- A purpose that FinTS and a bank's CSV export render differently breaks the match between a refresh and a file. This can't be checked before the FinTS connector of issue #13 exists.

## Open questions

- Does a refresh of a single account refresh the other accounts of its access too, when the bank asks for a second factor anyway? This design refreshes only the selected accounts, as the spec says.
