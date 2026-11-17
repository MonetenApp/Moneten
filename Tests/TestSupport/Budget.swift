import Foundation

/// The time limit of a test on a Mac, or 1.5 times as much on a runner that GitHub hosts, which is far slower than a
/// current Mac and stalls at random (issue #343 has the measurements). GitHub sets `RUNNER_ENVIRONMENT` to
/// `github-hosted` only on its own runners, so a developer Mac keeps the budget of a Mac.
///
/// Every upper time limit in a test goes through this function, so that one factor covers all of them (issue #372).
/// `scripts/check-time-limits.py` fails on a limit in `Tests/` that bypasses it. A limit that already has room for a
/// slow runner, such as a grace period or a deadline of many seconds, keeps its own value and says why with
/// `// time-ok: <reason>`.
public func budget(_ onAMac: Duration) -> Duration {
	ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" ? onAMac * 1.5 : onAMac
}
