# Security

Moneten handles bank credentials and financial data. Security reports have the highest priority.

## Report a vulnerability

Report it privately through [GitHub's private vulnerability reporting](https://github.com/MonetenApp/Moneten/security/advisories/new). Do not open a public issue.

Include the version, the steps to reproduce, and the impact you expect. The maintainers confirm receipt within three working days and publish a fix and an advisory after the fix ships.

## What the app protects

- The database is encrypted with SQLCipher. Its key comes from your database password. Until you set one, a random key in the Keychain protects the database.
- You can make the app lock after a set time without activity or when the main window closes. It then opens only with the password, or with Touch ID or an Apple Watch if you turn that on.
- Touch ID and automatic unlocking need the password saved in your login Keychain. In this build, Touch ID is checked by the app, not by the Keychain item. A program that runs under your user account and changes the app's settings can therefore unlock it without Touch ID. Do not save the password if that matters to you.

Bank access, extensions, and payments are not built yet. When they arrive, these rules apply:

- Bank PINs are saved only if you choose, and then only inside the encrypted database.
- Logs never contain PINs, TANs, passwords, cookies, or tokens, and no setting turns that off.
- TANs are never stored.
- Each extension runs in its own sandboxed process and can only reach the hosts in its manifest.
- The extension API has no payment functions, and the app sends payments only through FinTS or finAPI. A malicious extension could still misuse a login it holds, so catalog extensions are reviewed.

[Architecture](docs/architecture.md) explains each of these in detail.

## Supported versions

Before v1.0, only the latest release gets security fixes.
