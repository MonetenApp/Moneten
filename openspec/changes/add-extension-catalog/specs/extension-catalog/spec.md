# Spec Delta

## Purpose

The catalog is a signed list of reviewed extension packages. This capability defines how the user browses, installs, updates, and removes catalog extensions in the "Extensions" window, and how the app makes sure that a catalog extension runs only while its files are reviewed and unchanged.

## ADDED Requirements

### Requirement: Browse the catalog in the Extensions window

The app SHALL show the catalog extensions that are not installed under "Available" in the window that the menu item "Extensions" opens. Each entry shows the name, the description, the kinds of data it fetches, the author, and the version.

#### Scenario: Open the window

- **WHEN** the user chooses the menu item "Extensions"
- **THEN** the window shows the sections "Installed" and "Available"
- **AND** "Available" lists an entry such as "Broker", "Fetches balances and securities", version 2.31

### Requirement: Details before installing

The app SHALL show, before the user installs a catalog extension, the services it adds, the hosts it contacts, the labels of its login fields, its license, and a link to its folder in the catalog repository.

#### Scenario: Hosts are visible

- **WHEN** the user opens the details of "Broker" in the "Extensions" window
- **THEN** the details list the host `api.broker.example`, the login fields "Email address" and "API key", and the license "MIT"

### Requirement: Install from the catalog

The app SHALL download every file of a catalog package, check each one, and place the package in the "Extensions" folder in one step when the user chooses "Install". The services of the extension are then available in the add account assistant without a restart.

#### Scenario: Install

- **WHEN** the user chooses "Install" for "Broker"
- **THEN** the entry moves to "Installed" with its version
- **AND** "Broker" appears under "Other" in the add account assistant
- **AND** the app does not show the warning for extensions installed from a file

#### Scenario: Download fails

- **WHEN** the download stops because the network is gone
- **THEN** nothing is placed in the "Extensions" folder and the app says that the extension could not be downloaded

### Requirement: Signed index

The app SHALL accept a catalog index only when its signature is valid for one of the two public keys that ship inside the app, the current key and the next key. Each index carries a version number that only grows. The app uses no content of an index that fails this check.

#### Scenario: Tampered index

- **GIVEN** an index whose content was changed after it was signed
- **WHEN** the app downloads it
- **THEN** the app rejects the index and keeps the last accepted one
- **AND** the "Extensions" window shows that the new list could not be verified

#### Scenario: Index signed with the next key

- **GIVEN** the project moved the signing to the next key
- **WHEN** the app downloads an index signed with that key
- **THEN** the app accepts the index

#### Scenario: Unknown key

- **WHEN** the app downloads an index signed with a key that the app does not ship
- **THEN** the app rejects the index and keeps the last accepted one

### Requirement: Digest of every file

The app SHALL compare the SHA-256 digest of every file of a catalog package with the digest in the accepted index, at download time and each time before the extension runs. A package with a file that does not match is not installed and does not run.

#### Scenario: Script changed under a valid index

- **GIVEN** the catalog extension "Broker" is installed
- **WHEN** a program changes one line in `Broker.lua` and a refresh starts
- **THEN** the script does not run
- **AND** the accounts and the "Extensions" window show that "Broker" was changed and does not match the catalog

#### Scenario: Download does not match

- **WHEN** a downloaded script has another digest than the index lists
- **THEN** the app discards the download and reports that the file is damaged or was altered

### Requirement: Older index is rejected

The app SHALL reject an index whose version number is lower than the version number of the newest index it has accepted, also when its signature is valid.

#### Scenario: Replayed old index

- **GIVEN** the app accepted the index with version 120
- **WHEN** a server delivers the validly signed index with version 95
- **THEN** the app keeps index 120

### Requirement: Catalog extensions and file installs

The app SHALL treat an installed extension as a catalog extension only while its files match the accepted index. Every other installed extension is marked "Unverified" and runs after the warning for extensions installed from a file.

#### Scenario: File from elsewhere

- **WHEN** the user copies `Demo.lua` from a website into the "Extensions" folder
- **THEN** the "Extensions" window lists "Demo" under "Installed" marked "Unverified"
- **AND** its services are offered in the add account assistant after the warning

#### Scenario: Catalog install

- **WHEN** the user installs "Broker" from the catalog
- **THEN** "Broker" is not marked "Unverified" and runs without the warning

### Requirement: Stopped extension on an account

The app SHALL show on each account whose catalog extension is blocked, withdrawn, or changed that the refresh did not run, with the name of the extension and the reason. The stored data of the account stays visible.

#### Scenario: Refresh of a blocked extension

- **GIVEN** the account "Demo Account" uses the catalog extension "Demo", which the index blocks
- **WHEN** "Refresh All Accounts" runs
- **THEN** "Demo Account" shows that "Demo" is blocked and was not run
- **AND** all other accounts refresh

### Requirement: Look for updates

The app SHALL download the current index at start, once a day while it runs, and when the user chooses "Check Now" in the "Extensions" window. The app shows for each installed catalog extension whether a newer version exists.

#### Scenario: New version in the catalog

