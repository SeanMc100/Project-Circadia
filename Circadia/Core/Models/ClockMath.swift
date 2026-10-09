import Foundation

/// Helpers for working with clock times expressed as minutes relative to local midnight.
///
/// Times that can fall on either side of midnight (sleep onset, sleep midpoint) are expressed as
/// *signed* minutes in [-720, 720): 23:15 → -45, 03:30 → 210. Lists of such values are
/// "unwrapped" around their circular mean before taking medians or standard deviations, so a
/// mix of 23:50 and 00:10 is treated as 20 minutes apart, not 23 hours 40 minutes.
enum ClockMath {
    static let minutesPerDay: Double = 1440

    /// Wall-clock minutes since local midnight, in [0, 1440).
    static func minutesFromMidnight(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// Wall-clock minutes relative to local midnight, in [-720, 720).
    static func signedMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        wrapSigned(minutesFromMidnight(date, calendar: calendar))
    }

    static func wrapSigned(_ minutes: Double) -> Double {
        var v = minutes.truncatingRemainder(dividingBy: minutesPerDay)
        if v >= 720 { v -= minutesPerDay }
        if v < -720 { v += minutesPerDay }
        return v
    }

    static func wrapPositive(_ minutes: Double) -> Double {
        var v = minutes.truncatingRemainder(dividingBy: minutesPerDay)
        if v < 0 { v += minutesPerDay }
        return v
    }

    /// Circular mean of clock times, returned as signed minutes.
    static func circularMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var s = 0.0, c = 0.0
        for v in values {
            let angle = v / minutesPerDay * 2 * .pi
            s += sin(angle)
            c += cos(angle)
        }
        guard abs(s) > 1e-9 || abs(c) > 1e-9 else { return values.first.map(wrapSigned) }
        return wrapSigned(atan2(s, c) / (2 * .pi) * minutesPerDay)
    }

    /// Re-express each value within ±12 h of `reference`.
    static func unwrap(_ values: [Double], around reference: Double) -> [Double] {
        values.map { reference + wrapSigned($0 - reference) }
    }

    /// Re-express values within ±12 h of their circular mean.
    static func unwrap(_ values: [Double]) -> [Double] {
        guard let mean = circularMean(values) else { return values }
        return unwrap(values, around: mean)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n − 1). Requires at least two values.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// Median of clock times that may straddle midnight, returned as signed minutes.
    static func circularMedian(_ values: [Double]) -> Double? {
        median(unwrap(values)).map(wrapSigned)
    }

    /// Standard deviation of clock times that may straddle midnight.
    static func circularStandardDeviation(_ values: [Double]) -> Double? {
        standardDeviation(unwrap(values))
    }

    /// The date at `minutes` after the start of `day` (minutes may be negative or exceed 1440).
    static func date(on day: Date, minutes: Double, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(minutes * 60)
    }

    // MARK: - Days

    /// The day `date` belongs to. Days roll over at `CircadianConfig.dayRolloverHour`, so 1 AM is
    /// still the previous evening.
    static func activeDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-Double(CircadianConfig.dayRolloverHour) * 3600))
    }

    /// Bedtime as minutes from the start of its evening's day: a bedtime before noon falls after
    /// midnight, so it belongs to the following calendar day.
    static func bedtimeMinutes(_ targetBedMinutes: Double) -> Double {
        targetBedMinutes < 720 ? targetBedMinutes + 1440 : targetBedMinutes
    }

    /// "yyyy-MM-dd" for `day`: the per-day part of stored ids and keys.
    static func dayKey(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Formatting

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// "11:15 PM" for a clock time in minutes (any range).
    static func clockString(_ minutes: Double) -> String {
        let m = Int(wrapPositive(minutes).rounded()) % Int(minutesPerDay)
        let reference = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: m / 60, minute: m % 60)) ?? Date()
        return timeFormatter.string(from: reference)
    }

    static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "1h 20m", "45 min".
    static func durationString(_ minutes: Double) -> String {
        let total = Int(abs(minutes).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "25 min later", "1h 10m earlier", "on time".
    static func shiftDescription(_ minutes: Double) -> String {
        if abs(minutes) < 1 { return "right on baseline" }
        return "\(durationString(minutes)) \(minutes > 0 ? "later" : "earlier")"
    }

    /// Round clock minutes to the nearest multiple of `step`.
    static func rounded(_ minutes: Double, to step: Double) -> Double {
        (minutes / step).rounded() * step
    }
}

extension Date {
    func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
}
