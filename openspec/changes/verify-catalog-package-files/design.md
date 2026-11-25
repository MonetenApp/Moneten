# Design

## Context

`Installer.load` builds the package of an installed catalog extension before each session. It checks every file that the record lists against the size and the SHA-256 of the index, and it refuses an item in the folder that the record does not list (#584). `Installer.install` checks each downloaded file the same way.

## Decisions

### One descriptor for the check and the read

`PackageFile.data(in:)` opens the file once with `O_NOFOLLOW` and `O_NONBLOCK`, so a link fails at the open and a pipe does not wait for a writer. It takes the type and the size from `fstat` of that descriptor and returns nil for an item that is not a regular file or whose size is not the size of the record. Then it reads at most one byte more than the record and compares the bytes with `PackageFile.matches(_:)`, which `install` uses for a download too. The check and the read use the same open file, so another program cannot swap the file between them, and a file that grows is never read past the recorded size. So a large file in the place of a listed file costs one `open`, not a read on the main actor.

`load` keeps the bytes of every checked file, and `ExtensionPackage.load` gets the ones that it builds the package from.

### The exception is a regular file

An item that the record does not list passes only when its name is `.DS_Store` and it is a regular file. A folder or a link with that name stops the package. A missing listed file fails at the open in `data(in:)`, so the folder needs no count of its items.
