import SwiftUI
import AppKit

struct LauncherView: View {
    @EnvironmentObject private var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 380, maximum: 620), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Launcher",
                subtitle: launcherSubtitle
            ) {
                HStack(spacing: 8) {
                    GhostButton(title: state.launcher.isScanning ? "Analyse…" : "Rescanner",
                                icon: "arrow.clockwise", compact: true) {
                        Task { await scan() }
                    }
                    .disabled(state.launcher.isScanning)

                    GhostButton(title: "Ouvrir un dossier", icon: "folder", compact: true) {
                        chooseFolder()
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.launcher.games.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(state.launcher.games) { game in
                                LauncherCard(game: game, artwork: artworkURL(for: game))
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .task { await scan() }
    }

    private var launcherSubtitle: String {
        let count = state.launcher.games.count
        if state.launcher.isScanning { return "Recherche des jeux construits sur ce Mac…" }
        if count == 0 { return "Aucun jeu construit détecté" }
        let when = state.launcher.lastScan.map { Fmt.relative($0) } ?? "à l'instant"
        return "\(count) jeu\(count > 1 ? "x" : "") construit\(count > 1 ? "s" : "") · analysé \(when)"
    }

    private func artworkURL(for game: InstalledGame) -> URL? {
        guard let id = game.titleID?.lowercased() else { return nil }
        return state.artworks.artworkURL(for: id) ?? state.artworks.coverURL(for: id)
    }

    private func scan() async {
        await state.launcher.scan(
            records: state.records,
            titleIDs: state.games.map(\.id)
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Ajouter un jeu construit"
        panel.message = "Choisissez une application .app produite par nxnative"
        panel.prompt = "Ajouter"
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        state.launcher.add(contentsOf: panel.urls)
    }

    private var emptyState: some View {
        Panel(padding: 0) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.ember.opacity(0.16), Theme.violet.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 78, height: 78)
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Theme.ember)
                }
                Text("Aucun jeu installé")
                    .font(.label(14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Construisez un jeu dans l'onglet Construire : l'app produite apparaîtra ici, avec les jeux déjà présents sur le Mac.")
                    .font(.label(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                GhostButton(title: "Chercher à nouveau", icon: "arrow.clockwise", compact: true) {
                    Task { await scan() }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Card

struct LauncherCard: View {
    @EnvironmentObject private var state: AppState
    let game: InstalledGame
    let artwork: URL?

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var titleID: String? { game.titleID }

    var body: some View {
        Button {
            state.launcher.open(game)
        } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop

                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.45), .black.opacity(0.82)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        icon
                        Spacer()
                        if hover {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Jouer")
                                    .font(.label(9, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(.white.opacity(0.92)))
                            .transition(.opacity)
                        }
                    }

                    Spacer()

                    Text(game.name)
                        .font(.display(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if !game.version.isEmpty {
                            Text("v\(game.version)")
                        }
                        Text("·")
                        Text(Fmt.relative(game.modified))
                        if game.titleID != nil {
                            Text("·")
                            Text(game.bundleID)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.label(8.5))
                    .foregroundStyle(.white.opacity(0.62))
                }
                .padding(14)
            }
            .frame(height: 190)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(hover ? 0.22 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(hover ? 0.45 : 0.25), radius: hover ? 22 : 12, y: hover ? 12 : 6)
            .scaleEffect(hover && !reduceMotion ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { hover = value }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hover)
        .contextMenu {
            Button("Lancer") { state.launcher.open(game) }
            Button("Afficher dans le Finder") { state.launcher.reveal(game) }
            Button("Copier le chemin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(game.path.path, forType: .string)
            }
        }
        .help(game.path.path)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let artwork, let image = NSImage(contentsOf: artwork) {
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            let colors = CoverTint.colors(for: game.titleID ?? game.bundleID)
            LinearGradient(colors: [colors.0.opacity(0.55), colors.1.opacity(0.18), Theme.panel],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(colors.0.opacity(0.18))
                        .frame(width: 220, height: 220)
                        .blur(radius: 40)
                        .offset(x: 50, y: -80)
                }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = game.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
    }
}
