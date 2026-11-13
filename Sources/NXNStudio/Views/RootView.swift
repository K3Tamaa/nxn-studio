import SwiftUI

// MARK: - Window root

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                if state.navigationStyle == .sidebar {
                    Sidebar()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ZStack {
                    Theme.canvas
                    AmbientBackdrop()

                    Group {
                        switch state.route {
                        case .library: LibraryView()
                        case .launcher: LauncherView()
                        case .build: BuildView()
                        case .news: NewsView()
                        case .settings: SettingsView()
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .frame(maxWidth: state.navigationStyle == .dock ? 1160 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            if state.navigationStyle == .dock {
                DockBar()
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(Theme.canvas)
        .navigationTitle("NXN Studio")
        .preferredColorScheme(state.themeMode == .day ? .light : .dark)
        .animation(.easeOut(duration: 0.18), value: state.route)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: state.navigationStyle)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: Binding(
            get: { state.updates.showSheet },
            set: { state.updates.showSheet = $0 }
        )) {
            UpdateSheetView(service: state.updates)
        }
        .task {
            async let news: Void = state.news.refreshIfStale()
            if state.repo.isValid {
                await state.repoUpdate.checkOnce(repo: state.repo.url)
            }
            await news
        }
    }
}

// MARK: - Floating dock

/// Icon bar shown instead of the sidebar: one floating capsule, a sliding
/// active pill, and hover feedback that only touches transform/opacity.
struct DockBar: View {
    @EnvironmentObject private var state: AppState
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Route.allCases) { route in
                DockItem(
                    route: route,
                    selected: state.route == route,
                    badgeCount: route == .news ? state.news.unseenCount : 0,
                    dotColor: route == .settings && state.repoUpdate.behindCount > 0 ? Theme.warning : nil,
                    indicator: indicator
                ) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
                        state.route = route
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.panel.opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

struct DockItem: View {
    @EnvironmentObject private var state: AppState
    let route: Route
    let selected: Bool
    var badgeCount: Int = 0
    var dotColor: Color? = nil
    var indicator: Namespace.ID
    let action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    Circle()
                        .fill(Theme.ember.opacity(Theme.isLight ? 0.16 : 0.14))
                        .frame(width: 42, height: 42)
                        .matchedGeometryEffect(id: "dock.pill", in: indicator)
                }

                Image(systemName: route.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? Theme.ember : (hover ? Theme.text : Theme.textSecondary))
                    .scaleEffect(hover && !reduceMotion ? 1.08 : 1)
                    .offset(y: hover && !reduceMotion ? -1 : 0)

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.numeral(7, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 3.5)
                        .frame(height: 12)
                        .background(Capsule().fill(Theme.ember))
                        .offset(x: 13, y: 12)
                }
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                        .offset(x: 13, y: 11)
                }
            }
            .frame(width: 46, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hover = value }
        }
        .help(route.title)
        .accessibilityLabel(route.title)
    }
}

// MARK: - Ambient light

