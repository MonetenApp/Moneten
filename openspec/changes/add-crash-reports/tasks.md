## 1. Contract and privacy

- [x] 1.1 Specify the crash sheet, normal quit, decisions, privacy, and opt-in sharing. Correct the first-release log claim. Proof: strict OpenSpec validation passes all 54 items.
- [x] 1.2 Write failing tests for personal data in every text field, literal report output, crashed-thread selection, prefilled fields, and URL truncation. Implement the pure report builder and URL builder. Proof: seven CrashReportTests pass, including literal report output, all personal text fields, crashed-thread parsing, version formats, prefilled ids, and whole-frame truncation.

## 2. App and storage

- [x] 2.1 Subscribe to MetricKit at launch and keep the newest diagnostic in an encrypted file with a Keychain-protected key. Proof: CrashReportStoreTests passes encrypted persistence, replacement, replay suppression, decision deletion, and ciphertext authentication.
- [x] 2.2 Show the report and the three actions from #224. Prefill the Help menu form too. Proof: light and dark harness snapshots show the sheet; a pending report survives a process restart while locked; declining followed by normal quit and launch leaves no sheet; the harness confirms the full copy of 500 frames. The URL test checks the same version fields used by Help. Browser and menu clicks were not exercised.
- [x] 2.3 Add synthetic injection and an intentional crash to the debug harness. Add the privacy values to scripts/check-debug-log.sh. Proof: the debug app builds, the rebuilt app passes scripts/check-debug-log.sh with 217 clean lines, and scripts/check.sh passes, including all library tests and extension replays.

## 3. Maintainer verification

- [x] 3.1 Add and check scripts/symbolicate-crash.sh. Proof: two script tests pass, and the script resolves a synthetic offset from the debug binary to DebugHarness.intentionalCrash() with its matching dSYM. Task 4.6 of add-software-update keeps the release upload open.
- [ ] 3.2 Crash only the owned debug process through its harness. Relaunch it once. Record MetricKit delivery and symbolication to the crashing function. Leave this task open if MetricKit does not deliver.

MetricKit check on November 15: the owned debug process crashed through its harness and exited with signal 5. After one relaunch, the harness reported zero diagnostics and no pending report. Actual next-launch delivery and symbolication of a delivered report remain open in #224. The fallback now uses only system crash file names and modification dates. It adds no quit marker.

## 4. Gate round 1

- [x] 4.1 Recover from a lost key or damaged ciphertext. Proof: lostKey and pendingReport failed before recovery and pass after it. A new diagnostic can be persisted and offered.
- [x] 4.2 Record launch times and versions in encrypted state across updates. Decide the fallback from file names and dates only. Proof: fallbackFiles, fallbackDiagnostic, persistedLaunch, legacyState, newerFallbackDetails, and consecutiveFallbackDecisions cover old files, force quit, first launch, update, delayed details, and a decision.
- [x] 4.3 Keep a cut report after opening GitHub and use expected only. Proof: githubRetainsLongReport and boundedURL check 500 frames and persistence until Copy or Don't Report.
- [x] 4.4 Omit a zero macOS patch in both paths. Proof: zeroPatch calls the shared Help formatter with 15.2.0 and 15.2.1 and checks crash text and URL fields.
- [x] 4.5 Open the main window for a pending report and use the injected report time. Keep counters in debug builds. Proof: the owned harness closes the main window, injects a 500-frame report at a supplied time, and checks that the window returns and the time matches. The privacy script repeats the timestamp check.
- [x] 4.6 Crash the owned debug PID and show a short sheet on one relaunch. Proof: PID 71137 exited with signal 5. A new Moneten crash file appeared. Relaunch reported pending=true, fallback=true, received=0, failures=0. Harness snapshots cover light and dark. Decline, normal quit, and force quit do not prompt again. System file contents were never read.
