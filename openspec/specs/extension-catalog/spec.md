# extension-catalog Specification

## Purpose
The catalog is a signed list of reviewed extension packages. This capability defines how the user browses, installs, updates, and removes catalog extensions in the "Extensions" window, and how the app makes sure that a catalog extension runs only while its files are reviewed and unchanged.

## Requirements

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

The app SHALL accept a catalog index only when its signature is valid for one of the two public keys that ship inside the app, the current key and the next key. Once the app has accepted an index signed with the next key, it refuses every index signed with the current key. The app uses no content of an index that fails this check.

#### Scenario: Tampered index

- **GIVEN** an index whose content was changed after it was signed
- **WHEN** the app downloads it
- **THEN** the app rejects the index and keeps the last accepted one
- **AND** the "Extensions" window shows that the new list could not be verified

#### Scenario: Index signed with the next key

- **GIVEN** the project moved the signing to the next key
- **WHEN** the app downloads an index signed with that key
- **THEN** the app accepts the index

#### Scenario: Current key after the switch

- **GIVEN** the app accepted index 130, signed with the next key
- **WHEN** a server delivers an index with version 131, validly signed with the current key
- **THEN** the app rejects the index and keeps index 130

#### Scenario: Unknown key

- **WHEN** the app downloads an index signed with a key that the app does not ship
- **THEN** the app rejects the index and keeps the last accepted one

### Requirement: Digest of every file

The app SHALL compare the SHA-256 digest of every file of a catalog package with the accepted index: a download with the entry of the downloaded version, and an installed package before each run with the entry of the installed version. A package with a file that does not match is not installed and does not run.

#### Scenario: Script changed under a valid index

- **GIVEN** the catalog extension "Broker" is installed
- **WHEN** a program changes one line in `Broker.lua` and a refresh starts
- **THEN** the script does not run
- **AND** the accounts and the "Extensions" window show that "Broker" was changed and does not match the catalog

#### Scenario: Download does not match

- **GIVEN** "Broker" 2.31 is installed and the accepted index lists 2.32
- **WHEN** the downloaded `Broker.lua` of 2.32 has another digest than the index lists for 2.32
- **THEN** the app discards the download, keeps 2.31, and reports that the file is damaged or was altered

#### Scenario: Download of a new version matches

- **GIVEN** "Broker" 2.31 is installed and the accepted index lists 2.32
- **WHEN** every downloaded file of 2.32 matches the digests that the index lists for 2.32
- **THEN** the app installs 2.32, although the files differ from the digests of 2.31

### Requirement: Only the listed version runs

The app SHALL let an installed catalog extension run only while the accepted index lists its installed version. The index lists one version of each package. An installed version that is not the listed version does not run, its refreshes stop with a message that says to install the update, and the "Extensions" window offers the update when the listed version is newer.

#### Scenario: Update waits for the user

- **GIVEN** "Broker" 2.31 is installed and the update to 2.32 waits for the user
- **AND** the accepted index lists only 2.32
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" does not run, and "Broker Depot" says "Version 2.31 of Broker is no longer in the catalog. Open Extensions and install the update."
- **AND** the window shows "Broker" with the badge "Update Needed" and the button "Update" or "Review Update"

#### Scenario: Automatic update failed

- **GIVEN** "Broker" 2.31 is installed, "Update extensions automatically" is on, and the accepted index lists only 2.32
- **AND** 2.32 adds no host and no login field
- **WHEN** the download of 2.32 fails, because the Mac is offline or a file does not match its digest
- **THEN** the window shows "Broker" with the badge "Update Needed" and the button "Update"
- **AND** "Update" downloads 2.32 again and installs it when every file matches

#### Scenario: Listed version

- **GIVEN** "Broker" 2.32 is installed and the accepted index lists 2.32
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" 2.32 runs after its files match the digests that the index lists

### Requirement: Index version floor

The app SHALL accept an index only when its version is higher than the floor, the version of the newest index accepted with the same key. An index with the floor's version and the same content is the one the app has. The first index of the next key starts its own floor. The app keeps the floors and the refused key in the data folder.

#### Scenario: Replayed old index

- **GIVEN** the app accepted the index with version 120
- **WHEN** a server delivers the validly signed index with version 95
- **THEN** the app keeps index 120

#### Scenario: Same version, other content

- **GIVEN** the app accepted the index with version 120
- **WHEN** a server delivers an index with version 120, validly signed, that lists other files
- **THEN** the app rejects it and keeps the index it accepted

#### Scenario: Leaked current key

