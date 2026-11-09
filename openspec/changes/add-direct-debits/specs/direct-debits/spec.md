# Spec Delta

## Purpose

A creditor collects money from the account of a debtor with a SEPA direct debit, based on a mandate that the debtor signed. This capability defines the creditor ID, mandates, single direct debits, direct debit batches, and the direct debits that wait at the bank for their due date.

## ADDED Requirements

### Requirement: Direct debits are available to every user

The app SHALL offer all direct debit functions without a purchase or an activation in the app.

#### Scenario: Fresh installation

- **GIVEN** a new installation with one giro account
- **WHEN** the user opens the Payment menu
- **THEN** "New Direct Debit Mandate..." and "New Direct Debit..." are available

### Requirement: Creditor ID

The app SHALL let the user enter a creditor ID in the settings of an account. The app checks the length, the country code, and the check digits of the ID and rejects an invalid one. The settings explain that the creditor ID is required to collect payments by direct debit and that the Deutsche Bundesbank issues it.

#### Scenario: Valid creditor ID

- **WHEN** the user enters the creditor ID DE98ZZZ09999999999 in the settings of "Business"
- **THEN** the app saves the ID

#### Scenario: Typing error

- **WHEN** the user enters the creditor ID DE98ZZZ0999999999
- **THEN** the app shows that the creditor ID is invalid and asks the user to check for typing errors

### Requirement: A direct debit needs a creditor ID

The app SHALL refuse to create a direct debit from an account without a creditor ID. The message names the account by its IBAN and points to the account settings.

#### Scenario: Creditor ID missing

- **GIVEN** the account "Business" has no creditor ID
- **WHEN** the user chooses "New Direct Debit..." for "Business"
- **THEN** the app says that the account with this IBAN is missing a creditor ID and that the ID is entered in the account settings

### Requirement: The bank must have set up the account for direct debits

The app SHALL read from the bank's parameter data whether the account is set up for direct debits. When it is not, the app says so, explains that the user needs a direct debit collection agreement with the bank, and advises the user to ask the bank to activate direct debits for the user ID.

#### Scenario: Account not set up

- **GIVEN** the bank reports no direct debit function for the account "Giro"
- **WHEN** the user chooses "New Direct Debit..." for "Giro"
- **THEN** the app explains that the account with this IBAN is not set up for direct debits and that the bank must activate them

#### Scenario: No account at all

- **GIVEN** none of the accounts is set up for direct debits
- **WHEN** the user chooses "New Direct Debit..."
- **THEN** the app says that none of the accounts is set up for direct debits and opens no window

### Requirement: Direct debits need a euro account

The app SHALL refuse a direct debit for an account whose currency is not the euro and name the currency in the message.

#### Scenario: Dollar account

- **GIVEN** the account "USD-Konto" has the currency USD
- **WHEN** the user selects it for a direct debit
- **THEN** the app explains that SEPA direct debits only work with euro accounts

### Requirement: The list "Direct Debit Mandates"

The app SHALL show an entry "Direct Debit Mandates" under "Payments" in the sidebar. The list shows each mandate with the debtor, the IBAN, the mandate reference, the mandate date, the kind, the amount, and the date of its last use. The status line shows the number of mandates.

#### Scenario: List of mandates

- **GIVEN** 40 mandates
- **WHEN** the user selects "Direct Debit Mandates"
- **THEN** the list shows 40 rows and the status line shows "40 Direct Debit Mandates"

#### Scenario: No mandates

- **GIVEN** no mandate exists
- **WHEN** the user selects "Direct Debit Mandates"
- **THEN** the view says that there are no direct debit mandates

### Requirement: Create a mandate

The app SHALL open a mandate window through "New Direct Debit Mandate..." in the Payment menu and "Add Direct Debit Mandate..." in the context menu. A mandate holds the debtor name, the IBAN, the BIC, the mandate reference, the mandate date, the kind, the sequence, an optional amount, and a purpose.

