# Gate round 2 verification

## Behavior and design

A stopped search returns no rows and `gaveUp == true` in `TransactionSearchResult`.
The table and status line consume the same result.
The status line says "The regular expression stopped because it is too slow" and shows no sum.

Round 11 used a wall-clock cutoff. Round 12 removed it because a busy Mac lost matching rows.
This replacement counts only processor time spent in regex calls on the searching thread.
Every call, including empty-value checks and joined-fields attempts, shares one 300 ms total.
The joined-fields optimization retains its separate per-call watch.
It can retry real values when the synthetic joined text stops, within the shared total.
A stop of a real-value watch or the shared total discards the whole result.

Model the Domain puts rows and outcome in one result.
Test Behavior, Not Implementation uses literal rows and outcomes at the ledger boundary.
Sequence Work into Verifiable Units puts each spec before its failing test and fix.
Laziness Protocol keeps the existing filtering and regex prefilter.
Prove It Works requires the Debug harness checks as well as library tests.

## Failing tests before code

- `stoppedSearchHasNoPartialRows` failed with eight issues before the fix. One positive case returned `["Row0"]`. NOT returned `["Row1", "Row2"]`. The Opus pattern returned `["Row0", "Row1"]`. All should return `[]`.
- The final test rotates every row position for Astra's three texts with `purpose:/(\w+\s?)*:/` and NOT, and Opus's `/ok|(a+)+$/`. Every result is `[]` with `gaveUp == true`.
- `searchRegexProcessorBudget` first spent 2,445.5 ms of processor time on 100 copies of "aaaaaaaaaaaaaaaaaaaa!" with `purpose:/^(a+)+$/` and returned `gaveUp == false`. The expected result is `[]`, `gaveUp == true`, and 300 to 400 ms of processor time. Load average was 7.72 after that release run.
- `searchAmountAtInt64Edges` failed with seven issues. Literal expectations cover both Int64 edges, the requested huge equality and inequality, all comparison forms, and a JPY value that fits despite being outside the EUR range. The same rules independently match each literal expectation.
- `unfinishedSearchConstants` failed twice. `false "Stadtw` and `NOT true "Stadtw` returned the Stadtwerke row instead of `[]`. The final table also checks true, NOT false, and a word absent from the row.

All 46 LedgerTests pass. These four tests add no test-only production hook.

## Release measurements

Command for each of the three final runs:

```sh
scripts/test.sh -c release -Xswiftc -enable-testing --filter 'PerformanceTests|LedgerTests/searchRegexProcessorBudget' --no-parallel
```

Every run passes nine tests in six suites.
The 50,000-row measurements are the fastest of three calls, as the existing test defines.
The adversarial CPU measurement is one search per run, not the fastest of three.
The Mac has 18 logical cores.

| Final run | Adversarial thread CPU, ms | Regex over 37,500 rows, ms | Prefiltered regex over 50,000 rows, ms | Exhaustive regex over 50,000 rows, ms | One-minute load before / after |
|---|---:|---:|---:|---:|---|
| 1 | 311.84 | 24.74 | 36.21 | 96.06 | 5.19 / 5.04 |
| 2 | 312.06 | 25.57 | 40.46 | 96.77 | 5.04 / 4.96 |
| 3 | 304.64 | 22.19 | 34.79 | 92.08 | 4.96 / 4.50 |

Every adversarial result has zero rows and `gaveUp == true`.
The three normal regex cases return 6,078, 11,111, and 40,000 rows respectively.
The exhaustive case also asserts its literal 40,000 matches.

The first preflight measured the exhaustive case at 94.00 ms, enough for a twofold margin against 200 ms.
Two later runs during concurrent compilation measured 254.12 and 233.09 ms and failed the attempted 200 ms assertion.
They still returned all 40,000 matching rows. The runtime processor-time limit did not discard them.
Their one-minute load averages ranged from 9.88 to 11.82 around the second run, with 11.56 after the first.
A third run measured 140.81 ms at a load of 7.42 to 7.61.

The two faster cases keep a twofold margin against 200 ms even in those loaded runs.
Their largest measurements were 82.58 and 92.45 ms, so their test budgets are now 200 ms.
The exhaustive case retains 600 ms because its twofold margin does not hold across the loaded measurements.
No other performance budget changes.

A separate, unreported timing run sampled only this task's test-worker PID.
Its stack includes `RegexTerm.holds`, `RegexWatch.firstMatch`, Foundation regex enumeration, ICU matching, and the thread-clock reads.
The exhaustive path performs regex calls on all 50,000 rows. It is not a prefilter-only measurement.
Concurrent compilation and scheduling affect elapsed test times. They do not consume the runtime CPU budget.

## Debug app and privacy

Only this task's copied Debug app runs against a throwaway database.
Both `MONETEN_DATA_DIR` and `MONETEN_DEBUG_DIR` point under this worktree.
The app is driven by notifications addressed to that debug directory.
Only its own PID is stopped. Test database Keychain deletion is attempted after it exits.
No personal database or other running Moneten app is opened.

The before images show the old empty-result status with its zero sum.
The after images use `currency:/^+?49/` to reach the watch on the made-up seed data.
The unqualified probe can be rejected by the literal prefilter on that data.
The final harness state has `visible=0`, and the stop log contains only `gave up`.
The final after images have the same SHA-256 hashes as the committed images.

| Status | Light | Dark |
|---|---|---|
| Before | [Snapshot](before-status-light.png) | [Snapshot](before-status-dark.png) |
| Stopped search | [Snapshot](after-status-light.png) | [Snapshot](after-status-dark.png) |

`scripts/check-debug-log.sh` passes with 163 log lines.
It exercises the stopped search and checks that the literal search text never appears in the log.
The final Debug build passes.

## Repository checks and scope

`scripts/check.sh` passes with 1,141 library tests in 90 suites, all 53 OpenSpec items, Periphery, docs, UI rules, and four extension replays.
The full check is repeated after the final evidence and budget commits before review.

Search remains synchronous. Issue #244 owns moving it off the main thread.
This round changes no line of `Rule.swift`; issue #246 owns the categorization watch.
No merge, main push, CI polling, or real bank access is part of this round.
