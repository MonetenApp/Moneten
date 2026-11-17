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

### Requirement: Correct a BIC that the bank no longer uses

The app SHALL store the BIC `GENODEF1ETK` for an account of a login at the Bankleitzahl 83094495 when the bank sends the old BIC `GENODEF1ESN` for it. Any other BIC stays as the bank sends it.

#### Scenario: Old BIC of the bank

- **GIVEN** the bank with the Bankleitzahl 83094495 lists the account DE02120300000000202051 with the BIC `GENODEF1ESN`
- **WHEN** the setup adds the account
- **THEN** the account has the BIC `GENODEF1ETK`

#### Scenario: Same BIC at another bank

- **GIVEN** a bank with the Bankleitzahl 12030000 lists an account with the BIC `GENODEF1ESN`
- **WHEN** the setup adds the account
- **THEN** the account has the BIC `GENODEF1ESN`

### Requirement: Accounts of the partners of a cooperative bank

The app SHALL fetch the accounts of the partners that a cooperative bank on a host that ends in `.atruvia.de` or `.bankenit.de` lists for the login, such as a building savings contract of Bausparkasse Schwäbisch Hall or a fund depot of Union Investment, and offer them in the account selection with their balance or value.

#### Scenario: Building savings contract

- **GIVEN** a Volksbank lists a building savings contract of Bausparkasse Schwäbisch Hall with a balance of 4.250,00 € for the login
- **WHEN** the user looks for new accounts
- **THEN** the list offers "Bausparvertrag" with 4.250,00 €

#### Scenario: Fund depot

- **GIVEN** a Volksbank lists a fund depot of Union Investment with a value of 1.200,00 € for the login
- **WHEN** a refresh of the depot ends
- **THEN** the depot is a portfolio with the value 1.200,00 €

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

The app SHALL ask in a normal refresh for the transactions since the last successful fetch of the account with an overlap of 14 days, or from its oldest pending transaction when that is earlier, and for no more than the last 90 days. The bank then needs no TAN for older transactions, and the refresh can remove a pending transaction that the bank dropped. Only when the 90 days start after the day of the last successful fetch does the account view say that older transactions may be missing.

#### Scenario: Daily use

- **GIVEN** the last successful fetch of "Giro" was on 01.11.2026
- **WHEN** a refresh runs on 09.11.2026
- **THEN** the app asks for the transactions from 18.10.2026 on

#### Scenario: Old pending transaction

- **GIVEN** the last successful fetch of "Giro" was on 22.11.2026 and "Giro" has a pending transaction of -500,00 € on 01.11.2026
- **WHEN** a refresh runs
- **THEN** the app asks for the transactions from 01.11.2026 on

#### Scenario: Long pause

- **GIVEN** the last successful fetch of "Giro" was 200 days ago
- **WHEN** a normal refresh runs
- **THEN** the app asks for the last 90 days
- **AND** the account view says that older transactions may be missing and names "Refresh Account (enforced)"

#### Scenario: Pause shorter than 90 days

- **GIVEN** today is 16.11.2026 and the last successful fetch of "Giro" was 80 days ago, on 28.08.2026
- **WHEN** a normal refresh runs
- **THEN** the app asks for the transactions from 18.08.2026 on, 90 days ago
- **AND** the account view says nothing about missing older transactions

#### Scenario: Pending transaction older than 90 days

- **GIVEN** the last successful fetch of "Giro" was yesterday and "Giro" has a pending transaction of -500,00 € from 120 days ago
- **WHEN** a normal refresh runs
- **THEN** the app asks for the last 90 days
- **AND** the account view says nothing about missing older transactions

### Requirement: The first refresh asks for the full history

The app SHALL ask in the first refresh of a new account for all transactions that the bank keeps. When the bank asks for a TAN or a confirmation for transactions older than 90 days and the user cancels it, the app fetches the last 90 days. The account view then says that older transactions may be missing, until a refresh brings the full history of the account. The note stays with the account.

#### Scenario: Bank keeps 450 days

- **GIVEN** the bank keeps 450 days of transactions and needs no extra TAN after the login
- **WHEN** the first refresh of "Giro" ends
- **THEN** the list of "Giro" starts 450 days ago

#### Scenario: TAN for older transactions canceled

