import AppKit
import MacMDKit

/// Compares the running version with the latest GitHub release. Runs only when the user asks, so MacMD
/// never contacts the network on its own (see TERMS.md).
@MainActor
enum UpdateChecker {
    private static var isChecking = false

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                present(try await latestRelease())
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText =
                    "Check your internet connection and try again, or visit the releases page.\n\n"
                    + error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Open Releases Page")
                if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(AppInfo.releases) }
            }
        }
    }

    /// GitHub's latest-release API. UI tests pass `-updateFeedURL file:///…json` so they never use the network;
    /// only local files are accepted, so the setting can't point the app at another server.
    private static var feedURL: URL {
        if let value = UserDefaults.standard.string(forKey: "updateFeedURL"), let url = URL(string: value),
            url.isFileURL
        {
            return url
        }
        return AppInfo.latestReleaseAPI
    }

    /// The latest published release, or `nil` when none has been published yet.
    private static func latestRelease() async throws -> Release? {
        var request = URLRequest(url: feedURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        // A local feed has no HTTP status; reading it succeeded.
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static func present(_ release: Release?) {
        let alert = NSAlert()
        if let release, let latest = AppVersion(release.tagName), let current = AppVersion(AppInfo.version),
            current < latest
        {
            alert.messageText = "\(AppInfo.name) \(latest) is available"
            alert.informativeText = "You have version \(current). Download the new version from GitHub?"
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
        } else {
            alert.messageText = "You’re up to date"
            alert.informativeText = "\(AppInfo.name) \(AppInfo.version) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
