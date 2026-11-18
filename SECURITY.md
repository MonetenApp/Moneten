# Security

Moneten handles bank credentials and financial data. Security reports have the highest priority.

## Report a vulnerability

Report it privately through [GitHub's private vulnerability reporting](https://github.com/MonetenApp/Moneten/security/advisories/new). Do not open a public issue.

Include the version, the steps to reproduce, and the impact you expect. The maintainers confirm receipt within three working days and publish a fix and an advisory after the fix ships.

## What the app protects

- The database is encrypted with SQLCipher. Its key comes from your database password. Until you set one, a random key in the Keychain protects the database.
- You can make the app lock after a set time without activity or when the main window closes. It then opens only with the password, or with Touch ID or an Apple Watch if you turn that on.
- Automatic unlocking, Touch ID, and the Apple Watch need the password saved in your login Keychain. The encrypted database records which of these settings are on, so a Keychain entry that another program creates never turns on a setting that is off in your database. Touch ID is checked by the app, not by the Keychain entry. The [accepted risks](docs/security-review-v0.1.md#accepted-risks) explain what that means. Do not save the password if that matters to you.
- Bank PINs are saved only if you choose, and then only inside the encrypted database.
- TANs are never stored.
- The app has no log file. The [accepted risks](docs/security-review-v0.1.md#accepted-risks) list what it, the FinTS helper, and the `ext` tool write.
- The FinTS helper, which holds the PIN and reads the answers of the bank, runs in its own sandboxed process. It reaches the network and reads its own files in the app, and cannot read or change your other files or the database.
- Each extension runs in its own sandboxed process without file access. An extension with a manifest reaches only the hosts in its manifest. An extension without one asks you before it contacts each new host. The host check runs in the extension's own process, so a flaw in Lua or in a parser of the app could get around it.
- Automated checks and a maintainer review every catalog extension. The app installs one only from a signed index whose digests match every file. An update that adds a host or a login field waits for your confirmation.
- Nobody from the project reviews an extension that you install from a file. The app warns you before it runs one, lists the hosts of its manifest, warns again when any of its files changes, and marks it "Unverified".
- Extensions only read data. The extension API has no payment functions. A malicious extension could still misuse a login it holds, which is why the catalog reviews every package.
- The app installs an update and a new bank list only when the update key of the project signed them. It refuses an older bank list than the one it has.

[Architecture](docs/architecture.md) explains each of these in detail.

## Planned

- Payments are not built yet. The app will send them only through FinTS or finAPI.
- Issue #419: another program of the user can redirect a new Keychain entry of the app into a keychain file of its own. The fix comes before the first release.

## Security review

The [security review for v0.1](docs/security-review-v0.1.md) lists every finding with its fix, the risks that v0.1 accepts, and what the review did not check.

## Supported versions

Before v1.0, only the latest release gets security fixes.
