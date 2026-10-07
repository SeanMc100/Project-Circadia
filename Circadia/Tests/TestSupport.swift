import Foundation
@testable import Circadia

/// Fixed calendar so tests are independent of the machine's time zone and locale.
enum TestCal {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date { date(y, m, d) }
}

extension SleepSample {
    static func watch(_ start: Date, _ end: Date, _ stage: SleepStage = .asleepCore) -> SleepSample {
        SleepSample(start: start, end: end, stage: stage, sourceName: "Apple Watch", isFromWatch: true)
    }

    static func phone(_ start: Date, _ end: Date, _ stage: SleepStage = .asleepUnspecified) -> SleepSample {
        SleepSample(start: start, end: end, stage: stage, sourceName: "iPhone", isFromWatch: false)
    }
}

/// Builds a DayMetrics with only sleep timing filled in (minutes are signed, relative to midnight).
func makeDay(_ day: Date, onset: Double, wake: Double, light: DaylightSummary = .empty, hasLight: Bool = false,
             calendar: Calendar = TestCal.calendar) -> DayMetrics {
    let onsetDate = ClockMath.date(on: day, minutes: onset, calendar: calendar)
    let wakeDate = ClockMath.date(on: day, minutes: wake, calendar: calendar)
    let session = SleepSession(onset: onsetDate, wake: wakeDate, asleepMinutes: wake - onset, isFromWatch: true,
                               isInBedOnly: false, intervals: [DateInterval(start: onsetDate, end: wakeDate)])
    return DayMetrics(day: day, isFreeDay: calendar.isDateInWeekend(day),
                      night: NightRecord(wakeDay: day, primary: session, naps: []),
                      light: light, hasLightData: hasLight,
                      onsetMinutes: ClockMath.wrapSigned(onset), wakeMinutes: ClockMath.wrapSigned(wake),
                      midpointMinutes: ClockMath.wrapSigned((onset + wake) / 2))
}
