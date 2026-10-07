import Foundation

/// Everything the recommendation engine needs to decide what to suggest. Plain values only.
struct CircadianContext {
    var now: Date
    var calendar: Calendar = .current
    /// Actual wake time this morning, if last night's sleep has been recorded.
    var wakeToday: Date?
    /// User targets, minutes after midnight (0..<1440). Bedtimes before noon are treated as after midnight.
    var targetWakeMinutes: Double
    var targetBedMinutes: Double
    var baselineMidpointMinutes: Double?
    /// Outdoor light so far today.
    var light: DaylightSummary = .empty
    /// Whether the user has any daylight data source (Apple Watch). If false, light can't be auto-detected.
    var hasDaylightData: Bool
    var sunWeather: SunWeatherSnapshot?
    var travel: TravelState?
    var socialJetlagMinutes: Double?
    /// Last night's midpoint minus baseline.
    var todayDriftMinutes: Double?
    var alignmentScore: Int?
    var streakDays: Int = 0
    var caffeineCutoffHours: Double = CircadianConfig.defaultCaffeineCutoffHours
    /// Kinds the user already completed or skipped today.
    var completedKinds: Set<RecommendationKind> = []

    /// The day recommendations belong to (rolls over at 4 AM, so 1 AM is still "yesterday evening").
    var activeDay: Date {
        calendar.startOfDay(for: now.addingTimeInterval(-Double(CircadianConfig.dayRolloverHour) * 3600))
    }

    func time(_ minutes: Double) -> Date { ClockMath.date(on: activeDay, minutes: minutes, calendar: calendar) }

    /// Tonight's target bedtime (a bedtime before noon belongs to the following calendar day).
    var bedtime: Date { time(targetBedMinutes < 720 ? targetBedMinutes + 1440 : targetBedMinutes) }

    var travelIsActive: Bool {
        guard let travel else { return false }
        return travel.remainingHours(on: activeDay, calendar: calendar) > 0
    }
}

/// Rule-based, deterministic recommendation engine. No side effects; fully unit-testable.
enum RecommendationEngine {

    /// Recommendations that should be on screen right now, most important first.
    static func recommendations(for context: CircadianContext) -> [Recommendation] {
        rank(candidates(for: context).filter { rec in
            context.now >= rec.visibleFrom && (rec.window.map { context.now < $0.end } ?? true)
        })
    }

    /// Everything planned for the rest of the active day (including cards not yet visible).
    /// Used to schedule notifications.
    static func dailyPlan(for context: CircadianContext) -> [Recommendation] {
        rank(candidates(for: context).filter { rec in rec.window.map { context.now < $0.end } ?? true })
    }

    static func rank(_ recs: [Recommendation]) -> [Recommendation] {
        recs.sorted { ($0.urgency, $0.kind.priority) < ($1.urgency, $1.kind.priority) }
    }

    static func candidates(for ctx: CircadianContext) -> [Recommendation] {
        [travelShift(ctx), morningLight(ctx), lateDayLight(ctx), windDown(ctx),
         caffeineCutoff(ctx), anchorWake(ctx), maintenance(ctx)]
            .compactMap { $0 }
            .filter { !ctx.completedKinds.contains($0.kind) }
    }

    // MARK: - Shared helpers

