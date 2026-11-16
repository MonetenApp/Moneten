## Design

An Ubuntu job classifies changed paths. All pull requests run the existing specification checks. Documentation-only pull requests start no macOS jobs. Main and manual runs select every check.

One unit job builds the Debug test bundle once and runs core and connector suites together. FinTS runs after the other connector suites to avoid delaying its timers with CPU work. Release performance and the Lua memory-limit suite run serially. The memory-limit suite retains every assertion and iteration count. One app job uses scripts/build-app.sh perf to build Perf once, retain every bundled-helper, entitlement and signature check, and provide the unchanged privacy scenarios, strict Periphery scan, and UI artifact. Index recording is explicitly enabled for both the Perf app and ext so the scan reads only the current build. The existing CSV handoff helper is available in DEBUG and PERF_HARNESS; the extension host still keeps its original Debug and Release consent branches. Two downstream runners execute separate UI scenarios. The portfolio scenarios stay together because they share a portfolio. No parallel measurements share a runner.

Caches contain only source checkouts and repositories keyed by toolchain and lockfile, verified Periphery downloads, and Homebrew downloads. Built products are passed only as artifacts within the same run. No build results or extracted binary frameworks are restored from a cache. SwiftPM fetches the locked binary archive and checks its manifest checksum on each fresh runner.

The existing FinTS inactivity and grace parameters shorten timeout proof. The production defaults and a default-grace test remain. All 3,000 fuzz seeds remain because fewer seeds would reduce coverage.

Three macOS jobs start together. The two UI jobs need the app job, so at most four macOS jobs overlap. Each UI job downloads only this run's artifact, retained for one day.

Unknown paths run every check. Only allowed documentation and issue-template paths without macOS consumers skip macOS. Ubuntu-only documentation readers do not prevent that skip. A single consumed-input table and a scanner over macOS consumer literals protect runtime documentation and fixture inputs.

The memory fixture labels its unchanged 8 MB body as application/octet-stream. Profiling found HTML metadata scanning, rather than allocation or garbage collection, dominated the two request tests. Every memory ceiling, API variant, assertion, and iteration remains.