#### Scenario: Membership fee

- **WHEN** the user creates a mandate for "Max Mustermann" with the IBAN DE02120300000000202051, the mandate reference "M-2026-001", the mandate date 15 January 2026, the kind core, the amount 25,00 €, and the purpose "Beitrag @MMMM YYYY@"
- **THEN** the mandate appears in the list

### Requirement: Kinds of direct debit

The app SHALL offer the kinds core direct debit and B2B direct debit for a mandate. An express direct debit from an older file or mandate is treated as a core direct debit, and the app says that the core direct debit replaced it.

#### Scenario: B2B mandate

- **WHEN** the user creates a mandate with the kind B2B
- **THEN** direct debits from this mandate are sent as B2B direct debits

#### Scenario: Old express mandate

- **GIVEN** an imported mandate of the kind express direct debit
- **WHEN** the user uses the mandate
- **THEN** the app explains that the core direct debit replaced the express direct debit and creates a core direct debit

### Requirement: Sequence of a direct debit

The app SHALL offer the sequences "first/recurring direct debit", "final direct debit", and "one-off direct debit". The default is first/recurring. The app warns when the user uses a mandate again after a final or a one-off direct debit.

#### Scenario: Default sequence

- **WHEN** the user creates a mandate and does not change the sequence
- **THEN** direct debits from the mandate are sent as first/recurring direct debits

#### Scenario: Mandate used after the final direct debit

- **GIVEN** the last direct debit of a mandate was sent as a final direct debit
- **WHEN** the user uses the mandate again
- **THEN** the app warns that the mandate ended with a final direct debit and asks whether to continue

### Requirement: Mandate reference

The app SHALL require a mandate reference of at most 35 characters. The reference must not start with a slash, end with a slash, or contain two slashes in a row. When the bank does not support spaces in the mandate reference, the app rejects a reference with a space before sending.

#### Scenario: Missing reference

- **WHEN** the user saves a mandate without a mandate reference
- **THEN** the app asks the user to specify a mandate reference

#### Scenario: Two slashes

- **WHEN** the user enters the mandate reference "M//001"
- **THEN** the app shows that the mandate reference must not contain two consecutive slashes

#### Scenario: Space and a bank that does not support it

- **GIVEN** the bank does not support spaces in the mandate reference
- **WHEN** the user sends a direct debit with the mandate reference "M 001"
- **THEN** the app says that the bank does not support spaces in the mandate reference

### Requirement: Mandate date

The app SHALL require the date on which the debtor signed the mandate, and reject a date in the future.

#### Scenario: Date in the future

- **GIVEN** today is 3 November 2026
- **WHEN** the user enters the mandate date 1 December 2026
- **THEN** the app shows that the mandate date is invalid because it is in the future

### Requirement: Debtor address outside the European Economic Area

The app SHALL require the complete postal address of the debtor when the IBAN of the debtor comes from a SEPA country outside the European Economic Area. The address is entered through "Set address" in the gear menu.

#### Scenario: Debtor in Switzerland

- **WHEN** the user creates a direct debit for a debtor with the IBAN CH9300762011623852957 and no address
- **THEN** the app says that for direct debits from countries outside the European Economic Area the debtor address must be specified and points to the gear menu

### Requirement: The debtor bank must accept the direct debit

The app SHALL check with its bank directory whether the bank of the debtor accepts SEPA direct debits and, for a B2B direct debit, B2B direct debits. When it does not, the app says so. For a bank without B2B it suggests a core direct debit.

#### Scenario: Bank without B2B

- **GIVEN** the directory says that the BIC of the debtor cannot be used for B2B direct debits
- **WHEN** the user creates a B2B direct debit for this debtor
- **THEN** the app says that this BIC cannot be used for B2B direct debits and suggests a core direct debit

### Requirement: Change and delete mandates

