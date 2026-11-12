import Foundation

// MARK: - Install step

struct InstallStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case shell
        case manual
    }

    let id: String
    let title: String
    let command: [String]
    let note: String?
    var kind: Kind = .shell
    var url: URL? = nil

    var isAutomatic: Bool { kind == .shell && !command.isEmpty }
    var commandPreview: String { ShellRunner.pretty(command) }
}

enum InstallCatalog {
    static let steps: [InstallStep] = [
        InstallStep(
            id: "brew",
            title: "Homebrew",
            command: [],
            note: "Script officiel homebrew install, avec mot de passe administrateur.",
            kind: .manual
        ),
        InstallStep(
            id: "git",
            title: "Outils ligne de commande",
            command: ["xcode-select", "--install"],
            note: "macOS ouvre la fenêtre d'installation des Command Line Tools."
        ),
        InstallStep(
            id: "python",
            title: "Python 3.12",
            command: ["brew", "install", "python@3.12"],
            note: "Homebrew installe Python 3.12 dans /opt/homebrew/bin."
        ),
        InstallStep(
            id: "modules",
            title: "Modules Python",
            command: ["python3", "-m", "pip", "install", "--user", "--break-system-packages",
                      "--upgrade", "lz4", "capstone>=5,<6", "fonttools", "nsz", "zbic"],
            note: "lz4, capstone, fonttools, nsz et zbic."
        ),
        InstallStep(
            id: "xcodegen",
            title: "XcodeGen",
            command: ["brew", "install", "xcodegen"],
            note: nil
        ),
        InstallStep(
            id: "zstd",
            title: "zstd",
            command: ["brew", "install", "zstd"],
            note: nil
        ),
        InstallStep(
            id: "glslang",
            title: "glslang",
            command: ["brew", "install", "glslang"],
            note: "Optionnel · jeux Vulkan / OpenGL."
        ),
        InstallStep(
            id: "ios-sdk",
            title: "SDK iOS",
            command: ["xcodebuild", "-downloadPlatform", "iOS"],
            note: "Téléchargement volumineux (plusieurs Go)."
        ),
        InstallStep(
            id: "metal",
            title: "Compilateur Metal",
            command: ["xcodebuild", "-downloadComponent", "MetalToolchain"],
            note: "Téléchargement du composant Metal Toolchain."
        ),
        InstallStep(
            id: "dotnet",
            title: ".NET SDK",
            command: ["brew", "install", "--cask", "dotnet-sdk"],
            note: "macOS peut demander votre mot de passe."
        ),
        InstallStep(
            id: "xcode",
            title: "Xcode",
            command: [],
            note: "Xcode s'installe depuis l'App Store (plusieurs Go).",
            kind: .manual,
            url: URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")
        ),
    ]

    static func step(for id: String) -> InstallStep? {
        steps.first { $0.id == id }
    }

    static var automatic: [InstallStep] {
        steps.filter(\.isAutomatic)
    }
}

// MARK: - Installer

@MainActor
final class DependencyInstaller: ObservableObject {
    enum ItemState: Equatable {
        case queued
        case running
        case succeeded
        case failed(String)
        case skipped(String)
    }

    struct LogLine: Identifiable {
        enum Kind { case command, output, success, failure }
        let id = UUID()
        let text: String
        let kind: Kind
    }

    @Published private(set) var states: [String: ItemState] = [:]
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var runningID: String?
    @Published private(set) var isRunning = false
    @Published private(set) var batchCount = 0
    @Published private(set) var batchDone = 0
    @Published private(set) var lastFailure: String?

