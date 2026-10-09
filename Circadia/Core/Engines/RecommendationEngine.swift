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
    /// This morning's light goal, as stored for the day. Nil falls back to the current sky.
    var morningGoal: MorningLightGoal?
    var travel: TravelState?
    var socialJetlagMinutes: Double?
    /// Last night's midpoint minus baseline.
    var todayDriftMinutes: Double?
    var alignmentScore: Int?
    var streakDays: Int = 0
    var caffeineCutoffHours: Double = CircadianConfig.defaultCaffeineCutoffHours
    /// Kinds the user already completed or skipped today.
    var completedKinds: Set<RecommendationKind> = []
    /// The user's habit choices; habits that are missing or "not for me" produce no cards.
    var habits: [HabitKey: HabitStatus] = HabitCatalog.legacyDefaults

    /// The day recommendations belong to (rolls over at 4 AM, so 1 AM is still "yesterday evening").
    var activeDay: Date { ClockMath.activeDay(for: now, calendar: calendar) }

    func time(_ minutes: Double) -> Date { ClockMath.date(on: activeDay, minutes: minutes, calendar: calendar) }

    /// Tonight's target bedtime (a bedtime before noon belongs to the following calendar day).
    var bedtime: Date { time(ClockMath.bedtimeMinutes(targetBedMinutes)) }

    var lightGoal: MorningLightGoal { morningGoal ?? MorningLightGoal(sky: sunWeather?.sky ?? .unknown) }

    func isActive(_ habit: HabitKey) -> Bool { habits[habit]?.isActive ?? false }

    var timing: HabitTiming {
        HabitTiming(wakeMinutes: targetWakeMinutes, bedMinutes: targetBedMinutes, caffeineCutoffHours: caffeineCutoffHours)
    }

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
        id(kind, day: ctx.activeDay, calendar: ctx.calendar)
    }

    static func id(_ kind: RecommendationKind, day: Date, calendar: Calendar) -> String {
        "\(kind.rawValue)-\(ClockMath.dayKey(day, calendar: calendar))"
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
        guard ctx.isActive(.morningLight) else { return nil }
        if ctx.travelIsActive && ctx.travel?.direction == .west { return nil } // westward plan says avoid early light
        let goal = ctx.lightGoal
        let alreadyOutside = ctx.hasDaylightData ? MorningLightGoal.credited(ctx.light.minutesBeforeNoon) : 0
        if ctx.hasDaylightData && alreadyOutside >= goal.minutes { return nil }

        let window = morningWindow(ctx)
        let sky = goal.sky
        // What's left to do; success is judged on the whole goal, so earlier minutes aren't counted twice.
        let minutes = roundToFive(goal.minutes - alreadyOutside)
        let isOpen = ctx.now >= window.start

        // Up before sunrise: bright indoor light (or a light box) now, outdoors once it's light.
        let wake = ctx.wakeToday ?? ctx.time(ctx.targetWakeMinutes)
        let darkWake = window.start.timeIntervalSince(wake) / 60 >= CircadianConfig.preSunriseWakeMinutes
        if darkWake && !isOpen {
            return Recommendation(
                id: id(.morningLight, ctx), kind: .morningLight,
                title: "Up before sunrise: turn the lights up bright",
                body: "Sunrise is at \(ClockMath.timeString(window.start)). Bright indoor light now gives your clock an early signal, and a 10,000-lux light box for about 30 minutes is a stronger option. Then get outside for about \(Int(minutes)) minutes once it's light, before \(ClockMath.timeString(window.end)). If you have an eye condition or bipolar disorder, check with a doctor before using a light box.",
                window: window,
                urgency: ctx.now >= wake ? .now : .soon,
                mechanismKey: .phaseResponse,
                successCriteria: .outdoorLight(minutes: goal.minutes, within: window),
                visibleFrom: wake.adding(minutes: -CircadianConfig.morningLightLeadMinutes),
                nudgeDate: wake,
                nudgeTitle: "Bright light first, then outside",
                nudgeBody: "Turn the lights up now. " + goal.sentence
            )
        }

        var parts: [String] = []
        switch sky {
        case .clear: parts.append("Skies are clear, so \(Int(goal.minutes)) minutes does it today.")
        case .partlyCloudy: parts.append("It's partly cloudy, so today's goal is \(Int(goal.minutes)) minutes.")
        case .overcast: parts.append("It's overcast, so today's goal is a longer \(Int(goal.minutes)) minutes.")
        case .unknown: parts.append("Cloud cover is unknown, so today's goal is \(Int(goal.minutes)) minutes.")
        }
        if alreadyOutside > 0 { parts.append("You've had about \(Int(alreadyOutside)) so far.") }
        parts.append("Window until \(ClockMath.timeString(window.end)).")
        if !ctx.hasDaylightData {
            parts.append("Tap Done when you're back.")
        }

        return Recommendation(
            id: id(.morningLight, ctx), kind: .morningLight,
            title: isOpen ? "Go outside now for about \(Int(minutes)) minutes"
                          : "Morning light window opens at \(ClockMath.timeString(window.start))",
            body: parts.joined(separator: " "),
            window: window,
            urgency: isOpen ? .now : .soon,
            mechanismKey: .lightAndSCN,
            successCriteria: .outdoorLight(minutes: goal.minutes, within: window),
            visibleFrom: window.start.adding(minutes: -CircadianConfig.morningLightLeadMinutes),
            nudgeDate: window.start,
            nudgeTitle: "Time for morning light",
            nudgeBody: goal.sentence
        )
    }

    // MARK: - 2. Anchor wake time

    static func anchorWake(_ ctx: CircadianContext) -> Recommendation? {
        guard ctx.isActive(.consistentWake) else { return nil }
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
            body = "Weekend sleep runs about \(ClockMath.durationString(jetlag)) later than weekdays. Be up by \(ClockMath.timeString(latestWake)) tomorrow and get outside soon after."
        } else {
            body = "Last night ran about \(ClockMath.durationString(drift)) later than your baseline. Wake near \(ClockMath.timeString(targetWake)) tomorrow and get morning light."
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
        let active = HabitCatalog.eveningHabits.filter(ctx.isActive)
        guard !active.isEmpty else { return nil }
        let dims = active.contains(.eveningDim)
        let bed = ctx.bedtime
        let start = bed.adding(minutes: -CircadianConfig.windDownLeadMinutes)
        let started = ctx.now >= start
        let title: String
        if started {
            title = dims ? "Start dimming the lights" : "Tonight's wind-down"
        } else {
            title = "Wind-down starts at \(ClockMath.timeString(start))"
        }
        let body = dims
            ? "Switch overhead lights off, use warm low lamps and dim your screens before your \(ClockMath.timeString(bed)) bedtime."
            : "Your evening habits before your \(ClockMath.timeString(bed)) bedtime."
        return Recommendation(
            id: id(.windDown, ctx), kind: .windDown,
            title: title,
            body: body,
            window: DateInterval(start: start, end: bed),
            urgency: started ? .now : .soon,
            mechanismKey: .eveningLight,
            successCriteria: dims ? .lightsDimmed(by: start.adding(minutes: 30)) : .eveningPlan(bedtime: bed),
            visibleFrom: start.adding(minutes: -CircadianConfig.windDownShowAheadMinutes),
            steps: active.compactMap { $0.eveningStep(ctx.timing) },
            nudgeDate: start
        )
    }

    // MARK: - 4. Caffeine cutoff

    static func caffeineCutoff(_ ctx: CircadianContext) -> Recommendation? {
        guard ctx.isActive(.caffeineCutoff) else { return nil }
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
            body: "That leaves about \(hoursText) hours before your \(ClockMath.timeString(bed)) bedtime. You can adjust the cutoff in Settings.",
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
        guard ctx.isActive(.morningLight) else { return nil }
        let missed: Bool
        if ctx.hasDaylightData {
            missed = MorningLightGoal.credited(ctx.light.minutesBeforeNoon) < ctx.lightGoal.minutes * CircadianConfig.missedMorningLightFraction
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
            body: "You missed morning light. About \(Int(CircadianConfig.lateDayLightMinutes)) minutes outside before \(ClockMath.timeString(end)) is a weaker substitute, but it still helps.",
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

        let body = "Today: get outdoor light \(ClockMath.timeString(seek.start))–\(ClockMath.timeString(seek.end)), \(avoidText), and \(shiftText)."

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
            body: "Your timing is steady and close to your baseline. Keep your wake time and morning light as they are.",
            window: nil,
            urgency: .info,
            mechanismKey: .consistency,
            successCriteria: .keepRoutine,
            visibleFrom: ctx.activeDay
        )
    }
}
