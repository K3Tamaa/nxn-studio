import SwiftUI
import UniformTypeIdentifiers

struct BuildView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var checker = ToolchainChecker()

    var body: some View {
        Group {
            if !state.repo.isValid {
                OnboardingView()
            } else if state.runner.phase != .idle
                        && (state.runner.phase.isRunning
                            || state.runner.startedGameID == state.selection?.id
                            || state.selection == nil) {
                BuildMonitorView(runner: state.runner)
                    .transition(.opacity)
            } else if let game = state.selection {
                BuildFormView(checker: checker, game: game)
                    .transition(.opacity)
            } else if let direct = directGame {
                BuildFormView(checker: checker, game: direct)
                    .transition(.opacity)
            } else {
                NoGameSelectedView()
            }
        }
        .animation(.easeOut(duration: 0.22), value: state.runner.phase)
    }

    /// A source picked without going through the library: no profile, but a valid build.
    private var directGame: Game? {
        guard !state.draft.sourcePath.isEmpty, let url = state.draft.sourceURL else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return Game(
            id: "direct",
            name: name.isEmpty ? "Source directe" : name,
            ipaName: nil,
            category: nil,
            profileURL: url,
            isSwitch2: false
        )
    }
}

// MARK: - No selection

struct NoGameSelectedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Construire", subtitle: "Packagez un jeu en app native") {
                EmptyView()
            }

            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.ember.opacity(0.14), Theme.violet.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 92, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Theme.ember.opacity(0.24), lineWidth: 1)
                        )
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.ember)
                }
                Text("Choisissez un jeu à packager")
                    .font(.display(22, weight: .semibold))
                    .trackingHeadline(-0.4)
                    .foregroundStyle(Theme.text)
                Text("Sélectionnez un profil dans la bibliothèque, ou pointez directement un dossier de NSP, un dump ou un fichier .nup.")
                    .font(.label(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    PrimaryButton(title: "Parcourir la bibliothèque", icon: "square.grid.2x2") {
                        state.route = .library
                    }
                    GhostButton(title: "Choisir un dossier", icon: "folder") {
                        state.chooseSource()
                    }
                }
                .padding(.top, 4)

                HStack(spacing: 6) {
                    Text("Astuce : glissez un dossier ou un .nup sur la fenêtre.")
                        .font(.label(9.5))
                        .foregroundStyle(Theme.textTertiary.opacity(0.8))
                }
                .padding(.top, 6)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                state.draft.sourcePath = url.path
                state.route = .build
            }
        }
        return true
    }
}

// MARK: - Build form

