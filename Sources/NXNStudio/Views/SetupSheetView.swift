import SwiftUI

/// Progress sheet for the first-run helpers (Homebrew, nxnative clone).
struct SetupSheetView: View {
    @ObservedObject var setup: SetupService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            console
            Hairline()
            footer
        }
        .frame(width: 520)
        .background(Theme.panel)
    }

    private var title: String {
        switch setup.task {
        case .homebrew: return "Installation de Homebrew"
        case .clone: return "Clone de nxnative"
        case .idle: return setup.hasHomebrew ? "Environnement" : "Installation"
        }
    }

    private var subtitle: String {
        if setup.isRunning {
            return setup.task == .homebrew
                ? L.t("Le script officiel tourne ; macOS demande votre mot de passe.")
                : L.t("Récupération du dépôt nxnative…")
        }
        if let error = setup.lastError { return error }
        return L.t("Les opérations restent sur votre Mac.")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill((setup.lastError == nil ? Theme.mint : Theme.warning).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: setup.lastError == nil ? "shippingbox" : "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(setup.lastError == nil ? Theme.mint : Theme.warning)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.label(12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.label(9))
                    .foregroundStyle(setup.lastError == nil ? Theme.textTertiary : Theme.warning.opacity(0.9))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if setup.isRunning {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            }
        }
        .padding(16)
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(setup.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.mono(8.5))
                            .foregroundStyle(color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(10)
            }
            .frame(height: 200)
            .background(Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onChange(of: setup.log.count) {
                guard !setup.log.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(setup.log.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("✓") { return Theme.mint }
        if line.hasPrefix("✕") { return Theme.danger }
        if line.hasPrefix("$") { return Theme.emberSoft }
        return Theme.textTertiary
    }

    private var footer: some View {
        HStack {
            Text(setup.hasHomebrew ? "Homebrew : \(setup.homebrewPath ?? "")" : "Homebrew absent")
                .font(.label(8.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                setup.close()
                dismiss()
            } label: {
                Text(L.t("Fermer"))
                    .font(.label(9.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.fill(0.06)))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(setup.isRunning)
            .opacity(setup.isRunning ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
