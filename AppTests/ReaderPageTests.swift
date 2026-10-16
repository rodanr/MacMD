import Foundation
import Testing

@testable import MacMD

/// Relative links and images in Read mode resolve against the document's folder.
struct ReaderPageTests {
    @Test func baseURLIsTheDocumentsFolder() throws {
        let folder = URL(filePath: "/Users/a/docs/guide/setup.md").deletingLastPathComponent()
        let base = ReaderPage.baseURL(for: folder)
        #expect(base.absoluteString == "macmd://file/Users/a/docs/guide/")
        #expect(URL(string: "../index.md", relativeTo: base)?.absoluteURL.path() == "/Users/a/docs/index.md")
        #expect(URL(string: "img/a.png", relativeTo: base)?.absoluteURL.path() == "/Users/a/docs/guide/img/a.png")
    }

    @Test func baseURLWorksWithAndWithoutATrailingSlash() {
        let plain = ReaderPage.baseURL(for: URL(filePath: "/Users/a/my docs", directoryHint: .notDirectory))
        let slashed = ReaderPage.baseURL(for: URL(filePath: "/Users/a/my docs/", directoryHint: .isDirectory))
        #expect(plain == slashed)
        #expect(plain.path(percentEncoded: false) == "/Users/a/my docs/")
    }
}
