# Design

## Context

The dialog "Two-Factor Authentication" exists since task 2.8 of [add-account-refresh](../add-account-refresh/design.md), with every `Challenge` case, the queue of one dialog at a time, the validity, and the approval in an app. Issue #86 adds the parts that tasks 4.1 to 4.4 of that change name: the change of the TAN method inside the dialog, the progress while a challenge is requested, the enlargement of an image, the size of the flicker code with the seizure warning, and the message for an invalid challenge. [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) applies.

## Decisions

### Change the method inside the dialog

`SecondFactorRequest` carries `methods`, the methods that the user can change to, and `method`, the method of the challenge. The dialog shows "TAN method" with a menu when `methods` is not empty. Choosing another method answers the request with `.tanMethod(id)` in place of a TAN.

The FinTS connector sends that answer as `{"type":"answer","id":…,"method":"…"}`, also for an approval in an app, which otherwise gets no answer. The helper cannot change the method of a running hbci4java dialog, so it ends the dialog and starts a new one with the passport of the run and the new method. The new dialog logs in again with the PIN of the run and requests a new challenge. Once the user changed the method, every further request of the old dialog ends it at once, so it asks the user nothing more. Before the new dialog starts, the helper ends the old dialog at the bank with HKEND, unless hbci4java ended it already, so that a challenge of the login does not stay pending there. The new method is saved in the state of the access ("Remember the TAN method").

### Progress after a choice

`TANMethod` carries `needsMedium` and `delivery`: what the bank sends with the method, an SMS code, a push notification, a QR code, or another TAN. The FinTS helper reads both from the bank parameters: `needtanmedia`, the type of the method in hbci4java (decoupled, QR code, photoTAN), and the words "push", "sms", and "mobile" in its names.

After the user chooses a method or a medium, `SessionBroker` keeps the dialog of the access open as `requesting` with a `ChallengeProgress`: "Getting list of TAN media..." for a method with a medium, and then "Requesting the SMS code...", "Requesting the push notification...", "Requesting the QR code...", or "Requesting the challenge of the bank...". The next request of the same access replaces it. When the access goes on to fetch or ends, the progress closes. While it shows, the dialogs of other accesses wait ("One dialog at a time"). "Cancel" stops the refresh of the access.

### Images and the flicker code

- A photoTAN image or a QR code has "Enlarge", which shows it at 400 points instead of 220, and the dialog grows with it. Command-plus and Command-minus do the same.
- `FlickerCodeSize` in `Sync` keeps the width of the flicker code in the settings, from 160 to 400 points in steps of 40, and 240 at first. "Larger" waits for the warning that flicker codes might cause epileptic seizures, and enlarges only after "Continue". The answer is kept, so the warning comes once.

### Invalid challenge

hbci4java leaves out the flicker code when the challenge data of the bank does not read. The helper keeps the challenge data that hbci4java removes before its callback. When a TAN request has challenge data but no flicker code, the helper fails the access with "The bank responded with an invalid challenge.", and so does the connector for a flicker code that does not read. `SyncFailure.invalidChallenge` carries it.

## Deviations from the spec

- The progress texts after a choice come from the bank parameters and from the names of the method. A method whose names say nothing shows "Requesting the challenge of the bank...".
- The restart of the dialog after a change of the method is tested up to the change in the self-test of the helper. The new dialog with a real bank is part of task 3.1 of add-account-refresh.
- The size of an enlarged image is not kept, because the spec asks only for the flicker code.
- An invalid challenge ends the refresh of the access. The dialog does not open.

## Risks / Trade-offs

- A change of the method costs a new login at the bank. Some banks count it as a new session.
