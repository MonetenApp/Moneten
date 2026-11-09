# Spec Delta

## Purpose

The catalog is a signed list of reviewed extensions. This capability defines how the user browses, installs, updates, and removes catalog extensions in the app, and how the app makes sure that only reviewed and unchanged extensions run while the signature check is on.

## ADDED Requirements

### Requirement: Browse the catalog

The app SHALL show the extensions of the catalog in the settings tab "Extensions". Each entry shows the name, the description, the kinds of data it fetches, the author, the version, and whether it is installed. The user can search the list by name.

#### Scenario: Open the catalog

- **WHEN** the user opens the settings tab "Extensions" and the catalog
- **THEN** the list shows an entry such as "Broker", "Fetches balances and securities", version 2.31, "Not installed"

#### Scenario: Search

- **WHEN** the user types "brok" in the search field of the catalog
- **THEN** the list shows only entries whose name contains "brok", without regard to case

### Requirement: Details before installing

The app SHALL show, before the user installs a catalog extension, the services it adds, the hosts it contacts, the labels of its login fields, and a link to its page in the catalog repository.

#### Scenario: Hosts are visible

- **WHEN** the user opens the details of "Broker"
- **THEN** the details list the host `api.broker.example` and the login fields "Email address" and "API key"

### Requirement: Install from the catalog

The app SHALL download the script and the manifest of a catalog extension, check both, and place them in the "Extensions" folder when the user chooses "Install". The services of the extension are then available in the add account assistant without a restart.

#### Scenario: Install

- **WHEN** the user chooses "Install" for "Broker"
- **THEN** the entry changes to "Installed" with its version
- **AND** "Broker" appears under "Other" in the add account assistant
- **AND** the app does not show the warning for extensions from outside the catalog

#### Scenario: Download fails

- **WHEN** the download stops because the network is gone
- **THEN** nothing is placed in the "Extensions" folder and the app says that the extension could not be downloaded

### Requirement: Signed index

The app SHALL accept a catalog index only when its signature is valid for the public key of the project that ships inside the app. The app uses no content of an index that fails this check.

#### Scenario: Tampered index

- **GIVEN** an index whose content was changed after it was signed
- **WHEN** the app downloads it
- **THEN** the app rejects the index and keeps the last accepted one
- **AND** the catalog shows that the new list could not be verified

### Requirement: Digest of every file

The app SHALL compare the SHA-256 digest of every script and manifest with the digest in the accepted index, at download time and each time before the extension runs. A file that does not match is not installed and does not run.

#### Scenario: Script changed under a valid index

- **GIVEN** the catalog extension "Broker" is installed and the signature check is on
- **WHEN** a program changes one line in `Broker.lua` and a refresh starts
- **THEN** the script does not run
- **AND** the accounts and the list of extensions show that "Broker" was changed and does not match the catalog

#### Scenario: Download does not match

- **WHEN** a downloaded script has another digest than the index lists
- **THEN** the app discards the download and reports that the file is damaged or was altered

### Requirement: Older index is rejected

The app SHALL reject an index that is older than the newest index it has accepted, also when its signature is valid.

#### Scenario: Replayed old index

- **GIVEN** the app accepted the index number 120
- **WHEN** a server delivers the validly signed index number 95
- **THEN** the app keeps index 120

### Requirement: Signature check setting

The app SHALL offer the setting "Verify digital signatures of extensions" in the settings tab "Extensions", which is on by default. The setting carries the note that it is to be turned off only for self-developed, unsigned extensions. Turning it off needs a confirmation that states the risk.

#### Scenario: Default

- **WHEN** a new user opens the settings tab "Extensions"
- **THEN** "Verify digital signatures of extensions" is on

#### Scenario: Turn off

- **WHEN** the user turns the setting off
- **THEN** the app explains that any script in the "Extensions" folder can then receive login data, and asks for a confirmation
- **AND** the setting stays on when the user cancels

### Requirement: Only catalog extensions run while the check is on

The app SHALL, while the signature check is on, run only extensions whose script and manifest match the accepted index. Every other file in the "Extensions" folder is listed as blocked with the reason.

#### Scenario: File from elsewhere

- **GIVEN** the signature check is on
- **WHEN** the user copies `Demo.lua` from a website into the "Extensions" folder
- **THEN** the list shows "Demo" as blocked because it is not part of the catalog
- **AND** its services are not offered in the assistant

#### Scenario: Check turned off

- **GIVEN** the signature check is off
- **WHEN** the user picks a service of `Demo.lua` in the assistant
- **THEN** the app shows the warning for extensions from outside the catalog and runs the script after the user continues

