# Design

## Context

Issue #85 builds the FinTS path of the assistant on the connector of issue #13 part 1 ([add-fints-banking design](../add-fints-banking/design.md)). The services of extensions under "Other" come with E6 of the extension plan, and saved PINs with issue #86. [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) and [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) apply.

## Decisions

### The data of an access

`Storage` keeps each access in the table `access`: the source as JSON, the bank name, the login name, and the opaque `AccessState` of its connector. An account links to its access with `accessID` and to the account at the bank with `remoteID`, and keeps `refreshedAt` and `refreshError` for the status of the account-refresh spec. An access goes with its last account: `Store.deleteAccount(_:)` deletes its row and state, and the app forgets its PIN. Migration `v7` adds this and changes no existing row. [data-model.md](../../../docs/data-model.md#bank-accesses) lists the fields.

### Who owns what

- `Domain`: `BankEntry` reads "IBAN or Bankleitzahl" and runs the IBAN checks. `Ledger.setupMatch(for:)` and `Ledger.accountsToAdd(_:connecting:)` decide which listed accounts the setup adds.
- `FinTS`: `FinTSConnector.bankInfo` finds the bank, and `listAccounts` logs in and lists the accounts. `BankLookup` keeps the bank of the entry on screen: a new entry drops the bank of the last one, and a lookup that ends after the entry changed is ignored, so a quick "Next" never logs in to the bank of an earlier entry.
- `Sync`: `SetupSession` is the session of the login. It answers the PIN request with the PIN of the login step. A rejected PIN ends the login, so the message of the bank shows in the login step and the bank gets no second attempt. Every other request opens the dialogs of `SessionBroker`, one at a time with the dialogs of running refreshes.
- `Storage`: `Store.add(_:state:accounts:)` writes the access and its accounts in one transaction.
- `App`: `AccountSetup` holds the steps and their state, and `AccountSetupSheet` shows them. A TAN dialog opens as a sheet on top of the assistant.

### Seams for later work

- "Other" lists `AccountSetup.Service`, which has only "Offline account / Cash". E6 adds the services of installed extensions there, each with its own login step, and the connector of an access by its source in `AppModel`.
- After the setup, `SessionBroker.remember(_:for:)` keeps the PIN in memory, so the first refresh does not ask again. Issue #86 saves it in the database at that point when the user turns saving on.

### A migrated account takes over the access

The moneymoney-migration spec ("Connect a migrated account to its bank") lets the assistant attach a bank access to a migrated account with the same IBAN, or the same account number and Bankleitzahl, in the same currency. An account of a bank whose access is gone is connected in the same way. The third step shows such an account as "Connects", and it keeps its ID, name, group, and transactions. A closed account is never connected, so the open "Giro" wins over a closed "Giro (alt)" with the same IBAN. When several open accounts match, the row offers "Connect to" with "New account" selected, and the setup connects only the account that the user chooses. An account with an access and an offline account are shown as present and cannot be selected.

### A second setup of a login

`Store.add(_:state:accounts:)` looks for an access with the same Bankleitzahl and login name. When it finds one, the new accounts join it and it takes the new state, so one login keeps one session and one TAN for each refresh.

## Deviations from the spec

- The bank directory of hbci4java holds no field names, formats, or notes. The login step always asks for "User ID" and "PIN", and has no customer ID, no format checks, and no hint of the bank.
- The country menu is not built. A valid IBAN of another country gets the message that the app finds banks only by a German IBAN or Bankleitzahl so far.
- The bank directory marks no outdated Bankleitzahl, so the app cannot say that one is outdated.
- "Access with" is not shown, because FinTS is the only method until E6.
- The progress text is "Setting up Accounts..." without the current step, because the helper reports no progress while it lists accounts.
- "Look for New Accounts...", "Edit Login Data...", the switch of the access method, and the list of supported banks are not built.

## Risks / Trade-offs

- Each lookup of a bank starts a helper process. The first step waits 0.4 seconds after the last keystroke before it looks up.
