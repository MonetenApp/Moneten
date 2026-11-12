#!/bin/sh
# Writes the Public Suffix List at the commit of github.com/publicsuffix/list named in
# Sources/ExtensionHost/PublicSuffix/VERSION into PublicSuffixList.swift next to it, after a check of
# its SHA-256. The text stays unchanged, with the notice of the Mozilla Public License 2.0 in its first
# lines, so the Swift file is under that license. The cookie jar of the host reads it (ADR 0015).
#   scripts/vendor-public-suffix.sh           replace the list
#   scripts/vendor-public-suffix.sh --check   fail when the vendored file differs from the list
set -e
cd "$(dirname "$0")/.."
DIR=Sources/ExtensionHost/PublicSuffix
COMMIT=$(sed -n 1p "$DIR/VERSION")
SHA256=$(sed -n 2p "$DIR/VERSION")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -sSfL -o "$WORK/list.dat" "https://raw.githubusercontent.com/publicsuffix/list/$COMMIT/public_suffix_list.dat"
echo "$SHA256  $WORK/list.dat" | shasum -a 256 -c >/dev/null
{
	echo "// The Public Suffix List at commit $COMMIT of github.com/publicsuffix/list,"
	echo "// written by scripts/vendor-public-suffix.sh. The text between the quotes is unchanged."
	echo 'let publicSuffixList = #"""'
	cat "$WORK/list.dat"
	echo '"""#'
} > "$WORK/PublicSuffixList.swift"
if [ "$1" = "--check" ]; then
	cmp -s "$WORK/PublicSuffixList.swift" "$DIR/PublicSuffixList.swift" || { echo "$DIR/PublicSuffixList.swift differs from the list at $COMMIT." >&2; exit 1; }
	echo "$DIR/PublicSuffixList.swift matches the list at $COMMIT."
	exit 0
fi
cp "$WORK/PublicSuffixList.swift" "$DIR/PublicSuffixList.swift"
echo "Vendored the Public Suffix List at $COMMIT into $DIR."
