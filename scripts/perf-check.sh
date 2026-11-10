#!/bin/sh
# Runs the UI performance scenarios of App/Sources/PerfCheck.swift in the optimized Perf build.
# A scenario over the half second of the spec is reported as slow. The script fails when a scenario
# hangs past the limit, a table misses rows, or the app dies.
# The app runs with a temporary data folder, so it never opens the real database.
set -e
cd "$(dirname "$0")/.."
scripts/generate-project.sh
xcodebuild -project App/MonetenMoneten.xcodeproj -scheme MonetenMoneten -configuration Perf -derivedDataPath .build/xcode \
	-disableAutomaticPackageResolution -quiet build
APP=.build/xcode/Build/Products/Perf/MonetenMoneten.app

NOTIFY=.build/perf-notify
if [ ! -x "$NOTIFY" ] || [ scripts/perf-check.sh -nt "$NOTIFY" ]; then
	cat > "$NOTIFY.swift" <<-'EOF'
	import Foundation
	let a = CommandLine.arguments
	DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.monetenmoneten.debug"), object: a[1],
		userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)
	EOF
	swiftc -o "$NOTIFY" "$NOTIFY.swift"
fi

WORK="$(mktemp -d)"
LOG="$WORK/debug/debug.log"
MONETENMONETEN_DATA_DIR="$WORK/data" MONETENMONETEN_DEBUG_DIR="$WORK/debug" "$APP/Contents/MacOS/MonetenMoneten" \
	-viewMode barChart -lockAfterInactivity NO -ApplePersistenceIgnoreState YES >"$WORK/app.log" 2>&1 &
PID=$!

report() {
	[ -f "$LOG" ] && awk -F '[ =]' 'BEGIN { printf "%-30s %9s %10s %13s  %s\n", "scenario", "stall_ms", "budget_ms", "footprint_mb", "result" }
		/^perf .* stall_ms=/ { printf "%-30s %9s %10s %13s  %s\n", $2, $4, $6, $8, $10; next } /^perf / { print }' "$LOG"
	kill $PID 2>/dev/null || true
	rm -rf "$WORK"
}
trap report EXIT

send() {
	"$NOTIFY" "$WORK/debug" "$@"
}

alive() {
	case "$(ps -o stat= -p "$PID")" in "" | Z*) return 1 ;; esac
}

died() {
	echo "The app exited $1. Its output:" >&2
	tail -20 "$WORK/app.log" >&2
	exit 1
}

# Waits up to $2 seconds for a line in the debug log that matches $1.
wait_for() {
	deadline=$(($(date +%s) + $2))
	until grep -q "$1" "$LOG" 2>/dev/null; do
		alive || died "before \"$1\", in the scenario after the last one listed"
		if [ "$(date +%s)" -ge "$deadline" ]; then
			echo "No \"$1\" after $2 seconds." >&2
			exit 1
		fi
		sleep 0.2
	done
}

started=$(($(date +%s) + 60))
until grep -q "^phase=" "$LOG" 2>/dev/null; do
	alive || died "at launch"
	if [ "$(date +%s)" -ge "$started" ]; then
		echo "The app did not answer within 60 seconds of its launch." >&2
		exit 1
	fi
	send state
	sleep 1
done
send create perf-check
send state
wait_for "phase=unlocked" 30
send perf
wait_for "^perf done" 900
send quit
for _ in 1 2 3 4 5 6 7 8 9 10; do alive || break; sleep 0.5; done
if [ -n "$GITHUB_ACTIONS" ]; then
	awk '/^perf .* result=slow$/ { print "::warning title=Slow UI scenario::" $2 " blocked the main thread for " substr($3, 10) " ms, over the budget of " substr($4, 11) " ms" }' "$LOG"
fi
grep -q "^perf done failures=0 " "$LOG"
