# Design

## Context

See the proposal for why. [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) chose hbci4java in a helper process that talks JSON lines over a pipe. This design records how part 1 of issue #13 builds that: the helper in `Tools/FinTSHelper/FinTSHelper.java` and the connector in `Sources/FinTS/FinTSConnector.swift`. The connector implements `BankConnector` of the [add-account-refresh design](../add-account-refresh/design.md) and asks the user only through the session.

## Goals / Non-Goals

**Goals:**

- Fetch accounts, balances, and transactions through hbci4java without the PIN or a TAN ever leaving memory and the pipe.
- Let macOS decide whether to trust the server of the bank, as for every other connection of the app.
- End every run within a known time, also when the helper or the bank stops answering.

**Non-Goals:**

- Storing accesses and accounts in the database. That is part 2.
- The "Add Account" assistant, saved PINs, and the sidebar status. That is part 3.
- The tasks that `tasks.md` marks as deferred.

## Decisions

### One helper process per run

Each command starts a new JVM: `banks`, `accounts`, or `refresh`. The run ends when the helper writes its last line and exits. A crashed or stuck helper therefore never affects the next run. The JVM starts in about a second, which is small next to a dialog with a bank.

The helper gets an empty environment, `-XX:ErrorFile=/dev/null`, `-XX:+DisableAttachMechanism`, and `-Xrs`. So no agent can be loaded through the environment or the attach mechanism, a crash writes no file with the memory of the helper, and a signal writes no thread dump into the protocol.

### The protocol

`Sources/FinTS/HelperProtocol.swift` and the helper define the lines. The app sends one command, then answers to requests and a cancel. The helper sends requests for the user, progress, notices, one result per account, the new state, and errors. Every line is one JSON object with a `type`. `Tests/FinTSTests/helper-lines.jsonl` holds lines that the helper self-test writes from hbci4java, and a Swift test reads them, so both sides check the same lines.

Amounts travel as decimal strings and become minor units in the connector. Days travel as `yyyy-mm-dd` without a time zone.

### A wrong PIN

hbci4java clears the PIN only when the bank reports a wrong PIN, and calls `WRONG_PIN` right after that. The helper keeps the answer of the bank for the whole run and sends it with the next PIN request. The connector turns that into `PINRequest(rejected:)`, so the broker never answers it from memory: the PIN sheet opens again in a manual refresh, and an automatic refresh fails with `pinRejected`. 9930, 9933, and 3938 are a blocked access, and the connector stops without asking again. 3938 is a warning in FinTS, and hbci4java counts an answer with 0020 and 3938 as a successful login. No order succeeds after it, so the passport of the helper checks each answer to a dialog initialization (`DialogEvent.MSG_SENT`) and fails the dialog there: every later message and order (`MSG_CREATE`, `JOBS_CREATED`) fails with the same warning, so hbci4java sends nothing more. The setup login checks the passport first in `FinTSHelper.loggedIn`, the rest of the dialog after `HBCIHandler` returns, because hbci4java keeps a failed request of the TAN media to itself. 3931 names a blocked PIN or a TAN generator that needs a synchronization, so it keeps the text of the bank. 9931 means "Sperrung des Kontos nach Fehlversuchen", a block, but Sparkassen send it also for a wrong login name or PIN with the text "Anmeldename oder PIN ist falsch". So 9931 counts as a blocked access only when its text reports a block that happened, as "Zugang wegen ungültiger PIN gesperrt", "Sperrung des Kontos wegen ungültiger PIN", or "Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut" do. `HelperError.reportsBlock` looks for two lists of phrases. A phrase of a block that happened is "Teilnehmersperre", "Sperre durchgeführt", "Sperrung ist erfolgt", "Sperrung des Kontos", or the access, the PIN, or the account with at most four words before "gesperrt" or "blockiert", as in "Ihr Zugang wurde gesperrt". A phrase of attempts that remain, of a block to come, or of a denial is "noch 1 Fehlversuch", "verbleibend", "weitere Fehlversuche", "bei der nächsten falschen Eingabe", "bis zur Sperrung", "führen zur Sperrung", "wird ... gesperrt", "droht die Sperrung", "nicht gesperrt", or "keine Sperrung". A text is a block when it has a phrase of the first list and none of the second. The project owner chose this one rule over a reading clause by clause, which kept producing texts that it read the wrong way. Its worst error is one more PIN sheet on an access that is already blocked, as for "Nach weiteren Fehlversuchen wurde der Zugang gesperrt", and never a PIN that the app sends on its own. Every other text is a wrong PIN, also one that names no cause, such as "Anmeldung fehlgeschlagen". A text that only warns of a block to come is a wrong PIN, by the decision of the project owner: the broker forgets the PIN and sends it never again on its own, the automatic refresh skips the access, and the next PIN sheet shows the warning. The broker keeps the answer of the bank to a PIN of a refresh that failed with `pinRejected` until the next PIN sheet of the access, so the warning reaches the user also after an automatic refresh. The lock forgets it with the PINs.

