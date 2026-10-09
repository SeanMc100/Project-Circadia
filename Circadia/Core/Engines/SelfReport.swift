import Foundation

/// "Your usual sleep": the core questions of the Munich ChronoType Questionnaire (MCTQ), asked in
/// phone-only onboarding. Gives a provisional baseline and social jetlag before any night is logged.
struct UsualSleep: Codable, Equatable, Sendable {
    /// Clock minutes after midnight, 0..<1440.
    var workdayOnset: Double
    var workdayWake: Double
    var freeDayOnset: Double
    var freeDayWake: Double

    /// Work days follow the targets; days off run an hour later, a common pattern.
    static func defaults(targetBedMinutes: Double, targetWakeMinutes: Double) -> UsualSleep {
        UsualSleep(workdayOnset: targetBedMinutes, workdayWake: targetWakeMinutes,
                   freeDayOnset: ClockMath.wrapPositive(targetBedMinutes + 60),
                   freeDayWake: ClockMath.wrapPositive(targetWakeMinutes + 60))
    }

    func onset(isFreeDay: Bool) -> Double { isFreeDay ? freeDayOnset : workdayOnset }
    func wake(isFreeDay: Bool) -> Double { isFreeDay ? freeDayWake : workdayWake }

    /// Mid-sleep in signed minutes (MCTQ's MSW and MSF).
    func midpoint(isFreeDay: Bool) -> Double {
        let onset = onset(isFreeDay: isFreeDay)
        let duration = ClockMath.wrapPositive(wake(isFreeDay: isFreeDay) - onset)
        return ClockMath.wrapSigned(onset + duration / 2)
    }

    /// MCTQ social jetlag: free-day minus workday mid-sleep (positive = later on days off).
    var socialJetlag: Double { ClockMath.wrapSigned(midpoint(isFreeDay: true) - midpoint(isFreeDay: false)) }

    /// Midpoints for the `count` days before `day`, standing in for nights not logged yet.
    func standInMidpoints(count: Int, before day: Date, calendar: Calendar) -> [Double] {
        guard count > 0 else { return [] }
        return (1...count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: day).map { midpoint(isFreeDay: calendar.isDateInWeekend($0)) }
        }
    }
}

/// Outdoor time the user reported. Plain value; `LightReport` is the stored record.
struct ReportedLight: Equatable, Sendable {
    let day: Date
    let start: Date
    let end: Date
    let minutes: Double

    var sample: DaylightSample { DaylightSample(start: start, end: end, minutes: minutes) }

    /// A light card checked off at `at`: the time outside is assumed to end then, or when the card's
    /// window closed if the check-off came later (from a notification, the widget, or after noon).
    static func done(day: Date, minutes: Double, at date: Date, window: DateInterval? = nil) -> ReportedLight {
        let end = window.map { min(date, $0.end) } ?? date
        return ReportedLight(day: day, start: end.adding(minutes: -minutes), end: end, minutes: minutes)
    }

    /// "Got outside within 2 h of waking": that morning's goal, starting half an hour after wake.
    static func checkInYes(day: Date, wake: Date, minutes: Double) -> ReportedLight {
        let start = wake.adding(minutes: CircadianConfig.checkInLightOffsetMinutes)
        return ReportedLight(day: day, start: start, end: start.adding(minutes: minutes), minutes: minutes)
    }

    /// A known "no": the day counts as zero rather than unknown.
    static func none(day: Date, at date: Date) -> ReportedLight {
        ReportedLight(day: day, start: date, end: date, minutes: 0)
    }

    static func doneID(_ recommendationID: String) -> String { "light-\(recommendationID)" }

    static func checkInID(day: Date, calendar: Calendar = .current) -> String {
        "light-checkin-\(ClockMath.dayKey(day, calendar: calendar))"
    }
}

/// Which nights the app should ask about. Pure, so it's unit-testable.
enum SleepLogPlanner {
    struct Asks: Equatable {
        /// Show last night's question (or, once logged, the logged row).
        var today = false
        /// Also ask about the night before, which was missed.
        var yesterday = false
        /// Wearable mode only: the last night Health has, when the watch has gone quiet.
        var gapSince: Date?
    }

    /// - Parameters:
    ///   - healthNightDays: wake days Health has a night for (logged nights excluded).
    ///   - loggedDays: wake days with a stored log entry.
    static func asks(mode: TrackingMode, activeDay: Date, phoneOnlySince: Date?, healthNightDays: Set<Date>,
                     loggedDays: Set<Date>, isSkipped: (Date) -> Bool, calendar: Calendar) -> Asks {
        let today = calendar.startOfDay(for: activeDay)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return Asks() }
        func open(_ day: Date) -> Bool {
            !healthNightDays.contains(day) && (loggedDays.contains(day) || !isSkipped(day))
        }

        switch mode {
        case .phoneOnly:
            let since = phoneOnlySince.map { calendar.startOfDay(for: $0) } ?? today
            let askYesterday = since < today && !healthNightDays.contains(yesterday)
                && !loggedDays.contains(yesterday) && !isSkipped(yesterday)
            return Asks(today: open(today), yesterday: askYesterday)
        case .wearable:
            // Only once the watch has missed both last night and the night before, and only for
            // people who have had wearable data (new users get the empty state instead).
            guard let last = healthNightDays.max(), last < yesterday else { return Asks() }
            return Asks(today: open(today), gapSince: last)
        }
    }
}

/// A "Log last night?" notification.
struct PlannedSleepReminder: Equatable, Identifiable, Sendable {
    let id: String
    let wakeDay: Date
    let fireDate: Date
    let onset: Date
    let wake: Date
}

enum SleepLogReminderPlanner {
    /// One reminder per unlogged prompt, half an hour after the guessed wake, moved to the end of
    /// quiet hours if it would land inside them. Past times are dropped.
    static func plan(_ prompts: [SleepLogPrompt], now: Date, preferences: NotificationPreferences,
                     calendar: Calendar = .current) -> [PlannedSleepReminder] {
        prompts.filter { !$0.isLogged }.compactMap { prompt in
            var fire = prompt.wake.adding(minutes: CircadianConfig.sleepLogReminderDelayMinutes)
            if NotificationPlanner.isInQuietHours(fire, preferences: preferences, calendar: calendar) {
                var end = ClockMath.date(on: fire, minutes: preferences.quietEndMinutes, calendar: calendar)
                if end <= fire { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
                fire = end
            }
            guard fire > now.addingTimeInterval(60) else { return nil }
            return PlannedSleepReminder(id: prompt.id(calendar: calendar), wakeDay: prompt.wakeDay, fireDate: fire,
                                        onset: prompt.onset, wake: prompt.wake)
        }
    }
}
