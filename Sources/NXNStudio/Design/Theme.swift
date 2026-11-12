import SwiftUI

// MARK: - Palette

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Appearance

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case midnight, oled, day
    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "Nuit"
        case .oled: return "OLED"
        case .day: return "Jour"
        }
    }

    var detail: String {
        switch self {
        case .midnight: return "Le thème d'origine"
        case .oled: return "Noir absolu, pour les dalles OLED"
        case .day: return "Surfaces claires"
        }
    }
}

enum ThemeAccent: String, CaseIterable, Codable, Identifiable {
    case ember, cyan, mint, violet, rose
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ember: return "Ember"
        case .cyan: return "Cyan"
        case .mint: return "Mint"
        case .violet: return "Violet"
        case .rose: return "Rose"
        }
    }

    var color: Color {
        switch self {
        case .ember: return Color(hex: 0xFF5F45)
        case .cyan: return Color(hex: 0x3EA6FF)
        case .mint: return Color(hex: 0x2FCB9B)
        case .violet: return Color(hex: 0x8B6CFF)
        case .rose: return Color(hex: 0xFF5C8A)
        }
    }

    var soft: Color {
        switch self {
        case .ember: return Color(hex: 0xFF8E63)
        case .cyan: return Color(hex: 0x7DC4FF)
        case .mint: return Color(hex: 0x6BE3BF)
        case .violet: return Color(hex: 0xB49BFF)
        case .rose: return Color(hex: 0xFF93B2)
        }
    }
}

enum Theme {
    /// Set by AppState before the first view is built.
    static var mode: ThemeMode = .midnight
    static var accent: ThemeAccent = .ember

    static var isLight: Bool { mode == .day }

    // Surfaces
    static var canvas: Color {
        switch mode {
        case .midnight: return Color(hex: 0x08090B)
        case .oled: return Color(hex: 0x000000)
        case .day: return Color(hex: 0xF2F3F6)
        }
    }
    static var sidebar: Color {
        switch mode {
        case .midnight: return Color(hex: 0x0B0C0F)
        case .oled: return Color(hex: 0x000000)
        case .day: return Color(hex: 0xE9EBF0)
        }
    }
    static var panel: Color {
        switch mode {
        case .midnight: return Color(hex: 0x111318)
        case .oled: return Color(hex: 0x0A0A0B)
        case .day: return Color(hex: 0xFFFFFF)
        }
    }
    static var panelAlt: Color {
        switch mode {
        case .midnight: return Color(hex: 0x171A21)
        case .oled: return Color(hex: 0x111113)
        case .day: return Color(hex: 0xF7F8FA)
        }
    }
    static var inset: Color {
        switch mode {
        case .midnight: return Color(hex: 0x0C0E12)
        case .oled: return Color(hex: 0x000000)
        case .day: return Color(hex: 0xEFF1F5)
        }
    }
    static var raised: Color {
        switch mode {
        case .midnight: return Color(hex: 0x1B1F27)
        case .oled: return Color(hex: 0x17171A)
        case .day: return Color(hex: 0xE4E7ED)
        }
    }

    // Lines
    /// Neutral surface tint: white on dark themes, black on the light one.
    static func fill(_ alpha: Double) -> Color {
        isLight ? Color.black.opacity(alpha * 0.85) : Color.white.opacity(alpha)
    }

    static var hairline: Color {
        isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.065)
    }
    static var hairlineStrong: Color {
        isLight ? Color.black.opacity(0.16) : Color.white.opacity(0.13)
    }

    // Type
    static var text: Color {
        isLight ? Color(hex: 0x15171C) : Color(hex: 0xF4F5F7)
    }
    static var textSecondary: Color {
        isLight ? Color(hex: 0x4C535E) : Color(hex: 0xA5ACB7)
    }
    static var textTertiary: Color {
        isLight ? Color(hex: 0x7C838E) : Color(hex: 0x6D7480)
    }

    // Accents
    static var ember: Color { accent.color }
    static var emberSoft: Color { accent.soft }
    static let mint       = Color(hex: 0x5FE3B4)
    static let cyan       = Color(hex: 0x64C8FF)
    static let violet     = Color(hex: 0xA78BFA)
    static let warning    = Color(hex: 0xFFC24B)
    static let danger     = Color(hex: 0xFF6B6B)

    static var emberGradient: LinearGradient {
        LinearGradient(
            colors: [accent.soft, accent.color],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static let corner: CGFloat = 14
    static let cornerSmall: CGFloat = 10
}

// MARK: - Type

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension View {
    func trackingHeadline(_ amount: CGFloat = -0.6) -> some View {
        self.tracking(amount)
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ value: Double) -> String {
        let units: [(String, Double)] = [("Go", 1_073_741_824), ("Mo", 1_048_576), ("Ko", 1024)]
        for (unit, div) in units where value >= div {
            return String(format: "%.1f %@", value / div, unit)
        }
        return "\(Int(value)) o"
    }

    static func count(_ value: Double, unit: String) -> String {
        let n = Int(value.rounded())
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
        if unit == "B" { return bytes(value) }
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d h %02d", h, m) }
        return String(format: "%d:%02d", m, sec)
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Stable cover tint

enum CoverTint {
    static let palettes: [(Color, Color)] = [
        (Color(hex: 0xFF6B4A), Color(hex: 0xFFB03A)),
        (Color(hex: 0x5B8CFF), Color(hex: 0x7DE2FF)),
        (Color(hex: 0x9B6BFF), Color(hex: 0xFF6BAE)),
        (Color(hex: 0x2FD6A8), Color(hex: 0x86F0C8)),
        (Color(hex: 0xFF4D8D), Color(hex: 0xFF8A5C)),
        (Color(hex: 0x57C7FF), Color(hex: 0x8B7BFF)),
        (Color(hex: 0xE8B84B), Color(hex: 0xFF7A45)),
        (Color(hex: 0x6EE7A8), Color(hex: 0x3FA9FF)),
    ]

    static func index(for seed: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        return Int(h % UInt64(palettes.count))
    }

    static func colors(for seed: String) -> (Color, Color) {
        palettes[index(for: seed)]
    }
}