- **WHEN** the bank asks for a TAN for transactions older than 90 days and the user cancels
- **THEN** the list of "Giro" contains the last 90 days
- **AND** the account shows no error
- **AND** the account view says "Older transactions may be missing. Choose “Refresh Account (enforced)” with the Option key to fetch them."

#### Scenario: Confirmation for older transactions canceled before the bank answers

- **GIVEN** the bank asks for a confirmation in the banking app for transactions older than 90 days
- **WHEN** the user rejects the request in the banking app and clicks "Cancel" in the app before the app asks the bank about the confirmation again
- **THEN** the list of "Giro" contains the last 90 days
- **AND** the account shows no error

#### Scenario: The note stays after a lock

- **GIVEN** the account view of "Giro" says that older transactions may be missing
- **WHEN** the user locks the app and unlocks it, or quits the app and starts it again
- **THEN** the account view of "Giro" still says that older transactions may be missing

#### Scenario: The note stays after an export and an import

- **GIVEN** the account view of "Giro" says that older transactions may be missing
- **WHEN** the user chooses "Export All Data..." and imports the file with "Import All Data..." into an empty database
- **THEN** the account view of "Giro" says that older transactions may be missing

#### Scenario: Enforced refresh after the canceled TAN

- **GIVEN** the first refresh of "Giro" brought the last 90 days after the user canceled the TAN for older transactions, and the bank balance and the computed balance of "Giro" are 10.000,00 €
- **WHEN** the user chooses "Refresh Account (enforced)", enters the TAN, and the bank delivers older transactions that add up to -500,00 € with a bank balance of 10.000,00 €
- **THEN** the computed balance of "Giro" is 10.000,00 €, not 9.500,00 €
- **AND** the account view no longer says that older transactions may be missing

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

### Requirement: Amount limit of a bank answer

The app SHALL fail an account when the bank sends a balance, a value, or a transaction, or a position whose quantity times its price gives an amount, of more than 1,000,000,000,000,000 in the smallest unit of its currency, which is 10.000.000.000.000,00 € for the euro. The app stores nothing of that account from this refresh, and the other accounts of the login refresh as usual.

#### Scenario: Absurd balance

- **WHEN** the bank sends a balance of 50.000.000.000.000.000,00 € for the account "Giro"
- **THEN** the account "Giro" shows that the bank sent an amount that is too large
- **AND** the account "Tagesgeld" of the same login shows its new balance

#### Scenario: Absurd position

- **WHEN** the bank sends a position of 10.000.000.000 units at a price of 10.000.000.000,00 € without a market value for the portfolio "Depot"
- **THEN** the portfolio "Depot" shows that the bank sent an amount that is too large

### Requirement: Mark pending transactions

The app SHALL take over the transactions that a bank reports as not yet booked and mark each of them as pending.

#### Scenario: Card payment not yet booked

- **GIVEN** the bank reports a card payment of -23,80 € as pending
- **WHEN** the refresh ends
- **THEN** the list shows the payment as a pending transaction

#### Scenario: Pending MT942 row of Commerzbank

- **GIVEN** the FinTS server `fints.commerzbank.de` sends a pending MT942 row whose `:61:` line has the value date 14.11.2026, the entry date 15.11 as the expected booking day, the amount -42,00 €, and the name "Stadtwerke Musterstadt"
- **WHEN** the refresh ends
- **THEN** the pending transaction has the booking date 15.11.2026, the value date 14.11.2026, and the name "Stadtwerke Musterstadt"

#### Scenario: Expected booking day in the year before

- **GIVEN** the FinTS server `fints.commerzbank.de` sends a pending MT942 row whose `:61:` line has the value date 02.01.2026 and the entry date 31.12
- **WHEN** the refresh ends
- **THEN** the pending transaction has the booking date 31.12.2025

#### Scenario: Pending Postbank card payment without a name

- **GIVEN** the bank on the host `hbci.postbank.de` reports a pending row with the booking text "Kartenzahlung", no counterparty, the purpose "Kartenzahlung / Buchhandlung Beispiel", and the amount -23,80 €
- **WHEN** the refresh ends
- **THEN** the pending transaction has the name "Buchhandlung Beispiel", the text after the first " / " of the purpose
- **AND** when the bank later books -23,80 € to "Buchhandlung Beispiel", the booked transaction replaces the pending one

