## MODIFIED Requirements

### Requirement: Digest of every file

The app SHALL compare the SHA-256 digest of every file of a catalog package with the accepted index: a download with the entry of the downloaded version, and an installed package before each run with the entry of the installed version. A package with a file that does not match is not installed and does not run. An installed package also does not run while its folder holds an item that the index does not list. A regular file named `.DS_Store`, which the Finder writes, is the one exception.

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

#### Scenario: File that the index does not list

- **GIVEN** the catalog extension "Broker" is installed
- **WHEN** a program writes `Notes.txt` into the folder of "Broker" and a refresh starts
- **THEN** the script does not run
- **AND** the accounts and the "Extensions" window show that "Broker" was changed and does not match the catalog

#### Scenario: Finder view settings

- **GIVEN** the catalog extension "Broker" is installed and its files match the index
- **WHEN** the Finder writes a `.DS_Store` file into the folder of "Broker" and a refresh starts
- **THEN** "Broker" runs