    private var runningPID: Int32?
    private var cancelled = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-install") {
            states = [
                "modules": .succeeded,
                "xcodegen": .succeeded,
                "metal": .failed("Error: Download failed"),
                "ios-sdk": .queued,
            ]
            log = [
                LogLine(text: "$ brew install xcodegen", kind: .command),
                LogLine(text: "==> Downloading xcodegen 2.46.0", kind: .output),
                LogLine(text: "==> Pouring xcodegen--2.46.0.arm64.bottle.tar.gz", kind: .output),
                LogLine(text: "✓ XcodeGen installé", kind: .success),
                LogLine(text: "$ xcodebuild -downloadComponent MetalToolchain", kind: .command),
                LogLine(text: "Downloading Metal Toolchain…", kind: .output),
                LogLine(text: "✕ Compilateur Metal : Error: Download failed (code 1)", kind: .failure),
            ]
            batchCount = 5
            batchDone = 3
        }
        #endif
    }

    var statusText: String {
        guard isRunning else { return "" }
        if batchCount > 1 { return "Installation \(min(batchDone + 1, batchCount)) / \(batchCount)" }
        return "Installation en cours…"
    }

    func state(for id: String) -> ItemState? { states[id] }

    func install(_ step: InstallStep, repo: URL?) async {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        lastFailure = nil
        batchCount = 1
        batchDone = 0
        log = []
        states = [:]
        _ = await perform(step, repo: repo)
        batchDone = 1
        isRunning = false
    }

    func installAll(_ steps: [InstallStep], repo: URL?) async {
        guard !isRunning else { return }
        let queue = steps.filter(\.isAutomatic)
        guard !queue.isEmpty else { return }

        isRunning = true
        cancelled = false
        lastFailure = nil
        batchCount = queue.count
        batchDone = 0
        log = []
        states = [:]
        for step in queue { states[step.id] = .queued }

        for step in queue {
            if cancelled { break }
            _ = await perform(step, repo: repo)
            batchDone += 1
        }

        for step in queue where states[step.id] == .queued {
            states[step.id] = .skipped("annulé")
        }
        isRunning = false
    }

    func cancel() {
        guard isRunning, let pid = runningPID else { return }
        cancelled = true
        append("Interruption demandée…", .failure)
        ProcessTree.terminate(pid: pid)
        let deadline = DispatchTime.now() + 3
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if kill(pid, 0) == 0 { ProcessTree.terminate(pid: pid, signal: SIGKILL) }
        }
    }

    func clear() {
        guard !isRunning else { return }
        log = []
        states = [:]
        lastFailure = nil
        batchCount = 0
        batchDone = 0
    }

    // MARK: Execution

    @discardableResult
    private func perform(_ step: InstallStep, repo: URL?) async -> Bool {
        runningID = step.id
        states[step.id] = .running
        append("$ " + step.commandPreview, .command)
        if let note = step.note { append(note, .output) }

        let result = await ShellRunner.run(
            step.command,
            in: repo,
            onLaunch: { [weak self] pid in
                Task { @MainActor in self?.runningPID = pid }
            },
            onLine: { [weak self] line in
                Task { @MainActor in self?.append(line, .output) }
            }
        )

        runningPID = nil
        runningID = nil

        if cancelled {
            states[step.id] = .skipped("interrompu")
            append("✕ \(step.title) : installation interrompue", .failure)
            return false
        }

        if result.succeeded {
            states[step.id] = .succeeded
            append("✓ \(step.title) installé", .success)
            return true
        }

        let message = Self.errorMessage(result) ?? "code \(result.code)"
        states[step.id] = .failed(message)
        lastFailure = "\(step.title) : \(message)"
        append("✕ \(step.title) : \(message)", .failure)
        return false
    }

    private func append(_ text: String, _ kind: LogLine.Kind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.append(LogLine(text: trimmed, kind: kind))
        if log.count > 320 { log.removeFirst(log.count - 320) }
    }

    private static func errorMessage(_ result: ShellResult) -> String? {
        let lines = result.combined
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let error = lines.last(where: { $0.hasPrefix("Error:") || $0.hasPrefix("error:") || $0.hasPrefix("fatal:") }) {
            return error
        }
        return lines.last
    }
}