struct AmbientBackdrop: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.ember.opacity(0.075), .clear],
                center: UnitPoint(x: 0.82, y: -0.12),
                startRadius: 10, endRadius: 720
            )
            RadialGradient(
                colors: [Theme.cyan.opacity(0.035), .clear],
                center: UnitPoint(x: 0.05, y: 1.05),
                startRadius: 10, endRadius: 620
            )
            LinearGradient(
                colors: [Theme.fill(0.012), .clear, .black.opacity(0.14)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var state: AppState
    @Namespace private var navIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 27)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NXN")
                        .font(.display(13, weight: .bold))
                        .tracking(2.2)
                        .foregroundStyle(Theme.text)
                    Text("STUDIO")
                        .font(.label(7.5, weight: .semibold))
                        .tracking(2.6)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 46)
            .padding(.horizontal, 18)

            Spacer().frame(height: 34)

            Text(L.t("ESPACE DE TRAVAIL"))
                .font(.label(8.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.bottom, 9)

            VStack(spacing: 3) {
                ForEach(Route.allCases) { route in
                    NavItem(
                        route: route,
                        selected: state.route == route,
                        badgeCount: route == .news ? state.news.unseenCount : nil,
                        dotColor: route == .settings && state.repoUpdate.behindCount > 0 ? Theme.warning : nil,
                        indicator: navIndicator
                    ) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            state.route = route
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 18)

            if state.runner.phase.isRunning {
                BuildPulse()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            RepoFooter()
                .padding(.horizontal, 12)

            Text(L.t("Client non officiel", "Unofficial client") + " · v\(AppVersion.marketing)")
                .font(.label(8.5))
                .foregroundStyle(Theme.textTertiary.opacity(0.55))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(width: 226)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                Theme.sidebar
                LinearGradient(colors: [Theme.fill(0.016), .clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }
}

struct NavItem: View {
    let route: Route
    let selected: Bool
    var badgeCount: Int? = nil
    var dotColor: Color? = nil
    var indicator: Namespace.ID
    let action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: route.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Theme.ember : (hover ? Theme.text : Theme.textTertiary))
                Text(route.title)
                    .font(.label(12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : (hover ? Theme.text : Theme.textSecondary))
                Spacer(minLength: 0)
                if let badgeCount, badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .font(.numeral(8, weight: .bold))
                        .foregroundStyle(.black.opacity(0.86))
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Capsule().fill(Theme.ember))
                        .shadow(color: Theme.ember.opacity(0.35), radius: 4)
                }
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                        .shadow(color: dotColor.opacity(0.6), radius: 3)
                } else if selected {
                    Circle().fill(Theme.ember).frame(width: 4, height: 4)
                        .shadow(color: Theme.ember.opacity(0.7), radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.ember.opacity(Theme.isLight ? 0.13 : 0.10))
                        .matchedGeometryEffect(id: "nav.pill", in: indicator)
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.fill(Theme.isLight ? 0.05 : 0.035))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Theme.hairlineStrong : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

struct BuildPulse: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            state.route = .build
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    StatusDot(color: Theme.ember, size: 6, pulsing: true)
                    Text(L.t("BUILD EN COURS", "BUILD RUNNING"))
                        .font(.label(8, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.emberSoft)
                    Spacer(minLength: 0)
                    Text("\(Int(state.runner.overallFrac * 100))%")
                        .font(.numeral(10, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill(0.08))
                        Capsule()
                            .fill(Theme.emberGradient)
                            .frame(width: max(4, geo.size.width * state.runner.overallFrac))
                    }
                }
                .frame(height: 3)
                Text(state.runner.currentStage?.name ?? L.t("Démarrage…"))
                    .font(.label(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.ember.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.ember.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RepoFooter: View {
    @EnvironmentObject private var state: AppState
    @State private var hover = false

    var body: some View {
        Button {
            state.route = .settings
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.fill(0.05))
                        .frame(width: 24, height: 24)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state.repo.isValid ? Theme.mint : Theme.warning)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("nxnative")
                        .font(.label(10.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(state.repo.isValid ? L.t("\(state.repo.gamesCount) profils · connecté", "\(state.repo.gamesCount) profiles · connected") : L.t("non configuré"))
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(state.repo.isValid ? Theme.mint : Theme.warning)
                    .frame(width: 5, height: 5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.fill(hover ? 0.05 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(state.repo.url?.path ?? L.t("Configurer le checkout nxnative"))
    }
}

// MARK: - Page scaffold

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.display(30, weight: .semibold))
                    .trackingHeadline()
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.label(11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 30)
        .padding(.top, 42)
        .padding(.bottom, 20)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Rechercher"

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(focused ? Theme.textSecondary : Theme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.label(11.5))
                .foregroundStyle(Theme.text)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? Theme.ember.opacity(0.5) : Theme.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
