import Foundation

/// The proxy circadian model. Pure functions only, so everything here is unit-testable.
///
/// This is an *estimate* from sleep timing and outdoor light. It does not measure circadian
/// phase (dim-light melatonin onset is the gold standard for that).
enum CircadianModel {

    // MARK: - Snapshot

    /// - Parameter usual: "Your usual sleep" answers. While fewer than `baselineMinimumNights` prior
    ///   nights exist, they stand in for the missing ones, so there's a provisional baseline (and
    ///   score) from the first logged night. They never stand in for consistency: invented nights
    ///   would look perfectly regular.
    static func snapshot(days: [DayMetrics], now: Date, calendar: Calendar = .current,
                         weights: ScoreWeights = CircadianConfig.defaultWeights, usual: UsualSleep? = nil) -> CircadianSnapshot {
        let nights = days.filter { $0.night != nil && $0.midpointMinutes != nil }.sorted { $0.day < $1.day }
        guard let latest = nights.last, let latestMidpoint = latest.midpointMinutes else { return .empty }

        let prior = Array(nights.dropLast().suffix(CircadianConfig.baselineWindowNights))
        let priorMidpoints = prior.compactMap(\.midpointMinutes)
        var baseline = prior.count >= CircadianConfig.baselineMinimumNights ? baselineMidpoint(priorMidpoints) : nil
        var isProvisional = false
        if baseline == nil, let usual {
            let missing = CircadianConfig.baselineMinimumNights - prior.count
            baseline = baselineMidpoint(priorMidpoints + usual.standInMidpoints(count: missing, before: (prior.first ?? latest).day, calendar: calendar))
            isProvisional = baseline != nil
        }
        let drift = baseline.map { ClockMath.wrapSigned(latestMidpoint - $0) }

        let recent = Array(nights.suffix(CircadianConfig.consistencyWindowNights))
        let sds = consistency(onsets: recent.compactMap(\.onsetMinutes), wakes: recent.compactMap(\.wakeMinutes))

        let jetlagStart = calendar.date(byAdding: .day, value: -CircadianConfig.socialJetlagWindowDays, to: calendar.startOfDay(for: now)) ?? now
        let jetlagNights = nights.filter { $0.day > jetlagStart }
        let jetlag = socialJetlag(jetlagNights.compactMap { d in d.midpointMinutes.map { (d.isFreeDay, $0) } })

        let light = morningLightAssessment(days: days, now: now, calendar: calendar)

        var snapshot = CircadianSnapshot(status: .ready, streakDays: 0)
        snapshot.latestNight = latest.night
        snapshot.latestMidpoint = latestMidpoint
        snapshot.baselineMidpoint = baseline
        snapshot.baselineOnset = ClockMath.circularMedian((prior + [latest]).compactMap(\.onsetMinutes))
        snapshot.baselineWake = ClockMath.circularMedian((prior + [latest]).compactMap(\.wakeMinutes))
        snapshot.drift = drift
        snapshot.onsetSD = sds?.onset
        snapshot.wakeSD = sds?.wake
        snapshot.socialJetlag = jetlag ?? usual?.socialJetlag
        snapshot.morningLight = light

        guard let baseline else {
            snapshot.status = .calibrating(have: prior.count + 1, need: CircadianConfig.baselineMinimumNights + 1)
            return snapshot
        }

        if isProvisional {
            snapshot.status = .provisional(have: prior.count + 1, need: CircadianConfig.baselineMinimumNights + 1)
        } else {
            snapshot.streakDays = streak(midpoints: nights.compactMap(\.midpointMinutes), baseline: baseline)
        }
        snapshot.score = alignment(onsetSD: sds?.onset, wakeSD: sds?.wake, nightsInConsistency: recent.count,
                                   light: light, drift: drift, weights: weights)
        return snapshot
    }

    // MARK: - Components

    /// Rolling-baseline sleep midpoint: median of the given (signed) midpoints, robust to outliers.
    static func baselineMidpoint(_ midpoints: [Double]) -> Double? {
        guard midpoints.count >= CircadianConfig.baselineMinimumNights else { return nil }
        return ClockMath.circularMedian(midpoints)
    }

    /// Standard deviation of onset and wake times (minutes).
    static func consistency(onsets: [Double], wakes: [Double]) -> (onset: Double, wake: Double)? {
        guard onsets.count >= CircadianConfig.consistencyMinimumNights,
              wakes.count >= CircadianConfig.consistencyMinimumNights,
              let onsetSD = ClockMath.circularStandardDeviation(onsets),
              let wakeSD = ClockMath.circularStandardDeviation(wakes) else { return nil }
        return (onsetSD, wakeSD)
    }

