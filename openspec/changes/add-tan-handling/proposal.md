# Proposal: Handle every TAN in one dialog

## Why

Banks ask for a second factor at login, for older transactions, and for every payment. Each bank names and runs its methods in its own way, and most problem reports about banking software come from this step. The user needs one dialog that always says what the TAN is for, which system asks, and what to do next.

## What Changes

- One dialog titled "Two-Factor Authentication" serves FinTS, extensions, and the subscription.
- The dialog states the purpose and the system that asks.
- The user chooses among the TAN methods that the bank reports. The app remembers the choice for each access.
- The dialog supports approval in an app without typing, manual TAN entry, photoTAN and QR codes as images, and the optical chipTAN flicker code.
- For an approval in an app the app waits and checks the result by itself.
- A wrong TAN, an approval that did not happen, and an expired challenge each lead to a clear message. The app never repeats an order by itself.

## Capabilities

### New Capabilities

- `tan-handling`: the dialog for two-factor authentication, the choice of the TAN method, and the handling of each kind of challenge.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #13
- Modules: `Domain` owns the challenge types that all connectors share. `App` owns the dialog. `FinTSConnector` and `ExtensionConnector` raise challenges and receive answers.
- Depends on the change `add-fints-banking`. The changes for payments reuse this dialog.
- The change `add-tan-generator-devices` adds TAN generators with a cable or Bluetooth.
- Decisions: [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md) forbids saving a TAN. The change `add-login-credentials` holds that requirement.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The TAN window shows for which purpose and for which system the TAN is requested. One bank can need two TAN entries when two systems are used, for example the FinTS server and the website (https://moneymoney.app/sca/).
- The window appears also when the bank already sent a push message or an SMS at login. It shows the purpose and lets the user change the TAN method (https://moneymoney.app/sca/).
- Strings show "Two-Factor Authentication", "Choose TAN method", "Getting list of TAN media...", "There are no available TAN methods.", "Missing TAN.", prompts to confirm the data in an app for the login or for the download of transactions, and messages for a TAN that the server did not accept and for an authorization that was not carried out.
- Strings show that canceling an approval asks whether the user canceled the authorization in the app first.
- Strings show the note that a TAN is used only for the login and not for a transfer.
- With methods that approve in an app, the app checks the status in the background and the window closes by itself (version history 2.4.12). With pushTAN 2.0 the app waits a few seconds before the first check (2.4.6).
- The last chosen TAN method is remembered (version history 2.3.14 and 2.4.48).
- The flicker code stops when the user starts to type the TAN (version history 2.2.8). Enlarging the flicker code shows a warning about epileptic seizures (strings).
- A QR code can be enlarged when the reader does not recognize it (version history 2.4.72).
- The website lists the supported methods, among them pushTAN, SecureGo plus, photoTAN, QR-TAN, chipTAN and Sm@rtTAN in the optical, QR, and manual variants, smsTAN, and mobileTAN (https://moneymoney.app/).
- Strings show errors for an invalid flicker code, QR code, or color matrix code from the bank, and hints to set up or activate a TAN method on the bank website first.
- Strings show progress texts for requesting a push notification, an SMS code, and a QR code, the request to scan a QR code in the app of the bank, and logins with a first and a second QR code.

### Decided for Moneten

- The first status check of an approval in an app happens 3 seconds after the dialog appears. Later checks follow the interval that the bank states, or 2 seconds when the bank states none. MoneyMoney says only "a few seconds".
- The dialog closes with a message when the challenge expires. The time comes from the bank, or is 5 minutes when the bank states none. This was not observed.
- Only one TAN dialog is open at a time. Further challenges wait. This was not observed.
- When the user changes the TAN method in the dialog, the app cancels the running challenge and requests a new one. This was not observed.
- A flicker code has a size control and remembers the size. A speed control was not observed and is not specified.
- An automatic refresh never opens the dialog. The change `add-account-refresh` specifies that.
- After a choice of a method or a medium the dialog says what it requests. The text follows the type and the names of the method in the bank parameters. MoneyMoney's rule was not observed.
- The flicker code has seven widths from 160 to 400 points, and 240 at first. The sizes of MoneyMoney were not observed.
- Command-plus and Command-minus enlarge and reduce an image or the flicker code. This was not observed.