### Requirement: Blocked extension on an account

The app SHALL show on each account whose extension is blocked that the refresh did not run because the extension is not verified, and name the extension. The stored data of the account stays visible.

#### Scenario: Refresh of a blocked extension

- **GIVEN** the account "Demo Account" uses the blocked extension "Demo"
- **WHEN** "Refresh All Accounts" runs
- **THEN** "Demo Account" shows that "Demo" is not verified and was not run
- **AND** all other accounts refresh

### Requirement: Decision for extensions installed before the catalog

The app SHALL ask the user once, at the first start of the version that introduces the catalog, when extensions are installed that the catalog does not contain. The user chooses to keep the signature check on, which blocks them, or to turn it off, which keeps them running.

#### Scenario: Self-written extension from v0.1

- **GIVEN** the user installed the self-written `Meine Bank.lua` in an earlier version
- **WHEN** the user first starts the version with the catalog
- **THEN** the app lists "Meine Bank" as not in the catalog and offers both choices
- **AND** with the check on, "Meine Bank" is blocked and all catalog extensions run

#### Scenario: Same extension exists in the catalog

- **GIVEN** an installed file is identical to the catalog version of that extension
- **WHEN** the user first starts the version with the catalog
- **THEN** the app treats it as a catalog extension and does not ask about it

### Requirement: Look for updates

The app SHALL download the current index at start and once a day while it runs, and on request with a button in the catalog. The app shows for each installed catalog extension whether a newer version exists.

#### Scenario: New version in the catalog

- **GIVEN** "Broker" 2.31 is installed and the new index lists version 2.32
- **WHEN** the app accepts the new index
- **THEN** the entry "Broker" shows that version 2.32 is available

### Requirement: Install updates

The app SHALL install a newer version of an installed catalog extension automatically while the setting "Update extensions automatically" is on, which is the default. With the setting off, the user installs each update with a button. An update replaces the script and the manifest together and never runs before both pass the digest check.

#### Scenario: Automatic update

- **GIVEN** automatic updates are on and version 2.32 of "Broker" is available
- **WHEN** no session of "Broker" is running
- **THEN** the app installs 2.32, and the next refresh uses it without an app update

#### Scenario: Update during a refresh

- **WHEN** an update arrives while a session of "Broker" runs
- **THEN** the running session finishes with the old version and the update is installed afterwards

#### Scenario: Manual updates

- **GIVEN** automatic updates are off
- **WHEN** version 2.32 is available
- **THEN** "Broker" stays at 2.31 until the user chooses "Update"

### Requirement: Changes of an update are visible

The app SHALL show for each update the version, the date, and the change note from the catalog. When an update adds a host or a login field, the app states that in the list of extensions after the update.

#### Scenario: New host

- **WHEN** version 2.32 of "Broker" adds the host `login.broker.example`
- **THEN** the entry "Broker" says that version 2.32 also contacts `login.broker.example`

### Requirement: Remove a catalog extension

The app SHALL remove an installed catalog extension when the user chooses "Remove". Before that, the app names the accounts that use it and says that these accounts keep their data and can no longer be refreshed.

#### Scenario: Extension in use

- **GIVEN** the account "Broker Depot" uses "Broker"
- **WHEN** the user chooses "Remove" for "Broker"
- **THEN** the app names "Broker Depot" in the confirmation
- **AND** after the confirmation the script and the manifest are gone and "Broker Depot" keeps its data

### Requirement: Extension removed from the catalog

The app SHALL stop running an installed extension that a newer index no longer contains while the signature check is on, and show the reason that the catalog gives.

#### Scenario: Withdrawn extension

- **GIVEN** "Broker" is installed and a new index withdraws it with the note "The service closed its API."
- **WHEN** the app accepts the new index
- **THEN** "Broker" is listed as blocked with that note

### Requirement: Catalog not reachable

The app SHALL keep running the installed catalog extensions with the last accepted index when the catalog cannot be reached. Installing a new extension is not possible in that state, and the catalog says so with the date of the last accepted index.

#### Scenario: Offline

- **GIVEN** the Mac has no connection to the catalog
- **WHEN** the user opens the catalog
- **THEN** the app shows the entries of the last accepted index and its date, and "Install" is disabled

### Requirement: Catalog requests carry no personal data

The app SHALL request the index and the files of the catalog without any identifier of the user or the Mac, and without the list of installed extensions.

#### Scenario: Update check

- **WHEN** the app looks for updates
- **THEN** it downloads the whole index and compares versions on the Mac
- **AND** the request does not reveal which extensions are installed
