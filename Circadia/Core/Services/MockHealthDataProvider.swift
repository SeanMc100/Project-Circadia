import Foundation

/// Deterministic pseudo-random generator so demo data is stable across launches and in tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }

    mutating func chance(_ p: Double) -> Bool { uniform(0...1) < p }

    /// Box–Muller normal sample.
    mutating func normal(mean: Double = 0, sd: Double) -> Double {
        let u1 = max(uniform(0...1), 1e-12), u2 = uniform(0...1)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

struct MockDataset {
    var sleep: [SleepSample] = []
    var daylight: [DaylightSample] = []
    var secondary: [SecondaryMetric: [MetricSample]] = [:]
}

/// Generates ~60 days of realistic synthetic data: a stable weekday pattern, later weekends
/// (social jetlag), a few disrupted nights, variable morning light, overlapping iPhone + Watch
/// samples, occasional naps, and secondary signals. Early light on a day nudges the following
/// night's onset earlier, so the closed-loop insights have something real to find.
@MainActor
final class MockHealthDataProvider: HealthDataProviding {
    let sourceKind: HealthSourceKind = .mock
    let isAvailable = true
    private let calendar: Calendar
    private let days: Int
    private let nowProvider: () -> Date
    private var cache: (key: Date, data: MockDataset)?
    /// False simulates a phone-only user: nights look like sleep-log entries (rounded, no stages),
    /// last night is left for the user to log, and there's no daylight or heart data.
    var includesWearableData = true

    init(days: Int = CircadianConfig.mockDays, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.days = days
        self.calendar = calendar
        self.nowProvider = now
    }

    func authorizationState() async -> HealthAuthorizationState { .demo }
    func requestAuthorization() async throws {}
    func startObserving(onChange: @escaping @MainActor () -> Void) {}

    private func dataset() -> MockDataset {
        let now = nowProvider()
        // Regenerate at most every 5 minutes so "today so far" advances.
        let key = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 300).rounded(.down) * 300)
        if let cache, cache.key == key { return cache.data }
        let data = Self.generate(endingAt: now, days: days, calendar: calendar)
        cache = (key, data)
        return data
    }

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let sleep = includesWearableData ? dataset().sleep : Self.loggedNights(from: dataset().sleep, now: nowProvider(), calendar: calendar)
        return sleep.filter { $0.end > start && $0.start < end }
    }

    func daylightSamples(from start: Date, to end: Date) async throws -> [DaylightSample] {
        guard includesWearableData else { return [] }
        return dataset().daylight.filter { $0.end > start && $0.start < end }
    }

    func secondarySamples(_ metric: SecondaryMetric, from start: Date, to end: Date) async throws -> [MetricSample] {
        guard includesWearableData else { return [] }
        return (dataset().secondary[metric] ?? []).filter { $0.date >= start && $0.date <= end }
    }

    /// One rounded sample per main sleep, as if typed into the sleep log, except the night
    /// ending today.
    nonisolated static func loggedNights(from samples: [SleepSample], now: Date, calendar: Calendar) -> [SleepSample] {
        func round(_ date: Date) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 300).rounded() * 300)
        }
        return SleepSessionBuilder.buildNights(from: samples, calendar: calendar)
            .filter { !calendar.isDate($0.wakeDay, inSameDayAs: now) }
            .map { SleepLogMerger.sample(SleepLog(wakeDay: $0.wakeDay, onset: round($0.primary.onset), wake: round($0.primary.wake))) }
    }

    // MARK: - Generation

    nonisolated static func generate(endingAt now: Date, days: Int, calendar: Calendar) -> MockDataset {
        var data = MockDataset()
        let today = calendar.startOfDay(for: now)
        var previousDayHadEarlyLight = false

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let wakeDay = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let ordinal = calendar.ordinality(of: .day, in: .era, for: wakeDay) ?? offset
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: ordinal) &* 2_654_435_761)
            let isFree = calendar.isDateInWeekend(wakeDay)

            // --- The night ending on wakeDay ---
            var onsetMinutes = -45 + rng.normal(sd: 15)          // ~11:15 PM
            var wakeMinutes = 7 * 60 + rng.normal(sd: 12)        // ~7:00 AM
            if isFree {
                onsetMinutes += 70 + rng.normal(sd: 15)
                wakeMinutes += 95 + rng.normal(sd: 20)
            }
            onsetMinutes += previousDayHadEarlyLight ? -20 : 10
            let disrupted = rng.chance(0.07)
            if disrupted {
                onsetMinutes += 110 + rng.uniform(0...40)
                wakeMinutes += rng.uniform(0...30)
            }
            let onset = ClockMath.date(on: wakeDay, minutes: onsetMinutes, calendar: calendar)
            let wake = ClockMath.date(on: wakeDay, minutes: wakeMinutes, calendar: calendar)

            var wakeForLight: Date? = nil
            if wake <= now {
                wakeForLight = wake
                data.sleep += nightSamples(onset: onset, wake: wake, disrupted: disrupted, rng: &rng)
                if isFree && rng.chance(0.25) {
                    let napStart = ClockMath.date(on: wakeDay, minutes: 15 * 60 + rng.uniform(0...45), calendar: calendar)
                    let napEnd = napStart.adding(minutes: rng.uniform(18...35))
                    if napEnd <= now {
                        data.sleep.append(SleepSample(start: napStart, end: napEnd, stage: .asleepCore, sourceName: "Apple Watch", isFromWatch: true))
                    }
                }
                // Secondary signals recorded overnight.
                data.secondary[.hrv, default: []].append(MetricSample(date: wake, value: 48 + rng.normal(sd: 6) - (disrupted ? 9 : 0)))
                data.secondary[.restingHeartRate, default: []].append(MetricSample(date: wake, value: 57 + rng.normal(sd: 2) + (disrupted ? 3 : 0)))
                data.secondary[.wristTemperature, default: []].append(MetricSample(date: wake, value: 36.2 + rng.normal(sd: 0.15) + (disrupted ? 0.2 : 0)))
            }

            // --- Daylight on wakeDay ---
            let lightAnchor = wakeForLight ?? wake
            var blocks: [(Date, Double)] = []
            // Same probability every day so weekends don't confound the light → onset effect.
            let early = rng.chance(0.6)
            if early {
                blocks.append((lightAnchor.adding(minutes: rng.uniform(15...80)), rng.uniform(8...30)))
            } else if rng.chance(0.4) {
                blocks.append((lightAnchor.adding(minutes: rng.uniform(150...260)), rng.uniform(5...15)))
            }
            if rng.chance(0.7) {
                blocks.append((ClockMath.date(on: wakeDay, minutes: 12 * 60 + 15 + rng.uniform(0...60), calendar: calendar), rng.uniform(5...20)))
            }
            if rng.chance(isFree ? 0.6 : 0.35) {
                blocks.append((ClockMath.date(on: wakeDay, minutes: 16 * 60 + rng.uniform(0...120), calendar: calendar), rng.uniform(5...30)))
            }
            for (start, minutes) in blocks {
                data.daylight += chunkedDaylight(start: start, minutes: minutes, notAfter: now)
            }
            previousDayHadEarlyLight = early && wakeForLight != nil
        }
        return data
    }

    /// Watch stage samples cycling core/deep/REM with brief awakenings, plus an overlapping
    /// iPhone in-bed sample and sometimes a duplicate iPhone asleep sample.
    nonisolated private static func nightSamples(onset: Date, wake: Date, disrupted: Bool, rng: inout SeededRandom) -> [SleepSample] {
        var samples: [SleepSample] = []
        var t = onset
        var cycle = 0
        while t < wake {
            let late = Double(cycle) / 5
            let stages: [(SleepStage, Double)] = [
                (.asleepCore, rng.uniform(30...50)),
                (.asleepDeep, max(5, rng.uniform(15...30) * (1 - late))),
                (.asleepCore, rng.uniform(10...20)),
                (.asleepREM, rng.uniform(10...20) * (1 + late)),
            ]
            for (stage, minutes) in stages where t < wake {
                let end = min(wake, t.adding(minutes: minutes))
                samples.append(SleepSample(start: t, end: end, stage: stage, sourceName: "Apple Watch", isFromWatch: true))
                t = end
            }
            if t < wake, rng.chance(disrupted ? 0.6 : 0.2) {
                let end = min(wake, t.adding(minutes: rng.uniform(disrupted ? 10...35 : 2...8)))
                samples.append(SleepSample(start: t, end: end, stage: .awake, sourceName: "Apple Watch", isFromWatch: true))
                t = end
            }
            cycle += 1
        }
        samples.append(SleepSample(start: onset.adding(minutes: -15), end: wake.adding(minutes: 10), stage: .inBed, sourceName: "iPhone", isFromWatch: false))
        if rng.chance(0.3) {
            samples.append(SleepSample(start: onset.adding(minutes: -25), end: wake.adding(minutes: 20), stage: .asleepUnspecified, sourceName: "iPhone", isFromWatch: false))
        }
        return samples
    }

    /// Splits a block of outdoor time into ≤5-minute samples, like the Watch records them.
    nonisolated private static func chunkedDaylight(start: Date, minutes: Double, notAfter now: Date) -> [DaylightSample] {
        var samples: [DaylightSample] = []
        var t = start
        var remaining = minutes
        while remaining > 0.5 {
            let chunk = min(5, remaining)
            let end = t.adding(minutes: chunk)
            guard end <= now else { break }
            samples.append(DaylightSample(start: t, end: end, minutes: chunk))
            t = end
            remaining -= chunk
        }
        return samples
    }
}
