import Testing

@testable import MacMDKit

@Suite struct LaunchArgumentsTests {
    @Test func plainPathsAreFiles() {
        #expect(LaunchArguments.filePaths(in: ["notes.md", "/tmp/a.md"]) == ["notes.md", "/tmp/a.md"])
    }

    @Test func aFlagsValueIsNotAFile() {
        // `-appearance system` once opened /System: macOS paths are case-insensitive.
        #expect(
            LaunchArguments.filePaths(in: ["-appearance", "system", "-theme", "paper", "notes.md"]) == ["notes.md"])
    }

    @Test func aFlagWithoutAValueIsSkipped() {
        #expect(LaunchArguments.filePaths(in: ["-psn_0_12345", "notes.md"]) == ["notes.md"])
        #expect(LaunchArguments.filePaths(in: ["notes.md", "-zoom"]) == ["notes.md"])
    }

    @Test func flagsFollowingFlagsAreNotValues() {
        #expect(LaunchArguments.filePaths(in: ["-a", "-b", "1", "x.md"]) == ["x.md"])
    }
}
