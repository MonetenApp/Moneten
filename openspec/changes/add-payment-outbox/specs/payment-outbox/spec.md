# Spec Delta

## Purpose

The outbox holds payments that are prepared and not yet sent, and it lists every order that was sent. This capability also defines batch transfers, which send many positions as one order with one TAN, from drafts, from a template group, or from a SEPA XML file.

## ADDED Requirements

### Requirement: The view "Outbox"

The app SHALL show a view "Outbox" under "Payments" in the sidebar with a switch between "Drafts" and "Sent" and a filter "Account". The toolbar button of the view reads "Batch transfer". The status line shows the number of listed payments and their sum.

#### Scenario: Drafts of one account

- **GIVEN** 3 drafts from "Giro" and 2 drafts from "Business"
- **WHEN** the user selects "Outbox", "Drafts", and the account "Giro"
- **THEN** the list shows the 3 drafts from "Giro"

#### Scenario: Empty outbox

- **GIVEN** no draft exists
- **WHEN** the user selects "Drafts"
- **THEN** the view says that no draft payments were found

### Requirement: Save a payment in the outbox

The app SHALL offer "Save in outbox" in the gear menu of the payment window. With the option on, the app checks the fields and saves the payment as a draft. It contacts no bank and asks for no TAN.

#### Scenario: Prepare a transfer

- **GIVEN** the option "Save in outbox" is on
- **WHEN** the user enters a transfer of 89,00 € to "Stadtwerke Musterstadt" and finishes the window
- **THEN** the transfer appears under "Drafts"
- **AND** nothing is sent to the bank

#### Scenario: Invalid draft

- **GIVEN** the option "Save in outbox" is on
- **WHEN** the user enters the IBAN DE02120300000000202052
- **THEN** the app shows the checksum error and saves no draft

### Requirement: Save new payments in the outbox by default

The app SHALL turn on "Save in outbox" in every new payment window when the setting "Save new payments in outbox by default" is on. The user can turn the option off for a single payment. The setting is off by default.

#### Scenario: Setting on

- **GIVEN** the setting is on
- **WHEN** the user opens a new payment window
- **THEN** "Save in outbox" is checked in the gear menu

### Requirement: Open and change a draft

The app SHALL open a draft with its values in the payment window through a double click and through "Change Transfer...". The user can change the values and save the draft again.

#### Scenario: Correct an amount

- **GIVEN** a draft of 89,00 € to "Stadtwerke Musterstadt"
- **WHEN** the user opens the draft, changes the amount to 98,00 €, and saves
- **THEN** the draft shows 98,00 €

### Requirement: Send one draft

The app SHALL send a single draft as a normal transfer through "Send Transfer..." and from the opened draft. The transfer follows the review, the payee check, and the confirmation of a transfer. After the bank accepted it, the draft moves from "Drafts" to "Sent".

#### Scenario: Send a draft alone

- **GIVEN** a draft of 89,00 € to "Stadtwerke Musterstadt"
- **WHEN** the user chooses "Send Transfer...", confirms the review, and enters the TAN
- **THEN** the transfer is listed under "Sent" and no longer under "Drafts"

#### Scenario: Bank rejects the draft

- **WHEN** the bank rejects the transfer
- **THEN** the draft stays under "Drafts"

### Requirement: Delete drafts

The app SHALL delete the selected drafts through "Delete Transfers..." after a confirmation that states the number of drafts and that deleted drafts cannot be restored.

#### Scenario: Delete two drafts

- **WHEN** the user selects 2 drafts, chooses "Delete Transfers...", and confirms
- **THEN** both drafts are removed and nothing was sent to the bank

### Requirement: The list of sent orders

The app SHALL list under "Sent" every order that it transmitted to a bank. A row shows the date and time of the transmission, the execution date, the kind of order, the recipient, the amount, the TAN method, and the state. A batch shows the number of positions and the total. The app never stores or shows the TAN.

#### Scenario: Scheduled transfer in the list

- **GIVEN** the user submitted on 3 November 2026 at 10:15 a transfer that is scheduled for 28 November 2026
- **WHEN** the user opens "Sent"
- **THEN** the row shows "submitted on 03.11.2026, 10:15" and "scheduled for 28.11.2026"

### Requirement: Change and delete orders appear under "Sent"

The app SHALL also list under "Sent" the orders that changed or deleted a scheduled transfer, a standing order, or another order at the bank.

