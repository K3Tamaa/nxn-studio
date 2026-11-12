import Foundation
import AppKit
/// Headless verification of the nxnative checkout update flow.
enum RepoSelfTest {
    @MainActor
    static func run(repo: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let updater = RepoUpdate()
        let url = URL(fileURLWithPath: repo)

        Task {
            await updater.check(repo: url)
            print("CHECK \(updater.statusLabel) | \(updater.detail)")
            guard updater.behindCount > 0 else {
                print("SELFTEST-UPDATE SKIP (aucun retard à appliquer)")
                exit(0)
            }

            let updated = await updater.update(repo: url)
            print("UPDATE ok=\(updated) \(updater.statusLabel) | \(updater.detail)")
            let success = updated && updater.isUpToDate
            print("SELFTEST-UPDATE \(success ? "OK" : "FAIL")")
            exit(success ? 0 : 1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("SELFTEST-UPDATE TIMEOUT")
            exit(2)
        }
        app.run()
    }
}
