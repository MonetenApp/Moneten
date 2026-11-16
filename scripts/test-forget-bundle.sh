#!/bin/sh
# Checks that scripts/forget-bundle.sh deletes only what a check left under its own bundle ID. It runs
# with a throwaway HOME and a fake `defaults` that only records its arguments, so it touches no real
# settings, even when the script under test is wrong.
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/Library/Preferences" "$T/home/Library/Caches"
printf '#!/bin/sh\necho "$*" >> "%s/defaults.log"\n' "$T" > "$T/bin/defaults"
chmod +x "$T/bin/defaults"
L="$T/home/Library"
APP=io.github.alexander-schneider.Moneten
# What the installed app and its extension host keep, and a folder that a path with ".." would pass through.
for id in "$APP" "$APP.ExtensionHost" "$APP.check-debug-log.x"; do
	touch "$L/Preferences/$id.plist"
	mkdir -p "$L/Caches/$id"
done
forget() { HOME="$T/home" PATH="$T/bin:$PATH" scripts/forget-bundle.sh "$1" "$T/no.app" 2>/dev/null; }
failed=0
for id in "$APP" "$APP.ExtensionHost" "$APP.check-debug-log.x/../$APP" "$APP.perf-check.x/../../Preferences/$APP" \
	"$APP.check-debug-log." "$APP.perf-check." "$APP.check-debug-log.a-b" "$APP.perf-check.a b" "$APP.check-debug-log" "$APP.other.abc123"; do
	if forget "$id"; then echo "forget-bundle.sh accepted $id" >&2; failed=1; fi
done
[ ! -e "$T/defaults.log" ] || { echo "forget-bundle.sh ran defaults for a refused ID: $(cat "$T/defaults.log")" >&2; failed=1; }
for id in "$APP.check-debug-log.Xf9aut" "$APP.perf-check.e73IZI01"; do
	touch "$L/Preferences/$id.plist"
	mkdir -p "$L/Caches/$id"
	forget "$id" || { echo "forget-bundle.sh refused $id" >&2; failed=1; }
	[ ! -e "$L/Preferences/$id.plist" ] && [ ! -e "$L/Caches/$id" ] || { echo "forget-bundle.sh left the files of $id" >&2; failed=1; }
done
[ "$(cat "$T/defaults.log" 2>/dev/null)" = "delete $APP.check-debug-log.Xf9aut
delete $APP.perf-check.e73IZI01" ] || { echo "forget-bundle.sh ran defaults with other arguments" >&2; failed=1; }
for id in "$APP" "$APP.ExtensionHost" "$APP.check-debug-log.x"; do
	[ -e "$L/Preferences/$id.plist" ] && [ -d "$L/Caches/$id" ] || { echo "forget-bundle.sh deleted the files of $id" >&2; failed=1; }
done
[ "$failed" = 0 ] && echo "forget-bundle.sh refuses every bundle ID that is not of a check."
exit "$failed"
