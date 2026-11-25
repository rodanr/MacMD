import Testing

@testable import MacMDKit

struct InstallSourceTests {
    private func detect(existing: Set<String>, prefixes: [String] = InstallSource.homebrewPrefixes) -> InstallSource {
        InstallSource.detect(prefixes: prefixes) { existing.contains($0) }
    }

    @Test func homebrewOnAppleSilicon() {
        #expect(detect(existing: ["/opt/homebrew/Caskroom/macmd"]) == .homebrew)
    }

    @Test func homebrewInTheIntelPrefix() {
        #expect(detect(existing: ["/usr/local/Caskroom/macmd"]) == .homebrew)
    }

    @Test func directWhenNoCaskIsInstalled() {
        #expect(detect(existing: []) == .direct)
        #expect(detect(existing: ["/opt/homebrew/Caskroom"]) == .direct)
    }

    @Test func otherCasksDontCount() {
        #expect(detect(existing: ["/opt/homebrew/Caskroom/firefox", "/opt/homebrew/Caskroom/macmd-beta"]) == .direct)
    }

    @Test func customPrefixesWithOrWithoutTrailingSlash() {
        #expect(detect(existing: ["/tmp/brew/Caskroom/macmd"], prefixes: ["/tmp/brew/"]) == .homebrew)
        #expect(detect(existing: ["/tmp/brew/Caskroom/macmd"], prefixes: ["/tmp/brew"]) == .homebrew)
        #expect(detect(existing: ["/opt/homebrew/Caskroom/macmd"], prefixes: ["/tmp/brew"]) == .direct)
    }

    @Test func upgradeCommandNamesTheCask() {
        #expect(InstallSource.upgradeCommand == "brew upgrade macmd")
    }
}
