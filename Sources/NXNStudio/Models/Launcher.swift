import Foundation
import AppKit

// MARK: - Installed game

struct InstalledGame: Identifiable, Hashable {
    var id: String { path.path }
    let path: URL
    let name: String
    let bundleID: String
    let titleID: String?
    let version: String
    let modified: Date
    var icon: NSImage?

    func hash(into hasher: inout Hasher) { hasher.combine(path.path) }
    static func == (lhs: InstalledGame, rhs: InstalledGame) -> Bool { lhs.path == rhs.path }
}

// MARK: - Scanner

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var games: [InstalledGame] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?

    private var knownTitleIDs: Set<String> = []

    /// Directories that can hold a build made by nxnative.
    private var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Library/Application Support/NXN Studio/Builds"),
            URL(fileURLWithPath: "/Applications"),
        ]
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func scan(records: [BuildRecord] = [], titleIDs: [String] = []) async {
        guard !isScanning else { return }
        isScanning = true
        knownTitleIDs = Set(titleIDs.map { $0.lowercased() })
        defer { isScanning = false }

        let recordPaths = records.compactMap { record -> String? in
            guard let out = record.outputPath, out.hasSuffix(".app") else { return nil }
            return out
        }
        let roots = self.roots
        let known = knownTitleIDs

        let found = await Task.detached(priority: .userInitiated) {
            Self.collect(roots: roots, recordPaths: recordPaths, knownTitleIDs: known)
        }.value

        // App icons come from AppKit and stay on the main actor.
        games = found.map { game in
            var copy = game
            copy.icon = NSWorkspace.shared.icon(forFile: game.path.path)
            return copy
        }
        lastScan = Date()
    }

    func add(contentsOf urls: [URL]) {
        var merged = Dictionary(uniqueKeysWithValues: games.map { ($0.path.path, $0) })
        for url in urls {
            if let game = Self.inspect(url) { merged[url.standardizedFileURL.path] = game }
        }
        games = merged.values.sorted {
            $0.modified == $1.modified ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                                      : $0.modified > $1.modified
        }
    }

    func reveal(_ game: InstalledGame) {
        NSWorkspace.shared.activateFileViewerSelecting([game.path])
    }

    func open(_ game: InstalledGame) {
        NSWorkspace.shared.openApplication(at: game.path, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Internals

    /// Only `org.nxnative.<16 hex>` bundles are offered as games.
    nonisolated static func isGameBundleID(_ id: String) -> Bool {
        let parts = id.split(separator: ".")
        guard parts.count == 3, parts[0] == "org", parts[1] == "nxnative" else { return false }
        let suffix = parts[2]
        return suffix.count == 16 && suffix.allSatisfy(\.isHexDigit)
    }

    nonisolated static func inspect(_ bundle: URL) -> InstalledGame? {
        guard bundle.pathExtension.lowercased() == "app",
              let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        else { return nil }
        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        guard isGameBundleID(bundleID) else { return nil }

        let titleID = bundleID.split(separator: ".").last.map(String.init)
        let looksLikeTitle = titleID?.count == 16 && titleID?.allSatisfy(\.isHexDigit) == true
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let modified = (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return InstalledGame(
            path: bundle,
            name: name,
            bundleID: bundleID,
            titleID: looksLikeTitle ? titleID : nil,
            version: version,
            modified: modified,
            icon: nil
        )
    }

    nonisolated private static func collect(roots: [URL], recordPaths: [String], knownTitleIDs: Set<String>) -> [InstalledGame] {
        let fm = FileManager.default
        var bundles: [URL] = []

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > 4 { enumerator.skipDescendants(); continue }
                if url.pathExtension.lowercased() == "app" {
                    bundles.append(url)
                    enumerator.skipDescendants()
                }
            }
        }

        for path in recordPaths {
            let url = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: url.path) { bundles.append(url) }
        }

        var seen = Set<String>()
        var games: [InstalledGame] = []

        for bundle in bundles where seen.insert(bundle.standardizedFileURL.path).inserted {
            if let game = inspect(bundle) { games.append(game) }
        }

        return games.sorted {
            $0.modified == $1.modified ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                                      : $0.modified > $1.modified
        }
    }
}
