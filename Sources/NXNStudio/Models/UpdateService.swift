import Foundation
import CryptoKit
import AppKit

// MARK: - Manifest

struct UpdateManifest: Codable, Identifiable, Equatable {
    var version: String
    var build: String?
    var url: URL
    var size: Int?
    var sha256: String?
    var signature: String?
    var notes: String?
    var publishedAt: Date?

    var id: String { "\(version)-\(build ?? "")" }

    var isNewer: Bool { UpdateService.compare(version, AppVersion.marketing) > 0 }
}

// MARK: - Service

@MainActor
final class UpdateService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case downloading(Double)
        case installing
        case failed(String)

        var manifest: UpdateManifest? {
            if case .available(let manifest) = self { return manifest }
            return nil
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var showSheet = false

    private let feedURL: URL?
    private let publicKey: String?

    init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "NXNUpdateFeed") as? String ?? ""
        feedURL = feed.isEmpty ? nil : URL(string: feed)
        let key = Bundle.main.object(forInfoDictionaryKey: "NXNUpdatePublicKey") as? String ?? ""
        publicKey = key.isEmpty ? nil : key
    }

    var isConfigured: Bool { feedURL != nil }
    var hasSigningKey: Bool { publicKey != nil }

    // MARK: Check

    func check() async {
        guard let feedURL else {
            phase = .failed("Aucun flux de mise à jour configuré. Renseignez NXNUpdateFeed au packaging.")
            showSheet = true
            return
        }
        phase = .checking
        showSheet = true

        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            request.setValue("NXNStudio/1.0", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.message("Le flux de mise à jour est injoignable.")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(UpdateManifest.self, from: data)

            if manifest.isNewer {
                phase = .available(manifest)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed((error as? UpdateError)?.text ?? error.localizedDescription)
        }
    }

    // MARK: Download / install

    func downloadOnly(_ manifest: UpdateManifest) {
        NSWorkspace.shared.open(manifest.url)
        showSheet = false
    }

    func install(_ manifest: UpdateManifest) async {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            phase = .failed("Lancez l'app installée pour une mise à jour sur place.")
            return
        }
        let target = Bundle.main.bundlePath
        guard target.hasPrefix("/Applications/") || target.hasPrefix(NSHomeDirectory() + "/Applications/") else {
            phase = .failed("L'app doit se trouver dans Applications pour se remplacer elle-même.")
            return
        }

        phase = .downloading(0)

        do {
            let file = try await download(manifest)
            guard let publicKey else {
                throw UpdateError.message("Signature de mise à jour non configurée : téléchargez le DMG manuellement.")
            }
            guard let signature = manifest.signature else {
                throw UpdateError.message("Cette version n'est pas signée : téléchargez le DMG manuellement.")
            }
            guard UpdateCrypto.verify(file: file, signature: signature, publicKey: publicKey) else {
                throw UpdateError.message("La signature de la mise à jour est invalide. Installation annulée.")
            }
            if let expected = manifest.sha256, !expected.isEmpty {
                let actual = UpdateCrypto.sha256(file: file)
                guard actual == expected.lowercased() else {
                    throw UpdateError.message("L'empreinte du fichier ne correspond pas. Installation annulée.")
                }
            }

            phase = .installing
            let staged = try stageApp(from: file)
            try relaunchReplacing(target: target, with: staged)
        } catch {
            phase = .failed((error as? UpdateError)?.text ?? error.localizedDescription)
        }
    }

    private func download(_ manifest: UpdateManifest) async throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NXN Studio/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(manifest.url.lastPathComponent)

        // Cache-busting query derived from the checksum: GitHub's CDN can serve
        // the previous asset for a few minutes right after a release.
        var components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        if let sha = manifest.sha256, !sha.isEmpty {
            components?.queryItems = [URLQueryItem(name: "nx", value: String(sha.prefix(12)))]
        }
        let target = components?.url ?? manifest.url
        let (temp, response) = try await URLSession.shared.download(from: target)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.message("Téléchargement impossible.")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)

        if let size = manifest.size {
            let actual = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            guard actual == size else {
                throw UpdateError.message("Taille inattendue (\(actual) octets au lieu de \(size)).")
            }
        }
        phase = .downloading(1)
        return destination
    }

    private func stageApp(from dmg: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("NXNUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        let attach = ShellRunner.runSync(["hdiutil", "attach", "-nobrowse", "-readonly",
                                          "-mountpoint", mount.path, dmg.path])
        guard attach.code == 0 else {
            throw UpdateError.message("Le DMG n'a pas pu être monté.")
        }
        defer { _ = ShellRunner.runSync(["hdiutil", "detach", mount.path, "-quiet"]) }

        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.message("Aucune application dans le DMG.")
        }

        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXNStudio-\(UUID().uuidString).app")
        guard ShellRunner.runSync(["ditto", app.path, staged.path]).code == 0 else {
            throw UpdateError.message("Copie de la nouvelle version impossible.")
        }
        return staged
    }

    private func relaunchReplacing(target: String, with staged: URL) throws {
        let script = """
        sleep 1
        rm -rf "\(target)"
        ditto "\(staged.path)" "\(target)"
        xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        open "\(target)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        NSApp.terminate(nil)
    }

    #if DEBUG
    static func demo(phase: Phase) -> UpdateService {
        let service = UpdateService()
        service.phase = phase
        return service
    }
    #endif

    // MARK: Compare

    nonisolated static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = lhs.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

// MARK: - Crypto

enum UpdateCrypto {
    static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(),
                key.publicKey.rawRepresentation.base64EncodedString())
    }

    static func sign(file: URL, privateKey: String) -> String? {
        guard let data = try? Data(contentsOf: file),
              let raw = Data(base64Encoded: privateKey),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
              let signature = try? key.signature(for: data) else { return nil }
        return signature.base64EncodedString()
    }

    static func sha256(file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(file: URL, signature: String, publicKey: String) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let signatureData = Data(base64Encoded: signature),
              let rawKey = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else { return false }
        return key.isValidSignature(signatureData, for: data)
    }
}

// MARK: - Errors

enum UpdateError: Error {
    case message(String)
    var text: String {
        switch self {
        case .message(let text): return text
        }
    }
}

#if DEBUG
/// Headless end-to-end probe: fetch a manifest, download the package and check
/// its Ed25519 signature without touching the installed app.
enum UpdateProbe {
    @MainActor
    static func run(feed: String, publicKey: String?) {
        Task {
            do {
                var request = URLRequest(url: URL(string: feed)!)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(UpdateManifest.self, from: data)
                print("MANIFEST version=\(manifest.version) size=\(manifest.size ?? -1) newer=\(manifest.isNewer)")

                var components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
                if let sha = manifest.sha256, !sha.isEmpty {
                    components?.queryItems = [URLQueryItem(name: "nx", value: String(sha.prefix(12)))]
                }
                let target = components?.url ?? manifest.url
                let (temp, _) = try await URLSession.shared.download(from: target)
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(manifest.url.lastPathComponent)
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.copyItem(at: temp, to: file)
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                print("DOWNLOAD bytes=\(size) expected=\(manifest.size ?? -1)")

                if let key = publicKey ?? (Bundle.main.object(forInfoDictionaryKey: "NXNUpdatePublicKey") as? String),
                   let signature = manifest.signature {
                    let ok = UpdateCrypto.verify(file: file, signature: signature, publicKey: key)
                    print("SIGNATURE \(ok ? "OK" : "INVALID")")
                    exit(ok && size == (manifest.size ?? size) ? 0 : 1)
                }
                print("SIGNATURE none")
                exit(0)
            } catch {
                print("PROBE failed: \(error)")
                exit(2)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(3) }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}
#endif
