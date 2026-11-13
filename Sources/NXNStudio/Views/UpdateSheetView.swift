import SwiftUI
import AppKit

/// Update sheet: manual download (DMG) and, when a signing key is configured,
/// in-place replacement.
struct UpdateSheetView: View {
    @ObservedObject var service: UpdateService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            content
            Hairline()
            footer
        }
        .frame(width: 470)
        .background(Theme.panel)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(Theme.ember.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.label(12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.label(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.fill(0.04)))
            }
            .buttonStyle(.plain)
            .help("Fermer")
        }
        .padding(16)
    }

    private var symbol: String {
        switch service.phase {
        case .upToDate: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .downloading, .installing: return "arrow.down.circle"
        default: return "sparkles"
        }
    }

    private var title: String {
        switch service.phase {
        case .checking: return L.t("Recherche de mise à jour…")
        case .upToDate: return L.t("Vous êtes à jour")
        case .available(let manifest): return "Version \(manifest.version) disponible"
        case .downloading: return L.t("Téléchargement…")
        case .installing: return "Installation…"
        case .failed: return L.t("Mise à jour impossible")
        case .idle: return L.t("Mises à jour")
        }
    }

    private var subtitle: String {
        switch service.phase {
        case .upToDate: return L.t("Version installée : \(AppVersion.marketing)", "Installed version: \(AppVersion.marketing)")
        case .available(let manifest):
            return L.t("Installée : \(AppVersion.marketing) → disponible : \(manifest.version)", "Installed: \(AppVersion.marketing) → available: \(manifest.version)")
        case .failed(let message): return message
        case .downloading(let progress):
            return progress > 0 ? L.t("Vérification de la signature…") : L.t("Récupération du paquet…")
        default: return L.t("Flux configuré par l'auteur de l'app")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .available(let manifest):
            VStack(alignment: .leading, spacing: 10) {
                if let notes = manifest.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.label(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if manifest.signature == nil || service.hasSigningKey == false {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text(L.t("Version non signée : téléchargement manuel uniquement."))
                    }
                    .font(.label(8.5))
                    .foregroundStyle(Theme.warning)
                }
                if case .downloading(let progress) = service.phase, progress > 0 {
                    progressBar(progress)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                progressBar(progress)
            }
            .padding(16)
        default:
            EmptyView()
        }
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill(0.06))
                Capsule().fill(Theme.ember)
                    .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if case .available = service.phase, let manifest = service.phase.manifest {
                Button {
                    service.downloadOnly(manifest)
                } label: {
                    Text(L.t("Télécharger le DMG"))
                        .font(.label(9.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.fill(0.05)))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await service.install(manifest) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(L.t("Installer maintenant"))
                            .font(.label(9.5, weight: .semibold))
                    }
                    .foregroundStyle(service.hasSigningKey ? .black : Theme.textTertiary)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule().fill(service.hasSigningKey ? Theme.ember : Theme.raised))
                }
                .buttonStyle(.plain)
                .disabled(service.hasSigningKey == false)
            } else if case .checking = service.phase {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text(L.t("Connexion au flux…"))
                    .font(.label(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            } else {
                Spacer()
                Button(L.t("Fermer")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(.label(9.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.fill(0.05)))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

#if DEBUG
enum UpdateSnapshot {
    @MainActor
    static func render(path: String) {
        L.language = .en
        let manifest = UpdateManifest(
            version: "1.2.0",
            build: "202612011200",
            url: URL(string: "https://example.com/NXN-Studio-1.2.0.dmg")!,
            size: 3_120_000,
            signature: "demo",
            notes: "• Mise à jour des jaquettes IGDB sans relancer l'app\n• Diagnostic : vérification relancée à chaque ouverture\n• Correctifs sur les builds interrompus",
            publishedAt: Date()
        )
        let view = UpdateSheetView(service: .demo(phase: .available(manifest)))
            .background(Theme.canvas)
            .padding(20)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }
}
#endif
