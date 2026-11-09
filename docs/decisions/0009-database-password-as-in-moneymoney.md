# 0009. Protect the database with a password and save PINs only on request, as MoneyMoney does

Status: Accepted

## Context

MoneyMoney encrypts its database with a key that comes from a database password. Saving that password in the macOS Keychain is optional. PINs are saved only if the user chooses. Otherwise MoneyMoney asks for them once per launch ([security page](https://moneymoney.app/security/)). Its settings offer to unlock automatically at launch, with Touch ID, or with an Apple Watch, and to lock after a time without activity or when the main window closes.

The first plan for MonetenMoneten kept a random key and all PINs in the Keychain. That is convenient, but then anyone who can use the unlocked macOS account can also open the finances. MoneyMoney users expect the stronger model they already know.

## Decision

- The database password is the key. SQLCipher derives the key from it with its defaults, PBKDF2-HMAC-SHA512 with 256,000 iterations ([SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)).
- The app asks for the password at first launch. A user can skip that step. Until a password is set, the app uses a random key in the Keychain and shows a hint in the sidebar.
- The password can be changed later. The app re-encrypts the database with `PRAGMA rekey`.
- Saving the password in the Keychain is optional. Three settings use it: unlock automatically at launch, unlock with Touch ID, and unlock with an Apple Watch. When all three are off, the app deletes the password from the Keychain.
- The app locks after a set time without activity, and optionally when the main window closes.
- A PIN is saved only when the user turns on saving for that connection. A saved PIN lives in the encrypted database, not in the Keychain. Without saving, the app asks once and keeps the PIN in memory until the app locks or quits.
- TANs are never saved.

This replaces the key handling in [ADR 0005](0005-grdb-and-sqlcipher.md). The choice of GRDB and SQLCipher stays.

## Consequences

- A forgotten database password means lost data. The app says so when the user sets the password.
- A backup is a copy of the encrypted database and opens with the same password on any Mac.
- Automatic refresh works only for connections with a saved PIN, or with a PIN entered since the app was last unlocked.
- Unlocking takes a noticeable fraction of a second because of the key derivation. That is intended.
