# Spec Delta

## ADDED Requirements

### Requirement: Methods for connected TAN generators

The app SHALL offer the methods "chipTAN USB / Bluetooth" and "Sm@rtTAN USB / Bluetooth" in the choice of the TAN method when the bank reports a chipTAN or Sm@rtTAN method for the user. The methods appear next to the optical and manual variants.

#### Scenario: Bank with chipTAN

- **GIVEN** the bank reports the optical chipTAN method for the user
- **WHEN** the TAN dialog opens
- **THEN** the method menu also lists "chipTAN USB / Bluetooth"

#### Scenario: Bank without a chipTAN method

- **GIVEN** the bank reports only "pushTAN 2.0"
- **WHEN** the TAN dialog opens
- **THEN** the method menu lists no method for a connected TAN generator

### Requirement: Select the TAN generator

The app SHALL list the TAN generators that it finds through a USB cable and through Bluetooth under "TAN generator", let the user select one, and remember the device for the access. When it finds none, it asks the user to connect a USB or Bluetooth TAN generator.

#### Scenario: One device by cable and one by Bluetooth

- **GIVEN** one TAN generator is connected by USB cable and one is paired through Bluetooth
- **WHEN** the user selects "chipTAN USB / Bluetooth"
- **THEN** the menu "TAN generator" lists both devices

#### Scenario: No device

- **WHEN** the user selects "chipTAN USB / Bluetooth" and no device is found
- **THEN** the dialog asks the user to connect a USB or Bluetooth TAN generator

### Requirement: Bluetooth permission and pairing

The app SHALL ask for the Bluetooth permission of macOS when the user first selects a Bluetooth TAN generator, with a text that names TAN generators and card readers as the reason. When the permission is denied, or the Mac has no suitable Bluetooth, the app says so and still offers devices with a USB cable.

#### Scenario: Permission denied

- **WHEN** the user denies the Bluetooth permission
- **THEN** the dialog says where to allow Bluetooth for the app in the system settings
- **AND** the menu still lists a TAN generator that is connected by USB cable

#### Scenario: Pairing needed

- **WHEN** the app finds a Bluetooth TAN generator that is not in pairing mode
- **THEN** the dialog asks the user to turn on Bluetooth pairing on the TAN generator

### Requirement: Send the challenge and read the TAN back

The app SHALL send the challenge of the bank to the selected TAN generator, ask the user to insert the card and to confirm the data on the device, read the TAN from the device, and send it to the bank without typing by the user.

#### Scenario: Confirmed on the device

- **GIVEN** a TAN generator is connected by USB cable with the card inserted
- **WHEN** the bank sends a challenge and the user confirms the data on the device
- **THEN** the dialog shows "Connecting to TAN generator..." and then the request to confirm the data
- **AND** the dialog closes when the bank accepts the TAN

#### Scenario: Card missing

- **WHEN** the device reports that no card is inserted
- **THEN** the dialog asks the user to insert the card into the TAN generator

### Requirement: Failure of the device

The app SHALL say what failed when the TAN generator cannot be reached, cannot show the data, returns no TAN, holds a card that cannot generate TANs, or the user did not confirm on the device. When the device does not answer for 60 seconds, the dialog offers the optical and manual variants of the method.

#### Scenario: Not confirmed

- **WHEN** the user presses the cancel key on the TAN generator
- **THEN** the dialog says that the authorization on the TAN generator was not carried out

#### Scenario: Bluetooth connection lost

- **WHEN** the Bluetooth connection cannot be established
- **THEN** the dialog says that it cannot connect to the TAN generator
- **AND** after 60 seconds it offers the optical chipTAN variant

#### Scenario: Old firmware

- **WHEN** the firmware of the device is older than the oldest version that supports TAN generation
- **THEN** the dialog names the installed version and the version that is needed

### Requirement: Diagnostics for the TAN generator

The app SHALL show a Bluetooth symbol next to the menu "TAN generator". A click on it shows diagnostic information, which is the Bluetooth state of the Mac, the devices found, the connection type, and the firmware version of each device.

#### Scenario: Open the diagnostics

- **WHEN** the user clicks the Bluetooth symbol
- **THEN** the app shows the Bluetooth state and one line for each device with its connection type and firmware version

### Requirement: Synchronize a TAN generator

The app SHALL start a synchronization when the bank reports that the TAN generator must be synchronized. The app shows instructions for reading the ATC from the device, asks for the ATC and a TAN, and sends both to the bank. The progress text is "Synchronizing TAN generator...".

#### Scenario: Synchronization succeeds

- **GIVEN** the bank reports that the server requires a TAN generator synchronization
- **WHEN** the user reads the ATC 42 from the device, enters it with the TAN, and continues
- **THEN** the bank accepts the synchronization and the interrupted refresh can be started again

#### Scenario: Instructions match the method

- **GIVEN** the method of the access is "chipTAN QR"
- **WHEN** the synchronization dialog opens
- **THEN** the instructions tell the user to insert the card, scan the QR code, and press the OK key

#### Scenario: Missing or invalid ATC

- **WHEN** the user leaves the ATC empty or enters letters
- **THEN** the app says that the ATC is missing or invalid and sends nothing

### Requirement: Activate a pushTAN app

The app SHALL ask for an "Activation code" when the bank reports that the server requires a pushTAN activation. The dialog tells the user to scan the QR code from the registration letter of the bank with the pushTAN app to get the code. The progress text is "Activating pushTAN app...".

#### Scenario: Activation succeeds

- **GIVEN** the bank reports that the server requires a pushTAN activation
- **WHEN** the user enters the activation code from the pushTAN app and continues
- **THEN** the bank confirms the activation and the app offers the pushTAN method for the access

#### Scenario: Empty code

- **WHEN** the user continues with an empty field
- **THEN** the app says that the activation code is missing and sends nothing

### Requirement: Card readers as TAN generators

The app SHALL offer a connected card reader as a TAN generator only when the reader supports TAN generation. A reader that does not is listed as disabled with the note that it cannot be used as a TAN generator.

#### Scenario: Reader without TAN support

- **GIVEN** a connected card reader that cannot generate TANs
- **WHEN** the user opens the menu "TAN generator"
- **THEN** the reader is listed as disabled with the note that this card reader cannot be used as a TAN generator

#### Scenario: Reader with TAN support

- **GIVEN** a connected card reader that supports TAN generation
- **WHEN** the user opens the menu "TAN generator"
- **THEN** the reader can be selected
