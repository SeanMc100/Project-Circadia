import Foundation
import Observation

struct TimePoint: Identifiable {
    var id: Date { day }
    let day: Date
    let minutes: Double
}

struct SleepBar: Identifiable {
    var id: Date { day }
    let day: Date
    let onset: Double
    let wake: Double
}

struct LightBar: Identifiable {
    var id: String { "\(day.timeIntervalSince1970)-\(segment)" }
    let day: Date
    let segment: String
    let minutes: Double
}

struct ValuePoint: Identifiable {
    var id: Date { day }
    let day: Date
    let value: Double
}

@MainActor
@Observable
final class TrendsViewModel {
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String { "\(rawValue)d" }
    }

    var range: Range = .month
    var showSecondary = false
    var secondaryMetric: SecondaryMetric = .hrv

    /// Band half-width around the baseline in the midpoint chart.
    let baselineBandMinutes: Double = 30

    struct Series {
        var midpoints: [TimePoint] = []
        var baseline: [TimePoint] = []
        var sleepBars: [SleepBar] = []
        var light: [LightBar] = []
        var jetlag: [ValuePoint] = []
        var secondary: [ValuePoint] = []
        var onsetSD: Double?
        var wakeSD: Double?
        var hasLightData = false
        var startDay: Date = .now
        var endDay: Date = .now
    }

    func series(from days: [DayMetrics], calendar: Calendar = .current) -> Series {
        var s = Series()
        guard let last = days.last?.day,
              let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: last) else { return s }
        s.startDay = start
        s.endDay = last
        let inRange = days.filter { $0.day >= start }

        // Unwrap clock times around one reference so the y-axis is continuous across midnight.
        let reference = ClockMath.circularMean(inRange.compactMap(\.midpointMinutes)) ?? 180
        func u(_ m: Double) -> Double { ClockMath.unwrap([m], around: reference)[0] }

        let baselines = CircadianModel.rollingBaselines(days: days)
        for d in inRange {
            if let m = d.midpointMinutes { s.midpoints.append(TimePoint(day: d.day, minutes: u(m))) }
            if let b = baselines[d.day] { s.baseline.append(TimePoint(day: d.day, minutes: u(b))) }
            if let onset = d.onsetMinutes, let wake = d.wakeMinutes {
                s.sleepBars.append(SleepBar(day: d.day, onset: u(onset), wake: u(wake)))
            }
        }

        s.hasLightData = inRange.contains(where: \.hasLightData)
        if s.hasLightData {
            for d in inRange {
                s.light.append(LightBar(day: d.day, segment: "Before noon", minutes: d.light.minutesBeforeNoon))
                s.light.append(LightBar(day: d.day, segment: "After noon", minutes: max(0, d.light.totalMinutes - d.light.minutesBeforeNoon)))
            }
        }

        let jetlag = CircadianModel.rollingSocialJetlag(days: days, calendar: calendar)
        s.jetlag = inRange.compactMap { d in jetlag[d.day].map { ValuePoint(day: d.day, value: $0) } }

        let nights = inRange.filter { $0.night != nil }.suffix(range.rawValue)
        s.onsetSD = ClockMath.circularStandardDeviation(nights.compactMap(\.onsetMinutes))
        s.wakeSD = ClockMath.circularStandardDeviation(nights.compactMap(\.wakeMinutes))

        var secondary = inRange.compactMap { d in d.secondaryValue(secondaryMetric).map { ValuePoint(day: d.day, value: $0) } }
        if secondaryMetric == .wristTemperature, let median = ClockMath.median(secondary.map(\.value)) {
            secondary = secondary.map { ValuePoint(day: $0.day, value: $0.value - median) }
        }
        s.secondary = secondary
        return s
    }
}
