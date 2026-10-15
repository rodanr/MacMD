import Testing

@testable import MacMDKit

struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() throws {
        #expect(try #require(AppVersion("v1.2.3")).components == [1, 2, 3])
        #expect(try #require(AppVersion("0.1.0")).components == [0, 1, 0])
        #expect(try #require(AppVersion("2.0.0-beta.1")).components == [2, 0, 0])
        #expect(try #require(AppVersion(" 1.4+build.7 ")).description == "1.4")
    }

    @Test func rejectsGarbage() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("1.-2") == nil)
    }

    @Test func comparesNumericallyNotLexically() throws {
        let older = try #require(AppVersion("0.9.0"))
        let newer = try #require(AppVersion("0.10.0"))
        #expect(older < newer)
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
        #expect(!(try #require(AppVersion("1.0.1")) < #require(AppVersion("1.0"))))
    }
}
