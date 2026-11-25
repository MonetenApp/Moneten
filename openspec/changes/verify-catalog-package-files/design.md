# Design

## Context

`Installer.load` builds the package of an installed catalog extension before each session. It checks every file that the record lists against the size and the SHA-256 of the index, and it refuses an item in the folder that the record does not list (#584). `Installer.install` checks each downloaded file the same way.

## Decisions

### The size from lstat comes first

`PackageFile.data(in:)` reads the attributes of the item without following a link. It returns nil for an item that is not a regular file or whose size is not the size of the record, before it reads anything. Only then does it read the file and compare it with `PackageFile.matches(_:)`, which `install` uses for a download too. So a large file put in the place of a listed file costs one `lstat`, not a read on the main actor.

### Only the payload of the package stays in memory

After the check, `load` keeps the bytes of `manifest.json` and of the Lua files, which `ExtensionPackage.load` builds the package from. The other files, such as `README.md` and `LICENSE`, only have to match.

### The exception is a regular file

An item that the record does not list passes only when its name is `.DS_Store` and it is a regular file. A folder or a link with that name stops the package. A missing listed file fails in `data(in:)`, so the folder needs no count of its items.
