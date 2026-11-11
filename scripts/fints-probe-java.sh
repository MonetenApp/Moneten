#!/bin/sh
# Builds and runs Tools/FinTSProbeJava, the hbci4java counterpart of App/FinTSProbe (issue #11).
# It downloads the jars in Tools/FinTSProbeJava/dependencies.lock from Maven Central into
# .build/hbci4java/lib, checks the SHA-256 of each one, and compiles the probe with a JDK 17 or later.
# The arguments go to the probe. Its source file explains them. With --build-only the script stops
# after the compilation, as CI does.
set -e
cd "$(dirname "$0")/.."
LOCK=Tools/FinTSProbeJava/dependencies.lock
LIB=.build/hbci4java/lib
OUT=.build/hbci4java/classes
for dir in "$JAVA_HOME" "$JAVA_HOME_17_arm64" "$JAVA_HOME_21_arm64" /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk@17 /opt/homebrew/opt/openjdk; do
	[ -n "$dir" ] && [ -x "$dir/bin/javac" ] && JDK="$dir" && break
done
[ -n "$JDK" ] || { echo "No JDK found. Install one with: brew install openjdk@21" >&2; exit 1; }

mkdir -p "$LIB" "$OUT"
CP=""
while read -r coordinate sha; do
	case "$coordinate" in ""|\#*) continue ;; esac
	group=$(echo "$coordinate" | cut -d: -f1); artifact=$(echo "$coordinate" | cut -d: -f2); version=$(echo "$coordinate" | cut -d: -f3)
	jar="$LIB/$artifact-$version.jar"
	if [ ! -f "$jar" ]; then
		curl -sfL "https://repo1.maven.org/maven2/$(echo "$group" | tr . /)/$artifact/$version/$artifact-$version.jar" -o "$jar.part"
		mv "$jar.part" "$jar"
	fi
	if [ "$(shasum -a 256 "$jar" | cut -d' ' -f1)" != "$sha" ]; then
		rm -f "$jar"
		echo "Checksum mismatch for $coordinate. The file was removed." >&2
		exit 1
	fi
	CP="$CP${CP:+:}$jar"
done < "$LOCK"

SRC=Tools/FinTSProbeJava/FinTSProbeJava.java
if [ ! -f "$OUT/FinTSProbeJava.class" ] || [ "$SRC" -nt "$OUT/FinTSProbeJava.class" ]; then
	"$JDK/bin/javac" --release 17 -nowarn -cp "$CP" -d "$OUT" "$SRC"
fi
[ "$1" = "--build-only" ] && { echo "Built $OUT/FinTSProbeJava.class with $("$JDK/bin/javac" -version 2>&1)"; exit 0; }
exec "$JDK/bin/java" -cp "$OUT:$CP" FinTSProbeJava "$@"
