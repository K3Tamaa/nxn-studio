import SwiftUI
import AppKit

@main
enum NXNStudioMain {
    static func main() {
        let arguments = CommandLine.arguments

        if let iconIndex = arguments.firstIndex(of: "--make-icon"), arguments.count > iconIndex + 1 {
            IconExporter.export(to: arguments[iconIndex + 1])
            return
        }

        if arguments.contains("--gen-update-key") {
            let pair = UpdateCrypto.generateKeyPair()
            print("private=\(pair.privateKey)")
            print("public=\(pair.publicKey)")
            return
        }

        if let signIndex = arguments.firstIndex(of: "--sign-update"),
           arguments.count > signIndex + 2 {
            let file = URL(fileURLWithPath: arguments[signIndex + 1])
            guard let signature = UpdateCrypto.sign(file: file, privateKey: arguments[signIndex + 2]) else {
                FileHandle.standardError.write(Data("sign failed\n".utf8))
                exit(1)
            }
            print(signature)
            return
        }

        #if DEBUG
        if let probeIndex = arguments.firstIndex(of: "--test-update"),
           arguments.count > probeIndex + 1 {
            let key = arguments.count > probeIndex + 2 ? arguments[probeIndex + 2] : nil
            UpdateProbe.run(feed: arguments[probeIndex + 1], publicKey: key)
            return
        }

        if let updateIndex = arguments.firstIndex(of: "--screenshot-update"),
           arguments.count > updateIndex + 1 {
            UpdateSnapshot.render(path: arguments[updateIndex + 1])
            return
        }

        if let changelogIndex = arguments.firstIndex(of: "--screenshot-changelog"),
           arguments.count > changelogIndex + 1 {
            ChangelogSnapshot.render(
                path: arguments[changelogIndex + 1],
                recent: arguments.contains("--recent")
            )
            return
        }

        if let probeIndex = arguments.firstIndex(of: "--changelog"), arguments.count > probeIndex + 1 {
            ChangelogProbe.run(repo: arguments[probeIndex + 1])
            return
        }
        #endif

        if let testIndex = arguments.firstIndex(of: "--selftest"), arguments.count > testIndex + 1 {
            BuildSelfTest.run(repo: arguments[testIndex + 1])
            return
        }

        if let updateIndex = arguments.firstIndex(of: "--selftest-update"), arguments.count > updateIndex + 1 {
            RepoSelfTest.run(repo: arguments[updateIndex + 1])
            return
        }

        if arguments.contains("--selftest-install") {
            InstallerSelfTest.run()
            return
        }

        if let shotIndex = arguments.firstIndex(of: "--screenshot"), arguments.count > shotIndex + 1 {
            let path = arguments[shotIndex + 1]
            let route = value(of: "--route", in: arguments).flatMap(Route.init(rawValue:)) ?? .library
            let repo = value(of: "--repo", in: arguments) ?? ""
            Snapshotter.run(path: path, route: route, repo: repo)
            return
        }

        NXNStudioApp.main()
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}

struct NXNStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .id(state.appearanceRevision)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Vérifier les mises à jour…") {
                    Task { await state.updates.check() }
                }
                Button("Vérifier l'environnement") {
                    state.route = .settings
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu("Aller") {
                Button("Bibliothèque") { state.route = .library }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Construire") { state.route = .build }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Nouveautés") { state.route = .news }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Réglages") { state.route = .settings }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("Actualiser les profils") { state.refreshRepo() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Programmatic app icon

enum IconExporter {
    @MainActor
    static func export(to path: String) {
        let view = AppIconView().frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("icon render failed\n".utf8))
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

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 232, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(hex: 0x191C23), Color(hex: 0x0A0B0E)],
                                   startPoint: .top, endPoint: .bottom)
                )

            // Ember halo behind the mark.
            RadialGradient(colors: [Theme.ember.opacity(0.34), .clear],
                           center: UnitPoint(x: 0.5, y: 0.44),
                           startRadius: 30, endRadius: 430)
                .blendMode(.screen)

            RadialGradient(colors: [Theme.violet.opacity(0.10), .clear],
                           center: UnitPoint(x: 0.18, y: 0.86),
                           startRadius: 10, endRadius: 380)

            // Fine concentric rings.
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.03), lineWidth: 2)
                    .frame(width: 540 + CGFloat(i) * 92, height: 540 + CGFloat(i) * 92)
            }

            // Top glass highlight.
            LinearGradient(colors: [.white.opacity(0.05), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.34))

            BrandMark(size: 440)
                .shadow(color: Theme.ember.opacity(0.45), radius: 80, y: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 232, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 232, style: .continuous)
                .strokeBorder(.white.opacity(0.085), lineWidth: 3)
        )
        .padding(48)
        .background(Color.clear)
    }
}

// MARK: - Snapshot mode (design verification)

enum Snapshotter {
    @MainActor
    static func run(path: String, route: Route, repo: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)

        let state = AppState()
        state.autoCheckUpdates = false
        if CommandLine.arguments.contains("--blank") {
            state.repoPath = ""
        } else if !repo.isEmpty {
            state.repoPath = repo
        }
        state.refreshRepo()
        if route == .build, let game = state.games.first(where: { $0.name.contains("Mario") }) ?? state.games.first {
            state.selection = game
            state.draft.sourcePath = value(of: "--source", in: CommandLine.arguments)
                ?? repo + "/fixtures/\(game.id)"
            state.draft.keysPath = value(of: "--keys", in: CommandLine.arguments) ?? state.keysPath
            state.draft.platform = .macApp
        }
        state.route = route

        #if DEBUG
        if CommandLine.arguments.contains("--demo-monitor") {
            state.runner.loadDemo()
        }
        if CommandLine.arguments.contains("--demo-news") {
            state.news.loadDemo()
        }
        if CommandLine.arguments.contains("--demo-update") {
            state.repoUpdate.loadDemo(behind: value(of: "--demo-behind", in: CommandLine.arguments).flatMap(Int.init) ?? 0)
        }
        if CommandLine.arguments.contains("--demo-changelog") {
            state.repoUpdate.loadChangelogDemo()
        }
        #endif

        let width = value(of: "--width", in: CommandLine.arguments).flatMap(Double.init) ?? 1280
        let height = value(of: "--height", in: CommandLine.arguments).flatMap(Double.init) ?? 820

        let content = RootView()
            .environmentObject(state)
            .frame(width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovable = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        window.center()
        app.activate(ignoringOtherApps: true)

        let delay: TimeInterval = value(of: "--delay", in: CommandLine.arguments).flatMap(Double.init)
            ?? (route == .news ? 3.0 : 2.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            try? png.write(to: URL(fileURLWithPath: path))
            print("screenshot: \(path)")
            exit(0)
        }

        app.run()
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