#### Scenario: Pending Postbank card payment of one word

- **GIVEN** the bank on the host `hbci.postbank.de` reports a pending row with the booking text "Kartenzahlung", no counterparty, and the purpose "PayPal"
- **WHEN** the refresh ends
- **THEN** the pending transaction has the name "PayPal"
- **AND** a purpose of several words without " / ", a booked row, a row with a counterparty, and a row of another bank keep the name that the bank sent

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

#### Scenario: Sign of the original amount of an MT942 row

- **GIVEN** the bank reports a pending MT942 row of -10,00 € with the original amount 11,00 US dollars
- **WHEN** the refresh ends
- **THEN** the original amount is -11,00 US dollars

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

### Requirement: Ask for the name of the apoTAN device

The app SHALL ask for the name of the apoTAN device in a text field that may stay empty when the FinTS server `fints.apobank.de` asks for a TAN medium and lists none. The hint under the field says that the user leaves it empty unless the bank reports an error in the next step, and then enters the name exactly as the apoTAN settings of the website of apoBank show it. The app remembers the answer for the access, also an empty one, and sends it again while the bank lists no TAN media.

#### Scenario: Empty list of TAN media

- **GIVEN** the user adds an account of apoBank, whose FinTS server is `fints.apobank.de`
- **WHEN** the bank asks for a TAN medium and lists none
- **THEN** the dialog shows an empty text field "apoTAN device name" with the hint
- **AND** "Continue" is enabled

#### Scenario: Next refresh

- **GIVEN** the user left the field "apoTAN device name" empty in the setup
- **WHEN** the next refresh of the access asks for a TAN medium and the bank lists none
- **THEN** the app sends the empty name again and shows no dialog for it

#### Scenario: Name needed after the setup

- **WHEN** the dialog shows the field "apoTAN device name"
- **THEN** the hint also says that the user enters the name with "Edit Login Data..." when a later refresh reports the error

#### Scenario: Other bank without a list

- **GIVEN** a bank on another FinTS server asks for a TAN medium and lists none
- **WHEN** the dialog opens
- **THEN** the dialog asks for the name of the TAN medium, and "Continue" stays disabled while the field is empty

### Requirement: Fetch a credit card through its card statement

The app SHALL fetch the transactions and the balance of a credit card from its card statement when the bank allows the card statement for the card and no transaction list.

#### Scenario: Card with only the card statement

- **GIVEN** the bank allows only the card statement for the credit card "Visa" with the card number 1234567890123456
- **AND** the card statement reports the debit 19,90 with the mark "D", booked on 09.11.2026 with the value date 08.11.2026, for "Streaming Beispiel" in "Musterstadt"
- **WHEN** the user refreshes "Visa" from 01.10.2026
- **THEN** the app asks the bank for the card statement of the card number 1234567890123456 from 01.10.2026
- **AND** the list shows -19,90 € with the name "Streaming Beispiel" and the purpose "Streaming Beispiel / Musterstadt", booked on 09.11.2026 with the value date 08.11.2026

#### Scenario: Card with the balance and the card statement

- **GIVEN** the bank allows the balance and the card statement for "Visa", and no transaction list
- **WHEN** the user refreshes "Visa"
- **THEN** the app fetches the card statement, which brings the balance and the transactions of "Visa"
- **AND** the account view does not say that the bank provides no transactions for this account

#### Scenario: Sign of a credit

- **WHEN** the card statement reports the amount 25,00 with the mark "C"
- **THEN** the list shows +25,00 €

#### Scenario: Balance of the card

- **WHEN** the card statement reports the balance 1.234,56 with the mark "D" on 12.11.2026
- **THEN** "Visa" shows the balance -1.234,56 € on 12.11.2026, the amount that the user owes on the card

#### Scenario: Balance in two parts of the answer

- **WHEN** the first part of the card statement reports the balance -80,10 € and the second part -95,00 €
- **THEN** "Visa" shows the balance -80,10 €

#### Scenario: Repeated fetch

- **GIVEN** "Visa" has the payment of -19,90 € from 09.11.2026 from the last refresh
- **WHEN** the next refresh brings the same payment again
- **THEN** the list shows the payment once

