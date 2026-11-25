# Tasks

## 1. Requirements

- [x] 1.1 An unlisted `Notes.txt` stops the package, and a regular `.DS_Store` does not. Verified by `InstallerTests/fileThatTheEntryDoesNotListBeforeASession` and `InstallerTests/finderViewSettingsDoNotStopThePackage`.
- [x] 1.2 A folder or a link named `.DS_Store` stops the package. Verified by `InstallerTests/itemNamedLikeFinderViewSettingsStopsThePackage`.
- [x] 1.3 A listed file of another size is refused before it is read. Verified by `InstallerTests/fileOfAnotherSizeIsRefusedBeforeItIsRead`, with a file that cannot be read.
