# Design

## Context

The catalog is the repository MonetenApp/moneten-extensions. Its signing workflow publishes `index.json`, the raw Ed25519 signature `index.json.sig`, and every file of a package at `<id>/<version>/<path>` on `extensions.monetenapp.com`. The index lists one manifest and one list of files with their SHA-256 for each package. The app ships `current.pub` and `next.pub` from [keys/](https://github.com/MonetenApp/moneten-extensions/tree/main/keys) of that repository. The extensions run in the host of [add-web-banking-extensions](../add-web-banking-extensions/proposal.md), through the `ExtensionConnector`.

## Decisions

- **Module.** `Sources/ExtensionCatalog` holds the rules that need tests: `CatalogIndex` parses the index, `IndexVerifier` checks the signature and the floors, `Installer` downloads and checks a package, `UpdatePlan` and `Standing` decide what an installed package may do, `FileInstall` handles file installs, and `CatalogSource` downloads. `App/Sources/Extensions/ExtensionLibrary.swift` holds the state of the window and calls them.
- **Origin in the database.** Migration `v10` stores the accepted index with the floor of each key, and each installed extension with its origin and digests, in the encrypted database. A program that writes the Extensions folder cannot change them. A record that cannot be read never makes a catalog package a file install, and an origin that the app does not know counts as the catalog.
- **What runs is what was checked.** `ExtensionPackage.load` gets each file through a reader. `Installer.load` and `FileInstall.load` compare the digests of exactly the bytes that the package was built from, as raw bytes. Only regular files count, so a symbolic link cannot bring in another file.
- **Checked at the start of a session.** The connector of a refresh or a setup resolves when the session starts (`CheckedAtStart`), so a refresh that waited behind three others runs only a package that is still installed and allowed. Accepting an index that blocks or withdraws a package, and removing a package, cancel its running and waiting refreshes (`SyncCoordinator.cancelRefresh(of:)`).
- **Only the listed version runs.** The index lists one version of each package. An installed version that is not the version of the index does not run, and the window offers its update with "Update" or "Review Update". This keeps decision 24 of ADR 0015, because only files that the accepted index signs run. The catalog may list earlier versions with their digests later. The app would then let a listed earlier version run while its update waits. Until then, an update that waits for the confirmation stops the refreshes of its accounts, and they say "Open Extensions and install the update". The confirmation says so too.
- **Version order.** Versions compare as tuples of numbers without padding, as [tools/check_package.py](https://github.com/MonetenApp/moneten-extensions/blob/main/tools/check_package.py) and [tools/build_index.py](https://github.com/MonetenApp/moneten-extensions/blob/main/tools/build_index.py) of the catalog do. So 1.0 < 1.0.0 < 1.0.1 < 1.1.
- **Confirmations.** `UpdatePlan` takes the version that the user confirmed or chose with "Update". It installs that version, also with new rights or with automatic updates off, and never a later one. A confirmation shown for one version does not install another.
- **Limits.** Catalog requests have the timeouts of the transport of extensions, 60 seconds per request and 120 seconds per resource. The index may have 4 MB, the signature 64 bytes, and each package file the size that the index lists. A body over its limit stops the download. Redirects are refused.
- **Add Account.** The assistant lists under "Other" the services of catalog packages that may run and of file installs that the user allowed. The services come from the manifest, or from `services = {...}` of the registration of a script without a manifest. The choice hands over to the setup job of `ExtensionConnector`, with the login dialog, the browser and captcha windows, and the kept setup state of a failed setup.
- **Keys.** `App/Resources/CatalogKeys/current.pub` and `next.pub` are copies of [keys/](https://github.com/MonetenApp/moneten-extensions/tree/main/keys) of the catalog. `scripts/check-catalog-keys.sh` compares them byte for byte in CI.

## Deviations

- **Change note.** The spec says that the confirmation of an update shows its change note. The index has no field for it, so the confirmation shows the new version, its new hosts, and its new login fields. A follow-up adds an optional `changes` field to the manifest schema of the catalog.
- **Unmaintained note on accounts.** The note of an unmaintained package shows in the Extensions window. An account shows a note of the refresh only when the refresh fails.
- **Earlier versions.** See "Only the listed version runs".

## Risks / Trade-offs

- The index arrives at unlock, once a day, and on "Check Now". A block reaches the app only with the next accepted index.
- Without the change note, the user judges an update by its version, hosts, and login fields.
