# Test update key

`test-update.key` is the private half of the test update key, an Ed25519 seed in the key format of Sparkle. It is public on purpose. Only a Debug build trusts it, and a Debug build looks for updates only in the feed that the environment variable `MONETEN_FEED_URL` names. A Release build carries the production key or the placeholder, and `scripts/release.sh` refuses to package a release with this key.

`scripts/release.sh dry-run` signs its disk image and feed with this key, so a Debug build can read the feed of a dry run. `scripts/update-test-feed.sh` builds the test feeds of the tasks of add-software-update with it.
