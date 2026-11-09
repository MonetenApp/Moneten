# Spec Delta

## Purpose

Some orders wait at the bank for a later date. This capability covers scheduled transfers, standing orders, and orders from a service data center (SRZ). It defines how the user creates them, the view that lists them, and how the app fetches, changes, deletes, and authorizes them.

## ADDED Requirements

### Requirement: Schedule a transfer for a later date

The app SHALL let the user choose "Set date" under "Schedule" in the payment window and pick an execution date. The bank receives the order now and executes it on that date. With "Now" the transfer is executed at once.

#### Scenario: Pay an invoice on its due date

- **GIVEN** today is 3 November 2026
- **WHEN** the user enters a transfer of 89,00 € to "Stadtwerke Musterstadt", chooses "Set date", picks 28 November 2026, and confirms
- **THEN** the bank accepts a scheduled transfer for 28 November 2026
- **AND** the order appears in the view "Scheduled"

#### Scenario: Date in the past

- **WHEN** the user picks a date before today
- **THEN** the app rejects the date and "Next" stays disabled

### Requirement: Scheduled orders use the checks of a transfer

The app SHALL apply the field checks, the warnings, the review step, the payee check, the TAN confirmation, and the result handling of a transfer to scheduled transfers and to standing orders.

#### Scenario: Payee check for a standing order

- **WHEN** the user creates a standing order for "Erika Mustermann" and clicks "Next"
- **THEN** the review step shows the payee check result before the user can confirm

### Requirement: Respect the lead times of the bank

The app SHALL check the execution date against the minimum and the maximum lead time that the bank reports for the kind of order. For a date that is too early the app names the next possible date. For a date that is too late it names the latest possible date.

#### Scenario: Too early

- **GIVEN** the bank requires a lead time of 1 day for scheduled transfers and today is 3 November 2026
- **WHEN** the user picks 3 November 2026 as the scheduled date
- **THEN** the app says that the next possible scheduled date is 4 November 2026

#### Scenario: Too far in the future

- **GIVEN** the bank allows a lead time of at most 90 days for scheduled transfers and today is 3 November 2026
- **WHEN** the user picks 1 June 2027
- **THEN** the app says that the latest possible scheduled date is 1 February 2027

### Requirement: Scheduled transfers only where the bank supports them

The app SHALL read from the bank's parameter data whether the source account supports scheduled transfers. When it does not, the app says so and suggests a transfer without a scheduled date.

#### Scenario: Bank without scheduled transfers

- **GIVEN** the bank does not support scheduled transfers for the account "Giro"
- **WHEN** the user chooses "Set date"
- **THEN** the app explains that the bank does not support scheduled transfers for this account and suggests a bank transfer without a scheduled date

### Requirement: Scheduled transfer between own accounts

The app SHALL allow a scheduled date for a transfer between the user's own accounts.

#### Scenario: Move money next week

- **WHEN** the user chooses "Transfer to Tagesgeld", enters 500,00 €, sets the date to 10 November 2026, and confirms
- **THEN** the bank accepts the scheduled transfer to the user's own account

### Requirement: Create a standing order

The app SHALL open the payment window for a standing order through "New Standing Order..." in the Payment menu, through "New standing order" under "Action", and through the toolbar button "Standing order" in the view "Scheduled". The window has the fields of a transfer and the fields "First payment on", "Repeat", "Transaction day", and "Last payment on".

#### Scenario: Monthly rent

- **WHEN** the user enters a standing order of 950,00 € to "Erika Mustermann" with the purpose "Miete", the first payment on 1 December 2026, a monthly repeat, and no last payment
- **THEN** the review step shows a monthly standing order from 1 December 2026 without an end
- **AND** the bank accepts the standing order after the confirmation

### Requirement: Intervals and execution days of a standing order

The app SHALL offer for a standing order the intervals and the execution days that the bank reports as allowed. The last day of the month is offered as its own execution day.

#### Scenario: Quarterly on the last day

- **GIVEN** the bank allows an interval of 3 months and the last day of the month
- **WHEN** the user chooses a repeat of every 3 months and the last day of the month, starting in December 2026
- **THEN** the review step shows the payments on 31 December 2026, 31 March 2027, and 30 June 2027 as the first three dates

