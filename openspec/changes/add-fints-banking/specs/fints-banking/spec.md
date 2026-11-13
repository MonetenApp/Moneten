# Spec Delta

## Purpose

FinTS is the standard interface of German banks for banking software. This capability defines what the app reads through FinTS 3.0 with PIN and TAN, which are accounts, balances, and transactions, and how it reports what the bank answers.

## ADDED Requirements

### Requirement: Find the FinTS address of a bank

The app SHALL take the FinTS address of a bank from its bank directory by Bankleitzahl. The user does not enter an address. A bank without a FinTS address in the directory cannot be reached through FinTS.

#### Scenario: Known bank

- **WHEN** the user sets up an access for the Bankleitzahl 12030000
- **THEN** the app contacts the FinTS address that the bank directory holds for 12030000

#### Scenario: Address changed by the bank

- **GIVEN** an update of the bank directory holds a new FinTS address for "Musterbank"
- **WHEN** the next refresh of an account at "Musterbank" runs
- **THEN** the app contacts the new address and the user does nothing

### Requirement: Identify the app as a registered product

The app SHALL send its product registration number and its version in every FinTS dialog.

#### Scenario: Dialog start

- **WHEN** the app opens a dialog with a bank
- **THEN** the first message contains the registration number of the app and the app version

### Requirement: FinTS messages travel over HTTPS only

The app SHALL send FinTS messages only to an address that starts with `https`, and it SHALL refuse to connect when the bank directory holds another kind of address.

#### Scenario: Plain HTTP address

- **GIVEN** a bank directory entry with an address that starts with `http://`
- **WHEN** the user sets up an access for that bank
- **THEN** the app refuses the connection and says that the bank offers no encrypted FinTS address

### Requirement: List the accounts of a login

The app SHALL read from the bank all accounts that belong to a login, each with its product name, account type, IBAN and BIC or account number, owner name, and currency.

#### Scenario: Login with three products

- **GIVEN** the login "erika77" has a giro account, a savings account in euro, and a credit card
- **WHEN** the app lists the accounts of the login
- **THEN** it reports three accounts with the types "Giro account", "Savings account", and "Credit card"

### Requirement: Use only what the bank allows

The app SHALL read from the bank which operations the bank offers and which of them each account allows, and it SHALL not send an operation that is not allowed. When the user asks for such an operation, the app says which operation the FinTS server of the bank does not support for which account.

#### Scenario: Account without transactions

- **GIVEN** the bank allows the balance and no transaction list for the account "Loan"
- **WHEN** the user refreshes "Loan"
- **THEN** the app fetches the balance only
- **AND** the account view says that the bank provides no transactions for this account

#### Scenario: Bank adds an operation later

- **GIVEN** the bank starts to offer CAMT transactions
- **WHEN** the next dialog with the bank runs
- **THEN** the app uses CAMT from then on without a new setup

### Requirement: Fetch the balance separately

The app SHALL fetch the balance of each account with its date and currency in its own request and store it even when the transaction list of that account cannot be fetched.

#### Scenario: Balance and transactions

- **WHEN** the app refreshes "Giro"
- **THEN** it stores the balance that the bank reports, for example 2.340,15 € on 07.11.2026, and the new transactions

#### Scenario: Transaction request fails

- **GIVEN** the bank answers the balance request and rejects the transaction request with an error
- **WHEN** the refresh ends
- **THEN** "Giro" shows the new balance and the error of the transaction request

### Requirement: Prefer CAMT over MT940

The app SHALL fetch transactions in the CAMT format when the bank offers it for the account, and in the MT940 format otherwise. Both formats lead to the same fields in the transaction list.

#### Scenario: Bank offers both

- **GIVEN** the bank offers CAMT and MT940 for "Giro"
- **WHEN** the app fetches the transactions of "Giro"
- **THEN** it requests CAMT

#### Scenario: Bank offers MT940 only

