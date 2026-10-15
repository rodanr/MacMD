import Testing

@testable import MacMDKit

struct FontSizeTests {
    @Test func stepsByOnePointWithinTheRange() {
        #expect(FontSize.bigger(than: 16) == 17)
        #expect(FontSize.smaller(than: 16) == 15)
        #expect(FontSize.bigger(than: 36) == 36)
        #expect(FontSize.smaller(than: 10) == 10)
    }

    @Test func sanitizesTypedAndStoredValues() {
        #expect(FontSize.sanitized(18.4) == 18)
        #expect(FontSize.sanitized(2) == 10)
        #expect(FontSize.sanitized(400) == 36)
        #expect(FontSize.sanitized(0) == 16)
        #expect(FontSize.sanitized(-3) == 16)
        #expect(FontSize.sanitized(.nan) == 16)
        #expect(FontSize.sanitized(.infinity) == 16)
    }

    @Test func describesSizes() {
        #expect(FontSize.describe(16) == "16 pt (default)")
        #expect(FontSize.describe(36) == "36 pt (largest)")
        #expect(FontSize.describe(10) == "10 pt (smallest)")
        #expect(FontSize.describe(20) == "20 pt")
    }
}
