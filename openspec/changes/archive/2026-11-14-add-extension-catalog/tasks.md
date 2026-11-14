# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Browse the catalog in the Extensions window. `ExtensionsWindow` with "Installed" and "Available". Verified by live lane 1 and the PerfCheck scenario `open-extensions-window`.
- [x] 1.2 Details before installing. `ExtensionDetails` with services, login labels, hosts, license, and the repository link. Verified by live lane 2.
- [x] 1.3 Install from the catalog. `Installer.install`, `ExtensionLibrary.install`, and the services under "Other" in the Add Account assistant. Verified by `InstallerTests` (download that stops halfway, record before the files) and the live Add Account lane.
- [x] 1.4 Signed index. `IndexVerifier`. Verified by `IndexVerifierTests` (tampered index, next key, unknown key, current key after the switch) and live lanes 3 and 10.
- [x] 1.5 Digest of every file. `Installer.install` and `Installer.load`. Verified by `InstallerTests` (digest mismatch at download, changed script, changed manifest, manifest of the index, byte order mark, symbolic link) and live lane 4.
- [x] 1.6 Only the listed version runs. Earlier versions in the index are issue #125. Verified by `UpdatePlanTests/versionThatTheIndexNoLongerListsStops` and live lane 7.
- [x] 1.7 Index version floor. `KeyFloors`. Verified by `IndexVerifierTests` (index 95 after 120, same version with other content, leaked current key) and live lane 5.
- [x] 1.8 An app update resets the floor of retired keys. `KeyFloors.keeping`. Verified by `IndexVerifierTests` (app update with new keys, shipped minimum only while neither key has a floor).
- [x] 1.9 Catalog extensions and file installs. Migration `v10`, `InstalledOrigin`, and `FileInstall`. Verified by `FileInstallTests`, `CatalogStoreTests`, and live lane 9.
- [x] 1.10 Stopped extension on an account. `ExtensionLibrary.verifiedPackage` and `CheckedAtStart`. Verified by `CheckedAtStartTests` and live lanes 4 and 8.
- [x] 1.11 Look for updates. `ExtensionLibrary.checkNow` at unlock, once a day, and on "Check Now". Verified by live lanes 6 and 7.
- [x] 1.12 Install updates. `UpdatePlan`. Verified by `UpdatePlanTests` (removed host, running session, automatic updates off, confirmed version) and live lane 6.
- [x] 1.13 An update that asks for new rights waits. The confirmation shows the version, the new hosts, and the new login fields. The change note is issue #125. Verified by `UpdatePlanTests` (new host, new login field, newer version needs its own confirmation) and live lane 7.
- [x] 1.14 Remove a catalog extension. `ExtensionLibrary.remove`, which cancels the refreshes and a running download. Verified by `InstallerTests/removalDuringTheDownloadPlacesNothing`, `SyncCoordinatorTests/cancelOneAccess`, and live lane 4.
- [x] 1.15 Blocked, withdrawn, and unmaintained extensions. `Standing`. Verified by `UpdatePlanTests` and live lane 8.
- [x] 1.16 Catalog not reachable. Verified by live lane 5.
- [x] 1.17 Catalog requests carry no personal data. `CatalogSource`. Verified by `CatalogSourceTests` (no cookie, no query, limits, no redirect) and the request log of live lane 2.
- [x] 1.18 Catalog packages need a manifest. `CatalogIndex.Entry`. Verified by `IndexVerifierTests/manifestWithoutHostsIsNotInstallable`.
