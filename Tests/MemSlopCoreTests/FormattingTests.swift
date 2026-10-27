import Testing
@testable import MemSlopCore

@Suite struct FormattingTests {
    @Test func bytes() {
        #expect(Formatting.bytes(512) == "512 B")
        #expect(Formatting.bytes(5 * 1_048_576) == "5 MB")
        #expect(Formatting.bytes(3 * 1_073_741_824 / 2) == "1.5 GB")
    }

    @Test func durations() {
        #expect(Formatting.duration(42) == "42s")
        #expect(Formatting.duration(600) == "10m")
        #expect(Formatting.duration(3 * 3600 + 120) == "3h 2m")
    }
}