#### Scenario: Deleted standing order

- **WHEN** the user deletes a standing order at the bank through the app
- **THEN** "Sent" shows a row for the delete order with its time

### Requirement: Remove rows from "Sent"

The app SHALL remove the selected rows from "Sent" through "Remove Transfers..." after a confirmation. The confirmation says that removed rows cannot be restored. Removing a row changes nothing at the bank.

#### Scenario: Clean up the list

- **WHEN** the user selects 5 rows under "Sent", chooses "Remove Transfers...", and confirms
- **THEN** the 5 rows leave the list
- **AND** the transfers stay executed at the bank

### Requirement: Batch transfer from the outbox

The app SHALL create a batch transfer from drafts through "New Batch Transfer from Outbox..." and through the toolbar button. The batch contains the selected drafts, or all drafts when none is selected.

#### Scenario: All drafts of one account

- **GIVEN** 4 drafts from "Giro" with a total of 1.250,00 €
- **WHEN** the user chooses "New Batch Transfer from Outbox..."
- **THEN** the batch window shows 4 positions and the total 1.250,00 €

#### Scenario: No drafts

- **GIVEN** no draft exists
- **WHEN** the user chooses "New Batch Transfer from Outbox..."
- **THEN** the app says that there are no draft transfers

### Requirement: Batch transfer from a template group

The app SHALL create a batch transfer from the templates of a template group through "New Batch Transfer from Template Group...". The batch contains the selected templates, or all templates of the group when none is selected. Placeholders in the purposes are replaced. A template without an amount is reported with its name.

#### Scenario: Monthly salaries

- **GIVEN** the group "Gehälter" with 12 templates and the purpose "Gehalt @MMMM YYYY@", on 25 November 2026
- **WHEN** the user selects the group and chooses "New Batch Transfer from Template Group..."
- **THEN** the batch window shows 12 positions with the purpose "Gehalt November 2026"

#### Scenario: No group selected

- **GIVEN** an account view is selected
- **WHEN** the user chooses "New Batch Transfer from Template Group..."
- **THEN** the app asks the user to select a template group in the sidebar first

### Requirement: Batch transfer from a SEPA XML file

The app SHALL create a batch transfer from a SEPA credit transfer file through "New Batch Transfer from SEPA XML File...". The app reads files with the extensions `.xml` and `.pain` and SEPA container files that hold several orders. The positions of the file become the positions of the batch.

#### Scenario: Payroll file

- **GIVEN** a `pain.001` file with 12 positions from the IBAN of the account "Business"
- **WHEN** the user chooses the file
- **THEN** the batch window opens for "Business" with 12 positions

#### Scenario: Container file

- **GIVEN** a container file that holds two credit transfer orders
- **WHEN** the user chooses the file
- **THEN** the app offers one batch for each order

### Requirement: Open SEPA XML files from Finder and the Dock

The app SHALL accept a SEPA XML file that the user opens with the app in Finder or drops on the Dock icon. The app unlocks first when it is locked, and then it opens the batch window as if the user had chosen the file in the menu.

#### Scenario: Drop on the Dock icon

- **WHEN** the user drops the file "gehaelter-2026-11.xml" on the Dock icon of the app
- **THEN** the batch window opens with the positions of the file

### Requirement: Match a file to the source account

The app SHALL find the source account of a file by the debtor IBAN in the file. When no account has that IBAN, or the account cannot send payments, the app names the IBAN and creates no batch.

#### Scenario: Unknown debtor IBAN

- **GIVEN** a file with the debtor IBAN DE89370400440532013000 and no account with that IBAN
- **WHEN** the user opens the file
- **THEN** the app says that there is no matching account for the debtor IBAN DE89370400440532013000

#### Scenario: Account cannot pay

- **GIVEN** the account with the debtor IBAN of the file has a read-only access
- **WHEN** the user opens the file
- **THEN** the app says that the account for this debtor IBAN is not set up for payments

### Requirement: Report problems in a SEPA XML file

The app SHALL reject a file that is not valid SEPA XML with a message that names the file and the error, and it SHALL advise the user to correct the file in the program that wrote it. For a file that is no SEPA XML at all, the app points to "Import Transfer Templates..." as the way to load a list of recipients. Warnings that do not prevent the batch are listed for the file.

#### Scenario: CSV file chosen

