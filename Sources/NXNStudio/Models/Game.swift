import Foundation

// MARK: - Game profile (dm/games/<title id>/game.tsv)

struct Game: Identifiable, Hashable {
    let id: String              // title ID, 16 hex digits
    let name: String
    let ipaName: String?
    let category: String?
    let profileURL: URL
    let isSwitch2: Bool

    var monogram: String {
        let words = name
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .filter { $0.first?.isLetter == true && $0.lowercased() != "the" }
        let letters = words.prefix(2).compactMap { $0.first }
        if letters.isEmpty { return String(id.prefix(2)).uppercased() }
        return letters.map(String.init).joined().uppercased()
    }

    var shortID: String { String(id.suffix(8)) }
    var platformLabel: String { isSwitch2 ? "Switch 2" : "Switch" }

    static func load(from profilesDirectory: URL) -> [Game] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var games: [Game] = []
        for entry in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let tsv = entry.appendingPathComponent("game.tsv")
            guard fm.fileExists(atPath: tsv.path),
                  let text = try? String(contentsOf: tsv, encoding: .utf8) else { continue }

            let fields = parseTSV(text)
            guard let titleID = fields["title_id"] ?? Optional(entry.lastPathComponent),
                  titleID.count == 16, titleID.allSatisfy(\.isHexDigit) else { continue }

            let name = (fields["name"]?.isEmpty == false ? fields["name"]! : entry.lastPathComponent)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            games.append(Game(
                id: titleID.lowercased(),
                name: name,
                ipaName: fields["ipa"],
                category: fields["app_category"],
                profileURL: entry,
                isSwitch2: titleID.lowercased().hasPrefix("04")
            ))
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parseTSV(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, result[key] == nil else { continue }
            result[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}

// MARK: - Repository

struct RepoStatus: Equatable {
    var url: URL?
    var isValid = false
    var message: String = "Aucun dossier nxnative sélectionné"
    var gamesCount = 0
}

enum RepoInspector {
    static func inspect(_ url: URL?) -> RepoStatus {
        guard let url else { return RepoStatus() }
        let fm = FileManager.default
        let script = url.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        let profiles = url.appendingPathComponent("dm/games")

        guard fm.fileExists(atPath: url.path) else {
            return RepoStatus(url: url, isValid: false, message: "Dossier introuvable")
        }
        guard fm.fileExists(atPath: script.path) else {
            return RepoStatus(url: url, isValid: false,
                              message: "build_ipa_from_nsp.py absent — ce n'est pas un checkout nxnative")
        }
        guard fm.fileExists(atPath: profiles.path) else {
            return RepoStatus(url: url, isValid: false, message: "dm/games absent")
        }
        let games = Game.load(from: profiles)
        return RepoStatus(
            url: url,
            isValid: true,
            message: "\(games.count) profils de jeux détectés",
            gamesCount: games.count
        )
    }
}

// MARK: - Build configuration

enum BuildPlatform: String, CaseIterable, Identifiable {
    case ios = "ios"
    case macApp = "mac-app"
    case mac = "mac"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ios: return "iPhone & iPad"
        case .macApp: return "App Mac"
        case .mac: return "Développement"
        }
    }

    var subtitle: String {
        switch self {
        case .ios: return "IPA non signé à sideloader"
        case .macApp: return "App autonome double-cliquable"
        case .mac: return "Hôte Mac, sans packager"
        }
    }

    var icon: String {
        switch self {
        case .ios: return "iphone.gen3"
        case .macApp: return "macbook"
        case .mac: return "wrench.and.screwdriver"
        }
    }

    var outputExtension: String? {
        switch self {
        case .ios: return "ipa"
        case .macApp: return "app"
        case .mac: return nil
        }
    }
}

struct BuildOptions: Equatable {
    var sourcePath: String = ""
    var keysPath: String = ""
    var platform: BuildPlatform = .macApp
    var outputPath: String = ""

    var romfsSeparate = false
    var shaderFiles = false
    var keepExtracted = true
    var seenShaders = false
    var showFPS = true
    var motion = true

    var packageVersion = ""
    var appName = ""
    var bundleID = ""
    var iconPath = ""
    var language = ""
    var teamID = ""
    var gpu = ""
    var workDir = ""

    /// Package files to include when the source is a single .nsp. Empty means
    /// every sibling with the same title ID.
    var includedPackages: [String] = []

    var allowOtherMetal = false
    var allowDamaged = false
    var allowShaderRegressions = false
    var surveyOnly = false

    var sourceURL: URL? { sourcePath.isEmpty ? nil : URL(fileURLWithPath: (sourcePath as NSString).expandingTildeInPath) }
    var isNUP: Bool { sourceURL?.pathExtension.lowercased() == "nup" }
    var keysRequired: Bool { !isNUP }

    var isReady: Bool {
        guard let url = sourceURL else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return true
    }

    /// Human-readable command, one argument per token, with the repo script prefixed by the caller.
    func arguments() -> [String] {
        var args: [String] = []

        func add(_ flag: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            args += [flag, trimmed]
        }

        add("-k", keysPath)
        add("--platform", platform.rawValue)
        add("-o", outputPath)
        if romfsSeparate { args += ["--romfs", "separate"] }
        if shaderFiles { args.append("--shader-files") }
        args.append(keepExtracted ? "--keep-extracted" : "--no-keep-extracted")
        if seenShaders { args.append("--seen-shaders") }
        if !showFPS { args.append("--no-show-fps") }
        if !motion { args.append("--no-motion") }

        add("--package", packageVersion)
        add("--app-name", appName)
        add("--bundle-id", bundleID)
        add("--icon", iconPath)
        add("--language", language)
        add("--team-id", teamID)
        add("--gpu", gpu)
        add("--work-dir", workDir)

        if allowOtherMetal { args.append("--allow-other-metal") }
        if allowDamaged { args.append("--allow-damaged") }
        if allowShaderRegressions { args.append("--allow-shader-regressions") }
        if surveyOnly { args.append("--survey-only") }
        return args
    }
}

// MARK: - Build records

struct BuildRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var titleID: String
    var name: String
    var date: Date
    var succeeded: Bool
    var seconds: Double
    var outputPath: String?
    var platform: String
    var iconPath: String?

    var outputURL: URL? {
        guard let outputPath, !outputPath.isEmpty else { return nil }
        return URL(fileURLWithPath: outputPath)
    }

    var outputExists: Bool {
        guard let outputURL else { return false }
        return FileManager.default.fileExists(atPath: outputURL.path)
    }

    var isApp: Bool { outputURL?.pathExtension.lowercased() == "app" }
}
