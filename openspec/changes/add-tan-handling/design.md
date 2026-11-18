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

- Image bytes come from the bank, from the FinTS helper, and from extensions, and the image decoders of macOS have had exploited memory bugs. So `ChallengeImage` checks the bytes where a connector creates it: a PNG or JPEG signature, at most 1 MB, and at most 2048 by 2048 pixels as the PNG header or the JPEG frame header states. It keeps no bytes that fail the check. Real photoTAN images and QR codes are a few kilobytes and a few hundred pixels wide, so the limits leave room. The dialog then decodes with ImageIO through `ChallengePicture` in `Sync`, which hints the checked type, allows only that type from macOS 27 on, rejects any other detected type, checks the dimensions again, and draws at most 2048 pixels on the long side. An image that fails a check shows "The bank sent an image that cannot be shown." under the text of the bank, and the TAN field stays.
- A photoTAN image or a QR code has "Enlarge", which shows it at 400 points instead of 220, and the dialog grows with it. Command-plus and Command-minus do the same.
- `FlickerCodeSize` in `Sync` keeps the width of the flicker code in the settings, from 160 to 400 points in steps of 40, and 240 at first. "Larger" waits for the warning that flicker codes might cause epileptic seizures, and enlarges only after "Continue". The answer is kept, so the warning comes once.

### Invalid challenge

hbci4java leaves out the flicker code when the challenge data of the bank does not read. The helper keeps the challenge data that hbci4java removes before its callback. When a TAN request has challenge data but no flicker code, the helper fails the access with "The bank responded with an invalid challenge.", and so does the connector for a flicker code that does not read. `SyncFailure.invalidChallenge` carries it.

### TAN length of Commerzbank and comdirect

The helper sends with each typed TAN request the code of its method (`current`) and the maximum TAN length that the bank parameters (HITANS) announce for it (`maxLength`). `CommerzbankGroup.tanField` in `Sources/FinTS` turns them into the `TANField` of the request: for the method 900 on a server of Commerzbank, 7 digits up to the announced length, which counts between 7 and 15, and 15 when the bank announces none; for the method 902 on the server of comdirect, 6 or 7 digits. Both fields are numeric, so a blank or another character never counts toward the length. The photoTAN app of Commerzbank shows 7 characters and the bank announces more, so the announced length alone would let a 6 character TAN through. Every other method keeps the field without a length, as before.

### TAN in capitals

Deutsche Bank, Postbank, and norisbank take a TAN with letters only in capitals. The connector gives the request of these hosts, `FinTSServer.isDeutscheBankGroup`, a `TANField` with `isUppercase`, so the field turns letters into capitals as the user types, as it does for an extension that asks for it. A numeric TAN is unchanged by it. Which methods of these banks send a TAN with letters is not recorded yet, so the bank test of issue #11 checks it.

### Security App of Oberbank

Oberbank (#236) approves the transactions of its internet banking with its Security App, as the page of the app (`https://www.oberbank.de/security-app`) says. The HBCI page of Oberbank (`https://www.oberbank.de/electronic-banking`) names only xTAN by SMS and the security file for finance software. A user who knows the Security App from the website looks for it among the TAN methods. `Oberbank.methods(_:bankCode:)` in `Sources/FinTS/Oberbank.swift` adds it to the choice of the TAN method as a `TANMethod` with `unavailable`, the reason "Oberbank offers the Security App only for its internet banking, not for finance software." The dialog then shows the methods of the server to choose and the Security App with its reason in a radio group, as it does for a method that an extension cannot use. The ID of the added method is no code of a bank, and the dialog never sends a method that cannot be chosen.

The rule follows the Bankleitzahl 70120700, because the server of Bank-Verlag serves many banks. It applies only when no method of the server is an app: a method that the bank parameters mark as an approval in an app ("push"), or whose name has a word that is "app" or ends with "app", with or without "tan" after it, such as "Security App", "SecurityApp", or "appTAN". A word that only starts with "app", such as "Appsecure", is not an app, because many words start with these letters and say nothing about an app. The line above the methods names the login, the download, or the order, as for every bank, so the text fits the step.

hbci4java asks for no choice when the server allows the user a single method, as with only xTAN by SMS: it takes that method by itself, and the first request of the helper is the TAN. So the helper sends with every challenge the methods that the server allows the user, also a single one, and the connector offers a change of the method only from two methods on. `Oberbank.note(_:bankCode:)` gives a typed TAN or a flicker code at 70120700, whose methods have no app, the reason of the Security App as `SecondFactorRequest.note`, and the dialog shows it under the purpose. The note comes also after a choice of the method, because the dialog of the TAN does not show the Security App. An approval in an app gets no note.

The bank test of issue #11 records the TAN methods that the server of Oberbank reports, with their names. If the Security App is among them, the rule never applies and can go.

## Deviations from the spec

- The progress texts after a choice come from the bank parameters and from the names of the method. A method whose names say nothing shows "Requesting the challenge of the bank...".
- The restart of the dialog after a change of the method is tested up to the change in the self-test of the helper. The new dialog with a real bank is part of task 3.1 of add-account-refresh.
- The size of an enlarged image is not kept, because the spec asks only for the flicker code.
- An invalid challenge ends the refresh of the access. The dialog does not open.

## Risks / Trade-offs

- A change of the method costs a new login at the bank. Some banks count it as a new session.
