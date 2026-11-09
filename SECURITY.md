# Security

MonetenMoneten handles bank credentials and financial data. Security reports have the highest priority.

## Report a vulnerability

Report it privately through [GitHub's private vulnerability reporting](https://github.com/alexander-schneider/monetenmoneten/security/advisories/new). Do not open a public issue.

Include the version, the steps to reproduce, and the impact you expect. The maintainers confirm receipt within three working days and publish a fix and an advisory after the fix ships.

## What the app protects

- The database is encrypted with SQLCipher. Its key is in the macOS Keychain.
- Bank PINs are in the Keychain. They never enter the database.
- Logs never contain PINs, TANs, passwords, cookies, or tokens, and no setting turns that off.
- TANs are never stored.
- Each extension runs in its own sandboxed process and can only reach the hosts in its manifest.
- The extension API has no payment functions, and the app sends payments only through FinTS or finAPI. A malicious extension could still misuse a login it holds, so catalog extensions are reviewed.

[Architecture](docs/architecture.md) explains each of these in detail.

## Supported versions

Before v1.0, only the latest release gets security fixes.