- **GIVEN** the bank offers only MT940 for "Savings"
- **WHEN** the app fetches the transactions of "Savings"
- **THEN** it requests MT940 and shows booking date, value date, amount, counterparty, and purpose

### Requirement: A normal refresh asks for at most 90 days

The app SHALL ask in a normal refresh for the transactions since the last successful fetch of the account with an overlap of 14 days, and for no more than the last 90 days, so that the bank needs no TAN for older transactions.

#### Scenario: Daily use

- **GIVEN** the last successful fetch of "Giro" was on 01.11.2026
- **WHEN** a refresh runs on 09.11.2026
- **THEN** the app asks for the transactions from 18.10.2026 on

#### Scenario: Long pause

- **GIVEN** the last successful fetch of "Giro" was 200 days ago
- **WHEN** a normal refresh runs
- **THEN** the app asks for the last 90 days
- **AND** the account view says that older transactions may be missing and names "Refresh Account (enforced)"

### Requirement: The first refresh asks for the full history

The app SHALL ask in the first refresh of a new account for all transactions that the bank keeps. When the bank asks for a TAN for transactions older than 90 days and the user cancels that TAN, the app fetches the last 90 days.

#### Scenario: Bank keeps 450 days

- **GIVEN** the bank keeps 450 days of transactions and needs no extra TAN after the login
- **WHEN** the first refresh of "Giro" ends
- **THEN** the list of "Giro" starts 450 days ago

#### Scenario: TAN for older transactions canceled

- **WHEN** the bank asks for a TAN for transactions older than 90 days and the user cancels
- **THEN** the list of "Giro" contains the last 90 days
- **AND** the account shows no error

### Requirement: Enforced refresh

The app SHALL offer "Refresh Account (enforced)" in the context menu of an account and "Refresh Accounts (enforced)" for a group while the user holds the Option key. The command asks the bank for the full history again. The result contains no transaction twice.

#### Scenario: Close a gap

- **GIVEN** "Giro" has a gap between February and April 2026, and the bank keeps 450 days
- **WHEN** the user chooses "Refresh Account (enforced)" on 09.11.2026 and enters the TAN that the bank asks for
- **THEN** the transactions of the gap are in the list
- **AND** no transaction that was in the list before appears twice

#### Scenario: Option key not held

- **WHEN** the user opens the context menu of "Giro" without the Option key
- **THEN** the menu shows "Refresh Account" and not the enforced command

### Requirement: Say when the bank has no older transactions

The app SHALL tell the user, after a fetch of the full history, the date of the oldest transaction that the bank delivered, and that the bank provides no older transactions.

#### Scenario: Bank keeps 30 days

- **GIVEN** the bank keeps only 30 days
- **WHEN** an enforced refresh ends on 09.11.2026
- **THEN** the app says that the bank provides no transactions before 10.10.2026

### Requirement: Fetch every part of a long answer

The app SHALL request the next part when a bank delivers a transaction list in several parts, until the list is complete, and store the transactions only when all parts arrived.

#### Scenario: List in three parts

- **GIVEN** the bank delivers 1,400 transactions in three parts
- **WHEN** the fetch ends
- **THEN** the account has all 1,400 transactions

### Requirement: Mark pending transactions

The app SHALL take over the transactions that a bank reports as not yet booked and mark each of them as pending.

#### Scenario: Card payment not yet booked

- **GIVEN** the bank reports a card payment of -23,80 € as pending
- **WHEN** the refresh ends
- **THEN** the list shows the payment as a pending transaction

### Requirement: Store booking date and value date

The app SHALL store for each transaction the booking date and the value date that the bank reports.

#### Scenario: Different dates

- **WHEN** the bank reports a transaction booked on 02.11.2026 with the value date 30.10.2026
- **THEN** the transaction details show both dates

### Requirement: Split the structured purpose into fields

The app SHALL take the counterparty name, the counterparty IBAN and BIC, the booking text, the end-to-end reference, the mandate reference, the creditor ID, and the purpose text from a transaction as separate fields, also when an MT940 statement delivers them as tagged text inside the purpose.

