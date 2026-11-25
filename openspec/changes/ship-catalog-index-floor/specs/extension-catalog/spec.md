## MODIFIED Requirements

### Requirement: Index version floor

The app SHALL accept an index only when its version is higher than the floor, the version of the newest index accepted with the same key, and at least the lowest index version of the release. An index with the floor's version and the same content is the one the app has. The first index of the next key starts its own floor. The app keeps the floors and the refused key in the data folder.

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

#### Scenario: First index of the next key below the release

- **GIVEN** the release ships the lowest index version 140, and the app accepted index 200 with the current key
- **WHEN** a server delivers index 130, validly signed with the next key
- **THEN** the app rejects the index and keeps index 200

### Requirement: An app update resets the floor of retired keys

The app SHALL drop, after an app update, the floor of every key that the new build no longer ships.

#### Scenario: Both keys replaced

- **GIVEN** the app holds the floor 9007199254740991 for a key that the project retired
- **AND** the update ships two new keys and the lowest index version 140
- **WHEN** the updated app downloads index 140, signed with the new current key
- **THEN** the app accepts index 140

#### Scenario: Below the lowest shipped version

- **GIVEN** the update ships two new keys and the lowest index version 140, and neither key has a floor
- **WHEN** the updated app downloads index 139, signed with the new current key
- **THEN** the app rejects the index

## ADDED Requirements

### Requirement: Each release raises the lowest index version

The app SHALL refuse every index whose version is below the lowest index version of the release, also in a new data folder and also when the floor of its key is lower. Each release raises that version to the version of the newest index that the catalog signed before the release, and never lowers it. A floor that is higher still decides.

#### Scenario: New data folder

- **GIVEN** the release ships the lowest index version 140, and the data folder is new
- **WHEN** a server delivers the validly signed index with version 139
- **THEN** the app rejects the index and offers no extension of the catalog

#### Scenario: Index of the release

- **GIVEN** the release ships the lowest index version 140, and the data folder is new
- **WHEN** the app downloads the validly signed index with version 140
- **THEN** the app accepts index 140

#### Scenario: Lower floor

- **GIVEN** the app accepted index 50 with the current key, and the update ships the lowest index version 140
- **WHEN** a server delivers the validly signed index with version 60
- **THEN** the app rejects the index

#### Scenario: Higher floor

- **GIVEN** the release ships the lowest index version 140, and the app accepted index 200 with the current key
- **WHEN** a server delivers the validly signed index with version 150
- **THEN** the app keeps index 200

### Requirement: No catalog without an accepted index

The app SHALL show, install, and run nothing from the catalog while it holds no index that this build accepts: when the build has no readable keys or lowest index version, and when the stored index is below the lowest index version of the release. Extensions installed from a file still run.

#### Scenario: Stored index below the release

- **GIVEN** "Broker" 2.32 is installed from the catalog, and the app accepted index 50, which lists it
- **AND** the update ships the lowest index version 140, and the catalog cannot be reached
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" does not run, and "Broker Depot" says "Moneten has no list of extensions that this version accepts, so Broker does not run."
- **AND** the "Extensions" window shows "Broker" with the badge "Stopped" and lists no other extension of the catalog

#### Scenario: Index of the release arrives

- **GIVEN** the same app and "Broker" 2.32
- **WHEN** the app accepts index 140, which lists "Broker" 2.32
- **THEN** a refresh of "Broker Depot" runs "Broker" 2.32 again

#### Scenario: Build without its lowest index version

- **GIVEN** a build whose lowest index version cannot be read, and the app accepted index 150 before
- **WHEN** the user opens the "Extensions" window
- **THEN** the window says "This build of Moneten has no catalog keys, so it cannot show the catalog." and offers no extension of the catalog to install

### Requirement: A refresh waits for the check of the catalog

The app SHALL let a refresh of an extension of the catalog that starts while the app holds no index that this build accepts wait for the check of the catalog, for at most 30 seconds. When no check runs, the refresh starts one. After the wait, the refresh follows "No catalog without an accepted index". A refresh of an extension installed from a file does not wait.

#### Scenario: Online at launch

- **GIVEN** "Broker" 2.32 is installed from the catalog, and the app accepted index 50, which lists it
- **AND** the update ships the lowest index version 140, the catalog serves index 140, which lists "Broker" 2.32, and the Mac is online
- **AND** "Broker Depot" is due for the automatic refresh
- **WHEN** the updated app launches, and the automatic refresh starts "Broker Depot" before the check of the catalog ends
- **THEN** the refresh of "Broker Depot" waits for the check, runs "Broker" 2.32, and shows no error

#### Scenario: Offline at launch

- **GIVEN** the same app and "Broker" 2.32, and the Mac is offline
- **WHEN** the updated app launches
- **THEN** the check of the catalog fails, the automatic refresh does not start, and "Broker Depot" keeps its last state
- **WHEN** the connection returns
- **THEN** the automatic refresh of "Broker Depot" starts a check of the catalog, waits for it, and runs "Broker" 2.32 once the app accepts index 140

#### Scenario: Catalog does not answer

- **GIVEN** the same app and "Broker" 2.32, and the Mac is online, but the catalog does not answer
- **WHEN** the user chooses "Refresh Account" for "Broker Depot"
- **THEN** the refresh waits for the check of the catalog, for at most 30 seconds
- **AND** "Broker Depot" says "Moneten has no list of extensions that this version accepts, so Broker does not run."
