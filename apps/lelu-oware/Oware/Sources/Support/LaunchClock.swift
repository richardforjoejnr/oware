import Darwin
import Foundation

/// How long launch takes, measured by the app itself for `LaunchTimeUITests` (test launches with
/// `--report-launch-time` only). Two numbers:
/// - the app's own work: from its first code (`OwareApp.init`) to the home menu appearing, which
///   this repository controls and the test guards;
/// - the total since iOS started the process (the kernel's record), which also includes loading the
///   app's code, reported for reference: on a simulator running a Debug build that part dominates.
@MainActor
enum LaunchClock {
    private static var appStart: Date?
    /// Set once, when the home menu first appears.
    private(set) static var reading: (app: TimeInterval, total: TimeInterval)?

    static func appStarted() { if appStart == nil { appStart = Date() } }

    static func homeAppeared() {
        guard reading == nil, let appStart, let processStart = processStart() else { return }
        let now = Date()
        reading = (now.timeIntervalSince(appStart), now.timeIntervalSince(processStart))
    }

    static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }
}
