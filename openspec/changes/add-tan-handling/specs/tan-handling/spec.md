# Spec Delta

## Purpose

Banks ask for a second factor at login, for older transactions, and for orders. This capability defines the one dialog that handles every such request, the choice of the TAN method, and what the app does with each kind of challenge.

## ADDED Requirements

### Requirement: One dialog for every source

The app SHALL handle every request for a second factor in one dialog with the title "Two-Factor Authentication", whether the request comes from a FinTS server, from an extension, or from the subscription.

#### Scenario: FinTS login

- **WHEN** the FinTS server of "Musterbank" asks for a TAN at login
- **THEN** the dialog "Two-Factor Authentication" opens

#### Scenario: Extension asks for a code

- **WHEN** an extension asks for a verification code that the service sent by email
- **THEN** the same dialog opens with the text of the extension and a field for the code

### Requirement: State the purpose and the system

The app SHALL show in the dialog the bank, the account or login, the purpose of the request, and the system that asks. Purposes are the login, the download of transactions, and the order that is being sent. Systems are the FinTS server, the website, and the API server of the bank.

#### Scenario: Older transactions

- **WHEN** the FinTS server asks for a TAN because the app requests transactions older than 90 days
- **THEN** the dialog says that the FinTS server of "Musterbank" needs the confirmation to allow the download of transactions

#### Scenario: Login

- **WHEN** the website of a card issuer asks for a code at login
- **THEN** the dialog says that the website needs the confirmation to allow the login

### Requirement: Mark a TAN that covers only the login

The app SHALL say in the dialog that the TAN is used for the login only when the bank asks for a TAN at login while the user is sending an order.

#### Scenario: Login TAN before a payment

- **GIVEN** the user started an order and the bank first asks for a TAN for the login
- **WHEN** the dialog opens
- **THEN** it says that this TAN is used only for the login and not for the order

### Requirement: Choose the TAN method

The app SHALL list under "Choose TAN method" every TAN method that the bank reports for the user, with the name that the bank gives it, and use the method that the user selects.

#### Scenario: Two methods

- **GIVEN** the bank reports "pushTAN 2.0" and "chipTAN QR" for the user
- **WHEN** the dialog opens
- **THEN** the menu lists "pushTAN 2.0" and "chipTAN QR"

#### Scenario: One method

- **GIVEN** the bank reports only "photoTAN"
- **WHEN** the dialog opens
- **THEN** the dialog shows "photoTAN" as the method and offers no menu

### Requirement: Remember the TAN method

The app SHALL remember the TAN method that the user used last for each access and select it the next time. When the bank no longer reports that method, the app asks the user to choose again.

#### Scenario: Same method next time

- **GIVEN** the user chose "chipTAN QR" for the access "erika77" at the last login
- **WHEN** the bank asks for a TAN again
- **THEN** the dialog starts with "chipTAN QR"

#### Scenario: Method no longer offered

- **GIVEN** the remembered method is "smsTAN" and the bank stopped offering it
- **WHEN** the bank asks for a TAN
- **THEN** the dialog shows the methods that the bank reports now with none selected

### Requirement: Change the method inside the dialog

The app SHALL let the user select another TAN method while the dialog is open. The app then cancels the running challenge and requests a new one for the selected method.

#### Scenario: Phone not at hand

- **GIVEN** the dialog waits for an approval with "pushTAN 2.0"
- **WHEN** the user selects "chipTAN QR"
- **THEN** the dialog shows a QR code and a field for the TAN

### Requirement: No usable TAN method

The app SHALL tell the user when the bank reports no TAN method that the app can use, and name the next step, which is to set up a method on the website of the bank and then to run "Edit Login Data...".

#### Scenario: No method registered

- **WHEN** the bank reports no TAN method for the user
- **THEN** the app says that there are no available TAN methods and names both steps
- **AND** the account shows this text as its error

#### Scenario: Method only on the website

- **WHEN** the bank offers a method for its website only and not for its FinTS server
- **THEN** the app says that the bank supports this method only on the website

### Requirement: Choose the TAN medium

The app SHALL fetch the list of TAN media from the bank when the selected method needs the name of a medium, for example a phone or a card, and let the user choose one. The app remembers the choice for the access.

#### Scenario: Two phones registered

- **GIVEN** the user registered the phones "Handy privat" and "Handy Firma" at the bank
- **WHEN** the user selects "mobileTAN"
- **THEN** the dialog shows the progress text "Getting list of TAN media..." and then a menu with both names

#### Scenario: List not available

