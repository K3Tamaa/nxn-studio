import Foundation

/// Signals a process and everything it spawned. Needed for `brew` and
/// `xcodebuild`, which hand work to helpers that would otherwise keep running
/// after the app cancels the direct child.
enum ProcessTree {
    static func terminate(pid: Int32, signal: Int32 = SIGINT) {
        // `ps` must not run on the main thread; the signal is sent from a
        // detached task, deepest children first.
        let target = pid
        Task.detached(priority: .utility) {
            signalTree(pid: target, signal: signal)
        }
    }

    private static func signalTree(pid: Int32, signal: Int32) {
        for child in children(of: pid) {
            signalTree(pid: child, signal: signal)
        }
        kill(pid, signal)
    }

    private static func children(of pid: Int32) -> [Int32] {
        let output = ShellRunner.runSync(["/bin/ps", "-axo", "pid=,ppid="]).output
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 2, let ppid = Int32(parts[1]), ppid == pid else { return nil }
                return Int32(parts[0])
            }
    }
}
