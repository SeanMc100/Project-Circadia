import Foundation

enum DaylightAnalyzer {
    /// Minutes of outdoor light falling inside `interval`, prorating samples that straddle its edges.
    static func minutes(of samples: [DaylightSample], in interval: DateInterval) -> Double {
        samples.reduce(0) { total, sample in
            let span = sample.end.timeIntervalSince(sample.start)
            guard span > 0 else {
                return total + (interval.contains(sample.start) ? sample.minutes : 0)
            }
            let overlapStart = max(sample.start, interval.start)
            let overlapEnd = min(sample.end, interval.end)
            guard overlapEnd > overlapStart else { return total }
            return total + sample.minutes * overlapEnd.timeIntervalSince(overlapStart) / span
        }
    }

    static func summary(samples: [DaylightSample], day: Date, wake: Date?, calendar: Calendar = .current) -> DaylightSummary {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) else { return .empty }
        let daySamples = samples.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
        let total = minutes(of: daySamples, in: DateInterval(start: start, end: end))
        let beforeNoon = minutes(of: daySamples, in: DateInterval(start: start, end: noon))
        var firstLight: Double?
        if let wake, let first = daySamples.first(where: { $0.end > wake }) {
            firstLight = max(0, first.start.timeIntervalSince(wake) / 60)
        }
        return DaylightSummary(firstLightAfterWakeMinutes: firstLight, minutesBeforeNoon: beforeNoon, totalMinutes: total)
    }
}

/// Combines nights, daylight and secondary signals into one `DayMetrics` per calendar day.
enum DayMetricsBuilder {
    static func build(nights: [NightRecord],
                      daylight: [DaylightSample],
                      secondary: [SecondaryMetric: [MetricSample]],
                      from start: Date,
                      through end: Date,
                      calendar: Calendar = .current) -> [DayMetrics] {
        let nightsByDay = Dictionary(nights.map { ($0.wakeDay, $0) }, uniquingKeysWith: { a, _ in a })
        let hasLightData = !daylight.isEmpty
        let secondaryByDay: [SecondaryMetric: [Date: Double]] = secondary.mapValues { samples in
            Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
                .mapValues { group in group.reduce(0) { $0 + $1.value } / Double(group.count) }
        }

        var result: [DayMetrics] = []
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            let night = nightsByDay[day]
            let light = DaylightAnalyzer.summary(samples: daylight, day: day, wake: night?.primary.wake, calendar: calendar)
            result.append(DayMetrics(
                day: day,
                isFreeDay: calendar.isDateInWeekend(day),
                night: night,
                light: light,
                hasLightData: hasLightData,
                onsetMinutes: night.map { ClockMath.signedMinutes($0.primary.onset, calendar: calendar) },
                wakeMinutes: night.map { ClockMath.signedMinutes($0.primary.wake, calendar: calendar) },
                midpointMinutes: night.map { ClockMath.signedMinutes($0.primary.midpoint, calendar: calendar) },
                hrv: secondaryByDay[.hrv]?[day],
                restingHeartRate: secondaryByDay[.restingHeartRate]?[day],
                wristTemperature: secondaryByDay[.wristTemperature]?[day]
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
