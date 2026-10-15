import Testing

@testable import MacMDKit

@Suite struct ListContinuationTests {
    @Test(arguments: [
        ("- item", ListContinuation.continue(prefix: "- ")),
        ("  * nested", .continue(prefix: "  * ")),
        ("1. first", .continue(prefix: "2. ")),
        ("9) x", .continue(prefix: "10) ")),
        ("- [x] done", .continue(prefix: "- [ ] ")),
        ("> quote", .continue(prefix: "> ")),
        ("> - both", .continue(prefix: "> - ")),
        ("- ", .terminate(markerLength: 2)),
        ("- [ ] ", .terminate(markerLength: 6)),
        ("3. ", .terminate(markerLength: 3)),
        ("plain text", .notAList),
        ("", .notAList),
    ])
    func continuation(line: String, expected: ListContinuation) {
        #expect(ListContinuation.forLine(line) == expected)
    }

    @Test func indentAndOutdent() {
        #expect(ListContinuation.indented("- a") == "    - a")
        #expect(ListContinuation.outdented("    - a") == "- a")
        #expect(ListContinuation.outdented("  - a") == "- a")
        #expect(ListContinuation.outdented("- a") == "- a")
    }
}
