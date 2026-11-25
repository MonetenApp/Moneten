# Tasks

## 1. Requirements

- [x] 1.1 An unlisted `Notes.txt` stops the package, and a regular `.DS_Store` does not. Verified by `InstallerTests/fileThatTheEntryDoesNotListBeforeASession` and `InstallerTests/finderViewSettingsDoNotStopThePackage`.
- [x] 1.2 A folder or a link named `.DS_Store` stops the package. Verified by `InstallerTests/itemNamedLikeFinderViewSettingsStopsThePackage`.
- [x] 1.3 A listed file of another size is refused. Verified by `InstallerTests/fileOfAnotherSizeIsRefused`.
- [x] 1.4 A pipe or a link at the path of a listed file is refused without waiting and without following the link. Verified by `InstallerTests/pipeAtTheListedPathIsRefusedWithoutWaiting` and `InstallerTests/linkAtTheListedPathIsRefused`.
