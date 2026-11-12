import Foundation

// MARK: - IGDB

/// Minimal IGDB client: Twitch client-credentials token, then a name search on
/// `/v4/games`. No third-party dependency.
struct IGDBToken {
    let access: String
    let expires: Date

    var isFresh: Bool { expires.timeIntervalSinceNow > 60 }
}

struct IGDBGame {
    let id: Int
    let name: String
    let coverURL: URL?
    let artworkURL: URL?
}

enum IGDBError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum IGDB {
    static let apiRoot = "https://api.igdb.com/v4"

    // MARK: Auth

    static func requestToken(clientID: String, secret: String) async throws -> IGDBToken {
        var components = URLComponents(string: "https://id.twitch.tv/oauth2/token")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: secret),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IGDBError.message("Twitch est injoignable. Vérifiez votre connexion.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw IGDBError.message("Réponse Twitch illisible.")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 403 {
                throw IGDBError.message("Identifiants Twitch refusés (code \(http.statusCode)). Vérifiez le client ID et le secret.")
            }
            throw IGDBError.message("Twitch a répondu \(http.statusCode).")
        }

        struct Payload: Decodable {
            let access_token: String
            let expires_in: Double
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw IGDBError.message("Jeton Twitch illisible.")
        }
        return IGDBToken(access: payload.access_token,
                         expires: Date().addingTimeInterval(payload.expires_in))
    }

    // MARK: Search

    static func search(_ name: String, token: IGDBToken, clientID: String, limit: Int = 6) async throws -> [IGDBGame] {
        let escaped = name
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: "\"", with: " ")
        let body = """
        search "\(escaped)";
        fields name,cover.url,artworks.url;
        limit \(limit);
        """

        guard let url = URL(string: "\(apiRoot)/games") else {
            throw IGDBError.message("URL IGDB invalide.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.httpBody = Data(body.utf8)
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("Bearer \(token.access)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("NXNStudio/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IGDBError.message("IGDB est injoignable. Vérifiez votre connexion.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw IGDBError.message("Réponse IGDB illisible.")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw IGDBError.message("Jeton IGDB expiré. Relancez la récupération.")
            }
            if http.statusCode == 429 {
                throw IGDBError.message("IGDB limite les requêtes (4 par seconde). Réessayez dans un instant.")
            }
            throw IGDBError.message("IGDB a répondu \(http.statusCode).")
        }

        struct RawImage: Decodable { let url: String }
        struct RawGame: Decodable {
            let id: Int
            let name: String
            let cover: RawImage?
            let artworks: [RawImage]?
        }

        guard let raw = try? JSONDecoder().decode([RawGame].self, from: data) else {
            throw IGDBError.message("La réponse IGDB n'a pas pu être lue.")
        }

        return raw.map { game in
            IGDBGame(
                id: game.id,
                name: game.name,
                coverURL: imageURL(game.cover?.url, size: "t_cover_big_2x"),
                artworkURL: imageURL(game.artworks?.first?.url, size: "t_720p")
            )
        }
    }

    private static func imageURL(_ raw: String?, size: String) -> URL? {
        guard var text = raw, !text.isEmpty else { return nil }
        if text.hasPrefix("//") { text = "https:" + text }
        // IGDB returns a thumbnail path; swap the size segment.
        if let range = text.range(of: "/t_[a-z0-9_]+/", options: .regularExpression) {
            text.replaceSubrange(range, with: "/\(size)/")
        }
        return URL(string: text)
    }
}

// MARK: - Name matching

enum TitleMatcher {
    static func normalize(_ text: String) -> String {
        var value = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        value = value.replacingOccurrences(of: "[™®©]", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[[^]]*\\]", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func score(candidate: String, target: String) -> Double {
        let a = normalize(candidate)
        let b = normalize(target)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.hasPrefix(b) || b.hasPrefix(a) {
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            return 0.74 + 0.2 * (Double(shorter) / Double(longer))
        }

        let setA = Set(a.split(separator: " "))
        let setB = Set(b.split(separator: " "))
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        let common = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(common) / Double(union)
    }

    static func best(in games: [IGDBGame], for title: String) -> (game: IGDBGame, score: Double)? {
        games
            .map { (game: $0, score: score(candidate: $0.name, target: title)) }
            .max { $0.score < $1.score }
    }
}