The app SHALL open a mandate through "Change Direct Debit Mandate..." and save the changed values. The app deletes the selected mandates through "Delete Direct Debit Mandates..." after a confirmation that states their number and that deleted mandates cannot be restored.

#### Scenario: New IBAN of a member

- **WHEN** the user changes the IBAN of the mandate "M-2026-001" and saves
- **THEN** the list shows the new IBAN and the mandate reference stays "M-2026-001"

#### Scenario: Delete two mandates

- **WHEN** the user selects 2 mandates, chooses "Delete Direct Debit Mandates...", and confirms
- **THEN** both mandates are removed

### Requirement: Mandates in template groups

The app SHALL let the user keep mandates in template groups. The user drags a mandate onto a group in the sidebar to move it. Removing a group removes its mandates after a warning that says so.

#### Scenario: Group for monthly fees

- **GIVEN** the template group "Beiträge"
- **WHEN** the user drags 40 mandates onto "Beiträge"
- **THEN** selecting "Beiträge" lists the 40 mandates

### Requirement: Create a single direct debit

The app SHALL open the payment window for a direct debit through "New Direct Debit..." and through "Use Direct Debit Mandate..." in the context menu of a mandate. The window shows the creditor account, the debtor, the IBAN, the mandate reference, the mandate date, the kind, the sequence, the amount, the purpose, and the due date. Placeholders in the purpose are replaced.

#### Scenario: Use a mandate

- **GIVEN** the mandate "M-2026-001" for "Max Mustermann" with 25,00 € and the purpose "Beitrag @MMMM YYYY@", on 3 November 2026
- **WHEN** the user chooses "Use Direct Debit Mandate..."
- **THEN** the window shows a core direct debit of 25,00 € from "Max Mustermann" with the purpose "Beitrag November 2026"

#### Scenario: No mandate selected

- **GIVEN** no mandate is selected
- **WHEN** the user chooses the command to use a mandate
- **THEN** the app asks the user to select a direct debit mandate first and names the entry "Direct Debit Mandates" in the sidebar

### Requirement: Due date follows the lead time of the bank

The app SHALL set the due date of a new direct debit to the next possible date. The app computes that date from the minimum lead time in business days and the cut-off time that the bank reports for the kind and the sequence. For an earlier date the app names the lead time, the cut-off time, and the next possible date.

#### Scenario: Before the cut-off time

- **GIVEN** the bank requires one business day with a cut-off time of 12:00, and it is Tuesday 3 November 2026 at 10:00
- **WHEN** the user opens a new core direct debit
- **THEN** the due date is Wednesday 4 November 2026

#### Scenario: After the cut-off time before a weekend

- **GIVEN** the same bank, and it is Friday 6 November 2026 at 14:00
- **WHEN** the user picks Monday 9 November 2026 as the due date
- **THEN** the app says that the next possible scheduled date is Tuesday 10 November 2026

### Requirement: Latest possible due date

The app SHALL reject a due date that lies beyond the maximum lead time of the bank and name the latest possible date.

#### Scenario: Too far ahead

- **GIVEN** the bank allows a lead time of at most 14 days for this direct debit and today is 3 November 2026
- **WHEN** the user picks 30 November 2026
- **THEN** the app says that the latest possible scheduled date is 17 November 2026

### Requirement: Say what the bank does not support

The app SHALL check before each direct debit whether the bank supports the kind, as a single order or as a batch, for the creditor account. When the bank does not, the app names what is missing. The cases are core direct debits, B2B direct debits, core batches, B2B batches, and batches in general.

#### Scenario: Bank without B2B direct debits

- **GIVEN** the bank does not support B2B direct debits for the account "Business"
- **WHEN** the user creates a B2B direct debit from "Business"
- **THEN** the app explains that the bank does not support B2B direct debits for the selected account

### Requirement: Review, confirm, and send a direct debit