- **WHEN** the user chooses a CSV file in "New Batch Transfer from SEPA XML File..."
- **THEN** the app says that this is not a SEPA XML file and suggests "Import Transfer Templates..." followed by a batch transfer from the template group

#### Scenario: Broken XML

- **GIVEN** a file whose XML structure violates the SEPA schema
- **WHEN** the user opens the file
- **THEN** the app shows the error for this file and creates no batch

### Requirement: Correct bank details from a file

The app SHALL let the user correct the recipient name, the IBAN, and the BIC of a position in the batch window when the position from a file fails a check.

#### Scenario: Online shop file with a wrong IBAN

- **GIVEN** position 7 of a file has an IBAN with a wrong checksum
- **WHEN** the user opens position 7 in the batch window and enters the correct IBAN
- **THEN** the position passes the check and the batch can be sent

### Requirement: Send in a format that the bank accepts

The app SHALL convert the positions of a file to the newest SEPA format version that the bank of the source account supports before it sends the batch.

#### Scenario: Older file format

- **GIVEN** a file in the format `pain.001.001.03` and a bank that expects `pain.001.001.09`
- **WHEN** the user sends the batch
- **THEN** the bank receives the order in `pain.001.001.09` with the same positions

### Requirement: One batch for each source account

The app SHALL create one batch for each source account when the drafts or a file belong to several source accounts. The batch windows open one after the other.

#### Scenario: Drafts of two accounts

- **GIVEN** 3 drafts from "Giro" and 2 drafts from "Business"
- **WHEN** the user chooses "New Batch Transfer from Outbox..."
- **THEN** the app opens a batch window for "Giro" with 3 positions
- **AND** a batch window for "Business" with 2 positions follows

### Requirement: The batch window

The app SHALL show in the batch window the source account, the list of positions with recipient, IBAN, amount, and purpose, the number of positions, the total, the execution date under "Schedule", the TAN method under "Confirm using", and an optional "Designation". The bank shows the designation on the statement as the reference of the batch.

#### Scenario: Designation on the statement

- **WHEN** the user enters the designation "Gehälter 11/2026" and sends the batch
- **THEN** the bank receives "Gehälter 11/2026" as the reference of the batch

#### Scenario: Slash at the end

- **WHEN** the user enters the designation "Gehälter/"
- **THEN** the app shows that the designation must not end with a slash

### Requirement: Booking as single transactions

The app SHALL offer in the batch window an option that asks the bank to book each position as its own transaction. When the bank can book a batch only as single transactions, or only as one sum, the app says so and sets the option to match.

#### Scenario: Request single booking

- **GIVEN** the bank supports both kinds of booking
- **WHEN** the user turns on the single booking option and sends a batch of 4 positions
- **THEN** the order asks the bank to book 4 single transactions

#### Scenario: Bank books only the sum

- **GIVEN** the bank cannot book the positions of a batch as single transactions
- **WHEN** the user turns on the single booking option
- **THEN** the app explains that the bank is not able to book the positions as single transactions and turns the option off

### Requirement: Check every position

The app SHALL apply the field checks of a transfer to every position before a batch can be sent. A failed check names the number of the position, its recipient, and the reason. The reasons include a missing recipient name, a missing or invalid IBAN, an IBAN outside the SEPA area, an IBAN equal to the source account, an invalid or missing BIC, a missing or invalid amount, a currency other than the euro, unsupported characters, and an invalid end-to-end reference or purpose code.

#### Scenario: Position without an amount

- **GIVEN** position 3 for "Max Mustermann" has no amount
- **WHEN** the user clicks "Next" in the batch window
- **THEN** the app says that the 3rd position (Max Mustermann) has no amount
- **AND** the batch is not sent

#### Scenario: Position to the source account

- **GIVEN** position 5 has the IBAN of the source account
- **WHEN** the user clicks "Next"
- **THEN** the app says that the 5th position has an IBAN that is identical to the source account

### Requirement: Warn about duplicates inside a batch

The app SHALL ask for confirmation when a batch contains the same amount to the same IBAN more than once, and when it contains the same IBAN with different recipient names. The question names the amount, the IBAN, and the names.

#### Scenario: Same position twice

- **GIVEN** a batch with two positions of 100,00 € to DE02120300000000202051
- **WHEN** the user clicks "Next"
- **THEN** the app says that the batch contains the same amount to the same account multiple times and asks whether to continue

#### Scenario: Two names for one IBAN

