import Foundation

/// Turns raw multi-source sleep samples into one primary sleep session per night, plus naps.
///
/// Rules:
/// 1. Only asleep stages define onset and wake. In-bed samples are used only for periods
///    with no asleep data at all (e.g. an iPhone-only night).
/// 2. Samples within `mergeGapMinutes` of each other form one cluster (handles brief wakes).
/// 3. Within a cluster, Apple Watch samples win when present; otherwise all sources are merged.
/// 4. Overlapping intervals are unioned so duplicated data is never double counted.
/// 5. Sessions are keyed by the calendar day they end on; the longest one (≥ minimum length)
///    is the primary sleep and the rest are naps. Sessions crossing midnight work naturally.
enum SleepSessionBuilder {

    static func buildNights(from samples: [SleepSample],
                            calendar: Calendar = .current,
                            mergeGapMinutes: Double = CircadianConfig.sessionMergeGapMinutes,
                            minimumPrimaryMinutes: Double = CircadianConfig.minimumPrimarySleepMinutes) -> [NightRecord] {
        let sessions = buildSessions(from: samples, mergeGapMinutes: mergeGapMinutes)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.wake) }
        var nights: [NightRecord] = []
        for (day, daySessions) in grouped {
            let byLength = daySessions.sorted { $0.asleepMinutes > $1.asleepMinutes }
            guard let primary = byLength.first, primary.asleepMinutes >= minimumPrimaryMinutes else { continue }
            let naps = byLength.dropFirst().sorted { $0.onset < $1.onset }
            nights.append(NightRecord(wakeDay: day, primary: primary, naps: Array(naps)))
        }
        return nights.sorted { $0.wakeDay < $1.wakeDay }
    }

    static func buildSessions(from samples: [SleepSample],
                              mergeGapMinutes: Double = CircadianConfig.sessionMergeGapMinutes) -> [SleepSession] {
        let valid = samples.filter { $0.end > $0.start }
        let asleep = valid.filter { $0.stage.isAsleep }
        let asleepSessions = clusters(of: asleep, gapMinutes: mergeGapMinutes).map { session(from: $0, inBedOnly: false) }
        let inBedSessions = clusters(of: valid.filter { $0.stage == .inBed }, gapMinutes: mergeGapMinutes)
            .map { session(from: $0, inBedOnly: true) }
            .filter { candidate in !asleepSessions.contains { $0.overlaps(candidate) } }
        return (asleepSessions + inBedSessions).sorted { $0.onset < $1.onset }
    }

    /// Groups samples whose intervals overlap or sit within `gapMinutes` of each other.
    static func clusters(of samples: [SleepSample], gapMinutes: Double) -> [[SleepSample]] {
        let sorted = samples.sorted { $0.start < $1.start }
        var result: [[SleepSample]] = []
        var current: [SleepSample] = []
        var currentEnd = Date.distantPast
        for sample in sorted {
            if current.isEmpty || sample.start.timeIntervalSince(currentEnd) <= gapMinutes * 60 {
                current.append(sample)
                currentEnd = max(currentEnd, sample.end)
            } else {
                result.append(current)
                current = [sample]
                currentEnd = sample.end
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func session(from cluster: [SleepSample], inBedOnly: Bool) -> SleepSession {
        let watch = cluster.filter(\.isFromWatch)
        let chosen = watch.isEmpty ? cluster : watch
        let intervals = mergeIntervals(chosen.map { DateInterval(start: $0.start, end: $0.end) })
        let asleepMinutes = intervals.reduce(0) { $0 + $1.duration } / 60
        return SleepSession(onset: intervals.first?.start ?? Date(),
                            wake: intervals.map(\.end).max() ?? Date(),
                            asleepMinutes: asleepMinutes,
                            isFromWatch: !watch.isEmpty,
                            isInBedOnly: inBedOnly,
                            intervals: intervals)
    }

    /// Union of overlapping or touching intervals.
    static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