#### Scenario: Interval the bank does not offer

- **GIVEN** the bank allows only monthly intervals
- **WHEN** the user opens "Repeat"
- **THEN** the menu offers no weekly interval

### Requirement: First and last payment of a standing order

The app SHALL require a first payment date for a standing order and accept an optional last payment date. The first payment date must lie before the last payment date. The first payment follows the lead time rule of the bank for standing orders.

#### Scenario: Last payment before first payment

- **WHEN** the user sets the first payment to 1 December 2026 and the last payment to 1 November 2026
- **THEN** the app shows that the first payment date must be before the last payment date

#### Scenario: Limited standing order

- **WHEN** the user sets the first payment to 1 December 2026 and the last payment to 1 November 2027 with a monthly repeat
- **THEN** the list shows the standing order with the note "until 01.11.2027"

### Requirement: Standing orders only where the bank supports them

The app SHALL read from the bank's parameter data whether the source account supports standing orders, and it SHALL say so when the account does not.

#### Scenario: Account without standing orders

- **GIVEN** the bank does not support standing orders for the account "Tagesgeld"
- **WHEN** the user chooses "New standing order" for "Tagesgeld"
- **THEN** the app explains that the bank does not support standing orders for the account with this IBAN

### Requirement: No placeholders in standing orders

The app SHALL send the purpose of a standing order as the user entered it. The app warns when the purpose contains a template placeholder, because the bank executes the order and cannot replace placeholders.

#### Scenario: Placeholder in the purpose

- **WHEN** the user enters the purpose "Miete @MMMM YYYY@" in a standing order and clicks "Next"
- **THEN** the app warns that the placeholder will appear as written in every payment

### Requirement: The view "Scheduled"

The app SHALL show a view "Scheduled" under "Payments" in the sidebar. The view lists the scheduled transfers, standing orders, scheduled batch transfers, and SRZ orders of all accounts that the banks have not yet executed or that repeat.

#### Scenario: Orders of several accounts

- **GIVEN** a standing order from "Giro" and a scheduled transfer from "Business"
- **WHEN** the user selects "Scheduled"
- **THEN** the list shows both orders

#### Scenario: Nothing scheduled

- **GIVEN** no account has a scheduled order
- **WHEN** the user selects "Scheduled"
- **THEN** the view says that no scheduled transfers or standing orders were found

### Requirement: Filters of the view "Scheduled"

The app SHALL offer in the view "Scheduled" a filter "Kind" with "All", "Scheduled Transfers", "Standing Orders", and "SRZ Orders", and a filter "Account" with "Show All" and one entry for each account.

#### Scenario: Standing orders of one account

- **WHEN** the user chooses "Standing Orders" under "Kind" and "Giro" under "Account"
- **THEN** the list shows only the standing orders of "Giro"

### Requirement: Content of a scheduled order row

The app SHALL show for each scheduled order its kind, the next execution date, the amount, the recipient, the IBAN, the purpose, and the source account. A standing order also shows its interval and its last payment date or that it has no end. The status line shows the number of listed orders and their sum.

#### Scenario: Status line

- **GIVEN** the list shows three standing orders of 950,00 €, 49,90 €, and 25,00 €
- **WHEN** the user looks at the status line
- **THEN** it shows "3 Standing Orders" and the sum -1.024,90 €

### Requirement: Fetch the scheduled payments from the banks

The app SHALL fetch the lists of scheduled transfers, standing orders, and SRZ orders from the banks when the user chooses "Refresh Scheduled Payments". The command is in the File menu, on a button in the view "Scheduled", and in the context menu of "Scheduled" in the sidebar. The view then shows what the banks hold.

#### Scenario: Order created on the bank website

- **GIVEN** the user created a standing order on the website of the bank
- **WHEN** the user clicks "Refresh Scheduled Payments"
- **THEN** the standing order appears in the list

#### Scenario: Order deleted on the bank website

- **GIVEN** the user deleted a scheduled transfer on the website of the bank
- **WHEN** the user clicks "Refresh Scheduled Payments"
- **THEN** the scheduled transfer is no longer in the list

### Requirement: Compare with the bank only when an order is due

The app SHALL fetch the scheduled payments of an account during a normal refresh only when the execution date of one of its listed orders has arrived. A normal refresh does not ask the bank for the lists otherwise.

