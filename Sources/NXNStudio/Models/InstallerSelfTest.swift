import Foundation
import AppKit

/// Headless verification of the dependency installer: streaming, exit codes and
/// per-step state, using harmless local commands.
enum InstallerSelfTest {
    @MainActor
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let installer = DependencyInstaller()
        let steps = [
            InstallStep(
                id: "ok",
                title: "Test succès",
                command: ["/bin/sh", "-c", "echo 'première ligne'; echo 'seconde ligne'; exit 0"],
                note: "Commande locale sans effet."
            ),
            InstallStep(
                id: "fail",
                title: "Test échec",
                command: ["/bin/sh", "-c", "echo 'erreur attendue' >&2; exit 3"],
                note: nil
            ),
        ]

        Task {
            await installer.installAll(steps, repo: nil)
            let ok = installer.state(for: "ok") == .succeeded
            let failed = installer.state(for: "fail") == .failed("erreur attendue")
            print("STEP ok=\(String(describing: installer.state(for: "ok")))")
            print("STEP fail=\(String(describing: installer.state(for: "fail")))")
            print("LOG=\(installer.log.count) LINES=\(installer.log.map(\.text).joined(separator: " / "))")
            print("SELFTEST-INSTALL \(ok && failed ? "OK" : "FAIL")")
            exit(ok && failed ? 0 : 1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("SELFTEST-INSTALL TIMEOUT")
            exit(2)
        }
        app.run()
    }
}
