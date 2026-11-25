## ADDED Requirements

### Requirement: A new data folder refuses an index older than the release

The app SHALL refuse, while neither shipped key has a floor, as in a new data folder, an index whose version is below the lowest index version of the release. Each release raises that version to the version of the newest index that the catalog signed before the release, and never lowers it. A floor that the app holds still decides when it is higher.

#### Scenario: Index older than the release

- **GIVEN** the release ships the lowest index version 140, and the data folder is new
- **WHEN** a server delivers the validly signed index with version 139
- **THEN** the app rejects the index and offers no extension of the catalog

#### Scenario: Index of the release

- **GIVEN** the release ships the lowest index version 140, and the data folder is new
- **WHEN** the app downloads the validly signed index with version 140
- **THEN** the app accepts index 140

#### Scenario: A higher floor still decides

- **GIVEN** the release ships the lowest index version 140, and the app accepted index 200 with the current key
- **WHEN** a server delivers the validly signed index with version 150
- **THEN** the app keeps index 200
