import Foundation

// MARK: - Pull request

struct PullRequest: Codable, Identifiable, Hashable {
    struct User: Codable, Hashable {
        let login: String
    }

    struct Label: Codable, Hashable, Identifiable {
        let name: String
        let color: String
        var id: String { name }
    }

    let number: Int
    let title: String
    let state: String
    let draft: Bool?
    let createdAt: Date
    let updatedAt: Date
    let mergedAt: Date?
    var closedAt: Date? = nil
    let htmlURL: URL
    let user: User
    let labels: [Label]
    var body: String?

    /// Used before caching: the UI only shows the first ~240 characters, so a
    /// long PR description does not need to be stored whole.
    func trimmedBody(_ limit: Int) -> PullRequest {
        guard let body, body.count > limit else { return self }
        var copy = self
        copy.body = String(body.prefix(limit))
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case number, title, state, draft, user, labels, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case closedAt = "closed_at"
        case htmlURL = "html_url"
    }

    var id: Int { number }
    var isMerged: Bool { mergedAt != nil }
    var isOpen: Bool { state == "open" }

    var activityDate: Date {
        if let mergedAt { return mergedAt }
        if let closedAt { return closedAt }
        return createdAt
    }

    var stateLabel: String {
        if isMerged { return "fusionnée" }
        if isOpen { return draft == true ? "brouillon" : "ouverte" }
        return "fermée"
    }

    var excerpt: String {
        guard var text = body else { return "" }
        text = text.replacingOccurrences(of: "\r", with: "\n")
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("##")
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("<!--")
                    && !line.hasPrefix("```")
            }
        text = lines.joined(separator: " ")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        if let range = text.range(of: "## ") {
            text = String(text[..<range.lowerBound])
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(240))
    }
}

// MARK: - GitHub activity

@MainActor
final class RepoNews: ObservableObject {
    @Published private(set) var open: [PullRequest] = []
    @Published private(set) var closed: [PullRequest] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSynced: Date?
    @Published private(set) var unseenCount = 0
    @Published private(set) var rateRemaining: Int?
    @Published private(set) var rateLimit: Int?
    @Published private(set) var rateReset: Date?

    private struct Cache: Codable {
        var open: [PullRequest]
        var closed: [PullRequest]
        var synced: Date
        var rate: RateInfo? = nil
    }

    private let defaults = UserDefaults.standard
    private var lastSeen: Date
    private var lastAttempt: Date?