### Errors of the second factor

The codes come from the FinTS return codes of the Deutsche Kreditwirtschaft (FinTS_Rueckmeldungscodes_2019-07-22), and `HelperError` in `Sources/FinTS/HelperProtocol.swift` lists their meaning. 9941, 9943, and 9948 are a TAN that the bank refused, and 9951 a two-step dialog that timed out. After an approval in the app these codes mean that the approval did not happen, so the helper marks such an error `approvalDeclined`: it knows which kind of challenge came last. Without that mark 9951 keeps the text of the bank. A user whom the bank allows only the one-step method 999 (code 3920) has no TAN method for the FinTS server. When the bank then refuses the one-step method for the login, with 9075 "Starke Kundenauthentifizierung notwendig" or 9955 "Ein-Schritt-TAN-Verfahren nicht zugelassen", the helper marks the failure `noTANMethod` with the code and the text of the bank, and the account shows them with the website of the bank and "Edit Login Data...". Any other error, such as 9010 "Verarbeitungssystem nicht verfügbar", a wrong PIN, or a block, keeps its own failure, also while only 999 is allowed, and so does a 9955 of a user with another method. A blocked access and a missing TAN method wait for the user, and no dialog resolves them, so a command after a failed automatic refresh does not run the refresh again with dialogs.

### Credit cards

A credit card of FinTS type 50 to 59 gets the balance and the transactions like any other account, when it allows a transaction list. DKB and other banks offer their cards only through the card statement DKKKU. The helper sends only DKKKU for an account that allows it and neither HKKAZ nor HKCAZ, also when the account allows HKSAL, with the account number as the card number and the start day of the refresh. Its answer DIKKU carries the transactions and the balance of the card, so the helper sends no HKSAL beside it.

hbci4java 4.1.17 reads DIKKU in `GVKreditkartenUmsatz`, but it drops the field `finalized` of each row, and it reads the original amount of a converted row into a `Value` of two decimals. An original amount with three decimals, such as 1,234 Kuwaiti dinar, throws there, and hbci4java then fails the whole dialog, so the other accounts of the login get nothing either. The helper therefore sends DKKKU as `CardJob`, a `GVKreditkartenUmsatz` that reads no rows, and `cardRows` reads them from the raw data of the job, part by part in the order of the answer. Each amount keeps every decimal place and takes the sign of C or D. The merchant text of a row, its `purpose`, is also the name of the row, because the card statement has no other field for the other party, and a pending row pairs with its booked version only when both have a name or an IBAN. A row with `finalized` N is not final, such as the reservation of a hotel, so it goes to the app as pending. The original amount stays out until the app stores it (task 1.18). A row that does not read fails the card with "The bank sent a card transaction that does not read, so nothing of this card was stored.", and the other accounts of the login keep their results. The balance is the one of the first part of the answer that has one, with the sign of C or D, so a negative balance is the amount that the user owes on the card.

The rows of the card statement carry a `reference`. The helper does not use it as the source ID of a row yet: no answer of a real bank shows whether it is unique and whether it stays the same when a pending row becomes final, and a reference that repeats would merge different rows into one. A row fetched again matches by day, amount, and purpose, and a pending row matches its booked version by amount, name, and days at most seven apart, until the bank test of DKB records that. The helper writes the counts of the values of `finalized` and of the distinct references as a diagnostic for that test.

### The history of an account

A first and an enforced refresh ask for the full history, and any other refresh for no more than 90 days, so that the bank needs no TAN for older transactions. Before hbci4java sends the orders, every challenge is for the login, also the one of the dialog start in `execute`. hbci4java reports the end of the login with `DialogEvent.JOBS_CREATED`, and every challenge after it is for the download. When the refresh asks for the full history of an account, such a challenge may be for transactions older than 90 days, so the helper marks it with `history`, and the request carries `SecondFactorRequest.olderTransactions`.

