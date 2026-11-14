import Foundation
import AppKit

// MARK: - Build model

enum BuildPhase: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
    case cancelled

    var isRunning: Bool { self == .running }

    var label: String {
        switch self {
        case .idle: return "Prête"
        case .running: return L.t("Build en cours", "Build running")
        case .succeeded: return "Terminée"
        case .failed: return "Échec"
        case .cancelled: return "Annulée"
        }
    }
}

enum StageState: Equatable {
    case running, done, warn, failed
}

struct BuildStage: Identifiable, Equatable {
    let id: Int
    var name: String
    var step: String = ""
    var done: Double?
    var total: Double?
    var unit: String = ""
    var est = false
    var note: String = ""
    var frac: Double?
    var eta: Double?
    var elapsed: Double = 0
    var state: StageState = .running
    var summary: String = ""

    var countText: String? {
        guard let done else { return nil }
        if let total, total > 0 {
            let prefix = est ? "~" : ""
            if unit == "B" {
                return "\(Fmt.bytes(done)) / \(prefix)\(Fmt.bytes(total))"
            }
            let d = NumberFormatter.localizedString(from: NSNumber(value: Int(done)), number: .decimal)
            let t = NumberFormatter.localizedString(from: NSNumber(value: Int(total)), number: .decimal)
            return "\(d) / \(prefix)\(t)\(unit.isEmpty ? "" : " \(unit)")"
        }
        return Fmt.count(done, unit: unit)
    }
}

enum LogKind {
    case info, stage, success, warning, error, dim, stderr
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let time: String
    let text: String
    let kind: LogKind
}

struct BuildArtifact: Equatable {
    var titleID: String?
    var name: String?
    var version: String?
    var bundleID: String?
    var outPath: String?
    var iconPath: String?
}

// MARK: - Line accumulator

private final class LineAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func feed(_ data: Data, eof: Bool) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            let slice = buffer[buffer.startIndex..<index]
            var string = String(decoding: slice, as: UTF8.self)
            if string.hasSuffix("\r") { string.removeLast() }
            lines.append(string)
            buffer.removeSubrange(buffer.startIndex...index)
        }
        if eof, !buffer.isEmpty {
            lines.append(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll()
        }
        return lines
    }
}

// MARK: - Runner

@MainActor
final class BuildRunner: ObservableObject {
    @Published private(set) var phase: BuildPhase = .idle
    @Published private(set) var stages: [BuildStage] = []
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var artifact = BuildArtifact()
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var currentK = 0
    @Published private(set) var totalN = 0
    @Published private(set) var overallFrac: Double = 0
    @Published private(set) var currentStage: BuildStage?
    @Published private(set) var lastError: String?
    @Published private(set) var gameName: String?
    @Published private(set) var cachedIconPath: String?
    @Published private(set) var startedGameID: String?
    @Published private(set) var command: [String] = []
    @Published var autoScroll = true

    private var process: Process?
    private var stdoutAcc = LineAccumulator()
    private var stderrAcc = LineAccumulator()
    private var cancelledByUser = false
    private var logHandle: FileHandle?
    private var logFileURL: URL?
    private var activeOptions: BuildOptions?
    private var activeGame: Game?
    private var activeRepo: URL?

