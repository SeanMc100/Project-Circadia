import Foundation

/// What tomorrow morning's alignment estimate could be if tonight and the rest of today go to plan.
struct ScoreForecast: Equatable, Sendable {
    enum StepKind: String, Sendable {
        case morningLight, bedtime, wake

        var systemImage: String {
            switch self {
            case .morningLight: "sunrise.fill"
            case .bedtime: "moon.fill"
            case .wake: "alarm.fill"
            }
        }
    }

    struct Step: Identifiable, Equatable, Sendable {
        var id: StepKind { kind }
        let kind: StepKind
        let text: String
        /// Points this step adds compared with not doing it. The steps add up to
        /// `projected - withoutPlan`.
        let points: Int
    }

    /// Today's score.
    let current: Int
    /// Tomorrow's score if every step is followed.
    let projected: Int
    /// Tomorrow's score if tonight repeats last night's timing and there's no more outdoor light today.
    let withoutPlan: Int
    /// Biggest effect first.
    let steps: [Step]

    var change: Int { projected - current }
}

/// Simulates tonight's sleep (and the rest of today's light) to project tomorrow's score. Pure; unit-testable.
enum ScoreForecaster {
    typealias StepKind = ScoreForecast.StepKind

    /// Projects tomorrow's score for sleeping at the user's targets and meeting today's light target.
    /// Nil until there's a score to compare against.
    static func make(days: [DayMetrics], now: Date, targetBedMinutes: Double, targetWakeMinutes: Double,
                     calendar: Calendar = .current, weights: ScoreWeights = CircadianConfig.defaultWeights,
                     usual: UsualSleep? = nil) -> ScoreForecast? {
        let sorted = Array(days.sorted { $0.day < $1.day }.suffix(CircadianConfig.scoreHistorySliceDays))
        guard let currentScore = CircadianModel.snapshot(days: sorted, now: now, calendar: calendar, weights: weights, usual: usual).score else { return nil }

        let activeDay = ClockMath.activeDay(for: now, calendar: calendar)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: activeDay),
              let lastNight = sorted.last(where: { $0.day <= activeDay && $0.night != nil }),
              let lastOnset = lastNight.onsetMinutes, let lastWake = lastNight.wakeMinutes else { return nil }
        // Tomorrow's score is read in the morning, so it uses today's light.
        let readAt = ClockMath.date(on: tomorrow, minutes: 11 * 60, calendar: calendar)
        var history = sorted.filter { $0.day < tomorrow }
        let todayIndex = history.lastIndex { calendar.isDate($0.day, inSameDayAs: activeDay) }

        // Tonight: the plan vs a repeat of last night. Neither can start in the past.
        let bed = ClockMath.bedtimeMinutes(targetBedMinutes)
        let plannedOnset = max(ClockMath.date(on: activeDay, minutes: bed, calendar: calendar), now)
        let plannedWake = ClockMath.date(on: tomorrow, minutes: targetWakeMinutes, calendar: calendar)
        let usualOnset = max(ClockMath.date(on: tomorrow, minutes: lastOnset, calendar: calendar), now)
        let usualWake = ClockMath.date(on: tomorrow, minutes: lastWake, calendar: calendar)

        // Today's light: the target vs what's been logged so far.
        let todayLight = todayIndex.map { history[$0].light } ?? .empty
        let lightPlan = todayIndex.flatMap { lightPlan(today: history[$0], now: now, calendar: calendar) }

        var levers: [StepKind] = []
        if lightPlan != nil { levers.append(.morningLight) }
        levers += [.bedtime, .wake]

        func score(_ applied: Set<StepKind>) -> Double? {
            let onset = applied.contains(.bedtime) ? plannedOnset : usualOnset
            let wake = applied.contains(.wake) ? plannedWake : usualWake
            guard wake.timeIntervalSince(onset) >= CircadianConfig.minimumPrimarySleepMinutes * 60 else { return nil }
            var scenario = history
            if let todayIndex {
                let light = applied.contains(.morningLight) ? (lightPlan?.summary ?? todayLight) : todayLight
                scenario[todayIndex] = scenario[todayIndex].with(light: light)
            }
            scenario.append(.planned(day: tomorrow, onset: onset, wake: wake, hasLightData: history.last?.hasLightData ?? false,
                                     calendar: calendar))
            return CircadianModel.snapshot(days: scenario, now: readAt, calendar: calendar, weights: weights, usual: usual).score.map(rawValue)
        }

        // Each step's share of the gain, averaged over every order the steps could be added in
        // (Shapley values), so the steps add up to the total whatever order they're done in.
        var values: [Set<StepKind>: Double] = [:]
        for mask in 0..<(1 << levers.count) {
            let subset = Set(levers.indices.filter { mask & (1 << $0) != 0 }.map { levers[$0] })
            guard let v = score(subset) else { return nil }
            values[subset] = v
        }
        let n = levers.count
        var contributions: [StepKind: Double] = [:]
        for lever in levers {
            let others = levers.filter { $0 != lever }
            var total = 0.0
            for mask in 0..<(1 << others.count) {
                let subset = Set(others.indices.filter { mask & (1 << $0) != 0 }.map { others[$0] })
                let weight = Double(factorial(subset.count) * factorial(n - subset.count - 1)) / Double(factorial(n))
                total += weight * ((values[subset.union([lever])] ?? 0) - (values[subset] ?? 0))
            }
            contributions[lever] = total
        }