#### Scenario: Scheduled transfer was executed

- **GIVEN** a scheduled transfer for 28 November 2026
- **WHEN** the account is refreshed on 28 November 2026
- **THEN** the app fetches the scheduled payments of the account
- **AND** the executed transfer leaves the list

#### Scenario: Nothing due

- **GIVEN** the next execution date of all orders of "Giro" lies 10 days ahead
- **WHEN** "Giro" is refreshed
- **THEN** the app does not ask the bank for the scheduled payments of "Giro"

### Requirement: A new order is visible at once

The app SHALL list an order in "Scheduled" as soon as the bank accepted it, also when the bank does not yet return it in its own list. The entry from the bank replaces the local entry when it arrives.

#### Scenario: Bank lists the order with a delay

- **GIVEN** the bank accepted a new standing order and its list does not contain the order yet
- **WHEN** the user opens "Scheduled"
- **THEN** the new standing order is in the list

### Requirement: Change a standing order

The app SHALL open a standing order with its current values through "Change Standing Order..." in the Payment menu and in the context menu. After the user changed the values and confirmed with a TAN, the app sends the change to the bank and shows that the standing order has been changed.

#### Scenario: Raise the rent

- **GIVEN** a standing order of 950,00 € to "Erika Mustermann"
- **WHEN** the user chooses "Change Standing Order...", sets the amount to 980,00 €, and confirms with a TAN
- **THEN** the app shows that the standing order has been changed
- **AND** the list shows 980,00 €

### Requirement: Delete a standing order

The app SHALL delete a standing order at the bank through "Delete Standing Order..." after the user confirmed the deletion and, when the bank asks for it, a TAN. The app then shows that the standing order has been deleted and removes it from the list.

#### Scenario: Cancel a subscription

- **WHEN** the user chooses "Delete Standing Order..." for a standing order of 49,90 € and confirms
- **THEN** the bank deletes the standing order
- **AND** the order is no longer in the list

#### Scenario: User declines

- **WHEN** the user chooses "Delete Standing Order..." and cancels the confirmation
- **THEN** the standing order stays unchanged

### Requirement: Change and delete a scheduled transfer

The app SHALL offer "Change Scheduled Transfer..." and "Delete Scheduled Transfer..." for a scheduled transfer that the bank has not executed. Both work like the commands for a standing order.

#### Scenario: Move the date

- **GIVEN** a scheduled transfer for 28 November 2026
- **WHEN** the user changes the scheduled date to 30 November 2026 and confirms with a TAN
- **THEN** the list shows the transfer with the date 30 November 2026

### Requirement: Say what the bank cannot change or delete

The app SHALL check before each change and deletion whether the bank supports it for this account and this kind of order. When the bank does not, the app says so and names the alternative. The alternative is to delete the order and create a new one, or to make the change on the website of the bank.

#### Scenario: Bank cannot change standing orders

- **GIVEN** the bank does not support changing standing orders for the account "Giro"
- **WHEN** the user chooses "Change Standing Order..."
- **THEN** the app explains that the bank does not support changing standing orders for this account and suggests deleting the order and creating a new standing order

#### Scenario: Bank cannot delete scheduled transfers

- **GIVEN** the bank does not support deleting scheduled transfers
- **WHEN** the user chooses "Delete Scheduled Transfer..."
- **THEN** the app explains that the scheduled transfer cannot be deleted with the app and points to the website of the bank

### Requirement: Instant scheduled orders are shown and not changed

The app SHALL list instant scheduled transfers and instant standing orders with their kind, and it SHALL not offer to change them. The app says that these orders cannot be changed in the app.

#### Scenario: Instant standing order

- **GIVEN** the bank returns an instant standing order
- **WHEN** the user chooses the change command for it
- **THEN** the app explains that instant standing orders cannot be changed with the app

### Requirement: Scheduled batch transfers are listed and can be deleted

The app SHALL list a scheduled batch transfer that the bank holds with its execution date, its total, and the number of positions. The app says that the single positions cannot be displayed. The batch can be deleted where the bank supports it. It cannot be changed, and the app suggests deleting it and creating a new scheduled batch transfer.

#### Scenario: Batch in the list