    var onFinish: ((BuildRecord) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let process = self.process, process.isRunning else { return }
                ProcessTree.terminate(pid: process.processIdentifier)
            }
        }
    }

    // MARK: Lifecycle

    func start(repo: URL, game: Game?, options: BuildOptions) {
        guard !phase.isRunning else { return }

        let expandedSource = (options.sourcePath as NSString).expandingTildeInPath
        let script = repo.appendingPathComponent("scripts/build_ipa_from_nsp.py")

        // The script packs a game from a folder of NSPs (or a dump / NUP).
        // When the user picked a single package file, stage it alone in a
        // temporary folder so no other NSP on the Desktop is picked up.
        let sourceURL = URL(fileURLWithPath: expandedSource)
        let packageExtensions: Set<String> = ["nsp", "xci", "nsz", "xcz"]
        let isPackageFile = sourceURL.isFileURL
            && packageExtensions.contains(sourceURL.pathExtension.lowercased())

        // The extracted game and the packaged app need room; stop before the
        // pipeline starts rather than half-way through. Check the volume that
        // will actually hold the extraction (the staging folder for package
        // files, the repository otherwise).
        let requiredGB = options.romfsSeparate ? 6.0 : 12.0
        let spaceTarget = isPackageFile ? Self.stagingFolder(for: sourceURL) : repo
        if let free = Self.freeSpace(at: spaceTarget), free < requiredGB * 1_073_741_824 {
            phase = .failed("Espace disque insuffisant : \(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)) libres, \(Int(requiredGB)) Go recommandés.")
            lastError = "Espace disque insuffisant pour ce build."
            finishedAt = Date()
            return
        }

        var packArgument = expandedSource
        if isPackageFile {
            // Stable staging folder: the extracted files stay cached between
            // builds, and the folder holds this package alone.
            let stage = Self.stagingFolder(for: sourceURL)
            try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            // Only the stale links are removed: the extracted files in
            // `<title>_build` stay cached between builds.
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: stage, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
            for entry in entries {
                let isLink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                if isLink { try? FileManager.default.removeItem(at: entry) }
            }
            // Link the base package and every sibling with the same title ID
            // (updates, DLC), so the script can pick the newest version.
            let selected = options.includedPackages.isEmpty
                ? Self.packagesBeside(sourceURL)
                : options.includedPackages.map { URL(fileURLWithPath: $0) }
            for sibling in selected {
                let link = stage.appendingPathComponent(sibling.lastPathComponent)
                try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: sibling)
            }
            packArgument = stage.path
        }

        var args: [String] = [script.path, packArgument]
        args += options.arguments()
        if isPackageFile, options.outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = Self.outputName(for: sourceURL)
            let ext = options.platform == .macApp ? "app" : "ipa"
            let out = sourceURL.deletingLastPathComponent()
                .appendingPathComponent("\(name).\(ext)")
            args += ["-o", out.path]
        }
        args += ["--progress", "json"]

        let process = Process()
        if let python = Self.pythonExecutable() {
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3"] + args
        }
        process.currentDirectoryURL = repo
        process.environment = Self.environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Fresh state
        phase = .running
        stages = []
        log = []
        artifact = BuildArtifact()
        currentK = 0
        totalN = 0
        overallFrac = 0
        currentStage = nil
        lastError = nil
        startedAt = Date()
        finishedAt = nil
        gameName = game?.name
        cachedIconPath = nil
        startedGameID = game?.id
        command = [process.executableURL!.path] + (process.arguments ?? [])
        cancelledByUser = false
        stdoutAcc = LineAccumulator()
        stderrAcc = LineAccumulator()
        activeOptions = options
        activeGame = game
        activeRepo = repo

        openLogFile(game: game)

        let name = game?.name ?? URL(fileURLWithPath: expandedSource).lastPathComponent
        appendLog("Build de \(name) · \(options.platform.title)", kind: .info, stamp: true)
        appendLog("$ " + Self.prettyCommand(command), kind: .dim, stamp: false)
        writeLog("$ " + Self.prettyCommand(command))

        let outAcc = stdoutAcc
        let errAcc = stderrAcc
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                let tail = outAcc.feed(Data(), eof: true)
                if !tail.isEmpty {
                    DispatchQueue.main.async { self?.ingest(tail, isStdout: true) }
                }
                return
            }
            let lines = outAcc.feed(data, eof: false)
            if !lines.isEmpty {
                DispatchQueue.main.async { self?.ingest(lines, isStdout: true) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                let tail = errAcc.feed(Data(), eof: true)
                if !tail.isEmpty {
                    DispatchQueue.main.async { self?.ingest(tail, isStdout: false) }
                }
                return
            }
            let lines = errAcc.feed(data, eof: false)
            if !lines.isEmpty {
                DispatchQueue.main.async { self?.ingest(lines, isStdout: false) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.finish(status: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            appendLog("Impossible de lancer python3 : \(error.localizedDescription)", kind: .error, stamp: true)
            finishedAt = Date()
            closeLogFile()
            let record = BuildRecord(
                titleID: game?.id ?? "",
                name: game?.name ?? "Build",
                date: Date(),
                succeeded: false,
                seconds: 0,
                outputPath: options.outputPath.isEmpty ? nil : options.outputPath,
                platform: options.platform.rawValue
            )
            onFinish?(record)
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        cancelledByUser = true
        appendLog("Interruption demandée (SIGINT)…", kind: .warning, stamp: true)
        let pid = process.processIdentifier
        ProcessTree.terminate(pid: pid)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if process.isRunning {
                ProcessTree.terminate(pid: pid, signal: SIGKILL)
            }
        }
    }

    func reset() {
        guard !phase.isRunning else { return }
        phase = .idle
        stages = []
        log = []
        artifact = BuildArtifact()
        overallFrac = 0
        currentK = 0
        totalN = 0
        currentStage = nil
        lastError = nil
        startedAt = nil
        finishedAt = nil
    }

    // MARK: Ingestion

    private func ingest(_ lines: [String], isStdout: Bool) {
        for line in lines {
            if isStdout, line.hasPrefix("{"), let object = Self.jsonObject(line) {
                handle(event: object)
            } else {
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if isStdout {
                    appendLog(text, kind: .dim, stamp: false)
                } else {
                    appendLog(text, kind: .stderr, stamp: false)
                }
                writeLog(line)
            }
        }
    }

    private func handle(event: [String: Any]) {
        let ev = event["ev"] as? String ?? ""
        let k = event["k"] as? Int ?? currentK

        switch ev {
        case "stage":
            let name = event["name"] as? String ?? L.t("Étape \(k)", "Step \(k)")
            let step = event["step"] as? String ?? ""
            if let n = event["n"] as? Int { totalN = n }
            if k > 0 { currentK = k }
            var stage = BuildStage(id: k, name: name, step: step)
            if let index = stages.firstIndex(where: { $0.id == k }) {
                stage = stages[index]
                stage.name = name
                stage.step = step
                stage.state = .running
                stages[index] = stage
            } else {
                stages.append(stage)
            }
            currentStage = stage
            updateOverall()
            appendLog("[\(k)/\(totalN)] \(name)\(step.isEmpty ? "" : " · \(step)")", kind: .stage, stamp: true)
            writeLog("[\(k)/\(totalN)] \(name) · \(step)")

        case "step":
            let step = event["step"] as? String ?? ""
            if k > 0 { currentK = k }
            if let index = stages.firstIndex(where: { $0.id == k }) {
                stages[index].step = step
                if stages[index].state == .running {
                    stages[index].done = nil
                    stages[index].total = nil
                    stages[index].frac = nil
                }
                currentStage = stages[index]
            }
            if !step.isEmpty {
                appendLog("  ↳ \(step)", kind: .dim, stamp: true)
                writeLog("  ↳ \(step)")
            }

        case "progress":
            if k > 0 { currentK = k }
            guard let index = stages.firstIndex(where: { $0.id == k }) else { break }
            var stage = stages[index]
            if let step = event["step"] as? String, !step.isEmpty { stage.step = step }
            stage.done = event["done"] as? Double
            stage.total = event["total"] as? Double
            if let unit = event["unit"] as? String { stage.unit = unit }
            if let est = event["est"] as? Bool { stage.est = est }
            if let note = event["note"] as? String { stage.note = note }
            if let frac = event["frac"] as? Double { stage.frac = frac }
            if let eta = event["eta"] as? Double { stage.eta = eta }
            if let elapsed = event["elapsed"] as? Double { stage.elapsed = elapsed }
            stages[index] = stage
            currentStage = stage
            updateOverall()

        case "stage_end":
            guard let index = stages.firstIndex(where: { $0.id == k }) else { break }
            let ok = event["ok"] as? Bool ?? true
            let warn = event["warn"] as? Bool ?? false
            var stage = stages[index]
            stage.state = ok ? (warn ? .warn : .done) : .failed
            stage.summary = event["summary"] as? String ?? ""
            stage.elapsed = event["elapsed"] as? Double ?? stage.elapsed
            stage.frac = ok ? 1 : stage.frac
            stages[index] = stage
            currentStage = stage
            let glyph = ok ? (warn ? "⚠" : "✓") : "✗"
            appendLog("\(glyph) \(stage.name) · \(Fmt.duration(stage.elapsed))\(stage.summary.isEmpty ? "" : " — \(stage.summary)")",
                      kind: ok ? (warn ? .warning : .success) : .error, stamp: true)
            writeLog("\(glyph) \(stage.name) — \(stage.summary)")

        case "say":
            let raw = event["msg"] as? String ?? ""
            if raw.hasPrefix("[RED] ") {
                let message = String(raw.dropFirst(6))
                lastError = message
                appendLog(message, kind: .error, stamp: true)
                writeLog("[error] \(message)")
            } else {
                appendLog(raw, kind: .info, stamp: true)
                writeLog(raw)
            }

        case "shaders_stale":
            let count = event["count"] as? Int ?? 0
            appendLog(L.t("⚠ Bibliothèques de shaders à reconstruire (\(count) bibliothèques)", "⚠ Shader libraries to rebuild (\(count) libraries)"), kind: .warning, stamp: true)

        case "game":
            artifact = BuildArtifact(
                titleID: event["title_id"] as? String,
                name: event["name"] as? String,
                version: event["version"] as? String,
                bundleID: event["bundle_id"] as? String,
                outPath: event["out"] as? String,
                iconPath: event["icon"] as? String
            )
            if let name = artifact.name, !name.isEmpty { gameName = name }
            if let iconPath = artifact.iconPath, !iconPath.isEmpty {
                cachedIconPath = Self.cacheIcon(at: iconPath, titleID: artifact.titleID)
            }
            if let out = artifact.outPath {
                appendLog("Sortie : \(out)", kind: .info, stamp: true)
            }

        default:
            if let message = event["msg"] as? String {
                appendLog(message, kind: .info, stamp: true)
            }
        }
    }

    private func updateOverall() {
        guard totalN > 0 else { overallFrac = 0; return }
        let current = stages.first { $0.id == currentK }
        let within = current?.frac ?? (current?.state == .running ? 0 : 1)
        let completed = Double(max(currentK - 1, 0))
        overallFrac = min(0.995, (completed + within) / Double(totalN))
    }

    // MARK: Finish

    private func finish(status: Int32) {
        guard phase.isRunning else { return }
        finishedAt = Date()
        let seconds = finishedAt!.timeIntervalSince(startedAt ?? finishedAt!)

        if cancelledByUser {
            phase = .cancelled
            appendLog("Build annulée.", kind: .warning, stamp: true)
            writeLog("[cancelled]")
        } else if status == 0 {
            phase = .succeeded
            overallFrac = 1
            appendLog("✓ Build terminée en \(Fmt.duration(seconds)).", kind: .success, stamp: true)
            if let out = artifact.outPath {
                appendLog("→ \(out)", kind: .info, stamp: false)
            }
            writeLog("[done] \(Fmt.duration(seconds))")
        } else {
            let reason = lastError ?? Self.exitDescription(status)
            phase = .failed(reason)
            appendLog("✗ Build arrêtée : \(reason)", kind: .error, stamp: true)
            writeLog("[failed] \(reason)")
        }

        process = nil
        closeLogFile()

        guard let options = activeOptions else { return }
        let record = BuildRecord(
            titleID: artifact.titleID ?? activeGame?.id ?? "",
            name: artifact.name ?? activeGame?.name ?? gameName ?? "Build",
            date: finishedAt ?? Date(),
            succeeded: status == 0 && !cancelledByUser,
            seconds: seconds,
            outputPath: artifact.outPath ?? (options.outputPath.isEmpty ? nil : options.outputPath),
            platform: options.platform.rawValue,
            iconPath: cachedIconPath ?? artifact.iconPath
        )
        onFinish?(record)
    }

    // MARK: Log

    private func appendLog(_ text: String, kind: LogKind, stamp: Bool) {
        let line = LogLine(time: stamp ? Fmt.clock(Date()) : "", text: text, kind: kind)
        log.append(line)
        if log.count > 6000 { log.removeFirst(log.count - 6000) }
    }

    var logText: String {
        log.map { ($0.time.isEmpty ? "" : "[\($0.time)] ") + $0.text }.joined(separator: "\n")
    }

    private func openLogFile(game: Game?) {
        let fm = FileManager.default
        guard let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("Logs/NXN Studio", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\((game?.id ?? "build"))-\(stamp).log"
        let url = dir.appendingPathComponent(filename)
        fm.createFile(atPath: url.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: url)
        logFileURL = url
    }

    private func writeLog(_ text: String) {
        guard let logHandle, let data = (text + "\n").data(using: .utf8) else { return }
        try? logHandle.write(contentsOf: data)
    }

    private func closeLogFile() {
        try? logHandle?.close()
        logHandle = nil
    }

    var logFile: URL? { logFileURL }

    // MARK: Demo (design preview only)

    func loadDemo() {
        phase = .running
        startedAt = Date().addingTimeInterval(-6 * 60 - 12)
        finishedAt = nil
        gameName = "Mario Kart World"
        startedGameID = "0400C3F00006E000"
        totalN = 9
        currentK = 4
        overallFrac = 0.41
        lastError = nil
        artifact = BuildArtifact()

        stages = [
            BuildStage(id: 1, name: "extract MarioKartWorld", done: 9.03e9, total: 9.03e9, unit: "B",
                       frac: 1, elapsed: 142, state: .done, summary: "18,214 files, 8.4 GB"),
            BuildStage(id: 2, name: "survey / profile", step: "shader split",
                       frac: 1, elapsed: 561, state: .done, summary: "6,132 shaders → 1,402 libraries"),
            BuildStage(id: 3, name: "rewrite modules", step: "census",
                       frac: 1, elapsed: 32, state: .done, summary: "4 modules, 2 318 sites"),
            BuildStage(id: 4, name: "build shader libraries", step: "compiling 4 112 / 6 132",
                       done: 4112, total: 6132, unit: "shaders", note: "Metal 4 · g14s",
                       frac: 0.67, eta: 128, elapsed: 126, state: .running),
            BuildStage(id: 5, name: "pack RomFS", state: .running),
            BuildStage(id: 6, name: "pack DLC"),
            BuildStage(id: 7, name: "build IPA"),
            BuildStage(id: 8, name: "pipeline archive"),
            BuildStage(id: 9, name: "finalize"),
        ]
        currentStage = stages[3]

        let samples: [(String, String, LogKind)] = [
            ("17:42:06", "Build of Mario Kart World · Mac app", .info),
            ("17:42:06", "$ /usr/bin/env python3 scripts/build_ipa_from_nsp.py ~/Games/MarioKartWorld --platform mac-app", .dim),
            ("17:42:09", "[1/9] extract MarioKartWorld", .stage),
            ("17:44:31", "✓ extract MarioKartWorld · 2:22 — 18,214 files, 8.4 GB", .success),
            ("17:44:31", "[2/9] survey / profile · shader split", .stage),
            ("17:44:33", "  ↳ reading Shader/*.Nin_Ounce_NVN2.bfsha.zs", .dim),
            ("17:53:52", "✓ shader split · 9:21 — 6,132 shaders → 1,402 libraries", .success),
            ("17:53:52", "[3/9] rewrite modules · census", .stage),
            ("17:54:24", "✓ rewrite modules · 0:32 — 4 modules, 2 318 sites", .success),
            ("17:54:24", "[4/9] build shader libraries · compiling 4 112 / 6 132", .stage),
            ("17:54:25", "  ↳ Metal 4 · g14s · warm cache", .dim),
            ("17:54:25", "shader libraries from the previous chain are reused", .info),
            ("17:56:30", "library 1,402/1,402 · 1.9/~3.0 GB", .info),
        ]
        log = samples.map { LogLine(time: $0.0, text: $0.1, kind: $0.2) }
        command = ["python3", "scripts/build_ipa_from_nsp.py", "~/Games/MarioKartWorld", "--platform", "mac-app", "--progress", "json"]
    }

    // MARK: Helpers

    /// The build folder can be cleaned; keep a copy of the game icon for the library.
    /// A title ID is 16 hex digits. Anything else becomes a random name so a
    /// crafted value can never escape the cache directory.
    /// Absolute interpreter path, resolved once: `/usr/bin/env` would pick
    /// Apple's Python 3.9 when the app is launched from Finder.
    nonisolated static func pythonExecutable() -> String? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static func safeIdentifier(_ raw: String?) -> String {
        guard let raw else { return UUID().uuidString }
        let hex = raw.filter { $0.isHexDigit }
        return hex.count == 16 && hex.count == raw.count ? hex : UUID().uuidString
    }

    private static func cacheIcon(at path: String, titleID: String?) -> String? {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard fm.fileExists(atPath: source.path) else { return nil }
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("NXN Studio/Icons", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = Self.safeIdentifier(titleID)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
        let destination = dir.appendingPathComponent("\(id).\(ext)")
        try? fm.removeItem(at: destination)
        do {
            try fm.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    static func prettyCommand(_ args: [String]) -> String {
        args.map { token in
            if token.contains(" ") || token.contains("(") || token.contains(")") {
                return "\"\(token)\""
            }
            return token
        }.joined(separator: " ")
    }

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func exitDescription(_ code: Int32) -> String {
        switch code {
        case 1: return "erreur du script (code 1)"
        case 2: return "arguments invalides (code 2)"
        case 130: return "interrompue (code 130)"
        default: return "code de sortie \(code)"
        }
    }

    /// `~/Library/Application Support/NXN Studio/Builds/<stable key>`: one
    /// folder per source package, so extraction is reused between builds.
    private static func stagingFolder(for source: URL) -> URL {
        var hash: UInt64 = 5381
        for byte in source.path.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NXN Studio/Builds", isDirectory: true)
        return base.appendingPathComponent(String(hash, radix: 16), isDirectory: true)
    }

    /// The chosen package plus the .nsp files beside it that carry the same
    /// 16-hex title ID.
    private static func packagesBeside(_ source: URL) -> [URL] {
        let folder = source.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        let nsps = siblings.filter { $0.pathExtension.lowercased() == "nsp" }

        let name = source.lastPathComponent
        let range = name.range(of: "\\[[0-9A-Fa-f]{16}\\]", options: .regularExpression)
        guard let range else { return [source] }
        let token = String(name[range])

        let matches = nsps.filter { $0.lastPathComponent.contains(token) }
        return matches.contains(source) ? matches : [source] + matches
    }

    /// Readable app name from a package file name:
    /// `[Game] Mario Kart 8 Deluxe [0100…][v0].nsp` → `Mario Kart 8 Deluxe`.
    private static func outputName(for source: URL) -> String {
        var name = source.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "^\\[Game\\]\\s*", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Game" : name
    }

    private static func freeSpace(at url: URL) -> Double? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map(Double.init)
    }

    /// Keeps the log folder bounded: the 40 newest builds, nothing older than
    /// 30 days.
    static func pruneLogs() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = base.appendingPathComponent("Logs/NXN Studio", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let sorted = files
            .filter { $0.pathExtension == "log" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        for (index, file) in sorted.enumerated() {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if index >= 40 || date < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    private static func environment() -> [String: String] {
        // Same PATH ordering as the rest of the app: Homebrew first, so
        // `python3` is the toolchain build and not Apple's 3.9.
        var env = ShellRunner.environment()
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        if env["HOME"] == nil {
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        return env
    }
}
