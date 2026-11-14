import Foundation
import AppKit
import CryptoKit

// MARK: - Setup

/// First-run helpers that need privileges or long downloads: installing
/// Homebrew and cloning the nxnative checkout.
@MainActor
final class SetupService: ObservableObject {
    enum Activity: Equatable {
        case idle, homebrew, clone
    }

    @Published private(set) var task: Activity = .idle
    @Published private(set) var log: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published var showSheet = false

    var homebrewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    var hasHomebrew: Bool { homebrewPath != nil }

    var hasXcodeTools: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
            && ShellRunner.runSync(["/usr/bin/xcode-select", "-p"]).code == 0
    }

    // MARK: Homebrew

    /// Pinned to a reviewed commit: `HEAD` could change under a published
    /// checksum. SHA-256 is verified before the script is ever handed over.
    nonisolated static let homebrewInstallerURL = URL(string:
        "https://raw.githubusercontent.com/Homebrew/install/e5b3c5834e3932c8aaa42deef4794076c9b0cbf0/install.sh")!
    nonisolated static let homebrewInstallerSHA256 =
        "5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148"

    func installHomebrew() async {
        guard !isRunning else { return }
        isRunning = true
        task = .homebrew
        lastError = nil
        log = [L.t("Préparation de l'installation de Homebrew…", "Preparing the Homebrew installation…")]
        showSheet = true
        defer { isRunning = false }

        do {
            let script = try await downloadInstaller()
            log.append(L.t("Script vérifié (SHA-256).", "Script verified (SHA-256)."))
            log.append(L.t("L'installation s'ouvre dans Terminal ; Homebrew demandera votre mot de passe si nécessaire.", "The installer opens in Terminal; Homebrew will ask for your password if needed."))
            openInTerminal(script)
            log.append(L.t("✓ Installation lancée dans Terminal", "✓ Installer started in Terminal"))
            task = .idle
        } catch {
            lastError = (error as? SetupError)?.text ?? error.localizedDescription
            append("✕ \(lastError ?? "")")
        }
    }

    /// Runs the installer as the logged-in user in Terminal: the app never
    /// executes it as root and never handles the admin prompt itself.
    private func openInTerminal(_ script: URL) {
        let command = "NONINTERACTIVE=1 /bin/bash '\(script.path)'"
        let apple = "tell application \"Terminal\" to do script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        _ = ShellRunner.runSync(["osascript", "-e", apple])
        NSWorkspace.shared.launchApplication("Terminal")
    }

    private func downloadInstaller() async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: Self.homebrewInstallerURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SetupError.message("Le script d'installation de Homebrew est injoignable.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("nxn-brew-install.sh")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        guard Self.verifyInstaller(at: destination, expectedSHA256: Self.homebrewInstallerSHA256) else {
            try? FileManager.default.removeItem(at: destination)
            throw SetupError.message("Le script Homebrew ne correspond pas à l'empreinte attendue. Installation refusée.")
        }
        return destination
    }

    nonisolated static func verifyInstaller(at url: URL, expectedSHA256: String) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame
    }

    // MARK: Clone

    func clone(into folder: URL) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        task = .clone
        lastError = nil
        log = ["$ git clone https://github.com/seedds/nxnative.git \"\(folder.path)\""]
        showSheet = true
        defer { isRunning = false }

        let result = await ShellRunner.run(
            ["git", "clone", "--progress", "https://github.com/seedds/nxnative.git", folder.path],
            onLine: { [weak self] line in
                Task { @MainActor in self?.append(line) }
            }
        )

        guard result.succeeded else {
            lastError = Self.shortError(result) ?? "Le clone a échoué."
            append("✕ \(lastError ?? "")")
            return false
        }
        log.append("✓ nxnative cloné dans \(folder.path)")
        task = .idle
        return true
    }

    func close() {
        guard !isRunning else { return }
        showSheet = false
        task = .idle
    }

    // MARK: Helpers

    private func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.append(trimmed)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private static func shortError(_ result: ShellResult) -> String? {
        let lines = result.combined
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last(where: { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") || $0.hasPrefix("Error:") })
            ?? lines.last
    }
}

enum SetupError: Error {
    case message(String)
    var text: String {
        switch self {
        case .message(let text): return text
        }
    }
}
