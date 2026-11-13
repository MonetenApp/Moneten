#!/bin/sh
# Compares App/Resources/CatalogKeys/*.pub byte for byte with keys/*.pub of the catalog repository.
# While the main branch of the catalog has no keys yet, it compares with the commit that the app copied them from.
set -e
cd "$(dirname "$0")/.."
REPO=MonetenApp/moneten-extensions
PINNED=a83d9360fe9e76754c528c26f1938f8c35625c31
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch() {
	curl -fsL -o "$WORK/$2" "https://raw.githubusercontent.com/$REPO/$1/keys/$2"
}

REF=main
if ! fetch main current.pub || ! fetch main next.pub; then
	echo "check-catalog-keys: the main branch of $REPO has no keys/current.pub and keys/next.pub yet. Comparing with the pinned commit $PINNED instead."
	REF=$PINNED
	if ! fetch "$REF" current.pub || ! fetch "$REF" next.pub; then
		echo "check-catalog-keys: cannot download keys/*.pub of $REPO at $REF." >&2
		exit 1
	fi
fi
for key in current.pub next.pub; do
	if ! cmp -s "$WORK/$key" "App/Resources/CatalogKeys/$key"; then
		echo "check-catalog-keys: App/Resources/CatalogKeys/$key differs from keys/$key of $REPO at $REF." >&2
		exit 1
	fi
done
echo "check-catalog-keys: both keys equal keys/*.pub of $REPO at $REF."
