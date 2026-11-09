#!/bin/sh
# Run all tests. With only the Command Line Tools installed, Swift Testing needs extra search paths.
set -e
cd "$(dirname "$0")/.."
EXTRA=""
if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ]; then
	F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
	L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
	EXTRA="-Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L"
fi
# --disable-keychain keeps the package manager from waiting for a Keychain prompt about GitHub.
exec swift test --disable-keychain $EXTRA "$@"
