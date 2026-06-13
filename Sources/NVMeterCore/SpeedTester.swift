import Foundation

// MARK: - Public model

/// One benchmark pass — e.g. "SEQ1M Q8T1" read or write.
public struct SpeedTestProfile: Sendable, Identifiable, Equatable {
    public enum Pattern: String, Sendable, Codable { case sequential, random }

    public let id: String        // stable key, e.g. "seq1m-q8t1"
    public let label: String     // display, e.g. "SEQ1M Q8T1"
    public let pattern: Pattern
    public let blockSize: Int    // bytes per I/O
    public let queueDepth: Int   // concurrent in-flight I/Os
    public let isRead: Bool

    public init(id: String, label: String, pattern: Pattern, blockSize: Int, queueDepth: Int, isRead: Bool) {
        self.id = id
        self.label = label
        self.pattern = pattern
        self.blockSize = blockSize
        self.queueDepth = queueDepth
        self.isRead = isRead
    }

    /// CrystalDiskMark's classic four rows, each as a write then a read.
    /// Write precedes read in every pair so the read target always exists.
    public static func defaultSuite() -> [SpeedTestProfile] {
        func pair(id: String, label: String, pattern: Pattern, block: Int, qd: Int) -> [SpeedTestProfile] {
            [
                SpeedTestProfile(id: id + "-write", label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: false),
                SpeedTestProfile(id: id + "-read",  label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: true),
            ]
        }
        return sequentialSuite() + randomSuite()
    }

    /// Sequential read/write only — the meaningful test for spinning HDDs
    /// (random 4K is glacial and pointless on mechanical media).
    public static func sequentialSuite() -> [SpeedTestProfile] {
        func pair(id: String, label: String, pattern: Pattern, block: Int, qd: Int) -> [SpeedTestProfile] {
            [
                SpeedTestProfile(id: id + "-write", label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: false),
                SpeedTestProfile(id: id + "-read",  label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: true),
            ]
        }
        return pair(id: "seq1m-q8t1", label: "SEQ1M Q8T1", pattern: .sequential, block: 1 << 20, qd: 8)
             + pair(id: "seq1m-q1t1", label: "SEQ1M Q1T1", pattern: .sequential, block: 1 << 20, qd: 1)
    }

    public static func randomSuite() -> [SpeedTestProfile] {
        func pair(id: String, label: String, pattern: Pattern, block: Int, qd: Int) -> [SpeedTestProfile] {
            [
                SpeedTestProfile(id: id + "-write", label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: false),
                SpeedTestProfile(id: id + "-read",  label: label, pattern: pattern, blockSize: block, queueDepth: qd, isRead: true),
            ]
        }
        return pair(id: "rnd4k-q32", label: "RND4K Q32T1", pattern: .random, block: 4 << 10, qd: 32)
             + pair(id: "rnd4k-q1",  label: "RND4K Q1T1",  pattern: .random, block: 4 << 10, qd: 1)
    }
}

/// One point on the live speed/temperature timeline taken during a run.
public struct SpeedSample: Sendable, Codable {
    public let elapsed: TimeInterval   // seconds since the run started
    public let profileID: String
    public let isRead: Bool
    public let mbPerSec: Double
    public let temperatureC: Int?

    public init(elapsed: TimeInterval, profileID: String, isRead: Bool, mbPerSec: Double, temperatureC: Int?) {
        self.elapsed = elapsed
        self.profileID = profileID
        self.isRead = isRead
        self.mbPerSec = mbPerSec
        self.temperatureC = temperatureC
    }
}

/// Final figure for one profile.
public struct ProfileResult: Sendable, Codable, Identifiable {
    public let profileID: String
    public let label: String
    public let isRead: Bool
    public let mbPerSec: Double
    public let iops: Double?           // random patterns only

    public var id: String { profileID }

    public init(profileID: String, label: String, isRead: Bool, mbPerSec: Double, iops: Double?) {
        self.profileID = profileID
        self.label = label
        self.isRead = isRead
        self.mbPerSec = mbPerSec
        self.iops = iops
    }
}

/// Everything produced by one full benchmark run.
public struct SpeedTestRun: Sendable, Codable {
    public let results: [ProfileResult]
    public let samples: [SpeedSample]
    public let bytesWritten: Int64
    public let startedAt: Date
    public let durationSeconds: TimeInterval

    public init(results: [ProfileResult], samples: [SpeedSample], bytesWritten: Int64, startedAt: Date, durationSeconds: TimeInterval) {
        self.results = results
        self.samples = samples
        self.bytesWritten = bytesWritten
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
    }
}

public enum SpeedTestError: Error {
    case directoryNotWritable(String)
    case openFailed(String, Int32)
    case ioFailed(String, Int32)
    case cancelled
}

// MARK: - Engine

