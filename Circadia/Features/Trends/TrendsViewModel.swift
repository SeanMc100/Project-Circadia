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
        case week = 7, month = 30, quarter = 90, halfYear = 180, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .halfYear: "6m"
            case .year: "1y"
            default: "\(rawValue)d"
            }
        }
    }

    /// Best/worst stretches of the score, with the main reason for each.
    struct ScoreExtremes {
        struct Stretch {
            let period: ScorePeriod
            let reason: String?
        }
        let best: Stretch
        let worst: Stretch
    }

    struct ScoreSeries {
        var daily: [ScorePoint] = []
        var smoothed: [ValuePoint] = []
        /// Smoothed score at the start and end of the range.
        var start: ValuePoint?
        var end: ValuePoint?
        var extremes: ScoreExtremes?

        var change: Double? {
            guard let start, let end, start.day < end.day else { return nil }
            return end.value - start.value
        }
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
        /// Each morning's light goal (it changes with the sky).
        var lightGoals: [ValuePoint] = []
        var jetlag: [ValuePoint] = []
        var secondary: [ValuePoint] = []
        var onsetSD: Double?
        var wakeSD: Double?
        var hasLightData = false
        var startDay: Date = .now
        var endDay: Date = .now
    }

    func scoreSeries(from history: [ScorePoint], weights: ScoreWeights, calendar: Calendar = .current) -> ScoreSeries {
        var s = ScoreSeries()
        guard let last = history.last?.day,
              let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: last) else { return s }
        // Smooth over the full history so the first days in range still have a full window.
        let smoothed = ScoreTrends.smoothed(history, calendar: calendar)
        s.daily = history.filter { $0.day >= start }
        s.smoothed = smoothed.filter { $0.day >= start }
        s.start = s.smoothed.first
        s.end = s.smoothed.last

        // Best/worst stretches only mean something over a longer range.
        if range.rawValue >= Range.month.rawValue,
           let typical = ScoreTrends.period(s.daily, from: start, to: last),
           let ext = ScoreTrends.extremes(s.daily, calendar: calendar) {
            func stretch(_ p: ScorePeriod) -> ScoreExtremes.Stretch {
                .init(period: p, reason: ScoreTrends.mainReason(for: p, versus: typical, weights: weights)?.text)
            }
            s.extremes = ScoreExtremes(best: stretch(ext.best), worst: stretch(ext.worst))
        }
        return s
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
                s.lightGoals.append(ValuePoint(day: d.day, value: d.lightGoalMinutes))
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
