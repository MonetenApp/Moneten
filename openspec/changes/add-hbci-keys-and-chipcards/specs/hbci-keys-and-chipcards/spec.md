# Spec Delta

## Purpose

Some banks accept a signature key in place of PIN and TAN. The key lives in a key file or on a chip card. This capability defines the bank access with such a key, the setup of the keys with the bank, and the tools for key files, chip cards, and card readers.

## ADDED Requirements

### Requirement: Access methods for key files and chip cards

The app SHALL offer the access methods "HBCI keyfile" and "HBCI chipcard" in the account setup and in "Edit Login Data..." for a bank whose directory entry lists them.

#### Scenario: Bank with key file access

- **GIVEN** "Musterbank" offers FinTS with a TAN method and with a key file
- **WHEN** the user enters the Bankleitzahl of "Musterbank" in the account setup
- **THEN** "Access with" lists "FinTS/HBCI with TAN method" and "HBCI keyfile"

#### Scenario: Bank with key access only

- **GIVEN** "Beispielbank" offers FinTS only with a key file or a chip card
- **WHEN** the user enters its Bankleitzahl
- **THEN** the app says that this bank provides a FinTS server only with a key file or a chip card and offers both methods

### Requirement: Create a new key file

The app SHALL create a new key file when the user selects "Create new keyfile". The user chooses a folder, enters the user ID that the bank assigned, and sets a password for the file by entering it twice. The app advises the user to store the file on an external medium, and it rejects a folder that it cannot write to.

#### Scenario: New key file on a USB stick

- **WHEN** the user chooses a folder on a USB stick, enters the user ID "67890123", and enters the password twice
- **THEN** the app shows that it generates the key and asks for patience
- **AND** a key file exists in the chosen folder

#### Scenario: Write-protected folder

- **WHEN** the user chooses a folder that is write-protected
- **THEN** the app says that the folder is write-protected and asks for another location

### Requirement: Use an existing key file

The app SHALL use an existing key file when the user selects "Use existing keyfile", chooses the file, and enters its password. The app reads key files that it created and key files of other banking programs in the supported formats.

#### Scenario: Key file from another program

- **GIVEN** a key file in a supported format that another banking program created
- **WHEN** the user chooses the file and enters its password
- **THEN** the setup continues with the first contact to the bank

#### Scenario: Not a key file

- **WHEN** the user chooses a file that is not a key file or is damaged
- **THEN** the app says that the file is not a valid key file or is not in a supported format

#### Scenario: Wrong password

- **WHEN** the user enters a wrong password for the key file
- **THEN** the app says that the password is wrong and does not contact the bank

### Requirement: Supported security profiles

The app SHALL work with key files and chip cards of the security profiles RAH-9 and RAH-10 and with DDV chip cards. When the bank does not accept the profile of a key file or card, the app names the profile and says that the bank does not support it.

#### Scenario: Profile not accepted by the bank

- **GIVEN** a key file with the profile RAH-9 and a bank that accepts only RAH-10
- **WHEN** the app contacts the bank
- **THEN** the app says that the security profile RAH-9 of this key file is not supported by this bank

### Requirement: Verify the key of the bank

The app SHALL show the key of the bank with its hash value in a sheet "Verify Bank Key" when it sees that key for the first time, and tell the user to compare the hash value with the records of the bank. The user chooses "Accept" or "Reject". The app sends no data that needs the key before the user accepts.

#### Scenario: Accept

- **WHEN** the user compares the hash value with the letter of the bank and clicks "Accept"
- **THEN** the setup continues
- **AND** the app does not ask again for this bank key

#### Scenario: Reject

- **WHEN** the user clicks "Reject"
- **THEN** the app ends the connection and the setup stops with the note that the bank key was not accepted

#### Scenario: Bank key changed

- **GIVEN** the user accepted the key of "Musterbank" last year
- **WHEN** the bank presents another key
- **THEN** the sheet appears again with the new hash value

### Requirement: Send the user key and print the INI letter

The app SHALL send the public key of a new key file or card to the bank and then offer "Print INI Letter...". The letter contains the bank, the user ID, the date, the key number, the key version, and the hash value of the user key. The app also shows the hash value on screen for banks that accept it on their website.

#### Scenario: Print

- **WHEN** the app sent the new key and the user chooses "Print INI Letter..."
- **THEN** the print dialog opens with a letter that contains the user ID "67890123" and the hash value of the key

#### Scenario: Hash value for the website

- **WHEN** the user wants to enter the hash value on the website of the bank
- **THEN** the same sheet shows the hash value as text that can be copied