#### Scenario: Tagged text in MT940

- **GIVEN** an MT940 transaction with the text "EREF+RE-2026-1001 MREF+M-4711 CRED+DE98ZZZ09999999999 SVWZ+Rechnung 1001"
- **WHEN** the app stores the transaction
- **THEN** the end-to-end reference is "RE-2026-1001", the mandate reference is "M-4711", the creditor ID is "DE98ZZZ09999999999", and the purpose is "Rechnung 1001"

#### Scenario: Structured fields in CAMT

- **GIVEN** a CAMT transaction with the debtor "Stadtwerke Musterstadt" and the end-to-end reference "SW-778899"
- **WHEN** the app stores the transaction
- **THEN** the counterparty is "Stadtwerke Musterstadt" and the end-to-end reference is "SW-778899"

### Requirement: Join purpose lines

The app SHALL join the lines into which a bank splits a purpose so that words that were cut at a line end are whole again and separate words stay separate.

#### Scenario: Word cut at the line end

- **GIVEN** the bank delivers the purpose in the lines "Abschlagszahlung Strom Kundenn" and "ummer 4711"
- **WHEN** the app stores the transaction
- **THEN** the purpose reads "Abschlagszahlung Strom Kundennummer 4711"

### Requirement: Use the end-to-end reference when the purpose is missing

The app SHALL show the end-to-end reference as the purpose of a transaction when the bank delivers an end-to-end reference and no purpose text.

#### Scenario: Reference only

- **WHEN** the bank delivers a transaction with the end-to-end reference "INV-2026-0042" and an empty purpose
- **THEN** the list shows "INV-2026-0042" as the purpose

#### Scenario: Placeholder reference

- **WHEN** the bank delivers the end-to-end reference "NOTPROVIDED" and an empty purpose
- **THEN** the purpose stays empty

### Requirement: Keep the original amount and the deviating party

The app SHALL store the original amount and currency of a transaction that the bank converted, and the name of a deviating originator or recipient when the bank reports one.

#### Scenario: Card payment abroad

- **GIVEN** the bank reports a card payment of -46,12 € with the original amount 50,00 US dollars
- **WHEN** the user opens the transaction details
- **THEN** the details show 50,00 US dollars as the original amount

#### Scenario: Payment through a payment service

- **GIVEN** the bank reports the counterparty "Zahlungsdienst Muster GmbH" and the deviating recipient "Buchhandlung Beispiel"
- **WHEN** the user opens the transaction details
- **THEN** the details show both names

### Requirement: Credit cards through FinTS

The app SHALL list a credit card as an account of the type "Credit card" when the bank offers it through FinTS, and fetch its balance and transactions like those of any other account.

#### Scenario: Card of the house bank

- **GIVEN** the bank reports a credit card for the login of the giro account
- **WHEN** the user adds the card in the account selection
- **THEN** the card appears as its own account with its transactions

### Requirement: Read the value of a securities account

The app SHALL fetch the value of a securities account through the custody account balance (HKWPD) in place of its balance and transactions when the bank allows it, and store it with the date of the statement as the value of the portfolio on that day. The value sums the totals of all pages of the statement, or the values of the holdings of a page without a total. When the app cannot read a value, the account says why.

#### Scenario: Value of a securities account

- **GIVEN** the bank offers the custody account balance for "Depot" and reports a total of 24.518,37 € on 12.11.2026
- **WHEN** the user refreshes "Depot"
- **THEN** "Depot" shows 24.518,37 €
- **AND** the value of "Depot" on 12.11.2026 is 24.518,37 €

#### Scenario: Bank without the custody account balance

- **GIVEN** the bank lists the securities account "Fondsdepot" and allows neither the custody account balance, nor the balance, nor the transactions for it
- **WHEN** the user refreshes "Fondsdepot"
- **THEN** "Fondsdepot" shows "Moneten can't read this securities account at this bank yet."