        let projected = Int((values[Set(levers)] ?? 0).rounded())
        let withoutPlan = Int((values[[]] ?? 0).rounded())
        let points = roundedKeepingTotal(contributions, total: projected - withoutPlan)
        let steps = levers.map { lever -> ScoreForecast.Step in
            let text: String
            switch lever {
            case .morningLight: text = lightPlan?.text ?? ""
            case .bedtime: text = plannedOnset > ClockMath.date(on: activeDay, minutes: bed, calendar: calendar)
                ? "In bed as soon as you can" : "In bed by \(ClockMath.timeString(plannedOnset))"
            case .wake: text = "Up at \(ClockMath.timeString(plannedWake))"
            }
            return ScoreForecast.Step(kind: lever, text: text, points: points[lever] ?? 0)
        }
        .enumerated()
        .sorted { ($0.element.points, -$0.offset) > ($1.element.points, -$1.offset) }
        .map(\.element)

        return ScoreForecast(current: currentScore.value, projected: projected, withoutPlan: withoutPlan, steps: steps)
    }

    /// The unrounded score (0...100) behind an `AlignmentScore`.
    static func rawValue(_ score: AlignmentScore) -> Double {
        score.components.reduce(0) { $0 + $1.weight * ($1.value ?? 0) } * 100
    }

    /// Rounds each value so the rounded values still add up to `total` (largest remainders absorb the difference).
    static func roundedKeepingTotal<K: Hashable>(_ values: [K: Double], total: Int) -> [K: Int] {
        var result = values.mapValues { Int($0.rounded()) }
        var gap = total - result.values.reduce(0, +)
        let order = values.sorted { abs($0.value) > abs($1.value) }.map(\.key)
        var i = 0
        while gap != 0, !order.isEmpty {
            result[order[i % order.count], default: 0] += gap > 0 ? 1 : -1
            gap += gap > 0 ? -1 : 1
            i += 1
        }
        return result
    }

    // MARK: - Helpers

    /// Today's light if the user meets the target, while the morning still counts. Nil when it's
    /// too late, there's no daylight data, or the target is already met.
    private static func lightPlan(today: DayMetrics, now: Date, calendar: Calendar) -> (summary: DaylightSummary, text: String)? {
        guard today.hasLightData,
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today.day), now < noon else { return nil }
        let target = today.lightGoalMinutes
        let had = today.light
        let wake = today.night?.primary.wake
        let sinceWake = wake.map { max(0, now.timeIntervalSince($0) / 60) } ?? 0
        // Going out now (or at wake) is the earliest the first light can be.
        let first = had.firstLightAfterWakeMinutes ?? sinceWake
        let planned = DaylightSummary(firstLightAfterWakeMinutes: first,
                                      minutesBeforeNoon: max(had.minutesBeforeNoon, target),
                                      totalMinutes: max(had.totalMinutes, target))
        let before = CircadianModel.morningLightScore(firstLightMinutes: had.firstLightAfterWakeMinutes,
                                                      minutesBeforeNoon: had.minutesBeforeNoon, goalMinutes: target)
        let after = CircadianModel.morningLightScore(firstLightMinutes: first, minutesBeforeNoon: planned.minutesBeforeNoon,
                                                     goalMinutes: target)
        guard after.combined - before.combined > 0.01 else { return nil }

        let remaining = max(5, ((target - MorningLightGoal.credited(had.minutesBeforeNoon)) / 5).rounded(.up) * 5)
        let fullCreditBy = wake?.adding(minutes: CircadianConfig.morningLightFullCreditMinutes)
        let text: String
        if had.firstLightAfterWakeMinutes == nil, let fullCreditBy, fullCreditBy > now {
            text = "Outside for \(Int(remaining)) min, starting by \(ClockMath.timeString(fullCreditBy))"
        } else {
            text = "Outside for \(Int(remaining)) more min before noon"
        }
        return (planned, text)
    }

    private static func factorial(_ n: Int) -> Int { n <= 1 ? 1 : (2...n).reduce(1, *) }
}

extension DayMetrics {
    /// A copy with a different light summary.
    func with(light: DaylightSummary) -> DayMetrics {
        DayMetrics(day: day, isFreeDay: isFreeDay, night: night, light: light, hasLightData: hasLightData,
                   onsetMinutes: onsetMinutes, wakeMinutes: wakeMinutes, midpointMinutes: midpointMinutes,
                   hrv: hrv, restingHeartRate: restingHeartRate, wristTemperature: wristTemperature,
                   lightGoalMinutes: lightGoalMinutes)
    }

    /// A night that hasn't happened yet, for projections.
    static func planned(day: Date, onset: Date, wake: Date, hasLightData: Bool, calendar: Calendar) -> DayMetrics {
        let session = SleepSession(onset: onset, wake: wake, asleepMinutes: wake.timeIntervalSince(onset) / 60, isFromWatch: true,
                                   isInBedOnly: false, intervals: [DateInterval(start: onset, end: wake)])
        return DayMetrics(day: day, isFreeDay: calendar.isDateInWeekend(day),
                          night: NightRecord(wakeDay: day, primary: session, naps: []),
                          light: .empty, hasLightData: hasLightData,
                          onsetMinutes: ClockMath.signedMinutes(onset, calendar: calendar),
                          wakeMinutes: ClockMath.signedMinutes(wake, calendar: calendar),
                          midpointMinutes: ClockMath.signedMinutes(session.midpoint, calendar: calendar))
    }
}