#### Scenario: Payment that is not final

- **GIVEN** the card statement reports a hotel reservation of -150,00 € as not final
- **WHEN** the refresh ends
- **THEN** the list shows the reservation as a pending transaction
- **AND** when a later refresh no longer reports the reservation, the list no longer shows it

#### Scenario: Reservation that gets booked

- **GIVEN** "Visa" shows the pending reservation of -150,00 € for "Hotel Beispiel" from 10.11.2026, with the comment "Trip", the category "Travel", and a checkmark
- **WHEN** the next refresh reports the same payment as final, booked on 12.11.2026
- **THEN** the list shows one transaction of -150,00 € for "Hotel Beispiel", booked on 12.11.2026 and no longer pending
- **AND** the transaction keeps the comment "Trip", the category "Travel", and the checkmark

#### Scenario: Original amount with three decimals

- **WHEN** the card statement reports a payment of -3,69 € with the original amount 1,234 Kuwaiti dinar
- **THEN** the list shows the payment with -3,69 €

#### Scenario: A row that does not read

- **GIVEN** the login "erika77" has the giro account "Giro" and the credit card "Visa"
- **WHEN** the card statement of "Visa" has a row without an amount
- **THEN** "Visa" fails with "The bank sent a card transaction that does not read, so nothing of this card was stored." and keeps its transactions
- **AND** "Giro" gets its balance and its transactions

### Requirement: Read the value of a securities account

The app SHALL fetch the value of a securities account through the custody account balance (HKWPD) in place of its balance and transactions when the bank allows it, and store it with the date of the statement as the value of the portfolio on that day. The value sums the totals of all pages of the statement, or the values and accrued interest of the holdings of a page without a total. When the app cannot read a value, the account says why.

#### Scenario: Value of a securities account

- **GIVEN** the bank offers the custody account balance for "Depot" and reports a total of 24.518,37 € on 12.11.2026
- **WHEN** the user refreshes "Depot"
- **THEN** "Depot" shows 24.518,37 €
- **AND** the value of "Depot" on 12.11.2026 is 24.518,37 €

#### Scenario: Empty securities account

- **GIVEN** "Depot" showed 24.518,37 € on 12.11.2026, and the user sold every holding
- **WHEN** the bank answers the custody account balance of "Depot" on 13.11.2026 without holdings and without a total
- **THEN** "Depot" shows 0,00 €
- **AND** the value of "Depot" on 13.11.2026 is 0,00 €

#### Scenario: Securities account with the balance only

- **GIVEN** the bank allows the balance for the securities account "Depot" and not the custody account balance
- **WHEN** the user refreshes "Depot"
- **THEN** the app fetches the balance of "Depot" as for any other account
- **AND** a securities account that allows both gets only the custody account balance

#### Scenario: Bank without the custody account balance

- **GIVEN** the bank lists the securities account "Fondsdepot" and allows neither the custody account balance, nor the balance, nor the transactions for it
- **WHEN** the user refreshes "Fondsdepot"
- **THEN** "Fondsdepot" shows "Moneten can't read this securities account at this bank yet."

#### Scenario: Answer without a value

- **GIVEN** the bank answers the custody account balance of "Depot" without a total, and its holdings have no value in one currency
- **WHEN** the refresh ends
- **THEN** "Depot" shows "The bank sent no value for this securities account."

#### Scenario: Note without a statement

- **GIVEN** "Depot" showed 24.518,37 € on 12.11.2026
- **WHEN** the bank answers the custody account balance of "Depot" with the note 3010 "Keine Einträge vorhanden" and without a statement
- **THEN** the error of "Depot" quotes "Keine Einträge vorhanden" and shows the code 3010
- **AND** "Depot" keeps 24.518,37 €

#### Scenario: Bank rejects the request

- **WHEN** the bank answers the custody account balance of "Depot" with the code 9160 and the text "Erforderliche Auftragsreferenz fehlt"
- **THEN** the error of "Depot" quotes "Erforderliche Auftragsreferenz fehlt" and shows the code 9160

#### Scenario: Consorsbank

