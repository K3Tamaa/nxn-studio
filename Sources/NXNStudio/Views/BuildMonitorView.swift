import SwiftUI

struct BuildMonitorView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var runner: BuildRunner

    private var phase: BuildPhase { runner.phase }
    private var running: Bool { phase.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 14) {
                        statusPanel
                        pipelinePanel
                        summaryPanel
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .frame(width: 340)

                logPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                if running {
                    ProgressView().controlSize(.small).scaleEffect(0.85)
                } else {
                    Image(systemName: phaseSymbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(phaseColor)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(phase.label.uppercased())
                        .font(.label(8.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(phaseColor)
                    Text("·")
                        .foregroundStyle(Theme.textTertiary)
                    Text(state.draft.platform.title)
                        .font(.label(8.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(runner.gameName ?? state.selection?.name ?? "Build")
                    .font(.display(23, weight: .semibold))
                    .trackingHeadline(-0.5)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer()

            if !running {
                GhostButton(title: L.t("Nouvelle build"), icon: "arrow.counterclockwise") {
                    runner.reset()
                }
            }

            GhostButton(title: L.t("Commande", "Command"), icon: "terminal") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(BuildRunner.prettyCommand(runner.command), forType: .string)
            }

            if running {
                GhostButton(title: L.t("Interrompre"), icon: "stop.fill", tint: Theme.danger) {
                    runner.cancel()
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 18)
    }

    private var phaseColor: Color {
        switch phase {
        case .running: return Theme.ember
        case .succeeded: return Theme.mint
        case .failed: return Theme.danger
        case .cancelled: return Theme.warning
        case .idle: return Theme.textTertiary
        }
    }

    private var phaseSymbol: String {
        switch phase {
        case .running: return "bolt.fill"
        case .succeeded: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "stop.fill"
        case .idle: return "circle"
        }
    }

    // MARK: Status panel

    private var statusPanel: some View {
        Panel(padding: 16) {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ProgressRing(
                        progress: runner.overallFrac,
                        size: 108,
                        lineWidth: 8,
                        indeterminate: running && runner.totalN == 0,
                        caption: "global"
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text(runner.currentStage?.name ?? (running ? L.t("Démarrage…") : phase.label))
                            .font(.label(12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let step = runner.currentStage?.step, !step.isEmpty {
                            Text(step)
                                .font(.label(9.5))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(2)
                        }

                        if runner.totalN > 0 {
                            HStack(spacing: 4) {
                                Text(L.t("Étape", "Stage"))
                                    .font(.label(8.5))
                                    .foregroundStyle(Theme.textTertiary)
                                Text("\(min(runner.currentK, runner.totalN))")
                                    .font(.numeral(9.5, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("/ \(runner.totalN)")
                                    .font(.numeral(9.5))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 9) {
                                stat(label: L.t("TEMPS", "TIME"), value: Fmt.duration(elapsed(at: context.date)))
                                if let eta = runner.currentStage?.eta, running {
                                    stat(label: L.t("RESTE", "LEFT"), value: Fmt.duration(eta))
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let stage = runner.currentStage {
                    currentStageProgress(stage)
                } else if case .failed(let message) = phase {
                    Text(message)
                        .font(.label(10))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let out = runner.artifact.outPath {
                    Hairline()
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.mint)
                        Text((out as NSString).lastPathComponent)
                            .font(.mono(9.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        GhostButton(title: "Finder", icon: "folder", compact: true) {
                            state.reveal(out)
                        }
                        if (out as NSString).pathExtension.lowercased() == "app" {
                            GhostButton(title: L.t("Jouer"), icon: "play.fill", tint: Theme.mint, compact: true) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: out))
                            }
                        }
                    }
                }

                if case .failed(let message) = phase {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 1)
                        Text(message)
                            .font(.label(9.5))
                            .foregroundStyle(Theme.danger.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.08)))
                }
            }
        }
    }

    private func currentStageProgress(_ stage: BuildStage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill(0.07))
                    Capsule()
                        .fill(stage.state == .failed ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.emberGradient))
                        .frame(width: max(stage.frac == nil ? 0 : 4, geo.size.width * (stage.frac ?? (stage.state == .running ? 0 : 1))))
                }
            }
            .frame(height: 4)

            HStack {
                Text(stage.countText ?? (stage.state == .running ? "en cours…" : L.t("terminée")))
                    .font(.numeral(9, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if !stage.note.isEmpty {
                    Text(stage.note)
                        .font(.label(8.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if let frac = stage.frac {
                    Text("\(Int(frac * 100))%")
                        .font(.numeral(9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.label(7.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.numeral(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func elapsed(at date: Date) -> Double {
        guard let started = runner.startedAt else { return 0 }
        if let finished = runner.finishedAt { return finished.timeIntervalSince(started) }
        return date.timeIntervalSince(started)
    }

    // MARK: Pipeline

    private var pipelinePanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(text: L.t("Pipeline"))
                    Spacer()
                    Text("\(runner.stages.filter { $0.state == .done || $0.state == .warn }.count)/\(max(runner.totalN, runner.stages.count))")
                        .font(.numeral(9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Hairline()

                if runner.stages.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("Préparation du pipeline…"))
                            .font(.label(9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                } else {
                    VStack(spacing: 1) {
                        ForEach(runner.stages) { stage in
                            StageRow(stage: stage, isCurrent: stage.id == runner.currentK && running)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: Summary

    private var summaryPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(text: L.t("Détails"))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Hairline()

                VStack(spacing: 9) {
                    DataRow(label: L.t("Cible", "Target"), value: state.draft.platform.title)
                    DataRow(label: L.t("Source", "Source"),
                            value: state.draft.sourceURL?.lastPathComponent ?? runner.gameName ?? "—",
                            mono: true)
                    if let version = runner.artifact.version, !version.isEmpty {
                        DataRow(label: "Version", value: version, mono: true)
                    }
                    if let bundle = runner.artifact.bundleID, !bundle.isEmpty {
                        DataRow(label: "Bundle ID", value: bundle, mono: true)
                    }
                    DataRow(label: L.t("Sortie", "Output"),
                            value: runner.artifact.outPath.map { ($0 as NSString).lastPathComponent } ?? L.t("automatique", "automatic"),
                            mono: (runner.artifact.outPath != nil))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Log

    private var logPanel: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    SectionLabel(text: L.t("Journal"))
                    Text("\(runner.log.count)")
                        .font(.numeral(8.5, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.fill(0.05)))

                    Spacer()

                    if let logFile = runner.logFile {
                        IconButton(icon: "doc.text.magnifyingglass", help: L.t("Ouvrir le fichier de log")) {
                            NSWorkspace.shared.open(logFile)
                        }
                    }
                    IconButton(icon: "doc.on.doc", help: L.t("Copier le journal")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(runner.logText, forType: .string)
                    }
                    Button {
                        runner.autoScroll.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: runner.autoScroll ? "arrow.down.to.line.compact" : "pause.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("auto")
                                .font(.label(8.5, weight: .medium))
                        }
                        .foregroundStyle(runner.autoScroll ? Theme.mint : Theme.textTertiary)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fill(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L.t("Défilement automatique"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Hairline()

                if runner.log.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                        Text(L.t("Le journal apparaîtra ici."))
                            .font(.label(10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(runner.log) { line in
                                    LogRow(line: line).id(line.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.visible)
                        .onAppear { scrollToEnd(proxy) }
                        .onChange(of: runner.log.count) { _, _ in
                            if runner.autoScroll { scrollToEnd(proxy) }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.inset)
        )
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = runner.log.last else { return }
        withAnimation(.linear(duration: 0.12)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

// MARK: - Stage row

struct StageRow: View {
    let stage: BuildStage
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 19, height: 19)
                if stage.state == .running {
                    if isCurrent {
                        TinySpinner()
                    } else {
                        Circle().fill(Theme.textTertiary).frame(width: 4, height: 4)
                    }
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(foregroundColor)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.name)
                    .font(.label(10, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.text : (stage.state == .running ? Theme.textTertiary : Theme.textSecondary))
                    .lineLimit(1)
                if !stage.summary.isEmpty {
                    Text(stage.summary)
                        .font(.label(8.5))
                        .foregroundStyle(stage.state == .failed ? Theme.danger.opacity(0.85) : Theme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if stage.state != .running || stage.elapsed > 0 {
                Text(Fmt.duration(stage.elapsed))
                    .font(.numeral(8.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Theme.fill(0.035) : .clear)
        )
    }

    private var backgroundColor: Color {
        switch stage.state {
        case .done: return Theme.mint.opacity(0.14)
        case .warn: return Theme.warning.opacity(0.14)
        case .failed: return Theme.danger.opacity(0.14)
        case .running: return Theme.fill(0.05)
        }
    }

    private var foregroundColor: Color {
        switch stage.state {
        case .done: return Theme.mint
        case .warn: return Theme.warning
        case .failed: return Theme.danger
        case .running: return Theme.textTertiary
        }
    }

    private var symbol: String {
        switch stage.state {
        case .done: return "checkmark"
        case .warn: return "exclamationmark"
        case .failed: return "xmark"
        case .running: return "circle.fill"
        }
    }
}

struct TinySpinner: View {
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

// MARK: - Log row

struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if !line.time.isEmpty {
                Text(line.time)
                    .font(.mono(8.5))
                    .foregroundStyle(Theme.textTertiary.opacity(0.55))
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 1)
            } else {
                Spacer().frame(width: 50)
            }
            Text(line.text)
                .font(.mono(10))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var color: Color {
        switch line.kind {
        case .info: return Theme.textSecondary
        case .stage: return Theme.text
        case .success: return Theme.mint
        case .warning: return Theme.warning
        case .error: return Theme.danger
        case .dim: return Theme.textTertiary
        case .stderr: return Color(hex: 0xC9A0FF)
        }
    }
}

// MARK: - Bridge
