# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. "Debug app check" is the run of a debug build against `scripts/fake-fints-helper.sh` that pull request #85 records.

## 1. Requirements

- [x] 1.1 Assistant with three steps. Verified by the debug app check: "Add Account..." opens the bank step, "Next" leads to the login data and the accounts, and "Back" returns with the entry kept. The debug app check of issue #108 shows "Step 1 of 3: Bank" and "Step 2 of 3: Login data", the focus in the login name field after "Next", no focus after "Back", so a typed "oops" leaves the chosen bank as it was, and the login name kept after "Back" and "Next".
- [x] 1.2 Find the bank by name, IBAN, or Bankleitzahl. Verified by BankAccessTests "An IBAN with spaces and lower case letters names its Bankleitzahl..." and the debug app check, which shows "Musterbank" for "de02 1203 0000 0000 2020 51". The search by name is verified by BankDirectoryTests (parts of names, umlauts and accents, several words, ranking, FinTS banks first, short names such as "DKB", the start of a Bankleitzahl, no match), by BankLookupTests "A name lists the banks that match, and the chosen bank takes the place of the entry" and "The helper sends the bank directory once...", by FinTSConnectorTests "Reads the bank directory of the helper", by FinTSHelper self-test "bank directory with every bank", and by the debug app check of issue #108: "consors" lists both Consorsbank rows with place and Bankleitzahl, the down arrow and "Next" choose Nürnberg 76030080, and "munster" finds "Sparkasse Münsterland Muster".
- [x] 1.3 Check the IBAN before any connection. Verified by BankAccessTests "A wrong entry names the failed check before any bank is contacted".
- [ ] 1.4 Check the Bankleitzahl. Built in part: an unknown Bankleitzahl says that it is invalid. The bank directory marks no outdated Bankleitzahl.
- [ ] 1.5 Country menu. Not built.
- [ ] 1.6 Other services. Built in part: "Other" lists "Offline account / Cash", which asks for the name and the currency. The services of extensions come with E6.
- [ ] 1.7 Choose the access method. Not built until a second method exists (E6).
- [ ] 1.8 Explain why a bank cannot be added. Built in part: a bank without a FinTS address names the bank and says that an extension can add support, verified by the debug app check. The subscription comes later.
- [ ] 1.9 Ask for the login data in the words of the bank. Built in part: the label and a help line of the login name for Consorsbank, DKB, comdirect, ING, and the savings banks, from a public page of each bank, verified by LoginHintTests and by the debug app check of issue #108, which shows "Account number + 001" for Consorsbank and "Login name or Legitimations-ID" for a savings bank. Every other bank asks for "User ID". The five banks ask to leave the customer ID empty, so the step has no customer ID field.
- [ ] 1.10 Check the format of login fields. Not built.
- [ ] 1.11 Show what the bank requires before the first login. Not built.
- [x] 1.12 Report a failed login without leaving the assistant. Verified by SetupSessionTests "A rejected PIN ends the login with the message of the bank and opens no sheet" and the debug app check, which shows the message of the bank with an empty PIN field and the user ID kept. The text that also names the user ID and the hint of the bank is verified by SyncModelTests "At the first login of a setup a rejected PIN also names the user ID..." and by the debug app check of issue #108 with PIN 0000, for a savings bank with its hint and for Musterbank without one. Two "Next" commands during a login start one login and one TAN dialog, verified by the debug app check. A failed save keeps the assistant open with the error, verified by the debug app check with a removed group.
- [ ] 1.13 Progress and cancel during setup. Built: "Setting up Accounts...", a TAN dialog on top of the assistant, and "Cancel" at any step, verified by SetupSessionTests "Canceling the TAN dialog ends the login" and the debug app check. The current step of the bank dialog is not shown.
- [x] 1.14 Select the accounts to add. Verified by the debug app check: three listed accounts, all selected, and "Done" disabled without a selection. The message for a login without accounts is built.
- [x] 1.15 Do not add an account twice, and tell the accounts of a bank apart. Verified by BankAccessTests "The setup adds only new accounts...", "A migrated account takes over the access...", "Of the migrated accounts with the IBAN, the setup connects the open one in the same currency", and "Several open migrated accounts with the IBAN are a choice...", "A subaccount with the same account number is new...", "A migrated account without a subnumber is a choice...", and "An account with another IBAN is new...", by SyncCoordinatorTests "The login of a setup waits for the refresh of its access..." and "Cancel Refresh drops a refresh that waits for the login of a setup", by AccessStoreTests "A second setup of the same login adds its accounts to the access that exists..." and "A setup of a known login never rolls back the state of a refresh...", and by the debug app check, which shows all three accounts as present on a second setup and keeps one access.
- [x] 1.16 Finish the setup. Verified by the debug app check: the accounts appear with the names of the bank, the first new account is selected also when the setup connected a migrated account before it, and the first refresh fetches them. Opened for the group "Private", the new accounts go into "Private".
- [ ] 1.17 Look for new accounts. Not built.
- [ ] 1.18 Edit the login data of an access. Not built.
- [ ] 1.19 Switch the access method and keep the history. Not built.
- [ ] 1.20 Reinitialize an access after an aborted authentication. Not built.
- [ ] 1.21 List of supported banks. Not built.

## 2. Integration

- [ ] 2.1 Add a bank with pushTAN in a release build and record the result in the pull request.