    /// Mean free-day midpoint minus mean work-day midpoint (positive = later on weekends).
    static func socialJetlag(_ nights: [(isFreeDay: Bool, midpoint: Double)]) -> Double? {
        let all = ClockMath.unwrap(nights.map(\.midpoint))
        let free = zip(nights, all).filter { $0.0.isFreeDay }.map(\.1)
        let work = zip(nights, all).filter { !$0.0.isFreeDay }.map(\.1)
        let minimum = CircadianConfig.socialJetlagMinimumNightsPerGroup
        guard free.count >= minimum, work.count >= minimum,
              let freeMean = ClockMath.mean(free), let workMean = ClockMath.mean(work) else { return nil }
        return freeMean - workMean
    }

    /// Timing credit (0...1): full within 60 min of wake, linear to zero at 180 min, zero if no light.
    static func lightTimingScore(firstLightMinutes: Double?) -> Double {
        guard let firstLightMinutes else { return 0 }
        return linearScore(firstLightMinutes,
                           perfect: CircadianConfig.morningLightFullCreditMinutes,
                           zero: CircadianConfig.morningLightZeroCreditMinutes)
    }

    /// Amount credit (0...1) for outdoor minutes before noon against the morning's goal. Minutes are
    /// rounded to the nearest 5 (the Watch misses some), then the credit rises steeply and levels off
    /// at the goal (square root): the first minutes outside do the most, so half the goal earns
    /// about 70%, not 50%. Shorter light exposures give a disproportionately large share of the
    /// clock-shifting effect of longer ones (Chang et al. 2012, J Physiol).
    static func lightAmountScore(minutesBeforeNoon: Double, goalMinutes: Double) -> Double {
        guard goalMinutes > 0 else { return 1 }
        return min(1, (MorningLightGoal.credited(minutesBeforeNoon) / goalMinutes).squareRoot())
    }

    static func morningLightScore(firstLightMinutes: Double?, minutesBeforeNoon: Double,
                                  goalMinutes: Double) -> (timing: Double, amount: Double, combined: Double) {
        let timing = lightTimingScore(firstLightMinutes: firstLightMinutes)
        let amount = lightAmountScore(minutesBeforeNoon: minutesBeforeNoon, goalMinutes: goalMinutes)
        let share = CircadianConfig.morningLightTimingShare
        return (timing, amount, share * timing + (1 - share) * amount)
    }

