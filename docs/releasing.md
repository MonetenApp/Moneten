# Releasing

This page lists the secrets of the release workflow, how the owner creates each of them, and the steps of a release. The design of [add-software-update](../openspec/changes/add-software-update/design.md) explains why the pipeline works this way, and [ADR 0016](decisions/0016-developer-id-certificate-in-ci.md) explains the signing.

A release starts with a tag. `.github/workflows/release.yml` then builds the app, signs it with the Developer ID, notarizes it, puts it on a notarized disk image, signs the disk image with the update key, writes the update feed, and creates the GitHub release as a draft. The owner checks the draft and publishes it with `scripts/release.sh publish`.

## Dry run

The dry run needs no secrets and contacts no service. It builds the app signed to run locally, puts it on an unsigned disk image, checks the image as a user would get it, zips the dSYMs and checks them against the app on the image as a release does, and writes a feed signed with the test update key of `Fixtures/update`. Run it before a change to the packaging:

```sh
scripts/release.sh dry-run           # version 0.0.0-beta.1, on a copy of CHANGELOG.md
```

The dry run takes XcodeGen and the JDK from `scripts/build-tools.sh`, as a release does, and checks that Sparkle and the check of a feed agree on its signature, that a release refuses a current feed of another key, and that a withdrawal refuses an unsigned feed and a feed with a disk image over http.

A Debug build trusts the test key and reads the feed of the dry run:

```sh
scripts/build-app.sh debug
python3 -m http.server --directory dist/release --bind 127.0.0.1 8793
open --env MONETEN_FEED_URL=http://127.0.0.1:8793/appcast.xml --env MONETEN_DATA_DIR=/tmp/moneten-update dist/Moneten.app
```

`scripts/update-test-feed.sh` writes test feeds with several versions, signed with the same key, for the checks of the update window. A Debug build looks for updates only when `MONETEN_FEED_URL` is set.

The workflow runs the same dry run on each pull request that changes the packaging. A run by hand under Actions, "Release", "Run workflow", does it too. With "notarize" checked, the run by hand also signs and notarizes with the secrets of the environment `build`. It signs nothing with the update key and publishes nothing.

## Secrets

Only the owner of the repository creates and sets them, under Settings, Environments. No secret is ever printed, committed, or written to a log.

### Environment `build`

Allow the branch `main`, the tags `v*`, and the tags `ext-v*` of the [ext release](releasing-ext.md) under "Deployment branches and tags" ([ADR 0019](decisions/0019-ext-releases-in-the-build-environment.md)).

| Name | Kind | Content |
|---|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | secret | The Developer ID Application certificate with its private key, as a `.p12` file in Base64 |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | secret | The password of the `.p12` file |
| `NOTARY_API_KEY_P8` | secret | The text of the `.p8` file of the App Store Connect API key |
| `NOTARY_API_KEY_ID` | secret | The key ID of that API key |
| `NOTARY_API_ISSUER_ID` | secret | The issuer ID of the App Store Connect account |
| `FINTS_PRODUCT_ID` | secret | The FinTS product registration number of the project |
| `APPLE_TEAM_ID` | variable | The team ID of Adanos Software GmbH, ten characters |

**Developer ID certificate.** Only the Account Holder of the Apple Developer account can create it.

1. On the Mac of the owner, open Keychain Access, then Certificate Assistant, "Request a Certificate From a Certificate Authority", and save the request to disk.
2. In the Apple Developer account, Certificates, add a "Developer ID Application" certificate with the profile type "G2 Sub-CA" and upload the request.
3. Download the certificate and open it, so that Keychain Access adds it to the private key of step 1.
4. In Keychain Access, export the certificate with its private key as a `.p12` file, with a long random password.
5. Run `base64 -i Certificates.p12 | pbcopy` and paste the result as `DEVELOPER_ID_CERTIFICATE_P12`. Set the password as `DEVELOPER_ID_CERTIFICATE_PASSWORD`.
6. Keep the `.p12` file and its password in the two offline backups below, then delete the file from the Mac.

The certificate is valid for five years. Renew it before it ends with the same steps, and replace both secrets.

**App Store Connect API key.** In App Store Connect, Users and Access, Integrations, App Store Connect API, create a team key with the role "Developer". Download the `.p8` file, which Apple offers only once. Paste its whole text as `NOTARY_API_KEY_P8`, and set the key ID and the issuer ID that the page shows.

**FinTS product ID.** The Deutsche Kreditwirtschaft assigns it to the project. It goes into `Info.plist` of the release, as the build of a developer takes it from the login Keychain. A release without it fails at packaging.

### Environment `release`

Allow only the tags `v*`, and add the owner as a required reviewer. The workflow waits for this approval before it signs anything with the update key.

| Name | Kind | Content |
|---|---|---|
| `SPARKLE_ED_PRIVATE_KEY` | secret | The private EdDSA update key of Sparkle |

