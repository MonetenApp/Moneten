# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

- `TransactionFileImporter.parse` (module `Import`) returns a CAMT entry with the status PDNG or FUTR as pending, on the booking date of the entry, and leaves out an entry with the status INFO. A pending row from a file is booked by `reconcile` (module `Domain`) like one from a refresh, by the rule of `add-account-refresh`: a later file or refresh brings a booked row with the same amount and the same counterparty, at most seven days apart, and `Bookings` pairs it with the stored pending row. The counterparty is the IBAN when both rows have one, otherwise the name. The booking date stays the date of the entry, so the booked version lies within the seven days.
- The CAMT reader builds one transaction per `Ntry` with the amount of `Ntry/Amt`, as the first build does. It does not split a batch into its transaction details. The first build overwrites the name, the IBAN, the BIC, and the references for each `TxDtls`, so a batch takes the counterparty of its last payment. The reader instead collects the values of all details and keeps a counterparty field only when every detail gives the same name and IBAN. For such a batch it keeps a reference only when every detail gives the same value. A batch to several counterparties has no references. It already joins the `Ustrd` purposes of all details.
- The CAMT reader reads the return reason from `RtrInf/Rsn/Cd`. `Transaction` gets the field `returnReason` through a new migration in `Sources/Storage/Schema.swift`. `Transaction(arriving:in:fetched:)` and `takingBankFields(of:)` in `Sources/Domain/Reconcile.swift` copy it, so a stored or booked row keeps it.
- `reconcile` in `Sources/Domain/Reconcile.swift` keeps an unfetched pending file row through its booking date. A refresh can take it over only with an unpaired delivered pending row that `PendingMatch.fits`: the same amount and counterparty, at most seven days apart. For each delivered row, the free file row with the smallest distance in days wins. The same day wins first. Ties follow the order of `released`. The file row keeps its ID and user fields, takes the bank fields, and becomes fetched. Each delivered row pairs with at most one stored row. A delivered row with a live or deleted partner cannot take another file row. Unpaired future file rows stay, including after repeated refreshes. After their date, a refresh that covers them and does not deliver them drops them.
- A `.file` delivery first uses the existing source-ID and fingerprint matching. Each remaining pending file row then pairs with one free stored pending row on the same booking day when `PendingMatch.fits` it. The stored row can be fetched or imported. This skips the file row even when a bank takeover changed the stored purpose. New rows within the same file do not match each other. The stored row keeps its bank fields and fetched status. Its empty comment takes the file comment, its missing category takes the file category and assignment kind, and its checkmark stays set when either row is checked. Existing user fields win. `Storage` writes these updates in the same merge.
- `parse61` takes the booking year from the value year and corrects it by the six-month rule of the spec. It replaces the check for December and January only.

## Open gate decisions

Import matching remains on the same booking day only. A stored bank pending row of -800,00 € on 30 November 2026 and a file row of -800,00 € on 1 December 2026 stay as two rows, totaling -1.600,00 €. Widening the import match to seven days with the closest day first would merge them. The operator still decides whether to widen it.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.

- A batch entry stays one row, so a rule or a search does not see each payment of the batch on its own. Splitting it waits for the change that also matches the parts against a total, because split parts next to a refresh that brings the total would count the same payment twice.
- A pending batch entry to several counterparties has no name and no IBAN, so its booked version does not book it. After a later file, both rows stay until the user deletes the pending one. A refresh drops the pending row as it drops any pending row that it does not deliver.
- A FUTR row in an offline account stays pending until a booked version arrives or the user deletes it. An offline account has no refresh that drops it after its date.

- `Storage` stores each CSV profile as versioned JSON in the encrypted database. Independent records keep unreadable profiles unchanged when another is saved or deleted. `Import` decodes known column fields and defaults a missing category option to false. Legacy profiles without a delimiter require preview confirmation.
- `Domain` indexes category names and full paths once per file. `Storage` creates, assigns, merges and removes unused file categories in one database transaction, so a failed merge rolls back categories too.

- Cancellation shares a thread-safe flag between the import sheet and the storage transaction. Storage checks it during category writes and before commit. Complete exports carry versioned profile payloads, including unreadable entries, without decoding them.