The app SHALL show a review of a direct debit with all its data and a note that the payee check does not apply to direct debits. The user confirms with a TAN. The result says whether the bank accepted the direct debit. The app then stores today's date as the date of the last use in the mandate.

#### Scenario: Accepted

- **WHEN** the user confirms a direct debit of 25,00 € from "Max Mustermann" with a TAN and the bank accepts it
- **THEN** the app shows that the direct debit has been successfully transmitted to the bank
- **AND** the mandate "M-2026-001" shows "last used on" with today's date

#### Scenario: Rejected

- **WHEN** the bank rejects the direct debit
- **THEN** the app shows the message of the bank and the date of the last use stays unchanged

### Requirement: Warn about a likely duplicate direct debit

The app SHALL ask for confirmation when the user collected the same amount from the same account recently, and when the user recently used the same IBAN with a different debtor name.

#### Scenario: Same collection twice

- **GIVEN** the user collected 25,00 € from DE02120300000000202051 yesterday
- **WHEN** the user creates another direct debit of 25,00 € from the same IBAN
- **THEN** the app asks whether this is a duplicate direct debit

### Requirement: Direct debits in the outbox

The app SHALL save a direct debit as a draft when "Save in outbox" is on in its window. Drafts of direct debits are listed in the outbox next to transfers and are sent alone with "Send Direct Debit...".

#### Scenario: Prepare a direct debit

- **GIVEN** "Save in outbox" is on
- **WHEN** the user finishes a direct debit of 120,00 € from "Erika Mustermann"
- **THEN** the direct debit appears under "Drafts" and nothing is sent to the bank

#### Scenario: Import a direct debit file into the outbox

- **GIVEN** a SEPA direct debit file with 5 positions for the account "Business"
- **WHEN** the user chooses "Import Outbox..." and the file
- **THEN** "Drafts" shows 5 new direct debits and the app reports "Imported 5 draft direct debits."

### Requirement: Use several mandates

The app SHALL let the user use several selected mandates at once through "Use Direct Debit Mandates...". The app offers to send them as single direct debits one after the other or as one direct debit batch.

#### Scenario: Three mandates as a batch

- **WHEN** the user selects 3 mandates, chooses "Use Direct Debit Mandates...", and chooses the batch
- **THEN** the batch window opens with 3 positions

### Requirement: Direct debit batch from a template group

The app SHALL create a direct debit batch from the mandates of a template group through "New Batch Direct Debit from Template Group...". The batch contains the selected mandates, or all mandates of the group when none is selected. Placeholders are replaced. A mandate without an amount is reported with its debtor.

#### Scenario: Monthly fees

- **GIVEN** the group "Beiträge" with 40 mandates of 25,00 € each and the purpose "Beitrag @MMMM YYYY@", on 3 November 2026
- **WHEN** the user selects the group and chooses "New Batch Direct Debit from Template Group..."
- **THEN** the batch window shows 40 positions, the total 1.000,00 €, and the purpose "Beitrag November 2026"

#### Scenario: Only some mandates

- **WHEN** the user selects 5 mandates of the group with the Command key and creates the batch
- **THEN** the batch window shows 5 positions

### Requirement: Direct debit batch from the outbox

The app SHALL create a direct debit batch from the direct debit drafts through "New Batch Direct Debit from Outbox...", with one batch for each creditor account.

#### Scenario: Drafts of one account

- **GIVEN** 6 direct debit drafts for the account "Business"
- **WHEN** the user chooses "New Batch Direct Debit from Outbox..."
- **THEN** the batch window shows 6 positions

#### Scenario: No drafts

- **GIVEN** no direct debit draft exists
- **WHEN** the user chooses the command
- **THEN** the app says that there are no draft direct debits

### Requirement: Direct debit batch from a SEPA XML file