"Cancel" in that dialog does not cancel the refresh. `SessionBroker` ends only the request with `OlderTransactionsSkipped`, the connector answers the helper with `skip`, and the helper ends the dialog as after a change of the TAN method and starts a new one that asks for the last 90 days of those accounts. FinTS has no way to drop one order from a dialog whose challenge waits, so the new dialog may need the login again. A challenge in the new dialog is not marked, so a second "Cancel" stops the refresh. The account then shows no error.

hbci4java checks a decoupled approval again and again with `NEED_PT_DECOUPLED_RETRY`, and the helper reads a `skip` there. The bank may answer before that check: the user rejects the request in the banking app and clicks "Cancel" in Moneten before the next check, or hbci4java withdraws the approval while the `skip` is on its way. So the helper keeps the ID of the last approval in `Callback.lastApproval` and takes a waiting `skip` for it each time it withdraws an approval, after the orders ran and before any result counts, and when hbci4java throws on the refusal of the bank. The dialog then ends for one of 90 days. A refusal without a `skip` fails the account as before. `FinTSHelper.Orders` is the bank side of a dialog, so the self-test runs `refresh` and `dialog` against a made-up bank.

A result that starts after the last successful fetch of the account (`AccountRequest.lastFetched`) sets `RefreshResult.missesOlder`. The first day that the request asked for is no measure, because it reaches 14 days or a pending row back: an account last fetched 80 days ago asks from 94 days ago and gets 90 days, and nothing is missing. The mark stays until a refresh brings the full history, and the account view says "Older transactions may be missing." until then. While the mark lasts, the initial balance of the account follows the bank balance (add-charts, "The initial balance follows the bank balance while older transactions may be missing").

The mark is a field of the account, `Account.missesOlderTransactions`, and not part of the state of the access. The connector reports for each account only whether its answer may miss older transactions, in `RefreshResult.missesOlder`. `reconcile` turns that into the mark with `RefreshResult.missesOlder(after:)`: a full history clears it, an answer without transactions keeps it, and any other answer sets it when it misses older transactions and keeps it otherwise. `Store.merge` writes the mark in the same transaction as the rows, the balance, and the initial balance of the refresh, so a failed write changes none of them, and a full history that never reached the database does not end the mark. A lock, a restart, "Look for New Accounts...", and "Edit Login Data..." keep it, because they keep the account, and the complete export writes it with the account (docs/export-format.md). An earlier version of this change kept the mark in the state of the FinTS access. The complete export leaves out access states, so an export and an import dropped the mark, and the next normal refresh set the initial balance before the full history came, 500,00 € too high in the scenario of the spec. The state and the rows were also written in two transactions. The decision of the project lead in round 3 of #264 moved the mark to the account. Migration `v21` adds the column and moves a mark that a debug build stored in the state of a FinTS access once, and the state keeps the passport alone.

### Trust in the server of the bank

The helper installs a trust manager that sends the certificate chain and the host to the app. The app evaluates the chain with `SecTrustEvaluateWithError` and the SSL policy for the host, on a queue of its own: the check can wait for the network, and a thread of Swift concurrency that waits holds up the timers and the other refreshes. Only the answer "trusted" lets the connection go on. The root certificates of the Java runtime play no part, and nothing turns the check off.

### Timeouts and cancel

A watchdog fails a run when the helper sends nothing for 30 seconds while no request waits for the user. The helper sends a line when it sends a message to the bank and when the answer arrives. A line counts when it arrives, and the watchdog does not run out while the app has not handled it, so an app that is busy never times out a helper that sends. It stops when the output of the helper ends. The watchdog runs before the first write of the command, so a helper that does not read its input also times out. A helper that closes its output but keeps running gets the cancel and the grace too.

A cancel or a failure sends the cancel line, terminates the helper after 5 seconds, and kills it 2 seconds later. The end of the helper closes every open request. When the run ends, the watchdog drops its reference to the helper, so the process, its pipes, and the answers of the user are released.

### The state of an access

The helper sends the passport of hbci4java as the new state after a successful run: bank parameters, user parameters, system ID, the TAN method, and the TAN medium. It holds no PIN. A failed run sends no state, so the next run starts from the last good one and may register again.

### Notices of the bank

