import Foundation

/// The app's identity and public links, in one place for the About window, Help menu and update check.
enum AppInfo {
    static let name = "MacMD"
    static let author = "Rodan Ramdam"

    static var version: String { info("CFBundleShortVersionString") ?? "0.0.0" }
    static var build: String { info("CFBundleVersion") ?? "0" }
    static var copyright: String { info("NSHumanReadableCopyright") ?? "© \(author)" }

    static let repository = URL(string: "https://github.com/rodanr/MacMD")!
    static let help = URL(string: "https://github.com/rodanr/MacMD#readme")!
    static let issues = URL(string: "https://github.com/rodanr/MacMD/issues/new/choose")!
    static let releases = URL(string: "https://github.com/rodanr/MacMD/releases")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/rodanr/MacMD/releases/latest")!
    static let markdownGuide = URL(string: "https://www.markdownguide.org/basic-syntax/")!

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
