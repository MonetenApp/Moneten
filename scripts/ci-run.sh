#!/bin/bash
# A diagnostic must come from a repository source path, not a downloaded dependency or test argument.
set -euo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
status=0
"$@" 2>&1 | tee "$log" || status=$?
python3 - "$log" "$PWD" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[2]).resolve()
warnings = []
for line in pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines():
    match = re.match(r"(.+?):\d+:\d+: warning: (.*)", line)
    if not match:
        continue
    path = pathlib.Path(match[1])
    if path.is_absolute():
        try:
            path = path.relative_to(root)
        except ValueError:
            continue
    if path.parts and path.parts[0] in {"App", "Sources", "Tests", "Tools"}:
        warnings.append(line)
for warning in warnings:
    print(f"::error title=Compiler warning::{warning}")
sys.exit(bool(warnings))
PY
exit "$status"
