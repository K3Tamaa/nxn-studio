import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var state: AppState

    enum Filter: String, CaseIterable, Identifiable {
        case all, switch1, switch2, installed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tous"
            case .switch1: return "Switch"
            case .switch2: return "Switch 2"
            case .installed: return "Installés"
            }
        }
    }

    @State private var query = ""
    @State private var filter: Filter = .all

    private var filtered: [Game] {
        state.games.filter { game in
            let matchesQuery = query.isEmpty
                || game.name.localizedCaseInsensitiveContains(query)
                || game.id.localizedCaseInsensitiveContains(query)
            guard matchesQuery else { return false }
            switch filter {
            case .all: return true
            case .switch1: return !game.isSwitch2
            case .switch2: return game.isSwitch2
            case .installed: return state.latestAppRecord(for: game) != nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.repo.isValid {
                content
            } else {
                OnboardingView()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Bibliothèque",
                subtitle: state.repo.isValid
                    ? "\(state.games.count) profils de jeux · \(state.repo.url?.lastPathComponent ?? "nxnative")"
                    : "Reliez votre checkout nxnative pour commencer"
            ) {
                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Nom ou title ID")
                    Button {
                        state.route = .build
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("Nouvelle build").font(.label(11.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let record = state.records.first {
                        RecentBuildBanner(record: record)
                    }

                    HStack(spacing: 6) {
                        ForEach(Filter.allCases) { item in
                            FilterChip(title: item.title,
                                       count: count(for: item),
                                       selected: filter == item) {
                                withAnimation(.easeOut(duration: 0.16)) { filter = item }
                            }
                        }
                        Spacer()
                        Text("\(filtered.count) jeu\(filtered.count == 1 ? "" : "x")")
                            .font(.label(10))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    if filtered.isEmpty {
                        EmptyLibraryState(query: query, filter: filter)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 232, maximum: 320), spacing: 16)],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(filtered) { game in
                                GameCard(game: game)
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func count(for filter: Filter) -> Int {
        switch filter {
        case .all: return state.games.count
        case .switch1: return state.games.filter { !$0.isSwitch2 }.count
        case .switch2: return state.games.filter(\.isSwitch2).count
        case .installed: return state.games.filter { state.latestAppRecord(for: $0) != nil }.count
        }
    }
}

// MARK: - Filters

struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.label(10.5, weight: selected ? .semibold : .medium))
                Text("\(count)")
                    .font(.numeral(8.5, weight: .bold))
                    .foregroundStyle(selected ? Theme.text.opacity(0.5) : Theme.textTertiary)
            }
            .foregroundStyle(selected ? Theme.text : (hover ? Theme.textSecondary : Theme.textTertiary))
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(
                Capsule().fill(selected ? Theme.fill(0.085) : (hover ? Theme.fill(0.04) : Theme.fill(0.02)))
            )
            .overlay(
                Capsule().strokeBorder(selected ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Game card

struct GameCard: View {
    @EnvironmentObject private var state: AppState
    let game: Game
    @State private var hover = false

    private var installed: BuildRecord? { state.latestAppRecord(for: game) }

    var body: some View {
        Button {
            state.configure(game)
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    GameCover(
                        game: game,
                        iconURL: state.iconURL(for: game),
                        posterURL: state.posterURL(for: game),
                        wideURL: state.wideArtworkURL(for: game),
                        height: 104,
                        badge: game.isSwitch2 ? "SWITCH 2" : nil
                    )

                    if installed != nil {
                        Button {
                            if let record = installed { state.play(record) }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Theme.mint))
                                .shadow(color: Theme.mint.opacity(0.4), radius: 8)
                        }
                        .buttonStyle(.plain)
                        .help("Lancer la dernière app Mac")
                        .padding(10)
                        .transition(.opacity)
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13))

                VStack(alignment: .leading, spacing: 9) {
                    Text(game.name)
                        .font(.label(12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                    HStack(spacing: 6) {
                        Chip(
                            text: game.platformLabel,
                            icon: game.isSwitch2 ? "bolt.fill" : "gamecontroller.fill",
                            color: game.isSwitch2 ? Theme.violet : Theme.textSecondary
                        )
                        if installed != nil {
                            Chip(text: "Mac", icon: "checkmark", color: Theme.mint)
                        }
                        Spacer(minLength: 0)
                        Text(game.shortID)
                            .font(.mono(8.5))
                            .foregroundStyle(Theme.textTertiary.opacity(0.75))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(hover ? Theme.ember : Theme.textTertiary)
                            .opacity(hover ? 1 : 0.45)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 11)
            }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(hover ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hover ? 0.38 : 0.2), radius: hover ? 16 : 8, y: hover ? 8 : 4)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.18), value: hover)
        .contextMenu {
            Button("Configurer la build") { state.configure(game) }
            if let record = installed {
                Button("Lancer \(game.name)") { state.play(record) }
                Button("Afficher dans le Finder") { if let path = record.outputPath { state.reveal(path) } }
            }
            Divider()
            Button("Ouvrir la note du jeu") {
                NSWorkspace.shared.open(game.profileURL.appendingPathComponent("README.md"))
            }
            Button("Afficher le profil") {
                NSWorkspace.shared.activateFileViewerSelecting([game.profileURL])
            }
        }
    }
}

// MARK: - Recent build banner

struct RecentBuildBanner: View {
    @EnvironmentObject private var state: AppState
    let record: BuildRecord

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((record.succeeded ? Theme.mint : Theme.danger).opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: record.succeeded ? "checkmark" : "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(record.succeeded ? Theme.mint : Theme.danger)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.label(11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Dernière build · \(Fmt.relative(record.date)) · \(Fmt.duration(record.seconds)) · \(record.succeeded ? "réussie" : "échouée")")
                    .font(.label(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if record.outputExists {
                GhostButton(title: "Afficher", icon: "folder", compact: true) {
                    if let path = record.outputPath { state.reveal(path) }
                }
                if record.isApp {
                    GhostButton(title: "Lancer", icon: "play.fill", tint: Theme.mint, compact: true) {
                        state.play(record)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.fill(0.022))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Empty search

struct EmptyLibraryState: View {
    let query: String
    let filter: LibraryView.Filter

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Aucun jeu ne correspond")
                .font(.label(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(query.isEmpty
                 ? "Aucun profil dans cette catégorie."
                 : "Rien pour « \(query) » avec ce filtre.")
                .font(.label(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}
