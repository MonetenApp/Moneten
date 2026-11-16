## Implementation

- [x] 1. Route paths on Ubuntu. `python3 scripts/test-ci.py` proves documentation-only, mixed, Swift, tooling, empty, main, and manual cases.
- [x] 2. Split checks and cache verified dependencies. The two local UI halves cover all 21 scenarios once. Periphery passes against the reused app index. Every discovered test has a shard; the host-consent branches run in both configurations.
- [x] 3. Fix compiler warnings and fail new warnings from repository targets. The warning gate rejects the original diagnostics and passes the repaired owner tests and app builds.
- [x] 4. Shorten timeout proof with existing parameters. FinTS tests pass with shorter waits, and the unchanged default-grace test still checks five seconds.

Verification requires `scripts/check.sh`, independent autoreview and ponytail reviews, a full CI run, and a docs-only CI run. The PR body records the remote measurements after publication.
