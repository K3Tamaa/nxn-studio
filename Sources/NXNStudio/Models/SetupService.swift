import Foundation
import AppKit

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

    func installHomebrew() async {
        guard !isRunning else { return }
        isRunning = true
        task = .homebrew
        lastError = nil
        log = ["Préparation de l'installation de Homebrew…"]
        showSheet = true
        defer { isRunning = false }

        do {
            let script = try await downloadInstaller()
            log.append("macOS va demander votre mot de passe administrateur.")
            let apple = "do shell script \"NONINTERACTIVE=1 /bin/bash '\(script.path)'\" with administrator privileges"
            let result = await ShellRunner.run(["osascript", "-e", apple], onLine: { [weak self] line in
                Task { @MainActor in self?.append(line) }
            })
            guard result.succeeded, homebrewPath != nil else {
                throw SetupError.message(Self.shortError(result) ?? "Homebrew n'a pas pu être installé.")
            }
            log.append("✓ Homebrew installé (\(homebrewPath ?? ""))")
            task = .idle
        } catch {
            lastError = (error as? SetupError)?.text ?? error.localizedDescription
            append("✕ \(lastError ?? "")")
        }
    }

    private func downloadInstaller() async throws -> URL {
        let url = URL(string: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")!
        let (temp, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SetupError.message("Le script d'installation de Homebrew est injoignable.")
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("nxn-brew-install.sh")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
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
