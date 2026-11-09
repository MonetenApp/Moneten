# Proposal: Use TAN generators with a cable or Bluetooth

## Why

A user who confirms with a chipTAN generator reads a code from the screen and types a TAN for every order. Generators with a USB cable or Bluetooth take the data from the app and send the TAN back. That removes both steps. The same dialogs also cover two setup tasks that banks demand through FinTS, the synchronization of a TAN generator and the activation of a pushTAN app.

## What Changes

- The TAN dialog offers the methods "chipTAN USB / Bluetooth" and "Sm@rtTAN USB / Bluetooth" when the bank offers a chipTAN or Sm@rtTAN method and a suitable device is connected.
- The app sends the challenge to the device, the user confirms on the device, and the app reads the TAN back.
- The user selects the device. A Bluetooth symbol opens diagnostic information.
- The app handles a TAN generator synchronization that the server requires, with the ATC of the card.
- The app handles a pushTAN activation that the server requires, with an activation code.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tan-handling`: adds requirements for TAN generators that are connected to the Mac, for the synchronization of a TAN generator, and for the activation of a pushTAN app. The change `add-tan-handling` introduces this capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `FinTSConnector` owns the device protocol and the two setup dialogs with the bank. `App` owns the device choice and the diagnostics.
- Depends on the change `add-tan-handling`.
- The app needs the Bluetooth permission of macOS for this feature only.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- Devices with Bluetooth or a USB cable can serve as TAN generators for the chipTAN and Sm@rtTAN methods. The flicker code data goes to the device and the TAN comes back (version history 2.2.3).
- The user selects "chipTAN USB / Bluetooth" or "Sm@rtTAN USB / Bluetooth" under "Confirm using". A small Bluetooth symbol next to the TAN generator menu shows diagnostic information (https://moneymoney.app/help/).
- Strings show "TAN generator", "Device", "USB cable", "Connecting to TAN generator...", the request to connect a USB or Bluetooth TAN generator, the request to turn on Bluetooth pairing on the device, the request to insert the card into the TAN generator, the request to confirm the data on the TAN generator, and errors for a failed Bluetooth connection, a missing TAN, a card that cannot generate TANs, and a firmware that is too old.
- The Bluetooth permission text of the app names card readers and TAN generators.
- Strings show "The server requires a TAN generator synchronization.", "Synchronizing TAN generator...", three instructions for reading the ATC, "Missing ATC.", and "Invalid ATC."
- Strings show "The server requires a pushTAN activation.", "Activation code", the instruction to scan the QR code from the registration letter with the pushTAN app, "Activating pushTAN app...", and "Missing activation code."
- A card reader that connects through Bluetooth works only as a TAN generator, not as a card reader (strings).

### Decided for MonetenMoneten

- The app asks for the Bluetooth permission only when the user first selects a Bluetooth device. When MoneyMoney asks was not observed.
- When the device does not answer within 60 seconds, the app offers the optical or manual variant of the method in the same dialog. MoneyMoney's fallback was not observed.
- The app remembers the selected device for each access. This was not observed.
