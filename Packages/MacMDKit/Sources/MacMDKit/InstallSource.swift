import Foundation

/// How this copy of MacMD was installed, which decides how it should be updated. A Homebrew install has to be
/// updated with `brew upgrade`: copying a newer DMG over it leaves Homebrew believing the old version is installed.
public enum InstallSource: Equatable, Sendable {
    case homebrew
    case direct

    /// Homebrew's default prefixes on Apple silicon and Intel Macs.
    public static let homebrewPrefixes = ["/opt/homebrew", "/usr/local"]
    /// The cask's name in the `rodanr/tap` tap.
    public static let caskToken = "macmd"
    public static let upgradeCommand = "brew upgrade \(caskToken)"

    /// Homebrew keeps each installed cask in `<prefix>/Caskroom/<token>`. Checking for that folder reads the local
    /// disk only, so it never touches the network.
    public static func detect(
        prefixes: [String] = homebrewPrefixes, isDirectory: (String) -> Bool
    ) -> InstallSource {
        let found = prefixes.contains { prefix in
            var root = prefix
            while root.count > 1, root.hasSuffix("/") { root.removeLast() }
            return isDirectory("\(root)/Caskroom/\(caskToken)")
        }
        return found ? .homebrew : .direct
    }
}