/// Disk benchmark engine. Writes a scratch file, hammers it with the
/// requested I/O patterns (page cache disabled via `F_NOCACHE`), and
/// samples instantaneous throughput plus drive temperature throughout —
/// the temperature track is what lets the UI explain SLC-cache or
/// thermal-throttle slowdowns that pure speed tools can't.
public actor SpeedTester {
    public init() {}

    private static let scratchName = ".nvmeter-speedtest.bin"

    public func run(
        directory: URL,
        totalBytesPerProfile: Int64,
        profiles: [SpeedTestProfile] = SpeedTestProfile.defaultSuite(),
        temperatureSampler: @escaping @Sendable () async -> Int?,
        onProgress: @escaping @Sendable (_ profile: SpeedTestProfile, _ fraction: Double, _ instantMBps: Double, _ temp: Int?) -> Void,
        onProfileComplete: @escaping @Sendable (_ result: ProfileResult) -> Void = { _ in }
    ) async throws -> SpeedTestRun {
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw SpeedTestError.directoryNotWritable(directory.path)
        }
        let fileURL = directory.appendingPathComponent(Self.scratchName)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let collector = SampleCollector()
        let runStart = Date()
        var results: [ProfileResult] = []
        var bytesWritten: Int64 = 0

        for profile in profiles {
            if Task.isCancelled { throw SpeedTestError.cancelled }
            let result = try await runProfile(
                profile,
                fileURL: fileURL,
                totalBytes: totalBytesPerProfile,
                runStart: runStart,
                collector: collector,
                temperatureSampler: temperatureSampler,
                onProgress: onProgress
            )
            results.append(result)
            onProfileComplete(result)
            if !profile.isRead { bytesWritten += totalBytesPerProfile }
        }

        return SpeedTestRun(
            results: results,
            samples: collector.all(),
            bytesWritten: bytesWritten,
            startedAt: runStart,
            durationSeconds: Date().timeIntervalSince(runStart)
        )
    }

    // MARK: - One profile

    private func runProfile(
        _ profile: SpeedTestProfile,
        fileURL: URL,
        totalBytes: Int64,
        runStart: Date,
        collector: SampleCollector,
        temperatureSampler: @escaping @Sendable () async -> Int?,
        onProgress: @escaping @Sendable (SpeedTestProfile, Double, Double, Int?) -> Void
    ) async throws -> ProfileResult {
        let blockSize = profile.blockSize
        let blockCount = max(1, Int(totalBytes / Int64(blockSize)))
        let effectiveBytes = Int64(blockCount) * Int64(blockSize)
        let path = fileURL.path

        // Open: writers create/extend the file, readers open it read-only.
        let flags = profile.isRead ? O_RDONLY : (O_CREAT | O_WRONLY)
        let fd = open(path, flags, 0o644)
        guard fd >= 0 else { throw SpeedTestError.openFailed(path, errno) }
        defer { close(fd) }

        // Bypass the unified buffer cache so we measure the device, not RAM.
        _ = fcntl(fd, F_NOCACHE, 1)

        // Ensure the file is large enough for readers / random writers.
        if !profile.isRead {
            ftruncate(fd, off_t(effectiveBytes))
        }

        let counter = ByteCounter()
        let nextIndex = WorkIndex()
        let profileStart = Date()

        // Live sampler: every 0.5 s, derive instantaneous MB/s from the
        // byte counter and pair it with a fresh temperature reading.
        let samplerTask = Task<Void, Never> { [profile] in
            var lastBytes: Int64 = 0
            var lastTick = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }
                let now = counter.value()
                let dt = Date().timeIntervalSince(lastTick)
                let mbps = dt > 0 ? Double(now - lastBytes) / dt / 1_000_000 : 0
                let temp = await temperatureSampler()
                let fraction = min(1.0, Double(now) / Double(effectiveBytes))
                onProgress(profile, fraction, mbps, temp)
                collector.add(SpeedSample(
                    elapsed: Date().timeIntervalSince(runStart),
                    profileID: profile.id,
                    isRead: profile.isRead,
                    mbPerSec: mbps,
                    temperatureC: temp
                ))
                lastBytes = now
                lastTick = Date()
            }
        }

        // Concurrent I/O workers (queue depth = number of workers).
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for _ in 0..<profile.queueDepth {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    var raw: UnsafeMutableRawPointer? = nil
                    posix_memalign(&raw, 4096, blockSize)
                    guard let buffer = raw else { group.leave(); return }
                    defer { free(buffer) }
                    if !profile.isRead {
                        arc4random_buf(buffer, blockSize)   // incompressible
                    }

                    while let index = nextIndex.next(below: blockCount) {
                        let offset: off_t
                        if profile.pattern == .random {
                            offset = off_t(Int64.random(in: 0..<Int64(blockCount)) * Int64(blockSize))
                        } else {
                            offset = off_t(Int64(index) * Int64(blockSize))
                        }
                        let n = profile.isRead
                            ? pread(fd, buffer, blockSize, offset)
                            : pwrite(fd, buffer, blockSize, offset)
                        if n > 0 { counter.add(Int64(n)) }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .global()) { cont.resume() }
        }

        if !profile.isRead { fsync(fd) }
        samplerTask.cancel()

        let elapsed = max(0.0001, Date().timeIntervalSince(profileStart))
        let mbps = Double(effectiveBytes) / elapsed / 1_000_000
        let iops = profile.pattern == .random ? Double(blockCount) / elapsed : nil

        // One final progress tick at 100% so the UI lands on the real number.
        onProgress(profile, 1.0, mbps, await temperatureSampler())

        return ProfileResult(
            profileID: profile.id,
            label: profile.label,
            isRead: profile.isRead,
            mbPerSec: mbps,
            iops: iops
        )
    }
}

// MARK: - Lock-protected helpers (Sendable across GCD workers)

/// Monotonic byte counter updated by I/O workers, read by the sampler.
private final class ByteCounter: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var bytes: Int64 = 0
    func add(_ n: Int64) { os_unfair_lock_lock(&lock); bytes += n; os_unfair_lock_unlock(&lock) }
    func value() -> Int64 { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return bytes }
}

/// Hands out the next block index to whichever worker asks first.
private final class WorkIndex: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var i = 0
    func next(below limit: Int) -> Int? {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        guard i < limit else { return nil }
        defer { i += 1 }
        return i
    }
}

/// Accumulates samples from the sampler tasks across all profiles.
private final class SampleCollector: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var samples: [SpeedSample] = []
    func add(_ s: SpeedSample) { os_unfair_lock_lock(&lock); samples.append(s); os_unfair_lock_unlock(&lock) }
    func all() -> [SpeedSample] { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return samples }
}
