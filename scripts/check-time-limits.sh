#!/bin/sh
# Fails on an upper time limit in a test that bypasses budget(_:) of Tests/TestSupport (issue #372): a comparison with a raw
# duration, or with a count of milliseconds. A limit with its own room for a slow runner carries `// time-ok: <reason>`.
cd "$(dirname "$0")/.."
found=$(grep -rnE '<=? *(\.(nanoseconds|microseconds|milliseconds|seconds|minutes)\(|max\(\.|Duration\.)|1_000_000 *<|[Mm]illiseconds *<=? *[0-9]' Tests \
	--include='*.swift' | grep -v '// time-ok: ')
if [ -n "$found" ]; then
	printf '%s\n' "$found"
	echo "A time limit in a test goes through budget(_:) of Tests/TestSupport, or says why not with // time-ok: <reason>." >&2
	exit 1
fi
