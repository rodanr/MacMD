import Testing

@testable import MacMDKit

@Suite struct OutlineTests {
    @Test func collectsHeadingsWithLevelsLinesAndSlugs() {
        let outline = Outline.items(for: "# Intro\ntext\n## Getting *Started*\n## Intro\n")
        #expect(outline.map(\.title) == ["Intro", "Getting Started", "Intro"])
        #expect(outline.map(\.level) == [1, 2, 2])
        #expect(outline.map(\.line) == [1, 3, 4])
        #expect(outline.map(\.slug) == ["intro", "getting-started", "intro-1"])
    }

    @Test func setextHeadingsAreIncluded() {
        let outline = Outline.items(for: "Title\n=====\n")
        #expect(outline.map(\.title) == ["Title"])
    }

    @Test func slugRules() {
        var slugger = Slugger()
        #expect(slugger.slug("Hello, World!") == "hello-world")
        #expect(slugger.slug("Café & Crème") == "café--crème")
        #expect(slugger.slug("Hello, World!") == "hello-world-1")
        #expect(slugger.slug("") == "section")
    }
}
