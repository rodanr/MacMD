import Foundation
import Testing

@testable import MacMDKit

@Suite struct PerformanceTests {
    @Test func stylingALargeDocumentIsFast() throws {
        let url = try #require(
            Bundle.module.url(forResource: "kitchen-sink", withExtension: "md", subdirectory: "Fixtures"))
        let text = String(repeating: try String(contentsOf: url, encoding: .utf8) + "\n", count: 50)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = SpanCollector.collect(text) }
        // Generous bound for unoptimized CI builds; release builds are several times faster.
        #expect(elapsed < .milliseconds(500), "styling \(text.utf8.count) bytes took \(elapsed)")
        print("SpanCollector: \(text.utf8.count) bytes in \(elapsed)")
    }
}
