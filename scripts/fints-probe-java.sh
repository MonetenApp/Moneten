#!/bin/sh
# Builds and runs Tools/FinTSProbeJava, the hbci4java counterpart of App/FinTSProbe (issue #11).
# It gets the jars of hbci4java through scripts/hbci4java-jars.sh and compiles the probe with a JDK
# 17 or later.
# The arguments go to the probe. Its source file explains them. With --build-only the script stops
# after the compilation, as CI does.
set -e
cd "$(dirname "$0")/.."
OUT=.build/hbci4java/classes
. scripts/hbci4java-jars.sh
mkdir -p "$OUT"

# The probe shares the masking rules of the helper in Tools/FinTSHelper/Out.java.
SRC=Tools/FinTSProbeJava/FinTSProbeJava.java
SHARED=Tools/FinTSHelper/Out.java
if [ ! -f "$OUT/FinTSProbeJava.class" ] || [ "$SRC" -nt "$OUT/FinTSProbeJava.class" ] || [ "$SHARED" -nt "$OUT/FinTSProbeJava.class" ]; then
	"$JDK/bin/javac" --release 17 -nowarn -cp "$CP" -d "$OUT" "$SRC" "$SHARED"
fi
[ "$1" = "--build-only" ] && { echo "Built $OUT/FinTSProbeJava.class with $("$JDK/bin/javac" -version 2>&1)"; exit 0; }
exec "$JDK/bin/java" -cp "$OUT:$CP" FinTSProbeJava "$@"
