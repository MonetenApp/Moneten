## 1. Contract and privacy

- [x] 1.1 Specify the crash sheet, normal quit, decisions, privacy, and opt-in sharing. Correct the first-release log claim. Proof: strict OpenSpec validation passes all 54 items.
- [x] 1.2 Write failing tests for personal data in every text field, literal report output, crashed-thread selection, prefilled fields, and URL truncation. Implement the pure report builder and URL builder. Proof: seven CrashReportTests pass, including literal report output, all personal text fields, crashed-thread parsing, version formats, prefilled ids, and whole-frame truncation.

## 2. App and storage

- [x] 2.1 Subscribe to MetricKit at launch and keep the newest diagnostic in an encrypted file with a Keychain-protected key. Proof: CrashReportStoreTests passes encrypted persistence, replacement, replay suppression, decision deletion, and ciphertext authentication.
- [x] 2.2 Show the report and the three actions from #224. Prefill the Help menu form too. Proof: light and dark harness snapshots show the sheet; a pending report survives a process restart while locked; declining followed by normal quit and launch leaves no sheet; the harness confirms the full copy of 500 frames. The URL test checks the same version fields used by Help. Browser and menu clicks were not exercised.
- [x] 2.3 Add synthetic injection and an intentional crash to the debug harness. Add the privacy values to scripts/check-debug-log.sh. Proof: the debug app builds, the rebuilt app passes scripts/check-debug-log.sh with 217 clean lines, and scripts/check.sh passes, including all library tests and extension replays.

## 3. Maintainer verification

- [x] 3.1 Add and check scripts/symbolicate-crash.sh. Proof: two script tests pass, and the script resolves a synthetic offset from the debug binary to DebugHarness.intentionalCrash() with its matching dSYM. Task 4.6 of add-software-update keeps the release upload open.
- [x] 3.2 Crash only the owned debug process through its harness. Relaunch it once. Record MetricKit delivery and symbolication to the crashing function. Leave this task open if MetricKit does not deliver. Proof on November 18 with Debug build 321 of main, throwaway data, debug, and keychain folders, and the harness command `crash`:
  - An ad hoc signed build gets no delivery. PID 22039 crashed at 10:39:05. ReportCrash sent the `MXCrashDiagnostic` to metrickitd, which wrote a payload for delivery. On the relaunch, metrickitd logged "Bundle is not codesigned" and "_shouldDeliverToClientForBundleID returned NO", and the harness reported pending=true, fallback=true, received=0. This explains the try of November 15. The user still got the short report.
  - The same build signed with an Apple Development certificate gets the delivery. Its first launch at 10:52:32 received the payload of the 10:39 crash: received=1, fallback=false. The report had no frames, because `CrashDiagnostic.crashedFrames` expected a `callStackTree` key, and `MXCallStackTree.jsonRepresentation()` returns `callStacks` at its root. crashedThread now uses the real form.
  - A signed copy under a new bundle ID registered as a MetricKit client at its launch at 10:41:08, but ReportCrash called it "not a MetricKit client" for its crashes at 10:41:25 and 10:42:21, and its relaunch received nothing. The ReportCrash agent that started at 10:39:05 still ran 25 minutes later. The short report covered both crashes.
  - PID 84171 crashed at 10:58:38, launched at 10:58:21. The relaunch received the payload, but the short report stayed, because the payload ran from 10:58:00 to 10:58:00 and so began before the launch. MetricKit gives payload times in whole minutes. The fallback match now starts at the whole minute of the launch. wholeMinutePayload and fallbackTiming at 959 and 960 failed before the fix.
  - With both fixes, PID 43375 launched at 11:01:54 and crashed at 11:02:06. ReportCrash wrote the crash file at 11:03:45 and queued the payload at 11:03:51. One relaunch at 11:03:58 reported pending=true, fallback=false, received=1, failures=0, and a report of 42 frames. `scripts/symbolicate-crash.sh` with dsymutil output for `Moneten` and `Moneten.debug.dylib` resolved the first Moneten frame, offset 0x258b20, to `DebugHarness.intentionalCrash()`, and the next one to `DebugHarness.run(_:_:)` at DebugHarness.swift:180.

## 4. Gate round 1

- [x] 4.1 Recover from a lost key or damaged ciphertext. Proof: lostKey and pendingReport failed before recovery and pass after it. A new diagnostic can be persisted and offered.
- [x] 4.2 Record launch times and versions in encrypted state across updates. Decide the fallback from file names and dates only. Proof: fallbackFiles, fallbackDiagnostic, persistedLaunch, newerFallbackDetails, and consecutiveFallbackDecisions cover old files, force quit, first launch, update, delayed details, and a decision.
- [x] 4.3 Keep a cut report after opening GitHub and use expected only. Proof: githubRetainsLongReport and boundedURL check 500 frames and persistence until Copy or Don't Report.
- [x] 4.4 Omit a zero macOS patch in both paths. Proof: zeroPatch calls the shared Help formatter with 15.2.0 and 15.2.1 and checks crash text and URL fields.
- [x] 4.5 Open the main window for a pending report and use the injected report time. Keep counters in debug builds. Proof: the owned harness closes the main window, injects a 500-frame report at a supplied time, and checks that the window returns and the time matches. The privacy script repeats the timestamp check.
- [x] 4.6 Crash the owned debug PID and show a short sheet on one relaunch. Proof: PID 71137 exited with signal 5. A new Moneten crash file appeared. Relaunch reported pending=true, fallback=true, received=0, failures=0. Harness snapshots cover light and dark. Decline, normal quit, and force quit do not prompt again. System file contents were never read.


## 5. Gate round 2

- [x] 5.1 Preserve encrypted state for every Keychain failure and unclassified access error. Delete only permanently unreadable state. Proof: keychainAccess covers interaction denied, cancellation, authentication denied, and signature mismatch. unknownAccess covers unclassified Cocoa and CryptoKit errors. permanentlyUnreadable covers missing, short, long, and malformed keys, a malformed box, failed authentication, invalid JSON, and an invalid schema. The failing tests ran before the fix.
- [x] 5.2 Correlate delayed details with the fallback file date and its previous launch. Proof: lateDiagnostic reproduces crash 1100, file 1103, and payload 1100 through 1100. fallbackTiming covers starts before, at, and after the previous launch, and 59, 60, and 61 seconds after the file date across another launch. latePayloadReplay covers older, equal, and newer saved replay times and all three decisions. All 24 crash-report tests pass.
- [x] 5.3 Remove the unshipped legacy-state test. Clean up only the owned crash Keychain item after the performance harness. Proof: the remaining optional launch state serves first launch; the performance exit trap deletes by the dedicated service and its exact database account.
- [x] 5.4 Apply the same correlation window after every fallback decision. Proof: both independent reviews found starts after the file date could prompt again. decidedFallbackTiming failed first with 18 issues and decidedFallbackIntervals with six. They cover all three decisions, zero-length and broad intervals, the 59/60/61-second edges, and older consecutive decisions. One shared match rule now serves pending and decided fallbacks.

## 6. Harness runs without Keychain prompts

- [x] 6.1 Keep the crash report key of a harness run in the data folder, and test the store without the login Keychain. Proof: a debug build started twice with the same data folder and a rebuild in between showed no prompt, and the login Keychain has no crash report entry for that folder. A report injected by the harness survived SIGKILL and the rebuild and was offered on the relaunch. `scripts/test.sh --filter CrashReport` passes without Keychain access. The harness scripts no longer delete Keychain entries.
