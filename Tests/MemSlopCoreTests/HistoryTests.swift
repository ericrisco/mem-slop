import Foundation
import Testing
@testable import MemSlopCore

@Suite struct HistoryTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aggregatesMinutesWithAverageAndPeak() {
        var history = MetricHistory()
        history.record(time: start, cpu: 0.2, memory: 0.5)
        history.record(time: start.addingTimeInterval(20), cpu: 0.6, memory: 0.7)
        history.record(time: start.addingTimeInterval(61), cpu: 0.1, memory: 0.1)
        let minute = try! #require(history.minutes.first)
        #expect(history.minutes.count == 1)
        #expect(abs(minute.cpu - 0.4) < 0.0001)
        #expect(minute.cpuPeak == 0.6)
        #expect(minute.memoryPeak == 0.7)
    }

    @Test func keepsOnlyTwentyFourHours() {
        var history = MetricHistory()
        for minute in 0..<(26 * 60) {
            history.record(time: start.addingTimeInterval(TimeInterval(minute * 60)), cpu: 0.1, memory: 0.2)
        }
        let now = start.addingTimeInterval(TimeInterval(26 * 60 * 60))
        #expect(history.minutes.allSatisfy { now.timeIntervalSince($0.time) <= MetricHistory.retention + 60 })
        #expect(history.points(lastSeconds: 24 * 3600, now: now).count <= 24 * 60 + 1)
        #expect(history.fine.allSatisfy { now.timeIntervalSince($0.time) <= MetricHistory.fineSpan + 60 })
    }

    @Test func shortRangesUseFineResolution() {
        var history = MetricHistory()
        for second in stride(from: 0, to: 600, by: 2) {
            history.record(time: start.addingTimeInterval(TimeInterval(second)), cpu: 0.3, memory: 0.4)
        }
        let now = start.addingTimeInterval(600)
        #expect(history.points(lastSeconds: 3600, now: now).count == 300)
        #expect(history.points(lastSeconds: 6 * 3600, now: now).count == 10)
    }

    @Test func keepsTopConsumersPerMinute() {
        var history = MetricHistory()
        let top = [GroupUsage(name: "Node.js", cpuPercent: 240, memoryBytes: 8_000_000_000)]
        history.record(time: start, cpu: 0.9, memory: 0.8, top: top)
        history.record(time: start.addingTimeInterval(70), cpu: 0.1, memory: 0.1)
        #expect(history.minutePoint(near: start.addingTimeInterval(10))?.top == top)
    }

    @Test func survivesRestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = MetricHistory()
        for minute in 0..<120 {
            history.record(time: start.addingTimeInterval(TimeInterval(minute * 60)), cpu: 0.25, memory: 0.5)
        }
        history.save(to: url)
        let reloaded = MetricHistory.load(from: url, now: start.addingTimeInterval(121 * 60))
        #expect(reloaded.minutes.count == 120)
        let old = MetricHistory.load(from: url, now: start.addingTimeInterval(30 * 3600))
        #expect(old.minutes.isEmpty)
    }

    @Test func downsamplesKeepingAveragesAndPeaks() {
        let points = (0..<1800).map { MetricPoint(time: start.addingTimeInterval(TimeInterval($0 * 2)), cpu: $0 % 2 == 0 ? 0 : 1, memory: 0.5) }
        let reduced = MetricHistory.downsample(points, to: 240)
        #expect(reduced.count <= 240)
        #expect(reduced.allSatisfy { abs($0.cpu - 0.5) < 0.2 && $0.cpuPeak == 1 })
        #expect(MetricHistory.downsample(Array(points.prefix(10)), to: 240).count == 10)
    }
}