- **GIVEN** a login at Consorsbank, whose bank parameters say that no order needs a TAN
- **WHEN** the app refreshes a giro account and a securities account of the login
- **THEN** the balance and the transactions go with HKTAN, and the custody account balance goes without HKTAN

#### Scenario: DAB BNP Paribas on the server of Consorsbank

- **GIVEN** a login at DAB BNP Paribas, whose FinTS server is brokerage-hbci.consorsbank.de
- **WHEN** the app refreshes a giro account and a securities account of the login
- **THEN** the balance and the transactions go with HKTAN, and the custody account balance goes without HKTAN

#### Scenario: Another server with a similar name

- **GIVEN** a login whose FinTS server is brokerage-hbci-other.consorsbank.de or brokerage-hbci.other.consorsbank.de
- **WHEN** the app refreshes a giro account and a securities account of the login
- **THEN** every order goes with or without HKTAN as the bank parameters say

### Requirement: Recognize a securities account by its jobs

The app SHALL treat an account as a securities account when the bank gives it the FinTS account type 30 to 39 or 60 to 69, or when the bank allows the custody account balance (HKWPD) or the turnover of the holdings (HKWDU) for it and neither the balance (HKSAL) nor the transactions (HKKAZ, HKCAZ). The jobs decide also when the bank gives the account no type or another type. The setup lists a securities account as a portfolio.

#### Scenario: Securities account without an account type

- **GIVEN** the bank lists "Depot" without an account type, allows the custody account balance (HKWPD) for it, and allows neither the balance (HKSAL) nor the transactions (HKKAZ, HKCAZ)
- **WHEN** the user adds the login
- **THEN** the setup lists "Depot" as a portfolio

#### Scenario: Securities account with another account type

- **GIVEN** the bank lists "Depot" with the account type 1 of a giro account and allows only the custody account balance (HKWPD) for it
- **WHEN** the user adds the login
- **THEN** the setup lists "Depot" as a portfolio

### Requirement: The value of a securities account makes a portfolio

The app SHALL make an account a portfolio when a refresh fetches the value of a securities account for it, whatever type the account had, also a type that the user chose.

#### Scenario: Securities account added with the wrong type

- **GIVEN** an earlier setup added "Depot" as an account of the type "Other", and the bank allows the custody account balance (HKWPD) for it and neither the balance (HKSAL) nor the transactions (HKKAZ, HKCAZ)
- **WHEN** the user refreshes "Depot"
- **THEN** the app fetches the custody account balance (HKWPD)
- **AND** "Depot" becomes a portfolio and shows its value of 24,518.37 EUR

### Requirement: One dialog for all accounts of a login

The app SHALL fetch all accounts of one login that are due in a refresh inside one FinTS dialog, so that the bank sees one login and asks for at most one TAN for that login.

#### Scenario: Three accounts, one login

- **GIVEN** "Giro", "Savings", and "Card" belong to the login "erika77"
- **WHEN** the user chooses "Refresh All Accounts" and the bank asks for a TAN at login
- **THEN** the user enters one TAN
- **AND** all three accounts are refreshed

### Requirement: Show notices of the bank

The app SHALL show a notice that the bank sends through FinTS, such as planned maintenance, in a window titled "Notice" with the name of the bank and the text of the bank when the refresh ends. A notice about one account also names the account and the code of the bank. Each notice is shown once until the app locks. A notice of an automatic refresh waits until a refresh that the user started ends or the main window comes forward.

#### Scenario: Maintenance announcement

- **GIVEN** the bank sends the notice "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"
- **WHEN** a refresh that the user started ends
- **THEN** the app shows the notice with the name of the bank
- **AND** the next refresh does not show the same notice again

#### Scenario: Notice of an automatic refresh

- **GIVEN** the main window is closed
- **WHEN** the automatic refresh at 03:00 ends with the notice "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"
- **THEN** no window opens
- **AND** the window "Notice" shows the notice when the user opens the main window at 08:00

#### Scenario: Notice before a failed login

- **GIVEN** the bank sends the notice "Wartungsarbeiten bis 5 Uhr" and then ends the login with the code 9800 and the text "Dialog abgebrochen"
- **WHEN** a refresh that the user started ends
- **THEN** the window "Notice" shows "Wartungsarbeiten bis 5 Uhr"
- **AND** the error of the account quotes "Dialog abgebrochen"

