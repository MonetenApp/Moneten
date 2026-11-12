# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. "Debug app check" is the run of a debug build against `scripts/fake-fints-helper.sh` that pull request #85 records.

## 1. Requirements

- [x] 1.1 Assistant with three steps. Verified by the debug app check: "Add Account..." opens the bank step, "Next" leads to the login data and the accounts, and "Back" returns with the entry kept.
- [x] 1.2 Find the bank by IBAN or Bankleitzahl. Verified by BankAccessTests "An IBAN with spaces and lower case letters names its Bankleitzahl..." and the debug app check, which shows "Musterbank" for "de02 1203 0000 0000 2020 51".
- [x] 1.3 Check the IBAN before any connection. Verified by BankAccessTests "A wrong entry names the failed check before any bank is contacted".
- [ ] 1.4 Check the Bankleitzahl. Built in part: an unknown Bankleitzahl says that it is invalid. The bank directory marks no outdated Bankleitzahl.
- [ ] 1.5 Country menu. Not built.
- [ ] 1.6 Other services. Built in part: "Other" lists "Offline account / Cash", which asks for the name and the currency. The services of extensions come with E6.
- [ ] 1.7 Choose the access method. Not built until a second method exists (E6).
- [ ] 1.8 Explain why a bank cannot be added. Built in part: a bank without a FinTS address names the bank and says that an extension can add support, verified by the debug app check. The subscription comes later.
- [ ] 1.9 Ask for the login data in the words of the bank. Built in part: "User ID" and "PIN". The bank directory holds no field names.
- [ ] 1.10 Check the format of login fields. Not built.
- [ ] 1.11 Show what the bank requires before the first login. Not built.
- [x] 1.12 Report a failed login without leaving the assistant. Verified by SetupSessionTests "A rejected PIN ends the login with the message of the bank and opens no sheet" and the debug app check, which shows the message of the bank with an empty PIN field and the user ID kept.
- [ ] 1.13 Progress and cancel during setup. Built: "Setting up Accounts...", a TAN dialog on top of the assistant, and "Cancel" at any step, verified by SetupSessionTests "Canceling the TAN dialog ends the login" and the debug app check. The current step of the bank dialog is not shown.
- [x] 1.14 Select the accounts to add. Verified by the debug app check: three listed accounts, all selected, and "Done" disabled without a selection. The message for a login without accounts is built.
- [x] 1.15 Do not add an account twice. Verified by BankAccessTests "The setup adds only new accounts..." and "A migrated account takes over the access...", and by the debug app check, which shows all three accounts as present on a second setup.
- [x] 1.16 Finish the setup. Verified by the debug app check: the accounts appear with the names of the bank, the first is selected, and the first refresh fetches them. Opened for the group "Private", the new accounts go into "Private".
- [ ] 1.17 Look for new accounts. Not built.
- [ ] 1.18 Edit the login data of an access. Not built.
- [ ] 1.19 Switch the access method and keep the history. Not built.
- [ ] 1.20 Reinitialize an access after an aborted authentication. Not built.
- [ ] 1.21 List of supported banks. Not built.

## 2. Integration

- [ ] 2.1 Add a bank with pushTAN in a release build and record the result in the pull request.
