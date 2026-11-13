import Foundation

enum CheckState: Equatable {
    case ok, warn, missing, running, idle

    var color: String {
        switch self {
        case .ok: return "mint"
        case .warn: return "warning"
        case .missing: return "danger"
        case .running, .idle: return "tertiary"
        }
    }
}

struct ToolCheck: Identifiable, Equatable {
    let id: String
    var label: String
    var detail: String
    var state: CheckState
    var hint: String?
    var required: Bool = true

    var symbol: String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .missing: return "xmark.circle.fill"
        case .running, .idle: return "circle.dashed"
        }
    }
}

@MainActor
final class ToolchainChecker: ObservableObject {
    @Published var checks: [ToolCheck] = []
    @Published var isChecking = false
    @Published var lastRun: Date?

    func run(repo: RepoStatus) {
        guard !isChecking else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-missing") {
            checks = Self.demoMissing
            lastRun = Date()
            return
        }
        #endif
        isChecking = true
        checks = Self.placeholders
        Task {
            let results = await Self.collect(repo: repo)
            self.checks = results
            self.isChecking = false
            self.lastRun = Date()
        }
    }

    static let placeholders: [ToolCheck] = [
        ToolCheck(id: "repo", label: L.t("Checkout nxnative", "nxnative checkout"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "brew", label: L.t("Homebrew", "Homebrew"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "git", label: "git", detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "python", label: L.t("Python 3.12+", "Python 3.12+"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "modules", label: L.t("Modules Python", "Python modules"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "xcode", label: "Xcode", detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "ios-sdk", label: "SDK iOS", detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "metal", label: L.t("Compilateur Metal", "Metal compiler"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "xcodegen", label: "XcodeGen", detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "zstd", label: "zstd", detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "dotnet", label: L.t(".NET SDK", ".NET SDK"), detail: L.t("Vérification…"), state: .running),
        ToolCheck(id: "glslang", label: "glslang", detail: L.t("Vérification…"), state: .running, required: false),
    ]

    #if DEBUG
    static let demoMissing: [ToolCheck] = [
        ToolCheck(id: "repo", label: L.t("Checkout nxnative", "nxnative checkout"),
                  detail: "build_ipa_from_nsp.py + dm/games", state: .ok),
        ToolCheck(id: "brew", label: L.t("Homebrew", "Homebrew"), detail: "/opt/homebrew/bin/brew", state: .ok),
        ToolCheck(id: "git", label: "git", detail: "git version 2.51.0", state: .ok),
        ToolCheck(id: "python", label: L.t("Python 3.12+", "Python 3.12+"), detail: "Python 3.15.2", state: .ok),
        ToolCheck(id: "modules", label: L.t("Modules Python", "Python modules"),
                  detail: "missing lz4, capstone, fonttools", state: .missing,
                  hint: "python3 -m pip install lz4 \"capstone>=5,<6\" fonttools nsz zbic"),
        ToolCheck(id: "xcode", label: "Xcode", detail: "Xcode 27.2", state: .ok),
        ToolCheck(id: "ios-sdk", label: "SDK iOS", detail: "absent", state: .missing,
                  hint: "Xcode → Settings → Components → install the iOS platform."),
        ToolCheck(id: "metal", label: L.t("Compilateur Metal", "Metal compiler"), detail: "Metal toolchain missing",
                  state: .missing, hint: "xcodebuild -downloadComponent MetalToolchain"),
        ToolCheck(id: "xcodegen", label: "XcodeGen", detail: "not found", state: .missing,
                  hint: "brew install xcodegen"),
        ToolCheck(id: "zstd", label: "zstd", detail: "*** Zstandard CLI v1.5.7 ***", state: .ok),
        ToolCheck(id: "dotnet", label: L.t(".NET SDK", ".NET SDK"), detail: "SDK 10.0.403", state: .ok),
        ToolCheck(id: "glslang", label: "glslang", detail: "not found (Vulkan / OpenGL games)",
                  state: .warn, hint: "brew install glslang", required: false),
    ]
    #endif

    nonisolated private static func collect(repo: RepoStatus) async -> [ToolCheck] {
        await Task.detached(priority: .userInitiated) {
            var results: [ToolCheck] = []

            // 1. Repository
            results.append(ToolCheck(
                id: "repo", label: L.t("Checkout nxnative", "nxnative checkout"),
                detail: repo.isValid ? "build_ipa_from_nsp.py + dm/games" : repo.message,
                state: repo.isValid ? .ok : .missing,
                hint: repo.isValid ? nil : "Choisissez le dossier cloné de seedds/nxnative."
            ))

            // 1b. Homebrew and git
            let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
                FileManager.default.isExecutableFile(atPath: $0)
            }
            results.append(ToolCheck(
                id: "brew", label: L.t("Homebrew", "Homebrew"),
                detail: brew ?? "not found",
                state: brew == nil ? .missing : .ok,
                hint: "Homebrew installe Python, XcodeGen, zstd et glslang.",
                required: true
            ))

            let git = shell("/usr/bin/env", ["git", "--version"])
            results.append(ToolCheck(
                id: "git", label: "git",
                detail: git.output.trimmingCharacters(in: .whitespacesAndNewlines),
                state: git.code == 0 ? .ok : .missing,
                hint: "xcode-select --install",
                required: true
            ))

            // 2. Python
            let python = shell("/usr/bin/env", ["python3", "--version"])
            let version = python.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let versionNumber = version.replacingOccurrences(of: "Python ", with: "")
            let parts = versionNumber.split(separator: ".").compactMap { Int($0) }
            let recent = parts.count >= 2 && (parts[0] > 3 || (parts[0] == 3 && parts[1] >= 12))
            results.append(ToolCheck(
                id: "python", label: L.t("Python 3.12+", "Python 3.12+"),
                detail: version.isEmpty ? "not found" : version,
                state: python.code == 0 && recent ? .ok : (python.code == 0 ? .warn : .missing),
                hint: "Installez Python 3.12 arm64 (pas celui de Homebrew Intel)."
            ))

            // 3. Modules
            let modules = shell("/usr/bin/env", [
                "python3", "-c",
                "import lz4, capstone, fontTools; print('lz4', lz4.__version__, '· capstone', capstone.__version__)"
            ])
            let moduleDetail = modules.output.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(ToolCheck(
                id: "modules", label: L.t("Modules Python", "Python modules"),
                detail: modules.code == 0 ? moduleDetail : "missing lz4, capstone, fonttools",
                state: modules.code == 0 ? .ok : .missing,
                hint: "python3 -m pip install lz4 \"capstone>=5,<6\" fonttools nsz zbic"
            ))

            // 4. Xcode
            let xcode = shell("/usr/bin/xcodebuild", ["-version"])
            let xcodeDetail = xcode.output.split(separator: "\n").first.map(String.init) ?? "not found"
            results.append(ToolCheck(
                id: "xcode", label: "Xcode",
                detail: xcodeDetail,
                state: xcode.code == 0 ? .ok : .missing,
                hint: "Installez Xcode 27.2 et sélectionnez-le avec xcode-select."
            ))

            // 4b. iOS SDK
            let iosSdk = shell("/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-version"])
            let iosDetail = iosSdk.output.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(ToolCheck(
                id: "ios-sdk", label: "SDK iOS",
                detail: iosSdk.code == 0 && !iosDetail.isEmpty ? "version \(iosDetail)" : "absent",
                state: iosSdk.code == 0 && !iosDetail.isEmpty ? .ok : .missing,
                hint: "Xcode → Settings → Components → install the iOS platform."
            ))

            // 5. Metal compiler
            let metal = shell("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"])
            let metalDetail = metal.output.split(separator: "\n").first.map(String.init) ?? "not found"
            results.append(ToolCheck(
                id: "metal", label: L.t("Compilateur Metal", "Metal compiler"),
                detail: metal.code == 0 ? metalDetail : "Metal toolchain missing",
                state: metal.code == 0 ? .ok : .missing,
                hint: "xcodebuild -downloadComponent MetalToolchain"
            ))

            // 6. XcodeGen
            let xcodegen = shell("/usr/bin/env", ["xcodegen", "--version"])
            let xcodegenDetail = xcodegen.output.split(separator: "\n").first
                .map { $0.replacingOccurrences(of: "Version:", with: "")
                        .trimmingCharacters(in: .whitespaces) } ?? "not found"
            results.append(ToolCheck(
                id: "xcodegen", label: "XcodeGen",
                detail: xcodegen.code == 0 ? xcodegenDetail : "not found",
                state: xcodegen.code == 0 ? .ok : .missing,
                hint: "brew install xcodegen"
            ))

            // 7. zstd
            let zstd = shell("/usr/bin/env", ["zstd", "--version"])
            let zstdDetail = zstd.output.split(separator: "\n").first.map(String.init) ?? "not found"
            results.append(ToolCheck(
                id: "zstd", label: "zstd",
                detail: zstd.code == 0 ? zstdDetail : "not found",
                state: zstd.code == 0 ? .ok : .missing,
                hint: "brew install zstd"
            ))

            // 8. .NET
            let dotnet = shell("/usr/bin/env", ["dotnet", "--version"])
            let dotnetDetail = dotnet.output.split(separator: "\n").first.map(String.init) ?? "not found"
            results.append(ToolCheck(
                id: "dotnet", label: L.t(".NET SDK", ".NET SDK"),
                detail: dotnet.code == 0 ? "SDK \(dotnetDetail)" : "not found",
                state: dotnet.code == 0 ? .ok : .missing,
                hint: "brew install --cask dotnet-sdk"
            ))

            // 9. glslang (optional, Vulkan/OpenGL games)
            let glslang = shell("/usr/bin/env", ["glslangValidator", "--version"])
            let glslangDetail = glslang.output.split(separator: "\n").first
                .map { $0.replacingOccurrences(of: "Glslang Version:", with: "")
                        .trimmingCharacters(in: .whitespaces) } ?? "not found"
            results.append(ToolCheck(
                id: "glslang", label: "glslang",
                detail: glslang.code == 0 ? glslangDetail : "not found (Vulkan / OpenGL games)",
                state: glslang.code == 0 ? .ok : .warn,
                hint: "brew install glslang",
                required: false
            ))

            return results
        }.value
    }

    // MARK: Shell

    nonisolated private static func shell(_ executable: String, _ arguments: [String]) -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (127, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    nonisolated private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Homebrew first: the app is launched from Finder with a minimal PATH,
        // where `python3` would resolve to Apple's 3.9 build.
        let additions = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                         "\(home)/.local/bin", "\(home)/.dotnet", "/usr/local/share/dotnet"]
        var path = additions
        for entry in (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        where !path.contains(entry) {
            path.append(entry)
        }
        env["PATH"] = path.joined(separator: ":")
        return env
    }
}