**Update key.** This key signs every update and the bank data files. With it alone, someone could sign an update that every installed copy accepts, so it is the most critical secret of the project.

1. Run `"$(scripts/sparkle-tools.sh)/generate_keys"` on the Mac of the owner. It stores the private key in the login Keychain and prints the public key.
2. Run `"$(scripts/sparkle-tools.sh)/generate_keys" -x update-key.txt` to export the private key, and paste the content of the file as `SPARKLE_ED_PRIVATE_KEY`.
3. Store `update-key.txt` in the two offline backups below, then delete the file.
4. In `App/project.yml`, replace the placeholder `none` of `MONETEN_UPDATE_PUBLIC_KEY` in the base settings of the target `Moneten` with the public key, and merge it in a pull request. The public key is not secret. Until then, a Release build does not look for updates, and `scripts/release.sh preflight` and `package` refuse to run. They also refuse the public test key of `Fixtures/update`, and `feed` refuses a private key that does not belong to the public key in the app.

Never create a second key for the same feed. A lost key means that every user must download the next version by hand.

### Offline backups

The owner keeps the `.p12` file with its password and the private update key in two offline backups, for example two encrypted USB drives in two places. The owner records the places outside the repository.

### Protected tags

Add a ruleset under Settings, Rules, for the tags `v*` and `ext-v*` that allows only the owner to create, update, or delete them. A tag starts a release, so nobody else may push one.

## Release a version

1. In a pull request, run `python3 scripts/release-notes.py cut 0.1.3`, or `cut 0.2.0-beta.1` for a pre-release, and check the entries in `CHANGELOG.md`. Merge it.
2. Go through the checklist below.
3. Tag the merge commit on `main` and push the tag: `git tag v0.1.3 && git push origin v0.1.3`.
4. The workflow checks that the tag has a section in `CHANGELOG.md`, that the commit is on `main`, and that the build number and the version are above every version in the current feed. Then it builds, signs, and notarizes, and zips the dSYMs of the build. It checks with `dwarfdump --uuid` that the dSYMs match the binaries of the app on the disk image, and that `scripts/symbolicate-crash.sh` resolves a frame of each binary with them.
5. Approve the job `draft` in the run within a day, because the disk image of the job `package` is kept for one day. Otherwise run the workflow again. The job checks that the update key signed the current feed and that every disk image in it lies in a release of the repository. Then it signs the disk image with the update key, writes the feed, and creates the release as a draft, with the disk image, the dSYMs as `Moneten-0.1.3-dSYMs.zip`, and `appcast.xml`.
6. Open the draft. Download the disk image on a Mac with the default security settings, open it, and start the app.
7. Run `scripts/release.sh publish 0.1.3` with the GitHub CLI logged in as the owner and OpenSSL 3 or later installed (`brew install openssl@3`, because the LibreSSL of macOS cannot check the signature of a feed). It stops when the draft lacks one of its three files. It checks the feed of the draft, the current feed, and afterwards the published feed with the update key committed in `App/project.yml`, and stops at a feed that the key did not sign. A stable version becomes the newest release and carries the feed. A pre-release is published as a pre-release, and its feed replaces `appcast.xml` on the newest stable release. The command also updates the text of each earlier release whose section in `CHANGELOG.md` changed, and leaves the others alone, and checks that the feed URL lists the new version.

The feed URL is `https://github.com/MonetenApp/Moneten/releases/latest/download/appcast.xml`. Every other release, such as `bank-data`, must be created with "Set as the latest release" turned off, or the feed URL breaks.

To start over after a failed run, delete the draft and run the workflow again on the same tag under Actions.

### Checklist

- [ ] `CHANGELOG.md` has the section of the version, and every entry is written for users.
- [ ] CI is green on the commit.
- [ ] The release candidate was tested on the newest major version of macOS, and the key `MonetenTestedMacOS` in `App/Info.plist` names that version. The app warns at launch on a newer major version of macOS.
- [ ] The production update key in `App/project.yml` is the public key of `SPARKLE_ED_PRIVATE_KEY`. `scripts/release.sh` checks this too.

## Symbolicate a crash report

A user who sends a crash report, from the crash sheet of the app or the bug report form, sends only binary names, binary UUIDs, and offsets. The dSYMs of the release turn them into function names and source lines. Every release keeps them as the asset `Moneten-<version>-dSYMs.zip`, next to its disk image. The zip holds the dSYMs of every binary in the app: the app, the extension host, SQLCipher, and Sparkle with its helpers. Only the Java runtime of the FinTS helper has none.

