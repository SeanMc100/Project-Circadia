import Foundation

/// A night the user logged by hand. Plain value; `SleepLogEntry` is the stored record.
struct SleepLog: Equatable, Sendable {
    /// Start of the calendar day the user woke on.
    let wakeDay: Date
    let onset: Date
    let wake: Date

    /// Builds a night from two clock times (minutes after midnight). Wake falls on `wakeDay`;
    /// onset is the latest time before wake, so 11:15 PM lands on the evening before.
    static func make(wakeDay: Date, onsetClockMinutes: Double, wakeClockMinutes: Double, calendar: Calendar = .current) -> SleepLog {
        let day = calendar.startOfDay(for: wakeDay)
        let wake = ClockMath.date(on: day, minutes: ClockMath.wrapPositive(wakeClockMinutes), calendar: calendar)
        var onset = ClockMath.date(on: day, minutes: ClockMath.wrapPositive(onsetClockMinutes), calendar: calendar)
        if onset >= wake { onset = calendar.date(byAdding: .day, value: -1, to: onset) ?? onset.addingTimeInterval(-86_400) }
        return SleepLog(wakeDay: day, onset: onset, wake: wake)
    }

    var asleepMinutes: Double { wake.timeIntervalSince(onset) / 60 }

    /// Why this night can't be saved, or nil if it's fine.
    func problem(now: Date) -> String? {
        if wake > now { return "That wake time hasn't happened yet." }
        if asleepMinutes < CircadianConfig.minimumPrimarySleepMinutes {
            return "That's under \(Int(CircadianConfig.minimumPrimarySleepMinutes / 60)) hours. Circadia only tracks your main sleep, not naps."
        }
        if asleepMinutes > CircadianConfig.sleepLogMaximumMinutes {
            return "That's over \(Int(CircadianConfig.sleepLogMaximumMinutes / 60)) hours. Check the times."
        }
        return nil
    }
}

/// Feeds logged nights into the same pipeline as Health data.
enum SleepLogMerger {
    static let sourceName = "Circadia sleep log"

    /// Logs for nights Health has no sleep for. Health data always wins, so a log that overlaps
    /// any recorded sleep (asleep or in bed) is left out rather than merged with it.
    static func unrecorded(_ logs: [SleepLog], health: [SleepSample]) -> [SleepLog] {
        let recorded = health.filter { $0.stage != .awake && $0.end > $0.start }
        return logs.filter { log in
            log.wake > log.onset && !recorded.contains { $0.start < log.wake && log.onset < $0.end }
        }
    }

    static func sample(_ log: SleepLog) -> SleepSample {
        SleepSample(start: log.onset, end: log.wake, stage: .asleepUnspecified, sourceName: sourceName, isFromWatch: false)
    }

    /// Health samples plus one asleep sample per logged night Health doesn't cover.
    static func merge(health: [SleepSample], logs: [SleepLog]) -> [SleepSample] {
        health + unrecorded(logs, health: health).map(sample)
    }
}

/// The "when did you sleep?" question on Today, pre-filled with a best guess.
struct SleepLogPrompt: Equatable, Sendable {
    let wakeDay: Date
    let onset: Date
    let wake: Date
    /// True once the user has logged this night; the card then shows it with an Edit button.
    let isLogged: Bool

    var log: SleepLog { SleepLog(wakeDay: wakeDay, onset: onset, wake: wake) }

    /// "sleepLog-<yyyy-MM-dd>": shared by the reminder notification and the widget check-off, so
    /// confirming in one place cancels the other.
    func id(calendar: Calendar = .current) -> String { Self.id(wakeDay: wakeDay, calendar: calendar) }

    static func id(wakeDay: Date, calendar: Calendar = .current) -> String {
        "\(kind)-\(ClockMath.dayKey(wakeDay, calendar: calendar))"
    }

    /// The Focus widget item's kind for a sleep-log question.
    static let kind = WidgetShared.sleepLogKind
}

enum SleepLogGuess {
    /// The logged night if there is one. Otherwise the most recent night of the same kind (workday
    /// or free day) from the last two weeks, else the usual sleep answers, else the targets.
    /// Wake is never later than `now`.
    static func make(wakeDay: Date, logged: SleepLog?, days: [DayMetrics], usual: UsualSleep? = nil,
                     targetBedMinutes: Double, targetWakeMinutes: Double, now: Date,
                     calendar: Calendar = .current) -> SleepLogPrompt {
        let day = calendar.startOfDay(for: wakeDay)
        if let logged {
            return SleepLogPrompt(wakeDay: day, onset: logged.onset, wake: logged.wake, isLogged: true)
        }
        let isFree = calendar.isDateInWeekend(day)
        let since = calendar.date(byAdding: .day, value: -CircadianConfig.sleepLogGuessLookbackDays, to: day) ?? day
        let similar = days
            .filter { $0.day < day && $0.day >= since && $0.isFreeDay == isFree && $0.onsetMinutes != nil && $0.wakeMinutes != nil }
            .max { $0.day < $1.day }

        let onsetClock = similar?.onsetMinutes ?? usual?.onset(isFreeDay: isFree) ?? targetBedMinutes
        let wakeClock = similar?.wakeMinutes ?? usual?.wake(isFreeDay: isFree) ?? targetWakeMinutes
        var log = SleepLog.make(wakeDay: day, onsetClockMinutes: rounded(onsetClock), wakeClockMinutes: rounded(wakeClock), calendar: calendar)

        // Opened before the usual wake time: they're up now.
        if log.wake > now, now > day {
            let nowClock = (ClockMath.minutesFromMidnight(now, calendar: calendar) / 5).rounded(.down) * 5
            let wake = ClockMath.date(on: day, minutes: nowClock, calendar: calendar)
            var onset = log.onset
            if wake.timeIntervalSince(onset) < CircadianConfig.minimumPrimarySleepMinutes * 60 {
                onset = wake.adding(minutes: -CircadianConfig.sleepLogFallbackHours * 60)
            }
            log = SleepLog(wakeDay: day, onset: onset, wake: wake)
        }
        return SleepLogPrompt(wakeDay: day, onset: log.onset, wake: log.wake, isLogged: false)
    }

    private static func rounded(_ minutes: Double) -> Double {
        (minutes / CircadianConfig.sleepLogRoundingMinutes).rounded() * CircadianConfig.sleepLogRoundingMinutes
    }
}