#### Scenario: Error about one account

- **GIVEN** the bank delivers the transactions of "Tagesgeld" and answers its balance request with the code 9210 and the text "Saldo nicht verfügbar"
- **WHEN** a refresh that the user started ends
- **THEN** the window "Notice" shows "Tagesgeld" with "Saldo nicht verfügbar" and the code 9210

#### Scenario: Notice in the setup

- **GIVEN** the assistant "Add Account" showed the notice "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr" after the login
- **WHEN** the first refresh after the setup ends with the same notice
- **THEN** no window "Notice" opens

#### Scenario: Notice before a failed login in the setup

- **GIVEN** the app has an access of Musterbank
- **AND** the bank sends the notice "Wartungsarbeiten bis 5 Uhr" and then ends the login of a new access in the assistant "Add Account" with the code 9800 and the text "Dialog abgebrochen"
- **WHEN** the user clicks "Next" in the login step
- **THEN** the login step shows the error with "Dialog abgebrochen"
- **AND** it shows "Wartungsarbeiten bis 5 Uhr" under "Notices of the bank"
- **AND** no window "Notice" opens when the next refresh of the access of Musterbank ends with the same notice

#### Scenario: Lock

- **GIVEN** the window "Notice" showed the notice "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"
- **WHEN** the user locks and unlocks the app, and a refresh that the user started ends with the same notice
- **THEN** the window "Notice" shows the notice once more

### Requirement: Show errors in the words of the bank

The app SHALL show the text and the return code that the bank sends when the bank rejects a request, name the bank and the account, and add its own explanation only as a separate sentence.

#### Scenario: Bank rejects a request

- **WHEN** the bank answers a transaction request with the code 9010 and the text "Verarbeitung nicht möglich"
- **THEN** the error of the account quotes "Verarbeitung nicht möglich" and shows the code 9010

#### Scenario: Code of the second factor without its cause

- **GIVEN** the last challenge of the refresh asked for a typed TAN, and the bank allows the user the TAN method "pushTAN 2.0"
- **WHEN** the bank answers with the code 9951 and the text "Zeitüberschreitung im Zwei-Schritt-Verfahren", or with the code 9955 and the text "Ein-Schritt-TAN-Verfahren nicht zugelassen"
- **THEN** the error of the account quotes the text of the bank and shows its code

#### Scenario: Warning with a successful answer

- **WHEN** the bank delivers the transactions together with a warning text
- **THEN** the transactions are stored
- **AND** the log contains the warning

### Requirement: Send a request to comdirect again when comdirect asks for it

The app SHALL send a request of a refresh to the FinTS server `fints.comdirect.de` a second time, once, in a dialog of its own, when comdirect answers it with a text that contains "Bitte senden Sie die Anfrage erneut" and the request needs no TAN. A request needs no TAN when the PIN/TAN parameters of the bank mark it so and it asks for no full history. Any other request, and a second answer with that text in an error, fails its account with the text of the bank.

#### Scenario: Second answer succeeds

- **GIVEN** a refresh of a comdirect account at `fints.comdirect.de`, whose bank parameters mark the transaction request as one without a TAN
- **WHEN** comdirect answers the transaction request with the code 9010 and the text "Bitte senden Sie die Anfrage erneut."
- **THEN** the app sends the request a second time
- **AND** the transactions of the second answer are stored, and the account shows no error

#### Scenario: Second answer is the same

- **GIVEN** a refresh of a comdirect account at `fints.comdirect.de`, whose bank parameters mark the transaction request as one without a TAN
- **WHEN** comdirect answers the transaction request twice with the code 9010 and the text "Bitte senden Sie die Anfrage erneut."
- **THEN** the app sends no third request
- **AND** the account fails with "Bitte senden Sie die Anfrage erneut." and the code 9010

#### Scenario: TAN for the login of the second dialog

- **GIVEN** the first refresh of the comdirect accounts "Girokonto" and "Tagesgeld" asks for the full history of "Girokonto", and comdirect asked to send the transaction request of "Tagesgeld" again
- **WHEN** comdirect asks for a photoTAN for the login of the second dialog
- **THEN** the dialog says that the TAN allows the login, and it does not offer to skip older transactions
- **AND** a cancel of the dialog ends the refresh of the access and starts no new one

