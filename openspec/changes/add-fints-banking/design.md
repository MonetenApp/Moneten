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

hbci4java clears the PIN only when the bank reports a wrong PIN, and calls `WRONG_PIN` right after that. The helper keeps the answer of the bank for the whole run and sends it with the next PIN request. The connector turns that into `PINRequest(rejected:)`, so the broker never answers it from memory: the PIN sheet opens again in a manual refresh, and an automatic refresh fails with `pinRejected`. 9930 is a blocked access, and the connector stops without asking again. 9931 counts as a wrong PIN, because Sparkassen send it for a wrong login name or PIN.

### Trust in the server of the bank

The helper installs a trust manager that sends the certificate chain and the host to the app. The app evaluates the chain with `SecTrustEvaluateWithError` and the SSL policy for the host, on a queue of its own: the check can wait for the network, and a thread of Swift concurrency that waits holds up the timers and the other refreshes. Only the answer "trusted" lets the connection go on. The root certificates of the Java runtime play no part, and nothing turns the check off.

### Timeouts and cancel

A watchdog fails a run when the helper sends nothing for 30 seconds while no request waits for the user. The helper sends a line when it sends a message to the bank and when the answer arrives. A line counts when it arrives, and the watchdog does not run out while the app has not handled it, so an app that is busy never times out a helper that sends. It stops when the output of the helper ends. The watchdog runs before the first write of the command, so a helper that does not read its input also times out. A helper that closes its output but keeps running gets the cancel and the grace too.

A cancel or a failure sends the cancel line, terminates the helper after 5 seconds, and kills it 2 seconds later. The end of the helper closes every open request. When the run ends, the watchdog drops its reference to the helper, so the process, its pipes, and the answers of the user are released.

### The state of an access

The helper sends the passport of hbci4java as the new state after a successful run: bank parameters, user parameters, system ID, the TAN method, and the TAN medium. It holds no PIN. A failed run sends no state, so the next run starts from the last good one and may register again.

### Notices of the bank

`FinTSConnector` puts the institute messages of the bank, and the error of a balance request that failed beside transactions that worked, into `ConnectorReport.notices`. Such an error keeps its code and the name of its account. When the helper fails the run after it sent notices, the connector throws `FailureWithNotices`, so the notice of a maintenance survives the failed login that the maintenance causes. `listAccounts` does the same, and the assistant "Add Account" shows the notices next to the error of its login step. `SyncCoordinator.noticed` hands the notices to the app when a refresh ends, also when every account was fetched and also when the access failed. The error of the accounts lists them too. A canceled refresh brings none, also when the cancel comes while the app stores an account.

`BankNotices` in `Domain` holds the notices for the window "Notice" and keeps every notice that waited, by bank, account, code, and text, so a bank that repeats the notice in each dialog shows it once ("Show notices of the bank"). The notices that the assistant "Add Account" showed after the login count as shown. `BankNotices` lives in memory only: the lock and the quit forget it, and the next refresh after them shows a notice that the bank still sends once more. That is the one exception to "Each notice is shown once", and it saves a table and a schema migration.

An automatic refresh opens no dialog ("An automatic refresh never asks the user" in add-account-refresh), and the window "Notice" counts as one. So a new notice waits, and the window comes forward only when the user is there: when the main window comes forward, which is the next change of focus, or at the end of the next refresh that the user starts. Each new notice brings the window forward once. A notice that only repeats one that waits does not bring it forward again. The window lists all waiting notices and scrolls when they are taller than 400 points, and OK or the close button dismisses them.

### Signing

`scripts/build-app.sh` builds a runtime with jlink, puts the helper into `Contents/Resources/FinTSHelper`, and signs every Mach-O file of it with the identity of the app. Only the java of the helper gets the JIT entitlement. The build fails when a file cannot be signed or is not signed like the app. A Developer ID build leaves the helper out until task 3.2, see the risks.

## Risks / Trade-offs

- [The helper is signed with `codesign` after the export] → This needs the private key of the Developer ID in the Keychain, which a certificate that only Xcode manages does not provide. Until task 3.2 lets the export sign the helper, a Developer ID build leaves it out, and the app cannot use FinTS in a release.
- [hbci4java reads only the date form of CAMT booking dates] → See task 2.4.
- [The app grows by about 46 MB for the Java runtime] → Accepted in ADR 0014.

## Open Questions

None.
