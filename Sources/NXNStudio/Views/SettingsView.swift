import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var checker = ToolchainChecker()
    @StateObject private var installer = DependencyInstaller()
    @State private var confirmInstallAll = false
    @State private var showChangelog = false
    @State private var igdbClientID = ""
    @State private var igdbSecret = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("Réglages"), subtitle: L.t("Environnement, mises à jour et diagnostic")) {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    appearancePanel
                    environmentPanel
                    artworkPanel
                    diagnosticPanel
                    historyPanel
                    aboutPanel
                }
                .frame(maxWidth: state.navigationStyle == .dock ? .infinity : 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            checker.run(repo: state.repo)
            if igdbClientID.isEmpty { igdbClientID = state.artworks.clientID }
            if state.repo.isValid {
                await state.repoUpdate.checkOnce(repo: state.repo.url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !installer.isRunning else { return }
            checker.run(repo: state.repo)
        }
        .sheet(isPresented: Binding(
            get: { state.setup.showSheet },
            set: { state.setup.showSheet = $0 }
        )) {
            SetupSheetView(setup: state.setup)
        }
        .confirmationDialog(
            L.t("Installer les dépendances manquantes ?"),
            isPresented: $confirmInstallAll,
            titleVisibility: .visible
        ) {
            Button(L.t("Installer \(bulkSteps.count) dépendance\(bulkSteps.count > 1 ? "s" : "")", "Install \(bulkSteps.count) dependenc\(bulkSteps.count > 1 ? "ies" : "y")")) {
                installAll()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(bulkSteps.map(\.title).joined(separator: ", "))
        }
    }

    // MARK: Environment

    private var environmentPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                panelHeader(title: L.t("Environnement"),
                            subtitle: state.repo.isValid ? L.t("nxnative est connecté") : "Aucun checkout valide")

                SettingRow(icon: "shippingbox",
                           tint: state.repo.isValid ? Theme.mint : Theme.warning,
                           title: "Checkout nxnative",
                           detail: state.repoPath.isEmpty ? L.t("Aucun dossier sélectionné") : state.repoPath,
                           status: state.repo.isValid ? "✓ \(state.repo.gamesCount) profils" : state.repo.message) {
                    HStack(spacing: 6) {
                        if !state.repo.isValid {
                            GhostButton(title: L.t("Cloner nxnative"), icon: "arrow.down.circle",
                                        tint: Theme.ember, compact: true) {
                                cloneRepo()
                            }
                        }
                        GhostButton(title: L.t("Re-scan"), icon: "arrow.clockwise", compact: true) {
                            state.refreshRepo()
                        }
                        GhostButton(title: L.t("Choisir…"), icon: "folder", compact: true) {
                            state.chooseRepo()
                        }
                    }
                }

                Hairline().padding(.leading, 56)

                updateRow

                Hairline().padding(.leading, 56)

                SettingRow(icon: "key",
                           tint: !state.keysPath.isEmpty ? Theme.mint : Theme.textTertiary,
                           title: "prod.keys",
                           detail: state.keysPath.isEmpty ? L.t("Non configuré") : state.keysPath,
                           status: state.keysPath.isEmpty ? L.t("requis pour les NSP") : L.t("clés prêtes")) {
                    GhostButton(title: L.t("Choisir…"), icon: "key", compact: true) {
                        state.chooseKeys()
                    }
                }

                Hairline().padding(.leading, 56)

                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L.t("Cible par défaut"))
                                .font(.label(11, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Text(L.t("Utilisée quand vous ouvrez un jeu"))
                                .font(.label(8.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(BuildPlatform.allCases) { platform in
                            Button {
                                state.defaultPlatform = platform
                            } label: {
                                Text(platform.title)
                                    .font(.label(9.5, weight: .medium))
                                    .foregroundStyle(state.defaultPlatform == platform ? Theme.text : Theme.textTertiary)
                                    .padding(.horizontal, 9)
                                    .frame(height: 24)
                                    .background(
                                        Capsule().fill(state.defaultPlatform == platform ? Theme.fill(0.09) : .clear)
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(state.defaultPlatform == platform ? Theme.hairlineStrong : .clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
    }

    // MARK: Appearance

    private var appearancePanel: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.ember.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("Apparence"))
                            .font(.label(12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(L.t("Thème et couleur d'accent, appliqués immédiatement"))
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Hairline()

                HStack(spacing: 8) {
                    ForEach(ThemeMode.allCases) { mode in
                        modeTile(mode)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                HStack(spacing: 8) {
                    Text(L.t("Accent"))
                        .font(.label(8.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(ThemeAccent.allCases) { accent in
                        Button {
                            state.themeAccent = accent
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 18, height: 18)
                                if state.themeAccent == accent {
                                    Circle()
                                        .strokeBorder(Theme.text.opacity(0.85), lineWidth: 1.5)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(accent.title)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                HStack(spacing: 8) {
                    Text(L.t("Navigation"))
                        .font(.label(8.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(NavigationStyle.allCases) { style in
                        navigationTile(style)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Text(L.t("Langue", "Language"))
                        .font(.label(8.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 64, alignment: .leading)
                    ForEach(AppLanguage.allCases) { language in
                        languageTile(language)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
        }
    }

    private func languageTile(_ language: AppLanguage) -> some View {
        let selected = state.language == language
        return Button {
            state.language = language
        } label: {
            HStack(spacing: 7) {
                Text(language.short)
                    .font(.numeral(8.5, weight: .bold))
                    .foregroundStyle(selected ? Theme.ember : Theme.textTertiary)
                Text(language.title)
                    .font(.label(9.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.ember.opacity(0.08) : Theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.ember.opacity(0.35) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 132)
    }

    private func navigationTile(_ style: NavigationStyle) -> some View {
        let selected = state.navigationStyle == style
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                state.navigationStyle = style
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: style == .sidebar ? "sidebar.left" : "menubar.dock.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Theme.ember : Theme.textTertiary)
                Text(style.title)
                    .font(.label(9.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.ember.opacity(0.08) : Theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.ember.opacity(0.35) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 168)
    }

    private func modeTile(_ mode: ThemeMode) -> some View {
        let selected = state.themeMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { state.themeMode = mode }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == .day ? "sun.max.fill" : mode == .oled ? "circle.lefthalf.filled" : "moon.stars.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Theme.ember : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(.label(10, weight: .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                    Text(mode.detail)
                        .font(.label(8))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.ember.opacity(0.08) : Theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.ember.opacity(0.35) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: Artwork

    private var artworkPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.violet.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(L.t("Visuels des jeux"))
                                .font(.label(12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("IGDB")
                                .font(.label(7.5, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.violet)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Theme.violet.opacity(0.10)))
                        }
                        Text(L.t("Couvertures et bannières récupérées depuis IGDB · \(artworkSummary)", "Covers and banners fetched from IGDB · \(artworkSummary)"))
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 10)

                    HStack(spacing: 6) {
                        if state.artworks.isRunning {
                            GhostButton(title: L.t("Interrompre"), icon: "stop.circle", tint: Theme.danger, compact: true) {
                                state.artworks.cancel()
                            }
                        } else {
                            if state.artworks.count > 0 {
                                GhostButton(title: L.t("Vider"), icon: "trash", compact: true) {
                                    state.artworks.clearCache()
                                }
                                .help(L.t("Supprimer les visuels téléchargés"))
                            }
                            GhostButton(title: L.t("Tester"), icon: "bolt.horizontal", compact: true) {
                                saveCredentials()
                                Task { await state.artworks.testConnection() }
                            }
                            .disabled(!state.artworks.isConfigured)

                            GhostButton(title: L.t("Récupérer"), icon: "arrow.down.circle",
                                        tint: Theme.ember, compact: true) {
                                fetchArtwork()
                            }
                            .disabled(!state.artworks.isConfigured || state.artworks.isRunning || state.games.isEmpty)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Hairline()

                credentials

                if state.artworks.isRunning || !state.artworks.status.isEmpty || state.artworks.lastError != nil {
                    Hairline()
                    artworkStatus
                }
            }
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                credentialField("Client ID", text: $igdbClientID, secure: false, width: 240)
                credentialField("Client Secret", text: $igdbSecret, secure: true, width: 240)

                Button {
                    saveCredentials()
                } label: {
                    Text(L.t("Enregistrer"))
                        .font(.label(9, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.fill(0.06)))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(igdbClientID.trimmingCharacters(in: .whitespaces).isEmpty
                          || (igdbSecret.isEmpty && !state.artworks.hasSecret))

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: state.artworks.hasSecret ? "lock.fill" : "lock.open")
                        .font(.system(size: 7.5, weight: .semibold))
                    Text(state.artworks.hasSecret ? L.t("secret dans le Keychain") : "secret manquant")
                        .font(.label(8))
                }
                .foregroundStyle(state.artworks.hasSecret ? Theme.mint.opacity(0.8) : Theme.textTertiary)
            }

            Text(L.t("dev.twitch.tv/console → Applications → votre app. Le client ID reste en préférences, le secret va dans le Keychain.", "dev.twitch.tv/console → Applications → your app. The client ID stays in preferences, the secret goes to the Keychain."))
                .font(.label(8))
                .foregroundStyle(Theme.textTertiary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func credentialField(_ label: String, text: Binding<String>, secure: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.label(8, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Group {
                if secure {
                    SecureField(state.artworks.hasSecret ? L.t("•••••••• (enregistré)") : "secret", text: text)
                } else {
                    TextField("client id", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.mono(9.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .frame(width: width)
        }
    }

    private var artworkStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if state.artworks.isRunning {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                } else if state.artworks.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                } else {
                    Circle().fill(Theme.mint).frame(width: 4, height: 4)
                }

                Text(state.artworks.lastError ?? (state.artworks.status.isEmpty ? L.t("Prêt") : state.artworks.status))
                    .font(.label(9))
                    .foregroundStyle(state.artworks.lastError == nil ? Theme.textSecondary : Theme.warning.opacity(0.9))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(state.artworks.count) en cache · \(state.artworks.missingCount) sans visuel")
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }

            if state.artworks.isRunning {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill(0.06))
                        Capsule()
                            .fill(Theme.ember)
                            .frame(width: max(2, geo.size.width * state.artworks.progress))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var artworkSummary: String {
        let count = state.artworks.count
        if count == 0 { return L.t("aucun visuel en cache", "no artwork cached") }
        return L.t("\(count) visuel\(count > 1 ? "s" : "") en cache", "\(count) artwork item\(count > 1 ? "s" : "") cached")
    }

    private func saveCredentials() {
        state.artworks.clientID = igdbClientID.trimmingCharacters(in: .whitespaces)
        let secret = igdbSecret.trimmingCharacters(in: .whitespaces)
        if !secret.isEmpty {
            state.artworks.saveSecret(secret)
            igdbSecret = ""
        }
    }

    private func fetchArtwork() {
        saveCredentials()
        Task {
            await state.artworks.fetchAll(games: state.games)
        }
    }

    // MARK: Update

    private var updateRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(updateTint.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(updateTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(L.t("Mise à jour nxnative"))
                        .font(.label(11, weight: .medium))
                        .foregroundStyle(Theme.text)
                    updateBadge
                    if canShowChangelog {
                        Button {
                            openChangelog()
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(verbatim: changelogChipLabel)
                                    .font(.label(8.5, weight: .medium))
                            }
                            .foregroundStyle(showChangelog ? Theme.ember : Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Capsule().fill((showChangelog ? Theme.ember : Color.white).opacity(showChangelog ? 0.10 : 0.05)))
                        }
                        .buttonStyle(.plain)
                        .help(L.t("Voir les changements de la dernière mise à jour"))
                        .popover(isPresented: $showChangelog, arrowEdge: .bottom) {
                            if let changelog = state.repoUpdate.lastUpdate ?? state.repoUpdate.recent {
                                UpdateChangelogView(
                                    changelog: changelog,
                                    onClose: { showChangelog = false },
                                    onClear: {
                                        showChangelog = false
                                        state.repoUpdate.dismissChangelog()
                                    }
                                )
                            }
                        }
                    }
                }
                Text(state.repoUpdate.detail)
                    .font(.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if !state.repoUpdate.log.isEmpty, state.repoUpdate.isBusy || updateFailed {
                    Text(state.repoUpdate.log.suffix(3).joined(separator: "\n"))
                        .font(.mono(8.5))
                        .foregroundStyle(updateFailed ? Theme.warning.opacity(0.85) : Theme.textTertiary.opacity(0.8))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 6) {
                GhostButton(title: state.repoUpdate.isBusy ? L.t("Vérification…", "Checking…") : L.t("Vérifier", "Check"),
                            icon: "arrow.clockwise", compact: true) {
                    Task { await state.repoUpdate.check(repo: state.repo.url) }
                }
                .disabled(state.repoUpdate.isBusy || !state.repo.isValid)

                if state.repoUpdate.behindCount > 0 {
                    GhostButton(title: L.t("Mettre à jour"), icon: "arrow.down.circle.fill",
                                tint: Theme.ember, compact: true) {
                        updateRepo()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var updateTint: Color {
        switch state.repoUpdate.state {
        case .ready, .updated: return Theme.mint
        case .behind, .notGit, .failed: return Theme.warning
        case .checking, .updating: return Theme.emberSoft
        case .idle: return Theme.textTertiary
        }
    }

    private var updateFailed: Bool {
        if case .failed = state.repoUpdate.state { return true }
        return false
    }

    @ViewBuilder
    private var updateBadge: some View {
        switch state.repoUpdate.state {
        case .checking, .updating:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.55)
                Text(state.repoUpdate.statusLabel)
                    .font(.label(8.5, weight: .medium))
                    .foregroundStyle(Theme.emberSoft)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.ember.opacity(0.08)))
        case .ready, .updated:
            statusPill("À jour", tint: Theme.mint, icon: "checkmark.circle.fill")
        case .behind(let snapshot):
            statusPill(L.t("\(snapshot.behind) en retard", "\(snapshot.behind) behind"), tint: Theme.warning, icon: "arrow.down.circle.fill")
        case .notGit:
            statusPill(L.t("pas un dépôt git"), tint: Theme.warning, icon: "exclamationmark.triangle.fill")
        case .failed:
            statusPill(L.t("échec de vérification"), tint: Theme.warning, icon: "exclamationmark.triangle.fill")
        case .idle:
            statusPill(L.t("non vérifié"), tint: Theme.textTertiary, icon: "circle.dashed")
        }
    }

    private func statusPill(_ text: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
            Text(text)
                .font(.label(8.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.09)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }

    private func updateRepo() {
        Task {
            let updated = await state.repoUpdate.update(repo: state.repo.url)
            if updated {
                state.refreshRepo()
                checker.run(repo: state.repo)
                showChangelog = state.repoUpdate.lastUpdate != nil
            }
        }
    }

    private func copyDiagnostic() {
        var lines = [
            "NXN Studio \(AppVersion.marketing) (\(AppVersion.build)) · \(AppVersion.platform)",
            "Dépôt : \(state.repoPath.isEmpty ? L.t("non configuré") : state.repoPath)",
            "",
        ]
        for check in checker.checks {
            let mark: String
            switch check.state {
            case .ok: mark = "OK"
            case .warn: mark = "WARN"
            case .missing: mark = "MANQUANT"
            case .running, .idle: mark = "…"
            }
            lines.append("[\(mark)] \(check.label) — \(check.detail)")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func cloneRepo() {
        let panel = NSOpenPanel()
        panel.title = L.t("Où cloner nxnative ?")
        panel.message = L.t("Choisissez un dossier ; nxnative sera créé dedans.")
        panel.prompt = "Cloner ici"
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        var destination = parent.appendingPathComponent("nxnative")
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("nxnative-\(Int(Date().timeIntervalSince1970))")
        }

        Task {
            if await state.setup.clone(into: destination) {
                state.repoPath = destination.path
                state.refreshRepo()
                checker.run(repo: state.repo)
            }
        }
    }

    // MARK: Changelog

    private var canShowChangelog: Bool {
        state.repo.isValid
            && (state.repoUpdate.lastUpdate != nil || state.repoUpdate.lastCheck != nil)
    }

    private var changelogChipLabel: String {
        if let update = state.repoUpdate.lastUpdate {
            return "\(update.total) commit\(update.total > 1 ? "s" : "")"
        }
        return L.t("commits récents")
    }

    private func openChangelog() {
        if state.repoUpdate.lastUpdate != nil || state.repoUpdate.recent != nil {
            showChangelog.toggle()
            return
        }
        Task {
            await state.repoUpdate.loadRecentCommits(repo: state.repo.url)
            showChangelog = state.repoUpdate.recent != nil
        }
    }

    // MARK: Diagnostic

    private var diagnosticPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(L.t("Diagnostic"))
                                .font(.label(12, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if installer.isRunning {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini).scaleEffect(0.55)
                                    Text(installer.statusText)
                                        .font(.label(8.5))
                                        .foregroundStyle(Theme.emberSoft)
                                }
                            }
                        }
                        Text(diagnosticSummary)
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()

                    GhostButton(title: L.t("Copier"), icon: "doc.on.doc", compact: true) {
                        copyDiagnostic()
                    }
                    .help(L.t("Copier le diagnostic dans le presse-papiers"))

                    if !bulkSteps.isEmpty {
                        GhostButton(title: L.t("Tout installer"),
                                    icon: "arrow.down.circle",
                                    tint: Theme.ember,
                                    compact: true) {
                            confirmInstallAll = true
                        }
                        .disabled(installer.isRunning)
                    }

                    GhostButton(title: checker.isChecking ? L.t("Vérification…", "Checking…") : L.t("Vérifier", "Check"),
                                icon: "stethoscope",
                                compact: true) {
                        checker.run(repo: state.repo)
                    }
                    .disabled(checker.isChecking || installer.isRunning)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Hairline()

                VStack(spacing: 0) {
                    ForEach(Array(checker.checks.enumerated()), id: \.element.id) { index, check in
                        if index > 0 { Hairline().padding(.leading, 42) }
                        CheckRow(
                            check: check,
                            installTitle: installTitle(for: check),
                            installBusy: installer.state(for: check.id) == .running,
                            installResult: installer.state(for: check.id),
                            install: installAction(for: check)
                        )
                    }
                }
                .padding(.vertical, 4)

                if !installer.log.isEmpty {
                    Hairline()
                    installerConsole
                }
            }
        }
    }

    // MARK: Install helpers

    private var bulkSteps: [InstallStep] {
        checker.checks.compactMap { check in
            guard check.state == .missing || check.state == .warn else { return nil }
            guard let step = InstallCatalog.step(for: check.id), step.isAutomatic else { return nil }
            return step
        }
    }

    private func installTitle(for check: ToolCheck) -> String? {
        guard check.state == .missing || check.state == .warn,
              let step = InstallCatalog.step(for: check.id) else { return nil }
        if step.id == "brew" { return "Installer" }
        return step.kind == .manual ? "App Store" : "Installer"
    }

    private func installAction(for check: ToolCheck) -> (() -> Void)? {
        guard check.state == .missing || check.state == .warn,
              let step = InstallCatalog.step(for: check.id) else { return nil }
        return {
            if step.id == "brew" {
                Task { await state.setup.installHomebrew() }
                return
            }
            if step.kind == .manual, let url = step.url {
                NSWorkspace.shared.open(url)
                return
            }
            Task {
                await installer.install(step, repo: state.repo.url)
                checker.run(repo: state.repo)
            }
        }
    }

    private func installAll() {
        let steps = bulkSteps
        guard !steps.isEmpty else { return }
        Task {
            await installer.installAll(steps, repo: state.repo.url)
            checker.run(repo: state.repo)
        }
    }

    private var installerConsole: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(installer.lastFailure == nil ? Theme.emberSoft : Theme.warning)
                Text(L.t("Journal d'installation", "Install log"))
                    .font(.label(9.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if installer.isRunning {
                    Button {
                        installer.cancel()
                    } label: {
                        Text(L.t("Interrompre"))
                            .font(.label(9, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                    .help(L.t("Arrêter l'installation en cours"))
                } else {
                    if installer.lastFailure != nil, !bulkSteps.isEmpty {
                        Button {
                            installAll()
                        } label: {
                            Text(L.t("Reprendre"))
                                .font(.label(9, weight: .semibold))
                                .foregroundStyle(Theme.ember)
                        }
                        .buttonStyle(.plain)
                        .help(L.t("Relancer les dépendances encore manquantes"))
                    }
                    Button {
                        installer.clear()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L.t("Fermer le journal"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(installer.log) { line in
                            Text(line.text)
                                .font(.mono(8.5))
                                .foregroundStyle(color(for: line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .frame(height: 116)
                .onChange(of: installer.log.last?.id) {
                    guard let last = installer.log.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func color(for kind: DependencyInstaller.LogLine.Kind) -> Color {
        switch kind {
        case .command: return Theme.emberSoft
        case .output: return Theme.textTertiary
        case .success: return Theme.mint
        case .failure: return Theme.danger
        }
    }

    private var diagnosticSummary: String {
        if checker.isChecking { return L.t("Analyse de la chaîne d'outils…") }
        if checker.checks.isEmpty { return L.t("Lancez une vérification de l'environnement") }
        let failed = checker.checks.filter { $0.required && $0.state == .missing }.count
        let warned = checker.checks.filter { $0.state == .warn }.count
        let stamp = checker.lastRun.map { L.t(" · vérifié à \(Fmt.clock($0))", " · checked at \(Fmt.clock($0))") } ?? ""
        if failed > 0 { return L.t("\(failed) outil\(failed > 1 ? "s" : "") manquant\(failed > 1 ? "s" : "")\(stamp)", "\(failed) missing tool\(failed > 1 ? "s" : "")\(stamp)") }
        if warned > 0 { return L.t("Prêt · \(warned) avertissement\(warned > 1 ? "s" : "")\(stamp)", "Ready · \(warned) warning\(warned > 1 ? "s" : "")\(stamp)") }
        return L.t("Tous les outils requis sont présents\(stamp)", "All required tools are present\(stamp)")
    }

    // MARK: History

    private var historyPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("Historique des builds"))
                            .font(.label(12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(state.records.isEmpty ? L.t("Aucune build enregistrée") : "\(state.records.count) builds locales")
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if !state.records.isEmpty {
                        GhostButton(title: L.t("Effacer"), icon: "trash", compact: true) {
                            state.resetHistory()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if !state.records.isEmpty {
                    Hairline()
                    VStack(spacing: 0) {
                        ForEach(state.records.prefix(6)) { record in
                            HistoryRow(record: record)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: About

    private var aboutPanel: some View {
        Panel(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("NXN Studio")
                            .font(.label(12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Chip(text: "v\(AppVersion.marketing)", color: Theme.textTertiary)
                        Chip(text: AppVersion.platform, color: Theme.textTertiary)
                    }
                    Text(L.t("Client macOS non officiel pour nxnative, sans affiliation avec Nintendo. Les jeux et leurs données restent sur votre Mac ; rien n'est envoyé."))
                        .font(.label(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    HStack(spacing: 14) {
                        Link(destination: URL(string: "https://github.com/seedds/nxnative")!) {
                            linkLabel(L.t("Dépôt nxnative"), icon: "arrow.up.right")
                        }
                        Link(destination: URL(string: "https://github.com/seedds/nxnative/blob/main/docs/frontends.md")!) {
                            linkLabel("Docs front ends", icon: "book")
                        }
                        Link(destination: URL(string: "https://github.com/seedds/nxnative/blob/main/LICENSE")!) {
                            linkLabel("Licence nxnative (MIT)", icon: "doc.text")
                        }
                        Link(destination: URL(string: "https://www.igdb.com")!) {
                            linkLabel(L.t("Données IGDB"), icon: "photo")
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func linkLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.label(9.5, weight: .medium))
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
        }
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Helpers

    private func panelHeader(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.label(12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Setting row

struct SettingRow<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let status: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.label(11, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(status)
                        .font(.label(8.5))
                        .foregroundStyle(tint.opacity(0.9))
                }
                Text(detail)
                    .font(.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 10)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Check row

struct CheckRow: View {
    let check: ToolCheck
    var installTitle: String? = nil
    var installBusy: Bool = false
    var installResult: DependencyInstaller.ItemState? = nil
    var install: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(check.label)
                        .font(.label(10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    if !check.required {
                        Text(L.t("optionnel", "optional"))
                            .font(.label(7.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.fill(0.04)))
                    }
                }
                Text(check.detail)
                    .font(.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let hint = check.hint, check.state == .missing || check.state == .warn {
                    Text(hint)
                        .font(.mono(8.5))
                        .foregroundStyle(Theme.warning.opacity(0.75))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                if case .failed(let message)? = installResult {
                    Text(L.t("Échec : \(message)", "Failed: \(message)"))
                        .font(.mono(8.5))
                        .foregroundStyle(Theme.danger.opacity(0.85))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if check.state == .running {
                ProgressView().controlSize(.mini).scaleEffect(0.75)
            } else if installBusy {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                    Text("Installation…")
                        .font(.label(8.5))
                        .foregroundStyle(Theme.emberSoft)
                }
            } else if let install, let installTitle {
                GhostButton(
                    title: installTitle,
                    icon: installTitle == "App Store" ? "arrow.up.forward.app" : "arrow.down.circle",
                    tint: Theme.ember,
                    compact: true,
                    action: install
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var color: Color {
        switch check.state {
        case .ok: return Theme.mint
        case .warn: return Theme.warning
        case .missing: return Theme.danger
        case .running, .idle: return Theme.textTertiary
        }
    }
}

// MARK: - History row

struct HistoryRow: View {
    @EnvironmentObject private var state: AppState
    let record: BuildRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(record.succeeded ? Theme.mint : Theme.danger)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name)
                    .font(.label(10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("\(platformName) · \(Fmt.relative(record.date)) · \(Fmt.duration(record.seconds))")
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if record.outputExists {
                GhostButton(title: "Finder", icon: "folder", compact: true) {
                    if let path = record.outputPath { state.reveal(path) }
                }
                if record.isApp {
                    GhostButton(title: L.t("Jouer"), icon: "play.fill", tint: Theme.mint, compact: true) {
                        state.play(record)
                    }
                }
            } else {
                Text(L.t("sortie supprimée"))
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var platformName: String {
        BuildPlatform(rawValue: record.platform)?.title ?? record.platform
    }
}
