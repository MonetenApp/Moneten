# Security review for v0.1

This report is the security review of issue #26 before the first public release.

## Summary

No finding rated medium or higher is open on main at 214a282a. No finding is rated high or critical.

- The first pass, a static review of main at acf62f71, found no critical or high finding, three medium findings, and three low ones.
- The second pass read the security-relevant changes from acf62f71 to 84692fda. It found one more medium finding, issue #399. The merge gate of its fix found another one, issue #405.
- The third pass read the security-relevant changes from 84692fda to ae7fd282. Its merge gate rated the redirect of new Keychain entries medium, issue #419, which the pass had listed as an accepted risk.
- Pull request #420 fixed issue #419, merged as 214a282a.

## Scope

The review covered the code on main that handles secrets, data from outside the app, or the code that runs:

- The database: SQLCipher, the key derivation from the database password, the random key in the Keychain, the re-key, the backup copies, the restore, and the guards against a changed or replaced file.
- The app lock: the unlock settings, their state in the database, their Keychain entries, and the lock settings.
- Saved PINs in the database, and the rule that TANs are never stored.
- Logs and crash reports.
- The FinTS helper of [ADR 0014](decisions/0014-fints-through-hbci4java.md): its process, its sandbox, the pipe and its protocol, the stored helper state, and the seal check of its files.
- The extension host of [ADR 0015](decisions/0015-extension-program.md): its sandbox, its limits, the pipe to the app, the mapping of results and challenges, and the signed catalog.
- The parsers at the edge: CSV, CAMT, MT940, the MoneyMoney migration, the answers of the FinTS helper, and the results of extensions.
- Challenge images for photoTAN and other TAN methods.
- The CSV export and the copy of rows as text.
- The update channel: Sparkle, the signed feed, failed updates, pre-releases, the warning about several copies, and the release pipeline.
- The bank list between releases (pull request #391): the download, the signature check, the key, the refusal of a bad or older file, the place of the file, and the way the FinTS helper uses it.
- The signatures and entitlements of the app, the FinTS helper, and the extension host.
- The environment variables that the app reads.

Payments and finAPI are not built and are outside this review.

## Ratings

Ratings follow the impact on a user of a release build. A medium finding does one of these:

- It lets data from a file, a bank, or an extension crash the app for good, run code with more rights than the process that parsed it, or reach the home folder.
- It lets another program of the user read a secret of the app without a prompt of macOS, or open the database without the password.

A low finding needs a program that already runs as the user and gains little from it, or it only stops the app from working.

## Findings

### Medium

| Issue | Finding | Fix |
|---|---|---|
| #324 | Sums of amounts added `Int64` values with `+`. Two hostile amounts in a CSV file, or many rows from a file-installed extension, overflowed a sum, and the app stopped at every unlock. | 7653cf46 (#330). Every edge refuses an amount above `Money.maxMinorUnits`, sums add up in `Int128`, and a sum that does not fit shows the bound instead of stopping the app. |
| #325 | The app decoded challenge images with `NSImage(data:)`, which accepts every format of ImageIO. A crafted TIFF, HEIC, or JPEG 2000 image from an extension or a bank reached a large decoder in the app, which holds the open database. | 753c7871 (#331). `ChallengeImage` lets through only PNG and JPEG by signature, at most 1 MB and 2048 pixels on each side. `ChallengePicture` checks the type and size with ImageIO again before it decodes. |
| #326 | The java of the FinTS helper ran without a sandbox. A flaw in hbci4java or JAXB, set off by a bank server, could read and change the whole home folder together with the PIN. | d95b4707 (#333) and [ADR 0018](decisions/0018-sandbox-the-fints-helper.md). The java has the app sandbox, the network client, and JIT, and nothing else. `scripts/build-app.sh` fails on other entitlements and runs a login in the sandbox against a made-up bank. |
| #399 | `Keychain.write` updated an entry that it found. Another program of the user could create the unlock entries in advance, with an access list that lets every app read them. The app then wrote the database password into that entry, and the program read it without a prompt. A new database without a password also took over a planted random key. | 52d294ce (#402). `Keychain.write` deletes the entry and adds a new one, which gets the access list that names only the app. A new database without a password always writes a new random key and never reads the old entry. The tests plant entries in a throwaway keychain file, never in the login Keychain. |
| #405 | An unlock setting counted as on while its Keychain entry existed. Another program of the user could create the entry of the automatic unlock with any text. The next unlock with the password wrote the real password into it, and the database then opened at every launch without a password. | ae7fd282 (#414). The table `unlockMethod` of the encrypted database holds the settings that are on. An entry of a setting that is off never counts and is deleted at the next unlock with the password. An open with a password from the Keychain checks every offered setting against the database and closes the database again when one is off. |
| #419 | `Keychain.write` adds an entry without `kSecUseKeychain`, so it lands in the default keychain of the user, and a read searches the search list of the user. A program of the user can make a keychain file of its own the default and put it in the search list, which macOS allows without a prompt. It then plants an entry with a wrong password for an unlock setting that is on. At the next unlock with the password, the app finds the entry stale and writes the real database password into that file, whose password the program knows. A new database without a password writes its random key there the same way. | 214a282a (#420). Every add, read, and delete uses the login keychain, opened by a path from the user database, and nothing falls back to the default keychain. |

### Low

| Issue | Finding | Status |
|---|---|---|
| #327 | A release build read `MONETEN_DATA_DIR`, so another process of the user could make the app open a database that the user did not create. | Fixed in e595780c (#332). Only Debug and Perf builds read the variable. |
| #327 | A removed saved PIN could stay in free pages of the database. | Fixed in e595780c (#332), with a test in 4efee115 (#342). `PRAGMA secure_delete` is on for every connection. SQLCipher already turned it on, so older databases hold no removed PIN either. |
| #327 | The filter of the stored helper state had no limits, so a crafted state could exhaust the memory or the stack of the helper. | Fixed in e595780c (#332). The filter has `maxdepth=20`, `maxarray=100000`, and `maxrefs=100000`. |
| #416 | A planted Touch ID entry with a wrong password makes the Apple Watch path fail until the user types the password. It never unlocks. | Open, a follow-up of #414 together with two text fixes. |
| #422 | The data folder follows the environment variable `CFFIXED_USER_HOME`, so another program of the user can make a release build open another data folder, as #327 described for `MONETEN_DATA_DIR`. No secret leaks. Found in the merge gate of #420, which already takes the login keychain from the user database. | Open. |

## What each pass read

### First pass, main at acf62f71

A static review of every area of the scope. Issue #26 has its summary. Five pull requests that were open then are merged now and were read in the second pass: #266, #269, #273, #293, and #313.

### Second pass, acf62f71 to 84692fda

The pass read the diffs of the fixes of the first pass (#330 to #333) and of the pull requests that the first pass left open: the safe open, upgrade, and restore of the database (#266), the security settings behind the password (#269), the release pipeline (#273), Sparkle (#293), and the helper line length (#313). It found #399.

### Third pass, 84692fda to ae7fd282

- **Bank list between releases (#391).** `BankDataUpdater` downloads `blz.properties` and its signature once a day, and again at the first launch of each new build, only over https, and follows a redirect only to another https address. A list has at most 8 MB and a signature at most 1 KB. `BankData.verify` checks the Ed25519 signature with CryptoKit against `SUPublicEDKey` in Info.plist, the update key, which the code signature of the app seals. A list must read as a bank list and carry a header with a serial and the version of hbci4java inside the signed bytes. The app refuses a list whose serial is not above the installed one, or that comes from an older jar than its own. A replay of an older signed list therefore fails. A failed download, a wrong signature, or a list that does not read keeps the installed files. The files lie in the folder "Bank Data" of the data folder, mode 0700, and a new version replaces the folder in one rename. The app checks the signature again before each start of the helper and sends the list through the pipe. The helper reads it with `Properties` and keeps the list of its jar when it fails. Only Debug and Perf builds read `MONETEN_BANK_DATA_URL` or ask a server over http on this Mac. The workflow `bank-data.yml` signs only from `main`, with a pinned jar and pinned Sparkle tools. The approval of the owner comes from the environment `bank-data`, which does not exist yet; see [Before the first release](#before-the-first-release). No finding in the code.
- **Failed updates and pre-releases (#392).** A failed automatic check stays silent, and a failed installation shows the release page. A pre-release comes only from the channel `beta` of the signed feed, so it needs the update key too. No finding. The settings in the user defaults are an accepted risk below.
- **Warning about several copies (#407).** The lookup runs off the main actor and reads only the code signature of each copy. The team ID goes into a code requirement only when it holds letters and digits. No finding.
- **Keychain entries (#402) and the unlock state (#414).** The pass checked both against the attack of each issue, a crash between two steps, and a failed write. The remaining point is #416. #420 fixed #419.
- **One savepoint per write (#317).** A failed write rolls back to a savepoint and commits an empty transaction, so the store no longer counts its own rollback as a change of another program. The check against a change on disk still runs under the write lock before each write, and a test shows that a later write of another program still stops every write. No finding.
- **Other changes.** The regex limit of rules (#400) and the dSYMs of a release (#401) were read. The dSYMs hold the symbols of open source code and no secret. No finding.
- **Licenses and source archives (#415).** The pull request was open at the end of the pass. Only its release pipeline was read, at 4cb19110: the source archives come from https URLs with a pinned SHA-256, the cache of the workflow holds only those archives and is checked again, and `publish` refuses a release without them. No finding.

## Accepted risks

These risks stay in v0.1. Each one was checked again on main at ae7fd282.

- **Keychain.** The login Keychain of macOS is a file-based Keychain. It ignores `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which the entries ask for, and any program of the user can read an entry of the app after macOS asks. The redirect of a new entry without a prompt was issue #419, fixed by 214a282a (#420).
- **Touch ID and the Apple Watch.** The app asks macOS for the confirmation, and the Keychain entry has no access control of its own. A program of the user that asks the Keychain for the entry gets the prompt of the Keychain, not a request for Touch ID. A planted entry never turns on a setting that is off in the database of the user, because the open checks the setting in the database that opened.
- **Database file.** A program of the user can delete or replace the files and the Keychain entries of the app. The app then refuses to open or asks for the password. A program that replaces the database with one of its own and plants a matching entry for the automatic unlock can make the app open that database. The program knows its key, so it can read a bank login or PIN that the user then types or saves there. The rating stays low: the user sees all own accounts and transactions gone, because the program cannot read the real database to copy them, and a program of the user can show a false window of its own anyway.
- **Extension host.** The host checks its list of hosts in the process that runs the script, so a flaw in Lua or in a parser of the host could get around it. ADR 0015 accepts this. The sandbox of the process still keeps the script away from every file.
- **Logs.** The app has no log file and no central layer that removes secrets from log lines. It writes a few status lines to the system log of macOS and to its standard error: fixed words, counts, and error codes, with no names, amounts, paths, or secrets. The FinTS helper masks its own diagnostics before it writes them. The `ext` tool for extension authors prints what an extension prints, unchanged. The app drops that output, and the debug harness logs only its length.
- **One key for updates and bank data.** The update key signs the updates, the feed, and the bank list. The design of add-software-update decides this. The bank list carries the FinTS address of each bank, where the helper sends the PIN, so a list signed with a stolen key could send a PIN to another server. The key also sits in two environments, `release` and `bank-data`. The rating stays low, because the same key signs the whole app, and a stolen key could ship any code. The formats differ, so a signature of one file never passes as a signature of another kind: a bank list must consist of lines with a Bankleitzahl.
- **Serial of the bank list.** A signed list with a serial far in the future would block every later list until the folder "Bank Data" is removed. Only the update key can sign such a list. The design of add-software-update accepts this.
- **Update settings.** The automatic update check, the setting for pre-releases, and `highestFeedRevision`, the floor against a replayed older feed, live in the user defaults. A program of the user can turn the check off, offer pre-releases, or reset the floor so that the app reads an older signed feed and misses newer versions. Every update, also a pre-release, must carry the signature of the update key, and Sparkle never installs a build below the installed one.

## Not checked

- Anything that needs a person or real hardware: a real Touch ID or Apple Watch confirmation, and the prompts of the login Keychain for a build signed with Developer ID.
- Real banks. The FinTS tests replay recorded or made-up answers.
- The SSL socket factory and the XML entity handling of hbci4java.
- A notarized Developer ID build, and a release with the production update key. `App/project.yml` has no production update key yet, so the updater and the bank list download of a release build were checked only with the test key and in tests.
- The published bank list. The release `bank-data` does not exist yet.
- Fuzzing of the parsers.
- Third-party code beyond its pins: the fork of GRDB that links SQLCipher, the installer and XPC services of Sparkle, the bundled Java runtime, Lua, and hbci4java beyond the parts named above.

## Before the first release

- Create the environments `build`, `release`, and `bank-data` with their secrets and the owner as required reviewer, as `docs/releasing.md` says, and protect the branch `main`. The repository has no environment yet, so today only the check for `main` in `bank-data.yml` and the check for a missing secret hold, and the second one fails closed.
- Put the production update key into `App/project.yml`.