The app SHALL create a direct debit batch from a SEPA direct debit file through "New Batch Direct Debit from SEPA XML File..." and from a file that is opened with the app. The app finds the creditor account by the creditor IBAN in the file. The creditor ID in the file must equal the creditor ID of that account.

#### Scenario: File from the accounting system

- **GIVEN** a `pain.008` file with 30 positions, the creditor IBAN of "Business", and the creditor ID DE98ZZZ09999999999, which is also in the settings of "Business"
- **WHEN** the user opens the file
- **THEN** the batch window opens for "Business" with 30 positions

#### Scenario: Different creditor ID

- **GIVEN** the file holds another creditor ID than the settings of the account
- **WHEN** the user opens the file
- **THEN** the app shows both IDs and asks the user to change the file or the creditor ID in the account settings

#### Scenario: Not a SEPA XML file

- **WHEN** the user chooses a CSV file
- **THEN** the app says that this is not a SEPA XML file and suggests "Import Direct Debit Mandates..." followed by a batch from the template group

### Requirement: Check every position of a direct debit batch

The app SHALL check every position before a direct debit batch can be sent, and name the number of the position, the debtor, and the reason for a failed check. Besides the checks of a transfer position, the reasons are a missing debtor name, a missing or invalid mandate reference, a missing mandate date, a mandate date in the future, a missing debtor address for a country outside the European Economic Area, and a BIC that cannot be used for the kind of direct debit.

#### Scenario: Position without a mandate date

- **GIVEN** position 12 for "Erika Mustermann" has no mandate date
- **WHEN** the user clicks "Next" in the batch window
- **THEN** the app says that the 12th position (Erika Mustermann) has no mandate date

### Requirement: Ignore an invalid BIC inside the European Union

The app SHALL send a position of a direct debit batch without its BIC when the BIC is invalid and the IBAN comes from a country of the European Union.

#### Scenario: Wrong BIC in a file

- **GIVEN** position 3 has a valid German IBAN and the BIC "XXXXDEXX"
- **WHEN** the user sends the batch
- **THEN** the app sends position 3 with the IBAN and without a BIC

### Requirement: Warn about duplicates inside a direct debit batch

The app SHALL ask for confirmation when a direct debit batch contains the same amount from the same IBAN more than once, and when it contains the same IBAN with different debtor names.

#### Scenario: Same debtor twice

- **GIVEN** a batch with two positions of 25,00 € from DE02120300000000202051
- **WHEN** the user clicks "Next"
- **THEN** the app says that the batch contains the same amount from the same account multiple times and asks whether to continue

### Requirement: Split a direct debit batch

The app SHALL send a direct debit batch with one kind, one sequence, and one due date, and with at most the number of positions that the bank accepts. For a batch that mixes these or is too large, the app names the batches that would result and offers to split it. A bank that accepts several sequences in one batch gets them in one batch.

#### Scenario: Core and B2B mixed

- **GIVEN** a group with 30 core mandates and 5 B2B mandates
- **WHEN** the user creates a batch from the group
- **THEN** the app asks whether to split the batch into a core batch with 30 positions and a B2B batch with 5 positions

#### Scenario: Two due dates

- **GIVEN** drafts with the due dates 10 November 2026 and 20 November 2026
- **WHEN** the user creates a batch from them
- **THEN** the app asks whether to split the batch into 2 direct debit batches with different scheduled dates

#### Scenario: Bank accepts mixed sequences

- **GIVEN** the bank accepts several sequences in one batch
- **WHEN** the user creates a batch with first/recurring and final direct debits
- **THEN** the app offers no split by sequence

### Requirement: Send a direct debit batch

The app SHALL show the batch window of the outbox for a direct debit batch, with the due date, the designation, and the single booking option, and it SHALL send the batch as one order with one TAN. Positions that the bank rejects appear in a status report and stay as drafts.

#### Scenario: Forty fees with one TAN

