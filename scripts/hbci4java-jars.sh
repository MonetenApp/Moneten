# Sourced by the scripts that build Java code on hbci4java. It finds a JDK 17 or later and sets JDK,
# downloads the jars in Tools/FinTSProbeJava/dependencies.lock from Maven Central into
# .build/hbci4java/lib, checks the SHA-256 of each one, and sets CP to the class path of the jars.
LOCK=Tools/FinTSProbeJava/dependencies.lock
LIB=.build/hbci4java/lib
for dir in "$JAVA_HOME" "$JAVA_HOME_17_arm64" "$JAVA_HOME_21_arm64" /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk@17 /opt/homebrew/opt/openjdk; do
	[ -n "$dir" ] && [ -x "$dir/bin/javac" ] && JDK="$dir" && break
done
[ -n "$JDK" ] || { echo "No JDK found. Install one with: brew install openjdk@21" >&2; exit 1; }

mkdir -p "$LIB"
CP=""
while read -r coordinate sha; do
	case "$coordinate" in ""|\#*) continue ;; esac
	group=$(echo "$coordinate" | cut -d: -f1); artifact=$(echo "$coordinate" | cut -d: -f2); version=$(echo "$coordinate" | cut -d: -f3)
	jar="$LIB/$artifact-$version.jar"
	if [ ! -f "$jar" ]; then
		if ! curl -sfL "https://repo1.maven.org/maven2/$(echo "$group" | tr . /)/$artifact/$version/$artifact-$version.jar" -o "$jar.part"; then
			rm -f "$jar.part"
			echo "Download of $coordinate failed." >&2
			exit 1
		fi
		mv "$jar.part" "$jar"
	fi
	if [ "$(shasum -a 256 "$jar" | cut -d' ' -f1)" != "$sha" ]; then
		rm -f "$jar"
		echo "Checksum mismatch for $coordinate. The file was removed." >&2
		exit 1
	fi
	CP="$CP${CP:+:}$jar"
done < "$LOCK"
