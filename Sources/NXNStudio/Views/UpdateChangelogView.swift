import SwiftUI
import AppKit

// MARK: - Changelog popover

/// Shown from the “info” button of the nxnative update row: what the last
/// `git pull` actually brought in.
struct UpdateChangelogView: View {
    let changelog: RepoChangelog
    var onClose: () -> Void
    var onClear: () -> Void
    /// Offscreen renderers do not lay out `ScrollView` content, so the debug
    /// snapshot uses a plain stack instead.
    var previewRows = false

    private let repoURL = URL(string: "https://github.com/seedds/nxnative")!

    private var isRecent: Bool { changelog.from.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            kinds
            Hairline()
            if !isRecent {
                range
                Hairline()
            }
            commitList
            Hairline()
            footer
        }
        .frame(width: 468)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            RadialGradient(
                colors: [Theme.ember.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 220
            )
            .frame(height: 180)
            .allowsHitTesting(false)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Theme.ember.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(isRecent ? "Derniers commits" : L.t("Mise à jour appliquée"))
                    .font(.label(7.5, weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ember.opacity(0.85))

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(changelog.total)")
                        .font(.numeral(19, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(isRecent
                         ? (changelog.total > 1 ? L.t("commits récents") : L.t("commit récent"))
                         : (changelog.total > 1 ? L.t("commits récupérés") : L.t("commit récupéré")))
                        .font(.label(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 7.5, weight: .semibold))
                    Text(verbatim: changelog.branch)
                        .font(.mono(8.5))
                    Text("·")
                    if isRecent {
                        Text(verbatim: "HEAD \(changelog.to)")
                            .font(.mono(8.5))
                    } else {
                        Text(Fmt.relative(changelog.appliedAt))
                            .font(.label(8.5))
                    }
                }
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 6)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.fill(0.04)))
            }
            .buttonStyle(.plain)
            .help("Fermer")
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    // MARK: Kinds

    private var kinds: some View {
        HStack(spacing: 6) {
            ForEach(summary, id: \.kind) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(tint(item.kind))
                        .frame(width: 4.5, height: 4.5)
                    Text(verbatim: "\(item.count)")
                        .font(.numeral(9, weight: .bold))
                        .foregroundStyle(tint(item.kind).opacity(0.9))
                    Text(label(item.kind))
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 7)
                .frame(height: 21)
                .background(Capsule().fill(tint(item.kind).opacity(0.07)))
                .overlay(Capsule().strokeBorder(tint(item.kind).opacity(0.14), lineWidth: 0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private struct KindCount {
        let kind: RepoChangelog.Commit.Kind
        let count: Int
    }

    private var summary: [KindCount] {
        let order: [RepoChangelog.Commit.Kind] = [.feature, .fix, .perf, .docs, .other]
        return order.compactMap { kind in
            let count = changelog.count(of: kind)
            return count > 0 ? KindCount(kind: kind, count: count) : nil
        }
    }

    // MARK: Range

    private var range: some View {
        HStack(spacing: 7) {
            Text(verbatim: changelog.from)
                .font(.mono(9))
                .foregroundStyle(Theme.textTertiary)
            Image(systemName: "arrow.right")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Theme.textTertiary.opacity(0.6))
            Text(verbatim: changelog.to)
                .font(.mono(9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("·")
                .foregroundStyle(Theme.textTertiary.opacity(0.5))
            Text(verbatim: "origin/\(changelog.branch)")
                .font(.label(8.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Commits

    private var commitList: some View {
        Group {
            if previewRows {
                rows.frame(height: 250, alignment: .top).clipped()
            } else {
                ScrollView {
                    rows
                }
                .scrollIndicators(.hidden)
                .frame(height: 250)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(changelog.commits.enumerated()), id: \.element.id) { index, commit in
                if index > 0 {
                    Hairline().padding(.leading, 30)
                }
                row(commit)
            }
        }
    }

    private func row(_ commit: RepoChangelog.Commit) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(tint(commit.kind))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.label(9.5, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(verbatim: commit.sha)
                        .font(.mono(8))
                        .foregroundStyle(Theme.textTertiary.opacity(0.75))
                    Text("·")
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    Text(commit.author)
                        .font(.label(8))
                        .foregroundStyle(Theme.textTertiary)
                    Text("·")
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    Text(commit.when)
                        .font(.label(8))
                        .foregroundStyle(Theme.textTertiary.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(isRecent
                 ? L.t("\(changelog.commits.count) commits les plus récents", "\(changelog.commits.count) most recent commits")
                 : (changelog.isTruncated
                    ? L.t("\(changelog.total - changelog.commits.count) commits plus anciens non listés", "\(changelog.total - changelog.commits.count) older commits not listed")
                    : L.t("\(changelog.commits.count) commit\(changelog.commits.count > 1 ? "s" : "")", "\(changelog.commits.count) commit\(changelog.commits.count > 1 ? "s" : "")")))
                .font(.label(8.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if !isRecent {
                Button(action: onClear) {
                    Text(L.t("Effacer"))
                        .font(.label(8.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L.t("Retirer l'historique de cette mise à jour"))
            }

            Link(destination: sourceURL) {
                HStack(spacing: 4) {
                    Text(isRecent ? "GitHub" : L.t("Comparer", "Compare"))
                        .font(.label(9, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(Capsule().fill(Theme.fill(0.055)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sourceURL: URL {
        if isRecent {
            return URL(string: "\(repoURL.absoluteString)/commits/\(changelog.branch)") ?? repoURL
        }
        return URL(string: "\(repoURL.absoluteString)/compare/\(changelog.from)...\(changelog.to)") ?? repoURL
    }

    // MARK: Style

    private func tint(_ kind: RepoChangelog.Commit.Kind) -> Color {
        switch kind {
        case .feature: return Theme.cyan
        case .fix: return Theme.mint
        case .perf: return Theme.violet
        case .docs: return Theme.emberSoft
        case .other: return Theme.textTertiary
        }
    }

    private func label(_ kind: RepoChangelog.Commit.Kind) -> String {
        switch kind {
        case .feature: return L.t("nouveautés")
        case .fix: return L.t("correctifs", "fixes")
        case .perf: return L.t("performances", "performance")
        case .docs: return L.t("docs", "docs")
        case .other: return L.t("autres", "other")
        }
    }
}

// MARK: - Preview data (design verification)

#if DEBUG
extension RepoChangelog {
    static var demo: RepoChangelog {
        let samples = [
            ("6c676444", "A pool texture the walk leaves out holds a stand-in of its own colours until its first read: Ocarina of Time's streamed scenery no longer draws dark for one frame", "seedds", "1 hr ago"),
            ("6d9edb07", "A texture ID a shader has read keeps its read mark when the game puts another texture into it, and loses it only when emptied", "seedds", "1 hr ago"),
            ("bbea4c90", "A GPU copy into a texture uploaded from its storage no longer uploads all of it again: Star Fox's 7-10 s frames at its prologue's scene changes", "lunks", "2 hr ago"),
            ("5e1c1aec", "Whether a vertex shader writes the layer is in its reflection: Ocarina of Time's 230 ms camera-turn hitch goes to 39 ms", "seedds", "2 hr ago"),
            ("12a44e09", "The uniform copy thread hands off without a mutex, and a shadow overlay writes into its own layer", "uncraftablexd", "2 hr ago"),
            ("804809c6", "Hades II registers its update 1.0.141667 (v655360, SDK 20.5.15)", "seedds", "2 hr ago"),
            ("b84ee29a", "Hades II renders at up to 3840x2160: its render scale goes from 0.5 to 3.0", "seedds", "3 hr ago"),
            ("d4cc0eee", "An sRGB texture in an image slot is loaded and stored raw, as on NVN: Star Fox's picture was encoded twice", "lunks", "3 hr ago"),
            ("a888e668", "Switch 2 pixel shaders honour their early fragment tests flag: PRAGMATA's GPU frame time 19.0 to 16.6 ms", "uncraftablexd", "3 hr ago"),
            ("6f50de00", "The pool walk's statistics no longer make a chunk of a large pool for every texture they ask about", "seedds", "3 hr ago"),
            ("dbf84998", "Ocarina of Time's prewarm list gets 41 more task and mesh pipelines from later play", "seedds", "4 hr ago"),
            ("b54968e7", "A snapshot of an attachment lands a clear still waiting for the draw's pass before it copies", "Xipzer", "4 hr ago"),
        ]
        let commits = samples.map { sample in
            Commit(
                sha: sample.0,
                subject: sample.1,
                author: sample.2,
                when: sample.3,
                kind: RepoChangelog.kind(for: sample.1)
            )
        }
        return RepoChangelog(
            from: "4f2c1ab",
            to: "6c67644",
            branch: "main",
            total: 163,
            appliedAt: Date().addingTimeInterval(-180),
            commits: commits
        )
    }

    static var demoRecent: RepoChangelog {
        let base = demo
        return RepoChangelog(
            from: "",
            to: base.to,
            branch: base.branch,
            total: base.commits.count,
            appliedAt: Date(),
            commits: base.commits
        )
    }
}

enum ChangelogSnapshot {
    @MainActor
    static func render(path: String, recent: Bool = false) {
        L.language = .en
        let changelog: RepoChangelog = recent ? .demoRecent : .demo
        let view = UpdateChangelogView(changelog: changelog, onClose: {}, onClear: {}, previewRows: true)
            .background(Theme.canvas)
            .padding(20)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("changelog render failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

/// Headless probe: builds a changelog from real history and prints it.
enum ChangelogProbe {
    @MainActor
    static func run(repo: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let url = URL(fileURLWithPath: repo)

        Task {
            let fromResult = await ShellRunner.run(["git", "-C", repo, "rev-parse", "HEAD~6"])
            let from = fromResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let changelog = await RepoUpdate.changelog(repo: url, from: from, branch: "main") else {
                print("SELFTEST-CHANGELOG nil")
                exit(2)
            }
            print("SELFTEST-CHANGELOG total=\(changelog.total) listed=\(changelog.commits.count) \(changelog.from)->\(changelog.to)")
            for commit in changelog.commits {
                print("  \(commit.sha) [\(commit.kind.rawValue)] \(commit.subject.prefix(64)) | \(commit.author) | \(commit.when)")
            }

            if let recent = await RepoUpdate.recentChangelog(repo: url) {
                print("SELFTEST-RECENT total=\(recent.total) listed=\(recent.commits.count) branch=\(recent.branch) from='\(recent.from)' to=\(recent.to)")
            } else {
                print("SELFTEST-RECENT nil")
            }
            exit(changelog.total == 6 ? 0 : 1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            print("SELFTEST-CHANGELOG TIMEOUT")
            exit(3)
        }
        app.run()
    }
}
#endif