struct BuildFormView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var checker: ToolchainChecker
    let game: Game

    @State private var advancedOpen = false
    @State private var copied = false
    @State private var packages: [BuildPackage] = []
    @State private var packagesSource = ""

    private var requiredFailures: [ToolCheck] {
        checker.checks.filter { $0.required && ($0.state == .missing || $0.state == .warn) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    targetPicker
                    sourceSection
                    contentSection
                    optionsSection
                    advancedSection
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .frame(maxWidth: state.navigationStyle == .dock ? .infinity : 940, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            footerBar
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { state.draft.sourcePath = url.path }
            }
            return true
        }
        .task {
            if checker.checks.isEmpty {
                checker.run(repo: state.repo)
            }
            loadPackages()
        }
        .onChange(of: state.draft.sourcePath) {
            loadPackages()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentSection: some View {
        if !packages.isEmpty {
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        SectionLabel(text: "Contenus du build")
                        Text(verbatim: "\(selectedCount)/\(packages.count)")
                            .font(.numeral(9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.fill(0.05)))
                        Spacer()
                        Button(selectedCount == packages.count ? "Tout désélectionner" : "Tout sélectionner") {
                            toggleAll()
                        }
                        .buttonStyle(.plain)
                        .font(.label(9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    ForEach(packages) { package in
                        Hairline().padding(.leading, 16)
                        packageRow(package)
                    }

                    Hairline().padding(.top, 2)
                    Text("La base est toujours incluse ; les mises à jour et DLC cochés sont copiés dans le build.")
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var selectedCount: Int {
        packages.filter { isSelected($0) }.count
    }

    private func isSelected(_ package: BuildPackage) -> Bool {
        package.kind == .base || state.draft.includedPackages.contains(package.path)
    }

    private func packageRow(_ package: BuildPackage) -> some View {
        let selected = isSelected(package)
        let tint = package.kind == .base ? Theme.textSecondary
            : package.kind == .update ? Theme.cyan
            : package.kind == .dlc ? Theme.violet
            : Theme.warning

        return Button {
            guard package.kind != .base else { return }
            var paths = Set(state.draft.includedPackages)
            if paths.contains(package.path) { paths.remove(package.path) } else { paths.insert(package.path) }
            state.draft.includedPackages = Array(paths)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? Theme.ember.opacity(0.16) : Theme.fill(0.04))
                        .frame(width: 16, height: 16)
                    if package.kind == .base {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    } else if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Theme.ember)
                    }
                }

                Image(systemName: package.kind.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(package.name)
                        .font(.label(10.5, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(package.kind.label) · \(package.versionLabel)")
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 8)

                Text(package.sizeLabel)
                    .font(.mono(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(selected ? 1 : 0.55)
    }

    private func toggleAll() {
        if selectedCount == packages.count {
            state.draft.includedPackages = []
        } else {
            state.draft.includedPackages = packages.map(\.path)
        }
    }

    private func loadPackages() {
        guard let url = state.draft.sourceURL,
              ["nsp", "nsz", "xci", "xcz"].contains(url.pathExtension.lowercased()) else {
            packages = []
            packagesSource = ""
            state.draft.includedPackages = []
            return
        }
        let baseID = game.id.count == 16 ? game.id : nil
        let list = BuildContent.packages(beside: url, baseID: baseID)
        packages = list
        if packagesSource != url.path {
            packagesSource = url.path
            state.draft.includedPackages = []
        }
        if state.draft.includedPackages.isEmpty {
            state.draft.includedPackages = list
                .filter { $0.kind != .other }
                .map(\.path)
        }
    }

    // MARK: Header

    private var header: some View {
        headerContent
            .background(alignment: .top) { headerBanner }
            .overlay(alignment: .bottom) { Hairline() }
    }

    /// Wide IGDB artwork behind the title, graded into the canvas.
    private var headerBanner: some View {
        ZStack {
            if let url = state.wideArtworkURL(for: game) ?? state.posterURL(for: game),
               let image = NSImage(contentsOf: url) {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .opacity(0.5)
            } else {
                LinearGradient(
                    colors: [Theme.ember.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            LinearGradient(
                colors: [Theme.canvas.opacity(0.35), Theme.canvas.opacity(0.85), Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }

    private var headerContent: some View {
        HStack(spacing: 14) {
            Button {
                state.route = .library
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fill(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Retour à la bibliothèque")

            GameCover(game: game, iconURL: state.iconURL(for: game), posterURL: state.posterURL(for: game), height: 46, bannerStyle: false)
                .frame(width: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairlineStrong, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("CONSTRUIRE")
                        .font(.label(7.5, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.ember.opacity(0.9))
                    Text("·")
                        .font(.label(7.5, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(state.draft.platform.title)")
                        .font(.label(7.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(game.name)
                    .font(.display(21, weight: .semibold))
                    .trackingHeadline(-0.4)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if game.id == "direct" {
                        Chip(text: "Source directe", icon: "folder", color: Theme.textSecondary)
                    } else {
                        Chip(text: game.platformLabel,
                             icon: game.isSwitch2 ? "bolt.fill" : "gamecontroller.fill",
                             color: game.isSwitch2 ? Theme.violet : Theme.textSecondary)
                        Text(game.id)
                            .font(.mono(9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer()

            if let record = state.latestRecord(for: game) {
                HStack(spacing: 6) {
                    Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(record.succeeded ? Theme.mint : Theme.danger)
                    Text("Dernière build \(Fmt.relative(record.date))")
                        .font(.label(9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    // MARK: Target

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Cible")
            HStack(spacing: 10) {
                ForEach(BuildPlatform.allCases) { platform in
                    TargetCard(
                        platform: platform,
                        selected: state.draft.platform == platform
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) { state.draft.platform = platform }
                    }
                }
            }
        }
    }

    // MARK: Source / keys / output

    private var sourceSection: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    SectionLabel(text: "Source du jeu")
                    if let kind = sourceKind {
                        Chip(text: kind.label, icon: kind.icon, color: Theme.textSecondary)
                    }
                    Spacer()
                    Text(state.draft.isNUP ? "Aucune clé requise pour un .nup" : "Glissez un dossier, un .nup ou un dump")
                        .font(.label(9))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Button {
                    state.chooseSource(for: game)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(state.draft.sourcePath.isEmpty ? Theme.fill(0.04) : Theme.ember.opacity(0.12))
                                .frame(width: 38, height: 38)
                            Image(systemName: state.draft.sourcePath.isEmpty ? "tray.and.arrow.down" : "folder.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(state.draft.sourcePath.isEmpty ? Theme.textTertiary : Theme.ember)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if state.draft.sourcePath.isEmpty {
                                Text("Choisir un dossier de jeu ou un .nup")
                                    .font(.label(12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("NSP, XCI, NSZ, XCZ, dump (base/ updates/ dlc/) ou NUP")
                                    .font(.label(9.5))
                                    .foregroundStyle(Theme.textTertiary)
                            } else {
                                Text((state.draft.sourcePath as NSString).lastPathComponent)
                                    .font(.label(12, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(state.draft.sourcePath)
                                    .font(.mono(9))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("Parcourir")
                            .font(.label(10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fill(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.inset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: state.draft.sourcePath.isEmpty ? [4, 4] : []))
                            .foregroundStyle(Theme.hairlineStrong)
                    )
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                VStack(spacing: 0) {
                    PathRow(
                        icon: "key.fill",
                        label: "prod.keys",
                        value: state.draft.keysPath,
                        placeholder: keyless ? "Non nécessaire pour un .nup" : "Requis pour les NSP",
                        warning: !keyless && !state.draft.keysPath.isEmpty && !FileManager.default.fileExists(atPath: state.draft.keysPath),
                        action: {
                            state.chooseKeys()
                            state.draft.keysPath = state.keysPath
                        }
                    )
                    Hairline().padding(.leading, 16)
                    PathRow(
                        icon: "arrow.down.doc.fill",
                        label: "Sortie",
                        value: state.draft.outputPath,
                        placeholder: "Automatique (\(state.draft.platform.outputExtension?.uppercased() ?? "dossier") dans le dossier du jeu)",
                        action: state.chooseOutput
                    )
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
        }
    }

    private struct SourceKind {
        let label: String
        let icon: String
    }

    private var keyless: Bool {
        state.draft.isNUP || sourceKind?.label == "NUP"
    }

    private var sourceKind: SourceKind? {
        guard let url = state.draft.sourceURL else { return nil }
        if url.pathExtension.lowercased() == "nup" { return SourceKind(label: "NUP", icon: "shippingbox") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return SourceKind(label: "Fichier", icon: "doc")
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let lower = names.map { $0.lowercased() }
        if lower.contains(where: { $0.hasSuffix(".nsp") || $0.hasSuffix(".xci") || $0.hasSuffix(".nsz") || $0.hasSuffix(".xcz") }) {
            return SourceKind(label: "NSP", icon: "square.stack.3d.up")
        }
        if lower.contains(where: { $0.hasSuffix(".nup") }) {
            return SourceKind(label: "NUP", icon: "shippingbox")
        }
        if lower.contains("base") || lower.contains("exefs") || lower.contains("romfs") || lower.contains("updates") {
            return SourceKind(label: "Dump", icon: "folder")
        }
        return SourceKind(label: "Dossier", icon: "folder")
    }

    // MARK: Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Empaquetage")
            Panel(padding: 6) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    OptionToggle(
                        title: "RomFS séparé",
                        detail: "IPA léger, jeu copié à part sur l'appareil",
                        isOn: $state.draft.romfsSeparate
                    )
                    OptionToggle(
                        title: "Shaders en fichiers",
                        detail: "Pour AltServer, exige le RomFS séparé",
                        isOn: $state.draft.shaderFiles,
                        disabled: !state.draft.romfsSeparate
                    )
                    OptionToggle(
                        title: "Conserver l'extraction",
                        detail: "Accélère les builds suivantes",
                        isOn: $state.draft.keepExtracted
                    )
                    if state.draft.platform == .ios {
                        OptionToggle(
                            title: "Compteur de FPS",
                            detail: "Affiche les images/s en haut à gauche",
                            isOn: $state.draft.showFPS
                        )
                    } else {
                        OptionToggle(
                            title: "Shaders déjà vus",
                            detail: "Seulement les shaders des playtests",
                            isOn: $state.draft.seenShaders
                        )
                    }
                    OptionToggle(
                        title: "Motion",
                        detail: "Gyroscope et manette à mouvement",
                        isOn: $state.draft.motion
                    )
                    OptionToggle(
                        title: "Ignorer les régressions",
                        detail: "Packe même si un shader échoue",
                        isOn: $state.draft.allowShaderRegressions
                    )
                }
                .padding(2)
            }
            .padding(.horizontal, -6)
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { advancedOpen.toggle() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Text("Options avancées")
                            .font(.label(11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("identité, version, shaders")
                            .font(.label(9))
                            .foregroundStyle(Theme.textTertiary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(advancedOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if advancedOpen {
                    Hairline()
                    VStack(alignment: .leading, spacing: 14) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 12) {
                            FieldBox(label: "Version", placeholder: "la plus récente", text: $state.draft.packageVersion, mono: true)
                            FieldBox(label: "Nom de l'app", placeholder: game.name, text: $state.draft.appName)
                            FieldBox(label: "Bundle ID", placeholder: game.id == "direct" ? "org.nxnative.<title ID>" : "org.nxnative.\(game.id)", text: $state.draft.bundleID, mono: true)
                            FieldBox(label: "Langue", placeholder: "English", text: $state.draft.language)
                            FieldBox(label: "Team ID", placeholder: "équipe Apple", text: $state.draft.teamID, mono: true)
                            FieldBox(label: "GPU", placeholder: state.draft.platform == .ios ? "g18p" : "GPU de ce Mac", text: $state.draft.gpu, mono: true)
                            FieldBox(label: "Dossier de travail", placeholder: "<title ID>_build à côté du jeu", text: $state.draft.workDir, mono: true)
                            IconField(label: "Icône de l'app", text: $state.draft.iconPath)
                        }

                        Hairline()

                        VStack(spacing: 0) {
                            CompactToggle(title: "Enquête seulement", detail: "Jeu sans profil : écrit le survey, ne packe rien", isOn: $state.draft.surveyOnly)
                            CompactToggle(title: "Autoriser un autre compilateur Metal", detail: "Xcode 27.2 est celui testé : un autre peut casser le rendu", isOn: $state.draft.allowOtherMetal)
                            CompactToggle(title: "Autoriser les fichiers endommagés", detail: "Écrit les NCA tels quels au lieu de s'arrêter", isOn: $state.draft.allowDamaged)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: Build bar

    private var footerBar: some View {
        VStack(spacing: 0) {
            Hairline()
            buildBar
                .frame(maxWidth: state.navigationStyle == .dock ? .infinity : 940, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(
            ZStack {
                Theme.canvas
                LinearGradient(colors: [Theme.fill(0.012), .clear], startPoint: .top, endPoint: .bottom)
            }
        )
    }

    private var buildBar: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(checker.isChecking ? Theme.textTertiary : (requiredFailures.isEmpty ? Theme.mint : Theme.warning))
                            .frame(width: 5, height: 5)
                        Text(checker.isChecking
                             ? "Vérification de l'environnement…"
                             : (requiredFailures.isEmpty
                                ? "Environnement prêt · \(state.repo.gamesCount) profils"
                                : "\(requiredFailures.count) outil\(requiredFailures.count > 1 ? "s" : "") à vérifier"))
                            .font(.label(10, weight: .medium))
                            .foregroundStyle(checker.isChecking ? Theme.textTertiary : (requiredFailures.isEmpty ? Theme.textSecondary : Theme.warning))
                        if checker.isChecking {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        }
                    }
                    Text("Première build : 30–60 min selon le jeu. Prévoyez 2× la taille du jeu + 10 Go.")
                        .font(.label(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if keyless {
                    Chip(text: "sans clés", icon: "lock.open", color: Theme.mint)
                } else if state.draft.keysPath.isEmpty {
                    Chip(text: "prod.keys manquant", icon: "exclamationmark.triangle", color: Theme.warning)
                }

                Button {
                    state.runner.start(
                        repo: URL(fileURLWithPath: (state.repoPath as NSString).expandingTildeInPath),
                        game: state.selection,
                        options: state.draft
                    )
                    state.keysPath = state.draft.keysPath
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                        Text("Lancer la build").font(.label(12.5, weight: .semibold))
                    }
                    .foregroundStyle(.black.opacity(state.draft.isReady ? 0.92 : 0.35))
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.emberGradient)
                            .opacity(state.draft.isReady ? 1 : 0.4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.fill(0.18), lineWidth: 1)
                    )
                    .shadow(color: Theme.ember.opacity(state.draft.isReady ? 0.3 : 0), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(!state.draft.isReady)
                .help(state.draft.isReady ? "Démarrer la build" : "Choisissez d'abord une source")
            }

            // Command preview
            if state.draft.isReady {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(commandPreview)
                        .font(.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commandPreview, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(copied ? Theme.mint : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copier la commande")
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill(0.018)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var commandPreview: String {
        let script = URL(fileURLWithPath: (state.repoPath as NSString).expandingTildeInPath)
            .appendingPathComponent("scripts/build_ipa_from_nsp.py").path
        let source = (state.draft.sourcePath as NSString).expandingTildeInPath
        let args = [script, source] + state.draft.arguments()
        return "python3 " + BuildRunner.prettyCommand(args.map(Self.abbreviateHome))
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        let replacement = path.contains(" ") ? "$HOME" : "~"
        if path == home { return replacement }
        if path.hasPrefix(home + "/") { return replacement + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Target card

struct TargetCard: View {
    let platform: BuildPlatform
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.ember.opacity(0.14) : Theme.fill(0.04))
                        .frame(width: 30, height: 30)
                    Image(systemName: platform.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Theme.ember : Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.title)
                        .font(.label(11.5, weight: .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
                    Text(platform.subtitle)
                        .font(.label(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Theme.ember.opacity(0.055) : (hover ? Theme.fill(0.032) : Theme.panel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Theme.ember.opacity(0.42) : (hover ? Theme.hairlineStrong : Theme.hairline), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Rows

struct PathRow: View {
    let icon: String
    let label: String
    let value: String
    let placeholder: String
    var warning: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16)
                Text(label)
                    .font(.label(10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 62, alignment: .leading)
                Text(value.isEmpty ? placeholder : value)
                    .font(value.isEmpty ? .label(10.5) : .mono(9.5))
                    .foregroundStyle(warning ? Theme.warning : (value.isEmpty ? Theme.textTertiary : Theme.text))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if warning {
                    Text("introuvable")
                        .font(.label(8, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.warning.opacity(0.1)))
                }
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hover ? Theme.textSecondary : Theme.textTertiary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(hover ? Theme.fill(0.02) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct OptionToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var disabled = false
    @State private var hover = false

    var body: some View {
        Button {
            guard !disabled else { return }
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.label(10.5, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(disabled ? 0.35 : 1))
                    Text(detail)
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary.opacity(disabled ? 0.6 : 1))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                MiniSwitch(isOn: isOn, disabled: disabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hover && !disabled ? Theme.fill(0.03) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(disabled ? "Disponible avec le RomFS séparé" : detail)
    }
}

struct MiniSwitch: View {
    let isOn: Bool
    var disabled = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Theme.ember : Theme.fill(0.14))
                .frame(width: 30, height: 17)
            Circle()
                .fill(isOn ? .black.opacity(0.85) : Theme.fill(0.75))
                .frame(width: 13, height: 13)
                .padding(2)
        }
        .opacity(disabled ? 0.4 : 1)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

struct CompactToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.label(10.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                MiniSwitch(isOn: isOn)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FieldBox: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var mono = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.label(8, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(mono ? .mono(10.5) : .label(11))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.inset))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

struct IconField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.label(8, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                TextField("icône JPEG ou PNG", text: $text)
                    .textFieldStyle(.plain)
                    .font(.mono(10))
                    .foregroundStyle(Theme.text)
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.png, .jpeg]
                    if panel.runModal() == .OK, let url = panel.url { text = url.path }
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.inset))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