- **WHEN** the bank does not deliver the list
- **THEN** the dialog says that the list of TAN media could not be fetched and lets the user type the name of the medium

### Requirement: Show the challenge of the bank

The app SHALL show the challenge text that the bank sends without changing it, so that the user can compare it with the display of the TAN device or app.

#### Scenario: Text challenge

- **WHEN** the bank sends the text "Bitte geben Sie die TAN für den Auftrag vom 09.11.2026 ein"
- **THEN** the dialog shows exactly this text above the TAN field

### Requirement: Manual TAN entry

The app SHALL offer a field for the TAN when the method needs a typed TAN. The button to continue is disabled while the field is empty. The app sends the TAN once.

#### Scenario: SMS code

- **GIVEN** the method is "smsTAN" and the bank sent the code 482915 to the phone of the user
- **WHEN** the user types 482915 and continues
- **THEN** the app sends the TAN and the dialog closes when the bank accepts it

#### Scenario: Empty field

- **WHEN** the TAN field is empty
- **THEN** the user cannot continue

### Requirement: Approval in an app without typing

The app SHALL, for a method that the user approves in an app of the bank, ask the user to confirm the data in that app, show no TAN field, and check the result with the bank by itself. The dialog closes by itself when the bank reports the approval.

#### Scenario: Approval given

- **GIVEN** the method is "pushTAN 2.0"
- **WHEN** the user approves the request in the app of the bank
- **THEN** the dialog closes within a few seconds without a click
- **AND** the refresh continues

### Requirement: Timing of the approval check

The app SHALL wait 3 seconds before it asks the bank for the result of an approval for the first time. It repeats the check at the interval that the bank states, or every 2 seconds when the bank states none, and it never checks more often than the bank allows.

#### Scenario: Bank states five seconds

- **GIVEN** the bank asks clients to wait 5 seconds between checks
- **WHEN** the dialog waits for an approval
- **THEN** the app sends the first check after 3 seconds and each later check 5 seconds after the one before

### Requirement: Cancel a pending approval

The app SHALL, when the user cancels a dialog that waits for an approval, tell the user to cancel the authorization in the app of the bank first and ask whether that was done. When the user confirms, the app ends the request.

#### Scenario: Cancel while waiting

- **GIVEN** the dialog waits for an approval in the app of the bank
- **WHEN** the user clicks "Cancel"
- **THEN** the app asks whether the user canceled the authorization in the app
- **AND** after the user answers yes, the dialog closes and the refresh of that access stops

### Requirement: Approval that did not happen

The app SHALL show that the required authorization was not carried out when the bank reports that the user declined the approval or did not answer in time. The app does not start a new request by itself.

#### Scenario: Declined in the app

- **WHEN** the user declines the request in the app of the bank
- **THEN** the dialog closes and the account shows that the required authorization was not carried out

### Requirement: Image challenges

The app SHALL show a photoTAN image or a QR code that the bank sends in the dialog, large enough for a reader at normal distance, together with a field for the TAN. The user can enlarge the image.

#### Scenario: photoTAN

- **GIVEN** the method is "photoTAN"
- **WHEN** the bank sends the image
- **THEN** the dialog shows the image and a TAN field

#### Scenario: Reader does not recognize the code

- **GIVEN** the dialog shows a QR code for "chipTAN QR"
- **WHEN** the user clicks the control that enlarges the code
- **THEN** the code is shown larger and the dialog grows with it

### Requirement: QR code that is confirmed in an app

The app SHALL show a QR code without a TAN field when the bank expects the user to scan the code with its app and to approve there. The dialog names the app, and the app checks the result like for any approval in an app. When the bank sends two codes one after the other, the dialog numbers them.

#### Scenario: Login with a QR code

- **WHEN** the bank sends a QR code for a login that is approved in its app
- **THEN** the dialog shows the code and the request to scan it in the app of the bank
- **AND** the dialog closes by itself after the approval

#### Scenario: Two codes

- **WHEN** the bank sends a second QR code after the first was scanned
- **THEN** the dialog shows the second code and marks it as the second of two

### Requirement: Progress while a challenge is requested

The app SHALL show a progress text in the dialog while it requests a challenge from the bank, which says what is requested, for example a push notification, an SMS code, or a QR code.

#### Scenario: SMS requested

- **WHEN** the user selects "smsTAN" and the app asks the bank to send the code
- **THEN** the dialog shows that it is requesting the SMS code until the bank answers

### Requirement: Optical chipTAN with a flicker code

