# Proposal: Access banks with HBCI key files and chip cards

## Why

Some banks, and many business accounts, offer the classic HBCI access with a key file or a chip card next to PIN and TAN. With a key, the user never types a TAN, not for a login and not for a payment. A few banks offer payments to banking software only this way. Users who own such a key expect a Mac banking app to use it.

## What Changes

- The account setup offers the access methods "HBCI keyfile" and "HBCI chipcard" for banks that support them.
- The app creates a new key file or uses an existing one, also from other programs.
- At first contact the app shows the key of the bank with its hash value for comparison, sends the user's key, and prints an INI letter. The setup pauses until the bank activates the key.
- The app works with chip cards in card readers. The PIN is entered on the keypad of the reader.
- The Tools menu gets "Change PIN of Chipcard...", "Unblock Chipcard with PUK...", and "Change Password of Keyfile...".
- With a Secoder reader the payment data is shown on the reader for confirmation. A setting turns this off.
- No TAN is needed with a key file or a chip card.

## Capabilities

### New Capabilities

- `hbci-keys-and-chipcards`: bank access with a key file or a chip card, the setup of the keys, and the tools for cards and key files.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `FinTSConnector` owns keys, cards, readers, and the signed dialogs. `App` owns the setup steps, the Tools commands, and the setting.
- Depends on the changes `add-account-setup`, `add-fints-banking`, and `add-login-credentials`. Payment confirmation on a reader takes effect with the change `add-sepa-transfers`.
- Card readers with Bluetooth need the Bluetooth permission of macOS.
- Decisions: [ADR 0003](../../../docs/decisions/0003-fints-through-hbci4swift.md). The library decides which security profiles are possible.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- With an HBCI chip card or key file no TAN entry is ever needed. "Edit Login Data" switches between the access methods that a bank offers (https://moneymoney.app/sca/).
- When the bank key is not yet known, the app shows it for confirmation, and the user can compare its hash value with the records of the bank or reject the connection (https://moneymoney.app/security/).
- Strings show the setup with "Create new keyfile" and "Use existing keyfile", the folder choice with the advice to use an external medium, a user name and a password for the key file, the progress texts for generating and submitting keys, "Verify Bank Key", the INI letter with hash values that is printed and sent by mail or entered on the bank website, and "The account setup can be continued once your bank activated the HBCI key from the INI letter." with "Continue Account Setup...".
- Key files from common Windows programs can be taken over. An old key should be blocked at the bank before a new one is created (https://moneymoney.app/help/).
- Strings show messages for a file that is no valid key file, for a format that cannot be read, for a security profile that the bank does not support, and for a key file or card that is not the one the account was set up with.
- The Tools menu has "Change PIN of Chipcard...", "Unblock Chipcard with PUK...", and "Change Password of Keyfile...". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- Strings show the reader choice, the requests to connect a reader and to insert the card, PIN entry on the keypad of the reader, the warnings about one or two remaining attempts, a card without a PIN, the transport PIN with 5 digits, the PUK with 8 digits, an immutable PIN, memory slots on a card, and messages for cards that are unsupported, locked, or worn out.
- Card readers with a USB cable work through the driver of the operating system. One reader model is supported through Bluetooth. A Bluetooth symbol next to the reader menu shows diagnostic information (https://moneymoney.app/help/).
- The setting "Enable Secoder visualization" lets the user confirm a transfer on the display of the reader when the bank supports it. Otherwise the classic method is used. See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- A key file can be used by a background refresh and a payment at the same time (version history 2.4.37). After a payment with a card or key file the account is refreshed (2.4.8).

### Decided for Moneten

- The app supports the security profiles RAH-9 and RAH-10 for key files and cards, and DDV cards, as far as the FinTS library does. Older RDH profiles are supported for existing key files only when the library reads them. MoneyMoney supports more formats.
- The password of a key file follows the rules of the change `add-login-credentials`. It is saved only on request.
- An automatic refresh skips an access with a chip card when the card is not in the reader or a PIN entry is needed, and marks the accounts. MoneyMoney's behavior was not observed.
- When a key file is not reachable, for example because its USB stick is not connected, the app asks for the medium in a manual refresh and skips the access in an automatic refresh. This was not observed.
- Reader diagnostics are part of the app. MoneyMoney links to a separate diagnostic app.
- An accepted bank key is remembered for the access. A different bank key later leads to a new confirmation. This was not observed.