- **GIVEN** "Broker" 2.31 is installed and the new index lists version 2.32
- **WHEN** the app accepts the new index
- **THEN** the entry "Broker" shows that version 2.32 is available

### Requirement: Install updates

The app SHALL install a newer version of an installed catalog extension by itself when the update adds no host and no login field and the setting "Update extensions automatically" in the "Extensions" window is on, which is the default. With the setting off, every update waits until the user chooses "Update". An update replaces every file of the package together and never runs before all files pass the digest check.

#### Scenario: Automatic update

- **GIVEN** automatic updates are on and version 2.32 of "Broker" is available
- **AND** version 2.32 adds no host and no login field
- **WHEN** no session of "Broker" is running
- **THEN** the app installs 2.32, and the next refresh uses it without an app update

#### Scenario: Manual updates

- **GIVEN** the user turned "Update extensions automatically" off
- **WHEN** the index lists version 2.32 of "Broker", which adds no host and no login field
- **THEN** "Broker" stays at 2.31 until the user chooses "Update"

#### Scenario: Update during a refresh

- **WHEN** an update arrives while a session of "Broker" runs
- **THEN** the running session finishes with the old version and the update is installed afterwards

#### Scenario: Removed host

- **GIVEN** automatic updates are on
- **WHEN** version 2.32 of "Broker" no longer lists the host `old.broker.example`
- **THEN** the app installs 2.32 by itself

### Requirement: An update that asks for new rights waits

The app SHALL hold an update of a catalog extension that adds a host or a login field until the user confirms it. The "Extensions" window shows the new version, its change note, and what is new. The installed version keeps running until the user confirms.

#### Scenario: New host

- **GIVEN** "Broker" 2.31 is installed
- **WHEN** the index lists version 2.32, which adds the host `login.broker.example`
- **THEN** the entry "Broker" says "Version 2.32 also contacts login.broker.example" with the button "Review Update"
- **AND** the next refresh still uses 2.31

#### Scenario: Update confirmed

- **GIVEN** the update of "Broker" to 2.32 waits for the user
- **WHEN** the user chooses "Review Update" and confirms
- **THEN** the app installs 2.32 and the next refresh uses it

#### Scenario: New login field

- **WHEN** version 2.32 of "Broker" adds the login field "One-time code"
- **THEN** the update waits for the user and the window names the field "One-time code"

### Requirement: Remove a catalog extension

The app SHALL remove an installed catalog extension when the user chooses "Remove" in the "Extensions" window. Before that, the app names the accounts that use it and says that these accounts keep their data and can no longer be refreshed.

#### Scenario: Extension in use

- **GIVEN** the account "Broker Depot" uses "Broker"
- **WHEN** the user chooses "Remove" for "Broker"
- **THEN** the app names "Broker Depot" in the confirmation
- **AND** after the confirmation every file of the package is gone and "Broker Depot" keeps its data

### Requirement: Blocked, withdrawn, and unmaintained extensions

The app SHALL apply the state that the accepted index gives an installed catalog extension. A blocked extension, which has a security problem, stops running at once. A withdrawn extension stops running. An unmaintained extension keeps running. The "Extensions" window and the accounts of the extension show the note of the catalog.

#### Scenario: Blocked extension

- **GIVEN** "Broker" is installed and a new index blocks it with the note "Sends the password to another host."
- **WHEN** the app accepts the new index
- **THEN** "Broker" does not run and the window shows it as blocked with that note

#### Scenario: Withdrawn extension

- **GIVEN** "Broker" is installed and a new index withdraws it with the note "The service closed its API."
- **WHEN** the app accepts the new index
- **THEN** "Broker" does not run and the window shows it as withdrawn with that note

#### Scenario: Unmaintained extension

- **GIVEN** a new index marks "Broker" as unmaintained
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" runs and the window shows the note that nobody maintains it

### Requirement: Catalog not reachable

The app SHALL keep running the installed catalog extensions with the last accepted index when the catalog cannot be reached. Installing a new extension is not possible in that state, and the "Extensions" window says so with the date of the last accepted index.

#### Scenario: Offline

- **GIVEN** the Mac has no connection to the catalog
- **WHEN** the user opens the "Extensions" window
- **THEN** the app shows the entries of the last accepted index and its date, and "Install" is disabled

### Requirement: Catalog requests carry no personal data

The app SHALL request the index and the files of the catalog only from `extensions.monetenapp.com`, without any identifier of the user or the Mac, and without the list of installed extensions.

#### Scenario: Update check

- **WHEN** the app looks for updates
- **THEN** it downloads the whole index from `extensions.monetenapp.com` and compares versions on the Mac
- **AND** the request does not reveal which extensions are installed

### Requirement: Catalog packages need a manifest

The app SHALL install a catalog package only when its manifest lists the hosts, the login field labels of each service, the kinds of data, the API version, and in `license` the SPDX identifier of its license.

#### Scenario: Manifest without hosts

- **WHEN** an accepted index lists a package whose manifest has no `hosts`
- **THEN** the "Extensions" window shows the package as not installable because its manifest is incomplete
