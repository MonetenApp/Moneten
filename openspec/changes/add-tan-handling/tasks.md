# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. "Debug app check" is the run of a debug build against `scripts/fake-fints-helper.sh` and the requests of `SyncDemo`, which pull request #86 records with light and dark screenshots. Every scenario also needs the check with real banks of task 3.1 of add-account-refresh.

## 1. Requirements

- [ ] 1.1 One dialog for every source. Built for FinTS, verified by FinTSConnectorTests "Asks for the TAN method, the TAN medium, and TANs with a flicker code or an image" and the debug app check. Extensions come with E6.
- [x] 1.2 State the purpose and the system. Verified by the debug app check, which shows "The FinTS server of “Musterbank” needs a confirmation to allow the download of transactions." and "... to allow the login.", and the website for the QR code that is confirmed in an app.
- [ ] 1.3 Mark a TAN that covers only the login. Built in the dialog and shown by the `SyncDemo` request "order". Orders come with v0.2.
- [x] 1.4 Choose the TAN method. Verified by FinTSConnectorTests "Asks for the TAN method, the TAN medium, and TANs..." and the debug app check of "Choose TAN method". One method shows as its name without a menu.
- [ ] 1.5 Remember the TAN method. Built: the state of the access keeps the method, and hbci4java asks again when the bank no longer offers it. Check with a real bank.
- [x] 1.6 Change the method inside the dialog. Verified by TANDialogTests "Choosing another method while the dialog waits for an approval answers with that method and requests its challenge", FinTSConnectorTests "Offers the other TAN methods in the dialog of a challenge, and sends the method that the user changes to", FinTSHelper self-test "an answer with a method changes the method", "a method chosen while the approval waits", "no request after a change of the method", "a connection after a change of the method, for the end of the old dialog", "the dialog that the bank keeps open after a change of the method", and "a dialog that hbci4java ended", and the debug app check, in which the TAN dialog of "Add Account" changes from "pushTAN" to "mobileTAN".
- [ ] 1.7 No usable TAN method. Not built.
- [x] 1.8 Choose the TAN medium. Verified by TANDialogTests "After a method with media the dialog gets the list of TAN media, and after the medium it requests the SMS code" and the debug app check of "Getting list of TAN media...", and the menu with "Handy privat" and "Handy Firma".
- [x] 1.9 Show the challenge of the bank. Verified by FinTSConnectorTests, which pass the prompt of the helper unchanged, and the debug app check of "Bitte geben Sie die TAN für den Auftrag vom 09.11.2026 ein".
- [x] 1.10 Manual TAN entry. Verified by FinTSConnectorTests "Asks for the TAN method, the TAN medium, and TANs...", which send the TAN once, and the debug app check, in which "Continue" is disabled while the field is empty.
- [x] 1.11 Approval in an app without typing. Verified by SyncCoordinatorTests "The approval dialog closes when the connector withdraws its request" and FinTSConnectorTests "Keeps an approval in the app open until the helper withdraws it".
- [ ] 1.12 Timing of the approval check. hbci4java checks the approval with the waiting times of the bank parameters. Not verified.
- [ ] 1.13 Cancel a pending approval. Built: "Cancel" asks whether the user canceled the authorization in the app, and "Yes" stops the refresh, verified by SyncCoordinatorTests "Canceling a waiting approval stops the refresh" and FinTSConnectorTests "Cancels the refresh when the user cancels the approval". The question itself is not verified.
- [ ] 1.14 Approval that did not happen. Built: `SyncFailure.approvalDeclined` with its message. The answer of hbci4java for a declined approval is not mapped yet.
- [x] 1.15 Image challenges. Verified by FinTSConnectorTests "Asks for the TAN method, the TAN medium, and TANs with a flicker code or an image" and the debug app check, in which "Enlarge" shows the code at 400 points and the dialog grows with it.
- [ ] 1.16 QR code that is confirmed in an app. Built in the dialog, with "Code 2 of 2" and "Enlarge", shown by the debug app check. The FinTS helper sends no image with an approval yet.
- [x] 1.17 Progress while a challenge is requested. Verified by TANDialogTests "After a method with media the dialog gets the list of TAN media, and after the medium it requests the SMS code", "While the progress of one access shows, the dialog of another waits...", "The progress that the access reports before its first account keeps the dialog open until the new challenge", and "The progress ends with the refresh of its access...", SetupSessionTests "A login that fails after the choice of a TAN method closes the progress of the dialog", FinTSHelper self-test "TAN methods with their medium and what the bank sends", and the debug app check of "Requesting the SMS code...".
- [x] 1.18 Optical chipTAN with a flicker code. Verified by FinTSConnectorTests "A flicker code that does not read fails the access with an invalid challenge and opens no dialog", FinTSHelper self-test "challenge data without a flicker code", SyncModelTests "A flicker code starts with the sync pattern...", and the debug app check of the flicker code with its marks.
- [x] 1.19 Flicker code size. Verified by FlickerCodeSizeTests "The first enlargement waits for the warning...", "The next flicker code has the size of the last one...", and "The size stays between 160 and 400", and the debug app check of the warning and of a flicker code at 320 points.
- [ ] 1.20 Flicker code stops while typing. Built: the animation runs only while the TAN field is empty. Not verified.
- [ ] 1.21 Manual chipTAN. Built: the dialog shows the text of the bank with the start code and a TAN field. Check with a real bank.
- [ ] 1.22 Wrong TAN. Built: `SyncFailure.tanRejected` says "The bank did not accept the entered TAN", verified by SyncModelTests "Each failure says what the user can do". The code of the bank for a wrong TAN is not mapped yet.
- [x] 1.23 Expired challenge. Verified by SyncCoordinatorTests "A challenge expires after its validity" and "The validity starts when the dialog opens".
- [ ] 1.24 The dialog appears even when the bank already sent a code. Built: every challenge of hbci4java opens the dialog. Check with a real bank.
- [ ] 1.25 Separate dialogs for separate systems. Built in the queue of `SessionBroker`. A second system comes with E6.
- [x] 1.26 One dialog at a time. Verified by SyncCoordinatorTests "Two accesses that ask at the same time get one dialog after the other" and TANDialogTests "While the progress of one access shows, the dialog of another waits...".
- [x] 1.27 Cancel the dialog. Verified by SyncCoordinatorTests "Canceling the dialog stops only its access".
- [ ] 1.28 No dialog when no TAN is needed. Built by hbci4java, which asks only when the bank sends a challenge. Check with a real bank.

## 2. Build

- [x] 2.1 `Domain`: `SecondFactorRequest.methods` and `method`, `TANMethod.needsMedium` and `delivery`, `ChallengeProgress`, and `SyncFailure.invalidChallenge`.
- [x] 2.2 `Sync`: the progress after a choice in `SessionBroker`, and `FlickerCodeSize`.
- [x] 2.3 `FinTS`: the answer with a method, the new dialog of the helper, the details of each method, and the invalid challenge.
- [x] 2.4 `App`: the menu of the method, the progress sheet, "Enlarge", and the size of the flicker code with the warning.

## Workflow follow-up

- Archive the change with `openspec archive add-tan-handling` when every task is checked.
