import Testing

@testable import MacMDKit

struct ZoomTests {
    @Test func stepsThroughLevelsAndStopsAtTheEnds() {
        #expect(Zoom.zoomedIn(from: 1.0) == 1.1)
        #expect(Zoom.zoomedOut(from: 1.0) == 0.85)
        #expect(Zoom.zoomedIn(from: 2.0) == 2.0)
        #expect(Zoom.zoomedOut(from: 0.75) == 0.75)
    }

    @Test func snapsOffLevelValuesToTheNextStep() {
        #expect(Zoom.zoomedIn(from: 1.05) == 1.1)
        #expect(Zoom.zoomedOut(from: 1.05) == 1.0)
    }

    @Test func sanitizesStoredValues() {
        #expect(Zoom.sanitized(0) == 1.0)
        #expect(Zoom.sanitized(.nan) == 1.0)
        #expect(Zoom.sanitized(3) == 1.0)
        #expect(Zoom.sanitized(1.25) == 1.25)
    }

    @Test func describesLevels() {
        #expect(Zoom.percent(1.1) == "110%")
        #expect(Zoom.describe(1.0) == "100% (actual size)")
        #expect(Zoom.describe(2.0) == "200% (largest)")
        #expect(Zoom.describe(0.75) == "75% (smallest)")
        #expect(Zoom.describe(1.25) == "125%")
    }
}
