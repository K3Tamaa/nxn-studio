import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var copied = false

    private let cloneCommand = "git clone https://github.com/seedds/nxnative.git ~/nxnative"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Spacer(minLength: 40)

                HStack(alignment: .top, spacing: 18) {
                    BrandMark(size: 58)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reliez votre studio.")
                            .font(.display(32, weight: .semibold))
                            .trackingHeadline(-1)
                            .foregroundStyle(Theme.text)
                        Text(L.t("NXN Studio pilote nxnative : il transforme vos jeux en app Mac ou en IPA, suit chaque étape et garde vos réglages.", "NXN Studio drives nxnative: it turns your games into a Mac app or an IPA, follows every step and keeps your settings."))
                            .font(.label(12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !state.repo.message.isEmpty, !state.repoPath.isEmpty, !state.repo.isValid {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.warning)
                        Text(state.repo.message)
                            .font(.label(10.5))
                            .foregroundStyle(Theme.warning)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.warning.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.warning.opacity(0.2), lineWidth: 1))
                }

                VStack(spacing: 0) {
                    StepRow(number: 1,
                            title: L.t("Le checkout nxnative"),
                            detail: L.t("Le dossier cloné, avec scripts/ et dm/games."),
                            done: state.repo.isValid)
                    Hairline().padding(.leading, 42)
                    StepRow(number: 2,
                            title: L.t("Vos clés Switch"),
                            detail: L.t("prod.keys, seulement pour les NSP — inutile pour les .nup et les dumps."),
                            done: !state.keysPath.isEmpty && FileManager.default.fileExists(atPath: state.keysPath))
                    Hairline().padding(.leading, 42)
                    StepRow(number: 3,
                            title: L.t("Un jeu à packager"),
                            detail: L.t("Un dossier de NSP, un dump ou un fichier .nup."),
                            done: false)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

                HStack(spacing: 10) {
                    PrimaryButton(title: L.t("Choisir le dossier nxnative"), icon: "folder.badge.plus") {
                        state.chooseRepo()
                    }
                    GhostButton(title: "Choisir prod.keys", icon: "key") {
                        state.chooseKeys()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("PAS ENCORE CLONÉ ?"))
                        .font(.label(8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)

                    HStack(spacing: 10) {
                        Text(cloneCommand)
                            .font(.mono(10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cloneCommand, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(copied ? Theme.mint : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.inset))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))

                    Text(L.t("Puis installez les outils : brew install xcodegen zstd glslang, Python 3.12, Xcode 27.2."))
                        .font(.label(10))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }

                HStack(spacing: 14) {
                    Requirement(icon: "applelogo", label: "Apple silicon")
                    Requirement(icon: "desktopcomputer", label: "macOS 26.6+")
                    Requirement(icon: "hammer", label: "Xcode 27.2")
                    Requirement(icon: "chevron.left.forwardslash.chevron.right", label: "Python 3.12+")
                }
                .padding(.top, 2)

                Spacer(minLength: 30)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    state.repoPath = url.path
                    state.refreshRepo()
                }
            }
            return true
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Theme.mint.opacity(0.14) : Theme.fill(0.04))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.mint)
                } else {
                    Text("\(number)")
                        .font(.numeral(10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.label(11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.label(10))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct Requirement: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(label)
                .font(.label(9.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
