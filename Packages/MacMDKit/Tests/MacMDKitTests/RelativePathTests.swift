import Foundation
import Testing

@testable import MacMDKit

@Suite struct RelativePathTests {
    @Test func siblingAndNestedPaths() {
        let base = URL(filePath: "/Users/a/notes/", directoryHint: .isDirectory)
        #expect(RelativePath.from(base, to: URL(filePath: "/Users/a/notes/img.png")) == "img.png")
        #expect(RelativePath.from(base, to: URL(filePath: "/Users/a/notes/assets/x.png")) == "assets/x.png")
        #expect(RelativePath.from(base, to: URL(filePath: "/Users/a/pics/y.png")) == "../pics/y.png")
    }

    @Test func escapesSpacesForMarkdown() {
        #expect(RelativePath.markdownEscaped("my pic.png") == "<my pic.png>")
        #expect(RelativePath.markdownEscaped("pic.png") == "pic.png")
    }
}