- **GIVEN** a leaked current key signed an index with version 9007199254740991, which the app accepted
- **WHEN** the project signs index 130 with the next key
- **THEN** the app accepts index 130 and refuses the current key from then on

### Requirement: An app update resets the floor of retired keys

The app SHALL drop, after an app update, the floor of every key that the new build no longer ships. When neither shipped key has a floor, the app accepts an index whose version is at least the lowest index version that the build ships.

#### Scenario: Both keys replaced

- **GIVEN** the app holds the floor 9007199254740991 for a key that the project retired
- **AND** the update ships two new keys and the lowest index version 140
- **WHEN** the updated app downloads index 140, signed with the new current key
- **THEN** the app accepts index 140

#### Scenario: Below the lowest shipped version

- **GIVEN** the update ships two new keys and the lowest index version 140, and neither key has a floor
- **WHEN** the updated app downloads index 139, signed with the new current key
- **THEN** the app rejects the index

### Requirement: Catalog extensions and file installs

The app SHALL record for each installed extension whether it came from the catalog or from a file, and keep that origin outside the "Extensions" folder until the extension is removed. A catalog extension whose files do not match the index stays blocked as changed. It never becomes "Unverified". Only an extension installed from a file is marked "Unverified" and runs after the warning.

#### Scenario: File from elsewhere

- **WHEN** the user copies `Demo.lua` from a website into the "Extensions" folder
- **THEN** the "Extensions" window lists "Demo" under "Installed" marked "Unverified"
- **AND** its services are offered in the add account assistant after the warning

#### Scenario: Catalog install

- **WHEN** the user installs "Broker" from the catalog
- **THEN** "Broker" is not marked "Unverified" and runs without the warning

#### Scenario: Changed catalog package is not a file install

- **GIVEN** the catalog extension "Broker" is installed and the file install "Demo" is allowed
- **WHEN** a program changes one line in `Broker.lua` and one line in `Demo.lua`
- **THEN** "Broker" stays blocked as changed, and the app offers no warning that would let it run
- **AND** "Demo" runs again after the user confirms the warning

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

- **GIVEN** automatic updates are on and version 2.32 of "Broker" adds no host and no login field
- **WHEN** the app accepts the index with 2.32 while a session of "Broker" runs
- **THEN** the running session finishes with the old version and the update is installed afterwards

#### Scenario: Removed host

- **GIVEN** automatic updates are on
- **WHEN** version 2.32 of "Broker" no longer lists the host `old.broker.example`
- **THEN** the app installs 2.32 by itself

### Requirement: An update that asks for new rights waits

The app SHALL hold an update of a catalog extension that adds a host or a login field until the user confirms it. The confirmation shows the new version, the new hosts, and the new login fields, and says that the accounts of the extension can be refreshed only after the update. Until the user confirms, the installed version does not run, because the index no longer lists it.

#### Scenario: New host

- **GIVEN** "Broker" 2.31 is installed
- **WHEN** the app accepts an index that lists version 2.32, which adds the host `login.broker.example`
- **THEN** the entry "Broker" says "Version 2.32 also contacts login.broker.example" with the button "Review Update"
- **AND** the next refresh of "Broker Depot" stops with "Open Extensions and install the update."

#### Scenario: Review the update

- **GIVEN** the update of "Broker" to 2.32, which adds the host `login.broker.example`, waits for the user
- **WHEN** the user chooses "Review Update"
- **THEN** the confirmation asks "Update Broker to version 2.32?", lists `login.broker.example` under "New hosts it contacts:", and says that the accounts can be refreshed only after this update

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

The app SHALL apply the state that the accepted index gives an installed catalog extension. A blocked extension, which has a security problem, stops running at once. A withdrawn extension stops running. An unmaintained extension keeps running. The "Extensions" window shows the note of the catalog. The accounts of a blocked or withdrawn extension show it as the error of their refresh. The accounts of an unmaintained extension show no note.

#### Scenario: Blocked extension

- **GIVEN** "Broker" is installed and a new index blocks it with the note "Sends the password to another host."
- **WHEN** the app accepts the new index
- **THEN** "Broker" does not run and the window shows it as blocked with that note

#### Scenario: Withdrawn extension

- **GIVEN** "Broker" is installed and a new index withdraws it with the note "The service closed its API."
- **WHEN** the app accepts the new index
- **THEN** "Broker" does not run and the window shows it as withdrawn with that note

#### Scenario: Unmaintained extension

- **GIVEN** a new index marks "Broker" as unmaintained with the note "No answer since August."
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" runs, and the window shows "Nobody maintains Broker. No answer since August."

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