- **GIVEN** a batch with DE02120300000000202051 once for "Max Mustermann" and once for "M. Mustermann GmbH"
- **WHEN** the user clicks "Next"
- **THEN** the app shows both names for the IBAN and asks whether to continue

### Requirement: One execution date for a batch

The app SHALL send a batch with one execution date for all positions. When the positions come with different dates, the app offers to split the batch into one batch for each date. When the user declines, the app sets all positions to the date in the batch window and says so.

#### Scenario: Split by date

- **GIVEN** 6 drafts, 4 scheduled for 15 November 2026 and 2 for 30 November 2026
- **WHEN** the user creates a batch from them
- **THEN** the app asks whether to split the batch into 2 batch transfers with different scheduled dates

#### Scenario: Decline the split

- **WHEN** the user declines the split
- **THEN** the batch window shows a note that the scheduled date of all positions has been set to today and that the date can be changed in the window

### Requirement: Respect the largest batch size of the bank

The app SHALL read the largest number of positions that the bank accepts in one batch. For a larger batch the app offers to split it into several batches with at most that number of positions each.

#### Scenario: 250 positions with a limit of 100

- **GIVEN** the bank accepts at most 100 positions in a batch
- **WHEN** the user creates a batch with 250 positions
- **THEN** the app asks whether to split the batch into several batch transfers with up to 100 positions each
- **AND** after the user agrees, the app creates 3 batches with 100, 100, and 50 positions

### Requirement: Batch transfers only where the bank supports them

The app SHALL read from the bank's parameter data whether the source account supports batch transfers, with a scheduled date and without one. When the bank supports none of them, the app says so. When the bank supports only one of the two, the app says which one.

#### Scenario: No batch transfers

- **GIVEN** the bank does not support batch transfers for the account "Giro"
- **WHEN** the user creates a batch from "Giro"
- **THEN** the app explains that the bank does not support batch transfers for the selected account

#### Scenario: Only with a scheduled date

- **GIVEN** the bank supports batch transfers only with a scheduled date
- **WHEN** the user chooses "Now" in the batch window
- **THEN** the app explains that the bank does not support batch transfers without a scheduled date

### Requirement: Scheduled batch transfers

The app SHALL accept an execution date for a batch under "Schedule" and check it against the lead times that the bank reports for scheduled batch transfers. The accepted batch appears in the view "Scheduled".

#### Scenario: Date beyond the lead time

- **GIVEN** the bank allows a lead time of at most 30 days for scheduled batch transfers and today is 3 November 2026
- **WHEN** the user picks 15 December 2026
- **THEN** the app says that the latest possible scheduled date is 3 December 2026

### Requirement: Instant batch transfers

The app SHALL send a batch as instant payments when the user chooses this in the batch window and the bank supports batch instant payments for the account. When all positions come from drafts for instant payments, the app sets the batch to instant payments and says so. When the bank does not support it, the app says so.

#### Scenario: Drafts are instant payments

- **GIVEN** 3 drafts that were saved as instant payments
- **WHEN** the user creates a batch from them
- **THEN** the batch window notes that all positions have been set to instant payments and that this can be changed in the window

#### Scenario: Bank without batch instant payments

- **GIVEN** the bank does not support batch instant payments
- **WHEN** the user chooses instant payments for a batch
- **THEN** the app explains that the bank does not support batch instant payments for the selected account

### Requirement: Only euro positions with an IBAN

The app SHALL accept in a batch only positions in euro that have an IBAN. For a selection with a foreign currency position or a position with an account number and a Bankleitzahl, the app asks the user to deselect those positions.

#### Scenario: Foreign currency draft

- **GIVEN** the selected drafts contain a transfer in USD
- **WHEN** the user chooses "New Batch Transfer from Outbox..."
- **THEN** the app asks the user to select only transfers without a foreign currency

### Requirement: Payee check for a batch

The app SHALL ask the bank for the payee check of all positions before the user confirms a batch. The review shows how many positions match, and it lists each position with a close match, no match, or no result together with the name that the bank suggests. The batch continues only after the user confirmed the listed positions.

#### Scenario: One position does not match

- **GIVEN** a batch of 12 positions where the bank reports 11 matches and no match for position 4
- **WHEN** the review appears
- **THEN** it shows "11 of 12" as matching and lists position 4 with the liability notice
- **AND** the user can go back and correct position 4 or confirm and continue

