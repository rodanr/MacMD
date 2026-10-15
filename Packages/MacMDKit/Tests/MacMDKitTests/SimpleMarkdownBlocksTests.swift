import Testing

@testable import MacMDKit

struct SimpleMarkdownBlocksTests {
    @Test func joinsWrappedLinesAndDropsTitle() {
        let markdown = """
            # Terms

            First line
            continues here.

            ## No warranty

            - **One** item
              wraps.
            - Two
            """
        #expect(
            SimpleMarkdownBlocks.parse(markdown) == [
                .paragraph("First line continues here."),
                .heading("No warranty"),
                .bullet("**One** item wraps."),
                .bullet("Two"),
            ])
    }

    @Test func keepsWebLinksButUnlinksRelativeOnes() {
        let blocks = SimpleMarkdownBlocks.parse("See [license](LICENSE) and [issues](https://example.com/i).")
        #expect(blocks == [.paragraph("See license and [issues](https://example.com/i).")])
    }

    @Test func plainTextLicenseBecomesParagraphs() {
        let blocks = SimpleMarkdownBlocks.parse("MIT License\n\nCopyright (c) 2026 Someone\n\nPermission is\ngranted.")
        #expect(blocks.count == 3)
        #expect(blocks.last == .paragraph("Permission is granted."))
    }
}
