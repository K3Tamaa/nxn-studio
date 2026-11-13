import Foundation
import AppKit
import SwiftUI
import Combine

enum NavigationStyle: String, CaseIterable, Identifiable, Codable {
    case sidebar, dock
    var id: String { rawValue }
    var title: String { self == .sidebar ? L.t("Barre latérale", "Sidebar") : L.t("Dock flottant", "Floating dock") }
    var detail: String {
        self == .sidebar ? L.t("Le menu sur le côté", "The side menu") : L.t("Une barre d'icônes en bas", "An icon bar at the top")
    }
}

enum Route: String, CaseIterable, Identifiable {
    case library, launcher, build, news, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return L.t("Bibliothèque")
        case .launcher: return L.t("Launcher")
        case .build: return L.t("Construire")
        case .news: return L.t("Nouveautés")
        case .settings: return L.t("Réglages")
        }
    }

    var icon: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .launcher: return "play.rectangle.on.rectangle"
        case .build: return "bolt.fill"
        case .news: return "sparkles"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var route: Route = .library
    @Published var themeMode: ThemeMode = .midnight {
        didSet {
            Theme.mode = themeMode
            defaults.set(themeMode.rawValue, forKey: "themeMode")
            appearanceRevision += 1
        }
    }
    @Published var themeAccent: ThemeAccent = .ember {
        didSet {
            Theme.accent = themeAccent
            defaults.set(themeAccent.rawValue, forKey: "themeAccent")
            appearanceRevision += 1
        }
    }
    @Published var language: AppLanguage = .fr {
        didSet {
            L.language = language
            defaults.set(language.rawValue, forKey: "language")
            appearanceRevision += 1
        }
    }
    @Published var navigationStyle: NavigationStyle = .sidebar {
        didSet {
            defaults.set(navigationStyle.rawValue, forKey: "navigationStyle")
        }
    }
    @Published private(set) var appearanceRevision = 0
    @Published var repoPath: String = "" {
        didSet {
            guard oldValue != repoPath else { return }
            defaults.set(repoPath, forKey: "repoPath")
            repoUpdate.reset()
            refreshRepo()
            if autoCheckUpdates {
                Task { await repoUpdate.check(repo: repo.url) }
            }
        }
    }
    @Published var keysPath: String = "" {
        didSet { defaults.set(keysPath, forKey: "keysPath") }
    }
    @Published var defaultPlatform: BuildPlatform = .macApp {
        didSet { defaults.set(defaultPlatform.rawValue, forKey: "defaultPlatform") }
    }

    @Published private(set) var repo = RepoStatus()
    @Published private(set) var games: [Game] = []
    @Published var selection: Game?
    @Published var draft = BuildOptions()
    @Published private(set) var records: [BuildRecord] = []

    let runner = BuildRunner()
    let news = RepoNews()
    let repoUpdate = RepoUpdate()
    let artworks = ArtworkStore()
    let updates = UpdateService()
    let setup = SetupService()
    let launcher = LauncherStore()
    /// Turned off by the snapshotter so demo states are not overwritten by a
    /// real git check.
    var autoCheckUpdates = true
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let raw = UserDefaults.standard.string(forKey: "themeMode"),
           let mode = ThemeMode(rawValue: raw) {
            themeMode = mode
            Theme.mode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "language"),
           let language = AppLanguage(rawValue: raw) {
            self.language = language
            L.language = language
        } else {
            self.language = .en
            L.language = .en
        }
        if let raw = UserDefaults.standard.string(forKey: "navigationStyle"),
           let style = NavigationStyle(rawValue: raw) {
            navigationStyle = style
        }
        if let raw = UserDefaults.standard.string(forKey: "themeAccent"),
           let accent = ThemeAccent(rawValue: raw) {
            themeAccent = accent
            Theme.accent = accent
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot") {
            autoCheckUpdates = false
        }
        #endif
        let storedRepo = defaults.string(forKey: "repoPath") ?? ""
        let storedURL = URL(fileURLWithPath: (storedRepo as NSString).expandingTildeInPath)
        repoPath = !storedRepo.isEmpty && AppState.isCheckout(storedURL)
            ? storedRepo
            : AppState.detectRepoPath()
        keysPath = defaults.string(forKey: "keysPath") ?? AppState.detectKeysPath()
        if let raw = defaults.string(forKey: "defaultPlatform"),
           let platform = BuildPlatform(rawValue: raw) {
            defaultPlatform = platform
        }
        records = AppState.loadRecords()
        draft.platform = defaultPlatform

        news.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        repoUpdate.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        artworks.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        updates.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        setup.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        launcher.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refreshRepo()
        BuildRunner.pruneLogs()

        runner.onFinish = { [weak self] record in
            guard let self else { return }
            self.records.insert(record, at: 0)
            if self.records.count > 60 { self.records = Array(self.records.prefix(60)) }
            AppState.saveRecords(self.records)
            self.notify(record)
        }
    }

    // MARK: Repository

    func refreshRepo() {
        let status = RepoInspector.inspect(URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath))
        repo = status
        games = status.isValid
            ? Game.load(from: URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath).appendingPathComponent("dm/games"))
            : []

        if let selected = selection, !games.contains(where: { $0.id == selected.id }) {
            selection = nil
        }

        artworks.refreshMissing(in: games)
    }

    /// Cover provided by IGDB, if it has been fetched.
    func posterURL(for game: Game) -> URL? {
        artworks.coverURL(for: game.id)
    }

    func wideArtworkURL(for game: Game) -> URL? {
        artworks.artworkURL(for: game.id)
    }


    func chooseRepo() {
        let panel = NSOpenPanel()
        panel.title = "Choisir le dossier nxnative"
        panel.message = "Le dossier cloné depuis github.com/seedds/nxnative"
        panel.prompt = "Choisir"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
            refreshRepo()
        }
    }

    func chooseKeys() {
        let panel = NSOpenPanel()
        panel.title = "Choisir prod.keys"
        panel.message = "Vos clés Switch, nécessaires pour les NSP (pas pour les .nup ou les dumps)"
        panel.prompt = "Choisir"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { keysPath = url.path }
    }

    // MARK: Selection & draft

    func configure(_ game: Game) {
        selection = game
        var options = BuildOptions()
        options.platform = defaultPlatform
        options.keysPath = keysPath
        draft = options
        route = .build
    }

    func chooseSource(for game: Game? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choisir le jeu"
        panel.message = "Un dossier de NSP, un dossier de dump, ou un fichier .nup"
        panel.prompt = "Choisir"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.sourcePath = url.path
            if let game { selection = game }
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        if let ext = draft.platform.outputExtension {
            panel.nameFieldStringValue = suggestedOutputName
            panel.allowedContentTypes = []
            panel.isExtensionHidden = false
            _ = ext
        }
        panel.title = "Choisir la sortie"
        panel.prompt = "Choisir"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.outputPath = url.path
        }
    }

    var suggestedOutputName: String {
        let base = (selection?.name ?? "Game").replacingOccurrences(of: " ", with: "")
        return base + (draft.platform.outputExtension.map { ".\($0)" } ?? "")
    }

    // MARK: Records

    func latestRecord(for game: Game) -> BuildRecord? {
        records.first { $0.titleID == game.id }
    }

    func iconURL(for game: Game) -> URL? {
        for record in records where record.titleID == game.id {
            if let icon = record.iconPath,
               FileManager.default.fileExists(atPath: icon) {
                return URL(fileURLWithPath: icon)
            }
        }
        return nil
    }

    func latestAppRecord(for game: Game) -> BuildRecord? {
        records.first { $0.titleID == game.id && $0.isApp && $0.outputExists }
    }

    func play(_ record: BuildRecord) {
        guard let url = record.outputURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func notify(_ record: BuildRecord) {
        NSSound(named: record.succeeded ? "Glass" : "Basso")?.play()
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func resetHistory() {
        records = []
        AppState.saveRecords(records)
    }

    // MARK: Persistence helpers

    private static func loadRecords() -> [BuildRecord] {
        guard let data = UserDefaults.standard.data(forKey: "buildRecords"),
              let list = try? JSONDecoder().decode([BuildRecord].self, from: data) else { return [] }
        return list
    }

    private static func saveRecords(_ records: [BuildRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "buildRecords")
    }

    private static func detectRepoPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let named = [
            "nxnative",
            "NXNative/nxnative-main",
            "nxnative-oot",
            "nxnative-main",
            "Documents/nxnative",
            "Developer/nxnative",
            "Downloads/nxnative",
            "nxnative/nxnative",
        ]
        for relative in named {
            let candidate = home.appendingPathComponent(relative)
            if isCheckout(candidate) { return candidate.path }
        }

        // Fall back to a single-level scan of the home folder: any folder with
        // the build script counts as a checkout.
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for entry in entries where isCheckout(entry) {
            return entry.path
        }
        return ""
    }

    private static func isCheckout(_ url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appendingPathComponent("scripts/build_ipa_from_nsp.py").path
        )
    }

    private static func detectKeysPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent("keys/prod.keys"),
                          home.appendingPathComponent(".switch/prod.keys"),
                          home.appendingPathComponent("prod.keys")]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return ""
    }
}
