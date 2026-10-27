import Foundation

/// Resource usage of one group at one moment, for "who was it?" questions.
public struct GroupUsage: Codable, Sendable, Hashable {
    public let name: String
    /// Activity Monitor scale (100 = one core).
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

/// One point of the CPU / memory history. Ratios are 0...1.
public struct MetricPoint: Codable, Sendable, Hashable, Identifiable {
    public let time: Date
    public let cpu: Double
    public let memory: Double
    public let cpuPeak: Double
    public let memoryPeak: Double
    /// Biggest consumers at that moment (minute points only).
    public let top: [GroupUsage]

    public var id: Date { time }

    public init(time: Date, cpu: Double, memory: Double, cpuPeak: Double? = nil, memoryPeak: Double? = nil, top: [GroupUsage] = []) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.cpuPeak = cpuPeak ?? cpu
        self.memoryPeak = memoryPeak ?? memory
        self.top = top
    }
}

/// Two-resolution history: every sample for the last hour, one point per minute for 24 hours.
public struct MetricHistory: Sendable {
    public static let fineSpan: TimeInterval = 3600
    public static let retention: TimeInterval = 24 * 3600

    public private(set) var fine: [MetricPoint] = []
    public private(set) var minutes: [MetricPoint] = []

    private var bucketStart: Date?
    private var bucket: [(cpu: Double, memory: Double)] = []
    private var bucketTop: [GroupUsage] = []

    public init() {}

    public mutating func record(time: Date, cpu: Double, memory: Double, top: [GroupUsage]? = nil) {
        fine.append(MetricPoint(time: time, cpu: cpu, memory: memory))
        if let first = fine.first, time.timeIntervalSince(first.time) > Self.fineSpan {
            fine.removeAll { time.timeIntervalSince($0.time) > Self.fineSpan }
        }

        let minute = Self.minute(of: time)
        if let start = bucketStart, start != minute {
            flush()
        }
        bucketStart = minute
        bucket.append((cpu, memory))
        if let top { bucketTop = top }
        prune(now: time)
    }

    /// Points to draw for the last `span` seconds: fine resolution up to an hour, minutes beyond.
    public func points(lastSeconds span: TimeInterval, now: Date) -> [MetricPoint] {
        let since = now.addingTimeInterval(-span)
        if span <= Self.fineSpan {
            return fine.filter { $0.time >= since }
        }
        return (minutes + currentMinute()).filter { $0.time >= since }
    }

    /// Averages consecutive points into at most `limit` buckets (keeps peaks), for cheap charts.
    public static func downsample(_ points: [MetricPoint], to limit: Int) -> [MetricPoint] {
        guard limit > 0, points.count > limit else { return points }
        let size = Int((Double(points.count) / Double(limit)).rounded(.up))
        return stride(from: 0, to: points.count, by: size).map { start in
            let slice = points[start..<min(start + size, points.count)]
            let count = Double(slice.count)
            return MetricPoint(
                time: slice.first!.time,
                cpu: slice.reduce(0) { $0 + $1.cpu } / count,
                memory: slice.reduce(0) { $0 + $1.memory } / count,
                cpuPeak: slice.map(\.cpuPeak).max(),
                memoryPeak: slice.map(\.memoryPeak).max(),
                top: slice.last!.top
            )
        }
    }

    /// The minute point closest to `date`, with its top consumers.
    public func minutePoint(near date: Date) -> MetricPoint? {
        (minutes + currentMinute()).min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    public mutating func prune(now: Date) {
        if let first = minutes.first, now.timeIntervalSince(first.time) > Self.retention {
            minutes.removeAll { now.timeIntervalSince($0.time) > Self.retention }
        }
    }

    private mutating func flush() {
        guard let start = bucketStart, !bucket.isEmpty else { return }
        let count = Double(bucket.count)
        minutes.append(MetricPoint(
            time: start,
            cpu: bucket.reduce(0) { $0 + $1.cpu } / count,
            memory: bucket.reduce(0) { $0 + $1.memory } / count,
            cpuPeak: bucket.map(\.cpu).max(),
            memoryPeak: bucket.map(\.memory).max(),
            top: bucketTop
        ))
        bucket = []
        bucketTop = []
    }

    private func currentMinute() -> [MetricPoint] {
        guard let start = bucketStart, !bucket.isEmpty else { return [] }
        let count = Double(bucket.count)
        return [MetricPoint(
            time: start,
            cpu: bucket.reduce(0) { $0 + $1.cpu } / count,
            memory: bucket.reduce(0) { $0 + $1.memory } / count,
            cpuPeak: bucket.map(\.cpu).max(),
            memoryPeak: bucket.map(\.memory).max(),
            top: bucketTop
        )]
    }

    static func minute(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    // MARK: - Persistence (minute points only; the fine buffer is rebuilt in an hour)

    public func save(to url: URL) {
        var copy = self
        copy.flush()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.memslop.encode(copy.minutes) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func load(from url: URL, now: Date = Date()) -> MetricHistory {
        var history = MetricHistory()
        if let data = try? Data(contentsOf: url), let points = try? JSONDecoder.memslop.decode([MetricPoint].self, from: data) {
            history.minutes = points.sorted { $0.time < $1.time }
        }
        history.prune(now: now)
        return history
    }
}