- **WHEN** the user confirms a batch of 40 positions with a total of 1.000,00 € and enters one TAN
- **THEN** the app shows that the direct debit batch has been successfully transmitted to the bank
- **AND** each of the 40 mandates shows today's date as the date of its last use

#### Scenario: Bank books only single transactions

- **GIVEN** the bank can book a direct debit batch as single transactions only
- **WHEN** the batch window opens
- **THEN** the app says so and the single booking option is on and cannot be turned off

### Requirement: Submitted direct debits in the view "Scheduled"

The app SHALL list direct debits and direct debit batches that the bank has not yet executed in the view "Scheduled", with their due date and amount. The filter "Kind" gets an entry for direct debits. "Refresh Scheduled Payments" fetches them from the bank.

#### Scenario: Waiting direct debit

- **GIVEN** the user submitted a direct debit that is due on 10 November 2026
- **WHEN** the user opens "Scheduled" on 4 November 2026
- **THEN** the list shows the direct debit with its due date

### Requirement: Change and delete submitted direct debits

The app SHALL offer "Change Direct Debit..." and "Delete Direct Debit..." for a submitted direct debit where the bank supports it for the kind and the account. Where the bank does not, the app says so. A direct debit batch cannot be changed, and the app suggests deleting it and creating a new one.

#### Scenario: Delete before the due date

- **GIVEN** the bank supports deleting core direct debits
- **WHEN** the user chooses "Delete Direct Debit..." for a waiting direct debit and confirms
- **THEN** the app shows that the direct debit has been deleted and removes it from the list

#### Scenario: Bank cannot change B2B direct debits

- **GIVEN** the bank does not support changing B2B direct debits for the account
- **WHEN** the user chooses "Change Direct Debit..."
- **THEN** the app explains that the bank does not support changing B2B direct debits for this account

#### Scenario: Change a batch

- **WHEN** the user chooses the change command for a submitted direct debit batch
- **THEN** the app explains that direct debit batches cannot be changed through FinTS and suggests deleting the batch and creating a new one

### Requirement: Import mandates

The app SHALL import mandates from CSV files and SEPA XML files through "Import Direct Debit Mandates...". In a CSV file the app finds the columns by their header keywords. The file must contain the mandate reference and the mandate date. The app reports the number of imported mandates and rejects other formats with a message that names CSV and SEPA XML.

#### Scenario: Member list

- **GIVEN** a CSV file with the columns "Name", "IBAN", "Mandatsreferenz", "Mandatsdatum", and "Betrag" and 40 rows
- **WHEN** the user imports the file into the group "Beiträge"
- **THEN** the group holds 40 mandates and the app reports "Imported 40 direct debit mandates."

#### Scenario: File without mandate dates

- **GIVEN** a CSV file without a column for the mandate date
- **WHEN** the user imports the file
- **THEN** the app says that the mandate reference and the mandate date must be included in the CSV file and imports nothing

### Requirement: Export mandates

The app SHALL export the selected mandates, or all mandates of the selected group when none is selected, through "Export Direct Debit Mandates..." as a CSV file or as a SEPA XML file. A CSV file that the app exported can be imported again without loss.

#### Scenario: Export a group

- **GIVEN** the group "Beiträge" with 40 mandates
- **WHEN** the user exports the group as CSV
- **THEN** the file holds 40 rows with debtor, IBAN, BIC, mandate reference, mandate date, kind, amount, and purpose

### Requirement: Authorize SRZ orders for direct debits

The app SHALL list direct debit orders that a service data center submitted for the user's accounts in the view "Scheduled" and let the user authorize them with a TAN, in the same way as SRZ orders for transfers.

#### Scenario: Direct debit file from a service data center

- **GIVEN** a service data center submitted a direct debit order with a total of 8.400,00 €
- **WHEN** the user refreshes the scheduled payments and chooses "Authorize SRZ Order..." for it
- **THEN** the app sends the authorization after the TAN and shows that the SRZ order has been authorized
