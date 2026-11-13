import Foundation

// MARK: - Changelog

struct RepoChangelog: Codable, Equatable {
    struct Commit: Codable, Identifiable, Equatable {
        enum Kind: String, Codable {
            case feature, fix, perf, docs, other
        }

        var id: String { sha }
        let sha: String
        let subject: String
        let author: String
        let when: String
        let kind: Kind
    }

    let from: String
    let to: String
    let branch: String
    let total: Int
    let appliedAt: Date
    let commits: [Commit]

    var isTruncated: Bool { commits.count < total }

    func count(of kind: Commit.Kind) -> Int {
        commits.filter { $0.kind == kind }.count
    }

    /// Lightweight classification from the commit subject: conventional
    /// prefixes when present, keywords otherwise.
    static func kind(for subject: String) -> Commit.Kind {
        let text = subject.lowercased()
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 12 {
            let prefix = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            switch prefix {
            case "feat", "feature", "add": return .feature
            case "fix", "bugfix", "hotfix": return .fix
            case "perf", "opt": return .perf
            case "docs", "doc": return .docs
            default: break
            }
        }
        if text.contains("crash") || text.contains("fix") || text.contains("no longer")
            || text.contains("correct") || text.contains("regression") || text.contains("bug") {
            return .fix
        }
        if text.contains("faster") || text.contains("speed") || text.contains("performance")
            || text.contains("optimi") || text.contains("latency") || text.contains("hitch")
            || text.contains(" ms") || text.contains("fps") {
            return .perf
        }
        if text.contains("adds ") || text.contains("add ") || text.contains("support")
            || text.contains("implement") || text.contains("new ") || text.contains("introduce")
            || text.contains("registers") || text.contains("renders at") {
            return .feature
        }
        return .other
    }
}

// MARK: - Repository update

@MainActor
final class RepoUpdate: ObservableObject {
    struct Snapshot: Equatable {
        var branch: String
        var ahead: Int
        var behind: Int
        var lastCommit: String
        var dirty: Bool

        var branchName: String {
            branch.contains("/") ? String(branch.split(separator: "/").last ?? "") : branch
        }
    }

    enum State: Equatable {
        case idle
        case checking
        case ready(Snapshot)
        case behind(Snapshot)
        case notGit(String)
        case failed(String)
        case updating
        case updated(Snapshot)

