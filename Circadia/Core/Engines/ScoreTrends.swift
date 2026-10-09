import Foundation

/// A stretch of days in the score history, summarised.
struct ScorePeriod: Equatable, Sendable {
    let start: Date
    let end: Date
    let average: Double
    /// Average of each component (0...1) over the days it was available.
    let components: [ScoreComponentKind: Double]
    let consistencySD: Double?
    /// Average absolute drift from baseline (minutes).
    let absDrift: Double?
    let lightMinutesBeforeNoon: Double?
}

/// Pure helpers that turn the daily score history into trends. Unit-testable.
enum ScoreTrends {

    /// Average score over the `windowDays` days ending on each scored day.
    /// Days without enough scored days in their window are skipped.
    static func smoothed(_ points: [ScorePoint], windowDays: Int = CircadianConfig.scoreTrendWindowDays,
                         calendar: Calendar = .current) -> [ValuePoint] {
        // Sliding window over the (day-sorted) points.
        var result: [ValuePoint] = []
        var lower = 0
        var sum = 0
        for (i, p) in points.enumerated() {
            sum += p.value
            let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: p.day) ?? p.day
            while points[lower].day < start {
                sum -= points[lower].value
                lower += 1
            }
            let count = i - lower + 1
            if count >= CircadianConfig.scoreTrendMinimumDays {
                result.append(ValuePoint(day: p.day, value: Double(sum) / Double(count)))
            }
        }
        return result
    }

    /// The smoothed score on (or closest before) `day`.
    static func smoothedValue(_ smoothed: [ValuePoint], onOrBefore day: Date) -> ValuePoint? {
        smoothed.last { $0.day <= day }
    }

    /// Summary of the points in `[start, end]`.
    static func period(_ points: [ScorePoint], from start: Date, to end: Date) -> ScorePeriod? {
        let inRange = points.filter { $0.day >= start && $0.day <= end }
        guard !inRange.isEmpty else { return nil }
        var components: [ScoreComponentKind: Double] = [:]
        for kind in ScoreComponentKind.allCases {
            components[kind] = ClockMath.mean(inRange.compactMap { $0.components[kind] })
        }
        return ScorePeriod(start: start, end: end,
                           average: Double(inRange.map(\.value).reduce(0, +)) / Double(inRange.count),
                           components: components,
                           consistencySD: ClockMath.mean(inRange.compactMap(\.consistencySD)),
                           absDrift: ClockMath.mean(inRange.compactMap { $0.drift.map(abs) }),
                           lightMinutesBeforeNoon: ClockMath.mean(inRange.compactMap(\.lightMinutesBeforeNoon)))
    }

    /// The best and worst `windowDays` stretches, by smoothed score.
    /// Nil when there isn't enough history for two distinct stretches.
    static func extremes(_ points: [ScorePoint], windowDays: Int = CircadianConfig.scoreTrendWindowDays,
                         calendar: Calendar = .current) -> (best: ScorePeriod, worst: ScorePeriod)? {
        // Only stretches that lie entirely within `points`.
        guard let first = points.first?.day,
              let earliestEnd = calendar.date(byAdding: .day, value: windowDays - 1, to: first) else { return nil }
        let smooth = smoothed(points, windowDays: windowDays, calendar: calendar).filter { $0.day >= earliestEnd }
        guard let best = smooth.max(by: { $0.value < $1.value }),
              let worst = smooth.min(by: { $0.value < $1.value }),
              best.value - worst.value >= 1,
              let span = calendar.dateComponents([.day], from: worst.day, to: best.day).day,
              abs(span) >= windowDays,
              let bestPeriod = period(points, endingOn: best.day, days: windowDays, calendar: calendar),
              let worstPeriod = period(points, endingOn: worst.day, days: windowDays, calendar: calendar)
        else { return nil }
        return (bestPeriod, worstPeriod)
    }

    /// The component that most explains why `period` differs from `typical`, weighted by its
    /// share of the score, with a plain-language reason.
    static func mainReason(for period: ScorePeriod, versus typical: ScorePeriod,
                           weights: ScoreWeights) -> (kind: ScoreComponentKind, text: String)? {
        let higher = period.average >= typical.average
        let candidates = ScoreComponentKind.allCases.compactMap { kind -> (ScoreComponentKind, Double)? in
            guard let a = period.components[kind], let b = typical.components[kind] else { return nil }
            let impact = (a - b) * weights.weight(for: kind)
            return (higher ? impact : -impact) > 0 ? (kind, abs(impact)) : nil
        }
        guard let kind = candidates.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        return (kind, reasonText(kind, period: period, typical: typical))
    }

    private static func reasonText(_ kind: ScoreComponentKind, period: ScorePeriod, typical: ScorePeriod) -> String {
        func m(_ v: Double) -> String { "\(Int(v.rounded())) min" }
        switch kind {
        case .consistency:
            guard let a = period.consistencySD, let b = typical.consistencySD else { return "Sleep timing consistency" }
            return "Bedtime and wake varied about ±\(m(a)) (usually ±\(m(b)))"
        case .drift:
            guard let a = period.absDrift, let b = typical.absDrift else { return "Distance from your usual timing" }
            return "Nights were \(m(a)) off your baseline on average (usually \(m(b)))"
        case .morningLight:
            guard let a = period.lightMinutesBeforeNoon, let b = typical.lightMinutesBeforeNoon else { return "Morning outdoor light" }
            return "\(m(a)) of outdoor light before noon on average (usually \(m(b)))"
        }
    }

    // MARK: - Helpers

    private static func period(_ points: [ScorePoint], endingOn day: Date, days: Int, calendar: Calendar) -> ScorePeriod? {
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: day) else { return nil }
        return period(points, from: start, to: day)
    }
}
