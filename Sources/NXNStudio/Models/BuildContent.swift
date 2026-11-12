import Foundation

// MARK: - Build content

/// One package file that can go into a build: the base game, an update, a DLC
/// pack, or any other .nsp dropped beside it.
struct BuildPackage: Identifiable, Hashable {
    enum Kind: String {
        case base, update, dlc, other

        var label: String {
            switch self {
            case .base: return "Base"
            case .update: return "Mise à jour"
            case .dlc: return "DLC"
            case .other: return "Autre"
            }
        }

        var icon: String {
            switch self {
            case .base: return "shippingbox.fill"
            case .update: return "arrow.up.circle.fill"
            case .dlc: return "puzzlepiece.extension.fill"
            case .other: return "square.stack.3d.up.fill"
            }
        }
    }

    var id: String { path }
    var path: String
    var name: String
    var kind: Kind
    var versionToken: String?
    var size: Int64

    var versionLabel: String { versionToken ?? "v?" }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum BuildContent {
    /// Packages sitting beside the selected file, classified from their name.
    static func packages(beside source: URL, baseID: String?) -> [BuildPackage] {
        let folder = source.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let base = baseID?.uppercased()
        let selectedName = source.lastPathComponent
        let selectedID = titleID(in: selectedName) ?? base

        var result: [BuildPackage] = files
            .filter { ["nsp", "nsz", "xci", "xcz"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let name = url.lastPathComponent
                let id = titleID(in: name)
                let version = versionToken(in: name)
                let kind = classify(id: id, version: version, base: selectedID)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                return BuildPackage(path: url.path, name: name, kind: kind,
                                    versionToken: version, size: size)
            }

        // The file the user picked is always the base of the list.
        if let index = result.firstIndex(where: { $0.name == selectedName }) {
            result[index].kind = .base
        } else {
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            result.append(BuildPackage(path: source.path, name: selectedName, kind: .base,
                                       versionToken: versionToken(in: selectedName), size: size))
        }

        let order: [BuildPackage.Kind: Int] = [.base: 0, .update: 1, .dlc: 2, .other: 3]
        return result.sorted {
            order[$0.kind, default: 9] == order[$1.kind, default: 9]
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : order[$0.kind, default: 9] < order[$1.kind, default: 9]
        }
    }

    static func titleID(in name: String) -> String? {
        guard let range = name.range(of: "\\[[0-9A-Fa-f]{16}\\]", options: .regularExpression) else { return nil }
        return String(name[range].dropFirst().dropLast()).uppercased()
    }

    static func versionToken(in name: String) -> String? {
        guard let range = name.range(of: "\\[v[0-9]+\\]", options: .regularExpression) else { return nil }
        return String(name[range].dropFirst().dropLast())
    }

    private static func classify(id: String?, version: String?, base: String?) -> BuildPackage.Kind {
        guard let version else { return .other }
        let number = Int(version.dropFirst()) ?? 0
        guard let id, let base else { return number == 0 ? .base : .update }

        if id == base {
            return number == 0 ? .base : .update
        }
        // DLC packs share the first 12 hex digits of the base title ID.
        if id.hasPrefix(String(base.prefix(12))) { return .dlc }
        return .other
    }
}