### Requirement: Setup pauses until the bank activates the key

The app SHALL keep an unfinished access in the sidebar after the INI letter step, with the text that the setup can continue once the bank activated the key. "Continue Account Setup..." on that entry contacts the bank again and, when the key is active, shows the account selection.

#### Scenario: Key not yet active

- **GIVEN** the user printed the INI letter yesterday
- **WHEN** the user chooses "Continue Account Setup..." and the bank has not activated the key
- **THEN** the app says that the bank has not activated the key yet and the entry stays

#### Scenario: Key active

- **WHEN** the user chooses "Continue Account Setup..." after the bank activated the key
- **THEN** the assistant shows the accounts of the login for selection

### Requirement: No TAN with a key

The app SHALL sign every login and every order of an access with a key file or chip card with that key, and it SHALL open no TAN dialog for such an access.

#### Scenario: Refresh with a key file

- **GIVEN** an access with a key file whose password is available
- **WHEN** the user refreshes its accounts
- **THEN** the refresh completes and no dialog for two-factor authentication appears

#### Scenario: Order with a key file

- **WHEN** the user sends an order from an account with a key file access
- **THEN** the app says that no TAN is required and asks only for the confirmation to send

### Requirement: Key file must be reachable

The app SHALL ask the user to connect the medium or to choose the folder again when it cannot read the key file of an access during a manual refresh. An automatic refresh skips the access and marks its accounts.

#### Scenario: USB stick not connected

- **GIVEN** the key file of "Business" lies on a USB stick that is not connected
- **WHEN** the user refreshes "Business"
- **THEN** the app asks for the folder of the key file
- **AND** the refresh continues after the user connects the stick and chooses the folder

#### Scenario: Other key file

- **WHEN** the user chooses a key file that is not the one the access was set up with
- **THEN** the app says so and names "Edit Login Data..." as the way to switch the access to this key file

### Requirement: One key, several tasks

The app SHALL let a refresh and an order use the same key file or card one after the other without an error when both start at the same time.

#### Scenario: Refresh in the background, order in front

- **GIVEN** an automatic refresh of "Business" is running with the key file
- **WHEN** the user sends an order from "Business"
- **THEN** both complete and neither reports that the key is in use

### Requirement: Change the password of a key file

The app SHALL offer "Change Password of Keyfile..." in the Tools menu. The user selects the access, enters the current password and the new password twice, and the app writes the file with the new password. The new password must differ from the old one.

#### Scenario: Password changed

- **WHEN** the user enters the current password and a new password twice
- **THEN** the app says that the password has been changed
- **AND** the next refresh needs the new password

#### Scenario: Format cannot be rewritten

- **GIVEN** a key file in a format that the app can read and not write
- **WHEN** the user chooses the command for that file
- **THEN** the app says that the password of this key file cannot be changed with the app

### Requirement: Choose the card reader

The app SHALL list the connected card readers under "Chipcard reader" and remember the selected reader. When no reader is connected, it asks the user to connect one. When the reader holds no card, it asks the user to insert the HBCI chip card.

#### Scenario: Two readers

- **GIVEN** two card readers are connected by USB cable
- **WHEN** the setup for "HBCI chipcard" opens
- **THEN** the menu lists both readers by name

#### Scenario: No card

- **WHEN** the selected reader holds no card
- **THEN** the app asks the user to insert the HBCI chip card into the card reader

### Requirement: PIN entry on the keypad of the reader

The app SHALL ask the user to enter the card PIN on the keypad of the card reader when the reader has a keypad, and it SHALL never ask for that PIN on the Mac keyboard for such a reader. The app reports a canceled entry, a timeout, and a wrong PIN.

#### Scenario: PIN on the keypad

- **WHEN** a refresh needs the card
- **THEN** the app shows the request to enter the PIN on the keypad of the card reader and no PIN field

#### Scenario: Entry timed out

- **WHEN** the user enters nothing until the reader gives up
- **THEN** the app says that the PIN entry timed out and the refresh of that access ends

### Requirement: Warn about remaining PIN attempts

The app SHALL warn before a PIN entry when the card reports that only two attempts or one attempt remain before the card locks.

#### Scenario: One attempt left

- **GIVEN** the card reports one remaining attempt
- **WHEN** the app needs the PIN
- **THEN** the app says that the user has one attempt before the chip card becomes locked and asks whether to continue

### Requirement: Change the PIN of a chip card

The app SHALL offer "Change PIN of Chipcard..." in the Tools menu. The user enters the current PIN and then the new PIN twice on the keypad of the reader. A card with a transport PIN or with no PIN leads to the same step with the matching instruction.