### Requirement: Limit and opt-out of the payee check for batches

The app SHALL show a notice when the bank checks the payees only up to a number of positions and the batch has more. The app SHALL offer an opt-out of the payee check for batch transfers that is off by default. In both cases the notice says that the bank is not liable for transfers to account holders whose names differ from the intended recipients, and the batch continues only after the user confirmed the notice.

#### Scenario: Batch larger than the limit

- **GIVEN** the bank supports the payee check for up to 50 positions
- **WHEN** the user reviews a batch with 80 positions
- **THEN** the app says that the payee check cannot be performed because the batch has 80 positions and the bank checks up to 50
- **AND** the app asks whether to submit the order without the check

#### Scenario: Opt-out

- **GIVEN** the user turned on the opt-out in the batch window
- **WHEN** the user clicks "Next"
- **THEN** the app shows the liability notice for the opt-out and asks for confirmation

### Requirement: One TAN for the whole batch

The app SHALL send all positions of a batch as one order that the user confirms with one TAN. The TAN dialog states the number of positions and the total. The result names the batch and says whether the bank accepted it.

#### Scenario: Send twelve salaries

- **WHEN** the user confirms a batch of 12 positions with a total of 31.200,00 € and enters one TAN
- **THEN** the app shows that the batch transfer has been successfully transmitted to the bank
- **AND** "Sent" shows one row for the batch with 12 positions and 31.200,00 €

### Requirement: Positions that the bank rejects

The app SHALL show a status report when the bank accepts a batch and rejects single positions. The report states how many positions were accepted and lists each rejected position with the bank's message. Rejected positions that came from drafts stay under "Drafts". Accepted positions do not stay there.

#### Scenario: Two of ten rejected

- **GIVEN** the bank accepts 8 of 10 positions and rejects positions 3 and 9
- **WHEN** the result appears
- **THEN** the status report says that 8 out of 10 positions were accepted and lists positions 3 and 9 with the bank's reasons
- **AND** the drafts of positions 3 and 9 are still under "Drafts"

### Requirement: Stop after a failed batch

The app SHALL send the batches of a split one after the other and stop when the bank rejects one of them or its result is unknown. The result says that the order was partially transmitted, names the batches that were accepted, and names the batches that were not sent because of the earlier error.

#### Scenario: Second of three batches fails

- **GIVEN** a split into 3 batches
- **WHEN** the bank accepts the first batch and rejects the second
- **THEN** the app does not send the third batch
- **AND** the result says that the batch transfer has been partially transmitted and that the third batch was canceled because of the previous error
- **AND** the positions of the second and the third batch are still under "Drafts"

### Requirement: Drafts move to "Sent" with their batch

The app SHALL remove the drafts of a batch from "Drafts" when the bank accepted the batch, and keep all of them when the bank rejected the batch or the result is unknown.

#### Scenario: Batch rejected

- **WHEN** the bank rejects a batch that was created from 4 drafts
- **THEN** the 4 drafts are still under "Drafts"

### Requirement: Import the outbox

The app SHALL import SEPA XML files as drafts through "Import Outbox...". Each position becomes one draft for the account that has the debtor IBAN of the file. The app reports the number of imported drafts. It rejects other file formats with a message that names SEPA XML as the supported format.

#### Scenario: Import three transfers

- **GIVEN** a SEPA credit transfer file with 3 positions for the account "Giro"
- **WHEN** the user imports the file
- **THEN** "Drafts" shows 3 new transfers and the app reports "Imported 3 draft transfers."

#### Scenario: Wrong format

- **WHEN** the user chooses a CSV file in "Import Outbox..."
- **THEN** the app says that files in this format cannot be imported into the outbox and names SEPA XML

### Requirement: Export the outbox

The app SHALL export the selected drafts, or all drafts when none is selected, as a SEPA XML file through "Export Outbox...". The selection must hold only euro positions with an IBAN, and it must not mix transfers with direct debits. The command works in the view "Drafts".

#### Scenario: Export for another program

- **GIVEN** 4 drafts from "Giro"
- **WHEN** the user chooses "Export Outbox..." and a file name
- **THEN** the app writes a SEPA credit transfer file with 4 positions

#### Scenario: Command in the wrong view

- **GIVEN** the view "Sent" is selected
- **WHEN** the user chooses "Export Outbox..."
- **THEN** the app asks the user to select the drafts view in the filter bar first
