# Releasing

This page lists the secrets of the release workflow, how the owner creates each of them, and the steps of a release. The design of [add-software-update](../openspec/changes/add-software-update/design.md) explains why the pipeline works this way, and [ADR 0016](decisions/0016-developer-id-certificate-in-ci.md) explains the signing.

A release starts with a tag. `.github/workflows/release.yml` then builds the app, signs it with the Developer ID, notarizes it, puts it on a notarized disk image, signs the disk image with the update key, writes the update feed, and creates the GitHub release as a draft. The owner checks the draft and publishes it with `scripts/release.sh publish`.

## Dry run

The dry run needs no secrets and contacts no service. It builds the app signed to run locally, puts it on an unsigned disk image, checks the image as a user would get it, and writes a feed signed with the test update key of `Fixtures/update`. Run it before a change to the packaging:

```sh
scripts/release.sh dry-run           # version 0.0.0-beta.1, on a copy of CHANGELOG.md
```

The dry run takes XcodeGen and the JDK from `scripts/build-tools.sh`, as a release does, and checks that the check of the current feed refuses a changed feed, a feed of another key, and a disk image over http.

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

Allow the branch `main` and the tags `v*` under "Deployment branches and tags".

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

Add a ruleset under Settings, Rules, for the tags `v*` that allows only the owner to create, update, or delete them. A tag starts a release, so nobody else may push one.

## Release a version

1. In a pull request, run `python3 scripts/release-notes.py cut 0.1.3`, or `cut 0.2.0-beta.1` for a pre-release, and check the entries in `CHANGELOG.md`. Merge it.
2. Go through the checklist below.
3. Tag the merge commit on `main` and push the tag: `git tag v0.1.3 && git push origin v0.1.3`.
4. The workflow checks that the tag has a section in `CHANGELOG.md`, that the commit is on `main`, and that the build number and the version are above every version in the current feed. Then it builds, signs, and notarizes.
5. Approve the job `draft` in the run within a day, because the disk image of the job `package` is kept for one day. Otherwise run the workflow again. The job checks that the update key signed the current feed and that every disk image in it lies in a release of the repository. Then it signs the disk image with the update key, writes the feed, and creates the release as a draft, with the disk image and `appcast.xml`.
6. Open the draft. Download the disk image on a Mac with the default security settings, open it, and start the app.
7. Run `scripts/release.sh publish 0.1.3` with the GitHub CLI logged in as the owner. It checks the feed of the draft, the current feed, and afterwards the published feed with the update key committed in `App/project.yml`, and stops at a feed that the key did not sign. A stable version becomes the newest release and carries the feed. A pre-release is published as a pre-release, and its feed replaces `appcast.xml` on the newest stable release. The command also updates the text of each earlier release whose section in `CHANGELOG.md` changed, and leaves the others alone, and checks that the feed URL lists the new version.

The feed URL is `https://github.com/MonetenApp/Moneten/releases/latest/download/appcast.xml`. Every other release, such as `bank-data`, must be created with "Set as the latest release" turned off, or the feed URL breaks.

To start over after a failed run, delete the draft and run the workflow again on the same tag under Actions.

### Checklist

- [ ] `CHANGELOG.md` has the section of the version, and every entry is written for users.
- [ ] CI is green on the commit.
- [ ] The release candidate was tested on the newest major version of macOS, and the key `MonetenTestedMacOS` in `App/Info.plist` names that version. The app warns at launch on a newer major version of macOS.
- [ ] The production update key in `App/project.yml` is the public key of `SPARKLE_ED_PRIVATE_KEY`. `scripts/release.sh` checks this too.

## Update a pinned build tool

`scripts/build-tools.sh` pins XcodeGen with its version and SHA-256, and reads the Temurin JDK from the `jdk:` line of `Tools/FinTSProbeJava/dependencies.lock`. To move to a newer build, take the version and the SHA-256 from the release page of the project, which GitHub lists beside each file, change them in one pull request, and let the dry run of that pull request build with them. A security fix of the JDK 17 line is a reason for a new release, because its runtime ships inside the app.

## Withdraw a version

Sparkle never offers an older build, so a withdrawn version needs a fixed version with a higher build number.

1. Take the item out of the feed: download `appcast.xml` of the newest stable release, run `python3 scripts/release-notes.py remove 0.1.3 --feed appcast.xml --out appcast.xml`, sign it with `"$(scripts/sparkle-tools.sh)/sign_update" appcast.xml`, which reads the update key from the login Keychain, and upload it to the same release with `gh release upload <tag> appcast.xml --clobber`.
2. Mark the release page as withdrawn in its text.
3. Release the fixed version as usual, and soon. An installed copy that saw the withdrawn version refuses every feed whose newest build is lower than the one it saw, so it offers no update until the fixed version is in the feed.

## Replace a leaked update key

Follow the risk "The EdDSA private key leaks" in the [design](../openspec/changes/add-software-update/design.md#risks--trade-offs):

1. Create a new key pair with `generate_keys --account moneten-2`.
2. Publish at once a recovery release, signed with the old key, whose app carries the new public key and the new feed URL `appcast-2.xml`, and refuses every bank data file signed with the old key.
3. The old `appcast.xml` is then frozen: it stays signed with the old key and offers only the recovery release. Every later stable release carries this frozen `appcast.xml` next to `appcast-2.xml`, so a copy that was offline during the change still reaches the recovery release. A pre-release replaces only `appcast-2.xml`, never the frozen `appcast.xml`.
4. Replace `SPARKLE_ED_PRIVATE_KEY` and the offline backups, and announce the change.

The workflow does not automate this yet, because it has never been needed. The steps above must be done by hand with `scripts/release-notes.py` and `sign_update`.

## Replace a leaked Developer ID certificate

Revoke the certificate in the Apple Developer account, create a new one with the steps above, and replace `DEVELOPER_ID_CERTIFICATE_P12` and `DEVELOPER_ID_CERTIFICATE_PASSWORD`. Apps that were notarized before the revocation keep working. A leaked App Store Connect API key is revoked in App Store Connect and replaced the same way.