#### Scenario: Request that needs a TAN

- **GIVEN** the first refresh of a comdirect account at `fints.comdirect.de`, which asks for the full history
- **WHEN** comdirect answers the transaction request with the code 9010 and the text "Bitte senden Sie die Anfrage erneut."
- **THEN** the app sends no second request and asks for no second TAN
- **AND** the account fails with "Bitte senden Sie die Anfrage erneut." and the code 9010

#### Scenario: Another bank

- **GIVEN** a refresh at the FinTS server of "Musterbank"
- **WHEN** the bank answers the transaction request with the text "Bitte senden Sie die Anfrage erneut."
- **THEN** the app sends no second request, and the account fails with that text

### Requirement: Keep the other accounts when the second request to comdirect fails

The app SHALL fail only the accounts with a request in the second dialog with comdirect when that dialog fails, and keep the answers of the first dialog for the other accounts of the refresh.

#### Scenario: Second dialog fails

- **GIVEN** a refresh of the comdirect accounts "Girokonto" and "Tagesgeld", in which comdirect asked to send the transaction request of "Girokonto" again
- **WHEN** the second dialog fails with the code 9800 and the text "Dialog abgebrochen"
- **THEN** "Girokonto" fails with "Dialog abgebrochen"
- **AND** "Tagesgeld" keeps the transactions of the first answer

### Requirement: Handle a PIN change that the bank requires

The app SHALL stop the dialog when the bank reports that the PIN must be changed, tell the user so, and name the ways to change it, which are the website of the bank and the PIN change assistant when the app has one.

#### Scenario: First login with a start PIN

- **WHEN** the bank answers the login with the request to change the PIN
- **THEN** the account shows that the server requires a PIN change and where to change it
- **AND** the app sends no further request with the old PIN

### Requirement: Handle a blocked access

The app SHALL stop when the bank reports that the PIN or the access is blocked, show the message of the bank, tell the user to ask the bank to unblock it, and not log in again for that access until the user starts a refresh by hand. When one code of the bank means a wrong PIN or a block, the app treats the answer as a block only when its text reports a block that happened and names no remaining attempts, no block to come, and no denial, and as a wrong PIN with the text of the bank otherwise.

#### Scenario: PIN blocked after wrong attempts

- **WHEN** the bank answers the login with the code 9930 and the text "PIN gesperrt"
- **THEN** the accounts of the access show that the bank blocked the access, the text "PIN gesperrt" with the code 9930, and "Ask the bank to unblock it."
- **AND** the app asks for no new PIN
- **AND** the automatic refresh skips this access from then on

#### Scenario: Warning of a blocked access in a login

- **GIVEN** a refresh of "Giro"
- **WHEN** the bank accepts the login with the code 0020 and the warning 3938 "Ihr Zugang ist vorläufig gesperrt - Bitte PIN-Sperre aufheben."
- **THEN** the app sends no request for "Giro" and the refresh fails
- **AND** "Giro" shows that the bank blocked the access, the text of the warning with the code 3938, and "Ask the bank to unblock it."

#### Scenario: Warning of a blocked access in the setup

- **GIVEN** the assistant "Add Account" logs in to "Musterbank"
- **WHEN** the bank accepts the login with the warning 3938 "Ihr Zugang ist vorläufig gesperrt - Bitte PIN-Sperre aufheben."
- **THEN** the assistant lists no accounts and shows that the bank blocked the access with "Ask the bank to unblock it."

#### Scenario: Block with the code of a failed login

- **WHEN** the bank answers the login with the code 9931 and the text "Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut"
- **THEN** the accounts of the access show that the bank blocked the access and "Ask the bank to unblock it."
- **AND** the app asks for no new PIN

#### Scenario: Wrong PIN with the code of a failed login

- **WHEN** the bank answers the login with the code 9931 and the text "Anmeldename oder PIN ist falsch"
- **THEN** the PIN sheet opens again with "Anmeldename oder PIN ist falsch"

#### Scenario: Warning of a block to come in an automatic refresh

