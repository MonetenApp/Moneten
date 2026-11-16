#!/bin/sh
# Deletes what macOS keeps for a copy of the app that a check ran under a bundle ID of its own: the
# settings, the saved window state, the caches, and the entry of Launch Services. Usage:
# scripts/forget-bundle.sh <bundle ID> <app>. scripts/check-debug-log.sh and scripts/perf-check.sh call it
# at their end, after the app quit.
BUNDLE_ID=$1
APP=$2
# Only the two forms that the checks make pass, with the random part of their work folder as the suffix.
# The suffix holds only letters and digits, so no ID of the app, of its extension host, or with ".." passes.
case "$BUNDLE_ID" in
io.github.alexander-schneider.Moneten.check-debug-log.*) SUFFIX=${BUNDLE_ID#io.github.alexander-schneider.Moneten.check-debug-log.} ;;
io.github.alexander-schneider.Moneten.perf-check.*) SUFFIX=${BUNDLE_ID#io.github.alexander-schneider.Moneten.perf-check.} ;;
*) SUFFIX= ;;
esac
case "$SUFFIX" in
'' | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*) echo "Not a bundle ID of a check: $BUNDLE_ID" >&2; exit 1 ;;
esac
defaults delete "$BUNDLE_ID" >/dev/null 2>&1
L="$HOME/Library"
rm -rf "$L/Preferences/$BUNDLE_ID.plist" "$L/Saved Application State/$BUNDLE_ID.savedState" "$L/Caches/$BUNDLE_ID" \
	"$L/HTTPStorages/$BUNDLE_ID" "$L/HTTPStorages/$BUNDLE_ID.binarycookies" "$L/WebKit/$BUNDLE_ID"
[ -d "$APP" ] && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null
exit 0
