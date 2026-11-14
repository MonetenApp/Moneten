#!/bin/sh
# Checks that the debug log holds no personal data. It drives the debug build of dist/Moneten.app
# (scripts/build-app.sh debug) through the debug harness against scripts/fake-fints-helper.sh: a login
# with a wrong PIN, the setup of the made-up bank, two refreshes (the second fails an account with an
# error of the bank), the transactions and the status of each account, and a snapshot. It then fails when
# debug.log holds an IBAN, an account number, a name, a purpose, the login name, or a text of the bank.
# The app runs with a temporary data folder and a password, so it never opens the real database and
# leaves no Keychain item, and as a copy under its own bundle ID, so it leaves an installed Moneten alone.
set -e
cd "$(dirname "$0")/.."
BUILT=dist/Moneten.app
[ -d "$BUILT" ] || { echo "No $BUILT. Run scripts/build-app.sh debug first." >&2; exit 1; }
BUNDLE_ID=io.github.alexander-schneider.Moneten.check-debug-log
LOGIN=emuster42

NOTIFY=.build/check-debug-log-notify
if [ ! -x "$NOTIFY" ] || [ scripts/check-debug-log.sh -nt "$NOTIFY" ]; then
	mkdir -p .build
	cat > "$NOTIFY.swift" <<-'EOF'
	import Foundation
	let a = CommandLine.arguments
	DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.moneten.debug"), object: a[1],
		userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)
	EOF
	swiftc -o "$NOTIFY" "$NOTIFY.swift"
fi

WORK="$(mktemp -d)"
LOG="$WORK/debug/debug.log"
APP="$WORK/Moneten.app"
ditto "$BUILT" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements App/Moneten.entitlements "$APP" 2>/dev/null
MONETEN_DATA_DIR="$WORK/data" MONETEN_DEBUG_DIR="$WORK/debug" MONETEN_FINTS_HELPER="$PWD/scripts/fake-fints-helper.sh" \
	"$APP/Contents/MacOS/Moneten" -lockAfterInactivity NO -ApplePersistenceIgnoreState YES >"$WORK/app.log" 2>&1 &
PID=$!

finish() {
	kill $PID 2>/dev/null || true
	[ -n "$KEEP" ] && echo "The log stays in $WORK/debug." || rm -rf "$WORK"
}
trap finish EXIT

send() {
	"$NOTIFY" "$WORK/debug" "$@"
}

alive() {
	case "$(ps -o stat= -p "$PID")" in "" | Z*) return 1 ;; esac
}

# Sends the command in $2 and the rest until a line written after the first send matches $1, for up to 30 seconds.
poll() {
	pattern=$1
	shift
	seen=$({ wc -l <"$LOG"; } 2>/dev/null || echo 0)
	deadline=$(($(date +%s) + 30))
	while :; do
		send "$@"
		sleep 0.5
		tail -n +"$((seen + 1))" "$LOG" 2>/dev/null | grep -q "$pattern" && return
		alive || { echo "The app exited while waiting for \"$pattern\"." >&2; tail -20 "$WORK/app.log" >&2; exit 1; }
		if [ "$(date +%s)" -ge "$deadline" ]; then
			echo "No \"$pattern\" after 30 seconds. The end of the log:" >&2
			tail -5 "$LOG" >&2
			exit 1
		fi
	done
}

poll "^phase=" state
send create check-debug-log
poll "phase=unlocked" state
send sheet newAccount
send setup "entry 12030000"
send setup next
poll "setup step=login" setup
send setup "login $LOGIN"
send setup "pin 0000"
send setup next
poll "setup step=login .* error=[^-]" setup
send setup "pin 1234"
send setup next
poll "dialog=true" setup
send answer 123456
poll "setup step=accounts" setup
send setup next
poll "status line=.* accesses=1" status
send refresh all
poll "status #2 [a-zA-Z]* refreshing=false refreshedAt=[^-]" status
send refresh all
poll "status #1 savings refreshing=false .*error=[^-]" status
for account in Girokonto Tagesgeld Kreditkarte; do
	poll "^rows " rows "$account"
done
send select Girokonto
poll "^phase=" state
poll "^snapshot " snapshot check
send quit

found=0
for value in DE02120300000000202051 "DE02 1203" 202051 1234567890 4711 "$LOGIN" \
	Girokonto Tagesgeld Kreditkarte "Erika Mustermann" "Beispiel GmbH" "Wohnbau Musterstadt" "Tankstelle Beispiel" \
	"Gehalt November" "Zugang vorübergehend gesperrt" "PIN falsch"; do
	if grep -n -w -F -- "$value" "$LOG" >&2; then
		echo "debug.log holds \"$value\"." >&2
		found=1
	fi
done
[ "$found" = 0 ] && echo "debug.log holds no personal data in $(wc -l <"$LOG" | tr -d ' ') lines."
exit $found
