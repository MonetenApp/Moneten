#!/bin/sh
# Builds the FinTS helper of ADR 0014 from Tools/FinTSHelper and runs its self-test, which needs no bank.
# The self-test compares the lines of the helper with Tests/FinTSTests/helper-lines.jsonl, which the
# Swift tests decode. On a difference it writes the new lines there and fails.
#   scripts/build-fints-helper.sh               compile and run the self-test, as CI does
#   scripts/build-fints-helper.sh --bundle DIR  also write DIR for the app: the java launcher in
#                                               DIR/java, a jlink runtime in DIR/runtime, and the
#                                               jars in DIR/lib, and run the self-test again on them
# The jars come from scripts/hbci4java-jars.sh. The modules of the runtime are those that jdeps
# finds in the jars, and jdk.crypto.ec for the TLS key exchange of the bank servers.
set -e
cd "$(dirname "$0")/.."
. scripts/hbci4java-jars.sh
OUT=.build/fints-helper/classes
rm -rf "$OUT"
mkdir -p "$OUT"
"$JDK/bin/javac" --release 17 -nowarn -cp "$CP" -d "$OUT" Tools/FinTSHelper/*.java
# stderr carries the diagnostics of the helper, which the checks cause on purpose.
"$JDK/bin/java" -Djava.awt.headless=true -cp "$OUT:$CP" FinTSHelper --self-test Tests/FinTSTests/helper-lines.jsonl 2>/dev/null
[ "$1" = "--bundle" ] || exit 0
[ -n "$2" ] || { echo "usage: scripts/build-fints-helper.sh [--bundle DIR]" >&2; exit 2; }

rm -rf "$2"
mkdir -p "$2/lib"
"$JDK/bin/jlink" --add-modules java.base,java.compiler,java.desktop,java.logging,java.smartcardio,jdk.crypto.ec \
	--strip-debug --compress=2 --no-header-files --no-man-pages --output "$2/runtime"
# The app sandbox of the helper (ADR 0018) lets java read the folder of its own executable and the
# folder of each library that it loads at start, and nothing else of the app. So the launcher moves
# from runtime/bin up to DIR, where that folder holds the runtime and the jars, and finds libjli in
# runtime/lib. The JVM takes its home from the place of libjli, so it stays DIR/runtime.
mv "$2/runtime/bin/java" "$2/java"
rm -r "$2/runtime/bin"
# The change breaks the signature, and macOS runs no unsigned code. scripts/build-app.sh signs it again.
install_name_tool -rpath @loader_path/../lib @loader_path/runtime/lib "$2/java" 2>/dev/null
codesign --force --sign - "$2/java" 2>/dev/null
cp $(echo "$CP" | tr : ' ') "$2/lib/"
"$JDK/bin/jar" --create --file "$2/lib/FinTSHelper.jar" -C "$OUT" .
# As the app starts it: a module that jlink left out fails here, not at the bank.
env -i "$2/java" -Djava.awt.headless=true -XX:ErrorFile=/dev/null -XX:+DisableAttachMechanism -Xrs -cp "$2/lib/*" FinTSHelper \
	--self-test Tests/FinTSTests/helper-lines.jsonl 2>/dev/null
echo "Built the FinTS helper in $2 ($(du -sh "$2" | cut -f1))"
