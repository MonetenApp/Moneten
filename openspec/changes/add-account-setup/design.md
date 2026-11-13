# Design

## Context

Issue #85 builds the FinTS path of the assistant on the connector of issue #13 part 1 ([add-fints-banking design](../add-fints-banking/design.md)). The services of extensions under "Other" come with E6 of the extension plan. Issue #86 added "Save PIN" to the login step. [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) and [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) apply.

## Decisions

### The data of an access

`Storage` keeps each access in the table `access`: the source as JSON, the bank name, the login name, and the opaque `AccessState` of its connector. An account links to its access with `accessID` and to the account at the bank with `remoteID`, and keeps `refreshedAt` and `refreshError` for the status of the account-refresh spec. An access goes with its last account: `Store.deleteAccount(_:)` deletes its row and state, and the app forgets its PIN. Migration `v7` adds this and changes no existing row. [data-model.md](../../../docs/data-model.md#bank-accesses) lists the fields.

### Who owns what

- `Domain`: `BankEntry` reads an IBAN or a Bankleitzahl and runs the IBAN checks. `Ledger.setupMatch(for:listed:)` and `Ledger.accountsToAdd(_:listed:connecting:)` decide which listed accounts the setup adds.
- `FinTS`: `FinTSConnector.bankDirectory` reads the bank directory, and `listAccounts` logs in and lists the accounts. `BankLookup` keeps the bank of the entry on screen: a new entry drops the bank of the last one, and a lookup that ends after the entry changed is ignored, so a quick "Next" never logs in to the bank of an earlier entry. `LoginHint` holds what a bank calls its login name.
- `Sync`: `SetupSession` is the session of the login. It answers the PIN request with the PIN of the login step. A rejected PIN ends the login, so the message of the bank shows in the login step and the bank gets no second attempt. Every other request opens the dialogs of `SessionBroker`, one at a time with the dialogs of running refreshes.
- `Storage`: `Store.add(_:state:accounts:)` writes the access and its accounts in one transaction.
- `App`: `AccountSetup` holds the steps and their state, and `AccountSetupSheet` shows them. A TAN dialog opens as a sheet on top of the assistant.

### Seams for later work

- "Other" lists `AccountSetup.Service`, which has only "Offline account / Cash". E6 adds the services of installed extensions there, each with its own login step, and the connector of an access by its source in `AppModel`.
- After the setup, `SessionBroker.remember(_:for:save:)` keeps the PIN in memory, so the first refresh does not ask again, and saves it in the database when the user turned on "Save PIN" in the login step. The bank accepted it at the login of the setup.

### The search for a bank

The helper sends the whole bank directory of hbci4java once per assistant, with the command `banks`: 4,063 Bankleitzahlen in 535 KB, in about 0.2 seconds. `BankDirectory` keeps it in memory, so no keystroke starts a helper. An entry that starts like an IBAN, or has 8 or more digits, goes to `BankEntry`. Any other entry is a search.

A search compares each word of the entry with the words of the name and the place, in both spellings of umlauts ("muenchen" and "munchen" for "München") and without accents, and with the start of the Bankleitzahl. Every word must match. The order is:

1. Banks with a FinTS address before the others.
2. A bank whose name starts with the entry, such as "ING-DiBa" for "ing" before a bank in Ingolstadt.
3. A bank where each word starts a word of the name or the place.
4. A bank where a word only appears inside a word, such as "sparkasse" in "Stadtsparkasse".
5. The name, then the place and the Bankleitzahl, so two banks of one name stand in the order of their places.

The directory names some banks differently from their customers, such as "Deutsche Kreditbank Berlin" for DKB, so the short name of each bank with a login hint is a search word too. A search takes 4 to 12 ms in a release build and runs off the main thread. The step shows the first 50 matches. Each row has the place and the Bankleitzahl, and the step says that the Bankleitzahl is digits 5 to 12 of the IBAN, because the login sends the Bankleitzahl that the user chooses, and Consorsbank, for example, has two.

### Login hints

`LoginHint` is a table in `Sources/FinTS/LoginHints.swift`: a label for the login name field, one sentence of help, and the URL of the public page of the bank that confirms it. A bank is found by the host of its FinTS address, which is the same for all its Bankleitzahlen. The savings banks have a host each, so a savings bank is a bank with "Sparkasse" in its name on the FinTS servers of the savings banks (`s-fints-pt-` and `s-hbci.de`). That rule leaves out a Bausparkasse and the Südtiroler Sparkasse, which uses the servers of the cooperative banks. A hint without a public page of the bank is left out.

Many banks answer an unknown login name with a PIN error. Only at the first login of a setup can the login name be wrong, so only there `SyncFailure.messageAtFirstLogin(userIDHelp:)` names the user ID as well and repeats the hint. A refresh keeps the message and the rules of a rejected PIN.

### The steps and the keyboard

The line under the title names the step and its number, so that "Back" visibly leaves the login data. The field of the new step takes the keyboard focus: the login name, or the PIN when the login name is filled in. After "Back" to a chosen bank, no field takes it, so a login name typed by mistake does not replace the bank. The login name stays when the user goes back and forth.

### A migrated account takes over the access

The moneymoney-migration spec ("Connect a migrated account to its bank") lets the assistant attach a bank access to a migrated account with the same IBAN, or the same account number and Bankleitzahl, in the same currency. An account of a bank whose access is gone is connected in the same way. The third step shows such an account as "Connects", and it keeps its ID, name, group, and transactions. A closed account is never connected, so the open "Giro" wins over a closed "Giro (alt)" with the same IBAN. When several open accounts match, the row offers "Connect to" with "New account" selected, and the setup connects only the account that the user chooses. An account with an access and an offline account are shown as present and cannot be selected.

`Ledger.setupMatch(for:listed:)` compares two accounts by IBAN when both have one. Else it compares the account number and Bankleitzahl, and also `remoteID` when the account in the app has one, because FinTS keeps the subaccount number only in `remoteID`. So a second subaccount of a connected account number is new. A migrated account has no subaccount number. When it matches more than one account of the listing, each of those rows offers it under "Connect to", and the setup never connects it on its own. An account that was connected without an IBAN keeps the account and subaccount number as its `remoteID`. When the bank lists it with an IBAN later, the IDs differ and the setup lists it as new, because the listing with the IBAN no longer names the subaccount number.

### A second setup of a login

`Store.add(_:state:accounts:)` looks for an access with the same Bankleitzahl and login name. When it finds one, the new accounts join it, so one login keeps one session and one TAN for each refresh. The login of such a setup runs in `SyncCoordinator.exclusively(for:_:)`: it waits for a running refresh of the access, and a refresh that a command asks for meanwhile waits for the login. So the bank never gets two dialogs for one login.

The access keeps its stored state, and `Store.add(_:state:accounts:)` ignores the state of the setup. The refresh that waited for the login starts from the stored state and can end before or after "Done". With the state of the setup, "Done" would roll back the state of that refresh, or the refresh would roll back the state of "Done".

### Errors after the login

A second "Next" during the login sends nothing, so the bank gets the PIN once. When "Done" cannot store the accounts, the assistant stays at the third step and shows the error of the database, so the login and its TAN are not lost.

## Deviations from the spec

- The bank directory of hbci4java holds no field names, formats, or notes. The login step asks for "User ID" and "PIN", except for the five banks of `LoginHint`, and has no customer ID and no format checks. The five banks ask to leave the customer ID empty.
- The country menu is not built. A valid IBAN of another country gets the message that the app finds banks only by a German IBAN or Bankleitzahl so far, and the search covers only the German bank directory.
- The bank directory marks no outdated Bankleitzahl, so the app cannot say that one is outdated.
- "Access with" is not shown, because FinTS is the only method until E6.
- The progress text is "Setting up Accounts..." without the current step, because the helper reports no progress while it lists accounts.
- "Look for New Accounts...", "Edit Login Data...", the switch of the access method, and the list of supported banks are not built.

## Risks / Trade-offs

- The first lookup of an assistant starts a helper process for the bank directory. The first step waits 0.4 seconds after the last keystroke before it looks up.
- The bank directory comes with hbci4java and is as current as its release. A new or renamed bank appears with the next update of hbci4java.
- A login hint can go out of date when a bank changes its login. Each hint names its source page, so it can be checked again.