#### Scenario: Answer without a value

- **GIVEN** the bank answers the custody account balance of "Depot" without a total, and its holdings have no value in one currency
- **WHEN** the refresh ends
- **THEN** "Depot" shows "The bank sent no value for this securities account."

#### Scenario: Bank rejects the request

- **WHEN** the bank answers the custody account balance of "Depot" with the code 9160 and the text "Erforderliche Auftragsreferenz fehlt"
- **THEN** the error of "Depot" quotes "Erforderliche Auftragsreferenz fehlt" and shows the code 9160

#### Scenario: Consorsbank

- **GIVEN** a login at Consorsbank, whose bank parameters say that no order needs a TAN
- **WHEN** the app refreshes a giro account and a securities account of the login
- **THEN** the balance and the transactions go with HKTAN, and the custody account balance goes without HKTAN

### Requirement: One dialog for all accounts of a login

The app SHALL fetch all accounts of one login that are due in a refresh inside one FinTS dialog, so that the bank sees one login and asks for at most one TAN for that login.

#### Scenario: Three accounts, one login

- **GIVEN** "Giro", "Savings", and "Card" belong to the login "erika77"
- **WHEN** the user chooses "Refresh All Accounts" and the bank asks for a TAN at login
- **THEN** the user enters one TAN
- **AND** all three accounts are refreshed

### Requirement: Show notices of the bank

The app SHALL show a notice that the bank sends through FinTS, for example about planned maintenance, in a window titled "Notice" with the name of the bank and the text of the bank. Each notice is shown once.

#### Scenario: Maintenance announcement

- **GIVEN** the bank sends the notice "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"
- **WHEN** the refresh ends
- **THEN** the app shows the notice with the name of the bank
- **AND** the next refresh does not show the same notice again

### Requirement: Show errors in the words of the bank

The app SHALL show the text and the return code that the bank sends when the bank rejects a request, name the bank and the account, and add its own explanation only as a separate sentence.

#### Scenario: Bank rejects a request

- **WHEN** the bank answers a transaction request with the code 9010 and the text "Verarbeitung nicht möglich"
- **THEN** the error of the account quotes "Verarbeitung nicht möglich" and shows the code 9010

#### Scenario: Warning with a successful answer

- **WHEN** the bank delivers the transactions together with a warning text
- **THEN** the transactions are stored
- **AND** the log contains the warning

### Requirement: Handle a PIN change that the bank requires

The app SHALL stop the dialog when the bank reports that the PIN must be changed, tell the user so, and name the ways to change it, which are the website of the bank and the PIN change assistant when the app has one.

#### Scenario: First login with a start PIN

- **WHEN** the bank answers the login with the request to change the PIN
- **THEN** the account shows that the server requires a PIN change and where to change it
- **AND** the app sends no further request with the old PIN

### Requirement: Handle a blocked access

The app SHALL stop when the bank reports that the PIN or the access is blocked, show the message of the bank, tell the user to ask the bank to unblock it, and not log in again for that access until the user starts a refresh by hand.

#### Scenario: PIN blocked after wrong attempts

- **WHEN** the bank reports that the PIN is blocked
- **THEN** the accounts of the access show that the server has blocked the PIN
- **AND** the automatic refresh skips this access from then on

### Requirement: Cancel and interruption

The app SHALL end the FinTS dialog with the bank when the user cancels a refresh, and it SHALL store nothing for an account whose fetch was canceled, timed out, or lost its connection. Accounts that were complete before stay stored.

#### Scenario: Cancel during the second account

- **GIVEN** a refresh of "Giro" and "Savings" in one dialog, and "Giro" is complete
- **WHEN** the user chooses "Cancel Refresh" while "Savings" is being fetched
- **THEN** "Giro" shows its new transactions
- **AND** "Savings" is unchanged

#### Scenario: Timeout

- **WHEN** the bank does not answer within the time limit
- **THEN** the account shows that the connection to the FinTS server of the bank timed out