#### Scenario: PIN changed

- **WHEN** the user enters the current PIN and the new PIN twice on the keypad
- **THEN** the app says that the PIN has been changed

#### Scenario: New card with a transport PIN

- **GIVEN** a new card with a transport PIN of 5 digits
- **WHEN** the app first uses the card
- **THEN** the app asks the user to change the transport PIN and says that it has 5 digits

#### Scenario: Immutable PIN

- **WHEN** the card does not allow a PIN change
- **THEN** the app says that the PIN of this chip card is immutable

### Requirement: Unblock a chip card with the PUK

The app SHALL offer "Unblock Chipcard with PUK..." in the Tools menu. The user enters the PUK and then a new PIN twice on the keypad of the reader. The app says that the PUK has 8 digits, and it reports a wrong PUK and a card that cannot be unblocked.

#### Scenario: Unblocked

- **WHEN** the user enters the right PUK and a new PIN twice
- **THEN** the app says that the chip card has been unblocked

#### Scenario: Wrong PUK

- **WHEN** the user enters a wrong PUK
- **THEN** the app says that the PUK is wrong and does not ask for a new PIN

### Requirement: Memory slots on a chip card

The app SHALL show the memory slots of a chip card that holds keys for several banks, with the bank and user ID of each slot, and let the user select the slot for the access. Writing new keys into a used slot needs the explicit choice to overwrite the slot and to submit new keys to the bank.

#### Scenario: Card with two slots

- **GIVEN** a card with keys for "Musterbank" in slot 1 and an empty slot 2
- **WHEN** the user opens "Memory slots..." during setup
- **THEN** the app lists slot 1 with "Musterbank" and slot 2 as empty

#### Scenario: Overwrite

- **WHEN** the user selects the used slot 1 for a new key
- **THEN** the app continues only after the user turned on the option to overwrite the slot and submit new keys to the bank

### Requirement: Cards that cannot be used

The app SHALL say why a card cannot be used when the card is not an HBCI chip card, is not the card that the access was set up with, is permanently write-protected, or has reached the end of its signature counter. For a card that must be replaced, it says so.

#### Scenario: Wrong card

- **WHEN** the user inserts a card of another bank
- **THEN** the app says that this is not the chip card that was used to set up the account and names "Edit Login Data..." as the way to switch

#### Scenario: Health insurance card

- **WHEN** the user inserts a card that is not an HBCI chip card
- **THEN** the app says that the inserted card is not an HBCI chip card or is unsupported

### Requirement: Card reader connection and diagnostics

The app SHALL work with card readers that macOS supports through a USB cable, and with supported readers through Bluetooth. A Bluetooth symbol next to the reader menu shows diagnostic information, which is the state of the card service of macOS, the readers found, and for Bluetooth the pairing state. When the card service is not running, the app says that a current driver for the reader is needed.

#### Scenario: Driver missing

- **WHEN** the card service of macOS does not run
- **THEN** the app says so and advises the user to install the latest driver of the reader and to restart the Mac

#### Scenario: Reader works only by cable

- **WHEN** the user selects a device through Bluetooth that works as a card reader only with a USB cable
- **THEN** the app says that this device must be connected with a USB cable to be used as a card reader

### Requirement: Confirm payment data on a Secoder reader

The app SHALL offer the setting "Enable Secoder visualization" on the tab "Payments". With the setting on, a Secoder reader, and a bank that supports it, the reader shows the data of an order and the user confirms there. In every other case the app signs the order in the classic way without the display.

#### Scenario: Secoder available

- **GIVEN** the setting is on, the reader is a Secoder reader, and the bank supports the method
- **WHEN** the user sends a transfer of 120,00 € to DE02120300000000202051
- **THEN** the reader shows the IBAN and the amount
- **AND** the app sends the order after the user confirmed on the reader

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** the user sends a transfer with a chip card
- **THEN** the reader asks only for the PIN

#### Scenario: Not confirmed

- **WHEN** the user cancels on the reader
- **THEN** the app says that the authorization on the card reader was not carried out and sends nothing

### Requirement: Automatic refresh with a chip card

The app SHALL skip an access with a chip card in an automatic refresh when the card is not in the reader or the reader needs a PIN entry, and mark its accounts. The next manual refresh includes them.

#### Scenario: Card not inserted

- **GIVEN** the card of "Business" is not in the reader
- **WHEN** the automatic refresh runs
- **THEN** no request to insert the card appears
- **AND** the sidebar row of "Business" shows that the chip card is needed