The app SHALL show an animated flicker code for the optical chipTAN and Sm@rtTAN methods, with marks that show where to hold the TAN generator, and a field for the TAN.

#### Scenario: Flicker code

- **GIVEN** the method is the optical chipTAN
- **WHEN** the bank sends the challenge
- **THEN** the dialog shows the flickering bars and the TAN field

#### Scenario: Invalid challenge

- **WHEN** the bank sends challenge data that is not a valid flicker code
- **THEN** the app says that the bank responded with an invalid challenge and shows no flicker code

### Requirement: Flicker code size

The app SHALL let the user make the flicker code smaller and larger so that it fits the TAN generator, and remember the size. Before the first enlargement the app warns that flicker codes might cause epileptic seizures and asks whether to continue.

#### Scenario: Enlarge

- **WHEN** the user enlarges the flicker code for the first time
- **THEN** the app shows the warning and enlarges the code only after the user agrees

#### Scenario: Size is kept

- **GIVEN** the user set the flicker code to a larger size
- **WHEN** the next flicker code appears
- **THEN** it has the same size

### Requirement: Flicker code stops while typing

The app SHALL stop the animation of the flicker code when the user starts to type the TAN.

#### Scenario: First digit

- **GIVEN** the flicker code is animated
- **WHEN** the user types the first digit of the TAN
- **THEN** the animation stops

### Requirement: Manual chipTAN

The app SHALL show, for the manual chipTAN and Sm@rtTAN methods, the start code and the values that the user must type into the TAN generator, as the bank sends them, and a field for the TAN.

#### Scenario: Start code

- **WHEN** the bank sends the start code 87654321 for a login
- **THEN** the dialog shows 87654321 as the start code and a TAN field

### Requirement: Wrong TAN

The app SHALL show the message of the bank when the bank does not accept a TAN, and it SHALL not send the TAN or the request again by itself. The user starts the action again to get a new challenge.

#### Scenario: Typing error

- **WHEN** the user types a wrong TAN and the bank rejects it
- **THEN** the app says that the bank did not accept the entered TAN, with the text of the bank
- **AND** the refresh of that access ends with this error

### Requirement: Expired challenge

The app SHALL close the dialog and say that the confirmation timed out when the user does not answer within the validity that the bank states for the challenge, or within 5 minutes when the bank states none.

#### Scenario: User away from the Mac

- **GIVEN** a challenge without a stated validity
- **WHEN** the user does not answer for 5 minutes
- **THEN** the dialog closes
- **AND** the account shows that the two-factor authentication timed out

### Requirement: The dialog appears even when the bank already sent a code

The app SHALL show the dialog also when the bank sent a push message or an SMS at login before the app asked for one, so that the user sees the purpose and can change the method.

#### Scenario: SMS arrives first

- **GIVEN** the bank sends an SMS code as soon as the login starts
- **WHEN** the code arrives on the phone
- **THEN** the dialog is open or opens, shows the purpose, and accepts the code

### Requirement: Separate dialogs for separate systems

The app SHALL ask separately for each system of one bank that needs a second factor in one refresh, one after the other, and each dialog names its system.

#### Scenario: FinTS server and website

- **GIVEN** the giro account of "Musterbank" uses the FinTS server and the card of "Musterbank" uses an extension for the website
- **WHEN** both ask for a TAN in one refresh
- **THEN** the user sees two dialogs, the first for the FinTS server and the second for the website

### Requirement: One dialog at a time

The app SHALL show only one dialog for two-factor authentication at a time. A further request waits until the user answered or canceled the open dialog.

#### Scenario: Two banks at once

- **GIVEN** "Musterbank" and "Beispielbank" both ask for a TAN during "Refresh All Accounts"
- **WHEN** the dialog for "Musterbank" is open
- **THEN** the dialog for "Beispielbank" appears after the first dialog closed

### Requirement: Cancel the dialog

The app SHALL let the user cancel the dialog. The app then ends the request for that access, stores nothing for it, and continues with the other accesses.

#### Scenario: Cancel a login TAN

- **WHEN** the user cancels the dialog for the login at "Musterbank"
- **THEN** the accounts of "Musterbank" keep their last state without an error of the bank
- **AND** the accounts of other banks are refreshed

### Requirement: No dialog when no TAN is needed

The app SHALL open no dialog when the bank accepts a request without a second factor.

#### Scenario: Refresh within the exemption

- **GIVEN** the bank asked for a TAN 10 days ago and needs none for 90 days
- **WHEN** the user refreshes the account
- **THEN** the refresh completes and no dialog appears