    static func id(_ kind: RecommendationKind, _ ctx: CircadianContext) -> String {
        let c = ctx.calendar.dateComponents([.year, .month, .day], from: ctx.activeDay)
        return String(format: "%@-%04d-%02d-%02d", kind.rawValue, c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func lightMinutes(for sky: SkyCondition) -> Double {
        switch sky {
        case .clear: CircadianConfig.lightMinutesClear
        case .partlyCloudy: CircadianConfig.lightMinutesPartlyCloudy
        case .overcast: CircadianConfig.lightMinutesOvercast
        case .unknown: CircadianConfig.lightMinutesUnknownSky
        }
    }

    /// The post-wake light window: opens at wake (or sunrise, if later), closes ~2 h after wake.
    static func morningWindow(_ ctx: CircadianContext) -> DateInterval {
        let wake = ctx.wakeToday ?? ctx.time(ctx.targetWakeMinutes)
        var start = wake
        if let sunrise = ctx.sunWeather?.sun.sunrise, sunrise > start, ctx.calendar.isDate(sunrise, inSameDayAs: wake) {
            start = sunrise
        }
        let end = max(wake.adding(minutes: CircadianConfig.morningLightWindowMinutes),
                      start.adding(minutes: CircadianConfig.morningLightMinimumWindowMinutes))
        return DateInterval(start: start, end: end)
    }

    private static func roundToFive(_ minutes: Double) -> Double { max(5, (minutes / 5).rounded() * 5) }

    // MARK: - 1. Morning light

    static func morningLight(_ ctx: CircadianContext) -> Recommendation? {
        if ctx.travelIsActive && ctx.travel?.direction == .west { return nil } // westward plan says avoid early light
        let target = CircadianConfig.morningLightTargetMinutes
        if ctx.hasDaylightData && ctx.light.minutesBeforeNoon >= target { return nil }

        let window = morningWindow(ctx)
        let sky = ctx.sunWeather?.sky ?? .unknown
        let alreadyOutside = ctx.hasDaylightData ? ctx.light.minutesBeforeNoon : 0
        let minutes = roundToFive(lightMinutes(for: sky) - alreadyOutside)
        let isOpen = ctx.now >= window.start

        var parts: [String] = []
        if let sunrise = ctx.sunWeather?.sun.sunrise {
            parts.append("Sunrise \(ctx.now >= sunrise ? "was" : "is at") \(ClockMath.timeString(sunrise)).")
        }
        switch sky {
        case .clear: parts.append("Skies are clear, so a shorter stretch does the job.")
        case .partlyCloudy: parts.append("It's partly cloudy.")
        case .overcast: parts.append("It's overcast. Outdoor light is still far brighter than indoor lighting; it just takes a bit longer.")
        case .unknown: parts.append("Cloud cover is unknown, so this assumes average conditions.")
        }
        if ctx.sunWeather?.weather?.isPrecipitating == true {
            parts.append("If it's raining, a covered porch or an open doorway still counts.")
        }
        parts.append("You have a window until \(ClockMath.timeString(window.end)).")
        if alreadyOutside >= 1 {
            parts.append("You've logged \(Int(alreadyOutside.rounded())) min outdoors so far.")
        }
        if !ctx.hasDaylightData {
            parts.append("Tap Done when you're back; without Apple Watch daylight data the app can't detect it automatically.")
        }

        return Recommendation(
            id: id(.morningLight, ctx), kind: .morningLight,
            title: isOpen ? "Go outside now for about \(Int(minutes)) minutes"
                          : "Morning light window opens at \(ClockMath.timeString(window.start))",
            body: parts.joined(separator: " "),
            window: window,
            urgency: isOpen ? .now : .soon,
            mechanismKey: .lightAndSCN,
            successCriteria: .outdoorLight(minutes: minutes, within: window),
            visibleFrom: window.start.adding(minutes: -CircadianConfig.morningLightLeadMinutes),
            nudgeDate: window.start
        )
    }

    // MARK: - 2. Anchor wake time

    static func anchorWake(_ ctx: CircadianContext) -> Recommendation? {
        let jetlag = ctx.socialJetlagMinutes ?? 0
        let drift = ctx.todayDriftMinutes ?? 0
        guard let tomorrow = ctx.calendar.date(byAdding: .day, value: 1, to: ctx.activeDay) else { return nil }
        let tomorrowIsFree = ctx.calendar.isDateInWeekend(tomorrow)
        let highJetlag = jetlag >= CircadianConfig.anchorWakeThresholdMinutes && tomorrowIsFree
        let lateToday = drift >= CircadianConfig.anchorWakeThresholdMinutes
        guard highJetlag || lateToday else { return nil }

        let tolerance = CircadianConfig.anchorWakeToleranceMinutes
        let targetWake = ClockMath.date(on: tomorrow, minutes: ctx.targetWakeMinutes, calendar: ctx.calendar)
        let latestWake = targetWake.adding(minutes: tolerance)
        let body: String
        if highJetlag {
            body = "Your weekend sleep runs about \(ClockMath.durationString(jetlag)) later than on weekdays. Try to be up by \(ClockMath.timeString(latestWake)) tomorrow, even after a late night, and get outside soon after. A steady wake time limits how far your clock drifts before Monday."
        } else {
            body = "Last night ran about \(ClockMath.durationString(drift)) later than your baseline. Waking near \(ClockMath.timeString(targetWake)) tomorrow and getting morning light pulls your clock back faster than sleeping in again."
        }
        let eveningStart = ctx.time(17 * 60)
        return Recommendation(
            id: id(.anchorWake, ctx), kind: .anchorWake,
            title: "Anchor tomorrow's wake time",
            body: body,
            window: DateInterval(start: targetWake.adding(minutes: -tolerance), end: latestWake),
            urgency: ctx.now >= eveningStart ? .soon : .later,
            mechanismKey: highJetlag ? .socialJetlag : .consistency,
            successCriteria: .wakeNear(targetWake, toleranceMinutes: tolerance),
            visibleFrom: highJetlag ? ctx.time(12 * 60) : ctx.activeDay
        )
    }

    // MARK: - 3. Evening wind-down

    static func windDown(_ ctx: CircadianContext) -> Recommendation? {
        let bed = ctx.bedtime
        let start = bed.adding(minutes: -CircadianConfig.windDownLeadMinutes)
        let started = ctx.now >= start
        return Recommendation(
            id: id(.windDown, ctx), kind: .windDown,
            title: started ? "Start dimming the lights" : "Wind-down starts at \(ClockMath.timeString(start))",
            body: "Your target bedtime is \(ClockMath.timeString(bed)). From \(ClockMath.timeString(start)), switch overhead lights off or down, use warm low lamps, and turn screen brightness down. This keeps evening light from pushing tonight's melatonin rise later.",
            window: DateInterval(start: start, end: bed),
            urgency: started ? .now : .soon,
            mechanismKey: .eveningLight,
            successCriteria: .lightsDimmed(by: start.adding(minutes: 30)),
            visibleFrom: start.adding(minutes: -CircadianConfig.windDownShowAheadMinutes),
            nudgeDate: start
        )
    }

    // MARK: - 4. Caffeine cutoff

    static func caffeineCutoff(_ ctx: CircadianContext) -> Recommendation? {
        let bed = ctx.bedtime
        let hours = min(max(ctx.caffeineCutoffHours, CircadianConfig.caffeineCutoffRange.lowerBound), CircadianConfig.caffeineCutoffRange.upperBound)
        let cutoff = bed.adding(minutes: -hours * 60)
        let visibleFrom = ctx.wakeToday ?? ctx.time(ctx.targetWakeMinutes)
        guard visibleFrom < cutoff else { return nil }
        let soon = ctx.now >= cutoff.adding(minutes: -CircadianConfig.caffeineSoonMinutes)
        let hoursText = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        return Recommendation(
            id: id(.caffeineCutoff, ctx), kind: .caffeineCutoff,
            title: "Last caffeine by \(ClockMath.timeString(cutoff))",
            body: "That leaves about \(hoursText) hours before your \(ClockMath.timeString(bed)) bedtime. Caffeine's effects can last many hours, and how long varies a lot between people. Adjust the cutoff in Settings if you know you're more or less sensitive.",
            window: DateInterval(start: visibleFrom, end: cutoff),
            urgency: soon ? .soon : .later,
            mechanismKey: .caffeineAdenosine,
            successCriteria: .noCaffeineAfter(cutoff),
            visibleFrom: visibleFrom,
            nudgeDate: cutoff.adding(minutes: -CircadianConfig.caffeineNudgeLeadMinutes)
        )
    }

    // MARK: - 5. Late-day light (weaker substitute)

    static func lateDayLight(_ ctx: CircadianContext) -> Recommendation? {
        if ctx.travelIsActive { return nil } // the travel plan owns light timing while shifting
        let missed: Bool
        if ctx.hasDaylightData {
            missed = ctx.light.minutesBeforeNoon < CircadianConfig.morningLightTargetMinutes * CircadianConfig.missedMorningLightFraction
        } else {
            missed = !ctx.completedKinds.contains(.morningLight)
        }
        guard missed else { return nil }

        let start = morningWindow(ctx).end
        let sunsetLimit = (ctx.sunWeather?.sun.sunset ?? ctx.time(18 * 60)).adding(minutes: -CircadianConfig.lateDayLightBeforeSunsetMinutes)
        let windDownLimit = ctx.bedtime.adding(minutes: -CircadianConfig.windDownLeadMinutes - CircadianConfig.lateDayLightBeforeWindDownMinutes)
        let end = min(sunsetLimit, windDownLimit)
        guard end > start.adding(minutes: CircadianConfig.lateDayLightMinutes) else { return nil }
        let window = DateInterval(start: start, end: end)

        return Recommendation(
            id: id(.lateDayLight, ctx), kind: .lateDayLight,
            title: "Catch some afternoon daylight",
            body: "Your morning light window passed with little outdoor time. About \(Int(CircadianConfig.lateDayLightMinutes)) minutes outside before \(ClockMath.timeString(end)) is a weaker substitute: afternoon light moves your clock less than morning light does. It still helps, and brighter days tend to make you less sensitive to light in the evening.",
            window: window,
            urgency: .soon,
            mechanismKey: .phaseResponse,
            successCriteria: .outdoorLight(minutes: CircadianConfig.lateDayLightMinutes, within: window),
            visibleFrom: start,
            nudgeDate: max(start, ctx.time(14 * 60))
        )
    }

    // MARK: - 6. Travel shift plan

    static func travelShift(_ ctx: CircadianContext) -> Recommendation? {
        guard let travel = ctx.travel, ctx.travelIsActive else { return nil }
        let cal = ctx.calendar
        let dayIndex = travel.dayIndex(on: ctx.activeDay, calendar: cal)
        let totalDays = max(travel.planDays, dayIndex)
        let hours = abs(travel.shiftHours)
        let hoursText = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        let largeEast = travel.direction == .east && hours >= CircadianConfig.travelLargeEastwardHours

        let seek: DateInterval
        let avoidText: String
        let shiftText: String
        switch travel.direction {
        case .east:
            // For big eastward jumps, very early light can land before the temperature minimum
            // and push the wrong way, so start with late-morning light for the first two days.
            seek = (largeEast && dayIndex <= 2)
                ? DateInterval(start: ctx.time(10 * 60), end: ctx.time(13 * 60))
                : DateInterval(start: ctx.time(8 * 60), end: ctx.time(11 * 60))
            avoidText = "keep evenings dim after \(ClockMath.timeString(ctx.time(18 * 60)))"
            shiftText = "aim for bed about an hour earlier than your body wants"
        case .west:
            seek = DateInterval(start: ctx.time(16 * 60), end: ctx.time(20 * 60))
            avoidText = "avoid bright light before \(ClockMath.timeString(ctx.time(9 * 60))) (sunglasses help outdoors)"
            shiftText = "stay up about an hour later than your body wants"
        }

        var steps: [String] = []
        for i in 1...totalDays {
            let label = i == dayIndex ? "Day \(i) (today)" : "Day \(i)"
            let early = largeEast && i <= 2
            let lightWindow: String
            switch travel.direction {
            case .east: lightWindow = early ? "late-morning light (10 AM–1 PM)" : "morning light (8–11 AM)"
            case .west: lightWindow = "late-afternoon and evening light (4–8 PM)"
            }
            steps.append("\(label): shift ~1 h \(travel.direction == .east ? "earlier" : "later"); seek \(lightWindow).")
        }

        var body = "You're about \(hoursText) h \(travel.direction == .east ? "ahead of" : "behind") home time, so your clock needs to move \(travel.direction == .east ? "earlier" : "later"). Today: get outdoor light \(ClockMath.timeString(seek.start))–\(ClockMath.timeString(seek.end)), \(avoidText), and \(shiftText)."
        if largeEast {
            body += " With a jump this large, start with late-morning rather than early-morning light for the first couple of days."
        }

        return Recommendation(
            id: id(.travelShift, ctx), kind: .travelShift,
            title: "Travel plan: shift \(travel.direction == .east ? "earlier" : "later") (day \(dayIndex) of \(totalDays))",
            body: body,
            // Visible all day (the evening half of the plan matters too); success is judged on `seek`.
            window: DateInterval(start: ctx.activeDay, end: ctx.bedtime),
            urgency: seek.contains(ctx.now) ? .now : .soon,
            mechanismKey: .travelDirection,
            successCriteria: .outdoorLight(minutes: 30, within: seek),
            visibleFrom: ctx.activeDay,
            steps: steps,
            nudgeDate: seek.start
        )
    }

    // MARK: - 7. Maintenance

    static func maintenance(_ ctx: CircadianContext) -> Recommendation? {
        guard let score = ctx.alignmentScore, score >= CircadianConfig.alignedScoreThreshold, !ctx.travelIsActive else { return nil }
        let title = ctx.streakDays >= 3 ? "\(ctx.streakDays) nights in rhythm" : "You're in rhythm"
        return Recommendation(
            id: id(.maintenance, ctx), kind: .maintenance,
            title: title,
            body: "Your timing is steady and close to your baseline. Nothing to fix today; keep your wake time and morning light as they are.",
            window: nil,
            urgency: .info,
            mechanismKey: .consistency,
            successCriteria: .keepRoutine,
            visibleFrom: ctx.activeDay
        )
    }
}
