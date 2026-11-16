## Design

An Ubuntu job classifies changed paths. All pull requests run the existing specification checks. Documentation-only pull requests start no macOS jobs. Main and manual runs select every check.

Two unit shards separate core tests from connectors. FinTS runs after the other connector suites to avoid delaying its timers with CPU work. Release performance and the Lua memory-limit suite run serially. The memory-limit suite retains every assertion and iteration count. An app build produces Debug and Perf bundles once per run. Two downstream runners execute separate UI scenarios. The portfolio scenarios stay together because they share a portfolio. No parallel measurements share a runner.

Caches contain only dependencies keyed by toolchain and lockfile, verified Periphery downloads, and Homebrew downloads. Built products are passed only as artifacts within the same run. No build results are restored from a cache.

The existing FinTS inactivity and grace parameters shorten timeout proof. The production defaults and a default-grace test remain. All 3,000 fuzz seeds remain because fewer seeds would reduce coverage.
