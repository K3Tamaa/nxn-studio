import Foundation

/// Single source for what the About panel and the bundle display.
enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var platform: String {
        #if arch(arm64)
        return "Apple silicon · macOS 15+"
        #elseif arch(x86_64)
        return "Intel · macOS 15+"
        #else
        return "macOS 15+"
        #endif
    }
}