    /// Uses today's light once the morning is over (past noon), otherwise yesterday's complete morning.
    /// Nil when that morning's light is unknown (no sensor and nothing reported).
    static func morningLightAssessment(days: [DayMetrics], now: Date, calendar: Calendar) -> MorningLightAssessment? {
        let today = calendar.startOfDay(for: now)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today) ?? now
        let useToday = now >= noon
        let targetDay = useToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        guard let metrics = days.first(where: { calendar.isDate($0.day, inSameDayAs: targetDay) }),
              metrics.hasLightData else { return nil }
        let s = morningLightScore(firstLightMinutes: metrics.light.firstLightAfterWakeMinutes,
                                  minutesBeforeNoon: metrics.light.minutesBeforeNoon, goalMinutes: metrics.lightGoalMinutes)
        return MorningLightAssessment(timingScore: s.timing, amountScore: s.amount, combined: s.combined,
                                      firstLightMinutes: metrics.light.firstLightAfterWakeMinutes,
                                      minutesBeforeNoon: metrics.light.minutesBeforeNoon,
                                      goalMinutes: metrics.lightGoalMinutes, isToday: useToday)
    }

    static func consistencyScore(sd: Double) -> Double {
        linearScore(sd, perfect: CircadianConfig.consistencyPerfectSDMinutes, zero: CircadianConfig.consistencyZeroSDMinutes)
    }

    static func driftScore(drift: Double) -> Double {
        linearScore(abs(drift), perfect: CircadianConfig.driftPerfectMinutes, zero: CircadianConfig.driftZeroMinutes)
    }

    /// Weighted alignment estimate (0...100). Weights are renormalised over available components.
    static func alignment(onsetSD: Double?, wakeSD: Double?, nightsInConsistency: Int = CircadianConfig.consistencyWindowNights,
                          light: MorningLightAssessment?, drift: Double?,
                          weights: ScoreWeights) -> AlignmentScore? {
        var consistencySD: Double?
        var consistencyDetail = "Needs a few more nights"
        if let onsetSD, let wakeSD {
            consistencySD = (onsetSD + wakeSD) / 2
            consistencyDetail = "Bedtime varies ±\(Int(onsetSD.rounded())) min, wake ±\(Int(wakeSD.rounded())) min over the last \(nightsInConsistency) nights"
        }
        let raw: [(ScoreComponentKind, Double?, String)] = [
            (.consistency, consistencySD.map(consistencyScore(sd:)), consistencyDetail),
            (.morningLight, light?.combined, light.map(lightDetail) ?? "No outdoor-light data, so this part is left out"),
            (.drift, drift.map(driftScore(drift:)), drift.map(driftDetail) ?? "Needs a baseline"),
        ]
        let available = raw.filter { $0.1 != nil }
        let totalWeight = available.reduce(0) { $0 + weights.weight(for: $1.0) }
        guard totalWeight > 0 else { return nil }
        var sum = 0.0
        let components = raw.map { kind, value, detail -> ScoreComponent in
            let w = value == nil ? 0 : weights.weight(for: kind) / totalWeight
            sum += w * (value ?? 0)
            return ScoreComponent(kind: kind, value: value, weight: w, detail: detail)
        }
        return AlignmentScore(value: Int((sum * 100).rounded()), components: components)
    }

    private static func lightDetail(_ light: MorningLightAssessment) -> String {
        let when = light.isToday ? "Today" : "Yesterday"
        let first = light.firstLightMinutes.map { "first outdoor light \(ClockMath.durationString($0)) after waking" } ?? "no outdoor light logged"
        return "\(when): \(first), \(Int(light.minutesBeforeNoon.rounded())) of \(Int(light.goalMinutes)) min before noon"
    }

    private static func driftDetail(_ drift: Double) -> String {
        if abs(drift) < 1 { return "Last night matched your baseline timing" }
        return "Last night's midpoint was \(ClockMath.durationString(drift)) \(drift > 0 ? "later" : "earlier") than your baseline"
    }

    /// Consecutive most-recent nights whose midpoint was within tolerance of baseline.
    static func streak(midpoints: [Double], baseline: Double) -> Int {
        var count = 0
        for m in midpoints.reversed() {
            guard abs(ClockMath.wrapSigned(m - baseline)) <= CircadianConfig.streakToleranceMinutes else { break }
            count += 1
        }
        return count
    }

    static func linearScore(_ value: Double, perfect: Double, zero: Double) -> Double {
        if value <= perfect { return 1 }
        if value >= zero { return 0 }
        return 1 - (value - perfect) / (zero - perfect)
    }

    // MARK: - Score history

    /// The score as it stood at the end of each past day (and as of `now` for today), using only
    /// data available by then. Past days use that day's own morning light, so a value here can
    /// differ slightly from what Today showed that morning (which used the previous morning).
    static func scoreHistory(days: [DayMetrics], now: Date, calendar: Calendar = .current,
                             weights: ScoreWeights = CircadianConfig.defaultWeights, usual: UsualSleep? = nil) -> [ScorePoint] {
        let sorted = days.sorted { $0.day < $1.day }
        var result: [ScorePoint] = []
        for (i, day) in sorted.enumerated() where day.night != nil && day.midpointMinutes != nil {
            // Older days can't affect the score, so bound the slice to keep this linear.
            let slice = Array(sorted[max(0, i - CircadianConfig.scoreHistorySliceDays + 1)...i])
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day.day) ?? day.day
            let snap = snapshot(days: slice, now: min(endOfDay, now), calendar: calendar, weights: weights, usual: usual)
            guard let score = snap.score else { continue }
            var components: [ScoreComponentKind: Double] = [:]
            for c in score.components { components[c.kind] = c.value }
            result.append(ScorePoint(day: day.day, value: score.value, components: components,
                                     consistencySD: snap.consistencySD, drift: snap.drift,
                                     lightMinutesBeforeNoon: snap.morningLight?.minutesBeforeNoon))
        }
        return result
    }

    // MARK: - Series for trends

    /// Rolling baseline for each night (from the preceding nights only).
    static func rollingBaselines(days: [DayMetrics]) -> [Date: Double] {
        let nights = days.filter { $0.midpointMinutes != nil }.sorted { $0.day < $1.day }
        var result: [Date: Double] = [:]
        for (i, night) in nights.enumerated() {
            let window = nights[max(0, i - CircadianConfig.baselineWindowNights)..<i].compactMap(\.midpointMinutes)
            if let b = baselineMidpoint(window) { result[night.day] = b }
        }
        return result
    }

    /// Social jetlag computed over the window ending on each day.
    static func rollingSocialJetlag(days: [DayMetrics], calendar: Calendar = .current) -> [Date: Double] {
        let nights = days.filter { $0.midpointMinutes != nil }.sorted { $0.day < $1.day }
        var result: [Date: Double] = [:]
        for day in days.map(\.day) {
            guard let start = calendar.date(byAdding: .day, value: -CircadianConfig.socialJetlagWindowDays, to: day) else { continue }
            let window = nights.filter { $0.day > start && $0.day <= day }
            if let j = socialJetlag(window.compactMap { d in d.midpointMinutes.map { (d.isFreeDay, $0) } }) {
                result[day] = j
            }
        }
        return result
    }
}