        var snapshot: Snapshot? {
            switch self {
            case .ready(let s), .behind(let s), .updated(let s): return s
            default: return nil
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @Published private(set) var log: [String] = []
    @Published private(set) var lastUpdate: RepoChangelog?
    @Published private(set) var recent: RepoChangelog?

    init() {
        if let data = UserDefaults.standard.data(forKey: "lastUpdateChangelog"),
           let changelog = try? JSONDecoder().decode(RepoChangelog.self, from: data) {
            lastUpdate = changelog
        }
    }

    private var didAutoCheck = false

    var isBusy: Bool {
        switch state {
        case .checking, .updating: return true
        default: return false
        }
    }

    var behindCount: Int {
        if case .behind(let snapshot) = state { return snapshot.behind }
        return 0
    }

    var isUpToDate: Bool {
        switch state {
        case .ready, .updated: return true
        default: return false
        }
    }

    var statusLabel: String {
        switch state {
        case .idle: return L.t("Non vérifié", "Not checked")
        case .checking: return L.t("Vérification…", "Checking…")
        case .ready(let s): return s.ahead > 0 ? L.t("À jour · \(s.ahead) local", "Up to date · \(s.ahead) local") : L.t("À jour", "Up to date")
        case .behind(let s): return L.t("\(s.behind) commit\(s.behind > 1 ? "s" : "") de retard", "\(s.behind) commit\(s.behind > 1 ? "s" : "") behind")
        case .notGit: return L.t("Pas un dépôt git", "Not a git repository")
        case .failed: return L.t("Vérification impossible", "Check failed")
        case .updating: return L.t("Mise à jour…", "Updating…")
        case .updated: return L.t("À jour", "Up to date")
        }
    }

    var detail: String {
        switch state {
        case .idle:
            return L.t("Vérifiez si le checkout local est à jour", "Check whether the local checkout is up to date")
        case .checking:
            return L.t("Interrogation de la branche amont…", "Querying the upstream branch…")
        case .ready(let s), .updated(let s), .behind(let s):
            var text = "\(s.branchName) · \(s.lastCommit)"
            if s.dirty { text += L.t(" · modifications locales", " · local changes") }
            return text
        case .notGit(let message), .failed(let message):
            return message
        case .updating:
            return L.t("git pull --ff-only en cours…", "git pull --ff-only in progress…")
        }
    }

    // MARK: Check

    func checkOnce(repo: URL?, force: Bool = false) async {
        guard !didAutoCheck || force else { return }
        didAutoCheck = true
        await check(repo: repo)
    }

    func check(repo: URL?) async {
        guard let repo, !isBusy else { return }
        state = .checking
        log = []

        let inside = await ShellRunner.run(["git", "-C", repo.path, "rev-parse", "--is-inside-work-tree"])
        guard inside.succeeded, inside.output.contains("true") else {
            state = .notGit("Le dossier choisi n'est pas un dépôt git.")
            lastCheck = Date()
            return
        }

        let fetch = await ShellRunner.run(["git", "-C", repo.path, "fetch", "--quiet", "--prune"])
        guard fetch.succeeded else {
            state = .failed(Self.shortError(fetch) ?? "git fetch a échoué (réseau indisponible ?)")
            lastCheck = Date()
            return
        }

        let upstream = await ShellRunner.run(
            ["git", "-C", repo.path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
        let upstreamName = upstream.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstream.succeeded, !upstreamName.isEmpty else {
            state = .notGit("Aucune branche amont configurée pour ce checkout.")
            lastCheck = Date()
            return
        }

        let counts = await ShellRunner.run(
            ["git", "-C", repo.path, "rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        let numbers = counts.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .compactMap { Int($0) }
        let ahead = numbers.count > 0 ? numbers[0] : 0
        let behind = numbers.count > 1 ? numbers[1] : 0

        let logResult = await ShellRunner.run(
            ["git", "-C", repo.path, "log", "-1", "--format=%h%x1f%s%x1f%cr"])
        let logParts = logResult.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\u{1f}")
        let hash = logParts.count > 0 ? logParts[0] : ""
        let subject = logParts.count > 1 ? logParts[1] : ""
        let when = logParts.count > 2 ? logParts[2] : ""
        let lastCommit = [hash, subject, when]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        let status = await ShellRunner.run(["git", "-C", repo.path, "status", "--porcelain"])
        let dirty = !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let snapshot = Snapshot(
            branch: upstreamName,
            ahead: ahead,
            behind: behind,
            lastCommit: lastCommit.isEmpty ? "commit inconnu" : lastCommit,
            dirty: dirty
        )
        state = behind > 0 ? .behind(snapshot) : .ready(snapshot)
        lastCheck = Date()
    }

    // MARK: Update

    @discardableResult
    func update(repo: URL?) async -> Bool {
        guard let repo, case .behind = state, !isBusy else { return false }
        let branch = state.snapshot?.branchName ?? "main"
        let before = await ShellRunner.run(["git", "-C", repo.path, "rev-parse", "HEAD"])
        let beforeSHA = before.output.trimmingCharacters(in: .whitespacesAndNewlines)

        state = .updating
        log = ["$ git pull --ff-only"]

        let result = await ShellRunner.run(
            ["git", "-C", repo.path, "pull", "--ff-only"],
            onLine: { [weak self] line in
                Task { @MainActor in self?.append(line) }
            }
        )

        guard result.succeeded else {
            append("✕ " + (Self.shortError(result) ?? "La mise à jour a échoué"))
            state = .failed(Self.shortError(result) ?? "git pull a échoué")
            lastCheck = Date()
            return false
        }

        append("✓ Dépôt mis à jour")
        lastUpdate = await Self.changelog(repo: repo, from: beforeSHA, branch: branch)
        persistChangelog()
        state = .idle
        await check(repo: repo)
        return true
    }

    // MARK: Changelog

    static func changelog(repo: URL, from: String, branch: String) async -> RepoChangelog? {
        guard !from.isEmpty else { return nil }

        let head = await ShellRunner.run(["git", "-C", repo.path, "rev-parse", "HEAD"])
        let to = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty else { return nil }

        let countResult = await ShellRunner.run(
            ["git", "-C", repo.path, "rev-list", "--count", "\(from)..\(to)"])
        let total = Int(countResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        let logResult = await ShellRunner.run([
            "git", "-C", repo.path, "log", "--no-merges",
            "--max-count=80", "--format=%h%x1f%s%x1f%an%x1f%cr", "\(from)..\(to)"
        ])
        let commits = parse(logResult.output)

        guard total > 0, !commits.isEmpty else { return nil }
        return RepoChangelog(
            from: String(from.prefix(7)),
            to: String(to.prefix(7)),
            branch: branch,
            total: total,
            appliedAt: Date(),
            commits: commits
        )
    }

    /// Latest commits of the checkout, shown when no update was recorded by
    /// this app (for example after a `git pull` in Terminal).
    static func recentChangelog(repo: URL, limit: Int = 20) async -> RepoChangelog? {
        let branchResult = await ShellRunner.run(["git", "-C", repo.path, "rev-parse", "--abbrev-ref", "HEAD"])
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }

        let headResult = await ShellRunner.run(["git", "-C", repo.path, "rev-parse", "HEAD"])
        let head = headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return nil }

        let logResult = await ShellRunner.run([
            "git", "-C", repo.path, "log", "--no-merges",
            "--max-count=\(limit)", "--format=%h%x1f%s%x1f%an%x1f%cr", "HEAD"
        ])
        let commits = parse(logResult.output)
        guard !commits.isEmpty else { return nil }

        return RepoChangelog(
            from: "",
            to: String(head.prefix(7)),
            branch: branch,
            total: commits.count,
            appliedAt: Date(),
            commits: commits
        )
    }

    func loadRecentCommits(repo: URL?) async {
        guard let repo else { return }
        recent = await Self.recentChangelog(repo: repo)
    }

    private static func parse(_ output: String) -> [RepoChangelog.Commit] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RepoChangelog.Commit? in
                let parts = line.components(separatedBy: "\u{1f}")
                guard parts.count >= 4 else { return nil }
                let subject = parts[1].trimmingCharacters(in: .whitespaces)
                return RepoChangelog.Commit(
                    sha: parts[0],
                    subject: subject,
                    author: parts[2],
                    when: parts[3],
                    kind: RepoChangelog.kind(for: subject)
                )
            }
    }

    private func persistChangelog() {
        guard let lastUpdate else { return }
        if let data = try? JSONEncoder().encode(lastUpdate) {
            UserDefaults.standard.set(data, forKey: "lastUpdateChangelog")
        }
    }

    func dismissChangelog() {
        lastUpdate = nil
        UserDefaults.standard.removeObject(forKey: "lastUpdateChangelog")
    }

    func reset() {
        state = .idle
        lastCheck = nil
        log = []
        didAutoCheck = false
    }

    // MARK: Helpers

    private func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.append(trimmed)
        if log.count > 40 { log.removeFirst(log.count - 40) }
    }

    private static func shortError(_ result: ShellResult) -> String? {
        let text = result.combined
        guard !text.isEmpty else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if let error = lines.last(where: { $0.hasPrefix("error:") || $0.hasPrefix("fatal:") }) {
            return error
        }
        return lines.last(where: { !$0.isEmpty })
    }

    #if DEBUG
    func loadChangelogDemo() {
        lastUpdate = .demo
    }

    func loadDemo(behind: Int = 0) {
        didAutoCheck = true
        let snapshot = Snapshot(
            branch: "origin/main",
            ahead: 0,
            behind: behind,
            lastCommit: "4f2c1ab · fix: keep the Metal HUD in Mac builds · il y a 2 heures",
            dirty: false
        )
        state = behind > 0 ? .behind(snapshot) : .ready(snapshot)
        lastCheck = Date()
    }
    #endif
}