- **GIVEN** the bank holds a scheduled batch transfer with 12 positions and a total of 18.400,00 € for 30 November 2026
- **WHEN** the user opens "Scheduled"
- **THEN** the list shows one row for the batch with the date and the total

#### Scenario: Try to change a batch

- **WHEN** the user chooses the change command for a scheduled batch transfer
- **THEN** the app explains that scheduled batch transfers cannot be changed through FinTS and suggests deleting it and creating a new one

### Requirement: List SRZ orders

The app SHALL list the orders that a service data center submitted to the bank for the user's accounts under the kind "SRZ Orders". An SRZ order stays in the list when its planned execution date has passed and it is not yet authorized.

#### Scenario: Payroll file waits for authorization

- **GIVEN** a payroll office submitted an order with a total of 24.500,00 € for 27 November 2026
- **WHEN** the user refreshes the scheduled payments on 28 November 2026
- **THEN** the order is listed under "SRZ Orders" as not authorized

### Requirement: Authorize an SRZ order

The app SHALL send the authorization of an SRZ order to the bank through "Authorize SRZ Order..." after the user confirmed with a TAN. The row then shows the date of the authorization. For an order that is already authorized the app says so and shows that date.

#### Scenario: Authorize

- **WHEN** the user chooses "Authorize SRZ Order..." for an order of 24.500,00 € and confirms with a TAN
- **THEN** the app shows that the SRZ order has been authorized
- **AND** the row shows "authorized on" with today's date

#### Scenario: Already authorized

- **GIVEN** an SRZ order that was authorized on 20 November 2026
- **WHEN** the user chooses "Authorize SRZ Order..."
- **THEN** the app says that this SRZ order has already been authorized on 20 November 2026

### Requirement: Payee check notice for SRZ orders

The app SHALL show a notice before it authorizes an SRZ order when the bank cannot run the payee check for SRZ orders or when the user opted out of the check. The notice says that the bank is not liable for transfers to account holders whose names differ from the intended recipients. The authorization continues only after the user confirmed the notice.

#### Scenario: Bank cannot check SRZ orders

- **GIVEN** the bank does not support the payee check for SRZ orders
- **WHEN** the user chooses "Authorize SRZ Order..."
- **THEN** the app shows the liability notice and asks whether to submit the authorization

### Requirement: Delete an SRZ order and explain missing support

The app SHALL delete an SRZ order at the bank through "Delete SRZ Order..." after a confirmation. When the bank does not support authorizing or deleting SRZ orders for the account, or has not activated the function for the user, the app says so and advises the user to contact the bank.

#### Scenario: Function not activated

- **GIVEN** the bank has not activated SRZ authorization for the user ID
- **WHEN** the user chooses "Authorize SRZ Order..."
- **THEN** the app explains that the bank must activate SRZ order authorization for the user ID first

#### Scenario: Delete

- **WHEN** the user chooses "Delete SRZ Order..." and confirms
- **THEN** the app shows that the SRZ order has been deleted and removes it from the list

### Requirement: New payment from a scheduled order

The app SHALL offer "New from Selection" with "New Bank Transfer..." in the context menu of a scheduled order. The payment window opens with the recipient, the IBAN, the BIC, the amount, and the purpose of that order.

#### Scenario: Extra payment to the landlord

- **GIVEN** a standing order of 950,00 € to "Erika Mustermann"
- **WHEN** the user chooses "New from Selection" and "New Bank Transfer..."
- **THEN** the payment window shows a new transfer of 950,00 € to "Erika Mustermann"

### Requirement: Commands follow the selection

The app SHALL enable the commands to change, delete, and authorize a scheduled order only when exactly one order of the matching kind is selected.

#### Scenario: No selection

- **GIVEN** no row is selected in "Scheduled"
- **WHEN** the user opens the Payment menu
- **THEN** "Change Standing Order..." and "Delete Standing Order..." are disabled

### Requirement: Hint about changes made outside the app

The app SHALL show a hint after it created, changed, or deleted a scheduled order. The hint says that orders that the user changes on the website of the bank appear in the app after "Refresh Scheduled Payments".

#### Scenario: Hint after a deletion

- **WHEN** the app shows that a standing order has been deleted
- **THEN** the result also names "Refresh Scheduled Payments" as the way to fetch changes that were made on the website of the bank