- **GIVEN** the app has the PIN of "Musterbank" saved
- **WHEN** the automatic refresh logs in and the bank answers with the code 9931 and the text "PIN falsch. Weitere Fehlversuche führen zur Sperrung."
- **THEN** the app deletes the saved PIN and sends no second login
- **AND** the accounts of the access show that the bank did not accept the PIN, with "PIN falsch. Weitere Fehlversuche führen zur Sperrung."
- **AND** the automatic refresh sends no PIN for this access until the user starts a refresh
- **AND** the PIN sheet of the refresh that the user starts shows "PIN falsch. Weitere Fehlversuche führen zur Sperrung."

#### Scenario: Warning of a block to come in a manual refresh

- **WHEN** the bank answers the login with the code 9931 and the text "Weitere Fehlversuche führen zur Sperrung"
- **THEN** the PIN sheet opens again with "Weitere Fehlversuche führen zur Sperrung"

#### Scenario: Wrong PIN with a text that denies a block

- **WHEN** the bank answers the login with the code 9931 and the text "PIN falsch, Zugang nicht gesperrt"
- **THEN** the PIN sheet opens again with "PIN falsch, Zugang nicht gesperrt"

#### Scenario: Block with a text that also names a wrong PIN

- **WHEN** the bank answers the login with the code 9931 and the text "PIN ungültig - Zugang ist blockiert"
- **THEN** the accounts of the access show that the bank blocked the access and "Ask the bank to unblock it."
- **AND** the app asks for no new PIN

#### Scenario: Wrong PIN with a count of the attempts that remain before a block

- **WHEN** the bank answers the login with the code 9931 and the text "PIN falsch. Noch 1 Fehlversuch bis zur Sperrung."
- **THEN** the PIN sheet opens again with "PIN falsch. Noch 1 Fehlversuch bis zur Sperrung."

#### Scenario: Block with a text that names the unblock to come

- **WHEN** the bank answers the login with the code 9931 and the text "Zugang ist gesperrt und wird erst nach Freischaltung wieder nutzbar."
- **THEN** the accounts of the access show that the bank blocked the access and "Ask the bank to unblock it."
- **AND** the app asks for no new PIN

### Requirement: Say how to unblock the app at a savings bank

The app SHALL stop when a bank on the FinTS servers of the savings banks answers that the user deactivated the app ("Kundenprodukt" or "Kontozugriff" with "vom Benutzer deaktiviert"), and tell the user to unblock it under "Kontozugriffe" in the online banking. A bank is on these servers when its host label before ".de" starts with "s-fints-pt-" or is "s-hbci". The app forgets the PIN and asks for no new PIN until a refresh by hand.

#### Scenario: App deactivated in the online banking

- **GIVEN** a refresh of "Giro" at a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the bank answers the login with the code 9800 "Dialog abgebrochen" and the code 9010 "Kundenprodukt wurde vom Benutzer deaktiviert"
- **THEN** "Giro" shows that Moneten is blocked in the online banking of the Sparkasse, the text "Kundenprodukt wurde vom Benutzer deaktiviert" with the code 9010, and "Unblock Moneten there under “Service > Persönliche Einstellungen > Kontozugriffe”, then refresh the account."
- **AND** the app asks for no new PIN
- **AND** the automatic refresh skips this access until the user starts a refresh

#### Scenario: App deactivated during the setup

- **GIVEN** the assistant "Add Account" logs in to a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the bank answers the login with the code 9010 "Kundenprodukt wurde vom Benutzer deaktiviert"
- **THEN** the assistant lists no accounts and says where the user unblocks Moneten

#### Scenario: Card or TAN method blocked by the user

- **GIVEN** a refresh of "Giro" at a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the bank answers the login with the code 9942 "PIN falsch" and the code 9010 "pushTAN wurde vom Kunden deaktiviert"
- **THEN** the PIN sheet opens again with "PIN falsch"
- **AND** the app names no "Kontozugriffe"

#### Scenario: Same text from another bank

- **GIVEN** a refresh of "Giro" at "Musterbank" with the FinTS address "https://fints.musterbank.example/fints"
- **WHEN** the bank answers the login with the code 9010 "Kundenprodukt wurde vom Benutzer deaktiviert"
- **THEN** "Giro" shows the text of the bank with the code 9010 and no hint about "Kontozugriffe"

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