1. Read the version from the line "App version" of the report, for example `0.1.3 (412)`.
2. Save the report as a text file, for example `report.txt`. Keep the lines that start with "Frame:".
3. Download and unpack the dSYMs of that version:

   ```sh
   gh release download v0.1.3 --repo MonetenApp/Moneten -p 'Moneten-0.1.3-dSYMs.zip' -D /tmp/moneten-0.1.3
   ditto -x -k /tmp/moneten-0.1.3/Moneten-0.1.3-dSYMs.zip /tmp/moneten-0.1.3
   ```

4. Run `scripts/symbolicate-crash.sh report.txt /tmp/moneten-0.1.3`. It finds the dSYM of each frame by its UUID and prints the function and the source line after the frame, for example `-> AppModel.refresh() (in Moneten) (AppModel.swift:812)`.

A frame of macOS, such as SwiftUI or libsystem_kernel.dylib, prints "No matching dSYM", because only Apple has its symbols. When no frame of Moneten matches, the user ran another build than the release, for example a build from source, or the report names another version. Ask for the version in the About window. A crash of the extension host comes as a system report, `MonetenExtensionHost-*.ips` in `~/Library/Logs/DiagnosticReports`, and not from the crash sheet. Resolve its frames with `MonetenExtensionHost.dSYM` from the same zip: `atos -o MonetenExtensionHost.dSYM -arch arm64 -l <load address> <address>`, with the load address of the extension host from the list of images in the report.

The dry run makes the zip too, and checks it with the same script. `scripts/build-app.sh` writes the dSYMs of a Release build to `dist/Moneten.dSYMs`.

## Update a pinned build tool

`scripts/build-tools.sh` pins XcodeGen with its version and SHA-256, and reads the Temurin JDK from the `jdk:` line of `Tools/FinTSProbeJava/dependencies.lock`. To move to a newer build, take the version and the SHA-256 from the release page of the project, which GitHub lists beside each file, change them in one pull request, and let the dry run of that pull request build with them. A security fix of the JDK 17 line is a reason for a new release, because its runtime ships inside the app.

## Withdraw a version

Sparkle never offers an older build, so a withdrawn version needs a fixed version with a higher build number. Every feed carries a revision, and every write raises it, so an installed copy refuses a replay of the feed from before the withdrawal.

1. Run `scripts/release.sh withdraw 0.1.3` on the Mac that holds the update key in its login Keychain, with the GitHub CLI logged in as the owner and OpenSSL 3 or later installed. It downloads `appcast.xml` of the newest stable release and stops unless the update key committed in `App/project.yml` signed it and every disk image in it lies in a release of the repository, because the new signature would also cover a forged item. Then it takes the item out and raises the revision, signs the feed with `sign_update`, checks the result with the committed key, replaces `appcast.xml` on the newest stable release, and checks that the feed URL no longer lists the version. The check with the committed key matters: `SUSignedFeedFailureExpirationInterval` is 0, so a feed signed with another key in the login Keychain would stop the updates on every Mac. Never sign or upload a feed by hand: `scripts/release-notes.py remove` also refuses a feed that fails the check, but only the script checks the signed result before the upload. The command refuses to take out the last version of the feed, because a feed without items carries no revision: release the fixed version first, then withdraw the old one.
2. Mark the release page as withdrawn in its text.
3. Release the fixed version as usual.

## Replace a leaked update key

Follow the risk "The EdDSA private key leaks" in the [design](../openspec/changes/add-software-update/design.md#risks--trade-offs):

1. Create a new key pair with `generate_keys --account moneten-2`.
2. Publish at once a recovery release, signed with the old key, whose app carries the new public key and the new feed URL `appcast-2.xml`, and refuses every bank data file signed with the old key.
3. The old `appcast.xml` is then frozen: it stays signed with the old key and offers only the recovery release. Every later stable release carries this frozen `appcast.xml` next to `appcast-2.xml`, so a copy that was offline during the change still reaches the recovery release. A pre-release replaces only `appcast-2.xml`, never the frozen `appcast.xml`.
4. Replace `SPARKLE_ED_PRIVATE_KEY` and the offline backups, and announce the change.

The workflow does not automate this yet, because it has never been needed. The steps above must be done by hand with `scripts/release-notes.py` and `sign_update`. Before each upload, run `python3 scripts/release-notes.py check-feed --feed <file> --public-key <key>` on the signed file, with the old public key for `appcast.xml` and the new one for `appcast-2.xml`. A feed that the installed copies cannot check stops their updates, because `SUSignedFeedFailureExpirationInterval` is 0. Both feeds get a revision above the last one of the old feed, because every installed copy keeps the highest revision that it read.

## Replace a leaked Developer ID certificate

Revoke the certificate in the Apple Developer account, create a new one with the steps above, and replace `DEVELOPER_ID_CERTIFICATE_P12` and `DEVELOPER_ID_CERTIFICATE_PASSWORD`. Apps that were notarized before the revocation keep working. A leaked App Store Connect API key is revoked in App Store Connect and replaced the same way.