    init() {
        lastSeen = defaults.object(forKey: "newsLastSeen") as? Date ?? .distantPast
        if let data = defaults.data(forKey: "newsCache"),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            open = cache.open
            closed = cache.closed
            lastSynced = cache.synced
            rateRemaining = cache.rate?.remaining
            rateLimit = cache.rate?.limit
            rateReset = cache.rate?.reset
        }
        recomputeUnseen()
    }

    var isEmpty: Bool { open.isEmpty && closed.isEmpty }
    var items: [PullRequest] { open + closed }
    var hasSeenBefore: Bool { lastSeen > .distantPast }

    var contributors: Int {
        Set(items.map(\.user.login)).count
    }

    var mergedRecently: Int {
        let threshold = Date().addingTimeInterval(-14 * 24 * 3600)
        return closed.filter { $0.updatedAt > threshold }.count
    }

    var isStale: Bool {
        guard let lastSynced else { return true }
        return Date().timeIntervalSince(lastSynced) > 20 * 60
    }

    // MARK: Sync

    func refreshIfStale() async {
        guard isStale || isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }

        do {
            // One request for both states: `state=all` returns open and closed
            // pull requests in a single response, which halves the API quota
            // usage compared to two calls.
            let outcome = try await Self.fetchAll(limit: 100)
            rateRemaining = outcome.rate?.remaining
            rateLimit = outcome.rate?.limit
            rateReset = outcome.rate?.reset

            let items = outcome.items
            open = items.filter(\.isOpen).sorted { $0.updatedAt > $1.updatedAt }
            closed = items.filter { !$0.isOpen }.sorted {
                ($0.mergedAt ?? $0.closedAt ?? $0.updatedAt) > ($1.mergedAt ?? $1.closedAt ?? $1.updatedAt)
            }
            lastSynced = Date()
            lastError = nil
            persist()
            recomputeUnseen()
        } catch let error as RateLimitError {
            rateRemaining = error.rate?.remaining
            rateLimit = error.rate?.limit
            rateReset = error.rate?.reset
            lastError = error.message
        } catch {
            lastError = (error as? NewsError)?.message ?? "Impossible de joindre GitHub."
        }
    }

    func markSeen() {
        lastSeen = Date()
        defaults.set(lastSeen, forKey: "newsLastSeen")
        unseenCount = 0
    }

    var lastSeenDate: Date { lastSeen }

    // MARK: Persistence

    private func persist() {
        let rate = rateRemaining.map {
            RateInfo(remaining: $0, limit: rateLimit ?? 60, reset: rateReset)
        }
        let cache = Cache(
            open: open.map { $0.trimmedBody(1200) },
            closed: closed.map { $0.trimmedBody(1200) },
            synced: lastSynced ?? Date(),
            rate: rate
        )
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: "newsCache")
        }
    }

    private func recomputeUnseen() {
        guard hasSeenBefore else {
            unseenCount = 0
            return
        }
        unseenCount = items.filter { $0.activityDate > lastSeen }.count
    }

    // MARK: GitHub API

    struct RateInfo: Codable {
        var remaining: Int
        var limit: Int
        var reset: Date?
    }

    private struct FetchOutcome {
        var items: [PullRequest]
        var rate: RateInfo?
    }

    private enum NewsError: Error {
        case message(String)
        var message: String {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private struct RateLimitError: Error {
        let message: String
        let rate: RateInfo?
    }

    private static func fetchAll(limit: Int) async throws -> FetchOutcome {
        var components = URLComponents(string: "https://api.github.com/repos/seedds/nxnative/pulls")!
        components.queryItems = [
            URLQueryItem(name: "state", value: "all"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(limit)"),
        ]
        guard let url = components.url else { throw NewsError.message("URL GitHub invalide.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NXNStudio/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NewsError.message("Pas de connexion à GitHub. Les dernières nouveautés connues restent affichées.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw NewsError.message("Réponse GitHub illisible.")
        }
        let rate = rateInfo(from: http)
        guard http.statusCode == 200 else {
            if http.statusCode == 403 || http.statusCode == 429 {
                throw RateLimitError(
                    message: "Limite de requêtes GitHub atteinte. Réessayez dans quelques minutes.",
                    rate: rate
                )
            }
            throw NewsError.message("GitHub a répondu \(http.statusCode).")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = withFraction.date(from: text) ?? plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Date GitHub invalide : \(text)")
        }

        do {
            let items = try decoder.decode([PullRequest].self, from: data)
            return FetchOutcome(items: items, rate: rate)
        } catch {
            throw NewsError.message("Le flux GitHub n'a pas pu être lu.")
        }
    }

    private static func rateInfo(from http: HTTPURLResponse) -> RateInfo? {
        guard let text = http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
              let remaining = Int(text) else { return nil }
        let limit = http.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init) ?? 60
        let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) }
        return RateInfo(remaining: remaining, limit: limit, reset: reset)
    }

    #if DEBUG
    func loadDemo() {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        func date(daysAgo: Double) -> Date { now.addingTimeInterval(-daysAgo * 86_400) }
        _ = calendar

        let samples: [PullRequest] = [
            PullRequest(
                number: 2102, title: "Frame-rate counter on the Mac: DM_SHOW_FPS draws the iPhone's counter at the game window's top left",
                state: "open", draft: false,
                createdAt: date(daysAgo: 0.2), updatedAt: date(daysAgo: 0.1), mergedAt: nil,
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/2102")!,
                user: .init(login: "JakePre"),
                labels: [.init(name: "mac", color: "5FE3B4"), .init(name: "hud", color: "64C8FF")],
                body: "## What and why\n\nMost Mac builds run the game at a stable frame rate but there was no way to see it. DM_SHOW_FPS now draws the same counter the iPhone build uses, anchored to the top left of the game window."
            ),
            PullRequest(
                number: 2089, title: "switch_trace: a console-side NVN tracing module for timing, call order and reference tracking",
                state: "open", draft: false,
                createdAt: date(daysAgo: 0.4), updatedAt: date(daysAgo: 0.1), mergedAt: nil,
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/2089")!,
                user: .init(login: "dpadr"),
                labels: [.init(name: "diagnostics", color: "FFC24B")],
                body: "A tracing module that records NVN calls with timestamps, call order and object references. Useful to compare a working game against a regression."
            ),
            PullRequest(
                number: 2101, title: "Controllers: a radial deadzone for each stick",
                state: "open", draft: false,
                createdAt: date(daysAgo: 0.5), updatedAt: date(daysAgo: 0.2), mergedAt: nil,
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/2101")!,
                user: .init(login: "v0lumehi"),
                labels: [.init(name: "input", color: "A78BFA")],
                body: "Deadzones are now radial instead of per-axis, which removes the square corners and matches the console behaviour for diagonal movement."
            ),
            PullRequest(
                number: 918, title: "Add adaptive 60 fps support for Pokémon Legends: Z-A 2.0.2",
                state: "open", draft: false,
                createdAt: date(daysAgo: 3), updatedAt: date(daysAgo: 0.3), mergedAt: nil,
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/918")!,
                user: .init(login: "thehobbit85"),
                labels: [.init(name: "performance", color: "FF8E63")],
                body: "Uses the new dynamic resolution path to keep 60 fps when the scene budget allows it, and falls back to 30 fps otherwise."
            ),
            PullRequest(
                number: 1310, title: "A GPU copy into a texture taken from its storage no longer uploads all of it again",
                state: "closed", draft: false,
                createdAt: date(daysAgo: 6), updatedAt: date(daysAgo: 0.05), mergedAt: date(daysAgo: 0.05),
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/1310")!,
                user: .init(login: "lunks"),
                labels: [.init(name: "gpu", color: "5B8CFF")],
                body: "Star Fox's picture was uploaded twice per frame. The copy now reuses the source storage when the region is unchanged."
            ),
            PullRequest(
                number: 2065, title: "A vertex library with layer entry points of its own gets bases for its main0 pairs",
                state: "closed", draft: false,
                createdAt: date(daysAgo: 4), updatedAt: date(daysAgo: 0.1), mergedAt: date(daysAgo: 0.1),
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/2065")!,
                user: .init(login: "Raymon82777"),
                labels: [.init(name: "shaders", color: "2FD6A8")],
                body: "Ocarina of Time's layered vertex programs now resolve their base pairs correctly when the library declares its own entry points."
            ),
            PullRequest(
                number: 2078, title: "The uniform copy thread hands off without a mutex, and a shadow overlay writes into its own layer",
                state: "closed", draft: false,
                createdAt: date(daysAgo: 5), updatedAt: date(daysAgo: 0.2), mergedAt: date(daysAgo: 0.2),
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/2078")!,
                user: .init(login: "uncraftablexd"),
                labels: [.init(name: "concurrency", color: "FF6B6B")],
                body: "Removes a lock from the uniform copy fast path and keeps shadow overlays isolated, fixing a flicker in late-game scenes."
            ),
            PullRequest(
                number: 1899, title: "iOS build: IOBluetooth stays out of the link",
                state: "closed", draft: false,
                createdAt: date(daysAgo: 7), updatedAt: date(daysAgo: 0.4), mergedAt: date(daysAgo: 0.4),
                htmlURL: URL(string: "https://github.com/seedds/nxnative/pull/1899")!,
                user: .init(login: "Xipzer"),
                labels: [.init(name: "ios", color: "64C8FF")],
                body: "The iOS target no longer links IOBluetooth, which was preventing sideloaded builds from launching on device."
            ),
        ]

        open = samples.filter(\.isOpen).sorted { $0.updatedAt > $1.updatedAt }
        closed = samples.filter { !$0.isOpen }.sorted {
            ($0.mergedAt ?? $0.closedAt ?? $0.updatedAt) > ($1.mergedAt ?? $1.closedAt ?? $1.updatedAt)
        }
        lastSynced = now
        lastError = nil
        rateRemaining = 59
        rateLimit = 60
        rateReset = now.addingTimeInterval(12 * 60)
        recomputeUnseen()
    }
    #endif
}
