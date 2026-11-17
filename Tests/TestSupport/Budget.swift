import Foundation

/// The time limit of a test on a Mac, or 1.5 times as much on a runner that GitHub hosts, which takes about nine times
/// as long as a current Mac and stalls at random. There the sidebar amounts and the booked refresh usually take 18 to
/// 20 ms, so twice that fails, but the fastest runners pass up to 2.2 times. GitHub sets `RUNNER_ENVIRONMENT` to
/// `github-hosted` only on its own runners, so a developer Mac keeps the budget of a Mac.
///
/// Every upper time limit in a test goes through this function, so that one factor covers all of them (issue #372).
/// `scripts/check.sh` fails on a comparison with a raw duration in `Tests/`. A limit that already has room for a slow
/// runner, such as a grace period or a deadline of many seconds, keeps its own value and says why with `// time-ok:`.
public func budget(_ onAMac: Duration) -> Duration {
	ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" ? onAMac * 1.5 : onAMac
}
