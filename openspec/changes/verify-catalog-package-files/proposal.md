# Proposal: Say that an unlisted item stops an installed catalog package

Closes #589.

## Why

Before each run, the app checks every file of an installed catalog package and stops the package when its folder holds an item that the index does not list (#584). The Finder's `.DS_Store` is the one exception. The requirement "Digest of every file" does not say either rule. The check also read each file in full before it compared the size, so a large file put in the place of a listed one was read at every reload. And a folder or a link named `.DS_Store` passed, although the exception is meant for the file that the Finder writes.

## What Changes

- The requirement "Digest of every file" says that an item in the folder of an installed package that the index does not list stops the package, and that a regular file named `.DS_Store` does not.
- A folder or a link named `.DS_Store` stops the package.
- The app opens each file once without following a link, compares the type and the size of that open file, and reads at most one byte more than the recorded size.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extension-catalog`: "Digest of every file" names the items that the index does not list.

## Impact

- Milestone: v0.1
- Issues: #589
- Modules: `ExtensionCatalog` checks the files in `Installer.load`.
- Decisions: [ADR 0015](../../../docs/decisions/0015-extension-program.md), decision 24.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney has no signed catalog with the digests of each file, so there is nothing to compare.

### Decided for Moneten

- An installed catalog package runs only from the files that the index lists. Any other item in its folder stops it, except the view settings that the Finder writes as a regular file named `.DS_Store`.
