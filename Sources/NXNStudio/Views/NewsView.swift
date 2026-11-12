import SwiftUI
import AppKit

struct NewsView: View {
    @EnvironmentObject private var state: AppState

    enum Filter: String, CaseIterable, Identifiable {
        case all, open, done
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tout"
            case .open: return "Ouvertes"
            case .done: return "Terminées"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var freshCount = 0
    @State private var showFreshBanner = false

    private let repoURL = URL(string: "https://github.com/seedds/nxnative")!

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Nouveautés",
                subtitle: "Pull requests et fonctionnalités récentes de nxnative"
            ) {
                HStack(spacing: 8) {
                    syncBadge
                    if let remaining = state.news.rateRemaining {
                        rateChip(remaining)
                    }
                    GhostButton(
                        title: state.news.isLoading ? "Actualisation…" : "Actualiser",
                        icon: "arrow.clockwise",
                        compact: true
                    ) {
                        refresh(markSeen: true)
                    }
                    .disabled(state.news.isLoading)
                    GhostButton(title: "GitHub", icon: "arrow.up.right", compact: true) {
                        NSWorkspace.shared.open(repoURL)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showFreshBanner {
                        freshBanner
                    }
                    summaryPanel
                    if let error = state.news.lastError, !state.news.isEmpty {
                        errorBanner(error)
                    }
                    filterBar

                    if state.news.isEmpty {
                        emptyState
                    } else {
                        if filter != .done, !state.news.open.isEmpty {
                            feedSection(title: "En cours",
                                        subtitle: "Travail ouvert, du plus récemment modifié au plus ancien",
                                        items: state.news.open)
                        }
                        if filter != .open, !state.news.closed.isEmpty {
                            feedSection(title: "Récemment terminées",
                                        subtitle: "Pull requests fusionnées ou fermées",
                                        items: state.news.closed)
                        }
                    }

                    footer
                }
                .frame(maxWidth: state.navigationStyle == .dock ? .infinity : 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            var count = state.news.unseenCount
            await state.news.refreshIfStale()
            count = max(count, state.news.unseenCount)
            if state.news.hasSeenBefore, count > 0 {
                freshCount = count
                showFreshBanner = true
            }
            state.news.markSeen()
        }
    }

    // MARK: Header

    private var syncBadge: some View {
        HStack(spacing: 5) {
            if state.news.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text("Synchronisation…")
            } else if state.news.lastError != nil {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("hors ligne")
            } else if let date = state.news.lastSynced {
                Circle().fill(Theme.mint).frame(width: 4, height: 4)
                Text("synchronisé \(relativeSync(date))")
            } else {
                Circle().fill(Theme.textTertiary).frame(width: 4, height: 4)
                Text("jamais synchronisé")
            }
        }
        .font(.label(9))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Capsule().fill(Theme.fill(0.03)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Fresh banner

    private var freshBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.ember.opacity(0.14)).frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(freshCount) nouveauté\(freshCount > 1 ? "s" : "") depuis votre dernière visite")
                    .font(.label(11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Les pull requests concernées sont dans le flux ci-dessous.")
                    .font(.label(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.16)) { showFreshBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.fill(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.ember.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(Theme.ember.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: Summary

    private var summaryPanel: some View {
        Panel(padding: 0) {
            HStack(spacing: 0) {
                metric(value: "\(state.news.open.count)", label: "Pull requests ouvertes",
                       tint: Theme.cyan, icon: "arrow.triangle.branch")
                metricDivider
                metric(value: "\(state.news.mergedRecently)", label: "Terminées · 14 jours",
                       tint: Theme.mint, icon: "checkmark.seal")
                metricDivider
                metric(value: "\(state.news.contributors)", label: "Contributeurs dans le flux",
                       tint: Theme.violet, icon: "person.2")
                Spacer(minLength: 0)
                Text("\(state.news.items.count) PR récentes")
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 16)
            }
        }
    }

    private func metric(value: String, label: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.10)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.numeral(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(label)
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var metricDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 30)
    }

    // MARK: Filters

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { item in
                FilterChip(title: item.title, count: count(for: item), selected: filter == item) {
                    withAnimation(.easeOut(duration: 0.16)) { filter = item }
                }
            }
            Spacer()
            if !state.news.items.isEmpty {
                Text("\(visibleCount) pull request\(visibleCount == 1 ? "" : "s")")
                    .font(.label(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func count(for filter: Filter) -> Int {
        switch filter {
        case .all: return state.news.items.count
        case .open: return state.news.open.count
        case .done: return state.news.closed.count
        }
    }

    private var visibleCount: Int {
        switch filter {
        case .all: return state.news.items.count
        case .open: return state.news.open.count
        case .done: return state.news.closed.count
        }
    }

    // MARK: Feed

    private func feedSection(title: String, subtitle: String, items: [PullRequest]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionLabel(text: title)
                Text("\(items.count)")
                    .font(.numeral(9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.fill(0.05)))
                Spacer()
                Text(subtitle)
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.top, 2)

            VStack(spacing: 6) {
                ForEach(items) { pr in
                    PullRequestCard(pr: pr)
                }
            }
        }
    }

    // MARK: States

    private var emptyState: some View {
        Panel(padding: 0) {
            VStack(spacing: 10) {
                if state.news.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.9)
                    Text("Lecture de l'activité nxnative…")
                        .font(.label(11))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.ember.opacity(0.8))
                    Text("Aucune activité à afficher")
                        .font(.label(12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(state.news.lastError ?? "Actualisez pour interroger les pull requests du dépôt.")
                        .font(.label(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    GhostButton(title: "Réessayer", icon: "arrow.clockwise", compact: true) {
                        refresh(markSeen: false)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.label(9.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            GhostButton(title: "Réessayer", icon: "arrow.clockwise", compact: true) {
                refresh(markSeen: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.warning.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.16), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.system(size: 8.5, weight: .semibold))
            Text("Données publiques de l'API GitHub · rien n'est envoyé depuis votre Mac")
                .font(.label(8.5))
            Spacer()
            if let date = state.news.lastSynced {
                Text("dernière synchro \(relativeSync(date))")
                    .font(.label(8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .foregroundStyle(Theme.textTertiary.opacity(0.75))
        .padding(.top, 4)
    }

    private func rateChip(_ remaining: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(rateTint(remaining))
                .frame(width: 4.5, height: 4.5)
            Text(verbatim: "\(remaining)/\(state.news.rateLimit ?? 60)")
                .font(.numeral(8.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 2)
        .help(rateHelp(remaining))
    }

    private func rateTint(_ remaining: Int) -> Color {
        if remaining <= 4 { return Theme.danger }
        if remaining <= 15 { return Theme.warning }
        return Theme.mint
    }

    private func rateHelp(_ remaining: Int) -> String {
        var text = "\(remaining) requête\(remaining == 1 ? "" : "s") GitHub restante\(remaining == 1 ? "" : "s")"
        if let reset = state.news.rateReset {
            text += " · réinitialisation à \(Fmt.clock(reset))"
        }
        return text
    }

    private func refresh(markSeen: Bool) {
        Task {
            await state.news.refresh()
            if markSeen { state.news.markSeen() }
        }
    }

    private func relativeSync(_ date: Date) -> String {
        Date().timeIntervalSince(date) < 45 ? "à l'instant" : Fmt.relative(date)
    }
}

// MARK: - Pull request card

struct PullRequestCard: View {
    let pr: PullRequest

    @State private var hover = false

    private var tint: Color {
        if pr.isMerged { return Theme.mint }
        if pr.isOpen { return pr.draft == true ? Theme.textTertiary : Theme.cyan }
        return Theme.danger.opacity(0.8)
    }

    private var symbol: String {
        if pr.isMerged { return "arrow.triangle.merge" }
        if pr.isOpen { return pr.draft == true ? "pencil" : "arrow.triangle.branch" }
        return "xmark"
    }

    var body: some View {
        Link(destination: pr.htmlURL) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle().fill(tint.opacity(0.10)).frame(width: 27, height: 27)
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(verbatim: "#\(pr.number)")
                            .font(.mono(9, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Text(pr.stateLabel)
                            .font(.label(7.5, weight: .bold))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.10)))
                        if pr.isOpen, pr.draft == true {
                            Text("brouillon")
                                .font(.label(7.5, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.relative(pr.activityDate))
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Text(pr.title)
                        .font(.label(12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !pr.excerpt.isEmpty {
                        Text(pr.excerpt)
                            .font(.label(9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 5) {
                        AuthorDot(login: pr.user.login)
                        Text(pr.user.login)
                            .font(.label(8.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("· mise à jour \(Fmt.relative(pr.updatedAt))")
                            .font(.label(8.5))
                            .foregroundStyle(Theme.textTertiary.opacity(0.8))
                        if !pr.labels.isEmpty {
                            ForEach(pr.labels.prefix(3)) { label in
                                LabelChip(label: label)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(hover ? Theme.textSecondary : Theme.textTertiary.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(hover ? Theme.fill(0.045) : Theme.panelAlt.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .strokeBorder(hover ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

// MARK: - Small pieces

struct AuthorDot: View {
    let login: String

    var body: some View {
        Text(String(login.prefix(1)).uppercased())
            .font(.numeral(7.5, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .frame(width: 15, height: 15)
            .background(Circle().fill(tint))
    }

    private var tint: Color {
        let colors = [Theme.cyan, Theme.violet, Theme.mint, Theme.emberSoft, Theme.warning]
        var hash = 0
        for scalar in login.unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) & 0xFFFF }
        return colors[hash % colors.count]
    }
}

struct LabelChip: View {
    let label: PullRequest.Label

    var body: some View {
        Text(label.name)
            .font(.label(7.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.11)))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }

    private var color: Color {
        guard let hex = UInt32(label.color, radix: 16) else { return Theme.textSecondary }
        return Color(hex: hex)
    }
}
