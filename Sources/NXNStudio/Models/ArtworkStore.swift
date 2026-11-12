import Foundation
import AppKit

// MARK: - Artwork store

/// Resolves a cover and a wide artwork for every library title through IGDB,
/// downloads them once and keeps a small index on disk.
@MainActor
final class ArtworkStore: ObservableObject {
    struct Entry: Codable, Equatable {
        var file: String            // cover file name
        var artwork: String?        // wide artwork file name
        var igdbName: String
        var igdbID: Int
        var updated: Date
    }

    @Published private(set) var entries: [String: Entry] = [:]
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status: String = ""
    @Published private(set) var lastError: String?
    @Published private(set) var tokenExpiry: Date?
    @Published private(set) var missingCount = 0

    /// Client ID is not secret; the secret itself lives in the Keychain.
    @Published var clientID: String {
        didSet { defaults.set(clientID, forKey: "igdbClientID") }
    }

    var hasSecret: Bool { !secret.isEmpty }

    private let defaults = UserDefaults.standard
    private var secret: String
    private var token: IGDBToken?
    private var cancellation = false

    private let directory: URL
    private let indexURL: URL
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init() {
        clientID = defaults.string(forKey: "igdbClientID") ?? ""
        secret = Keychain.get("igdbSecret") ?? ""

        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NXN Studio/Artwork", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: indexURL),
           let stored = try? ArtworkStore.decoder.decode([String: Entry].self, from: data) {
            entries = stored.reduce(into: [:]) { result, pair in
                result[pair.key.lowercased()] = pair.value
            }
        }
    }

    // MARK: Credentials

    func saveSecret(_ value: String) {
        secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if secret.isEmpty {
            Keychain.delete("igdbSecret")
        } else {
            Keychain.set(secret, account: "igdbSecret")
        }
        token = nil
        tokenExpiry = nil
    }

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty && !secret.isEmpty
    }

    // MARK: Lookup

    func coverURL(for titleID: String) -> URL? {
        guard let entry = entries[titleID.lowercased()] else { return nil }
        let url = directory.appendingPathComponent(entry.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func artworkURL(for titleID: String) -> URL? {
        guard let name = entries[titleID.lowercased()]?.artwork else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var count: Int { entries.count }

    func refreshMissing(in games: [Game]) {
        missingCount = games.filter { entries[$0.id.lowercased()] == nil }.count
    }

    // MARK: Fetch

    func testConnection() async {
        lastError = nil
        status = "Connexion à Twitch…"
        do {
            let token = try await ensureToken(force: true)
            tokenExpiry = token.expires
            status = "Connecté · jeton valable jusqu'à \(Fmt.clock(token.expires))"
        } catch {
            tokenExpiry = nil
            status = ""
            lastError = (error as? IGDBError)?.errorDescription ?? error.localizedDescription
        }
    }

    func fetchAll(games: [Game], force: Bool = false) async {
        guard !isRunning else { return }
        guard isConfigured else {
            lastError = "Renseignez le client ID et le secret Twitch (dev.twitch.tv/console)."
            return
        }
        guard !games.isEmpty else { return }

        isRunning = true
        cancellation = false
        lastError = nil
        progress = 0
        defer { isRunning = false }

        let active: IGDBToken
        do {
            active = try await ensureToken()
        } catch {
            lastError = (error as? IGDBError)?.errorDescription ?? error.localizedDescription
            return
        }

        let queue = games.filter { force || entries[$0.id.lowercased()] == nil }
        guard !queue.isEmpty else {
            status = "Tous les visuels sont déjà en cache."
            return
        }

        var done = 0
        var failures = 0

        for game in queue {
            if cancellation { break }
            status = "\(done + 1) / \(queue.count) · \(game.name)"
            defer {
                done += 1
                progress = Double(done) / Double(queue.count)
            }

            do {
                try Task.checkCancellation()
                let results = try await IGDB.search(game.name, token: active, clientID: clientID)
                try await Task.sleep(nanoseconds: 260_000_000) // IGDB allows 4 req/s
                guard let best = TitleMatcher.best(in: results, for: game.name), best.score >= 0.62 else {
                    failures += 1
                    continue
                }
                try await download(best.game, for: game)
            } catch is CancellationError {
                break
            } catch {
                failures += 1
                if !cancellation {
                    lastError = (error as? IGDBError)?.errorDescription ?? error.localizedDescription
                }
                if lastError?.contains("Jeton") == true { break }
            }
        }

        persist()
        tokenExpiry = token?.expires
        if cancellation {
            status = "Récupération interrompue · \(entries.count) visuels en cache"
        } else if failures > 0 {
            status = "\(entries.count) visuels en cache · \(failures) titre\(failures > 1 ? "s" : "") sans correspondance"
        } else {
            status = "\(entries.count) visuels en cache"
        }
        missingCount = games.filter { entries[$0.id.lowercased()] == nil }.count
    }

    func cancel() {
        cancellation = true
        status = "Interruption…"
    }

    func clearCache() {
        for entry in entries.values {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
            if let artwork = entry.artwork {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(artwork))
            }
        }
        entries = [:]
        persist()
        status = "Cache vidé"
    }

    // MARK: Internals

    private func ensureToken(force: Bool = false) async throws -> IGDBToken {
        if !force, let token, token.isFresh {
            tokenExpiry = token.expires
            return token
        }
        let id = clientID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else {
            throw IGDBError.message("Renseignez le client ID et le secret Twitch.")
        }
        let fresh = try await IGDB.requestToken(clientID: id, secret: secret)
        token = fresh
        tokenExpiry = fresh.expires
        return fresh
    }

    private func download(_ match: IGDBGame, for game: Game) async throws {
        guard let coverURL = match.coverURL else { return }
        guard let coverData = await fetchImage(coverURL) else { return }
        let coverName = "\(game.id).jpg"
        try coverData.write(to: directory.appendingPathComponent(coverName), options: .atomic)

        var artworkName: String?
        if let artworkURL = match.artworkURL, let data = await fetchImage(artworkURL) {
            let name = "\(game.id)-wide.jpg"
            if (try? data.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil {
                artworkName = name
            }
        }

        entries[game.id.lowercased()] = Entry(
            file: coverName,
            artwork: artworkName,
            igdbName: match.name,
            igdbID: match.id,
            updated: Date()
        )
        persist()
    }

    private func fetchImage(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("NXNStudio/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        return data
    }

    private func persist() {
        if let data = try? ArtworkStore.encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
