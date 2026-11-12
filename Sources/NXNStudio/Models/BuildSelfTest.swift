import Foundation
import AppKit

/// Headless verification of the build pipeline bridge: runs a mock build script that
/// emits the same newline-delimited JSON as scripts/build_ipa_from_nsp.py.
enum BuildSelfTest {
    @MainActor
    static func run(repo: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let runner = BuildRunner()
        var options = BuildOptions()
        options.platform = .macApp
        options.sourcePath = repo + "/game.nsp"
        options.keepExtracted = true

        let game = Game(
            id: "0100000000000000",
            name: "Demo Game",
            ipaName: nil,
            category: nil,
            profileURL: URL(fileURLWithPath: repo),
            isSwitch2: false
        )

        runner.onFinish = { record in
            print("PHASE=\(runner.phase)")
            print("STAGES=\(runner.stages.count) CURRENT=\(runner.currentK)/\(runner.totalN)")
            for stage in runner.stages {
                print("STAGE \(stage.id) [\(stage.state)] \(stage.name) — \(stage.summary)")
            }
            print("ARTIFACT title=\(runner.artifact.titleID ?? "nil") name=\(runner.artifact.name ?? "nil") out=\(runner.artifact.outPath ?? "nil")")
            print("LOG=\(runner.log.count) AUTO=\(runner.autoScroll)")
            print("RECORD ok=\(record.succeeded) seconds=\(String(format: "%.2f", record.seconds)) out=\(record.outputPath ?? "nil")")
            let failed = !record.succeeded
            let missing = runner.stages.count != 4
            let badArtifact = runner.artifact.titleID != "0100000000000000"
            print("SELFTEST \(failed || missing || badArtifact ? "FAIL" : "OK")")
            exit(failed || missing || badArtifact ? 1 : 0)
        }

        runner.start(repo: URL(fileURLWithPath: repo), game: game, options: options)

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("SELFTEST TIMEOUT")
            exit(2)
        }
        app.run()
    }
}
