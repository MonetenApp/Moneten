#!/bin/sh
# Deletes what macOS keeps for a copy of the app that a check ran under a bundle ID of its own: the
# settings, the saved window state, the caches, and the entry of Launch Services. Usage:
# scripts/forget-bundle.sh <bundle ID> <app>. scripts/check-debug-log.sh and scripts/perf-check.sh call it
# at their end, after the app quit.
BUNDLE_ID=$1
APP=$2
case "$BUNDLE_ID" in io.github.alexander-schneider.Moneten.?*) ;; *) echo "Not a bundle ID of a check: $BUNDLE_ID" >&2; exit 1 ;; esac
defaults delete "$BUNDLE_ID" >/dev/null 2>&1
L="$HOME/Library"
rm -rf "$L/Preferences/$BUNDLE_ID.plist" "$L/Saved Application State/$BUNDLE_ID.savedState" "$L/Caches/$BUNDLE_ID" \
	"$L/HTTPStorages/$BUNDLE_ID" "$L/HTTPStorages/$BUNDLE_ID.binarycookies" "$L/WebKit/$BUNDLE_ID"
[ -d "$APP" ] && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null
exit 0