`FinTSConnector` puts the institute messages of the bank, and the error of a balance request that failed beside transactions that worked, into `ConnectorReport.notices`. Such an error keeps its code and the name of its account. When the helper fails the run after it sent notices, the connector throws `FailureWithNotices`, so the notice of a maintenance survives the failed login that the maintenance causes. `listAccounts` does the same, also when the helper ends without the accounts, and the assistant "Add Account" shows the notices next to the error of its login step. `SyncCoordinator.noticed` hands the notices to the app when a refresh ends, also when every account was fetched and also when the access failed. The error of the accounts lists them too. A canceled refresh brings none, also when the cancel comes while the app stores an account.

`BankNotices` in `Domain` holds the notices for the window "Notice" and keeps every notice that waited, by bank, account, code, and text, so a bank that repeats the notice in each dialog shows it once ("Show notices of the bank"). The notices that the assistant "Add Account" showed after its login count as shown, also the notices under the error of a failed login and the notices of a login without accounts (`BankNotices.setupFailed` and `BankNotices.markShown`). A canceled login shows none, so the next refresh shows them. `BankNotices` lives in memory only: the lock and the quit forget it, and the next refresh after them shows a notice that the bank still sends once more. That is the one exception to "Each notice is shown once", and it saves a table and a schema migration.

An automatic refresh opens no dialog ("An automatic refresh never asks the user" in add-account-refresh), and the window "Notice" counts as one. So a new notice waits, and the window comes forward only when the user is there: when the main window comes forward, which is the next change of focus, or at the end of the next refresh that the user starts. Each new notice brings the window forward once. A notice that only repeats one that waits does not bring it forward again. The window lists all waiting notices and scrolls when they are taller than 400 points, and OK or the close button dismisses them.

### Rules of the savings banks and 1822direkt

The helper decides these rules by the FinTS host of the dialog, which comes from the bank directory, in `Tools/FinTSHelper/SavingsBanks.java`. Each bank group keeps its rules in a file of its own, so that the rules of another group change no line of it. A savings bank is a host whose label before ".de" starts with "s-fints-pt-" or is "s-hbci", the servers of Finanz Informatik. 1822direkt is the host "1822direkt.com" or a host that ends with ".1822direkt.com".

A Sparkasse lets the user block a software under "Service > Persönliche Einstellungen > Kontozugriffe" in its online banking, and then answers the login with "Kundenprodukt wurde vom Benutzer deaktiviert". The code of that answer is not known yet, so the text decides: an error of a savings bank host that says that the product was deactivated or blocked by the user ("vom Benutzer", "vom Kunden", "vom Nutzer" before "deaktiviert" or "gesperrt") comes first among the errors of the answer, before the urgent codes, and the helper marks it `appBlocked`. The connector maps it to `SyncFailure.appBlocked`, which tells the user where to unblock Moneten. It acts like a blocked access: the PIN leaves the memory and the database, no PIN sheet opens, and the automatic refresh waits for a refresh by hand. The same text from another host keeps the failure of its code.

The FinTS server of 1822direkt may send an MT940 statement in which a ":61:" or ":62F:" tag follows other text on the same line, and hbci4java finds a tag only at the start of a line, so the booking would vanish into the purpose of the booking before it. For such a host the helper sends the transactions as `SavingsBanks.StatementJob`, a `GVKUmsAll` that inserts a line break before each such tag of the booked part before hbci4java reads it. It inserts the break and replaces no character, so the purpose before the tag keeps its last character. hbci4java gives a job answer no dialog event, so the job is the only place where the helper sees the statement before it is read. When the server offers CAMT, the helper asks for CAMT and the rule does not apply.

### Signing

`scripts/build-app.sh` builds a runtime with jlink, puts the helper into `Contents/Resources/FinTSHelper`, and signs every Mach-O file of it with the identity of the app. Only the java of the helper gets the JIT entitlement. The build fails when a file cannot be signed or is not signed like the app. A Developer ID build signs it with the Developer ID certificate in the Keychain ([ADR 0016](../../../docs/decisions/0016-developer-id-certificate-in-ci.md)).

## Risks / Trade-offs

- [The helper is signed with `codesign` after the export] → This needs the private key of the Developer ID in the Keychain, which a certificate that only Xcode manages does not provide. [ADR 0016](../../../docs/decisions/0016-developer-id-certificate-in-ci.md) signs releases with a certificate whose private key the release workflow imports, so a Developer ID build includes the helper.
- [hbci4java reads only the date form of CAMT booking dates] → See task 2.4.
- [The app grows by about 46 MB for the Java runtime] → Accepted in ADR 0014.

## Open Questions

None.
